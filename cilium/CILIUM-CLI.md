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
cilium monitor --type l7

# Monitoring events L7 (HTTP, DNS)
cilium monitor --type l7

# Monitor dropped packages
cilium monitor --type drop

# Logs of policies applied
cilium monitor --type policy-verdict
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

# 📘 Cilium CLI – Useful Commands

A collection of commonly used `cilium` CLI commands for troubleshooting, observability, and network policy management.

| Command | Description |
|---------|-------------|
| `cilium status` | Shows the overall status of the Cilium agent. |
| `cilium endpoint list` | Lists all endpoints managed by Cilium. |
| `cilium endpoint get <id>` | Displays detailed information about a specific endpoint. |
| `cilium bpf ct list` | Lists BPF connection tracking (CT) table entries. |
| `cilium bpf tunnel list` | Shows the BPF tunnels used for inter-node communication. |
| `cilium bpf egress list` | Lists BPF egress gateway rules (if configured). |
| `cilium bpf ipcache list` | Shows the IP-to-identity cache maintained by Cilium. |
| `cilium bpf nat list` | Displays NAT BPF map entries. |
| `cilium bpf recorder list` | Lists packet capture sessions (recorder feature). |
| `cilium policy get` | Displays all active network policies. |
| `cilium policy trace --src-pod <pod> --dst-pod <pod>` | Traces policy enforcement between source and destination pods. |
| `cilium identity list` | Lists all known Cilium security identities. |
| `cilium identity get <id>` | Shows details for a specific identity. |
| `cilium service list` | Lists all services managed by Cilium (with internal load balancing). |
| `cilium node list` | Shows all cluster nodes known to Cilium. |
| `cilium config` | Prints the current Cilium agent configuration. |
| `cilium hubble status` | Displays the current status of Hubble. |
| `cilium hubble enable` | Enables Hubble (observability component). |
| `cilium hubble observe` | Streams real-time network flow events (like `tcpdump`). |
| `cilium clustermesh status` | Shows the status of ClusterMesh (multi-cluster support). |
