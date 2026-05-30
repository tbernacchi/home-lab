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
