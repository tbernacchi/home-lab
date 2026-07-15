# K3s Configuration

K3s built-in component customization via `HelmChartConfig` CRDs.

## Root cause: Pi workers cannot reach OCI pod IPs

OCI master has no LAN IP — Pi workers reach it via Tailscale only.
Pi workers run with `--accept-routes=false` (required to fix `bpf_redirect_neigh` crash on `tailscale0`).

Without `--accept-routes`, Tailscale on Pi workers drops packets destined for OCI pod CIDR (`10.42.0.0/24`).
Any k3s component scheduled on OCI that Pi pods need to reach will be silently unreachable.

**Affected components by default:** CoreDNS, metrics-server.

**Symptom check:**
```bash
# From any Pi pod — should resolve, not timeout:
kubectl exec -n monitoring <pod> -c <container> -- nslookup kubernetes.default.svc.cluster.local

# Should show metrics for all Pi nodes, not <unknown>:
kubectl top nodes
```

---

## CoreDNS — must avoid OCI master, any Pi worker OK

**Why:** CoreDNS must never run on OCI. Pi pods query `10.43.0.10` (kube-dns ClusterIP) → Cilium translates to the CoreDNS pod IP → if that pod is on OCI, the packet enters `tailscale0` → Tailscale drops it (Pi workers run `--accept-routes=false`, no route to OCI pod CIDR). All DNS from Pi pods times out.

Previously hard-pinned to a single node (`kubernetes.io/hostname: raspberrypi4-1`) via `nodeSelector`. **This was a single point of failure** — 2026-07-14 outage: pi4-1 died, CoreDNS/metrics-server stuck `Pending` forever (nodeSelector only allows that one node — default eviction/reschedule can't save it, unlike normal deployments which just move to any Ready node within ~5min).

**Current fix:** no node pinned by name. Required anti-affinity excludes only the OCI master (`instance-20260606-1317`) by hostname; scheduler is free to place on whichever Pi worker is Ready. Node dies → default eviction (~5min) → reschedules on any other Ready Pi worker automatically.

Note: CoreDNS is a k3s **Addon**, not a live `HelmChart` (no `helmchart.helm.cattle.io` resource exists once cluster is running) — `HelmChartConfig` alone has **no effect on an already-running cluster**, only consumed by the addon controller at k3s startup. Keep it in sync for that case, but the live fix needs a direct Deployment patch:

```bash
kubectl apply -f k3s/coredns-helmchartconfig.yaml   # for next k3s startup/reinstall
kubectl patch deployment coredns -n kube-system \
  --type strategic --patch-file k3s/coredns-patch.yaml   # live cluster now
```

Files: [`coredns-helmchartconfig.yaml`](coredns-helmchartconfig.yaml), [`coredns-patch.yaml`](coredns-patch.yaml)

**Gotcha:** OCI master has **no taints** in this cluster — dropping the `control-plane:NoSchedule` toleration is not enough to keep pods off it (confirmed empty on `kubectl get node instance-20260606-1317 -o jsonpath='{.spec.taints}'`). Must exclude it explicitly via `nodeAffinity` `NotIn` hostname, or it becomes schedulable like any worker.

If `topologySpreadConstraints` conflict with scheduling:
```bash
kubectl patch deployment coredns -n kube-system --type=strategic -p '{"spec":{"template":{"spec":{"topologySpreadConstraints":null}}}}'
```

## metrics-server — same fix as CoreDNS

**Why:** metrics-server scrapes kubelet on each node's `InternalIP`. Pi nodes register with LAN IPs (`192.168.1.x`) — unreachable from OCI. If metrics-server itself runs on OCI, `kubectl top nodes` shows `<unknown>` for every Pi node.

Same history and same live fix as CoreDNS above: was pinned to `raspberrypi4-1` by name, now uses `nodeAffinity` excluding only the OCI master, free to land on any Pi worker.

metrics-server is a k3s **Addon** (not a HelmChart), so `HelmChartConfig` has no effect at all — always patch the Deployment directly. The Addon controller reconciles only on k3s startup — patch survives reboots, but re-apply after k3s reinstall.

**Fix:**
```bash
kubectl patch deployment metrics-server -n kube-system \
  --type strategic --patch-file k3s/metrics-server-patch.yaml
```

File: [`metrics-server-patch.yaml`](metrics-server-patch.yaml)

---

## Disable built-in servicelb (klipper)

K3s ships a built-in LoadBalancer controller (klipper/servicelb) that assigns all node IPs as ExternalIPs. Disable it when using Cilium L2 announcement instead.

Edit `/etc/systemd/system/k3s.service` on the control-plane node — add `--disable servicelb` alongside the existing `--disable traefik`:

```
ExecStart=/usr/local/bin/k3s \
    server \
    '--cluster-init' \
    '--disable' \
    'traefik' \
    '--disable' \
    'servicelb' \
    ...
```

Via sed (appends after `'traefik' \` line):

```bash
sudo sed -i "/'traefik' \\\\/a\\    '--disable' \\\\\n    'servicelb' \\\\" /etc/systemd/system/k3s.service
sudo systemctl daemon-reload && sudo systemctl restart k3s
```

After restart, klipper `svclb-*` pods terminate and stop assigning node IPs to LoadBalancer services.

## Useful commands

```bash
# Check CoreDNS endpoints
kubectl get endpoints kube-dns -n kube-system

# Test DNS from a pod
kubectl run dnstest --image=busybox --rm -it --restart=Never -- nslookup google.com

# Force delete stuck CoreDNS pods
kubectl delete pods -n kube-system -l k8s-app=kube-dns --force --grace-period=0

# Check CoreDNS logs
kubectl logs -n kube-system -l k8s-app=kube-dns --tail=30

# Force delete all Terminating pods (any namespace)
kubectl get pods -A | grep Terminating | while read ns name rest; do
  kubectl patch pod $name -n $ns -p '{"metadata":{"finalizers":null}}' --type=merge 2>/dev/null
  kubectl delete pod $name -n $ns --force --grace-period=0 2>/dev/null
done
```
