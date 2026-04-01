#!/usr/bin/env bash
set -euo pipefail

# Tears down the flink-only deployment (reverse order).
# All components were installed via Helm + oc apply.
#
# Usage:
#   ./scripts/destroy-flink-only-dev.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ENV="dev"
NS="confluent-$ENV"

echo "==> Verifying cluster connectivity..."
oc cluster-info || { echo "ERROR: Cannot reach the cluster."; exit 1; }

# ── Step 1: Delete Flink CRs ────────────────────────────────────────────────
echo ""
echo "==> Deleting Flink CRs..."
oc delete -f "$REPO_ROOT/apps/confluent-flink/$ENV/" --ignore-not-found 2>/dev/null || true

# Clear finalizers on stuck Flink CRs
for KIND in cmfrestclass flinkenvironment flinkdeployment; do
  for RESOURCE in $(oc get "$KIND" -n "$NS" -o name 2>/dev/null); do
    echo "    Clearing finalizers on $RESOURCE..."
    oc patch "$RESOURCE" -n "$NS" --type merge \
      -p '{"metadata":{"finalizers":null}}' 2>/dev/null || true
  done
done

# ── Step 2: Uninstall CMF ───────────────────────────────────────────────────
echo ""
echo "==> Uninstalling CMF..."
helm uninstall confluent-cmf -n "$NS" 2>/dev/null || true

# ── Step 3: Uninstall Flink Operator ────────────────────────────────────────
echo ""
echo "==> Uninstalling Flink Operator..."
helm uninstall confluent-flink-operator -n "$NS" 2>/dev/null || true

# ── Step 4: Delete CFK webhook TLS resources ────────────────────────────────
echo ""
echo "==> Deleting CFK webhook TLS resources..."
oc delete certificate confluent-operator-serving-cert -n "$NS" --ignore-not-found
oc delete issuer cfk-selfsigned-issuer -n "$NS" --ignore-not-found
oc delete secret confluent-operator-serving-cert cfk-jks-password cfk-jks-password-file \
  -n "$NS" --ignore-not-found

# ── Step 5: Uninstall CFK Operator ──────────────────────────────────────────
echo ""
echo "==> Uninstalling CFK Operator..."
helm uninstall confluent-operator -n "$NS" 2>/dev/null || true

# ── Step 6: Uninstall cert-manager ──────────────────────────────────────────
echo ""
echo "==> Uninstalling cert-manager..."
helm uninstall cert-manager -n cert-manager 2>/dev/null || true

# ── Step 7: Delete OpenShift prerequisites ──────────────────────────────────
echo ""
echo "==> Deleting OpenShift prerequisites (SCC + ClusterRoleBindings)..."
oc delete -f "$REPO_ROOT/openshift-prereqs/$ENV/manifests/" --ignore-not-found

# ── Step 8: Delete namespaces ───────────────────────────────────────────────
echo ""
echo "==> Deleting namespaces..."
oc delete ns "$NS" --ignore-not-found --wait --timeout=120s
oc delete ns cert-manager --ignore-not-found --wait --timeout=120s

echo ""
echo "========================================"
echo "  Flink-Only Teardown complete!"
echo "========================================"
echo ""
