#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-dah-flink-dev}"

echo "=== Force-deleting cfk-license Secret ==="
echo "Namespace: $NAMESPACE"
echo ""

SECRET_NAME="cfk-license"

echo "Checking if secret exists..."
if ! oc -n "$NAMESPACE" get secret "$SECRET_NAME" &>/dev/null; then
  echo "Secret $SECRET_NAME not found in namespace $NAMESPACE"
  exit 0
fi

echo "Secret $SECRET_NAME found. Removing finalizers..."
oc -n "$NAMESPACE" patch secret "$SECRET_NAME" -p '{"metadata":{"finalizers":null}}' --type=merge || true

echo "Deleting secret $SECRET_NAME..."
oc -n "$NAMESPACE" delete secret "$SECRET_NAME" --ignore-not-found

echo "✓ Done"
