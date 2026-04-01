#!/usr/bin/env bash
set -euo pipefail

# Health-check script for the flink-only deployment.
#
# Usage:
#   ./scripts/verify-flink-only-dev.sh

ENV="dev"
NS="dah-kafka-$ENV"
FAILURES=0

check() {
  local desc="$1"; shift
  echo -n "  $desc... "
  if "$@" &>/dev/null; then echo "OK"; else echo "FAIL"; FAILURES=$((FAILURES + 1)); fi
}

echo "==> Verifying cluster connectivity..."
oc cluster-info || { echo "ERROR: Cannot reach the cluster."; exit 1; }

# ── Helm Releases ───────────────────────────────────────────────────────────
echo ""
echo "==> Helm Releases"
check "cert-manager release" helm status cert-manager -n cert-manager
check "confluent-operator release" helm status confluent-operator -n "$NS"
check "confluent-flink-operator release" helm status confluent-flink-operator -n "$NS"
check "confluent-cmf release" helm status confluent-cmf -n "$NS"

# ── cert-manager ────────────────────────────────────────────────────────────
echo ""
echo "==> cert-manager"
check "cert-manager pods running" \
  oc get pods -n cert-manager -l app=cert-manager --field-selector=status.phase=Running -o name
check "CFK webhook certificate Ready" \
  oc wait --for=condition=Ready certificate/confluent-operator-serving-cert -n "$NS" --timeout=10s

# ── Operators ───────────────────────────────────────────────────────────────
echo ""
echo "==> Operators in $NS"
check "CFK operator pods running" \
  oc get pods -n "$NS" -l app=confluent-operator --field-selector=status.phase=Running -o name
check "Flink operator pods running" \
  oc get pods -n "$NS" -l app.kubernetes.io/name=flink-kubernetes-operator --field-selector=status.phase=Running -o name

# ── CMF ─────────────────────────────────────────────────────────────────────
echo ""
echo "==> CMF"
check "CMF pod running" \
  oc get pods -n "$NS" -l app.kubernetes.io/name=confluent-manager-for-apache-flink --field-selector=status.phase=Running -o name

# ── Flink CRs ──────────────────────────────────────────────────────────────
echo ""
echo "==> Flink CRs"
check "CMFRestClass 'default'" oc get cmfrestclass default -n "$NS"
check "FlinkEnvironment 'flink-env1'" oc get flinkenvironment flink-env1 -n "$NS"
check "PVC 'flink-pvc'" oc get pvc flink-pvc -n "$NS"
check "FlinkDeployment 'flink-session'" oc get flinkdeployment flink-session -n "$NS"
check "Flink session cluster READY" \
  oc wait --for=jsonpath='{.status.jobManagerDeploymentStatus}'=READY \
    flinkdeployment/flink-session -n "$NS" --timeout=10s

# ── Summary ─────────────────────────────────────────────────────────────────
echo ""
if [ "$FAILURES" -eq 0 ]; then
  echo "========================================"
  echo "  All checks passed!"
  echo "========================================"
else
  echo "========================================"
  echo "  $FAILURES check(s) FAILED"
  echo "========================================"
fi
echo ""
echo "--- Pods in $NS ---"
oc get pods -n "$NS"
echo ""

exit "$FAILURES"
