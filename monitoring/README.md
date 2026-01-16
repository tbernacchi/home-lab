# Monitoring Stack Installation

This directory contains the configuration for deploying the Prometheus monitoring stack (kube-prometheus-stack) on Kubernetes.

## Prerequisites

- Access to the Kubernetes cluster
- Helm installed
- kubectl configured to access the cluster
- Traefik ingress controller configured (for IngressRoute)

## Installation Steps

### 1. Create the monitoring namespace

```bash
kubectl create namespace monitoring
```

### 2. Add the Prometheus Community Helm repository

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
```

### 3. Install kube-prometheus-stack

```bash
helm install my-kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --version 72.3.0 \
  --namespace monitoring \
  --values values.yaml
```

### 4. Wait for the stack to be ready

```bash
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=prometheus-operator \
  -n monitoring \
  --timeout=300s

kubectl wait --for=condition=ready pod \
  -l app=prometheus,prometheus=my-kube-prometheus-stack-prometheus \
  -n monitoring \
  --timeout=300s
```

### 5. Apply Prometheus patch

Apply the patch to configure Prometheus alertmanager integration:

```bash
kubectl patch prometheus prometheus-stack-kube-prom-prometheus -n monitoring --type='merge' \
  -p='{"spec":{"alerting":{"alertmanagers":[{"apiVersion":"v2","namespace":"monitoring","name":"prometheus-stack-kube-prom-alertmanager","port":"http-web","pathPrefix":"/alertmanager"}]}}}'
```

**Note:** Adjust the Prometheus resource name according to your installation. If using `prometheus-patch.yaml`, verify the resource name matches your actual Prometheus instance.

### 6. Configure SSL/TLS Certificate

Ensure the `traefik-dashboard-cert` secret exists in the `monitoring` namespace (see [SSL/TLS Certificate](#ssltls-certificate) section).

### 7. Apply IngressRoute configuration

Apply the IngressRoute to expose Prometheus, Grafana, and Alertmanager through Traefik:

```bash
kubectl apply -f ingressroute.yaml
```

**Note:** The `ingressroute.yaml` uses service names that match your installation:
- `prometheus-stack-kube-prom-prometheus`
- `prometheus-stack-grafana`
- `prometheus-stack-kube-prom-alertmanager`

### 8. Get Grafana admin password

```bash
kubectl get secret prometheus-stack-grafana -n monitoring -o jsonpath="{.data.admin-password}" | base64 -d
echo
```

### 9. Verify installation

Check that all pods are running:

```bash
kubectl get pods -n monitoring
```

Access the services:
- **Prometheus**: https://traefik.mykubernetes.com/prometheus
- **Grafana**: https://traefik.mykubernetes.com/grafana (user: `admin`, password: from step 7)
- **Alertmanager**: https://traefik.mykubernetes.com/alertmanager

## Configuration

### Storage

The stack uses `local-path` storage class (default in k3s):
- Prometheus: 2Gi storage
- Alertmanager: 1Gi storage

### Resources

Resource limits and requests are configured in `values.yaml`:
- Prometheus: 1Gi memory, 1 CPU
- Alertmanager: 512Mi memory, 500m CPU
- Grafana: 512Mi memory, 500m CPU

### SSL/TLS Certificate

The IngressRoute uses the `traefik-dashboard-cert` secret for TLS encryption. If the certificate is missing or expired, follow these steps:

#### 1. Check if certificate exists in monitoring namespace

```bash
kubectl get secret traefik-dashboard-cert -n monitoring
```

#### 2. Generate new certificate (if needed)

If the certificate is missing or expired, generate a new one:

```bash
cd ../certs
./certificate.sh
```

This will create the `traefik-dashboard-cert` secret in the `traefik` namespace.

#### 3. Copy certificate to monitoring namespace

The IngressRoute needs the certificate in the `monitoring` namespace:

```bash
kubectl get secret traefik-dashboard-cert -n traefik -o yaml | \
  sed 's/namespace: traefik/namespace: monitoring/' | \
  sed '/resourceVersion:/d' | \
  sed '/uid:/d' | \
  kubectl apply -f -
```

#### 4. Verify certificate validity

Check certificate expiration date:

```bash
kubectl get secret traefik-dashboard-cert -n monitoring -o jsonpath='{.data.tls\.crt}' | \
  base64 -d | openssl x509 -noout -dates -subject
```

#### 5. Add CA to system keychain (macOS)

If you get certificate errors in the browser, add the CA certificate to your system keychain:

```bash
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ../certs/ca.crt
```

**Note:** After generating a new certificate, you may need to clear your browser cache or use incognito mode to avoid HSTS (HTTP Strict Transport Security) issues.

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

