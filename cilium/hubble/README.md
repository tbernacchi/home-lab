## Enable Hubble

```
cilium hubble enable
cilium hubble enable --ui
```

# Check 
```
cilium status
```

```
kubectl port-forward -n kube-system svc/hubble-ui 12000:80 --address 192.168.1.106
```
