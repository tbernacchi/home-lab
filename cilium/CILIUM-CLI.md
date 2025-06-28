# 📘 Cilium CLI Cheatsheet

Essential commands to install, test, monitor, and configure Cilium in Kubernetes clusters.

---

## 🛠️ Installation

```bash
# Install Cilium with default settings
cilium install
```

---

## ✅ Status Check

```bash
# Check if Cilium is healthy and running
cilium status
```

---

## 🔄 Connectivity Testing

```bash
# Run a full connectivity test across pods, namespaces, services, and DNS
cilium connectivity test
```

---

## 📱 Traffic Monitoring

```bash
# Monitor all L3-L7 traffic in real time
cilium monitor

# Filter only HTTP traffic
cilium monitor --type http
```

---

## 🔍 Resource Inspection

```bash
# List all Cilium-managed endpoints
cilium endpoint list

# List current security identities
cilium identity list

# Show applied network policies
cilium policy get
```

---

## ⚙️ Agent Configuration

```bash
# View current agent configuration
cilium config view

# Set a dynamic config (may require agent restart)
cilium config set enable-envoy-config true
```

---

## 🧹 Uninstallation

```bash
# Uninstall Cilium from the cluster
cilium uninstall
```

---

## 📌 Tips

* Use `--context <kube-context>` when managing multiple clusters.
* Combine with `kubectl get pods -n kube-system -l k8s-app=cilium` to debug Cilium pods.

---

> Maintained by Tadeu Bernacchi — For clusters using Cilium with Gateway API (e.g., HTTPRoute + observability setup).
