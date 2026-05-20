# Kyverno

Kubernetes-native policy engine for admission control, mutation, and validation.

## Installation

```bash
helm repo add kyverno https://kyverno.github.io/kyverno/
helm repo update
helm install kyverno kyverno/kyverno \
  --version 3.8.1 \
  --namespace kyverno \
  --create-namespace \
  --values values.yaml
```

## Upgrade

```bash
helm get values kyverno -n kyverno -o yaml > kyverno/values.yaml
helm upgrade kyverno kyverno/kyverno \
  --version <NEW_VERSION> \
  --namespace kyverno \
  --values values.yaml
```

## Configuration

`values.yaml` sets `admissionController.replicas=1` (no HA) and reduced resource limits to fit Raspberry Pi 4 nodes.

## Verify

```bash
kubectl get pods -n kyverno
kubectl get clusterpolicies
```
