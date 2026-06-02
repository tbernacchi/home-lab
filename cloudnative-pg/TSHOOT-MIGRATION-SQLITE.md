# CNPG Troubleshooting: etcd → SQLite Migration

## What happened

After migrating the K3s datastore from etcd to SQLite (kine), the `cnpg-cluster-1` replica became unresponsive and entered a crash loop. The other two replicas (`cnpg-cluster-2` on raspberrypi4-4, `cnpg-cluster-3` on raspberrypi4-3) remained healthy and the cluster stayed operational with the primary on `cnpg-cluster-3`.

---

## Root cause

### etcd vs SQLite on the master node

Under etcd, the datastore ran as a separate process with its own I/O scheduling. After migration, K3s uses **kine** — a shim that translates the etcd API to SQLite. Kine runs **inside** the k3s process and writes directly to `/var/lib/rancher/k3s/server/db/state.db` on the master's SD card.

### Slow SQL during post-migration compaction

Immediately after migration, kine performed aggressive compaction to clean up old revision history imported from the etcd snapshot:

```
Slow SQL (total time: 2.981234526s): INSERT INTO kine(...)
COMPACT deleted 997 rows from 1000 revisions in 609ms
COMPACT deleted 962 rows from 1000 revisions in 458ms
```

These heavy write transactions locked the SQLite WAL, causing all API server requests to queue up and time out.

### Resource contention on raspberrypi4-5 (master)

`cnpg-cluster-1` ran on the same node as the kine/SQLite datastore. When kine was under compaction load:

- SQLite WAL locked → API server slow to respond
- `cnpg-cluster-1` makes API calls to `10.43.0.1:443` (kubernetes ClusterIP) at startup
- API responses arrived after the pod's startup probe timeout
- Result: `i/o timeout` to API server → pod crash loop

`cnpg-cluster-2` and `cnpg-cluster-3` on worker nodes made the same API calls over the network — they experienced latency too, but their connection path didn't compete with the SQLite writes happening on the local disk, so they stayed healthy.

### Cilium eBPF stale endpoint

As a compounding factor, restarting k3s during migration left the Cilium agent on the master with stale eBPF endpoint state. This caused `no route to host` errors for pods on the master — another reason `cnpg-cluster-1` couldn't reach the API server even after compaction settled.

**Fix:** delete and recreate the Cilium pod on the master to flush the eBPF state.

---

## Fix applied

### 1. nodeAffinity to exclude master from CNPG scheduling

Added to `002-postgresql-cluster.yaml`:

```yaml
affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
        - matchExpressions:
            - key: kubernetes.io/hostname
              operator: NotIn
              values:
                - raspberrypi4-5
```

This prevents any CNPG replica from being scheduled on the master node. The master now runs only the control plane (kine, apiserver, scheduler, controller-manager) without competing workloads.

### 2. Migrate cnpg-cluster-1 off the master

Since `cnpg-cluster-1`'s PV had node affinity to `raspberrypi4-5` (local-path provisioner), simply rescheduling the pod wasn't enough. Steps taken:

```bash
# confirm cluster-1 is a replica, not primary
kubectl get cluster cnpg-cluster -n postgres -o jsonpath='{.status.currentPrimary}'
# → cnpg-cluster-3 (safe to delete cluster-1)

# apply nodeAffinity first
kubectl apply -f cloudnative-pg/002-postgresql-cluster.yaml

# delete pod and PVC — CNPG will provision new replica on a worker
kubectl delete pod cnpg-cluster-1 -n postgres
kubectl delete pvc cnpg-cluster-1 -n postgres

# restart CNPG controller to clear stuck reconciliation state
kubectl rollout restart deployment/cnpg-controller-manager -n cnpg-system
```

CNPG created `cnpg-cluster-4` on `raspberrypi4-1` and joined it as a streaming replica from the primary.

### 3. Create storage directory on new node

The CNPG custom storage class requires the storage path to exist on each node before scheduling:

```bash
ssh root@192.168.1.102 'mkdir -p /opt/local-path-provisioner/cnpg && chown -R 1000:1000 /opt/local-path-provisioner/cnpg'
```

---

## Final state

| Pod | Node | Role |
|-----|------|------|
| cnpg-cluster-2 | raspberrypi4-4 | replica |
| cnpg-cluster-3 | raspberrypi4-3 | **primary** |
| cnpg-cluster-4 | raspberrypi4-1 | replica |

Master node (raspberrypi4-5) runs no CNPG workload. Cluster healthy: 3/3 instances ready.

---

## Prevention

- Never schedule stateful workloads that make frequent API calls on the same node as the kine/SQLite datastore.
- After any K3s restart (migration, upgrade), expect a compaction burst. Monitor with:
  ```bash
  journalctl -u k3s | grep "Slow SQL"
  ```
- After Cilium pod restarts on the master, verify cross-node connectivity before assuming networking is healthy.
