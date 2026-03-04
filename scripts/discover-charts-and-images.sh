#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# Discover pinned Helm chart versions and container images for:
#   - Operators (cert-manager, CFK, Flink Operator, ArgoCD)
#
# Chart versions: queried via `helm search repo`
# Container images: derived from `helm template` with pinned chart versions
#   and the repository's own values/overlay files. This ensures the image
#   inventory always matches what the charts actually deploy — no hand-
#   maintained lists or registry API queries that can drift.
# ============================================================================

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# --- Pinned chart versions (single source of truth) ---
CERT_MANAGER_VERSION="v1.19.4"
CFK_VERSION="0.1351.59"
FLINK_OPERATOR_VERSION="1.130.2"
ARGOCD_VERSION="9.4.7"

# ========================================
#  Helm Chart Versions
# ========================================

echo "========================================"
echo "  Helm Chart Versions"
echo "========================================"

# Add repos
helm repo add jetstack https://charts.jetstack.io 2>/dev/null || true
helm repo add confluent https://packages.confluent.io/helm 2>/dev/null || true
helm repo add argo-cd https://argoproj.github.io/argo-helm 2>/dev/null || true
helm repo update >/dev/null 2>&1

echo ""
echo "=== cert-manager ==="
helm search repo jetstack/cert-manager --versions | head -5

echo ""
echo "=== confluent-for-kubernetes (CFK) ==="
helm search repo confluent/confluent-for-kubernetes --versions | head -5

echo ""
echo "=== flink-kubernetes-operator ==="
helm search repo confluent/flink-kubernetes-operator --versions | head -5

echo ""
echo "=== argo-cd ==="
helm search repo argo-cd/argo-cd --versions | head -5

# ========================================
#  Container Images (from helm template)
# ========================================

echo ""
echo "========================================"
echo "  Container Images (derived from helm template)"
echo "========================================"
echo ""
echo "Rendering charts with pinned versions + values files..."
echo "This is the authoritative image inventory."
echo ""

# Collect all images into a temp file for deduplication
ALL_IMAGES=$(mktemp)
trap 'rm -f "$ALL_IMAGES"' EXIT

# Helper: render a chart and extract image references
extract_images() {
  local label="$1"
  shift
  # Run helm template; extract image: fields; clean up whitespace and quotes
  local images
  images=$(helm template "$@" 2>/dev/null \
    | grep -E '^\s+image:|^\s+- image:' \
    | sed 's/.*image: *//; s/^"//; s/"$//' \
    | sed "s/^'//; s/'$//" \
    | sort -u) || true

  if [ -z "$images" ]; then
    echo "  WARNING: No images found for ${label} — is the chart version correct?"
    return
  fi

  echo "$images" >> "$ALL_IMAGES"

  echo "--- ${label} ---"
  printf "%-70s\n" "IMAGE"
  echo "----------------------------------------------------------------------"
  echo "$images" | while read -r img; do
    printf "  %s\n" "$img"
  done
  echo ""
}

# --- cert-manager ---
extract_images "cert-manager (${CERT_MANAGER_VERSION})" \
  cert-manager jetstack/cert-manager \
  --version "$CERT_MANAGER_VERSION" \
  -f "${REPO_ROOT}/apps/cert-manager/dev/values.yaml" \
  -f "${REPO_ROOT}/apps/cert-manager/openshift-overlay.yaml"

# --- Confluent for Kubernetes (CFK) ---
extract_images "confluent-for-kubernetes (${CFK_VERSION})" \
  confluent-operator confluent/confluent-for-kubernetes \
  --version "$CFK_VERSION" \
  -f "${REPO_ROOT}/apps/confluent-operator/dev/values.yaml" \
  -f "${REPO_ROOT}/apps/confluent-operator/openshift-overlay.yaml"

# --- Flink Kubernetes Operator ---
extract_images "flink-kubernetes-operator (${FLINK_OPERATOR_VERSION})" \
  flink-operator confluent/flink-kubernetes-operator \
  --version "$FLINK_OPERATOR_VERSION" \
  -f "${REPO_ROOT}/apps/confluent-flink-operator/dev/values.yaml" \
  -f "${REPO_ROOT}/apps/confluent-flink-operator/openshift-overlay.yaml"

# --- ArgoCD ---
# ArgoCD has no openshift-overlay file; render with env values only
extract_images "argo-cd (${ARGOCD_VERSION})" \
  argocd argo-cd/argo-cd \
  --version "$ARGOCD_VERSION" \
  -f "${REPO_ROOT}/apps/argocd/dev/values.yaml"

# --- Deduplicated summary ---
echo "========================================"
echo "  All Unique Images (deduplicated)"
echo "========================================"
echo ""
sort -u "$ALL_IMAGES" | while read -r img; do
  echo "  $img"
done
echo ""
IMAGE_COUNT=$(sort -u "$ALL_IMAGES" | wc -l | tr -d ' ')
echo "Total unique images: ${IMAGE_COUNT}"
echo ""
echo "Done."
