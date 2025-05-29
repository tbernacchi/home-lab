```
kubectl patch deployment argocd-redis -n argocd --patch "$(cat patch-argocd-redis.yaml)"
```
