# home-lab

> This is my personal Kubernetes setup for my home-lab running on my Raspberry Pi4 cluster.

## Core Components
- **[K3s](https://k3s.io/)** - Lightweight Kubernetes distribution perfect for IoT & Edge computing
- **[Cilium](https://docs.cilium.io/en/stable/installation/k8s-install-helm/)** - eBPF-based networking, observability & security

## Ingress Controller
- **[Traefik](https://doc.traefik.io/)** - Cloud native ingress controller for handling incoming traffic and routing requests

## Monitoring
- **[Prometheus](https://prometheus.io/)** - Metrics collection and storage
- **[Grafana](https://grafana.com/)** - Metrics visualization and dashboarding 
- **[AlertManager](https://prometheus.io/docs/alerting/latest/alertmanager/)** - Alerting and notifications

## GitOps
- **[Argo CD](https://argo-cd.readthedocs.io/en/stable/)** - Declarative continuous delivery
- **[Argo Workflows](https://argoproj.github.io/workflows/)** - Kubernetes-native workflow engine
- **[Argo Rollouts](https://argoproj.github.io/rollouts/)** - Progressive delivery controller

## Hand's on

## k3s

```bash
export K3S_KUBECONFIG_MODE="644"
export INSTALL_K3S_EXEC=" --flannel-backend=none --disable-network-policy --disable servicelb --disable traefik" 
curl -sfL https://get.k3s.io | sh -
```

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

[cluster-init](https://docs.k3s.io/cli/server#:~:text=join%20a%20cluster-,%2D%2Dcluster%2Dinit,-K3S_CLUSTER_INIT)   
[https://k3s.io/](https://k3s.io/)

## Cilium 

```bash
helm repo add cilium https://helm.cilium.io/
helm repo update
helm upgrade --install cilium cilium/cilium --version v1.15.6 \
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
  --set enable-bgp-control-plane.enabled=true
```

* Be attention to your `k8sServicePort`, which it's the interface advertised from your `k3s`.

```bash 
kubectl edit cm -n kube-system cilium-config
```

```bash
bpf-lb-sock-hostns-only: "true"
enable-host-legacy-routing: "true"
device: eth0
enable-bpf-masquerade: "true"
```

```bash
kubectl -n kube-system rollout restart ds/cilium
```

```bash
kubectl create -f cilium/CiliumL2AnnouncementPolicy-IPPool.yaml
```

[https://docs.cilium.io/en/stable/installation/k8s-install-helm/](https://docs.cilium.io/en/stable/installation/k8s-install-helm/)

## Certs 

Run [certificate.sh](certificate.sh) on certs folder.

```bash
./certificate.sh
Certificate request self-signature ok
subject=C = BR, ST = SP, L = Sao Paulo, O = MyKubernetes, CN = traefik.mykubernetes.com
secret/traefik-dashboard-cert created
```

Add your ca.crt to the system keychain. If you are using macOS:

```bash  
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ./ca.crt
```

## Monitoring

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
kubectl create namespace monitoring
helm install my-kube-prometheus-stack prometheus-community/kube-prometheus-stack --version 68.3.0 -n monitoring -f monitoring/prometheus-values.yaml
```

Setting my monitoring solution to reach at `/prometheus`, `/grafana` and `/alertmanager`.

```bash
kubectl patch prometheus my-kube-prometheus-stack-prometheus -n monitoring --type='json' -p='[{"op": "replace", "path": "/spec/externalUrl", "value": "https://traefik.mykubernetes.com/prometheus"}]'
kubectl patch prometheus my-kube-prometheus-stack-prometheus -n monitoring --type='json' -p='[{"op": "replace", "path": "/spec/routePrefix", "value": "/prometheus"}]'

kubectl patch alertmanager my-kube-prometheus-stack-alertmanager -n monitoring --type='json' -p='[{"op": "replace", "path": "/spec/externalUrl", "value": "https://traefik.mykubernetes.com/alertmanager"}]'
kubectl patch alertmanager my-kube-prometheus-stack-alertmanager -n monitoring --type='json' -p='[{"op": "replace", "path": "/spec/routePrefix", "value": "/alertmanager"}]'

kubectl set env deployment/my-kube-prometheus-stack-grafana -n monitoring GF_SERVER_SERVE_FROM_SUB_PATH=true
kubectl set env deployment/my-kube-prometheus-stack-grafana -n monitoring GF_SERVER_ROOT_URL=/grafana

# Add the secret to the monitoring namespace
kubectl get secret traefik-dashboard-cert -n traefik -o yaml | sed 's/namespace: traefik/namespace: monitoring/' | kubectl apply -f -
```

## Traefik

```bash
kubectl create namespace traefik
helm repo add traefik https://traefik.github.io/charts
helm repo update
helm install traefik traefik/traefik --namespace traefik --values traefik/values.yaml
kubectl create -f traefik/dashboard.yaml
```

[https://doc.traefik.io/traefik/getting-started/install-traefik/#use-the-helm-chart](https://doc.traefik.io/traefik/getting-started/install-traefik/#use-the-helm-chart)
[https://github.com/traefik/traefik-helm-chart/blob/master/traefik/values.yaml](https://github.com/traefik/traefik-helm-chart/blob/master/traefik/values.yaml)

