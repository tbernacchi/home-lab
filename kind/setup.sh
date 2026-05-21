#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="istio-study"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}[+]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
die()  { echo -e "${RED}[x]${NC} $*"; exit 1; }

check_prereqs() {
  local missing=()
  for cmd in kind kubectl docker; do
    command -v "$cmd" &>/dev/null || missing+=("$cmd")
  done
  [[ ${#missing[@]} -gt 0 ]] && die "Missing: ${missing[*]}"
  docker info &>/dev/null || die "Docker daemon not running"
}

create_cluster() {
  if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
    warn "Cluster '${CLUSTER_NAME}' already exists, skipping"
    return
  fi
  log "Creating kind cluster '${CLUSTER_NAME}'..."
  kind create cluster --config "${SCRIPT_DIR}/cluster.yaml" --wait 90s
}

print_summary() {
  echo ""
  echo "================================================================="
  echo " Cluster '${CLUSTER_NAME}' ready"
  echo " Nodes: $(kubectl get nodes --no-headers | wc -l | tr -d ' ')"
  echo "================================================================="
}

check_prereqs
create_cluster
print_summary
