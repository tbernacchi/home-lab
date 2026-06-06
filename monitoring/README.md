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
helm upgrade --install my-kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --timeout 10m \
  --set prometheusOperator.admissionWebhooks.enabled=false \
  --set prometheusOperator.admissionWebhooks.patch.enabled=false \
  -f monitoring/values.yaml
```

**Why `admissionWebhooks.enabled=false`:** the `admission-create` job spawns a pod that generates TLS certs for webhook validation. With Tailscale + VXLAN networking, this job hits `BackoffLimitExceeded` (timing/connectivity issue during pod startup). Disabling is safe for home lab — PrometheusRule validation errors fail silently instead of being rejected at admission.

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
- **Grafana**: https://traefik.mykubernetes.com/grafana (user: `admin`, password: from step 8)
- **Alertmanager**: https://traefik.mykubernetes.com/alertmanager

> **Common issue — services returning 404:** The `ingressroute.yaml` must be explicitly applied after Helm install — it is not managed by Helm.
> ```bash
> kubectl apply -f ingressroute.yaml
> kubectl get ingressroute -n monitoring  # confirm it appears
> ```

> **Common issue — `ERR_CERT_AUTHORITY_INVALID` in browser:** The cluster uses a self-signed CA (`MyKubernetes CA`). Install it in the OS trust store:
> ```bash
> # export the CA from the cluster
> kubectl get secret traefik-dashboard-cert -n monitoring \
>   -o jsonpath='{.data.tls\.crt}' | base64 -d > mykubernetes-ca.crt
>
> # install on macOS
> sudo security add-trusted-cert -d -r trustRoot \
>   -k /Library/Keychains/System.keychain mykubernetes-ca.crt
> ```
> Fully quit Chrome (Cmd+Q) and reopen. If still blocked by HSTS:
> - Open `chrome://net-internals/#hsts`
> - Under "Delete domain security policies" → enter `traefik.mykubernetes.com` → Delete
> - Reopen the tab

> **Common issue — Prometheus returning 301 but not loading:** `301` is expected — Prometheus redirects `/prometheus` → `/prometheus/graph`. Use `curl -skL` (follow redirects) to confirm `200`. If browser still fails, it's the cert issue above.

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

The IngressRoute uses `traefik-dashboard-cert` for TLS. Certs are generated via `mkcert` (handles CA trust + SAN automatically — macOS LibreSSL cannot generate certs with SAN via `openssl x509 -req`).

#### Prerequisite

```bash
brew install mkcert
```

#### Generate and apply certs

```bash
cd ../certs
bash certificate.sh
```

The script:
1. Runs `mkcert -install` — creates and installs the mkcert CA in the macOS keychain
2. Generates `traefik.mykubernetes.com.pem` + key with correct SAN
3. Applies `traefik-dashboard-cert` secret to `traefik` and `monitoring` namespaces
4. Updates `traefik-cert` secret in `traefik` namespace (used by Gateway websecure listener as default cert)
5. Restarts Traefik

> **Why both secrets?** `traefik-cert` is the default cert for the Gateway `websecure` listener (port 443). If it holds the old cert, Traefik serves it instead of `traefik-dashboard-cert` even when the IngressRoute specifies the latter. Both must be updated.

#### Verify cert served by Traefik

```bash
echo | openssl s_client -connect 192.168.1.131:443 \
  -servername traefik.mykubernetes.com 2>/dev/null \
  | openssl x509 -noout -issuer

# expected: issuer=O=mkcert development CA, ...
```

Verify SAN (use `-text` — LibreSSL doesn't support `-ext san`):
```bash
openssl x509 -text -noout \
  -in ../certs/traefik.mykubernetes.com.pem \
  | grep -A2 "Subject Alternative"

# expected: DNS:traefik.mykubernetes.com
```

#### After running the script — browser steps

1. **Clear HSTS cache in Chrome:**
   - Open `chrome://net-internals/#hsts`
   - "Delete domain security policies" → `traefik.mykubernetes.com` → Delete

2. **Fully quit Chrome** (Cmd+Q — not just close the window)

3. Reopen and access `https://traefik.mykubernetes.com/prometheus`

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

