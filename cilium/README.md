## Upgrade

```
helm upgrade --install cilium cilium/cilium --version v1.17.5 \
  --namespace kube-system \
  --set operator.replicas=1 \
  --set ipam.operator.clusterPoolIPv4PodCIDRList=10.42.0.0/16 \
  --set ipv4NativeRoutingCIDR=10.42.0.0/16 \
  --set ipv4.enabled=true \
  --set loadBalancer.mode=dsr \
  --set routingMode=native \
  --set autoDirectNodeRoutes=true \
  --set l2announcements.enabled=true \
  --set kubeProxyReplacement=true \
  --set k8sClientRateLimit.qps=50 \
  --set k8sClientRateLimit.burst=100 \
  --set k8sServiceHost=192.168.1.106 \
  --set k8sServicePort=6443 \
  --set l2announcements.leaseDuration=3s \
  --set l2announcements.leaseRenewDeadline=1s \
  --set l2announcements.leaseRetryPeriod=200ms \
  --set ingressController.Enabled=true \
  --set enable-bgp-control-plane.enabled=true \
  --set installCRDs=true
  ```

## Enable Prometheus

```
 helm upgrade cilium cilium/cilium --version v1.17.5 \
  --namespace kube-system \
  --reuse-values \
  --set prometheus.enabled=true \
  --set prometheus.port=9962
```

https://docs.cilium.io/en/stable/observability/grafana/

## Disable IPv6

```
helm upgrade cilium cilium/cilium --version v1.17.5 \
  --namespace kube-system \
  --reuse-values \
  --set ipv6.enabled=false
```

```
kubectl -n kube-system rollout restart daemonset cilium
```

```
systemctl restart k3s
```

## Enable Gateway-API

```
helm upgrade cilium cilium/cilium --version v1.17.5 \
  --namespace kube-system \
  --reuse-values \
  --set gatewayAPI.enabled=true
```

## Troubleshooting

### Cilium DaemonSet restart breaks new TCP connections on workers (kubeProxyReplacement)

**Symptom:** after `helm upgrade` + `kubectl rollout restart ds/cilium`, some Cilium pods get stuck in `Init:CrashLoopBackOff`. Init container (`cilium-dbg config`) fails with:
```
dial tcp 192.168.1.106:6443: i/o timeout
```
Existing connections from k3s agent to API server still show `ESTABLISHED` — but new TCP connections to the API server time out.

**Cause:** with `kubeProxyReplacement=true`, Cilium installs socket-level eBPF hooks that intercept ALL new TCP connections, even from the host network namespace. When Cilium crashes or restarts, these hooks are left in a broken state. Existing keepalive connections survive because they were established before the hook broke. New connections are intercepted by stale eBPF and silently dropped — including the API server connection the init container needs to start.

**Fix:** reboot the affected worker nodes. On boot, eBPF state is cleared and Cilium initializes cleanly.
```bash
# identify which nodes have failing Cilium pods
kubectl get pod -n kube-system -l k8s-app=cilium -o wide

# reboot nodes with Init:CrashLoopBackOff
ssh root@<worker-ip> 'reboot'
```

**Prevention:** when upgrading Cilium, avoid restarting all pods simultaneously. Use `--set rollUpdatePods` or manually restart one node at a time.

---

### Force delete all Terminating pods

When nodes are NotReady for a long time, pods accumulate in `Terminating` state and block recovery. Force delete all of them:

```bash
kubectl get pods -A | grep Terminating | while read ns name rest; do
  kubectl patch pod $name -n $ns -p '{"metadata":{"finalizers":null}}' --type=merge 2>/dev/null
  kubectl delete pod $name -n $ns --force --grace-period=0 2>/dev/null
done
```

---

### Cilium config change doesn't restart pods (ConfigMap-only changes)

`helm upgrade` with settings that only change the `cilium-config` ConfigMap (e.g. `devices`, `tunnel`) does NOT automatically restart Cilium pods. Restart manually **one pod at a time** — never all at once with `rollout restart`.

```bash
# Get pod names
kubectl get pods -n kube-system -l k8s-app=cilium -o wide

# Restart one at a time — wait for Running before next
kubectl delete pod <cilium-pod> -n kube-system
kubectl get pods -n kube-system -l k8s-app=cilium -w
# repeat for each pod
```

**Why one at a time:** with `kubeProxyReplacement=true`, restarting all Cilium pods simultaneously drops networking on all nodes at once. See golden rule #11.

---

### Pods can't reach external IPs or API server (wrong Cilium device)

**Symptom:** pods get `connection timed out` to any external IP (1.1.1.1, OCI master, etc.). Host-level connectivity works fine.

**Cause:** when `--node-ip` is a Tailscale IP (100.x.x.x), Cilium auto-detects `tailscale0` as the primary device and attaches BPF programs there. `tailscale0` only routes Tailscale IPs — external traffic is dropped.

**Fix:** force Cilium to use `eth0`:

```bash
helm upgrade cilium cilium/cilium --version v1.17.5 \
  --namespace kube-system \
  --reuse-values \
  --set devices=eth0
```

Then restart Cilium pods one at a time (see above).

---

## Cilium + Tailscale (OCI master + Pi workers)

When the k3s master runs on OCI (cloud) and workers are Raspberry Pi nodes connected via Tailscale, Cilium must use **native routing mode** with Tailscale subnet routing. VXLAN over Tailscale causes masquerade issues (pods can't reach external IPs or the API server).

### Why VXLAN fails over Tailscale

With VXLAN + Tailscale, Cilium's eBPF masquerade uses `eth0`'s LAN IP (192.168.1.x) as source for pod traffic. Packets route via `tailscale0` to OCI, but OCI can't route responses back to 192.168.1.x (not in Tailscale network) → timeout.

### Architecture (native routing)

- Cilium: native routing mode, no VXLAN
- Each node advertises its pod CIDR via Tailscale
- Cilium adds host routes: `10.42.x.0/24 → Tailscale IP of that node`
- Pod-to-pod traffic goes via Tailscale directly, no masquerade
- External traffic (internet) goes via eth0/ens3 with correct SNAT

### Node pod CIDRs

| Node | Tailscale IP | Pod CIDR |
|---|---|---|
| OCI master | `<OCI_TS_IP>` | `10.42.0.0/24` |
| raspberrypi4-1 | `<TS_IP_PI1>` | `10.42.1.0/24` |
| raspberrypi4-3 | `<TS_IP_PI3>` | `10.42.2.0/24` |
| raspberrypi4-5 | `<TS_IP_PI5>` | `10.42.3.0/24` |
| raspberrypi4-4 | `<TS_IP_PI4>` | `10.42.4.0/24` |

Pod CIDRs are assigned by Cilium IPAM on first join — they don't change unless the node is deleted and rejoins.

### Step 1 — Enable IP forwarding (all nodes)

```bash
sudo sysctl -w net.ipv6.conf.all.forwarding=1
echo "net.ipv6.conf.all.forwarding=1" | sudo tee -a /etc/sysctl.d/99-k3s.conf
sudo ethtool -K eth0 rx-udp-gro-forwarding on 2>/dev/null || true  # Pi workers only
```

### Step 2 — Advertise pod CIDR via Tailscale (each node)

```bash
# OCI master
sudo tailscale up --advertise-routes=10.42.0.0/24 --accept-routes

# raspberrypi4-1
sudo tailscale up --advertise-routes=10.42.1.0/24 --accept-routes

# raspberrypi4-3
sudo tailscale up --advertise-routes=10.42.2.0/24 --accept-routes

# raspberrypi4-4
sudo tailscale up --advertise-routes=10.42.4.0/24 --accept-routes

# raspberrypi4-5
sudo tailscale up --advertise-routes=10.42.3.0/24 --accept-routes
```

### Step 3 — Approve routes in Tailscale admin

Go to admin.tailscale.com → each machine → Edit route settings → approve the subnet route.

Auto-approval logs appear as: `Update auto approved routes for node ...`

### Step 4 — Verify routes propagated

```bash
tailscale status --json | python3 -m json.tool | grep -A3 "PrimaryRoutes"
# each peer should show its 10.42.x.0/24 in PrimaryRoutes
```

### Step 5 — Upgrade Cilium to native routing

OCI master uses `ens3`, Pi workers use `eth0`. Pass both so Cilium picks the correct one per node:

```bash
helm upgrade cilium cilium/cilium --version v1.17.5 \
  --namespace kube-system \
  --reuse-values \
  --set tunnelProtocol="" \
  --set routingMode=native \
  --set ipv4NativeRoutingCIDR=10.42.0.0/16 \
  --set autoDirectNodeRoutes=true \
  --set 'devices={eth0,ens3}'
```

### Step 6 — Restart Cilium pods one at a time

```bash
kubectl get pods -n kube-system -l k8s-app=cilium -o wide
kubectl delete pod <cilium-pod> -n kube-system
# wait for Running, then next pod
```

### Verify

```bash
# Routes via Tailscale (not cilium_host) after restart
ip route show | grep 10.42

# Pod connectivity test
kubectl run nettest --image=busybox --rm -it --restart=Never -- nc -zv <OCI_TS_IP> 6443

# External connectivity
kubectl run nettest --image=busybox --rm -it --restart=Never -- wget -qO- http://1.1.1.1 --timeout=5
```

---

## Enable hubble flowVisibility

```
 helm upgrade cilium cilium/cilium --version v1.17.5 \ 
 --namespace kube-system \ 
 --reuse-values \ 
 --set hubble.flowVisibility=full 
 --set hubble.listenAddress=":4244"
```

```
cilium config view | grep "enable-gateway-api"
```

---

## OCI master + Tailscale cluster (2026-06 rebuild)

When control-plane moved from `raspberrypi4-5` (192.168.1.106) to OCI (`instance-20260606-1317`, Tailscale IP `100.95.112.47`), three issues surfaced.

### 1. `k8sServiceHost` must use Tailscale IP

`cilium-values.yaml` had `k8sServiceHost: 192.168.1.106` (old Pi master). Pi worker Cilium pods tried to reach the API server on a dead IP → `Init:CrashLoopBackOff`.

**Fix:** update to OCI Tailscale IP:
```yaml
k8sServiceHost: 100.95.112.47
k8sServicePort: 6443
```

### 2. `loadBalancer.mode: dsr` incompatible with Tailscale transport

Pi nodes use `tailscale0` as INTERNAL-IP (`--node-ip 100.x.x.x`). DSR requires IPIP encapsulation between nodes — Tailscale does not forward raw IPIP packets, so return traffic from backend pods never reached the client.

**Symptom:** `telnet 192.168.1.130 443` → `Operation timed out` (ARP worked, TCP SYN dropped).

**Fix:**
```yaml
loadBalancer:
  mode: snat
```

### 3. L2 announcements must be applied via `helm upgrade`

`l2announcements.enabled: true` in `cilium-values.yaml` only takes effect after `helm upgrade --reuse-values -f cilium-values.yaml`. The ConfigMap `cilium-config` must contain `enable-l2-announcements: "true"` — verify with:

```bash
kubectl -n kube-system get configmap cilium-config -o yaml | grep l2-announce
```

Without this, `CiliumLoadBalancerIPPool` assigns the IP but no ARP is broadcast → `No route to host`.

