#!/bin/bash

# Script para restaurar backup do cluster K3s
# Execute este script no servidor master do cluster

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Verificar se está rodando como root ou com sudo
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Este script precisa ser executado como root ou com sudo${NC}"
    exit 1
fi

# Verificar argumento
if [ -z "$1" ]; then
    echo -e "${RED}Uso: $0 <arquivo-backup.tar.gz>${NC}"
    echo -e "${YELLOW}Exemplo: $0 k3s-backup-20240122-143000.tar.gz${NC}"
    exit 1
fi

BACKUP_FILE="$1"

if [ ! -f "$BACKUP_FILE" ]; then
    echo -e "${RED}Erro: Arquivo de backup não encontrado: ${BACKUP_FILE}${NC}"
    exit 1
fi

echo -e "${BLUE}╔════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Restore do Cluster K3s                            ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════╝\n"

echo -e "${RED}⚠ ATENÇÃO: Este processo irá restaurar o backup e pode sobrescrever dados existentes!${NC}\n"
read -p "Tem certeza que deseja continuar? (digite 'sim' para confirmar): " confirm

if [ "$confirm" != "sim" ]; then
    echo -e "${YELLOW}Restore cancelado.${NC}"
    exit 0
fi

# Diretório temporário para extrair backup
RESTORE_DIR="./k3s-restore-$(date +%Y%m%d-%H%M%S)"
mkdir -p "${RESTORE_DIR}"

echo -e "\n${GREEN}[1/4]${NC} Extraindo arquivo de backup...\n"

# Extrair backup
if tar -xzf "${BACKUP_FILE}" -C "${RESTORE_DIR}"; then
    echo -e "  ${GREEN}✓${NC} Backup extraído\n"
else
    echo -e "  ${RED}✗${NC} Erro ao extrair backup\n"
    exit 1
fi

# Verificar se K3s está rodando
if ! systemctl is-active --quiet k3s; then
    echo -e "${RED}Erro: K3s não está rodando. Inicie o K3s antes de restaurar.${NC}"
    exit 1
fi

echo -e "${GREEN}[2/4]${NC} Restaurando snapshot do etcd...\n"

# Encontrar snapshot do etcd
ETCD_SNAPSHOT=$(find "${RESTORE_DIR}" -name "etcd-snapshot-*.db" | head -1)

if [ -z "$ETCD_SNAPSHOT" ]; then
    echo -e "  ${YELLOW}⚠${NC} Snapshot do etcd não encontrado no backup\n"
else
    echo -e "  ${GREEN}→${NC} Restaurando snapshot: $(basename ${ETCD_SNAPSHOT})"
    
    # Parar K3s temporariamente para restaurar etcd
    echo -e "  ${YELLOW}→${NC} Parando K3s..."
    systemctl stop k3s
    
    # Restaurar snapshot
    if k3s etcd-snapshot restore "${ETCD_SNAPSHOT}"; then
        echo -e "  ${GREEN}✓${NC} Snapshot do etcd restaurado\n"
    else
        echo -e "  ${RED}✗${NC} Erro ao restaurar snapshot do etcd\n"
        systemctl start k3s
        exit 1
    fi
    
    # Reiniciar K3s
    echo -e "  ${YELLOW}→${NC} Reiniciando K3s..."
    systemctl start k3s
    
    # Aguardar K3s estar pronto
    echo -e "  ${YELLOW}→${NC} Aguardando K3s estar pronto..."
    sleep 10
    
    # Aguardar API estar disponível
    for i in {1..30}; do
        if kubectl cluster-info &>/dev/null; then
            echo -e "  ${GREEN}✓${NC} K3s está pronto\n"
            break
        fi
        sleep 2
    done
fi

echo -e "${GREEN}[3/4]${NC} Restaurando recursos do Kubernetes...\n"

# Restaurar recursos
if [ -d "${RESTORE_DIR}/resources" ]; then
    for ns_dir in "${RESTORE_DIR}"/resources/*; do
        if [ -d "$ns_dir" ]; then
            ns=$(basename "$ns_dir")
            echo -e "  ${GREEN}→${NC} Restaurando namespace: ${ns}"
            
            # Criar namespace se não existir
            kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f - 2>/dev/null || true
            
            # Restaurar recursos
            if [ -f "${ns_dir}/resources.yaml" ]; then
                kubectl apply -f "${ns_dir}/resources.yaml" 2>/dev/null || true
            fi
            
            # Restaurar CRDs específicos
            for crd_file in "${ns_dir}"/*.yaml; do
                if [ -f "$crd_file" ] && [ "$(basename $crd_file)" != "resources.yaml" ]; then
                    kubectl apply -f "$crd_file" 2>/dev/null || true
                fi
            done
        fi
    done
    echo -e "  ${GREEN}✓${NC} Recursos restaurados\n"
else
    echo -e "  ${YELLOW}⚠${NC} Diretório de recursos não encontrado no backup\n"
fi

echo -e "${GREEN}[4/4]${NC} Restaurando configurações do K3s...\n"

# Restaurar configurações (cuidado - pode sobrescrever configurações atuais)
if [ -d "${RESTORE_DIR}/k3s-config" ]; then
    echo -e "  ${YELLOW}⚠${NC} Configurações do K3s encontradas no backup"
    echo -e "  ${YELLOW}⚠${NC} Revise manualmente os arquivos em: ${RESTORE_DIR}/k3s-config"
    echo -e "  ${YELLOW}⚠${NC} Não restaurando automaticamente para evitar sobrescrever configurações atuais\n"
    
    # Mostrar o que está disponível
    echo -e "  ${BLUE}Arquivos disponíveis para restauração manual:${NC}"
    ls -la "${RESTORE_DIR}/k3s-config/" | grep -v "^total" | awk '{print "    " $9}'
    echo ""
else
    echo -e "  ${YELLOW}⚠${NC} Configurações do K3s não encontradas no backup\n"
fi

# Limpar diretório temporário
rm -rf "${RESTORE_DIR}"

echo -e "${GREEN}✓✓✓ Restore concluído! ✓✓✓${NC}\n"

echo -e "${YELLOW}Próximos passos:${NC}"
echo -e "  1. Verifique o status do cluster: ${GREEN}kubectl get nodes${NC}"
echo -e "  2. Verifique os pods: ${GREEN}kubectl get pods --all-namespaces${NC}"
echo -e "  3. Se necessário, restaure configurações manualmente de ${RESTORE_DIR}/k3s-config\n"
