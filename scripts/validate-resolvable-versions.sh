#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# Validate that pinned chart versions resolve in Helm repos.
#
# Usage:
#   ./validate-resolvable-versions.sh            # check public repos (default)
#   ./validate-resolvable-versions.sh --internal  # check internal repo alias
#
# When --internal is used (or HELM_REPO=internal is set), the script checks
# the "internal" Helm repo alias instead of the public repos. You must have
# already run:
#   helm repo add internal https://artifactory.example.com/artifactory/helm-virtual
#
# Validation uses `helm show chart` which actually fetches chart metadata —
# a stronger signal than grepping `helm search` output.
# ============================================================================

MODE="public"
INTERNAL_REPO="${HELM_REPO:-}"

if [[ "${1:-}" == "--internal" ]] || [[ "$INTERNAL_REPO" == "internal" ]]; then
  MODE="internal"
  INTERNAL_REPO="${INTERNAL_REPO:-internal}"
fi

# Ensure repos are up to date
helm repo update >/dev/null 2>&1

echo "ApplicationSet Pinned Version Check (${MODE} repos)"
echo "===================================="
printf "%-35s %-15s %-10s\n" "CHART" "PINNED" "STATUS"
echo "-----------------------------------+--------------+----------"

check() {
  local repo=$1 chart=$2 version=$3
  # helm show chart fetches actual chart metadata — confirms the version is pullable
  local found
  found=$(helm show chart "${repo}/${chart}" --version "$version" 2>/dev/null \
    | grep -E '^version:' \
    | awk '{print $2}') || true
  if [ "$found" = "$version" ]; then
    printf "%-35s %-15s %-10s\n" "$chart" "$version" "OK"
  else
    printf "%-35s %-15s %-10s\n" "$chart" "$version" "NOT FOUND"
  fi
}

if [ "$MODE" = "internal" ]; then
  check "$INTERNAL_REPO"  cert-manager                    "v1.19.4"
  check "$INTERNAL_REPO"  confluent-for-kubernetes        "0.1351.59"
  check "$INTERNAL_REPO"  flink-kubernetes-operator       "1.130.2"
  check "$INTERNAL_REPO"  argo-cd                         "9.4.7"
else
  check jetstack    cert-manager                    "v1.19.4"
  check confluent   confluent-for-kubernetes        "0.1351.59"
  check confluent   flink-kubernetes-operator       "1.130.2"
  check argo-cd     argo-cd                         "9.4.7"
fi
