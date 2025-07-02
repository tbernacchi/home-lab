# eBPF Exam Study Guide

This guide summarizes key concepts from the book _Learning eBPF_ by Liz Rice. It focuses on the role of eBPF in Cilium, core benefits of eBPF, and comparisons with iptables-based platforms.

---

## 📘 Topics Covered

### 1. Understand the Role of eBPF in Cilium

- Cilium is a cloud-native networking, security, and observability platform built entirely on eBPF.
- It replaces traditional tools like iptables and sidecar proxies by leveraging kernel-level visibility.
- eBPF allows Cilium to:
  - Enforce network policies per-pod and per-process.
  - Perform L3/L4 load balancing with near-zero overhead.
  - Monitor traffic, syscalls, and application behavior in real time.
- No changes to the application code or container configuration are required.

---

### 2. eBPF Key Benefits

- **High Performance**: eBPF runs in kernel space, reducing overhead by avoiding context switches.
- **Security**: Programs are verified before execution to ensure memory safety and prevent system crashes.
- **Observability**: Provides deep insights into system behavior (networking, files, syscalls, etc.).
- **Dynamic Instrumentation**: Programs can be attached/detached at runtime, no need to reboot.
- **Portability**: CO-RE (Compile Once, Run Everywhere) allows eBPF programs to run across multiple kernel versions.
- **Extensibility**: eBPF maps enable communication between user space and kernel programs.

---

### 3. eBPF-Based Platforms vs. iptables-Based Platforms

| Feature                    | eBPF-Based (e.g., Cilium)                          | iptables-Based                            |
|----------------------------|----------------------------------------------------|--------------------------------------------|
| Performance                | JIT compiled, runs in kernel                       | Slower, sequential rule matching           |
| Observability              | Built-in, full-stack insights                      | Requires external tools                    |
| Policy Enforcement         | Fine-grained, per-pod/process                      | Coarse-grained, IP/port-based              |
| Kubernetes Integration     | Native (via CNI + CRDs)                            | Indirect and less flexible                 |
| Dynamic Updates            | Real-time, no restart needed                       | Requires full reloads                      |
| Sidecar Dependency         | None                                               | Often required (e.g., service meshes)      |
| Attack Surface             | Smaller, enforced in kernel                        | Larger, depends on user-space components   |

---

## 📚 Source

These notes are based on:

- _Learning eBPF: Programming the Linux Kernel for Enhanced Observability, Networking, and Security_ by Liz Rice (O’Reilly, 2023)
- Chapters 1, 6, and 8 are particularly relevant

