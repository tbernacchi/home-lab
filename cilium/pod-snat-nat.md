# SNAT vs NAT in Kubernetes (Pods Networking)

This document provides a complete overview of how **NAT**, **SNAT**, and **DNAT** work in Kubernetes, especially when applied to **pods** and their network traffic.

---

## 📘 What is NAT?

**NAT (Network Address Translation)** is a mechanism for rewriting the IP address (and sometimes port) of packets as they travel through a router or gateway. In Kubernetes, NAT is commonly used to allow:

- Pods to access the internet or external services (via **SNAT**)
- External clients to access services inside the cluster (via **DNAT**)

---

## 🔁 Types of NAT

### 🧭 SNAT – Source Network Address Translation

- **Modifies the source IP** of the packet.
- Typically applied when **pods send traffic outside the cluster**.
- Ensures that the return traffic knows where to go — through the node that owns the pod.

### 🎯 DNAT – Destination Network Address Translation

- **Modifies the destination IP** of the packet.
- Applied when **external traffic enters the cluster** (e.g., via LoadBalancer or NodePort).
- Allows routing traffic from the node to the appropriate pod.

---

## 📊 SNAT vs DNAT – Comparison Table

| Feature | SNAT (Source NAT) | DNAT (Destination NAT) |
|-----------------------------|----------------------------------------------------------|----------------------------------------------------------|
| 🎯 Translates | **Source IP address** | **Destination IP address** |
| 📤 Direction | **Outbound** – Pod → External destination | **Inbound** – External client → Pod |
| 🌐 Common Use Case | Pod accessing external services (e.g., Internet) | External access to a pod via NodePort or LoadBalancer |
| 🛡️ Purpose | Ensures return traffic is correctly routed back to node | Routes traffic to the correct pod inside the cluster |
| 🧠 Involved in | **Egress traffic** | **Ingress traffic** |
| 🔧 Example | Pod IP → Node IP → Internet | Node IP:Port → Pod IP:Port |
| ⚙️ Requires Configuration? | Usually automatic via CNI or iptables | Managed by Kubernetes Services |

---

## 🔀 Network Flow Diagrams

### 📤 Outbound Flow (Pod → External) — SNAT

```text
Pod (10.244.1.10)
│
▼
SNAT → Node (192.168.0.5)
│
▼
Internet / External API (e.g. 8.8.8.8)
```

✅ In this case, the **source IP** of the packet is rewritten from `10.244.1.10` to `192.168.0.5` so that the return traffic from the internet knows how to route back through the node.

---

### 📥 Inbound Flow (External → Pod) — DNAT

```text
Client (e.g. user hitting LoadBalancer IP)
│
▼
Node (192.168.0.5:30080)
│
▼
DNAT → Pod (10.244.1.10:8080)
```

✅ Here, the **destination IP/port** is rewritten so that the incoming request is forwarded to the actual pod behind the service.

---

## 🧱 Notes for CNI Plugins

- **Cilium**, **Calico**, and other CNI plugins often avoid SNAT for **intra-cluster** traffic (pod-to-pod), especially with **eBPF**.
- **SNAT is necessary** when pods communicate with external services.
- **DNAT is typically used** when exposing services through:
- `NodePort`
- `LoadBalancer`
- Ingress Controller (e.g., Envoy, NGINX)

---

## 📚 References

- [Kubernetes Networking Concepts](https://kubernetes.io/docs/concepts/cluster-administration/networking/)
- [Cilium NAT Documentation](https://docs.cilium.io/en/stable/network/nat/)
- [Calico NAT Reference](https://docs.tigera.io/calico/latest/networking/ip-addresses/nat)

---