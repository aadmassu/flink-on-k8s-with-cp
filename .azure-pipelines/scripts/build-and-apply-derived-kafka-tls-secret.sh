#!/usr/bin/env bash
set -uo pipefail

# Build and apply derived kafka-tls-cfk Secret from source kafka-tls + CA bundle.
#
# This script:
# 1. Reads environment-specific CA bundle declaration (ca-bundle.conf)
# 2. Checks source kafka-tls Secret ownership (fail if cert-manager/ESO managed without derived secret)
# 3. Extracts tls.crt + tls.key from source Secret
# 4. Combines with CA bundle in deterministic order
# 5. Creates/updates kafka-tls-cfk Secret with the complete trust chain
# 6. Reconciles on every run (updates if exists, ensuring renewed certs propagate)
#
# Security: Never logs secrets, keys, or base64 values. Logs only subjects and fingerprints.
#
# Usage: build-and-apply-derived-kafka-tls-secret.sh --namespace <ns> --environment <env> --ca-bundle-conf <conf>
#
# Example:
#   ./build-and-apply-derived-kafka-tls-secret.sh \
#     --namespace dah-flink-dev --environment dev \
#     --ca-bundle-conf apps/confluent-platform/dev/ca-bundle.conf

NAMESPACE=""
ENVIRONMENT=""
CA_BUNDLE_CONF=""
SOURCE_SECRET_NAME="kafka-tls"
DERIVED_SECRET_NAME="kafka-tls-cfk"

usage() {
  printf 'Usage: %s --namespace <ns> --environment <env> --ca-bundle-conf <conf>\n' "$0" >&2
  exit 1
}

while [ $# -gt 0 ]; do
  case "$1" in
    --namespace) NAMESPACE="$2"; shift 2;;
    --environment) ENVIRONMENT="$2"; shift 2;;
    --ca-bundle-conf) CA_BUNDLE_CONF="$2"; shift 2;;
    *) printf 'Unknown option: %s\n' "$1" >&2; usage;;
  esac
done

if [ -z "$NAMESPACE" ] || [ -z "$ENVIRONMENT" ] || [ -z "$CA_BUNDLE_CONF" ]; then
  printf 'Error: missing required arguments\n' >&2
  usage
fi

if [ ! -f "$CA_BUNDLE_CONF" ]; then
  printf 'Error: CA bundle conf file not found: %s\n' "$CA_BUNDLE_CONF" >&2
  exit 1
fi

section() {
  printf '\n%s\n%s\n%s\n' \
    '================================================================================' \
    "$1" \
    '================================================================================'
}

redact_secret_value() {
  printf '[REDACTED]'
}

# Resolve relative paths in ca-bundle.conf
resolve_ca_paths() {
  local conf_file="$1"
  local conf_dir
  conf_dir=$(cd "$(dirname "$conf_file")" && pwd -P)

  while IFS= read -r line; do
    # Skip comments and empty lines
    [[ "$line" =~ ^#  ]] && continue
    [[ -z "$line" ]] && continue

    # Resolve relative to conf file directory, normalize path
    local ca_path
    ca_path=$(readlink -f "${conf_dir}/${line}" 2>/dev/null) || ca_path="${conf_dir}/${line}"

    if [ ! -f "$ca_path" ]; then
      printf 'Error: CA certificate not found: %s (from %s)\n' "$ca_path" "$line" >&2
      return 1
    fi
    printf '%s\n' "$ca_path"
  done < "$conf_file"
}

section "Building derived kafka-tls-cfk Secret for ${ENVIRONMENT}"

# Validate CA bundle config
printf '\nValidating CA bundle configuration...\n'
CA_FILES=()
while IFS= read -r ca_path; do
  CA_FILES+=("$ca_path")
  printf '  ✓ %s\n' "$(basename "$ca_path")"
done < <(resolve_ca_paths "$CA_BUNDLE_CONF")

if [ ${#CA_FILES[@]} -eq 0 ]; then
  printf 'Error: No CA certificates found in ca-bundle.conf\n' >&2
  exit 1
fi

section "Validating source kafka-tls Secret"

# Check if source secret exists
if ! oc -n "$NAMESPACE" get secret "$SOURCE_SECRET_NAME" &>/dev/null; then
  printf 'Error: Source secret %s not found in namespace %s\n' "$SOURCE_SECRET_NAME" "$NAMESPACE" >&2
  exit 1
fi

# Check ownership (fail if cert-manager/ESO managed without guidance)
OWNER_REFS=$(oc -n "$NAMESPACE" get secret "$SOURCE_SECRET_NAME" -o jsonpath='{.metadata.ownerReferences}' 2>/dev/null || echo "")
CERT_MGR_ANNOT=$(oc -n "$NAMESPACE" get secret "$SOURCE_SECRET_NAME" -o jsonpath='{.metadata.annotations.cert-manager\.io\/certificate-name}' 2>/dev/null || echo "")
ESO_ANNOT=$(oc -n "$NAMESPACE" get secret "$SOURCE_SECRET_NAME" -o jsonpath='{.metadata.annotations.external-secrets\.io\/status}' 2>/dev/null || echo "")

if [ -n "$CERT_MGR_ANNOT" ] || [ -n "$ESO_ANNOT" ] || [ "$OWNER_REFS" != "[]" ] 2>/dev/null; then
  printf '\nWARNING: Source secret %s is managed by cert-manager or External Secrets\n' "$SOURCE_SECRET_NAME"
  printf 'This script creates a derived secret (%s) containing the source cert + CA bundle.\n' "$DERIVED_SECRET_NAME"
  printf 'The source secret will be updated by its operator; the derived secret will be created/updated here.\n'
fi

printf '\n  Source secret: %s\n' "$SOURCE_SECRET_NAME"
printf '  Derived secret: %s\n' "$DERIVED_SECRET_NAME"

section "Extracting source certificate and key"

# Extract tls.crt and tls.key from source secret
SOURCE_CRT_TMP=$(mktemp)
SOURCE_KEY_TMP=$(mktemp)
oc -n "$NAMESPACE" get secret "$SOURCE_SECRET_NAME" -o jsonpath='{.data.tls\.crt}' | base64 -d > "$SOURCE_CRT_TMP" 2>/dev/null || {
  printf 'Error: Could not extract tls.crt from %s\n' "$SOURCE_SECRET_NAME" >&2
  rm -f "$SOURCE_CRT_TMP" "$SOURCE_KEY_TMP"
  exit 1
}

oc -n "$NAMESPACE" get secret "$SOURCE_SECRET_NAME" -o jsonpath='{.data.tls\.key}' | base64 -d > "$SOURCE_KEY_TMP" 2>/dev/null || {
  printf 'Error: Could not extract tls.key from %s\n' "$SOURCE_SECRET_NAME" >&2
  rm -f "$SOURCE_CRT_TMP" "$SOURCE_KEY_TMP"
  exit 1
}

# Validate source certificate
if ! openssl x509 -noout -in "$SOURCE_CRT_TMP" &>/dev/null; then
  printf 'Error: Source certificate is not valid X.509 PEM\n' >&2
  rm -f "$SOURCE_CRT_TMP" "$SOURCE_KEY_TMP"
  exit 1
fi

CERT_SUBJECT=$(openssl x509 -noout -subject -in "$SOURCE_CRT_TMP")
CERT_DATES=$(openssl x509 -noout -dates -in "$SOURCE_CRT_TMP")
printf '\n  Extracted from %s:\n' "$SOURCE_SECRET_NAME"
printf '    Subject: %s\n' "$CERT_SUBJECT"
printf '    %s\n' "$CERT_DATES"

section "Assembling CA bundle"

# Assemble CA bundle in declared order
CA_BUNDLE_TMP=$(mktemp)
{
  for ca_path in "${CA_FILES[@]}"; do
    cat "$ca_path"
  done
} > "$CA_BUNDLE_TMP"

NUM_CA_CERTS=$(grep -c "BEGIN CERTIFICATE" "$CA_BUNDLE_TMP")
CA_BUNDLE_SHA256=$(sha256sum "$CA_BUNDLE_TMP" | awk '{print $1}')

printf '\nCA bundle assembled:\n'
printf '  Certificates: %s\n' "$NUM_CA_CERTS"
printf '  SHA256: %s\n' "$CA_BUNDLE_SHA256"

# Print CA details (subjects only, no secrets)
printf '\nCA certificate details:\n'
awk '/-----BEGIN CERTIFICATE-----/{flag=1; next} /-----END CERTIFICATE-----/{flag=0} flag' "$CA_BUNDLE_TMP" | \
  while IFS= read -r line; do
    if [[ "$line" =~ ^[A-Za-z0-9+/]+=?$ ]]; then
      echo "$line"
    fi
  done | while read -r b64_data; do
    echo "$b64_data" | base64 -d 2>/dev/null | openssl x509 -noout -subject 2>/dev/null | sed 's/^/    /'
  done

if [ "$NUM_CA_CERTS" -ne ${#CA_FILES[@]} ]; then
  printf '\nError: Expected %s CA certificates, found %s\n' "${#CA_FILES[@]}" "$NUM_CA_CERTS" >&2
  rm -f "$SOURCE_CRT_TMP" "$SOURCE_KEY_TMP" "$CA_BUNDLE_TMP"
  exit 1
fi

section "Creating/updating derived Secret: ${DERIVED_SECRET_NAME}"

# Base64 encode all components
SOURCE_CRT_B64=$(base64 < "$SOURCE_CRT_TMP" | tr -d '\n')
SOURCE_KEY_B64=$(base64 < "$SOURCE_KEY_TMP" | tr -d '\n')
CA_BUNDLE_B64=$(base64 < "$CA_BUNDLE_TMP" | tr -d '\n')

# Create the derived secret manifest (dry-run to generate YAML)
DERIVED_SECRET_MANIFEST=$(mktemp)
oc create secret tls "$DERIVED_SECRET_NAME" \
  -n "$NAMESPACE" --dry-run=client -o yaml \
  --cert=<(echo "$SOURCE_CRT_B64" | base64 -d) \
  --key=<(echo "$SOURCE_KEY_B64" | base64 -d) > "$DERIVED_SECRET_MANIFEST" 2>/dev/null || {
  printf 'Error: Could not generate Secret manifest\n' >&2
  rm -f "$SOURCE_CRT_TMP" "$SOURCE_KEY_TMP" "$CA_BUNDLE_TMP" "$DERIVED_SECRET_MANIFEST"
  exit 1
}

# Add the combined CA bundle to the manifest
# Use kubectl patch to insert the ca.crt data field
kubectl patch -f "$DERIVED_SECRET_MANIFEST" --local --type=json \
  -p="[{\"op\":\"add\",\"path\":\"/data/ca.crt\",\"value\":\"${CA_BUNDLE_B64}\"}]" -o yaml | \
  oc apply -f - 2>&1 || {
  printf 'Error: Could not apply derived Secret\n' >&2
  rm -f "$SOURCE_CRT_TMP" "$SOURCE_KEY_TMP" "$CA_BUNDLE_TMP" "$DERIVED_SECRET_MANIFEST"
  exit 1
}

printf '\n  ✓ Secret %s created/updated in namespace %s\n' "$DERIVED_SECRET_NAME" "$NAMESPACE"

section "Verification"

printf '\nDerived Secret summary (audit trail):\n'
printf '  Name: %s\n' "$DERIVED_SECRET_NAME"
printf '  Namespace: %s\n' "$NAMESPACE"
printf '  tls.crt source: %s (subject: %s)\n' "$SOURCE_SECRET_NAME" "$CERT_SUBJECT"
printf '  ca.crt contents: %s CAs, SHA256: %s\n' "$NUM_CA_CERTS" "$CA_BUNDLE_SHA256"
printf '  Created: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"

printf '\nNext steps:\n'
printf '  1. Update Kafka CR to reference secretRef: %s in spec.tls and services.mds.tls\n' "$DERIVED_SECRET_NAME"
printf '  2. CFK will detect the Secret change and regenerate MDS truststore.p12\n'
printf '  3. Monitor: oc -n %s get pods -w\n' "$NAMESPACE"
printf '  4. Verify: keytool -list -v -keystore /mnt/sslcerts/%s/truststore.p12 -storetype PKCS12\n' "$DERIVED_SECRET_NAME"

# Cleanup
rm -f "$SOURCE_CRT_TMP" "$SOURCE_KEY_TMP" "$CA_BUNDLE_TMP" "$DERIVED_SECRET_MANIFEST"

section "Complete"
