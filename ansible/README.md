# Ansible Playbooks

Playbooks for cluster-wide maintenance on all Pi worker nodes.

## Playbooks

| File | Purpose |
|------|---------|
| `fix-cni-flannel.yml` | Remove flannel conflist and restart k3s-agent on all workers |
| `disable-unattended-upgrades.yml` | Disable apt auto-upgrades and daily timers |
| `fix-tailscale-route.yml` | Add Tailscale CGNAT route to main routing table + persist via systemd-networkd |
| `ntp.yml` | Configure chrony NTP on all nodes |

## Running playbooks

```bash
ansible-playbook -i ansible/inventory/hosts.yml ansible/<playbook>.yml \
  -e "ansible_become_pass=<sudo_password>"
```

---

## Incident: unattended-upgrades broke Cilium L2 LoadBalancer (2026-06-09)

### Summary

`unattended-upgrades` updated `systemd` + `systemd-resolved` automatically. The upgrade restarted `systemd-resolved`, which triggered a network reconfiguration that removed the Tailscale CGNAT route (`100.64.0.0/10`) from the main routing table. Cilium lost the ability to install direct node routes → L2 LoadBalancer traffic stopped flowing → cluster nodes went NotReady after manual intervention.

### Root cause chain

1. `apt-daily-upgrade.service` ran at 06:15 on `raspberrypi4-3`
2. Upgraded: `systemd`, `systemd-resolved`, `udev`, `libsystemd0` (255.4-1ubuntu8.14 → 8.16)
3. `systemd-resolved` restarted at 06:16 — Tailscale detected it and re-synced DNS config
4. Network reconfiguration flushed the main routing table — route `100.64.0.0/10 dev tailscale0` was removed
5. Tailscale re-populated only `table 52` (policy routing), not the main table — this is expected behavior in current Tailscale versions
6. Cilium `autoDirectNodeRoutes` tries to install pod CIDR routes via Tailscale IPs in the **main table**: `ip route add 10.42.x.0/24 via 100.x.x.x` — fails with `network is unreachable` because `100.x.x.x` is not in the main table
7. Cilium L2 announcement lease holder could no longer forward SNAT traffic to Traefik pod → `curl https://traefik.mykubernetes.com` timed out
8. `networkctl reload` ran on all nodes simultaneously (Ansible handler) → brief Tailscale disruption on all nodes at once → eBPF maps stale on all Pi nodes → all Pi nodes went NotReady

### Why all nodes went NotReady

With `kubeProxyReplacement=true`, Cilium installs eBPF hooks at the socket level on the host. When Cilium crashes or the network is disrupted, these hooks remain loaded with stale maps. New TCP connections (including k3s-agent → API server) are intercepted by stale eBPF and silently dropped. `systemctl restart k3s-agent` does NOT help — the new process's connections are still intercepted. Only a full reboot clears the eBPF state.

### Diagnosis steps

```bash
# 1. Identify which node holds the L2 lease
kubectl get leases -n kube-system | grep cilium-l2

# 2. Check Cilium logs on that node for routing errors
kubectl logs <cilium-pod> -n kube-system | grep -E "Unable to install|network is unreachable"

# 3. Confirm main routing table missing Tailscale routes
ssh root@<node-ip> 'ip route show | grep "100\."'
# empty = broken

# 4. Check table 52 (Tailscale policy table) — usually has the routes
ssh root@<node-ip> 'ip route show table 52'

# 5. Find what caused the network change
ssh root@<node-ip> 'journalctl -u tailscaled --since "3 hours ago" | grep -iE "restart|dns"'
ssh root@<node-ip> 'journalctl --since "1 hour ago" | grep -iE "apt|dpkg|upgrade"'
```

### Fix applied

**1. Disable unattended-upgrades on all Pi nodes:**

```bash
ansible-playbook -i ansible/inventory/hosts.yml ansible/disable-unattended-upgrades.yml \
  -e "ansible_become_pass=<password>"
```

**2. Add Tailscale CGNAT route to main table (persistent):**

```bash
ansible-playbook -i ansible/inventory/hosts.yml ansible/fix-tailscale-route.yml \
  -e "ansible_become_pass=<password>"
```

This adds `100.64.0.0/10 dev tailscale0` to the main routing table immediately and persists it via `/etc/systemd/network/10-tailscale-route.network` so it survives any future network reconfiguration.

**3. Recover NotReady nodes:**

`systemctl restart k3s-agent` does NOT work when eBPF is stale. Only option:

```bash
ssh tadeu@<node-ip> 'sudo reboot'
```

After reboot: eBPF state is cleared → Cilium initializes cleanly → k3s-agent connects → node becomes Ready.

### Lessons learned

- **Disable unattended-upgrades on all cluster nodes** — automatic `systemd` upgrades restart network services and can break Cilium routing silently
- **Never run `networkctl reload` on all nodes simultaneously** — Ansible handlers fire in parallel; use `serial: 1` in the play or separate the handler
- **The Tailscale route in the main table is a hard dependency for Cilium** — without `100.64.0.0/10 dev tailscale0` in the main table, `autoDirectNodeRoutes` silently fails and L2 LB breaks
- **NotReady recovery = reboot, not k3s-agent restart** — stale eBPF hooks block all new connections regardless of what userspace does

### Prevention

- `disable-unattended-upgrades.yml` now deployed on all nodes
- `fix-tailscale-route.yml` persisted via systemd-networkd on all nodes
- For future Ansible playbooks that affect networking: add `serial: 1` to avoid simultaneous disruption across nodes
