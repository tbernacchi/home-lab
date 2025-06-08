## UPDATE

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts -n monitoring
helm repo update
helm get values my-kube-prometheus-stack -n monitoring -o yaml > ~tadeu/home-lab/monitoring/values.yaml
helm upgrade my-kube-prometheus-stack prometheus-community/kube-prometheus-stack -n monitoring --version 72.3.0 -n monitoring -f ~tadeu/home-lab/monitoring/values.yaml
```

[Kube-Prometheus](https://artifacthub.io/packages/helm/bitnami/kube-prometheus)

# Cleaning up stale Prometheus metrics

This guide describes how to clean up old/obsolete metrics from Prometheus running on Kubernetes.

## Problem
When metrics are renamed or discontinued, they may continue to appear in the Prometheus UI even though they are no longer being collected. This happens because Prometheus maintains a history of these metrics in its storage.

## Solution
To completely clean up old metrics, we need to recreate Prometheus with a clean storage.

### Prerequisites
- Access to the Kubernetes cluster
- Helm installed
- Prometheus values file (`~/home-lab/monitoring/values.yaml`)

### Steps

1. Delete the Prometheus StatefulSet:
```bash
kubectl delete statefulset prometheus-my-kube-prometheus-stack-prometheus -n monitoring
```

2. Delete the PVC to clean the storage:
```bash
kubectl delete pvc prometheus-my-kube-prometheus-stack-prometheus-db-prometheus-my-kube-prometheus-stack-prometheus-0 -n monitoring
```

3. Upgrade the helm chart:
```bash
helm upgrade my-kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  -n monitoring \
  --version 72.3.0 \
  -n monitoring \
  -f ~/home-lab/monitoring/values.yaml
```

4. Verify that Prometheus is running:
```bash
kubectl get pods -n monitoring | grep prometheus-0
```

### Verification
After these steps, access the Prometheus UI and verify that:
- The old metrics no longer appear
- Current metrics are being collected correctly
- Prometheus is functioning normally

### Notes
- This process will erase all metric history
- Prometheus will start collecting metrics from scratch
- Wait a few minutes after the process for Prometheus to fully initialize

## References
- [Prometheus Operator Documentation](https://github.com/prometheus-operator/prometheus-operator)
- [Helm Chart Documentation](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack) 

