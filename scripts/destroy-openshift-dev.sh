#!/usr/bin/env bash
set -euo pipefail

# Tears down everything deployed by deploy-openshift-dev.sh:
#   - ArgoCD ApplicationSets (reverse order)
#   - OpenShift prerequisites (SCC + ClusterRoleBindings)
#   - Namespaces: confluent-dev, cert-manager
#
# Note: OpenShift GitOps Operator and its namespace (openshift-gitops)
# are NOT removed — they are managed by the OperatorHub subscription.
#
# Usage:
#   ./scripts/destroy-openshift-dev.sh

ENV="dev"
ARGOCD_NS="openshift-gitops"

echo "==> Verifying cluster connectivity..."
oc cluster-info || { echo "ERROR: Cannot reach the cluster. Check your kubeconfig / oc login."; exit 1; }

# ── Step 1: Delete ArgoCD ApplicationSets (reverse order of deploy) ──────────
echo ""
echo "==> Deleting ArgoCD ApplicationSets..."
oc delete applicationset confluent-flink-$ENV -n "$ARGOCD_NS" --ignore-not-found
oc delete applicationset confluent-platform-$ENV -n "$ARGOCD_NS" --ignore-not-found
oc delete applicationset confluent-flink-operator-$ENV -n "$ARGOCD_NS" --ignore-not-found
oc delete applicationset confluent-operator-$ENV -n "$ARGOCD_NS" --ignore-not-found
oc delete applicationset cert-manager-$ENV -n "$ARGOCD_NS" --ignore-not-found

echo "    Waiting for application resources to be cleaned up..."
oc wait --for=delete applicationset/confluent-flink-$ENV -n "$ARGOCD_NS" --timeout=120s 2>/dev/null || true
oc wait --for=delete applicationset/confluent-platform-$ENV -n "$ARGOCD_NS" --timeout=120s 2>/dev/null || true
oc wait --for=delete applicationset/confluent-flink-operator-$ENV -n "$ARGOCD_NS" --timeout=120s 2>/dev/null || true
oc wait --for=delete applicationset/confluent-operator-$ENV -n "$ARGOCD_NS" --timeout=120s 2>/dev/null || true
oc wait --for=delete applicationset/cert-manager-$ENV -n "$ARGOCD_NS" --timeout=120s 2>/dev/null || true

# ── Step 2: Delete OpenShift prerequisites (SCC + bindings) ───────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo ""
echo "==> Deleting OpenShift prerequisites (SCC + ClusterRoleBindings)..."
oc delete -f "$REPO_ROOT/openshift-prereqs/$ENV/manifests/" --ignore-not-found

# ── Step 2: Delete namespaces ────────────────────────────────────────────────
echo ""
echo "==> Deleting namespaces..."
oc delete ns confluent-$ENV --ignore-not-found --wait --timeout=120s
oc delete ns cert-manager --ignore-not-found --wait --timeout=120s

# ── Done ─────────────────────────────────────────────────────────────────────
echo ""
echo "========================================"
echo "  OpenShift Teardown complete!"
echo "========================================"
echo ""
echo "Note: The OpenShift GitOps Operator and openshift-gitops namespace"
echo "      were NOT removed. Remove them via OperatorHub if needed."
echo ""
