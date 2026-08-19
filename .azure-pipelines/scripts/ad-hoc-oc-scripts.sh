#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-dah-flink-dev}"
ENV_NAME="${NAMESPACE#dah-flink-}"

echo "=== Restoring CMF ExternalSecrets ==="
CMF_EXTERNALSECRETS_DIR="apps/confluent-cmf/$ENV_NAME/externalsecrets"
if [ ! -d "$CMF_EXTERNALSECRETS_DIR" ]; then
  echo "ERROR: CMF externalsecrets directory not found: $CMF_EXTERNALSECRETS_DIR"
  exit 1
fi

for eso_file in "$CMF_EXTERNALSECRETS_DIR"/*.yaml; do
  [ -f "$eso_file" ] || continue
  echo "Restoring $(basename "$eso_file")..."
  oc apply -f "$eso_file" --wait=true
done

echo ""
echo "=== Restored ExternalSecrets ==="
oc -n "$NAMESPACE" get externalsecrets.external-secrets.io -l app.kubernetes.io/part-of=confluent-manager-for-flink
