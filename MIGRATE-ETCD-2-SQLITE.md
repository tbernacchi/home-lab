# Migrate K3s: etcd → SQLite

## Why

The master node (raspberrypi4-5) runs etcd on an SD card. etcd's aggressive fsync and random I/O pattern causes timeouts under load (apiserver handler timeouts, kubelet unreachable). The cluster has 1 master + 3 workers — no HA benefit from etcd. SQLite with WAL mode is sequential-write friendly and well-suited for single-server K3s on SD card.

## How it works

K3s uses [kine](https://github.com/k3s-io/kine) as a shim that translates the etcd API to SQLite. When `--cluster-init` is absent from the K3s server flags and no `etcd/` directory exists, K3s automatically starts kine backed by `/var/lib/rancher/k3s/server/db/state.db`.

The migration tool (`etcd-2-sqlite/`) converts an etcd snapshot to a kine-compatible `state.db`, so the cluster state (all Kubernetes objects) is preserved across the datastore switch.

---

## Migration completed: 2026-06-01

**Cluster:** raspberrypi4-5 (master, 192.168.1.106) + 3 workers  
**K3s version:** v1.35.5+k3s1  
**etcd version:** v3.6.7-k3s1  
**Downtime:** ~30 seconds (k3s restart on master only; workloads on workers kept running)

---

## Steps

### 1. Take a fresh etcd snapshot

```bash
ssh root@192.168.1.106 'k3s etcd-snapshot save --name pre-sqlite-$(date +%Y%m%d-%H%M%S)'
```

### 2. Copy snapshot to your machine

```bash
scp root@192.168.1.106:/var/lib/rancher/k3s/server/db/snapshots/pre-sqlite-* ./
```

### 3. Install etcd binaries (needed for conversion)

The conversion tool requires `etcd`, `etcdctl`, `etcdutl` matching the K3s-bundled etcd version.

```bash
# macOS ARM64 — adjust version to match 'k3s etcd-snapshot --help'
curl -L https://github.com/etcd-io/etcd/releases/download/v3.6.7/etcd-v3.6.7-darwin-arm64.zip \
  -o /tmp/etcd.zip
unzip -j /tmp/etcd.zip 'etcd-v3.6.7-darwin-arm64/etcd' \
  'etcd-v3.6.7-darwin-arm64/etcdctl' \
  'etcd-v3.6.7-darwin-arm64/etcdutl' \
  -d /tmp/etcd-bins
sudo mv /tmp/etcd-bins/{etcd,etcdctl,etcdutl} /usr/local/bin/
brew install sqlite3
```

### 4. Convert snapshot to state.db

```bash
cd etcd-2-sqlite
go build -o k3s-etcd2sqlite .

./k3s-etcd2sqlite direct-convert \
  --snapshot ../pre-sqlite-<name> \
  --output-db ../state.db \
  --force
```

### 5. Inspect the result

Confirm all namespaces and nodes are present before proceeding:

```bash
sqlite3 state.db "SELECT count(*) FROM kine;"
sqlite3 state.db "SELECT name FROM kine WHERE name LIKE '/registry/namespaces/%';"
sqlite3 state.db "SELECT name FROM kine WHERE name LIKE '/registry/minions/%';"
```

### 6. Cross-compile for ARM64 and copy to master

```bash
GOOS=linux GOARCH=arm64 go build -o k3s-etcd2sqlite-arm64 .
scp k3s-etcd2sqlite-arm64 ../state.db root@192.168.1.106:~/
```

### 7. Run restore-sqlite on the master

```bash
ssh root@192.168.1.106 'sudo ./k3s-etcd2sqlite-arm64 restore-sqlite --state-db ~/state.db'
# type: RESTORE
```

This command:
- Stops k3s
- Backs up `etcd/` → `etcd-backup-<timestamp>` (rollback point)
- Places `state.db` at `/var/lib/rancher/k3s/server/db/state.db`
- Removes `--cluster-init` from `/etc/systemd/system/k3s.service`
- Runs `systemctl daemon-reload && systemctl start k3s`

### 8. Verify SQLite is active

```bash
ssh root@192.168.1.106 './k3s-etcd2sqlite-arm64 verify --strict'
kubectl get nodes
```

Confirm in logs:
```bash
ssh root@192.168.1.106 'journalctl -u k3s --since "5 minutes ago" | grep -i "kine\|sqlite"'
```

Expected:
```
"Configuring sqlite3 database connection pooling"
"Kine available at unix://kine.sock"
```

---

## Post-migration cleanup

### Remove stale Traefik HelmChart CRs

The imported `state.db` may contain built-in K3s HelmChart objects for Traefik from before `--disable traefik` was set. They cause failing jobs:

```bash
kubectl delete helmchart traefik traefik-crd -n kube-system 2>/dev/null
kubectl delete job -n kube-system helm-install-traefik helm-install-traefik-crd 2>/dev/null
```

### Remove empty arg artifact in service file

The patch that removes `--cluster-init` may leave an empty `''` on its own line if the flag was quoted in the service file:

```bash
ssh root@192.168.1.106 "sed -i \"/^    ''\$/d\" /etc/systemd/system/k3s.service && systemctl daemon-reload"
```

### Optional: taint master node

Prevents workload pods from scheduling on the master, keeping kine/apiserver I/O uncontested:

```bash
kubectl taint nodes raspberrypi4-5 node-role.kubernetes.io/control-plane=:NoSchedule
```

---

## Why a k3s restart is required

The datastore backend is a startup flag (`--cluster-init` enables etcd mode). k3s reads it once at boot, opens a connection, and holds it for the lifetime of the process. There is no hot-swap — to switch from etcd to kine/SQLite you must:

1. Stop k3s
2. Remove `--cluster-init` from `/etc/systemd/system/k3s.service`
3. Place `state.db` at `/var/lib/rancher/k3s/server/db/state.db`
4. Start k3s

The restart itself is unavoidable. The chaos that follows is a predictable cascade from restarting a process that owns the network datapath and the datastore simultaneously.

---

## Why things break during migration

### k3s restart → Cilium eBPF stale state

Cilium builds eBPF maps keyed to container network namespaces. When k3s stops and restarts, those namespaces are invalidated. If Cilium doesn't flush its maps (which it doesn't automatically on k3s restart), the stale entries cause cross-node traffic to be silently dropped — pods on other nodes can't reach pods on the master. Fix: delete the Cilium pod on the master; the DaemonSet recreates it with clean eBPF state.

### First k3s startup after import → kine compaction burst

On first boot after importing an etcd snapshot, kine compacts all the revision history it inherited. This generates heavy sequential SQLite writes that lock the WAL for several seconds at a time:

```
COMPACT deleted 997 rows from 1000 revisions in 609ms
COMPACT deleted 962 rows from 1000 revisions in 458ms
Slow SQL (total time: 2.981s): INSERT INTO kine(...)
```

During this window the API server is slow to respond to all requests.

### Compaction + Cilium → CNPG crash loop

`cnpg-cluster-1` ran on the master node. On startup it makes API server calls (`10.43.0.1:443`). It hit both problems simultaneously:

- Stale Cilium eBPF on master → `i/o timeout` to API server
- WAL contention from kine compaction → API server response latency

Startup probes timed out → crash loop. Worker-node replicas (`cnpg-cluster-2`, `cnpg-cluster-3`) made the same API calls over the network and survived because they didn't compete with the local SQLite writes. Fix: nodeAffinity to exclude master from CNPG scheduling.

### Slow API server → Kyverno chicken-and-egg

Kyverno pod failed its startup probe during the compaction burst and got stuck in `Init:0/1`. Its admission webhooks were still registered but had no healthy endpoints — every `helm upgrade` or `kubectl apply` timed out waiting for the webhook:

```
failed calling webhook "validate.kyverno.svc-fail": context deadline exceeded
```

Fix: delete all Kyverno webhook configurations to unblock the cluster; Kyverno re-registers them once its pod recovers.

---

## Post-migration troubleshooting

### Cilium eBPF state corruption after k3s restart

**Symptom:** pods on other nodes cannot reach pods running on the master (504 Gateway Timeout, `curl` timeout, `ENOBUFS` on traceroute from master).

**Cause:** when k3s restarts during migration, Cilium's eBPF state on the master node can become corrupted — socket buffers exhausted, stale BPF maps. Cross-node traffic to pods on the master is silently dropped.

**Diagnosis:**
```bash
# from a worker node, try to reach a pod on the master by pod IP
ssh root@<worker-ip> 'curl -s --max-time 5 http://<master-pod-ip>:<port>/-/healthy'
# timeout = Cilium routing broken

# confirm endpoint not known on worker's Cilium
kubectl exec -n kube-system <cilium-pod-on-worker> -- cilium-dbg endpoint list | grep <master-pod-ip>
# no output = endpoint not propagated

# check buffer exhaustion on master
ssh root@192.168.1.106 'traceroute -n <master-pod-ip>'
# "No buffer space available" = eBPF state bad
```

**Fix:** restart the Cilium pod on the master — DaemonSet recreates it with clean eBPF state:
```bash
kubectl delete pod -n kube-system <cilium-pod-on-master>
# wait for it to come back Running, then retest connectivity
```

---

### Ingress returning 504 after migration

**Symptom:** Traefik returns `504 Gateway Timeout` for monitoring UIs (Prometheus, Grafana).

**Cause:** usually a consequence of the Cilium eBPF issue above — Traefik resolves the backend pod IP correctly but traffic is dropped at the master's Cilium layer.

**Fix:** same as above — restart Cilium on master. Once connectivity is restored, Traefik routes traffic successfully without any reconfiguration.

---

### Kyverno webhook blocking all resource changes

**Symptom:** `helm upgrade`, `kubectl apply` fail with:
```
failed calling webhook "validate.kyverno.svc-fail": ... context deadline exceeded
```

**Cause:** Kyverno admission controller pod stuck in `Init:0/1` (chicken-and-egg: pod violates its own resource limits policy). Webhooks registered but no endpoints available — all admission requests time out.

**Fix:** delete all Kyverno webhook configurations to unblock the cluster, then let Kyverno recover and re-register them:
```bash
kubectl delete validatingwebhookconfiguration \
  $(kubectl get validatingwebhookconfiguration --no-headers | grep kyverno | awk '{print $1}')
kubectl delete mutatingwebhookconfiguration \
  $(kubectl get mutatingwebhookconfiguration --no-headers | grep kyverno | awk '{print $1}')
```

Kyverno will re-register the webhooks once its pod is healthy.

---

### General pattern: pods on master with stale Cilium state

After migration, any pod running on the master that was alive during the k3s restart will have stale Cilium eBPF state. Symptoms vary but root cause is the same: the pod cannot reach other IPs (API server, other pods, its own pod IP) because the eBPF maps were invalidated by the k3s restart and never flushed.

**Affected pods (observed):** Prometheus, local-path-provisioner, metrics-server, CNPG replica.

**Fix pattern:**
```bash
# 1. restart Cilium on master to flush stale eBPF maps
kubectl delete pod -n kube-system $(kubectl get pod -n kube-system -l k8s-app=cilium -o wide | grep raspberrypi4-5 | awk '{print $1}')

# 2. restart each affected pod so it comes up after Cilium is clean
kubectl rollout restart deployment/<affected-deployment> -n <namespace>
# or for StatefulSet: delete the pod
kubectl delete pod <statefulset-pod> -n <namespace>
```

**Long-term fix:** move stateful or control-plane-sensitive workloads off the master entirely (nodeSelector or nodeAffinity). The master should run only kine/apiserver/scheduler/controller-manager. Any workload competing for I/O or making frequent API calls will be affected during kine compaction bursts.

---

### metrics-server crash loop (no route to host on port 10250)

**Symptom:** metrics-server repeatedly fails readiness/liveness probes:
```
Readiness probe failed: Get "https://10.42.x.x:10250/readyz": dial tcp: connect: no route to host
```

**Cause:** metrics-server connects to kubelet on each node via port 10250. If Cilium eBPF state is stale on any node, those connections are silently dropped — same root cause as the 504 ingress issue.

**Fix:**
```bash
# 1. restart Cilium on master to flush stale eBPF state
MASTER_CILIUM=$(kubectl get pod -n kube-system -l k8s-app=cilium -o wide | grep raspberrypi4-5 | awk '{print $1}')
kubectl delete pod -n kube-system $MASTER_CILIUM

# 2. restart metrics-server to clear backoff state
kubectl rollout restart deployment/metrics-server -n kube-system

# 3. verify
kubectl top nodes
```

---

### Stale Traefik HelmChart CRs causing looping helm-install jobs

**Symptom:** `helm-install-traefik` and `helm-install-traefik-crd` jobs keep restarting in `kube-system`, failing with `secret "chart-values-traefik" not found` or `configmap "chart-content-traefik" not found`.

**Cause:** the imported `state.db` contains K3s built-in HelmChart CRs for Traefik from before `--disable traefik` was configured. K3s HelmChart controller watches these CRs and continuously spawns new install jobs.

**Fix:** delete the HelmChart CRs — the controller stops spawning jobs immediately:
```bash
kubectl delete helmchart traefik traefik-crd -n kube-system --ignore-not-found
kubectl get job -n kube-system | grep traefik | awk '{print $1}' | xargs kubectl delete job -n kube-system --ignore-not-found
```

Confirm:
```bash
kubectl get helmchart,job -n kube-system | grep traefik
# should return nothing
```

---

## Rollback

If k3s fails to start after the migration:

```bash
ssh root@192.168.1.106 '
systemctl stop k3s
rm -f /var/lib/rancher/k3s/server/db/state.db
mv /var/lib/rancher/k3s/server/db/etcd-backup-* /var/lib/rancher/k3s/server/db/etcd
cp /etc/systemd/system/k3s.service.bak-sqlite /etc/systemd/system/k3s.service
systemctl daemon-reload && systemctl start k3s
'
```

---

## Notes

- `kubectl get nodes` still shows `ROLES: control-plane,etcd` after migration. This is a node label set at install time — it is cosmetic and does not reflect the active datastore.
- Workers do not need to rejoin. Cluster TLS certificates live in `/var/lib/rancher/k3s/server/` (outside the datastore) and are unaffected by the switch.
- Pods are rescheduled after the master restarts — this is normal. Workloads on workers remain running during the control-plane restart.
