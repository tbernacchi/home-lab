#!/usr/bin/env bash
# Cleans a Raspberry Pi node: removes containerd, broken kernels, and K3s.
# Usage: sudo ./prepare-node.sh

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Execute como root: sudo $0${NC}"
    exit 1
fi

echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Limpando nó Raspberry Pi${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"

# ── 1. Remove containerd manual ──────────────────────────────
echo -e "\n${YELLOW}[1/3] Removendo containerd...${NC}"
systemctl stop containerd 2>/dev/null || true
systemctl disable containerd 2>/dev/null || true
rm -f /usr/local/bin/containerd
find /etc/systemd/system -name "containerd*" -delete 2>/dev/null || true
systemctl daemon-reload

# ── 2. Remove kernel genérico quebrado (se existir) ──────────
echo -e "\n${YELLOW}[2/3] Limpando pacotes quebrados...${NC}"
echo -e "Kernel ativo: ${GREEN}$(uname -r)${NC}"

for pkg in $(dpkg -l | awk '/linux-image-unsigned.*generic/{print $2}'); do
    echo -e "Removendo kernel genérico: ${YELLOW}${pkg}${NC}"
    dpkg --purge --force-remove-reinstreq "$pkg" || true
    ver="${pkg#linux-image-unsigned-}"
    [[ -d "/lib/modules/${ver}" ]] && rm -rf "/lib/modules/${ver}"
done

apt-get -f install -y

# ── 3. Remove K3s se existir ─────────────────────────────────
echo -e "\n${YELLOW}[3/3] Removendo K3s (se existir)...${NC}"
systemctl stop k3s 2>/dev/null || true
systemctl stop k3s-agent 2>/dev/null || true

if [[ -x /usr/local/bin/k3s-uninstall.sh ]]; then
    /usr/local/bin/k3s-uninstall.sh
elif [[ -x /usr/local/bin/k3s-agent-uninstall.sh ]]; then
    /usr/local/bin/k3s-agent-uninstall.sh
else
    rm -f /usr/local/bin/k3s /usr/local/bin/k3s-agent
    rm -rf /var/lib/rancher /etc/rancher /var/lib/cni /opt/cni
    rm -f /etc/systemd/system/k3s.service /etc/systemd/system/k3s-agent.service
    systemctl daemon-reload
fi

iptables -F 2>/dev/null || true
iptables -t nat -F 2>/dev/null || true
iptables -t mangle -F 2>/dev/null || true

echo -e "\n${GREEN}✓ Nó limpo. Pronto para nova instalação K3s.${NC}"
