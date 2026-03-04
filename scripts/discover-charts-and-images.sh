#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# Discover pinned Helm chart versions and container images for:
#   - Phase 1: Operators (cert-manager, CFK, Flink Operator, ArgoCD)
#   - Phase 2: Phase 1 + CMF + Flink SQL runtime
#   - Phase 3: Phase 2 + Confluent Platform components on K8s
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
#   - Prints chart versions and images to stdout
#   - Writes images-phase{1,2,3}.txt to the repo root (one image per line)
#     These files are the authoritative mirror manifests for JFrog.
#
# Environment variable overrides (optional):
#   CMF_VERSION       CMF chart version        (default: 2.2.0)
#   CP_FLINK_VERSION  Flink SQL runtime tag    (default: 1.19.4-cp1)
#   CP_VERSION        Confluent Platform tag   (default: 8.1.1)
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

# --- Pinned versions (single source of truth) ---
# Phase 1 — Operators
CERT_MANAGER_VERSION="v1.19.4"
CFK_VERSION="0.1351.59"
FLINK_OPERATOR_VERSION="1.130.2"
ARGOCD_VERSION="9.4.7"

# Phase 2 — CMF + Flink runtime
CMF_VERSION="${CMF_VERSION:-2.2.0}"
CP_FLINK_VERSION="${CP_FLINK_VERSION:-1.19.4-cp1}"

# Phase 3 — Confluent Platform on K8s (CFK 3.1.1 aligns with CP 8.1.1)
CP_VERSION="${CP_VERSION:-8.1.1}"

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

extract_images "cert-manager (${CERT_MANAGER_VERSION})" \
  cert-manager jetstack/cert-manager \
  --version "$CERT_MANAGER_VERSION" \
  -f "${REPO_ROOT}/apps/cert-manager/dev/values.yaml" \
  -f "${REPO_ROOT}/apps/cert-manager/openshift-overlay.yaml"

extract_images "confluent-for-kubernetes (${CFK_VERSION})" \
  confluent-operator confluent/confluent-for-kubernetes \
  --version "$CFK_VERSION" \
  -f "${REPO_ROOT}/apps/confluent-operator/dev/values.yaml" \
  -f "${REPO_ROOT}/apps/confluent-operator/openshift-overlay.yaml"

extract_images "flink-kubernetes-operator (${FLINK_OPERATOR_VERSION})" \
  flink-operator confluent/flink-kubernetes-operator \
  --version "$FLINK_OPERATOR_VERSION" \
  -f "${REPO_ROOT}/apps/confluent-flink-operator/dev/values.yaml" \
  -f "${REPO_ROOT}/apps/confluent-flink-operator/openshift-overlay.yaml"

extract_images "argo-cd (${ARGOCD_VERSION})" \
  argocd argo-cd/argo-cd \
  --version "$ARGOCD_VERSION" \
  -f "${REPO_ROOT}/apps/argocd/dev/values.yaml"

# Write Phase 1 manifest
sort -u "$ALL_IMAGES" > "${REPO_ROOT}/images-phase1.txt"
echo "  >> Wrote ${REPO_ROOT}/images-phase1.txt ($(wc -l < "${REPO_ROOT}/images-phase1.txt" | tr -d ' ') images)"
echo ""

# ========================================
#  Phase 2 — CMF + Flink Runtime
# ========================================

if [[ "$PHASE" -ge 2 ]]; then
  echo "=== Phase 2: CMF + Flink Runtime ==="
  echo "  CMF_VERSION=${CMF_VERSION}  CP_FLINK_VERSION=${CP_FLINK_VERSION}"
  echo ""

  extract_images "confluent-manager-for-apache-flink (${CMF_VERSION})" \
    cmf confluent/confluent-manager-for-apache-flink \
    --version "$CMF_VERSION"

  add_static_image "cp-flink SQL runtime (${CP_FLINK_VERSION})" \
    "docker.io/confluentinc/cp-flink:${CP_FLINK_VERSION}"

  # Write Phase 2 manifest (superset of Phase 1)
  sort -u "$ALL_IMAGES" > "${REPO_ROOT}/images-phase2.txt"
  echo "  >> Wrote ${REPO_ROOT}/images-phase2.txt ($(wc -l < "${REPO_ROOT}/images-phase2.txt" | tr -d ' ') images)"
  echo ""
fi

# ========================================
#  Phase 3 — Confluent Platform on K8s
# ========================================

if [[ "$PHASE" -ge 3 ]]; then
  echo "=== Phase 3: Confluent Platform Components (CP ${CP_VERSION}) ==="
  echo ""

  # CFK init container — required for all CFK-managed CRs
  add_static_image "confluent-init-container (3.1.1)" \
    "docker.io/confluentinc/confluent-init-container:3.1.1"

  # CP component images
  for component in cp-server cp-schema-registry cp-kafka-connect cp-enterprise-control-center cp-ksqldb-server cp-kafka-rest cp-zookeeper; do
    add_static_image "${component} (${CP_VERSION})" \
      "docker.io/confluentinc/${component}:${CP_VERSION}"
  done

  # Write Phase 3 manifest (superset of Phase 1 + 2)
  sort -u "$ALL_IMAGES" > "${REPO_ROOT}/images-phase3.txt"
  echo "  >> Wrote ${REPO_ROOT}/images-phase3.txt ($(wc -l < "${REPO_ROOT}/images-phase3.txt" | tr -d ' ') images)"
  echo ""
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
