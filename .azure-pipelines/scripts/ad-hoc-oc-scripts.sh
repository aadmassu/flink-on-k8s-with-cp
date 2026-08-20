#!/usr/bin/env bash
set -euo pipefail

NS="${OC_NS:-dah-flink-dev}"
LABEL="rbac.fcbint.net/managed-by=application-onboarding"

echo "============================================================"
echo "Force-reconcile application-onboarding ConfluentRolebindings"
echo "Namespace: $NS"
echo "Selector:  $LABEL"
echo "============================================================"

mapfile -t bindings < <(oc -n "$NS" get confluentrolebinding \
  -l "$LABEL" -o name 2>/dev/null | sort)

if [ "${#bindings[@]}" -ne 6 ]; then
  echo "FATAL: expected exactly 6 onboarding bindings; found ${#bindings[@]}."
  printf '  %s\n' "${bindings[@]:-<none>}"
  exit 1
fi

echo
echo "=== 1. Current state ==="
for binding in "${bindings[@]}"; do
  status=$(oc -n "$NS" get "$binding" -o jsonpath='{.status}' 2>/dev/null || true)
  finalizers=$(oc -n "$NS" get "$binding" -o jsonpath='{.metadata.finalizers}' 2>/dev/null || true)
  echo "$binding status=${status:-<empty>} finalizers=${finalizers:-<none>}"
done

echo
echo "=== 2. Request CFK reconciliation ==="
for binding in "${bindings[@]}"; do
  echo "+ oc -n $NS annotate $binding platform.confluent.io/force-reconcile=true --overwrite"
  oc -n "$NS" annotate "$binding" \
    platform.confluent.io/force-reconcile=true --overwrite
done

echo
echo "=== 3. Wait up to 300s for all bindings to become app-ready ==="
deadline=$((SECONDS + 300))
while [ "$SECONDS" -lt "$deadline" ]; do
  ready_count=0
  touched_count=0

  for binding in "${bindings[@]}"; do
    conditions=$(oc -n "$NS" get "$binding" \
      -o jsonpath='{range .status.conditions[*]}{.type}={.status}{"\n"}{end}' \
      2>/dev/null || true)
    finalizers=$(oc -n "$NS" get "$binding" \
      -o jsonpath='{.metadata.finalizers}' 2>/dev/null || true)

    if [ -n "$conditions" ] || [ -n "$finalizers" ]; then
      touched_count=$((touched_count + 1))
    fi
    if printf '%s\n' "$conditions" | \
        grep -Eq '(^|/)app-ready=True$'; then
      ready_count=$((ready_count + 1))
    fi
  done

  echo "elapsed=$((300 - (deadline - SECONDS)))s operator-touched=$touched_count/6 app-ready=$ready_count/6"
  if [ "$ready_count" -eq 6 ]; then
    echo "PASS: all six onboarding bindings reconciled successfully."
    exit 0
  fi
  sleep 10
done

echo
echo "=== 4. Failure evidence ==="
for binding in "${bindings[@]}"; do
  echo
  echo "--- $binding ---"
  oc -n "$NS" describe "$binding" 2>&1 || true
done

echo
echo "FATAL: CFK did not make all onboarding bindings app-ready within 300s."
echo "If operator-touched remained 0/6, the CFK rolebinding controller is not"
echo "watching/reconciling these CRs. Escalate to the confluent-operator owner"
echo "with this output and request operator logs for these six resource names."
exit 2