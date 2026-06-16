# Fix: External NodePort/LB Access Broken (redirect_neigh via Tailscale)

## Symptom

`curl https://traefik.mykubernetes.com/...` returns `000` from Mac.  
NodePort from any external (non-Kubernetes) host times out.  
From inside the cluster (Pi nodes), service access works fine.

## Root Cause

Workers are registered in k3s with their **Tailscale IPs** as `--node-ip`:

```
k3s agent --node-ip 100.73.163.8 --flannel-iface tailscale0
```

Because of this, Cilium's `autoDirectNodeRoutes` programs all cross-node pod routes via `tailscale0`:

```
10.42.4.0/24 dev tailscale0   # route to raspberrypi4-4 pod CIDR
10.42.3.0/24 dev tailscale0   # route to raspberrypi4-3 pod CIDR
...
```

When `cil_from_netdev` (TC BPF hook on eth0) handles a NodePort/LB SYN from an external host, it does:
1. DNAT: `192.168.1.130:443` → `10.42.4.245:443` (Traefik pod on raspberrypi4-4)
2. Calls `bpf_redirect_neigh()` to forward via the next hop

`bpf_redirect_neigh()` requires an **L2 neighbor entry** (ARP) for the next hop.  
Tailscale/WireGuard has **no L2 neighbors** (`ip neigh show dev tailscale0` is empty).  
`bpf_redirect_neigh()` fails → packet is **silently dropped**, no Cilium drop counter incremented.

### Why pods-to-pods works

Pod-to-pod traffic uses `cil_from_lxc`/`cil_to_lxc` (veth pair hooks), not `cil_from_netdev`.  
Cilium also SNATs pod traffic to the node's Tailscale IP before it exits via Tailscale.  
These paths don't use `bpf_redirect_neigh()` on a WireGuard interface.

### Why Cilium nodes (e.g., Pi-5) can access the service

When a Cilium node accesses a service IP (e.g., `192.168.1.130:443`), its local `cil_to_netdev`
BPF performs DNAT **before the packet leaves the node**. No cross-node `redirect_neigh` needed.
Passes directly to Traefik via Tailscale using the node's own Tailscale IP as source → works.

## Node IP Map

| Node            | Tailscale IP    | LAN IP (eth0)   |
|-----------------|-----------------|-----------------|
| raspberrypi4-1  | 100.73.163.8    | 192.168.1.102   |
| raspberrypi4-3  | 100.64.99.68    | 192.168.1.103   |
| raspberrypi4-4  | 100.111.45.83   | 192.168.1.105   |
| raspberrypi4-5  | 100.77.224.110  | 192.168.1.106   |

## Fix

Change `--node-ip` on every Pi worker from Tailscale IP → LAN IP.  
This makes Cilium set up pod routes via LAN on eth0 → `bpf_redirect_neigh()` finds ARP entries → works.

`k8sServiceHost` in `cilium-values.yaml` remains `100.95.112.47` (OCI Tailscale) — separate concern.

### Step 1 — Edit k3s-agent service on each Pi worker

Run on **each** Pi (via Tailscale SSH or LAN SSH):

```bash
# raspberrypi4-1 (SSH: 192.168.1.102 or 100.73.163.8)
sudo sed -i 's/--node-ip 100.73.163.8/--node-ip 192.168.1.102/' /etc/systemd/system/k3s-agent.service
sudo systemctl daemon-reload

# raspberrypi4-3 (SSH: 192.168.1.103 or 100.64.99.68)
sudo sed -i 's/--node-ip 100.64.99.68/--node-ip 192.168.1.103/' /etc/systemd/system/k3s-agent.service
sudo systemctl daemon-reload

# raspberrypi4-4 (SSH: 192.168.1.105 or 100.111.45.83)
sudo sed -i 's/--node-ip 100.111.45.83/--node-ip 192.168.1.105/' /etc/systemd/system/k3s-agent.service
sudo systemctl daemon-reload

# raspberrypi4-5 (SSH: 192.168.1.106 or 100.77.224.110)
sudo sed -i 's/--node-ip 100.77.224.110/--node-ip 192.168.1.106/' /etc/systemd/system/k3s-agent.service
sudo systemctl daemon-reload
```

### Step 2 — Restart k3s-agent ONE NODE AT A TIME

Do NOT restart all nodes simultaneously. Wait for each node to be Ready before proceeding.

```bash
# On each Pi (sequentially):
sudo systemctl restart k3s-agent

# From Mac, wait for Ready:
kubectl get nodes -w
```

### Step 3 — Delete Cilium pod on the restarted node

After each node restarts k3s-agent, the node's INTERNAL-IP changes.
Cilium will detect the change, but delete its pod to force clean BPF re-init:

```bash
# Replace <cilium-pod> with the pod on the restarted node
kubectl delete pod <cilium-pod> -n kube-system
# Wait for it to become Running (0 restarts)
kubectl get pod <cilium-pod> -n kube-system -w
```

### Step 4 — Verify routes after each node

After Cilium reinitializes on the node, check that pod routes now go via eth0 LAN IPs:

```bash
kubectl exec -n kube-system <cilium-pod> -- ip route show table 52
# Expected: 10.42.X.0/24 via 192.168.1.X dev eth0   (NOT tailscale0)
```

### Step 5 — Verify external access

```bash
curl -sk --connect-timeout 5 https://traefik.mykubernetes.com/dashboard/ -o /dev/null -w "http=%{http_code}\n"
# Expected: http=200 (or 301/302)
```

## Pitfall: Tailscale Subnet Route Breaks LAN After Fix

After changing `--node-ip` to LAN IPs, if any Pi node has Tailscale **accept-routes=true** and Pi-5 is advertising `192.168.1.0/24` as a subnet route, Tailscale injects `192.168.1.0/24 dev tailscale0` into the kernel routing table. Cilium picks this up into table 52 (priority 5270, beats main table at 32766) → all LAN TCP responses route via tailscale0 → TCP handshake breaks → SSH and all LAN services time out.

**Symptoms:** SSH to Pi nodes times out on LAN AND Tailscale SSH returns "connection refused".

**Fix:**
```bash
# 1. Remove the route from table 52 immediately via cilium exec (restores SSH)
kubectl exec <cilium-pod> -n kube-system -- ip route del 192.168.1.0/24 table 52

# 2. Permanently disable accept-routes on all Pi workers
ansible-playbook -i ansible/inventory/hosts.yml ansible/fix-tailscale-accept-routes.yml -e "ansible_become_pass=<pass>"

# 3. Restart Cilium pods one at a time (30s between) to re-sync table 52
for node in raspberrypi4-1 raspberrypi4-3 raspberrypi4-4 raspberrypi4-5; do
  pod=$(kubectl get pod -n kube-system -l k8s-app=cilium --field-selector spec.nodeName=$node -o jsonpath='{.items[0].metadata.name}')
  kubectl delete pod $pod -n kube-system
  kubectl wait pod -n kube-system -l k8s-app=cilium --field-selector spec.nodeName=$node --for=condition=Ready --timeout=120s
  sleep 30
done
```

**Expected table 52 after fix** (no 192.168.1.0/24, pod CIDRs in main table via eth0):
```
10.42.x.0/24 via 192.168.1.x dev eth0    ← Pi workers (LAN)
10.42.0.0/24 via 100.95.112.47 dev tailscale0  ← OCI master (Tailscale only)
```

## Rollback

Revert `--node-ip` to Tailscale IPs and restart k3s-agent. Cilium may need pod restart per node.

## Notes

- The `--flannel-iface tailscale0` flag in the service is harmless (Flannel is not the CNI), but can be removed.
- After fix, `kubectl get nodes -o wide` will show LAN IPs as INTERNAL-IP instead of Tailscale IPs.
- Tailscale is still used for: control-plane (API server), SSH fallback, Cilium pod-to-pod (existing behavior won't change immediately — autoDirectNodeRoutes will switch to eth0 routes as Cilium reprograms them).
- If after the fix cross-node pod traffic breaks, check that LAN IPs are reachable between nodes (they should be — same /24 subnet).
