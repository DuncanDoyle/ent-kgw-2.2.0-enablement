#!/bin/sh
# Generates the CA, server, and client certificates for the mTLS listener demo.
# Designed to be called from the gateway-api-1.5.1/ directory (as done by setup.sh).
#
# Creates in namespace gwapi151:
#   Secret      gateway-server-tls  — server TLS cert/key for the HTTPS listener
#   ConfigMap   client-ca           — CA cert used by frontendValidation to verify client certs
#
# Saves the client-side material to install/certs/ for use with curl.

NAMESPACE=gwapi151
CERT_DIR="$(dirname "$0")/certs"
mkdir -p "$CERT_DIR"

TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

# ---------------------------------------------------------------------------
# 1. Self-signed CA
# ---------------------------------------------------------------------------
openssl genrsa -out "$TMPDIR/ca.key" 4096
openssl req -x509 -new -nodes \
  -key "$TMPDIR/ca.key" \
  -sha256 -days 3650 \
  -subj "/CN=gwapi151-demo-ca/O=demo" \
  -out "$TMPDIR/ca.crt"

# ---------------------------------------------------------------------------
# 2. Server cert for mtls.example.com, signed by the CA
# ---------------------------------------------------------------------------
openssl genrsa -out "$TMPDIR/server.key" 2048
openssl req -new -key "$TMPDIR/server.key" \
  -subj "/CN=mtls.example.com/O=demo" \
  -out "$TMPDIR/server.csr"
printf "subjectAltName=DNS:mtls.example.com\n" > "$TMPDIR/san.cnf"
openssl x509 -req \
  -in "$TMPDIR/server.csr" \
  -CA "$TMPDIR/ca.crt" -CAkey "$TMPDIR/ca.key" -CAcreateserial \
  -days 3650 -sha256 \
  -extfile "$TMPDIR/san.cnf" \
  -out "$TMPDIR/server.crt"

# ---------------------------------------------------------------------------
# 3. Client cert, signed by the same CA
# ---------------------------------------------------------------------------
openssl genrsa -out "$TMPDIR/client.key" 2048
openssl req -new -key "$TMPDIR/client.key" \
  -subj "/CN=demo-client/O=demo" \
  -out "$TMPDIR/client.csr"
openssl x509 -req \
  -in "$TMPDIR/client.csr" \
  -CA "$TMPDIR/ca.crt" -CAkey "$TMPDIR/ca.key" -CAcreateserial \
  -days 3650 -sha256 \
  -out "$TMPDIR/client.crt"

# ---------------------------------------------------------------------------
# Kubernetes resources
# ---------------------------------------------------------------------------

# Server TLS Secret — referenced by the HTTPS listener's certificateRefs
kubectl create secret tls gateway-server-tls \
  --cert="$TMPDIR/server.crt" --key="$TMPDIR/server.key" \
  -n "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# CA ConfigMap — referenced by spec.tls.frontend.perPort[443].validation.caCertificateRefs
# The key must be named ca.crt.
kubectl create configmap client-ca \
  --from-file=ca.crt="$TMPDIR/ca.crt" \
  -n "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# ---------------------------------------------------------------------------
# Save client material for the curl demo
# ---------------------------------------------------------------------------
cp "$TMPDIR/ca.crt"     "$CERT_DIR/ca.crt"
cp "$TMPDIR/client.crt" "$CERT_DIR/client.crt"
cp "$TMPDIR/client.key" "$CERT_DIR/client.key"

printf "\nSecrets/ConfigMaps created in namespace '%s'.\n" "$NAMESPACE"
printf "Client certs saved to %s/ for use with curl-mtls-demo.sh.\n" "$CERT_DIR"
