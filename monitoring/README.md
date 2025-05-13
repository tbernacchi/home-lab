# UPDATE

```bash
 helm repo add prometheus-community https://prometheus-community.github.io/helm-charts -n monitoring
 helm repo update
 helm get values my-kube-prometheus-stack -n monitoring -o yaml > ~tadeu/home-lab/monitoring/values.yaml
helm upgrade my-kube-prometheus-stack prometheus-community/kube-prometheus-stack -n monitoring --version 72.3.0 -n monitoring -f ~tadeu/home-lab/monitoring/values.yaml
```

[Kube-Prometheus](https://artifacthub.io/packages/helm/bitnami/kube-prometheus)
