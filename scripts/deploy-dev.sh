#!/usr/bin/env bash
set -euo pipefail

# Full deploy script for the dev environment.
# Installs ArgoCD via Helm, then deploys cert-manager, Confluent Operator,
# and Flink Operator through ArgoCD ApplicationSet resources.
#
# Usage:
#   ./scripts/deploy-dev.sh
#
# Prerequisites:
#   - kubectl configured and pointing to the target cluster
#   - helm 3.14+ / 4.x installed

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ENV="dev"
ARGOCD_NS="argocd"

echo "==> Verifying cluster connectivity..."
kubectl cluster-info || { echo "ERROR: Cannot reach the cluster. Check your kubeconfig."; exit 1; }

# ── Step 1: Add Helm repos ──────────────────────────────────────────────────
echo ""
echo "==> Adding Helm repositories..."
helm repo add argo-cd https://argoproj.github.io/argo-helm 2>/dev/null || true
helm repo add confluent https://packages.confluent.io/helm 2>/dev/null || true
helm repo add jetstack https://charts.jetstack.io 2>/dev/null || true
helm repo update

# ── Step 2: Install ArgoCD ──────────────────────────────────────────────────
echo ""
echo "==> Installing ArgoCD..."
if helm status argocd -n "$ARGOCD_NS" >/dev/null 2>&1; then
  echo "    ArgoCD Helm release already exists — upgrading..."
  helm upgrade argocd argo-cd/argo-cd \
    --namespace "$ARGOCD_NS" \
    -f "$REPO_ROOT/apps/argocd/$ENV/values.yaml" \
    --wait --timeout 5m
else
  helm install argocd argo-cd/argo-cd \
    --namespace "$ARGOCD_NS" --create-namespace \
    -f "$REPO_ROOT/apps/argocd/$ENV/values.yaml" \
    --wait --timeout 5m
fi

echo "    Waiting for ArgoCD pods..."
kubectl wait --for=condition=Ready pods -l app.kubernetes.io/instance=argocd -n "$ARGOCD_NS" --timeout=300s

# ── Step 3: Deploy cert-manager (required before Flink operator) ────────────
echo ""
echo "==> Deploying cert-manager..."
kubectl apply -f "$REPO_ROOT/gitops-config/aws-us-east-2/$ENV/cert-manager-application-set.yaml"
echo "    Waiting for cert-manager to become Healthy..."
kubectl wait --for=jsonpath='{.status.health.status}'=Healthy \
  application/cert-manager-$ENV -n "$ARGOCD_NS" --timeout=180s

# ── Step 4: Deploy Confluent Operator & Flink Operator ──────────────────────
echo ""
echo "==> Deploying Confluent Operator..."
kubectl apply -f "$REPO_ROOT/gitops-config/aws-us-east-2/$ENV/confluent-operator-application-set.yaml"

echo "==> Deploying Flink Operator..."
kubectl apply -f "$REPO_ROOT/gitops-config/aws-us-east-2/$ENV/confluent-flink-operator-application-set.yaml"

echo "    Waiting for both operators to become Healthy..."
kubectl wait --for=jsonpath='{.status.health.status}'=Healthy \
  application/confluent-operator-$ENV \
  application/confluent-flink-operator-$ENV \
  -n "$ARGOCD_NS" --timeout=180s

# ── Step 5: Print summary ──────────────────────────────────────────────────
echo ""
echo "========================================"
echo "  Deployment complete!"
echo "========================================"
echo ""
echo "--- ArgoCD Applications ---"
kubectl get applications -n "$ARGOCD_NS"
echo ""
echo "--- Operator Pods ---"
kubectl get pods -n confluent-$ENV
echo ""
echo "--- cert-manager Pods ---"
kubectl get pods -n cert-manager
echo ""

# Print ArgoCD access info
ARGOCD_URL=$(kubectl get svc argocd-server -n "$ARGOCD_NS" \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
if [ -z "$ARGOCD_URL" ]; then
  ARGOCD_URL=$(kubectl get svc argocd-server -n "$ARGOCD_NS" \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
fi

echo "--- ArgoCD Access ---"
if [ -n "$ARGOCD_URL" ]; then
  echo "  URL:      http://$ARGOCD_URL"
else
  echo "  URL:      (LoadBalancer pending — run: kubectl get svc argocd-server -n $ARGOCD_NS)"
fi
echo "  Username: admin"
echo "  Password: 3qnIIsA5FZfG1Krq"
echo ""
