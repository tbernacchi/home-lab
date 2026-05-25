#!/usr/bin/env bash
set -euo pipefail

DOMAIN="traefik.mykubernetes.com"

# mkcert handles CA creation, keychain trust, and SAN automatically.
# Prerequisite: brew install mkcert

# Install mkcert CA into OS trust store (idempotent)
mkcert -install

# Generate cert + key for the domain
mkcert "$DOMAIN"

CERT_FILE="${DOMAIN}.pem"
KEY_FILE="${DOMAIN}-key.pem"

# Verify SAN is present
echo "--- cert details ---"
openssl x509 -noout -subject -issuer -ext san -in "$CERT_FILE"
echo "--------------------"

# Apply secrets to cluster
kubectl create secret tls traefik-dashboard-cert \
  --cert="$CERT_FILE" \
  --key="$KEY_FILE" \
  -n traefik \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret tls traefik-dashboard-cert \
  --cert="$CERT_FILE" \
  --key="$KEY_FILE" \
  -n monitoring \
  --dry-run=client -o yaml | kubectl apply -f -

# Restart Traefik to pick up new cert
kubectl rollout restart deployment traefik -n traefik
kubectl rollout status deployment traefik -n traefik --timeout=60s

echo "Done. Access https://${DOMAIN}/prometheus"
