# Argo Rollouts

Canary deployment controller with automatic rollback via Prometheus error-rate analysis.

## Files

- `kustomization.yaml` — Kustomize config (rollout-demo namespace)
- `rollout-demo.yaml` — Demo rollout (pod-based canary, no traffic router)
- `patch-argocd-server.yaml` — Enables Rollouts extension in Argo CD UI
- `gateway-api-plugin-config.yaml` — ConfigMap enabling Gateway API traffic router plugin (ARM64 v0.13.0)
- `analysis-template-error-rate.yaml` — AnalysisTemplate: auto-rollback if 5xx rate >= 5% (Traefik metrics via Prometheus)

## Architecture

```
Rollout → HTTPRoute → Traefik → Prometheus → AnalysisRun
           (weights)   (metrics)   (error rate)  (rollback)
```

Traffic split uses Kubernetes Gateway API (`HTTPRoute`) with Traefik as the gateway provider.
Argo Rollouts updates `HTTPRoute` weights at each canary step — real percentage split, not pod-count ratio.

## Plugin: Gateway API (ARM64)

The `argoproj-labs/rollouts-plugin-trafficrouter-traefik` has no ARM64 binary.
Use `argoproj-labs/gatewayAPI` plugin instead — has `linux-arm64` binary from v0.3.0+.

Apply config:
```bash
kubectl apply -f gateway-api-plugin-config.yaml
kubectl rollout restart deployment/argo-rollouts -n argo-rollouts
```

## Canary strategy (with Gateway API plugin)

```yaml
strategy:
  canary:
    canaryService: my-app-canary
    stableService: my-app-stable
    trafficRouting:
      plugins:
        argoproj-labs/gatewayAPI:
          httpRoute: my-app-httproute
          namespace: app
    steps:
      - setWeight: 20
      - pause: {duration: 2m}
      - analysis:
          templates:
            - templateName: error-rate
      - setWeight: 50
      - pause: {duration: 2m}
      - analysis:
          templates:
            - templateName: error-rate
      - setWeight: 100
```

## Prerequisites for Gateway API

```bash
# Install Gateway API CRDs (if not present)
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.1/standard-install.yaml

# Verify Traefik GatewayClass exists
kubectl get gatewayclass
```

K3s ships with Traefik v3 which supports Gateway API natively.
Enable in Traefik HelmChartConfig:
```yaml
providers:
  kubernetesGateway:
    enabled: true
```

## Prometheus address

```
http://my-kube-prometheus-stack-prometheus.monitoring.svc.cluster.local:9090/prometheus
```

Route-prefix `/prometheus` set via `--web.route-prefix=/prometheus` in kube-prometheus-stack values.

## Enable Argo CD UI extension

```bash
kubectl patch deployment argocd-server -n argocd --patch "$(cat patch-argocd-server.yaml)"
```

## References

- [Argo Rollouts](https://argoproj.github.io/argo-rollouts/)
- [Gateway API plugin](https://github.com/argoproj-labs/rollouts-plugin-trafficrouter-gatewayapi)
- [Traefik + Gateway API](https://doc.traefik.io/traefik/routing/providers/kubernetes-gateway/)
