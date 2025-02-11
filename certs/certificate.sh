# Generate CA private key
openssl genrsa -out ca.key 4096

# Generate CA certificate
openssl req -x509 -new -nodes -key ca.key -sha256 -days 1024 -out ca.crt \
  -subj "/C=BR/ST=SP/L=Sao Paulo/O=MyKubernetes/CN=MyKubernetes CA"

# Generate certificate private key
openssl genrsa -out tls.key 2048

# Create OpenSSL configuration file
cat > traefik.conf <<EOF
[req]
req_extensions = v3_req
distinguished_name = req_distinguished_name

[req_distinguished_name]

[v3_req]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = traefik.mykubernetes.com
EOF

# Generate certificate signing request (CSR)
openssl req -new -key tls.key -out tls.csr \
  -subj "/C=BR/ST=SP/L=Sao Paulo/O=MyKubernetes/CN=traefik.mykubernetes.com" \
  -config traefik.conf

# Sign the certificate with our CA
openssl x509 -req -in tls.csr \
  -CA ca.crt -CAkey ca.key -CAcreateserial \
  -out tls.crt -days 365 -sha256 \
  -extensions v3_req -extfile traefik.conf

# Create Kubernetes TLS secrets
kubectl create secret tls traefik-dashboard-cert \
  --cert=tls.crt \
  --key=tls.key \
  -n traefik \
  --dry-run=client -o yaml | kubectl apply -f -

