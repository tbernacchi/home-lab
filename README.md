# home-lab

> This is my personal Kubernetes setup for my home lab running on Raspberry Pi4.

## Core Components
- **[K3s](https://k3s.io/)** - Lightweight Kubernetes distribution perfect for IoT & Edge computing
- **[Cilium](https://docs.cilium.io/en/stable/installation/k8s-install-helm/)** - eBPF-based networking, observability & security

## Monitoring Stack
- **[Prometheus](https://prometheus.io/)** - Metrics collection and storage
- **[Grafana](https://grafana.com/)** - Metrics visualization and dashboarding 
- **[AlertManager](https://prometheus.io/docs/alerting/latest/alertmanager/)** - Alerting and notifications

## GitOps
- **[Argo CD](https://argo.github.io/)** - Declarative continuous delivery
- **[Argo Workflows](https://argoproj.github.io/argo-workflows/)** - Kubernetes-native workflow engine
- **[Argo Rollouts](https://argoproj.github.io/argo-rollouts/)** - Progressive delivery controller

## Ingress Controller
- **[Traefik](https://doc.traefik.io/traefik/v3/providers/kubernetes-ingress/)** - Cloud native ingress controller for handling incoming traffic and routing requests

This setup provides a robust platform for running containerized applications with comprehensive monitoring, observability and deployment capabilities on Raspberry Pi hardware.

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
