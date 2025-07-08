# Cilium Components Overview

This document describes the responsibilities and roles of the two core components in a Cilium-based Kubernetes setup: `cilium-agent` and `cilium-operator`.

---

## 🧠 Cilium Agent (`cilium-agent`)

The `cilium-agent` runs **on every node** in the Kubernetes cluster. It is responsible for configuring the Linux kernel via **eBPF** and handling pod-level networking and policy enforcement.

### Key Responsibilities

| Area | Description |
|-------------------------|-----------------------------------------------------------------------------|
| 🧠 **eBPF Programs** | Loads and manages eBPF programs in the kernel to process network traffic |
| 📶 **Routing** | Handles L3/L4 routing between pods and nodes using eBPF |
| 🔒 **Network Policies** | Enforces `CiliumNetworkPolicy` (L3/L4/L7) at the pod level |
| 🌐 **DNS-aware Policies**| Applies rules based on FQDN or DNS domain names |
| 🔄 **L7 Proxy Integration** | Uses Envoy for L7 (e.g., HTTP) policy enforcement and observability |
| 👁️ **Observability** | Exposes flow logs, metrics, and integrates with Hubble |
| 📡 **IP Assignment (local)**| Assigns IPs to pods (in certain IPAM modes) |
| 🧩 **Identity Management (local)** | Resolves pod label → identity mappings locally |

> 🔹 In short: `cilium-agent` handles the **data plane** logic, applying policies and controlling traffic at the node level.

---

## ⚙️ Cilium Operator (`cilium-operator`)

The `cilium-operator` is a centralized controller running as a Kubernetes `Deployment`. It operates at the **control plane level**, coordinating global state and resources across the cluster.

### Key Responsibilities

| Area | Description |
|-------------------------------|-------------------------------------------------------------------------|
| 🧠 **IP Management (IPAM)** | Manages IP address blocks using ClusterPool, ENI, Azure IPAM modes |
| 📋 **CRD Watching** | Watches `CiliumNetworkPolicy`, `CiliumEndpoint`, `CiliumNode`, etc. |
| 🆔 **Identity Garbage Collection** | Cleans up unused security identities |
| 🚪 **NodePort / External IPs**| Handles NodePort or LoadBalancer logic (in some Cilium setups) |
| 🌐 **Kubernetes Integration** | Syncs node, service, and endpoint info with Kubernetes API |
| 🔐 **Encryption Coordination** | Manages encryption keys (for IPsec or WireGuard, if enabled) |
| 📥 **Endpoint Status Export** | Updates `CiliumEndpoint` status objects with detailed connection info |

> 🔹 In short: `cilium-operator` handles **cluster-wide control and state synchronization**, including IP management and CRD integration.

---

## 🔍 Side-by-Side Comparison

| Function | `cilium-agent` | `cilium-operator` |
|------------------------------|----------------------------------|--------------------------------|
| Runs on each node | ✅ | ❌ (centralized) |
| eBPF integration | ✅ | ❌ |
| Applies network policies | ✅ | ❌ |
| IPAM | 🔄 (depends on mode) | ✅ |
| Talks to Kubernetes API | Limited (via CRDs) | ✅ |
| Manages security identities | ✅ (local) + ❌ (GC) | ✅ (GC for unused identities) |
| Handles traffic | ✅ | ❌ |
| CRD control | Read-only | Reads & writes status |

---

## 📘 References

- [Cilium Documentation](https://docs.cilium.io/)
- [Cilium Architecture](https://docs.cilium.io/en/stable/architecture/)
- [GitHub – Cilium](https://github.com/cilium/cilium)

---
