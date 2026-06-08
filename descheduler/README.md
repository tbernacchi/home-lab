# Descheduler

Evicts pods from overloaded nodes so the scheduler can rebalance them across the cluster. Runs as a CronJob every 5 minutes.

## Installation

```bash
helm repo add descheduler https://kubernetes-sigs.github.io/descheduler/
helm repo update

helm upgrade --install descheduler descheduler/descheduler \
  --namespace kube-system \
  --set schedule="*/5 * * * *" \
  --set "deschedulerPolicy.strategies.LowNodeUtilization.enabled=true" \
  --set "deschedulerPolicy.strategies.LowNodeUtilization.params.nodeResourceUtilizationThresholds.thresholds.cpu=30" \
  --set "deschedulerPolicy.strategies.LowNodeUtilization.params.nodeResourceUtilizationThresholds.thresholds.memory=30" \
  --set "deschedulerPolicy.strategies.LowNodeUtilization.params.nodeResourceUtilizationThresholds.targetThresholds.cpu=50" \
  --set "deschedulerPolicy.strategies.LowNodeUtilization.params.nodeResourceUtilizationThresholds.targetThresholds.memory=50"
```

## Strategy: LowNodeUtilization

| Threshold | CPU | Memory | Meaning |
|-----------|-----|--------|---------|
| `thresholds` | 30% | 30% | Node below this → candidate to receive pods |
| `targetThresholds` | 50% | 50% | Node above this → pods evicted from here |

Narrow window (30%→50%) = more frequent rebalancing, uniform load across nodes.

## Zero-downtime eviction

The descheduler evicts pods but does not move them — the scheduler reschedules them on a better node. During eviction, the pod is terminated briefly.

To avoid downtime during rebalancing:
1. Run at least **2 replicas** on the deployment.
2. Add a `PodDisruptionBudget` with `minAvailable: 1`.

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: myapp-pdb
  namespace: mynamespace
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: myapp
```

Single-replica workloads (Grafana, Alertmanager, etc.) will always have a brief downtime during eviction. Acceptable in a homelab context.

## Upgrade

```bash
helm get values descheduler -n kube-system -o yaml > descheduler/values.yaml
helm upgrade descheduler descheduler/descheduler \
  --namespace kube-system \
  --values descheduler/values.yaml
```

## Verify

```bash
kubectl get cronjob -n kube-system
kubectl get configmap -n kube-system descheduler -o yaml
```
