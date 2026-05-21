#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="istio-study"

kind delete cluster --name "${CLUSTER_NAME}" && \
  echo "Cluster '${CLUSTER_NAME}' deleted."
