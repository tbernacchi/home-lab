# Loki

Loki deployed in single-binary mode in the `monitoring` namespace. Promtail runs as a DaemonSet on all nodes and ships logs to Loki automatically.

## Files

| File | Purpose |
|------|---------|
| `values.yaml` | Helm values for Loki (single-binary, filesystem storage, 7-day retention) |
| `promtail-values.yaml` | Helm values for Promtail DaemonSet |

## Installation

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

helm upgrade --install loki grafana/loki \
  -n monitoring \
  -f monitoring/loki/values.yaml

helm upgrade --install promtail grafana/promtail \
  -n monitoring \
  -f monitoring/loki/promtail-values.yaml
```

After installing, update Grafana to provision the Loki datasource:

```bash
helm upgrade my-kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  -n monitoring -f monitoring/values.yaml

kubectl rollout restart deployment/my-kube-prometheus-stack-grafana -n monitoring
```

## Verify

```bash
# Loki pod (single-binary)
kubectl get pods -n monitoring | grep loki-0

# Promtail DaemonSet — one pod per node
kubectl get pods -n monitoring | grep promtail
```

Expected: 1 `loki-0` pod + 5 `promtail-*` pods (one per node including OCI master).

## Architecture

- **Loki** — single-binary mode, filesystem storage via `local-path` PVC (10Gi on the scheduled node)
- **Promtail** — DaemonSet, reads `/var/log/pods/` on each node, ships all container stdout/stderr to Loki
- **Retention** — 7 days (`168h`), compactor with `delete_request_store: filesystem`
- **Grafana datasource** — provisioned via `additionalDataSources` in `monitoring/values.yaml` (url: `http://loki.monitoring.svc:3100`)

## Querying logs in Grafana

Grafana → Explore → select **Loki** datasource. Filter examples:

```
{namespace="monitoring"}
{namespace="argocd"}
{app="traefik"}
{node_name="raspberrypi4-3"}
```

Promtail collects stdout/stderr from all containers in all namespaces — no extra configuration needed per application.

## Troubleshooting

### CrashLoopBackOff — compactor config error

```
CONFIG ERROR: invalid compactor config: compactor.delete-request-store should be configured when retention is enabled
```

`retention_enabled: true` requires `delete_request_store` to be set. Already fixed in `values.yaml`:

```yaml
loki:
  compactor:
    retention_enabled: true
    delete_request_store: filesystem
```

### Unnecessary pods on OCI master

By default the chart enables `lokiCanary` (DaemonSet) and memcached caches (`chunksCache`, `resultsCache`). Disabled in `values.yaml` — overhead without benefit in a homelab:

```yaml
monitoring:
  lokiCanary:
    enabled: false
chunksCache:
  enabled: false
resultsCache:
  enabled: false
```
