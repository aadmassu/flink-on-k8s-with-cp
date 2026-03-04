#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# Discover pinned Helm chart versions and container images for:
#   - Operators (cert-manager, CFK, Flink Operator, ArgoCD)
#   - Phase 2: CMF + Flink runtime
#   - Phase 3: Confluent Platform components
#
# Usage:
#   ./discover-charts-and-images.sh              # Phase 1 (operators only)
#   ./discover-charts-and-images.sh --phase 1    # Same as default
#   ./discover-charts-and-images.sh --phase 2    # Phase 1 + CMF + cp-flink
#   ./discover-charts-and-images.sh --phase 3    # Phase 2 + CP components
#
# Chart versions: queried via `helm search repo`
# Container images: derived from `helm template` with pinned chart versions
#   and the repository's own values/overlay files. This ensures the image
#   inventory always matches what the charts actually deploy — no hand-
#   maintained lists or registry API queries that can drift.
#
# Output:
#   Prints chart versions and images to stdout. The deduplicated image list
#   at the end can be piped to a bulk mirror script.
# ============================================================================

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# --- Parse arguments ---
PHASE=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --phase)
      PHASE="$2"
      shift 2
      ;;
    *)
      echo "Usage: $0 [--phase 1|2|3]" >&2
      exit 1
      ;;
  esac
done

if [[ "$PHASE" != "1" && "$PHASE" != "2" && "$PHASE" != "3" ]]; then
  echo "ERROR: --phase must be 1, 2, or 3" >&2
  exit 1
fi

# --- Pinned chart versions (single source of truth) ---
CERT_MANAGER_VERSION="v1.19.4"
CFK_VERSION="0.1351.59"
FLINK_OPERATOR_VERSION="1.130.2"
ARGOCD_VERSION="9.4.7"

# Phase 2/3 versions — update these when you pin specific versions
CMF_VERSION="${CMF_VERSION:-}"          # e.g. "0.xxx.yy"
CP_FLINK_VERSION="${CP_FLINK_VERSION:-}"  # e.g. "1.19-cp1"
CP_VERSION="${CP_VERSION:-}"            # e.g. "7.8.0"

# ========================================
#  Helm Chart Versions
# ========================================

echo "========================================"
echo "  Helm Chart Versions (Phase ${PHASE})"
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

if [[ "$PHASE" -ge 2 ]]; then
  echo ""
  echo "=== confluent-manager-for-apache-flink (CMF) ==="
  helm search repo confluent/confluent-manager-for-apache-flink --versions 2>/dev/null | head -5 || echo "  (chart not found — add repo or check chart name)"
fi

# ========================================
#  Container Images (from helm template)
# ========================================

echo ""
echo "========================================"
echo "  Container Images — Phase ${PHASE} (derived from helm template)"
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

# Helper: add a static image (for phases where no chart is rendered)
add_static_image() {
  local label="$1"
  local image="$2"
  echo "$image" >> "$ALL_IMAGES"
  echo "--- ${label} ---"
  printf "  %s\n\n" "$image"
}

# ========================================
#  Phase 1 — Operators
# ========================================

echo "=== Phase 1: Operators ==="
echo ""

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

# ========================================
#  Phase 2 — CMF + Flink Runtime
# ========================================

if [[ "$PHASE" -ge 2 ]]; then
  echo "=== Phase 2: CMF + Flink Runtime ==="
  echo ""

  if [ -n "$CMF_VERSION" ]; then
    extract_images "confluent-manager-for-apache-flink (${CMF_VERSION})" \
      cmf confluent/confluent-manager-for-apache-flink \
      --version "$CMF_VERSION"
  else
    echo "  NOTE: CMF_VERSION not set. Set CMF_VERSION env var to render CMF chart images."
    echo "  Example: CMF_VERSION=0.xxx.yy $0 --phase 2"
    echo ""
  fi

  if [ -n "$CP_FLINK_VERSION" ]; then
    add_static_image "cp-flink runtime (${CP_FLINK_VERSION})" \
      "docker.io/confluentinc/cp-flink:${CP_FLINK_VERSION}"
  else
    echo "  NOTE: CP_FLINK_VERSION not set. Set CP_FLINK_VERSION env var to include the Flink runtime image."
    echo "  Example: CP_FLINK_VERSION=1.19-cp1 $0 --phase 2"
    echo ""
  fi
fi

# ========================================
#  Phase 3 — Confluent Platform on K8s
# ========================================

if [[ "$PHASE" -ge 3 ]]; then
  echo "=== Phase 3: Confluent Platform Components ==="
  echo ""

  if [ -n "$CP_VERSION" ]; then
    for component in cp-server cp-schema-registry cp-kafka-connect cp-enterprise-control-center cp-kafka-rest cp-zookeeper; do
      add_static_image "${component} (${CP_VERSION})" \
        "docker.io/confluentinc/${component}:${CP_VERSION}"
    done
  else
    echo "  NOTE: CP_VERSION not set. Set CP_VERSION env var to include Confluent Platform images."
    echo "  Example: CP_VERSION=7.8.0 $0 --phase 3"
    echo ""
  fi
fi

# ========================================
#  Deduplicated summary
# ========================================

echo "========================================"
echo "  All Unique Images — Phase ${PHASE} (deduplicated)"
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
