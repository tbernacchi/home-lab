# OCI Master Node

K3s master running on Oracle Cloud Infrastructure (OCI) with etcd, connected to Raspberry Pi workers via Tailscale.

## Architecture

| Node | Role | LAN IP | Tailscale IP |
|---|---|---|---|
| OCI instance | master (etcd) | `<OCI_PUBLIC_IP>` | `<OCI_TS_IP>` |
| raspberrypi4-1 | worker | 192.168.1.102 | `<TS_IP_PI1>` |
| raspberrypi4-3 | worker | 192.168.1.103 | `<TS_IP_PI3>` |
| raspberrypi4-4 | worker | 192.168.1.105 | `<TS_IP_PI4>` |
| raspberrypi4-5 | worker | 192.168.1.106 | `<TS_IP_PI5>` |

**Why OCI:** eliminates SD card I/O issues (Slow SQL / kine compaction) that caused master instability. etcd on SSD is stable.

**Why Tailscale:** all nodes communicate via encrypted WireGuard mesh. API server (6443) never exposed to internet. Workers join master via Tailscale IP.

---

## OCI Instance Setup

### 1. Create instance

- Shape: VM.Standard.E2.2 (2 OCPU, 16GB RAM)
- OS: Ubuntu 24.04
- Storage: 45GB SSD
- **Check "Assign a public IPv4 address"** during creation
- Add your SSH public key

### 2. Network (Security List)

Allow inbound:
- TCP 22 (SSH) from your IP
- UDP 41641 (Tailscale direct connections) — optional, Tailscale works via relay without it

Route Table must have: `0.0.0.0/0 → Internet Gateway`

### 3. Kernel modules

```bash
sudo modprobe br_netfilter overlay xt_TPROXY xt_socket

cat <<EOF | sudo tee /etc/modules-load.d/k3s.conf
br_netfilter
overlay
xt_TPROXY
xt_socket
EOF

cat <<EOF | sudo tee /etc/sysctl.d/99-k3s.conf
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF

sudo sysctl --system
```

### 4. Tailscale

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
tailscale ip -4  # note this IP → OCI_TS_IP
```

### 5. Install k3s master

```bash
OCI_TS_IP=$(tailscale ip -4)

curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=v1.35.5+k3s1 sh -s - \
  --cluster-init \
  --disable traefik \
  --flannel-backend none \
  --disable-kube-proxy \
  --node-ip $OCI_TS_IP \
  --advertise-address $OCI_TS_IP \
  --tls-san $OCI_TS_IP \
  --cluster-cidr 10.42.0.0/16 \
  --service-cidr 10.43.0.0/16
```

**Note:** use `INSTALL_K3S_VERSION` env var, NOT `--version` flag (causes startup failure).

### 6. Fix kubeconfig

```bash
sudo sed -i "s|https://127.0.0.1:6443|https://${OCI_TS_IP}:6443|g" /etc/rancher/k3s/k3s.yaml
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
```

### 7. Remove control-plane taints (needed while no workers)

```bash
kubectl taint nodes --all node-role.kubernetes.io/control-plane:NoSchedule- 2>/dev/null || true
kubectl taint nodes --all node-role.kubernetes.io/master:NoSchedule- 2>/dev/null || true
```

### 8. Firewall — allow Tailscale traffic

```bash
sudo iptables -I INPUT -i tailscale0 -j ACCEPT
sudo iptables -I INPUT -i tailscale0 -p tcp --dport 6443 -j ACCEPT
```

### 9. Install Cilium (VXLAN tunnel — required for cross-network)

```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
helm repo add cilium https://helm.cilium.io/
helm repo update

helm install cilium cilium/cilium --version v1.17.5 \
  --namespace kube-system \
  --set operator.replicas=1 \
  --set ipam.operator.clusterPoolIPv4PodCIDRList=10.42.0.0/16 \
  --set kubeProxyReplacement=true \
  --set k8sServiceHost=${OCI_TS_IP} \
  --set k8sServicePort=6443 \
  --set tunnelProtocol=vxlan \
  --set autoDirectNodeRoutes=false
```

### 10. Get node token

```bash
sudo cat /var/lib/rancher/k3s/server/node-token
```

---

## Adding Worker Nodes (Raspberry Pi)

### On each Pi worker:

```bash
# 1. Install Tailscale
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up  # authenticate in browser (same tailnet as OCI)
NODE_TS_IP=$(tailscale ip -4)
echo "Tailscale IP: $NODE_TS_IP"

# 2. Uninstall old k3s (if was server/master use k3s-uninstall, if was agent use k3s-agent-uninstall)
sudo k3s-uninstall.sh 2>/dev/null || true
sudo k3s-agent-uninstall.sh 2>/dev/null || true

# 3. Join cluster — pass TOKEN literally, not as variable (avoids "not authorized" error)
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=v1.35.5+k3s1 \
  K3S_URL=https://<OCI_TS_IP>:6443 \
  K3S_TOKEN=<TOKEN_LITERAL> \
  sh -s - \
  --node-ip $NODE_TS_IP
```

**Notes:**
- Install script hangs at "Starting k3s-agent" for 30-60s while connecting via Tailscale — this is normal
- `not authorized` error = `$K3S_TOKEN` env var not set, pass token value literally
- If node had `flannel-backend: none` in `/etc/rancher/k3s/config.yaml` → remove it before joining (`sudo rm /etc/rancher/k3s/config.yaml`)
- Old master (previously running k3s server) joins as worker with `k3s-uninstall.sh` first

---

## Managing from Mac

```bash
# Install Tailscale (menu bar app, low resource usage)
brew install tailscale
sudo tailscale up

# Copy kubeconfig from OCI
scp ubuntu@<OCI_PUBLIC_IP>:/etc/rancher/k3s/k3s.yaml ~/.kube/config-oci
sed -i '' "s|https://127.0.0.1:6443|https://<OCI_TS_IP>:6443|g" ~/.kube/config-oci
export KUBECONFIG=~/.kube/config-oci
kubectl get nodes
```

With Tailscale on Mac, SSH via `ssh ubuntu@<OCI_TS_IP>` — no public port 22 needed.
