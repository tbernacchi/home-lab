#!/usr/bin/env bash
# Opens port-forwards for all Istio observability UIs + ingress gateway.
# Each runs in background. Ctrl+C kills all.

set -euo pipefail

NS="istio-system"

cleanup() {
  echo ""
  echo "Killing port-forwards..."
  kill "${PIDS[@]}" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

PIDS=()

start_forward() {
  local name=$1 svc=$2 local_port=$3 remote_port=$4
  kubectl port-forward "svc/${svc}" -n "${NS}" "${local_port}:${remote_port}" &>/dev/null &
  PIDS+=($!)
  echo "[+] ${name} → http://localhost:${local_port}"
}

echo ""
echo "Starting port-forwards..."
echo ""

start_forward "Bookinfo (ingress)"  "istio-ingressgateway"  8080  80
start_forward "Kiali"               "kiali"                 20001 20001
start_forward "Jaeger"              "tracing"               16686 80
start_forward "Grafana"             "grafana"               3000  3000
start_forward "Prometheus"          "prometheus"            9090  9090

echo ""
echo "Bookinfo: http://localhost:8080/productpage"
echo ""
echo "Press Ctrl+C to stop all."

wait
