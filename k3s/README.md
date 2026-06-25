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

## CoreDNS — pinned to raspberrypi4-1

K3s manages CoreDNS internally. To customize it, use `HelmChartConfig` instead of editing the Deployment directly.

**Why:** CoreDNS defaults to OCI. Pi pods query `10.43.0.10` (kube-dns ClusterIP) → Cilium translates to `10.42.0.226` (CoreDNS pod on OCI) → packet enters `tailscale0` → Tailscale drops it (no accepted subnet routes). All DNS from Pi pods times out.

**Fix:**
```bash
kubectl apply -f k3s/coredns-helmchartconfig.yaml
```

File: [`coredns-helmchartconfig.yaml`](coredns-helmchartconfig.yaml)

### Troubleshooting — CoreDNS stuck Pending after pinning

If CoreDNS stays Pending with `untolerated taint(s)`, patch tolerations directly:

```bash
kubectl patch deployment coredns -n kube-system --type=strategic -p '{
  "spec": {
    "template": {
      "spec": {
        "tolerations": [
          {"key": "node-role.kubernetes.io/control-plane", "operator": "Exists", "effect": "NoSchedule"},
          {"key": "node-role.kubernetes.io/master",        "operator": "Exists", "effect": "NoSchedule"},
          {"key": "node.kubernetes.io/not-ready",          "operator": "Exists", "effect": "NoExecute"},
          {"key": "node.kubernetes.io/unreachable",        "operator": "Exists", "effect": "NoExecute"}
        ]
      }
    }
  }
}'
```

If `topologySpreadConstraints` conflict with single-node scheduling:
```bash
kubectl patch deployment coredns -n kube-system --type=strategic -p '{"spec":{"template":{"spec":{"topologySpreadConstraints":null}}}}'
```

## metrics-server — pinned to raspberrypi4-1

**Why:** metrics-server defaults to OCI. Scrapes kubelet on each node's `InternalIP`. Pi nodes register with LAN IPs (`192.168.1.x`) — unreachable from OCI. All Pi nodes show `<unknown>` in `kubectl top nodes`.

metrics-server is a k3s **Addon** (not a HelmChart), so `HelmChartConfig` has no effect.
The Addon controller reconciles only on k3s startup — patch survives reboots, but re-apply after k3s reinstall.

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
