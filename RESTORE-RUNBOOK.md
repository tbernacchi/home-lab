# K3s Cluster Restore Runbook

Restore from raw etcd snapshot after a `reset-k3s-cluster.sh`. 
Snapshot format: `etcd-snapshot-<node>-<timestamp>`

## Prerequisites

- Snapshot file accessible on master
- Full backup tar.gz (contains `node-token` from snapshot era)
- Cilium not running (etcd restore wipes state)

---

## Step 1 — Copy snapshot to master

```bash
scp /path/to/etcd-snapshot-raspberrypi4-5-<timestamp> root@192.168.1.106:/tmp/
```

---

## Step 2 — Extract original token from full backup

```bash
# List to confirm path
tar -tzf k3s-backup-<date>.tar.gz | grep -i token

# Extract token
tar -xzf k3s-backup-<date>.tar.gz --to-stdout ./k3s-config/node-token
```

> Token must match the one used when snapshot was taken.
> After `reset-k3s-cluster.sh` a new token is generated — use the OLD one from backup.

---

## Step 3 — Stop k3s on all nodes

```bash
# On master (192.168.1.106)
k3s-killall.sh

# On each worker (105, 103)
ssh root@192.168.1.105 "systemctl stop k3s-agent"
ssh root@192.168.1.103 "systemctl stop k3s-agent"
```

---

## Step 4 — Restore etcd snapshot

```bash
k3s server \
  --cluster-reset \
  --cluster-reset-restore-path=/tmp/etcd-snapshot-raspberrypi4-5-<timestamp> \
  --token=<TOKEN-FROM-STEP-2>
```

Wait for: `Managed etcd cluster membership has been reset, restart without --cluster-reset flag now`

---

## Step 5 — Start k3s

```bash
systemctl start k3s
kubectl get nodes -w
```

---

## Step 6 — Check Cilium

```bash
kubectl -n kube-system get pods -l k8s-app=cilium
```

If pods missing or crashlooping, reinstall:

```bash
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

kubectl -n kube-system rollout restart daemonset cilium
kubectl -n kube-system get pods -l k8s-app=cilium -w
```

---

## Step 7 — Re-join workers

After `--cluster-reset`, workers must re-join with new token.

```bash
# Get new token on master
sudo cat /var/lib/rancher/k3s/server/node-token

# On each worker node, run:
sudo ./reset-and-join-node.sh \
  --version v1.33.6+k3s1 \
  --master-ip 192.168.1.106 \
  --token <NEW-TOKEN>
```

---

## Verify

```bash
kubectl get nodes
kubectl get pods --all-namespaces | grep -v Running | grep -v Completed
```

---

## Common Errors

| Error | Cause | Fix |
|-------|-------|-----|
| `address already in use :6444` | k3s still running | `k3s-killall.sh` |
| `bootstrap data already found and encrypted with different token` | Token mismatch (reset generated new token) | Pass `--token` with original token from backup tar.gz |
| Cilium pods not starting / socket refused | Cilium not installed or crashed post-restore | Re-run helm install (Step 6) |
