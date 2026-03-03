#!/usr/bin/env bash
set -euo pipefail

# Full deploy script for the dev environment on OpenShift.
# Uses the OpenShift GitOps Operator (ArgoCD in openshift-gitops namespace)
# to deploy cert-manager, operators, Confluent Platform, and CMF.
# SCCs are applied directly (one-time cluster prerequisite, not managed by ArgoCD).
#
# Usage:
#   ./scripts/deploy-openshift-dev.sh
#
# Prerequisites:
#   - oc CLI configured and logged in with cluster-admin access
#   - OpenShift GitOps Operator installed

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ENV="dev"
ARGOCD_NS="openshift-gitops"

echo "==> Verifying cluster connectivity..."
oc cluster-info || { echo "ERROR: Cannot reach the cluster. Check your kubeconfig / oc login."; exit 1; }

# ── Step 1: Verify OpenShift GitOps Operator ─────────────────────────────────
echo ""
echo "==> Verifying OpenShift GitOps Operator..."
if ! oc get pods -n "$ARGOCD_NS" -l app.kubernetes.io/name=openshift-gitops-server --no-headers 2>/dev/null | grep -q Running; then
  echo "ERROR: OpenShift GitOps ArgoCD server is not running in $ARGOCD_NS."
  echo "       Install the OpenShift GitOps Operator from OperatorHub first."
  echo "       See README-OPENSHIFT.md for instructions."
  exit 1
fi
echo "    OpenShift GitOps Operator is running."

# ── Step 2: Create and label namespaces ──────────────────────────────────────
echo ""
echo "==> Creating and labeling namespaces..."
for NS in "confluent-$ENV" "cert-manager"; do
  oc create namespace "$NS" --dry-run=client -o yaml | oc apply -f -
  oc label namespace "$NS" argocd.argoproj.io/managed-by="$ARGOCD_NS" --overwrite
  echo "    Namespace $NS labeled for OpenShift GitOps management."
done

# ── Step 3: Apply OpenShift prerequisites (SCC + bindings) ───────────────────
echo ""
echo "==> Applying OpenShift prerequisites (SCC + bindings)..."
oc apply -f "$REPO_ROOT/openshift-prereqs/$ENV/manifests/"
echo "    SCC and ClusterRoleBindings applied."

# ── Step 4: Deploy cert-manager (skip if already installed) ──────────────────
echo ""
echo "==> Deploying cert-manager..."
if oc get pods -n cert-manager 2>/dev/null | grep -q Running || \
   oc get pods -n openshift-cert-manager 2>/dev/null | grep -q Running; then
  echo "    cert-manager already running — skipping."
else
  oc apply -f "$REPO_ROOT/gitops-config/openshift/$ENV/cert-manager-application-set.yaml"
  echo "    Waiting for cert-manager to become Healthy..."
  oc wait --for=jsonpath='{.status.health.status}'=Healthy \
    application/cert-manager-$ENV -n "$ARGOCD_NS" --timeout=180s
fi

# ── Step 5: Deploy Confluent Operator & Flink Operator ───────────────────────
echo ""
echo "==> Deploying Confluent Operator..."
oc apply -f "$REPO_ROOT/gitops-config/openshift/$ENV/confluent-operator-application-set.yaml"

echo "==> Deploying Flink Operator..."
oc apply -f "$REPO_ROOT/gitops-config/openshift/$ENV/confluent-flink-operator-application-set.yaml"

echo "    Waiting for both operators to become Healthy..."
oc wait --for=jsonpath='{.status.health.status}'=Healthy \
  application/confluent-operator-$ENV \
  application/confluent-flink-operator-$ENV \
  -n "$ARGOCD_NS" --timeout=180s

# ── Step 6: Deploy Confluent Platform ────────────────────────────────────────
echo ""
echo "==> Deploying Confluent Platform..."
oc apply -f "$REPO_ROOT/gitops-config/openshift/$ENV/confluent-platform-application-set.yaml"
echo "    Waiting for Confluent Platform to become Healthy..."
oc wait --for=jsonpath='{.status.health.status}'=Healthy \
  application/confluent-platform-$ENV -n "$ARGOCD_NS" --timeout=600s

# ── Step 7: Deploy Confluent Flink Manager (CMF) ────────────────────────────
echo ""
echo "==> Deploying Confluent Flink Manager..."
oc apply -f "$REPO_ROOT/gitops-config/openshift/$ENV/confluent-flink-application-set.yaml"
echo "    Waiting for Confluent Flink Manager to become Healthy..."
oc wait --for=jsonpath='{.status.health.status}'=Healthy \
  application/confluent-flink-$ENV -n "$ARGOCD_NS" --timeout=300s

# ── Step 8: Print summary ───────────────────────────────────────────────────
echo ""
echo "========================================"
echo "  OpenShift Deployment complete!"
echo "========================================"
echo ""
echo "--- ArgoCD Applications ---"
oc get applications -n "$ARGOCD_NS"
echo ""
echo "--- Operator Pods ---"
oc get pods -n confluent-$ENV
echo ""
echo "--- cert-manager Pods ---"
oc get pods -n cert-manager 2>/dev/null || echo "  (using OpenShift-provided cert-manager)"
echo ""

# Print ArgoCD access info
ARGOCD_URL=$(oc get route openshift-gitops-server -n "$ARGOCD_NS" \
  -o jsonpath='{.spec.host}' 2>/dev/null || true)

echo "--- ArgoCD Access ---"
if [ -n "$ARGOCD_URL" ]; then
  echo "  URL:      https://$ARGOCD_URL"
else
  echo "  URL:      (Run: oc get route -n $ARGOCD_NS)"
fi
echo "  Username: admin"
echo "  Password: oc -n $ARGOCD_NS get secret openshift-gitops-cluster -o jsonpath='{.data.admin\\.password}' | base64 -d"
echo ""
