# Cilium `fromEntities` Reference

In Cilium Network Policies, the `fromEntities` field under an `ingress` rule defines trusted entities that are allowed to initiate inbound traffic to the selected pods.

This is useful for allowing traffic from predefined sources without specifying exact labels or IPs.

## Available `fromEntities` Values

| Value         | Description                                                                 |
|---------------|-----------------------------------------------------------------------------|
| `all`         | Allows traffic from all entities (equivalent to allow-all).                |
| `world`       | Refers to traffic coming from outside the cluster (e.g., Internet).        |
| `cluster`     | Refers to traffic originating from within the Kubernetes cluster.          |
| `host`        | Traffic coming from the node's host system (e.g., system daemons).         |
| `remote-node` | Traffic between nodes within the cluster.                                  |
| `health`      | Used internally by Cilium for health checks between agents.                |
| `unmanaged`   | Traffic from endpoints not managed by Cilium.                              |
| `ingress`     | Traffic that entered via the host’s ingress interface.                     |
| `init`        | Traffic allowed during pod initialization time.                            |

## Example

```yaml
apiVersion: "cilium.io/v2"
kind: CiliumNetworkPolicy
metadata:
  name: allow-from-cluster-and-host
spec:
  endpointSelector:
    matchLabels:
      app: my-app
  ingress:
    - fromEntities:
        - cluster
        - host
```
