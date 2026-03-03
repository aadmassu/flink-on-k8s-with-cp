#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# Discover latest Helm chart versions and container image tags for:
#   - Operators (cert-manager, CFK, Flink Operator, ArgoCD)
#   - Confluent Platform components (for future phases)
#   - Apache Flink runtime (for future phases)
# ============================================================================

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

echo ""
echo "========================================"
echo "  Container Images — Latest Tags"
echo "========================================"

DOCKER_HUB_API="https://hub.docker.com/v2/repositories/confluentinc"

fetch_latest_tag() {
  local image=$1
  local filter=${2:-""}
  local url="${DOCKER_HUB_API}/${image}/tags/?page_size=100"
  if [ -n "$filter" ]; then
    url="${url}&name=${filter}"
  fi
  curl -s "$url" 2>/dev/null \
    | python3 -c "
import sys, json
d = json.load(sys.stdin)
prefix = '${filter}'
tags = [r['name'] for r in d.get('results', [])
        if not any(s in r['name'] for s in ['amd64', 'arm64', 's390x', 'beta'])
        and (not prefix or r['name'].startswith(prefix))]
def ver_key(v):
    parts = v.replace('-', '.').split('.')
    return tuple(int(p) if p.isdigit() else 0 for p in parts)
tags.sort(key=ver_key, reverse=True)
print(tags[0] if tags else 'N/A')
" 2>/dev/null || echo "N/A"
}

echo ""
echo "--- Operators (Phase 1) ---"
printf "%-55s %s\n" "IMAGE" "LATEST TAG"
echo "-------------------------------------------------------+------------------"

for img in confluent-operator confluent-init-container; do
  tag=$(fetch_latest_tag "$img")
  printf "%-55s %s\n" "confluentinc/${img}" "$tag"
done

tag=$(fetch_latest_tag "cp-flink-kubernetes-operator" "1.13.0-cp")
printf "%-55s %s\n" "confluentinc/cp-flink-kubernetes-operator" "$tag"

echo ""
echo "--- Confluent Platform (Phase 2/3 — for reference) ---"
printf "%-55s %s\n" "IMAGE" "LATEST TAG"
echo "-------------------------------------------------------+------------------"

for img in cp-server cp-kafka cp-schema-registry cp-kafka-connect cp-kafka-rest cp-ksqldb-server; do
  tag=$(fetch_latest_tag "$img" "8.1")
  printf "%-55s %s\n" "confluentinc/${img}" "$tag"
done

tag=$(fetch_latest_tag "cp-enterprise-control-center" "7.8")
printf "%-55s %s\n" "confluentinc/cp-enterprise-control-center" "$tag"

echo ""
echo "--- Apache Flink Runtime (Phase 2/3 — for reference) ---"
printf "%-55s %s\n" "IMAGE" "LATEST TAG"
echo "-------------------------------------------------------+------------------"

for flink_ver in 1.19 1.18; do
  tag=$(fetch_latest_tag "cp-flink" "${flink_ver}")
  printf "%-55s %s\n" "confluentinc/cp-flink (${flink_ver})" "$tag"
done

echo ""
echo "--- cert-manager ---"
printf "%-55s %s\n" "IMAGE" "LATEST TAG"
echo "-------------------------------------------------------+------------------"

JETSTACK_API="https://quay.io/api/v1/repository/jetstack"
for img in cert-manager-controller cert-manager-webhook cert-manager-cainjector cert-manager-startupapicheck; do
  tag=$(curl -s "${JETSTACK_API}/${img}/tag/?limit=50&onlyActiveTags=true" 2>/dev/null \
    | python3 -c "
import sys, json
d = json.load(sys.stdin)
tags = [t['name'] for t in d.get('tags', [])
        if t['name'].startswith('v') and '.' in t['name']
        and 'alpha' not in t['name'] and 'beta' not in t['name'] and 'rc' not in t['name']]
def ver_key(v):
    parts = v.lstrip('v').split('.')
    return tuple(int(p) for p in parts if p.isdigit())
tags.sort(key=ver_key, reverse=True)
print(tags[0] if tags else 'N/A')
" 2>/dev/null || echo "N/A")
  printf "%-55s %s\n" "quay.io/jetstack/${img}" "$tag"
done

echo ""
echo "--- ArgoCD ---"
printf "%-55s %s\n" "IMAGE" "LATEST TAG"
echo "-------------------------------------------------------+------------------"

QUAY_ARGO_API="https://quay.io/api/v1/repository/argoproj"
tag=$(curl -s "${QUAY_ARGO_API}/argocd/tag/?limit=10&onlyActiveTags=true" 2>/dev/null \
  | python3 -c "
import sys, json
d = json.load(sys.stdin)
tags = [t['name'] for t in d.get('tags', []) if t['name'].startswith('v') and '.' in t['name'] and 'alpha' not in t['name'] and 'beta' not in t['name'] and 'rc' not in t['name']]
print(tags[0] if tags else 'N/A')
" 2>/dev/null || echo "N/A")
printf "%-55s %s\n" "quay.io/argoproj/argocd" "$tag"

echo ""
echo "Done."
