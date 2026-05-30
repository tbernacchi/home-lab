#!/bin/bash
#
# Destrói o K3s no master (e opcionalmente nos workers via SSH) e reinstala o servidor do zero.
# Execute no nó que será o control-plane (master).
#
# Uso:
#   sudo ./reset-k3s-cluster.sh --version v1.33.6+k3s1
#   sudo ./reset-k3s-cluster.sh --version v1.34.3+k3s1 --workers 192.168.1.105,192.168.1.103
#   sudo ./reset-k3s-cluster.sh --version latest --workers 192.168.1.105 --ssh-user root
#
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

K3S_VERSION=""
WORKERS=""
SSH_USER="root"
SSH_OPTS="-o StrictHostKeyChecking=accept-new -o ConnectTimeout=10"
UNINSTALL_ONLY=false
NODE_IP=""

show_help() {
    echo -e "${BLUE}Uso:${NC} sudo $0 --version VERSION [opções]"
    echo ""
    echo -e "${YELLOW}Obrigatório:${NC}"
    echo "  --version VERSION   Versão K3s (ex: v1.33.6+k3s1) ou latest"
    echo ""
    echo -e "${YELLOW}Opcional:${NC}"
    echo "  --workers IP1,IP2   IPs dos agents; roda desinstalação remota via SSH"
    echo "  --ssh-user USER     Usuário SSH (padrão: root)"
    echo "  --node-ip IP        IP do nó (evita pegar interface errada)"
    echo "  --uninstall-only    Só remove, não reinstala"
    echo "  -h, --help          Ajuda"
    echo ""
    echo -e "${YELLOW}Depois:${NC} nos workers, use reset-and-join-node.sh com a mesma versão."
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)
            K3S_VERSION="${2:-}"
            shift 2
            ;;
        --workers)
            WORKERS="${2:-}"
            shift 2
            ;;
        --ssh-user)
            SSH_USER="${2:-}"
            shift 2
            ;;
        --node-ip)
            NODE_IP="${2:-}"
            shift 2
            ;;
        --uninstall-only)
            UNINSTALL_ONLY=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo -e "${RED}Opção desconhecida: $1${NC}"
            show_help
            exit 1
            ;;
    esac
done

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Execute como root: sudo $0 ...${NC}"
    exit 1
fi

if [[ -z "$K3S_VERSION" ]] && [[ "$UNINSTALL_ONLY" == false ]]; then
    echo -e "${RED}Falta --version${NC}"
    show_help
    exit 1
fi

echo -e "${RED}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${RED}║  ATENÇÃO: isso APAGA o cluster K3s neste nó (e nos workers) ║${NC}"
echo -e "${RED}╚════════════════════════════════════════════════════════════╝${NC}"
echo -e "Versão a instalar: ${GREEN}${K3S_VERSION}${NC}"
[[ -n "$WORKERS" ]] && echo -e "Workers (SSH):     ${YELLOW}${WORKERS}${NC}"
read -r -p "Digite DESTRUIR para continuar: " confirm
if [[ "$confirm" != "DESTRUIR" ]]; then
    echo -e "${YELLOW}Cancelado.${NC}"
    exit 0
fi

uninstall_remote_worker() {
    local ip="$1"
    echo -e "\n${BLUE}→ Worker ${ip}${NC}"
    ssh $SSH_OPTS "${SSH_USER}@${ip}" 'bash -s' <<'REMOTE' || true
set -e
sudo systemctl stop k3s-agent 2>/dev/null || true
sudo systemctl stop k3s 2>/dev/null || true
if [[ -x /usr/local/bin/k3s-agent-uninstall.sh ]]; then
    sudo /usr/local/bin/k3s-agent-uninstall.sh
elif [[ -x /usr/local/bin/k3s-uninstall.sh ]]; then
    sudo /usr/local/bin/k3s-uninstall.sh
else
    sudo rm -f /usr/local/bin/k3s /usr/local/bin/k3s-agent
    sudo rm -rf /var/lib/rancher /etc/rancher
    sudo rm -f /etc/systemd/system/k3s.service /etc/systemd/system/k3s-agent.service
    sudo systemctl daemon-reload
fi
echo "Worker limpo."
REMOTE
}

if [[ -n "$WORKERS" ]]; then
    echo -e "\n${YELLOW}[1/3] Desinstalando agents (SSH)...${NC}"
    IFS=',' read -ra WARR <<< "$WORKERS"
    for w in "${WARR[@]}"; do
        w=$(echo "$w" | xargs)
        [[ -z "$w" ]] && continue
        uninstall_remote_worker "$w" || echo -e "${YELLOW}⚠ Falha em ${w} (verifique SSH)${NC}"
    done
fi

echo -e "\n${YELLOW}[2/3] Desinstalando K3s neste nó (master)...${NC}"
systemctl stop k3s 2>/dev/null || true
systemctl stop k3s-agent 2>/dev/null || true

if [[ -x /usr/local/bin/k3s-uninstall.sh ]]; then
    /usr/local/bin/k3s-uninstall.sh
else
    echo -e "${YELLOW}k3s-uninstall.sh não encontrado; remoção manual...${NC}"
    rm -f /usr/local/bin/k3s /usr/local/bin/k3s-agent /usr/local/bin/kubectl /usr/local/bin/crictl /usr/local/bin/ctr
    rm -rf /var/lib/rancher /etc/rancher /var/lib/cni /opt/cni 2>/dev/null || true
    rm -f /etc/systemd/system/k3s.service /etc/systemd/system/k3s-agent.service
    systemctl daemon-reload
    systemctl reset-failed 2>/dev/null || true
fi

iptables -F 2>/dev/null || true
iptables -t nat -F 2>/dev/null || true
iptables -t mangle -F 2>/dev/null || true

if [[ "$UNINSTALL_ONLY" == true ]]; then
    echo -e "\n${GREEN}✓ Desinstalação concluída. K3s removido.${NC}"
    exit 0
fi

echo -e "\n${YELLOW}[3/3] Instalando K3s server (cluster-init + flags do home-lab)...${NC}"

export K3S_KUBECONFIG_MODE="644"
# Alinhado ao README: etcd via --cluster-init, sem flannel/traefik/servicelb
# Flags do server (o instalador já usa o subcomando server neste nó)
NODE_IP_FLAGS=""
[[ -n "$NODE_IP" ]] && NODE_IP_FLAGS="--node-ip ${NODE_IP} --advertise-address ${NODE_IP}"
export INSTALL_K3S_EXEC="--cluster-init --flannel-backend=none --disable-network-policy --disable servicelb --disable traefik ${NODE_IP_FLAGS}"

if [[ "$K3S_VERSION" == "latest" ]]; then
    unset INSTALL_K3S_VERSION
    echo -e "${GREEN}Instalando última versão estável...${NC}"
    curl -sfL https://get.k3s.io | sh -
else
    export INSTALL_K3S_VERSION="$K3S_VERSION"
    echo -e "${GREEN}Instalando ${K3S_VERSION}...${NC}"
    curl -sfL https://get.k3s.io | sh -
fi

systemctl enable k3s 2>/dev/null || true
systemctl start k3s

sleep 5
if systemctl is-active --quiet k3s; then
    echo -e "\n${GREEN}✓ K3s server ativo.${NC}"
else
    echo -e "\n${RED}✗ k3s não subiu. Veja: journalctl -u k3s -e${NC}"
    exit 1
fi

TOKEN=$(cat /var/lib/rancher/k3s/server/node-token 2>/dev/null || echo "")
MASTER_IP=$(hostname -I | awk '{print $1}')

echo -e "\n${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}Próximos passos (workers):${NC}"
echo -e "  1. Em cada worker, rode reset-and-join-node.sh com a ${YELLOW}mesma versão${NC}:"
echo -e "     ${GREEN}./reset-and-join-node.sh --version ${K3S_VERSION} --master-ip ${MASTER_IP} --token <TOKEN>${NC}"
echo -e "  2. Token do nó:"
echo -e "     ${GREEN}sudo cat /var/lib/rancher/k3s/server/node-token${NC}"
if [[ -n "$TOKEN" ]]; then
    echo -e "     ${YELLOW}${TOKEN}${NC}"
fi
echo -e "  3. Kubeconfig (nesta máquina): ${GREEN}/etc/rancher/k3s/k3s.yaml${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
