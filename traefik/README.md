# Traefik

Traefik v3 deployed via Helm chart `traefik/traefik` (chart 38.0.1, app v3.6.5) in the `traefik` namespace.

## Files

| File | Purpose |
|------|---------|
| `values.yaml` | Helm values for Traefik deployment |
| `dashboard.yaml` | IngressRoute for the Traefik dashboard |

## Helm install

```bash
helm repo add traefik https://traefik.github.io/charts
helm repo update
helm upgrade --install traefik traefik/traefik \
  -n traefik --create-namespace \
  -f values.yaml
```

## Gateway API listeners

The Helm-managed Gateway (`traefik-gateway` in `traefik` namespace) is configured with a `web` listener (port 80, HTTP) in `values.yaml`. After install, a `websecure` listener (port 443, HTTPS) must be added via `kubectl patch` because the chart 38.0.1 schema does not allow `gateway.listeners.<name>.tls` in values:

```bash
kubectl patch gateway traefik-gateway -n traefik --type=json -p='[
  {
    "op": "add",
    "path": "/spec/listeners/-",
    "value": {
      "name": "websecure",
      "port": 443,
      "protocol": "HTTPS",
      "tls": {
        "mode": "Terminate",
        "certificateRefs": [
          {
            "kind": "Secret",
            "name": "traefik-cert",
            "namespace": "traefik"
          }
        ]
      },
      "allowedRoutes": {
        "namespaces": {
          "from": "All"
        }
      }
    }
  }
]'
```

> **Note:** `helm upgrade` reverts the Gateway to Helm-managed state and removes the patched listener. Re-apply the patch after every Helm upgrade.

### Verify listeners

```bash
kubectl get gateway traefik-gateway -n traefik -o jsonpath='{.status.listeners[*].name}'
# expected: web websecure
```

## Entrypoints

| Entrypoint | Port | Notes |
|-----------|------|-------|
| `web` | 80 | HTTP — redirects to `websecure` (configured via `additionalArguments`) |
| `websecure` | 443 | HTTPS — TLS terminated by Traefik |
| `metrics` | 8899 | Prometheus metrics |

HTTP→HTTPS redirect is global: `--entrypoints.web.http.redirections.entryPoint.to=websecure`. All HTTPRoutes must use `sectionName: websecure` — routes on `sectionName: web` will never serve traffic since HTTP requests are redirected at the entrypoint level before route matching.

## HTTPRoute requirements

For apps using Gateway API (`HTTPRoute`):

1. `sectionName: websecure` in `parentRefs` (not `web`)
2. `URLRewrite` filter to strip path prefix — apps do not receive the prefix:

```yaml
rules:
  - matches:
      - path:
          type: PathPrefix
          value: /myapp
    filters:
      - type: URLRewrite
        urlRewrite:
          path:
            type: ReplacePrefixMatch
            replacePrefixMatch: /
    backendRefs:
      - name: myapp-stable
        port: 8080
        weight: 100
```

3. HTTPRoutes with no `sectionName` match ALL listeners — avoid this as it causes routes to be applied on both `web` and `websecure`, potentially mixing backends across namespaces.

## TLS certificates

| Secret | Namespace | Covers |
|--------|-----------|--------|
| `traefik-cert` | `traefik` | `traefik.mykubernetes.com` (self-signed, MyKubernetes CA) |
| `traefik-clube-perfumes` | `traefik` | `*.clubedeperfumes.com.br` |
| `traefik-dashboard-cert` | `traefik` | Traefik dashboard |

The `websecure` Gateway listener uses `traefik-cert`. Apps that need a specific cert can reference it in their `IngressRoute` (CRD) or via `TLSRoute`.

## IngressRoute pattern (existing apps)

Apps predating the Gateway API setup use Traefik's native `IngressRoute` CRD directly on `websecure`:

```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: myapp
  namespace: mynamespace
spec:
  entryPoints:
    - websecure
  routes:
    - kind: Rule
      match: Host(`myapp.mykubernetes.com`) && PathPrefix(`/myapp`)
      services:
        - name: myapp-svc
          port: 80
  tls:
    secretName: traefik-cert
```

## Trusted IPs

`forwardedHeaders.trustedIPs` and `proxyProtocol.trustedIPs` include:
- Cloudflare IP ranges (for CF-Connecting-IP, CF-IPCountry, etc.)
- `192.168.1.130/32` — local load balancer / router
- `10.0.0.145/32` — internal node

## Dashboard

Accessible at `https://traefik.mykubernetes.com/dashboard/` via `IngressRoute` in `dashboard.yaml` (namespace `traefik-v2`). Requires DNS or `/etc/hosts` entry.
