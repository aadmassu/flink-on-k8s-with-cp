#!/usr/bin/env bash
set -euo pipefail

# Tears down everything deployed by deploy-openshift-dev.sh:
#   - Phase-II ArgoCD ApplicationSets (Flink infra, CP, CMF — reverse order)
#   - Phase-I ArgoCD ApplicationSets (FKO, CFK, cert-manager — reverse order)
#   - Finalizer cleanup for stuck CFK/Flink CRs and ArgoCD Applications
#   - OpenShift prerequisites (SCC + ClusterRoleBindings)
#   - Namespaces: dah-kafka-dev, cert-manager
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

# ── Step 1: Delete Phase-II ApplicationSets (reverse order) ──────────────
echo ""
echo "==> Deleting Phase-II ArgoCD ApplicationSets..."
oc delete applicationset confluent-flink-$ENV -n "$ARGOCD_NS" --ignore-not-found
oc delete applicationset confluent-platform-$ENV -n "$ARGOCD_NS" --ignore-not-found
oc delete applicationset confluent-cmf-$ENV -n "$ARGOCD_NS" --ignore-not-found

echo "    Waiting for Phase-II application resources to be cleaned up..."
oc wait --for=delete applicationset/confluent-flink-$ENV -n "$ARGOCD_NS" --timeout=120s 2>/dev/null || true
oc wait --for=delete applicationset/confluent-platform-$ENV -n "$ARGOCD_NS" --timeout=120s 2>/dev/null || true
oc wait --for=delete applicationset/confluent-cmf-$ENV -n "$ARGOCD_NS" --timeout=120s 2>/dev/null || true

# ── Step 2: Delete Phase-I ApplicationSets (reverse order) ───────────────
echo ""
echo "==> Deleting Phase-I ArgoCD ApplicationSets..."
oc delete applicationset confluent-flink-operator-$ENV -n "$ARGOCD_NS" --ignore-not-found
oc delete applicationset confluent-operator-$ENV -n "$ARGOCD_NS" --ignore-not-found
oc delete applicationset cert-manager-$ENV -n "$ARGOCD_NS" --ignore-not-found

echo "    Waiting for Phase-I application resources to be cleaned up..."
oc wait --for=delete applicationset/confluent-flink-operator-$ENV -n "$ARGOCD_NS" --timeout=120s 2>/dev/null || true
oc wait --for=delete applicationset/confluent-operator-$ENV -n "$ARGOCD_NS" --timeout=120s 2>/dev/null || true
oc wait --for=delete applicationset/cert-manager-$ENV -n "$ARGOCD_NS" --timeout=120s 2>/dev/null || true

# ── Step 3: Remove finalizers from stuck CRs ────────────────────────────────
echo ""
echo "==> Clearing finalizers from CFK/Flink CRs (if any)..."
for KIND in cmfrestclass flinkenvironment flinkdeployment kafka kraftcontroller connect \
            controlcenter schemaregistry; do
  for RESOURCE in $(oc get "$KIND" -n dah-kafka-$ENV -o name 2>/dev/null); do
    echo "    Clearing finalizers on $RESOURCE..."
    oc patch "$RESOURCE" -n dah-kafka-$ENV --type merge \
      -p '{"metadata":{"finalizers":null}}' 2>/dev/null || true
  done
done

# ── Step 3a: Remove finalizers from ArgoCD Applications ──────────────────
echo ""
echo "==> Clearing finalizers from ArgoCD Applications (if any)..."
for APP in $(oc get applications -n "$ARGOCD_NS" -o name 2>/dev/null); do
  oc patch "$APP" -n "$ARGOCD_NS" --type merge \
    -p '{"metadata":{"finalizers":null}}' 2>/dev/null || true
done

# ── Step 4: Delete OpenShift prerequisites (SCC + bindings) ───────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo ""
echo "==> Deleting OpenShift prerequisites (SCC + ClusterRoleBindings)..."
oc delete -f "$REPO_ROOT/openshift-prereqs/$ENV/manifests/" --ignore-not-found

# ── Step 5: Delete namespaces ────────────────────────────────────────────────
echo ""
echo "==> Deleting namespaces..."
oc delete ns dah-kafka-$ENV --ignore-not-found --wait --timeout=120s
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
