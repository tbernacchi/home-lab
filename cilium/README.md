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

## Troubleshooting

### Cilium DaemonSet restart breaks new TCP connections on workers (kubeProxyReplacement)

**Symptom:** after `helm upgrade` + `kubectl rollout restart ds/cilium`, some Cilium pods get stuck in `Init:CrashLoopBackOff`. Init container (`cilium-dbg config`) fails with:
```
dial tcp 192.168.1.106:6443: i/o timeout
```
Existing connections from k3s agent to API server still show `ESTABLISHED` — but new TCP connections to the API server time out.

**Cause:** with `kubeProxyReplacement=true`, Cilium installs socket-level eBPF hooks that intercept ALL new TCP connections, even from the host network namespace. When Cilium crashes or restarts, these hooks are left in a broken state. Existing keepalive connections survive because they were established before the hook broke. New connections are intercepted by stale eBPF and silently dropped — including the API server connection the init container needs to start.

**Fix:** reboot the affected worker nodes. On boot, eBPF state is cleared and Cilium initializes cleanly.
```bash
# identify which nodes have failing Cilium pods
kubectl get pod -n kube-system -l k8s-app=cilium -o wide

# reboot nodes with Init:CrashLoopBackOff
ssh root@<worker-ip> 'reboot'
```

**Prevention:** when upgrading Cilium, avoid restarting all pods simultaneously. Use `--set rollUpdatePods` or manually restart one node at a time.

---

### Force delete all Terminating pods

When nodes are NotReady for a long time, pods accumulate in `Terminating` state and block recovery. Force delete all of them:

```bash
kubectl get pods -A | grep Terminating | while read ns name rest; do
  kubectl patch pod $name -n $ns -p '{"metadata":{"finalizers":null}}' --type=merge 2>/dev/null
  kubectl delete pod $name -n $ns --force --grace-period=0 2>/dev/null
done
```

---

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

