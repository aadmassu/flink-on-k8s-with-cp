#!/usr/bin/env bash
set -uo pipefail

# Initialize c3-trust-bundle ConfigMap in target namespace.
# This ConfigMap is Control Center-specific and includes:
# - All certificates from the QA reference truststore (org standard + OIDC certs)
# - Can be synced/updated via sync-truststore.sh later
# Usage: init-c3-truststore.sh <target-namespace> [reference-jks-file]

TARGET_NS="${1:-}"
REFERENCE_JKS="${2:-}"
CONFIGMAP_NAME="c3-trust-bundle"
TRUSTSTORE_KEY="bundle.jks"

if [ -z "$TARGET_NS" ]; then
  echo "Usage: $0 <target-namespace> [reference-jks-file]" >&2
  exit 1
fi

# If REFERENCE_JKS not provided, use default
if [ -z "$REFERENCE_JKS" ]; then
  REFERENCE_JKS=".azure-pipelines/truststore-references/qa-reference.jks"
fi

# Convert to absolute path if relative
if [[ ! "$REFERENCE_JKS" = /* ]]; then
  REFERENCE_JKS="$(cd "$(dirname "$REFERENCE_JKS")" && pwd)/$(basename "$REFERENCE_JKS")"
fi

command -v oc >/dev/null 2>&1 || { echo "FATAL: oc is unavailable" >&2; exit 1; }
oc whoami >/dev/null 2>&1 || { echo "FATAL: not logged into OpenShift" >&2; exit 1; }
oc get namespace "$TARGET_NS" >/dev/null 2>&1 || { echo "FATAL: namespace $TARGET_NS is inaccessible" >&2; exit 1; }

if [ ! -f "$REFERENCE_JKS" ]; then
  echo "FATAL: Reference truststore not found: $REFERENCE_JKS" >&2
  exit 1
fi

printf '\n============================================================\n'
printf 'Initializing c3-trust-bundle ConfigMap\n'
printf '============================================================\n'

echo "Target namespace: $TARGET_NS"
echo "Reference truststore: $REFERENCE_JKS"
echo "ConfigMap name: $CONFIGMAP_NAME"
echo ""

# Check if ConfigMap already exists
if oc -n "$TARGET_NS" get configmap "$CONFIGMAP_NAME" >/dev/null 2>&1; then
  echo "ℹ ConfigMap/$CONFIGMAP_NAME already exists; skipping creation"
  echo "  Use 'oc -n $TARGET_NS delete configmap $CONFIGMAP_NAME' to reset, then re-run this script"
  exit 0
fi

# Verify reference truststore is valid
echo "Verifying reference truststore..."
if ! keytool -list -keystore "$REFERENCE_JKS" -storepass changeit >/dev/null 2>&1; then
  echo "FATAL: Reference truststore is invalid or uses wrong password" >&2
  exit 1
fi

REF_ALIASES=$(keytool -list -keystore "$REFERENCE_JKS" -storepass changeit 2>&1 | tail -n +2 | wc -l)
echo "✓ Reference truststore has $REF_ALIASES aliases"
echo ""

# Create the ConfigMap from reference
echo "Creating $CONFIGMAP_NAME in namespace $TARGET_NS..."
if oc -n "$TARGET_NS" create configmap "$CONFIGMAP_NAME" --from-file="$TRUSTSTORE_KEY=$REFERENCE_JKS" >/dev/null 2>&1; then
  echo "✓ ConfigMap created"
else
  echo "FATAL: Could not create ConfigMap" >&2
  exit 1
fi
echo ""

# Verify creation
echo "Verifying ConfigMap contents..."
CM_B64=$(oc -n "$TARGET_NS" get configmap "$CONFIGMAP_NAME" -o jsonpath="{.binaryData.${TRUSTSTORE_KEY//./\\.}}" 2>/dev/null || true)
if [ -z "$CM_B64" ]; then
  CM_B64=$(oc -n "$TARGET_NS" get configmap "$CONFIGMAP_NAME" -o jsonpath="{.data.${TRUSTSTORE_KEY//./\\.}}" 2>/dev/null || true)
fi

if [ -z "$CM_B64" ]; then
  echo "FATAL: ConfigMap does not contain $TRUSTSTORE_KEY" >&2
  exit 1
fi

printf '%s' "$CM_B64" | base64 --decode > /tmp/verify.jks 2>/dev/null || true
if [ -f /tmp/verify.jks ] && [ -s /tmp/verify.jks ]; then
  CM_ALIASES=$(keytool -list -keystore /tmp/verify.jks -storepass changeit 2>&1 | tail -n +2 | wc -l)
  echo "✓ ConfigMap contains $CM_ALIASES aliases (matches reference)"
  rm -f /tmp/verify.jks
else
  echo "WARN: Could not verify ConfigMap contents"
fi

echo ""
echo "SUCCESS: c3-trust-bundle initialized. Control Center pod must be restarted to use it."
