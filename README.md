## K3S

```bash
export K3S_KUBECONFIG_MODE="644"
export INSTALL_K3S_EXEC=" --flannel-backend=none --disable-network-policy --disable servicelb --disable traefik" 
curl -sfL https://get.k3s.io | sh -
```
[https://k3s.io/](https://k3s.io/)

## Cilium 

```bash
helm install cilium cilium/cilium --version v1.15.6 \
  --namespace kube-system \
  --set operator.replicas=1 \
  --set ipam.operator.clusterPoolIPv4PodCIDRList=10.42.0.0/16 \
  --set ipv4.enabled=true \
  --set kubeProxyReplacement=strict \
  --set k8sServiceHost=192.168.1.106 \
  --set k8sServicePort=6443 \
  --set tunnel=disabled \
  --set routingMode=native \
  --set autoDirectNodeRoutes=true
```
* Be attention to your `k8sServicePort`, which it's the interface advertised of your `k3s`.

[https://docs.cilium.io/en/stable/installation/k8s-install-helm/](https://docs.cilium.io/en/stable/installation/k8s-install-helm/)

After everything it's up and running I've changed `k3s` to use etcd as a data store.

I've added `--cluster-init` on `/etc/systemd/system/k3s.service`

```bash
ExecStart=/usr/local/bin/k3s \
    server \
        '--cluster-init' \
	'--flannel-backend=none' \
	'--disable-network-policy' \
	'--disable' \
	'servicelb' \
	'--disable' \
	'traefik' \
```

```bash
systemctl daemon-reload
systemctl restart k3s
```

[--cluster-init](https://docs.k3s.io/cli/server#:~:text=join%20a%20cluster-,%2D%2Dcluster%2Dinit,-K3S_CLUSTER_INIT)

