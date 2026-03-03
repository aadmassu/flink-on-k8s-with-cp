#!/usr/bin/env bash
set -euo pipefail

# Tears down everything deployed by deploy-dev.sh:
#   - ArgoCD ApplicationSets (confluent-flink-operator, confluent-operator, cert-manager)
#   - ArgoCD Helm release
#   - Namespaces: confluent-dev, cert-manager, argocd
#
# Usage:
#   ./scripts/destroy-dev.sh

ENV="dev"
ARGOCD_NS="argocd"

echo "==> Verifying cluster connectivity..."
kubectl cluster-info || { echo "ERROR: Cannot reach the cluster. Check your kubeconfig."; exit 1; }

# ── Step 1: Delete ArgoCD ApplicationSets (reverse order of deploy) ──────────
echo ""
echo "==> Deleting ArgoCD ApplicationSets..."
kubectl delete applicationset confluent-flink-operator-$ENV -n "$ARGOCD_NS" --ignore-not-found
kubectl delete applicationset confluent-operator-$ENV -n "$ARGOCD_NS" --ignore-not-found
kubectl delete applicationset cert-manager-$ENV -n "$ARGOCD_NS" --ignore-not-found

echo "    Waiting for application resources to be cleaned up..."
kubectl wait --for=delete applicationset/confluent-flink-operator-$ENV -n "$ARGOCD_NS" --timeout=120s 2>/dev/null || true
kubectl wait --for=delete applicationset/confluent-operator-$ENV -n "$ARGOCD_NS" --timeout=120s 2>/dev/null || true
kubectl wait --for=delete applicationset/cert-manager-$ENV -n "$ARGOCD_NS" --timeout=120s 2>/dev/null || true

# ── Step 2: Uninstall ArgoCD Helm release ───────────────────────────────────
echo ""
echo "==> Uninstalling ArgoCD Helm release..."
if helm status argocd -n "$ARGOCD_NS" >/dev/null 2>&1; then
  helm uninstall argocd --namespace "$ARGOCD_NS" --wait --timeout 2m
else
  echo "    ArgoCD Helm release not found — skipping."
fi

# ── Step 3: Delete namespaces ───────────────────────────────────────────────
echo ""
echo "==> Deleting namespaces..."
kubectl delete ns confluent-$ENV --ignore-not-found --wait --timeout=120s
kubectl delete ns cert-manager --ignore-not-found --wait --timeout=120s
kubectl delete ns "$ARGOCD_NS" --ignore-not-found --wait --timeout=120s

# ── Done ────────────────────────────────────────────────────────────────────
echo ""
echo "========================================"
echo "  Teardown complete!"
echo "========================================"
echo ""
