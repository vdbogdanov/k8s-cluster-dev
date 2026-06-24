#!/bin/bash
source .env

# Create folder for certificates
mkdir pki

# Generate CA key
openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:prime256v1 -out pki/ca.key

# Generate CA certificate
openssl req -new -x509 -sha256 -days 3650 \
  -subj "/CN=Crypto CA" \
  -key pki/ca.key \
  -out pki/ca.crt

# Generate server key
openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:prime256v1 -out pki/server.key

# Generate server certificate signing request
openssl req -new \
  -subj "/CN=server" \
  -key pki/server.key \
  -out pki/server.csr

# Sign server certificate with CA
openssl x509 -req -sha256 -days 365 -CAcreateserial  \
  -CA pki/ca.crt \
  -CAkey pki/ca.key  \
  -in pki/server.csr \
  -out pki/server.crt \
  -extfile <(printf "basicConstraints=CA:FALSE\nkeyUsage=digitalSignature\nextendedKeyUsage=serverAuth\nsubjectAltName=DNS:*.${DOMAIN}")

# Generate client key
openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:prime256v1 -out pki/admin.key

# Generate client certificate signing request
openssl req -new \
  -subj "/CN=administrator" \
  -key pki/admin.key \
  -out pki/admin.csr

# Sign client certificate with CA
openssl x509 -req -sha256 -days 365 -CAcreateserial  \
  -CA pki/ca.crt \
  -CAkey pki/ca.key  \
  -in pki/admin.csr \
  -out pki/admin.crt \
  -extfile <(printf "basicConstraints=CA:FALSE\nkeyUsage=digitalSignature\nextendedKeyUsage=clientAuth")

# Create PKCS#12 bundle for client certificate
openssl pkcs12 -export \
  -certfile pki/ca.crt \
  -in pki/admin.crt \
  -inkey pki/admin.key \
  -out pki/admin.p12 \
  -passout pass:

# Install cert-manager using Helm
helm upgrade --install cert-manager \
  oci://quay.io/jetstack/charts/cert-manager \
  --version v1.20.2 \
  --namespace cert-manager \
  --create-namespace \
  --set crds.enabled=true

# Create secret for Cloudflare API token
kubectl create secret generic cloudflare-api-token \
  --namespace cert-manager \
  --from-literal=api-token="${CLOUDFLARE_API_TOKEN}" \
  --dry-run=client -o yaml | kubectl apply -f -

# Create cluster issuer for Let's Encrypt
kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    email: ${ACME_EMAIL}
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: letsencrypt-prod-key
    solvers:
      - dns01:
          cloudflare:
            apiTokenSecretRef:
              name: cloudflare-api-token
              key: api-token
EOF
