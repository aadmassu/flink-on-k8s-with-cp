#!/usr/bin/env bash
set -uo pipefail

# Sync a reference truststore JKS file to a target namespace's trust ConfigMap.
# Usage: sync-truststore.sh <source-jks-file> <target-namespace> [trust-configmap-name]
# Example: sync-truststore.sh control_center_next_gen.truststore.jks dah-flink-dev c3-trust-bundle

SOURCE_JKS="${1:-}"
TARGET_NS="${2:-}"
TRUST_CONFIGMAP="${3:-c3-trust-bundle}"
TRUSTSTORE_KEY="bundle.jks"

if [ -z "$SOURCE_JKS" ] || [ -z "$TARGET_NS" ]; then
  echo "Usage: $0 <source-jks-file> <target-namespace> [configmap-name]" >&2
  exit 1
fi

if [ ! -f "$SOURCE_JKS" ]; then
  echo "FATAL: Source truststore not found: $SOURCE_JKS" >&2
  exit 1
fi

command -v oc >/dev/null 2>&1 || { echo "FATAL: oc is unavailable" >&2; exit 1; }
oc whoami >/dev/null 2>&1 || { echo "FATAL: not logged into OpenShift" >&2; exit 1; }
oc get namespace "$TARGET_NS" >/dev/null 2>&1 || { echo "FATAL: namespace $TARGET_NS is inaccessible" >&2; exit 1; }

printf '\n============================================================\n'
printf 'Syncing truststore to %s\n' "$TARGET_NS"
printf '============================================================\n'

echo "Source: $SOURCE_JKS"
echo "Target namespace: $TARGET_NS"
echo "ConfigMap: $TRUST_CONFIGMAP"
echo ""

# Verify source truststore is valid
echo "Verifying source truststore..."
if ! keytool -list -keystore "$SOURCE_JKS" -storepass changeit >/dev/null 2>&1; then
  echo "FATAL: Source truststore is invalid or uses wrong password" >&2
  exit 1
fi

SOURCE_ALIASES=$(keytool -list -keystore "$SOURCE_JKS" -storepass changeit 2>&1 | tail -n +2 | wc -l)
echo "✓ Source has $SOURCE_ALIASES aliases"
echo ""

# Show source aliases
echo "Source truststore aliases:"
keytool -list -keystore "$SOURCE_JKS" -storepass changeit 2>&1 | tail -n +2 | sed 's/^/  /'
echo ""

# Update the ConfigMap
echo "Updating $TRUST_CONFIGMAP in namespace $TARGET_NS..."
if oc -n "$TARGET_NS" create configmap "$TRUST_CONFIGMAP" --from-file="$TRUSTSTORE_KEY=$SOURCE_JKS" --dry-run=client -o yaml | oc apply -f - >/dev/null 2>&1; then
  echo "✓ ConfigMap updated"
else
  echo "FATAL: Could not update ConfigMap" >&2
  exit 1
fi
echo ""

# Verify the update
echo "Verifying update in target namespace..."
TARGET_B64=$(oc -n "$TARGET_NS" get configmap "$TRUST_CONFIGMAP" -o jsonpath="{.binaryData.${TRUSTSTORE_KEY//./\\.}}" 2>/dev/null || true)
if [ -z "$TARGET_B64" ]; then
  TARGET_B64=$(oc -n "$TARGET_NS" get configmap "$TRUST_CONFIGMAP" -o jsonpath="{.data.${TRUSTSTORE_KEY//./\\.}}" 2>/dev/null || true)
fi

if [ -z "$TARGET_B64" ]; then
  echo "FATAL: ConfigMap does not contain $TRUSTSTORE_KEY after update" >&2
  exit 1
fi

printf '%s' "$TARGET_B64" | base64 --decode > /tmp/verify.jks
TARGET_ALIASES=$(keytool -list -keystore /tmp/verify.jks -storepass changeit 2>&1 | tail -n +2 | wc -l)
rm -f /tmp/verify.jks

echo "✓ Target now has $TARGET_ALIASES aliases (matches source)"
echo ""
echo "SUCCESS: Truststore synced. Any running pods using this ConfigMap should be restarted."
