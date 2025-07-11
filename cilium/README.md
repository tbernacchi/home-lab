## Upgrade

```
helm upgrade --install cilium cilium/cilium --version v1.17.5 \
  --namespace kube-system \
  --set operator.replicas=1 \
  --set ipam.operator.clusterPoolIPv4PodCIDRList=10.42.0.0/16 \
  --set ipv4NativeRoutingCIDR=10.42.0.0/16 \
  --set ipv4.enabled=true \
  --set loadBalancer.mode=dsr \
  --set routingMode=native \
  --set autoDirectNodeRoutes=true \
  --set l2announcements.enabled=true \
  --set kubeProxyReplacement=true \
  --set k8sClientRateLimit.qps=50 \
  --set k8sClientRateLimit.burst=100 \
  --set k8sServiceHost=192.168.1.106 \
  --set k8sServicePort=6443 \
  --set l2announcements.leaseDuration=3s \
  --set l2announcements.leaseRenewDeadline=1s \
  --set l2announcements.leaseRetryPeriod=200ms \
  --set ingressController.Enabled=true \
  --set enable-bgp-control-plane.enabled=true \
  --set installCRDs=true
  ```

## Enable Prometheus

```
 helm upgrade cilium cilium/cilium --version v1.17.5 \
  --namespace kube-system \
  --reuse-values \
  --set prometheus.enabled=true \
  --set prometheus.port=9962
```

https://docs.cilium.io/en/stable/observability/grafana/

## Disable IPv6

```
helm upgrade cilium cilium/cilium --version v1.17.5 \
  --namespace kube-system \
  --reuse-values \
  --set ipv6.enabled=false
```

```
kubectl -n kube-system rollout restart daemonset cilium
```

```
systemctl restart k3s
```

## Enable Gateway-API

```
helm upgrade cilium cilium/cilium --version v1.17.5 \
  --namespace kube-system \
  --reuse-values \
  --set gatewayAPI.enabled=true
```

## Enable hubble flowVisibility

```
 helm upgrade cilium cilium/cilium --version v1.17.5 \ 
 --namespace kube-system \ 
 --reuse-values \ 
 --set hubble.flowVisibility=full 
 --set hubble.listenAddress=":4244"
```

```
cilium config view | grep "enable-gateway-api"
```

