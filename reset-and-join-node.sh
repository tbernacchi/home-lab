#!/bin/bash

# Script para resetar K3s antigo e adicionar nó ao cluster
# Execute este script no novo nó que deseja adicionar ao cluster
#
# Uso:
#   ./reset-and-join-node.sh [--version VERSION] [--master-ip IP] [--token TOKEN]
#
# Exemplo:
#   ./reset-and-join-node.sh --version v1.33.6+k3s1
#   ./reset-and-join-node.sh --version v1.33.6+k3s1 --master-ip 192.168.1.106 --token SEU_TOKEN

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Variáveis padrão
K3S_VERSION=""
MASTER_IP=""
K3S_TOKEN=""
K3S_PORT="6443"

# Função de ajuda
show_help() {
    echo -e "${BLUE}Uso:${NC} $0 [OPÇÕES]\n"
    echo -e "${YELLOW}Opções:${NC}"
    echo -e "  --version VERSION    Versão do K3s a instalar (ex: v1.33.6+k3s1) ou 'latest'"
    echo -e "  --master-ip IP       IP do servidor master (padrão: 192.168.1.106)"
    echo -e "  --token TOKEN        Token do cluster (obtido do master)"
    echo -e "  --port PORT          Porta do servidor master (padrão: 6443)"
    echo -e "  -h, --help           Mostrar esta ajuda\n"
    echo -e "${YELLOW}Exemplos:${NC}"
    echo -e "  $0 --version v1.33.6+k3s1"
    echo -e "  $0 --version v1.33.6+k3s1 --master-ip 192.168.1.106 --token SEU_TOKEN\n"
    echo -e "${YELLOW}Nota:${NC} Para obter o token, execute no servidor master:"
    echo -e "  ${GREEN}sudo cat /var/lib/rancher/k3s/server/node-token${NC}\n"
}

# Processar argumentos
while [[ $# -gt 0 ]]; do
    case $1 in
        --version)
            K3S_VERSION="$2"
            shift 2
            ;;
        --master-ip)
            MASTER_IP="$2"
            shift 2
            ;;
        --token)
            K3S_TOKEN="$2"
            shift 2
            ;;
        --port)
            K3S_PORT="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo -e "${RED}Erro: Opção desconhecida: $1${NC}\n"
            show_help
            exit 1
            ;;
    esac
done

echo -e "${BLUE}╔════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Reset e Join de Nó ao Cluster K3s               ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════╝\n"

# ============================================
# PARTE 1: REMOVER K3S ANTIGO
# ============================================
echo -e "${YELLOW}=== PARTE 1: Removendo K3s antigo ===${NC}\n"

# Parar serviços
echo -e "${GREEN}[1/7]${NC} Parando serviços K3s..."
sudo systemctl stop k3s 2>/dev/null || true
sudo systemctl stop k3s-agent 2>/dev/null || true
echo -e "  ${GREEN}✓${NC} Serviços parados\n"

# Desabilitar serviços
echo -e "${GREEN}[2/7]${NC} Desabilitando serviços..."
sudo systemctl disable k3s 2>/dev/null || true
sudo systemctl disable k3s-agent 2>/dev/null || true
echo -e "  ${GREEN}✓${NC} Serviços desabilitados\n"

# Remover binários
echo -e "${GREEN}[3/7]${NC} Removendo binários..."
sudo rm -f /usr/local/bin/k3s
sudo rm -f /usr/local/bin/k3s-agent
sudo rm -f /usr/local/bin/kubectl
sudo rm -f /usr/local/bin/crictl
sudo rm -f /usr/local/bin/ctr
echo -e "  ${GREEN}✓${NC} Binários removidos\n"

# Remover dados e configurações
echo -e "${GREEN}[4/7]${NC} Removendo dados e configurações..."
echo -e "  ${YELLOW}Removendo /var/lib/rancher...${NC}"
sudo rm -rf /var/lib/rancher 2>&1 | grep -v "cannot remove" | grep -v "Structure needs cleaning" | grep -v "Bad message" || true

# Se ainda existir, tentar método alternativo
if [ -d "/var/lib/rancher" ]; then
    echo -e "  ${YELLOW}⚠ Alguns arquivos problemáticos detectados, tentando método alternativo...${NC}"
    # Tentar remover com find (mais robusto)
    sudo find /var/lib/rancher -delete 2>&1 | grep -v "cannot remove" | grep -v "Structure needs cleaning" | grep -v "Bad message" || true
    # Se ainda existir, renomear para remover depois
    if [ -d "/var/lib/rancher" ]; then
        sudo mv /var/lib/rancher /var/lib/rancher.old.$(date +%s) 2>/dev/null || true
        echo -e "  ${YELLOW}⚠ Diretório renomeado para remoção posterior${NC}"
    fi
fi

sudo rm -rf /etc/rancher 2>&1 | grep -v "cannot remove" || true
sudo rm -rf /var/lib/cni 2>&1 | grep -v "cannot remove" || true
sudo rm -rf /opt/cni 2>&1 | grep -v "cannot remove" || true
echo -e "  ${GREEN}✓${NC} Dados removidos (alguns arquivos problemáticos podem ter sido ignorados)\n"

# Remover arquivos systemd
echo -e "${GREEN}[5/7]${NC} Removendo arquivos systemd..."
sudo rm -f /etc/systemd/system/k3s.service
sudo rm -f /etc/systemd/system/k3s-agent.service
sudo rm -f /etc/systemd/system/k3s*.service
sudo systemctl daemon-reload
sudo systemctl reset-failed
echo -e "  ${GREEN}✓${NC} Arquivos systemd removidos\n"

# Limpar iptables
echo -e "${GREEN}[6/7]${NC} Limpando iptables..."
sudo iptables -F 2>/dev/null || true
sudo iptables -t nat -F 2>/dev/null || true
sudo iptables -t mangle -F 2>/dev/null || true
sudo iptables -X 2>/dev/null || true
echo -e "  ${GREEN}✓${NC} iptables limpo\n"

# Verificar processos
echo -e "${GREEN}[7/7]${NC} Verificando processos restantes..."
if pgrep -x k3s > /dev/null; then
    echo -e "  ${YELLOW}⚠${NC} Processos K3s ainda rodando, finalizando..."
    sudo pkill -9 k3s 2>/dev/null || true
    sleep 2
fi
echo -e "  ${GREEN}✓${NC} Nenhum processo K3s encontrado\n"

echo -e "${GREEN}✓✓✓ K3s antigo removido com sucesso! ✓✓✓${NC}\n"

# ============================================
# PARTE 2: ADICIONAR NÓ AO CLUSTER
# ============================================
echo -e "${YELLOW}=== PARTE 2: Adicionando nó ao cluster ===${NC}\n"

# IP do servidor master (padrão se não fornecido)
if [ -z "$MASTER_IP" ]; then
    MASTER_IP="${K3S_MASTER_IP:-192.168.1.106}"
fi

# Solicitar versão se não foi fornecida
if [ -z "$K3S_VERSION" ]; then
    echo -e "${YELLOW}Versão do K3s não especificada.${NC}"
    echo -e "${YELLOW}Para verificar a versão do master, execute:${NC}"
    echo -e "  ${GREEN}kubectl get nodes -o wide${NC}\n"
    read -p "Digite a versão do K3s (ex: v1.33.6+k3s1) ou deixe em branco para usar a versão mais recente: " K3S_VERSION
    
    # Se deixou em branco ou digitou "latest", usar versão mais recente
    if [ -z "$K3S_VERSION" ] || [ "$K3S_VERSION" = "latest" ]; then
        K3S_VERSION="latest"
        echo -e "  ${GREEN}✓${NC} Usando versão mais recente do K3s\n"
    fi
fi

# Solicitar IP do master se não foi fornecido
if [ -z "$MASTER_IP" ] || [ "$MASTER_IP" = "192.168.1.106" ]; then
    read -p "IP do servidor master [${MASTER_IP}]: " input_ip
    MASTER_IP="${input_ip:-$MASTER_IP}"
fi

# Solicitar token se não foi fornecido
if [ -z "$K3S_TOKEN" ]; then
    echo -e "${YELLOW}Para obter o token, execute no servidor master:${NC}"
    echo -e "  ${GREEN}sudo cat /var/lib/rancher/k3s/server/node-token${NC}\n"
    read -p "Cole o token aqui: " K3S_TOKEN
    
    if [ -z "$K3S_TOKEN" ]; then
        echo -e "${RED}✗ Erro: Token não fornecido. Abortando.${NC}"
        exit 1
    fi
fi

echo -e "\n${BLUE}Configuração:${NC}"
if [ "$K3S_VERSION" = "latest" ]; then
    echo -e "  Versão K3s: ${GREEN}mais recente${NC}"
else
    echo -e "  Versão K3s: ${K3S_VERSION}"
fi
echo -e "  Master IP: ${MASTER_IP}"
echo -e "  Porta: ${K3S_PORT}"
echo -e "  Token: ${K3S_TOKEN:0:20}... (oculto)\n"

read -p "Continuar com a instalação? (y/N): " confirm
if [[ ! $confirm =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Instalação cancelada.${NC}"
    exit 0
fi

echo -e "\n${GREEN}Instalando K3s como agente...${NC}\n"

# Configurações do K3s para agente
# Nota: Flags de desabilitação (--disable-*) são apenas para o servidor
# O agente apenas se conecta ao servidor e segue suas configurações
export K3S_URL="https://${MASTER_IP}:${K3S_PORT}"
export K3S_TOKEN="${K3S_TOKEN}"
export INSTALL_K3S_EXEC=""

# Instalar K3s com versão específica (se não for "latest")
if [ "$K3S_VERSION" != "latest" ]; then
    export INSTALL_K3S_VERSION="${K3S_VERSION}"
    echo -e "${GREEN}Instalando K3s versão ${K3S_VERSION}...${NC}"
else
    echo -e "${GREEN}Instalando K3s versão mais recente...${NC}"
fi

if ! curl -sfL https://get.k3s.io | sh -; then
    echo -e "${RED}✗ Erro ao instalar K3s${NC}"
    exit 1
fi

echo -e "\n${GREEN}✓ K3s instalado com sucesso!${NC}\n"

# Verificar status
echo -e "${GREEN}Aguardando registro no cluster...${NC}"
sleep 10

# Verificar se o serviço está rodando
if sudo systemctl is-active --quiet k3s-agent; then
    echo -e "  ${GREEN}✓${NC} Serviço k3s-agent está rodando\n"
else
    echo -e "  ${YELLOW}⚠${NC} Serviço k3s-agent não está rodando. Verifique com: ${GREEN}sudo systemctl status k3s-agent${NC}\n"
fi

echo -e "${YELLOW}Nota:${NC} Este é um nó agente, não um servidor master."
echo -e "${YELLOW}Para verificar o status do nó no cluster, execute no servidor master:${NC}"
echo -e "  ${GREEN}kubectl get nodes${NC}\n"

echo -e "\n${BLUE}╔════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  ✓✓✓ Concluído com sucesso! ✓✓✓                   ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════╝${NC}\n"

echo -e "${YELLOW}Lembrete:${NC}"
echo -e "  - Se você desabilitou wlan0 no master, faça o mesmo neste nó"
echo -e "  - O Cilium será configurado automaticamente"
echo -e "  - Verifique o status no master com: ${GREEN}kubectl get nodes${NC}\n"
