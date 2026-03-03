#!/usr/bin/env bash
set -euo pipefail

# Ensure repos are up to date
helm repo update >/dev/null 2>&1

echo "ApplicationSet Pinned Version Check"
echo "===================================="
printf "%-35s %-15s %-10s\n" "CHART" "PINNED" "STATUS"
echo "-----------------------------------+--------------+----------"

check() {
  local repo=$1 chart=$2 version=$3
  local found
  found=$(helm search repo "${repo}/${chart}" --version "$version" \
    --output json 2>/dev/null \
    | grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' \
    | head -1 | cut -d'"' -f4) || true
  if [ "$found" = "$version" ]; then
    printf "%-35s %-15s %-10s\n" "$chart" "$version" "OK"
  else
    printf "%-35s %-15s %-10s\n" "$chart" "$version" "NOT FOUND"
  fi
}

check jetstack    cert-manager                    "v1.19.4"
check confluent   confluent-for-kubernetes        "0.1351.59"
check confluent   flink-kubernetes-operator       "1.130.2"
check argo-cd     argo-cd                         "9.4.7"
