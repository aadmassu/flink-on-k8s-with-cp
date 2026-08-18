#!/usr/bin/env bash
set -uo pipefail

# Build and apply Kafka TLS CA bundle from environment-specific CA certificates.
# Assembles all CAs in the correct order, encodes, and patches/creates the kafka-tls Secret.
#
# Usage: build-and-apply-kafka-ca-bundle.sh --namespace <ns> --environment <env> --ca-dir <dir>
#
# Example:
#   ./build-and-apply-kafka-ca-bundle.sh --namespace dah-flink-dev --environment dev \
#     --ca-dir apps/confluent-platform/dev/ca-certificates

NAMESPACE=""
ENVIRONMENT=""
CA_DIR=""

usage() {
  printf 'Usage: %s --namespace <ns> --environment <env> --ca-dir <ca-dir>\n' "$0" >&2
  exit 1
}

while [ $# -gt 0 ]; do
  case "$1" in
    --namespace) NAMESPACE="$2"; shift 2;;
    --environment) ENVIRONMENT="$2"; shift 2;;
    --ca-dir) CA_DIR="$2"; shift 2;;
    *) printf 'Unknown option: %s\n' "$1" >&2; usage;;
  esac
done

if [ -z "$NAMESPACE" ] || [ -z "$ENVIRONMENT" ] || [ -z "$CA_DIR" ]; then
  printf 'Error: missing required arguments\n' >&2
  usage
fi

if [ ! -d "$CA_DIR" ]; then
  printf 'Error: CA directory not found: %s\n' "$CA_DIR" >&2
  exit 1
fi

section() {
  printf '\n%s\n%s\n%s\n' \
    '================================================================================' \
    "$1" \
    '================================================================================'
}

section "Building Kafka TLS CA bundle for ${ENVIRONMENT}"

# Assemble bundle in order: FCB Root CA 2, Root CA 1, Issuing CA 1, Okta CA
BUNDLE_FILE="/tmp/kafka-ca-bundle-${ENVIRONMENT}.pem"
{
  cat "$CA_DIR/fcb-root-ca-2.pem"
  cat "$CA_DIR/fcb-root-ca-1.pem"
  cat "$CA_DIR/fcb-issuing-ca-1.pem"
  cat "$CA_DIR/okta-firstcitizens-ca.pem"
} > "$BUNDLE_FILE"

NUM_CERTS=$(grep -c "BEGIN CERTIFICATE" "$BUNDLE_FILE")
BUNDLE_SHA256=$(sha256sum "$BUNDLE_FILE" | awk '{print $1}')

printf '\nBundle assembled:\n'
printf '  Path: %s\n' "$BUNDLE_FILE"
printf '  Certificates: %s\n' "$NUM_CERTS"
printf '  SHA256: %s\n' "$BUNDLE_SHA256"

if [ "$NUM_CERTS" -ne 4 ]; then
  printf '\nError: Expected 4 certificates, found %s\n' "$NUM_CERTS" >&2
  exit 1
fi

# Base64 encode (on macOS, handle both `base64` variants)
if command -v base64 &>/dev/null; then
  CA_B64=$(base64 < "$BUNDLE_FILE" | tr -d '\n')
else
  printf 'Error: base64 command not found\n' >&2
  exit 1
fi

printf 'Base64 encoded size: %s bytes\n' "${#CA_B64}"

section "Applying kafka-tls Secret to namespace: ${NAMESPACE}"

# Check if secret exists
if oc -n "$NAMESPACE" get secret kafka-tls &>/dev/null; then
  printf '\nSecret exists. Patching ca.crt...\n'
  oc -n "$NAMESPACE" patch secret kafka-tls --type=merge \
    -p "{\"data\":{\"ca.crt\":\"${CA_B64}\"}}" 2>&1 || {
    printf 'Error: Failed to patch kafka-tls secret\n' >&2
    exit 1
  }
else
  printf '\nError: kafka-tls secret does not exist in %s\n' "$NAMESPACE" >&2
  printf 'Please create it manually or ensure the secret exists before patching\n' >&2
  exit 1
fi

section "Verification"

printf '\nKafka-tls secret updated successfully.\n'
printf 'Bundle summary for audit trail:\n'
printf '  Environment: %s\n' "$ENVIRONMENT"
printf '  Namespace: %s\n' "$NAMESPACE"
printf '  Bundle SHA256: %s\n' "$BUNDLE_SHA256"
printf '  Certificates: %s\n' "$NUM_CERTS"
printf '  Source: %s\n' "$CA_DIR"

printf '\nCertificate details:\n'
for ca_file in "$CA_DIR"/*.pem; do
  printf '\n  File: %s\n' "$(basename "$ca_file")"
  openssl x509 -noout -subject -in "$ca_file" 2>/dev/null | sed 's/^/    /'
done

printf '\n\nCFK will detect the secret change and regenerate the MDS truststore.\n'
printf 'Monitor pod restart with: oc -n %s get pods -w\n' "$NAMESPACE"

rm -f "$BUNDLE_FILE"
section "Complete"
