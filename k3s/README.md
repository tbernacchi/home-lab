# K3s Configuration

K3s built-in component customization via `HelmChartConfig` CRDs.

## CoreDNS

K3s manages CoreDNS internally. To customize it, use `HelmChartConfig` instead of editing the Deployment directly.

### Pin CoreDNS to master node

**Permanent (auto-applied on boot):**
```bash
sudo cp coredns-helmchartconfig.yaml /var/lib/rancher/k3s/server/manifests/
```

**Manual apply:**
```bash
kubectl apply -f coredns-helmchartconfig.yaml
```

**Why:** worker nodes with Cilium instability cause CoreDNS readiness probes to fail (kubelet can't reach pod IP when Cilium endpoint is not yet created). Pinning to the master ensures DNS is always available.

**Important:** the master has TWO taints — both must be tolerated:
```
node-role.kubernetes.io/control-plane:NoSchedule
node-role.kubernetes.io/master:NoSchedule
```

Check all taints on master:
```bash
kubectl get node raspberrypi4-5 -o jsonpath='{.spec.taints}' | jq
```

### Troubleshooting — CoreDNS stuck Pending after pinning to master

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
