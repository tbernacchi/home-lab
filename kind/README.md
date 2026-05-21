# Istio Study Cluster (ICA Exam Prep)

Local kind cluster with Istio + full observability stack. Isolated from the RPi home-lab (Cilium conflict — see [why](../cilium/cilium-compare-2-istio.md)).

## Prerequisites

| Tool | Install |
|---|---|
| `kind` | `brew install kind` |
| `kubectl` | `brew install kubectl` |
| `docker` | Docker Desktop |
| `istioctl` | auto-downloaded by `setup.sh` |

## Quick Start

```bash
chmod +x setup.sh teardown.sh port-forward.sh
./setup.sh   # creates kind cluster only
```

Istio, addons, and app deploys are done separately.

## Teardown

```bash
./teardown.sh
```

---

## ICA Exam Domain Map

| Domain | Weight | Practice Files |
|---|---|---|
| Installation, Upgrade & Configuration | 7% | `setup.sh` — review demo profile, `istioctl analyze` |
| Traffic Management | 40% | `01-traffic-shifting.yaml`, `06-egress-serviceentry.yaml` |
| Resilience & Fault Tolerance | 20% | `02-fault-injection.yaml`, `05-circuit-breaker.yaml`, `07-request-timeout-retry.yaml` |
| Securing Workloads | 20% | `03-mtls-strict.yaml`, `04-authz-policy.yaml` |
| Advanced Scenarios (Observability) | 13% | Kiali, Jaeger, Grafana via `port-forward.sh` |

---

## Practice Manifests

```
practice/
├── 01-traffic-shifting.yaml      # VirtualService weight-based canary (90/10)
├── 02-fault-injection.yaml       # Delay + HTTP abort via fault injection
├── 03-mtls-strict.yaml           # PeerAuthentication STRICT namespace-wide
├── 04-authz-policy.yaml          # Deny-all + allow rules (AuthorizationPolicy)
├── 05-circuit-breaker.yaml       # DestinationRule outlier detection
├── 06-egress-serviceentry.yaml   # ServiceEntry for external traffic
└── 07-request-timeout-retry.yaml # Timeouts + retries on VirtualService
```

Apply individually and reset before the next exercise:

```bash
kubectl apply -f practice/01-traffic-shifting.yaml
# ... test ...
kubectl delete -f practice/01-traffic-shifting.yaml
```

---

## Key ICA Commands

```bash
# Verify mesh config
istioctl analyze

# Check mTLS status between services
istioctl authn tls-check <pod>.<namespace> <service>.<namespace>.svc.cluster.local

# Inspect proxy config for a pod
istioctl proxy-config routes <pod> -n default
istioctl proxy-config clusters <pod> -n default
istioctl proxy-config listeners <pod> -n default

# Check sidecar injection
kubectl get pod -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[*].name}{"\n"}{end}'

# Tail Envoy access logs
kubectl logs -l app=productpage -c istio-proxy -f

# Generate traffic (for Kiali/Jaeger graphs)
while true; do curl -s http://localhost:8080/productpage > /dev/null; sleep 0.5; done
```

---

## Istio Demo Profile — What's Installed

```
istiod              (Pilot + Citadel + Galley)
istio-ingressgateway
istio-egressgateway
prometheus
grafana
jaeger (via tracing deployment)
kiali
```

---

## Cluster Config

- **Name:** `istio-study`
- **Nodes:** 1 control-plane + 2 workers
- **Istio version:** 1.24.3 (demo profile)
- **Namespace injection:** `default` namespace auto-injects sidecars
