## NetworkPolicies block kubelet health probes (Cilium)

**Symptom:** after a fresh install, `argocd-application-controller`,
`argocd-repo-server`, `argocd-notifications-controller` stay `CrashLoopBackOff`
or perpetually `0/1 Not Ready`. `kubectl describe pod` shows
`Readiness/Liveness probe failed: context deadline exceeded` — but `curl`ing
the same healthz port from another pod works instantly. `argocd-server` is
fine.

**Cause:** the upstream `v2.14.10` install manifest ships a per-component
`NetworkPolicy` for each of these (plus `argocd-image-updater`'s own
`allow-metrics-traffic` policy). Their ingress rules use
`from: [{namespaceSelector: {}}]` or restrict to specific pod selectors —
under Cilium's strict enforcement this does **not** include host-originated
traffic (kubelet's probes run in the host network namespace, not as a pod).
Cilium silently drops the probe request; there's no portable way to allow
"host" as a source in a plain `NetworkPolicy` (`CiliumNetworkPolicy`'s
`fromEntities: [host]` would work but these are vanilla `NetworkPolicy`
objects). `argocd-server-network-policy` doesn't have this problem — its rule
is a wide-open `ingress: - {}`.

**Fix:** delete the restrictive policies (matches `argocd-server`'s existing
unrestricted pattern — this cluster doesn't otherwise rely on pod-level
network segmentation):
```bash
kubectl delete networkpolicy -n argocd \
  argocd-application-controller-network-policy \
  argocd-repo-server-network-policy \
  argocd-notifications-controller-network-policy \
  allow-metrics-traffic
```

Also bumped `limitrange.yaml`'s default CPU limit from `500m` to `1000m` —
`500m` forces Go's `GOMAXPROCS=1` on these components, which was a red
herring during 2026-07-22's diagnosis (didn't actually fix the crash loop,
the NetworkPolicy was the real cause) but is still worth the higher ceiling
on constrained ARM hardware.

## Patch annotion on argocd-redis

```
kubectl patch deployment argocd-redis -n argocd --patch "$(cat patch-argocd-redis.yaml)"
```

## Datadog's redis integration is reporting:

[{message: Authentication required}]

* ```configmap.yaml```;  
* ```clusterrole.yaml```;  
* ```role.yaml```;  
