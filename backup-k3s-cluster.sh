#!/bin/bash

# Script para fazer backup completo do cluster K3s
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

# Diretório de backup
BACKUP_DIR="${BACKUP_DIR:-./k3s-backup-$(date +%Y%m%d-%H%M%S)}"
BACKUP_FILE="${BACKUP_FILE:-k3s-backup-$(date +%Y%m%d-%H%M%S).tar.gz}"

echo -e "${BLUE}╔════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Backup do Cluster K3s                            ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════╝\n"

# Criar diretório de backup
mkdir -p "${BACKUP_DIR}"
cd "${BACKUP_DIR}"

echo -e "${GREEN}[1/5]${NC} Fazendo backup do datastore...\n"

# Verificar qual datastore está sendo usado
DATSTORE_TYPE=""
if systemctl cat k3s 2>/dev/null | grep -q "cluster-init\|--datastore-endpoint"; then
    DATSTORE_TYPE="etcd"
elif [ -d "/var/lib/rancher/k3s/server/db" ]; then
    # Verificar se é SQLite ou etcd
    if [ -f "/var/lib/rancher/k3s/server/db/state.db" ]; then
        DATSTORE_TYPE="sqlite"
    elif [ -d "/var/lib/rancher/k3s/server/db/etcd" ]; then
        DATSTORE_TYPE="etcd"
    fi
fi

if [ "$DATSTORE_TYPE" = "etcd" ]; then
    echo -e "  ${BLUE}→${NC} Detectado datastore: etcd"
    
    # Criar snapshot do etcd
    ETCD_SNAPSHOT_NAME="etcd-snapshot-$(date +%Y%m%d-%H%M%S)"
    SNAPSHOT_TMP_DIR="/tmp/k3s-snapshots"
    mkdir -p "${SNAPSHOT_TMP_DIR}"
    
    # Criar snapshot do etcd usando flags corretas
    if k3s etcd-snapshot save --name "${ETCD_SNAPSHOT_NAME}" --etcd-snapshot-dir "${SNAPSHOT_TMP_DIR}" 2>/dev/null; then
        # O K3s cria o snapshot com o formato: on-demand-<nome>-<node-name>-<timestamp>
        SNAPSHOT_FILE=$(find "${SNAPSHOT_TMP_DIR}" -name "*${ETCD_SNAPSHOT_NAME}*" -o -name "on-demand-*" | head -1)
        
        if [ -n "$SNAPSHOT_FILE" ] && [ -f "$SNAPSHOT_FILE" ]; then
            FINAL_NAME="$(basename ${SNAPSHOT_FILE})"
            cp "${SNAPSHOT_FILE}" "./${FINAL_NAME}"
            echo -e "  ${GREEN}✓${NC} Snapshot do etcd criado: ${FINAL_NAME}"
            echo -e "  ${BLUE}→${NC} Tamanho: $(du -h ${SNAPSHOT_FILE} | cut -f1)\n"
            rm -rf "${SNAPSHOT_TMP_DIR}"
        else
            echo -e "  ${YELLOW}⚠${NC} Snapshot criado mas arquivo não encontrado\n"
            rm -rf "${SNAPSHOT_TMP_DIR}"
        fi
    else
        echo -e "  ${YELLOW}⚠${NC} Não foi possível criar snapshot do etcd (pode estar desabilitado)"
        echo -e "  ${YELLOW}→${NC} Fazendo backup direto do diretório do datastore...\n"
        
        # Fazer backup direto do diretório do etcd
        if [ -d "/var/lib/rancher/k3s/server/db" ]; then
            mkdir -p datastore-backup
            tar -czf "datastore-backup/etcd-data-$(date +%Y%m%d-%H%M%S).tar.gz" -C /var/lib/rancher/k3s/server db 2>/dev/null
            echo -e "  ${GREEN}✓${NC} Backup do diretório do datastore criado\n"
        fi
    fi
elif [ "$DATSTORE_TYPE" = "sqlite" ]; then
    echo -e "  ${BLUE}→${NC} Detectado datastore: SQLite"
    
    # Fazer backup do SQLite
    if [ -f "/var/lib/rancher/k3s/server/db/state.db" ]; then
        mkdir -p datastore-backup
        cp "/var/lib/rancher/k3s/server/db/state.db" "datastore-backup/state-$(date +%Y%m%d-%H%M%S).db"
        echo -e "  ${GREEN}✓${NC} Backup do SQLite criado\n"
    fi
else
    echo -e "  ${YELLOW}⚠${NC} Tipo de datastore não identificado"
    echo -e "  ${YELLOW}→${NC} Fazendo backup do diretório completo do servidor...\n"
    
    # Fazer backup do diretório do servidor como fallback
    if [ -d "/var/lib/rancher/k3s/server" ]; then
        mkdir -p datastore-backup
        tar -czf "datastore-backup/server-data-$(date +%Y%m%d-%H%M%S).tar.gz" -C /var/lib/rancher/k3s server 2>/dev/null
        echo -e "  ${GREEN}✓${NC} Backup do diretório do servidor criado\n"
    fi
fi

echo -e "${GREEN}[2/5]${NC} Fazendo backup dos recursos do Kubernetes...\n"

# Backup de todos os recursos do cluster (exceto alguns do sistema)
mkdir -p resources

# Lista de namespaces para backup (excluindo alguns do sistema que são recriados automaticamente)
NAMESPACES=$(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")

if [ -n "$NAMESPACES" ]; then
    for ns in $NAMESPACES; do
        # Pular namespaces do sistema que são recriados automaticamente
        if [[ "$ns" == "kube-system" ]] || [[ "$ns" == "kube-public" ]] || [[ "$ns" == "kube-node-lease" ]]; then
            echo -e "  ${YELLOW}⚠${NC} Pulando namespace do sistema: ${ns}"
            continue
        fi
        
        echo -e "  ${GREEN}→${NC} Fazendo backup do namespace: ${ns}"
        mkdir -p "resources/${ns}"
        
        # Backup de todos os recursos do namespace
        kubectl get all,configmap,secret,ingress,serviceaccount,role,rolebinding,clusterrole,clusterrolebinding,pvc,pv -n "$ns" -o yaml > "resources/${ns}/resources.yaml" 2>/dev/null || true
        
        # Backup de CRDs específicos (se existirem)
        kubectl get applications.argoproj.io -n "$ns" -o yaml > "resources/${ns}/applications.yaml" 2>/dev/null || true
        kubectl get rollouts.argoproj.io -n "$ns" -o yaml > "resources/${ns}/rollouts.yaml" 2>/dev/null || true
        kubectl get clusters.postgresql.cnpg.io -n "$ns" -o yaml > "resources/${ns}/postgresql-clusters.yaml" 2>/dev/null || true
    done
    echo -e "  ${GREEN}✓${NC} Recursos do Kubernetes salvos\n"
else
    echo -e "  ${YELLOW}⚠${NC} Não foi possível listar namespaces (kubectl pode não estar configurado)\n"
fi

echo -e "${GREEN}[3/5]${NC} Fazendo backup das configurações do K3s...\n"

# Backup de snapshots existentes (caso queira manter histórico)
# Verificar possíveis locais de snapshots
POSSIBLE_SNAPSHOT_DIRS=(
    "/var/lib/rancher/k3s/db/snapshots"
    "/var/lib/rancher/k3s/server/db/snapshots"
    "/var/lib/rancher/k3s/data"
)

for snap_dir in "${POSSIBLE_SNAPSHOT_DIRS[@]}"; do
    if [ -d "$snap_dir" ] && [ "$(ls -A $snap_dir 2>/dev/null)" ]; then
        echo -e "  ${GREEN}→${NC} Copiando snapshots existentes de ${snap_dir}..."
        mkdir -p k3s-snapshots
        cp -r "${snap_dir}"/* k3s-snapshots/ 2>/dev/null || true
        echo -e "  ${GREEN}✓${NC} Snapshots existentes copiados"
        break
    fi
done

# Backup das configurações do K3s
mkdir -p k3s-config

# Backup do arquivo de serviço systemd
if [ -f "/etc/systemd/system/k3s.service" ]; then
    cp /etc/systemd/system/k3s.service k3s-config/k3s.service
    echo -e "  ${GREEN}✓${NC} k3s.service copiado"
fi

# Backup do token do nó
if [ -f "/var/lib/rancher/k3s/server/node-token" ]; then
    cp /var/lib/rancher/k3s/server/node-token k3s-config/node-token
    echo -e "  ${GREEN}✓${NC} node-token copiado"
fi

# Backup do kubeconfig
if [ -f "/etc/rancher/k3s/k3s.yaml" ]; then
    cp /etc/rancher/k3s/k3s.yaml k3s-config/k3s.yaml
    echo -e "  ${GREEN}✓${NC} k3s.yaml copiado"
fi

# Backup de configurações customizadas do K3s
if [ -d "/etc/rancher/k3s" ]; then
    cp -r /etc/rancher/k3s/* k3s-config/ 2>/dev/null || true
    echo -e "  ${GREEN}✓${NC} Configurações do K3s copiadas\n"
fi

echo -e "${GREEN}[4/5]${NC} Criando arquivo de informações do cluster...\n"

# Criar arquivo com informações do cluster
cat > cluster-info.txt <<EOF
# Informações do Cluster K3s
# Backup criado em: $(date)

## Versão do K3s
$(k3s --version 2>/dev/null || echo "Versão não disponível")

## Versão do Kubernetes
$(kubectl version --short 2>/dev/null || echo "Versão não disponível")

## Nós do Cluster
$(kubectl get nodes -o wide 2>/dev/null || echo "Nós não disponíveis")

## Namespaces
$(kubectl get namespaces 2>/dev/null || echo "Namespaces não disponíveis")

## Storage Classes
$(kubectl get storageclass 2>/dev/null || echo "Storage classes não disponíveis")

## Configuração do K3s
EOF

# Adicionar informações do serviço systemd
if [ -f "/etc/systemd/system/k3s.service" ]; then
    echo "" >> cluster-info.txt
    echo "### Systemd Service" >> cluster-info.txt
    cat /etc/systemd/system/k3s.service >> cluster-info.txt
fi

echo -e "  ${GREEN}✓${NC} Informações do cluster salvas\n"

echo -e "${GREEN}[5/5]${NC} Criando arquivo compactado...\n"

# Voltar para o diretório anterior
cd ..

# Criar arquivo tar.gz
if tar -czf "${BACKUP_FILE}" -C "${BACKUP_DIR}" .; then
    echo -e "  ${GREEN}✓${NC} Backup compactado criado: ${BACKUP_FILE}\n"
    
    # Mostrar tamanho do arquivo
    SIZE=$(du -h "${BACKUP_FILE}" | cut -f1)
    echo -e "${GREEN}✓✓✓ Backup concluído com sucesso! ✓✓✓${NC}\n"
    echo -e "${BLUE}Arquivo de backup:${NC} ${BACKUP_FILE}"
    echo -e "${BLUE}Tamanho:${NC} ${SIZE}"
    echo -e "${BLUE}Localização:${NC} $(pwd)/${BACKUP_FILE}\n"
    
    # Limpar diretório temporário
    rm -rf "${BACKUP_DIR}"
    
    echo -e "${YELLOW}Para restaurar este backup, execute:${NC}"
    echo -e "  ${GREEN}./restore-k3s-cluster.sh ${BACKUP_FILE}${NC}\n"
else
    echo -e "  ${RED}✗${NC} Erro ao criar arquivo compactado\n"
    exit 1
fi
