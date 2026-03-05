#!/usr/bin/env bash
set -euo pipefail

# Verifies the dev environment deployment on OpenShift.
# Checks all Phase-I and Phase-II components are running and healthy.
#
# Usage:
#   ./scripts/verify-openshift-dev.sh

ENV="dev"
ARGOCD_NS="openshift-gitops"
FAILURES=0

pass() { echo "  [PASS] $1"; }
fail() { echo "  [FAIL] $1"; FAILURES=$((FAILURES + 1)); }

# ── Cluster connectivity ─────────────────────────────────────────────────────
echo "==> Verifying cluster connectivity..."
oc cluster-info &>/dev/null && pass "Cluster reachable" || fail "Cluster unreachable"

# ── ArgoCD applications ──────────────────────────────────────────────────────
echo ""
echo "==> ArgoCD Applications..."
for APP in cert-manager-$ENV confluent-operator-$ENV confluent-flink-operator-$ENV \
           confluent-cmf-$ENV confluent-platform-$ENV confluent-flink-$ENV; do
  HEALTH=$(oc get application "$APP" -n "$ARGOCD_NS" -o jsonpath='{.status.health.status}' 2>/dev/null || true)
  SYNC=$(oc get application "$APP" -n "$ARGOCD_NS" -o jsonpath='{.status.sync.status}' 2>/dev/null || true)
  if [ "$HEALTH" = "Healthy" ] && [ "$SYNC" = "Synced" ]; then
    pass "$APP (Healthy/Synced)"
  elif [ "$HEALTH" = "Healthy" ] && [ "$SYNC" = "OutOfSync" ]; then
    pass "$APP (Healthy/OutOfSync — CRD drift expected)"
  elif [ "$HEALTH" = "Progressing" ] && [ "$SYNC" = "Synced" ]; then
    pass "$APP (Progressing/Synced — PVC pending first consumer)"
  else
    fail "$APP (health=$HEALTH, sync=$SYNC)"
  fi
done

# ── CMF pod ──────────────────────────────────────────────────────────────────
echo ""
echo "==> CMF pod..."
if oc get pods -n confluent-$ENV -l app.kubernetes.io/name=confluent-manager-for-apache-flink 2>/dev/null | grep -q Running; then
  pass "CMF pod running"
else
  fail "CMF pod not running"
fi

# ── Kafka status ─────────────────────────────────────────────────────────────
echo ""
echo "==> Kafka status..."
KAFKA_PHASE=$(oc get kafka kafka -n confluent-$ENV -o jsonpath='{.status.phase}' 2>/dev/null || true)
if [ "$KAFKA_PHASE" = "RUNNING" ]; then
  pass "Kafka is RUNNING"
else
  fail "Kafka phase: ${KAFKA_PHASE:-not found}"
fi

# ── Confluent Platform pods ──────────────────────────────────────────────────
echo ""
echo "==> Confluent Platform pods (confluent-$ENV)..."
oc get pods -n confluent-$ENV --no-headers 2>/dev/null | while read -r line; do
  POD=$(echo "$line" | awk '{print $1}')
  STATUS=$(echo "$line" | awk '{print $3}')
  if [ "$STATUS" = "Running" ]; then
    pass "$POD"
  else
    fail "$POD ($STATUS)"
  fi
done

# ── Flink infra CRs ─────────────────────────────────────────────────────────
echo ""
echo "==> Flink infrastructure CRs..."
oc get cmfrestclass default -n confluent-$ENV &>/dev/null \
  && pass "CMFRestClass 'default' exists" || fail "CMFRestClass 'default' not found"

oc get flinkenvironment flink-env1 -n confluent-$ENV &>/dev/null \
  && pass "FlinkEnvironment 'flink-env1' exists" || fail "FlinkEnvironment 'flink-env1' not found"

oc get pvc flink-pvc -n confluent-$ENV &>/dev/null \
  && pass "PVC 'flink-pvc' exists" || fail "PVC 'flink-pvc' not found"

# ── Flink session cluster ─────────────────────────────────────────────────
echo ""
echo "==> Flink session cluster..."
FLINK_STATUS=$(oc get flinkdeployment flink-session -n confluent-$ENV \
  -o jsonpath='{.status.jobManagerDeploymentStatus}' 2>/dev/null || true)
if [ "$FLINK_STATUS" = "READY" ]; then
  pass "Flink session cluster is READY"
else
  fail "Flink session cluster status: ${FLINK_STATUS:-not found}"
fi

# ── cert-manager pods ────────────────────────────────────────────────────────
echo ""
echo "==> cert-manager pods..."
if oc get pods -n cert-manager --no-headers 2>/dev/null | grep -q Running; then
  pass "cert-manager pods running"
elif oc get pods -n openshift-cert-manager --no-headers 2>/dev/null | grep -q Running; then
  pass "cert-manager pods running (openshift-cert-manager namespace)"
else
  fail "cert-manager pods not running"
fi

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "========================================"
if [ "$FAILURES" -eq 0 ]; then
  echo "  All checks passed!"
else
  echo "  $FAILURES check(s) failed."
fi
echo "========================================"
exit "$FAILURES"
