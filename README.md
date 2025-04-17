# home-lab

> This is my personal Kubernetes setup for my home-lab running on my Raspberry Pi4 cluster.

<div align=>
	<img align="center"  width="550px" src=/.github/assets/img/IMG_1624.png>
</div>

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

> For this setup I've disable `wlan0` interface and use only `eth0` for performance reasons.
I also disable `brcmfmac_wcc`, `brcmfmac`, `brcmutil` and `cfg80211` modules to avoid the `wlan0` interface to be used.

```bash
modprobe -r brcmfmac_wcc
modprobe -r brcmfmac
modprobe -r brcmutil
modprobe -r cfg80211

echo "blacklist brcmfmac_wcc" > /etc/modprobe.d/blacklist-brcmfmac.conf
echo "blacklist brcmfmac" >> /etc/modprobe.d/blacklist-brcmfmac.conf
shutdown -r now
```

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

#### Join nodes to the cluster

master node:

```bash 
cat /var/lib/rancher/k3s/server/node-token
K10d84e93e2b80dcb4340fa8445df1c7c818d8b97bdc0a9b5cf8ac6798f82d5e33f::server:0224f4ef28fb909b59f12d2804196d89
```

worker node:
```bash 
export K3S_TOKEN=K10d84e93e2b80dcb4340fa8445df1c7c818d8b97bdc0a9b5cf8ac6798f82d5e33f::server:0224f4ef28fb909b59f12d2804196d89
```

```bash 
echo $K3S_TOKEN
K10d84e93e2b80dcb4340fa8445df1c7c818d8b97bdc0a9b5cf8ac6798f82d5e33f::server:0224f4ef28fb909b59f12d2804196d89
```
```bash 
curl -sfL https://get.k3s.io | K3S_TOKEN=$K3S_TOKEN sh -s - agent --server https://192.168.1.106:6443
```

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

Add your `ca.crt` to the system keychain. If you are using macOS:

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

# Create the ingressroute for the monitoring namespace
kubectl create -f monitoring/ingressroute.yaml
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

## argo-workflow

```bash
kubectl create namespace argo
kubectl apply -n argo -f https://github.com/argoproj/argo-workflows/releases/download/v3.5.8/install.yaml
```

In this setup I've changed the [Base_HREF](https://argo-workflows.readthedocs.io/en/release-3.5/argo-server/#base-href) to `/argo/` to be able to reach the workflows UI at `/argo/`.

```bash
kubectl edit deploy/argo-server -n argo
```

```bash
- args: 
  - server
  - --auth-mode=server
  env:
  - name: BASE_HREF
    value: /argo/
```

Argo Workflows need a service account in the respective namespace where the workloads it's going to run order to work properly. This service account needs some permissions to manage workflows, interact with pods and etctera. You can find more info [here](https://argoproj.github.io/argo-workflows/service-accounts/).

```bash
kubectl get secret traefik-dashboard-cert -n traefik -o yaml | sed 's/namespace: traefik/namespace: argo/' | kubectl apply -f -
kubectl create -f argo/rbac.yaml
```


## argo-cd

To install argo-cd I've followed the [https://argo-cd.readthedocs.io/en/stable/getting_started/](https://argo-cd.readthedocs.io/en/stable/getting_started/).

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

For this installation I've managed the UI through Traefik to access on `traefik.mykubernetes.com/argocd`.

```bash
kubectl patch deployment argocd-server -n argocd --type='json' -p='[
  {
    "op": "replace",
    "path": "/spec/template/spec/containers/0/args",
    "value": [
      "/usr/local/bin/argocd-server",
      "--insecure",
      "--basehref=/argocd",
      "--rootpath=/argocd"
    ]
  }
]'
```

```bash
kubectl get deploy argocd-server -n argocd -o jsonpath='{.spec.template.spec.containers[0].args}' | jq
```

```bash
kubectl create -f argo-stack/argo-cd/ingressroute.yaml
```

Reference:
[https://argo-cd.readthedocs.io/en/latest/operator-manual/ingress/](https://argo-cd.readthedocs.io/en/latest/operator-manual/ingress/)

UI password: 

```
kubectl get secret/argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 --decode
```

-> argo-cd has an [issue](https://github.com/argoproj/argo-cd/issues/20790) using basehref with `/argocd`; 

Bug fix:

```bash
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.14.10/manifests/install.yaml
```
-> Don't forget to patch the deploment after the upgrade.

## argo-rollouts

To enable the argo-rollouts on the UI I've use this extension: https://github.com/argoproj-labs/rollout-extension

```bash
kubectl create namespace argo-rollouts
helm repo add argo-rollouts https://argoproj.github.io/argo-helm -n argo-rollouts
helm repo update
helm install argo-rollouts argo/argo-rollouts -n argo-rollouts --set dashboard.enabled=true
```

```bash
kubectl patch deployment argocd-server -n argocd --type='json' -p='
[
  {
    "op": "add",
    "path": "/spec/template/spec/initContainers",
    "value": [
      {
        "name": "rollout-extension",
        "image": "quay.io/argoprojlabs/argocd-extension-installer:v0.0.8",
        "env": [
          {
            "name": "EXTENSION_URL",
            "value": "https://github.com/argoproj-labs/rollout-extension/releases/download/v0.3.6/extension.tar"
          }
        ],
        "volumeMounts": [
          {
            "name": "extensions",
            "mountPath": "/tmp/extensions/"
          }
        ],
        "securityContext": {
          "runAsUser": 1000,
          "allowPrivilegeEscalation": false
        }
      }
    ]
  },
  {
    "op": "add",
    "path": "/spec/template/spec/volumes",
    "value": [
      {
        "name": "extensions",
        "emptyDir": {}
      }
    ]
  },
  {
    "op": "add",
    "path": "/spec/template/spec/containers/0/volumeMounts",
    "value": [
      {
        "name": "extensions",
        "mountPath": "/tmp/extensions/"
      }
    ]
  }
]'
```

## argo-image-updater

```bash
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj-labs/argocd-image-updater/master/manifests/install.yaml
```

We've to create a secret from Docker Hub registry to store the credentials for the image updater.

```
kubectl create secret docker-registry regcred \
  --namespace argocd \
  --docker-server=https://index.docker.io/v1/ \
  --docker-username=ambrosiaaaaa\
  --docker-password=token-xyz\
  --docker-email=myemail@gmail.com
```

Also we need a credentials for the GitHub registry.

```
kubectl create secret generic git-creds \
  -n argocd \
  --from-literal=username=myusername \
  --from-literal=password=token-xyz
```

Now we just need to "annotate" the application with the image updater.

```
kubectl get application -n argocd
NAME     SYNC STATUS   HEALTH STATUS
foobar   Synced        Healthy
```


```bash
kubectl annotate application foobar \
  argocd-image-updater.argoproj.io/credentials="docker.io=secret:dockerhub-secret" \
  argocd-image-updater.argoproj.io/image-list="ambrosiaaaaa/foobar-api" \
  argocd-image-updater.argoproj.io/update-strategy="semver" \
  argocd-image-updater.argoproj.io/write-back-method="git:secret:argocd/git-creds" \
  -n argocd
```

[https://argocd-image-updater.readthedocs.io/en/stable/](https://argocd-image-updater.readthedocs.io/en/stable/)
[update-strategies](https://argocd-image-updater.readthedocs.io/en/stable/basics/update-strategies/)
[git write-back method](https://argocd-image-updater.readthedocs.io/en/stable/basics/update-methods/#:~:text=no%20further%20configuration.-,git%20write%2Dback%20method,-%C2%B6)
[examples](https://argocd-image-updater.readthedocs.io/en/stable/examples/)
