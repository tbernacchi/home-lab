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

# Verify SAN is present (use -text, LibreSSL doesn't support -ext san)
echo "--- cert details ---"
openssl x509 -text -noout -in "$CERT_FILE" | grep -A2 "Subject Alternative"
echo "--------------------"

# traefik-dashboard-cert: used by IngressRoutes (dashboard, monitoring)
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

# traefik-cert: default cert for Gateway websecure listener (port 443)
# must also be updated — otherwise Traefik serves this old cert for all SNI
kubectl create secret tls traefik-cert \
  --cert="$CERT_FILE" \
  --key="$KEY_FILE" \
  -n traefik \
  --dry-run=client -o yaml | kubectl apply -f -

# Restart Traefik to pick up new cert
kubectl rollout restart deployment traefik -n traefik
kubectl rollout status deployment traefik -n traefik --timeout=60s

echo "Done. Access https://${DOMAIN}/prometheus"
