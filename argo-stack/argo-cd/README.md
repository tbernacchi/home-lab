## Patch annotion on argocd-redis

```
kubectl patch deployment argocd-redis -n argocd --patch "$(cat patch-argocd-redis.yaml)"
```

## Datadog's redis integration is reporting:

[{message: Authentication required}]

* ```configmap.yaml```;  
* ```clusterrole.yaml```;  
* ```role.yaml```;  
