# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Personal home-lab Kubernetes setup running on a Raspberry Pi 4 cluster. Infrastructure-as-code — no application code, only YAML manifests, Helm values, and shell scripts.

**Cluster nodes:** `192.168.1.106` (master/control-plane), workers at `192.168.1.105`, `192.168.1.103`  
**Domain:** `traefik.mykubernetes.com`

## Cluster Management Scripts

```bash
# Reset master and optionally workers, reinstall K3s from scratch
sudo ./reset-k3s-cluster.sh --version v1.33.6+k3s1 --workers 192.168.1.105,192.168.1.103

# Join a worker node after reset (run on the worker)
sudo ./reset-and-join-node.sh --version v1.33.6+k3s1 --master-ip 192.168.1.106 --token <TOKEN>

# Get node token (run on master)
sudo cat /var/lib/rancher/k3s/server/node-token

# Backup / restore etcd snapshot
./backup-k3s-cluster.sh
./restore-k3s-cluster.sh
```

## Architecture

### Networking (Cilium)
Cilium replaces kube-proxy entirely (`kubeProxyReplacement=true`) and runs in native routing mode (no overlay/VXLAN). L2 announcements handle LoadBalancer IPs. The `kube-system` ConfigMap `cilium-config` holds additional tuning (`bpf-lb-sock-hostns-only`, `device: eth0`).

Upgrade Cilium via `helm upgrade --install` with `--reuse-values` to preserve settings. Always restart the daemonset after config changes: `kubectl -n kube-system rollout restart ds/cilium`.

### Ingress (Traefik)
All UIs are exposed through Traefik **IngressRoute** CRDs (not standard Ingress). Each service uses path-based routing:
- `/argocd` → Argo CD
- `/argo/` → Argo Workflows  
- `/prometheus`, `/grafana`, `/alertmanager` → monitoring stack

**TLS:** Single self-signed cert stored as secret `traefik-dashboard-cert` in the `traefik` namespace. This secret must be manually copied to every namespace that has an IngressRoute:
```bash
kubectl get secret traefik-dashboard-cert -n traefik -o yaml \
  | sed 's/namespace: traefik/namespace: TARGET_NS/' \
  | sed '/resourceVersion:/d' | sed '/uid:/d' \
  | kubectl apply -f -
```
Regenerate cert: `cd certs && ./certificate.sh`

### GitOps Stack (argo-stack/)
All four Argo components install into `argocd` or `argo` namespaces via raw manifests from upstream URLs, then patched:

- **Argo CD** — needs deployment patch for `--insecure --basehref=/argocd --rootpath=/argocd`. Use version `v2.14.10` (known basehref bug in later versions). Get initial password: `kubectl get secret/argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 --decode`
- **Argo Workflows** — edit deploy `argo-server` to add `BASE_HREF=/argo/` env var and `--auth-mode=server` arg
- **Argo Rollouts** — installed via Helm into `argo-rollouts` namespace; patch argocd-server to show rollouts extension in UI
- **Argo Image Updater** — installed into `argocd` namespace; requires `regcred` (DockerHub) and `git-creds` secrets

### Monitoring (monitoring/)
`kube-prometheus-stack` via Helm in `monitoring` namespace. Values in `monitoring/values.yaml`. Storage: `local-path` (k3s default), Prometheus 2Gi, Alertmanager 1Gi.

To clean stale metrics: delete the Prometheus StatefulSet + PVC, then `helm upgrade`.

### Database (cloudnative-pg/)
3-replica PostgreSQL cluster with PgBouncer. Uses custom storage class pointing to `/opt/local-path-provisioner/cnpg` on each node (must exist before deploying). The PodMonitor needs label patch (`release: my-kube-prometheus-stack`) to be discovered by Prometheus.

Connection endpoints in `cnpg` namespace: `-rw` (primary), `-ro` (replicas), pooler service for PgBouncer.

## Key Patterns

**Applying a component in order:** CloudNativePG files are numbered `000-` through `004-` — apply sequentially.

**Helm releases in use:**
| Release | Chart | Namespace |
|---------|-------|-----------|
| `cilium` | `cilium/cilium` | `kube-system` |
| `traefik` | `traefik/traefik` | `traefik` |
| `my-kube-prometheus-stack` | `prometheus-community/kube-prometheus-stack` | `monitoring` |
| `argo-rollouts` | `argo/argo-rollouts` | `argo-rollouts` |

**Updating Helm values:** Always export current values before upgrading:
```bash
helm get values <release> -n <namespace> -o yaml > <path>/values.yaml
```
