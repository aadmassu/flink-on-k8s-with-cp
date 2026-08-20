#!/usr/bin/env bash
set -euo pipefail

NS="${OC_NS:-dah-flink-dev}"
USER_ID="00u1u5ovirxMj7Aq0358"
GROUP_ID="dv_app_okta_digital_analytics_hub_developers"
LABEL="rbac.fcbint.net/managed-by=application-onboarding"

echo "============================================================"
echo "DEV C3 RBAC visibility diagnostic (read-only)"
echo "Namespace: $NS"
echo "User:      $USER_ID"
echo "Group:     $GROUP_ID"
echo "============================================================"

command -v oc >/dev/null 2>&1 || { echo "FATAL: oc is unavailable"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "FATAL: python3 is unavailable"; exit 1; }

echo
echo "=== 1. Component readiness and reported cluster identifiers ==="
for pair in "kafka kafka" "schemaregistry schemaregistry" "connect connect" "controlcenter controlcenter"; do
  kind=${pair% *}
  name=${pair#* }
  echo
  echo "--- $kind/$name ---"
  if ! oc -n "$NS" get "$kind" "$name" -o json >/tmp/cfk-component.json 2>/dev/null; then
    echo "FAIL: $kind/$name does not exist"
    continue
  fi
  python3 - "$kind" "$name" </tmp/cfk-component.json <<'PY'
import json, sys
kind, name = sys.argv[1:]
obj = json.load(sys.stdin)
status = obj.get("status") or {}
conditions = status.get("conditions") or []
print("generation=%s observedGeneration=%s" %
      ((obj.get("metadata") or {}).get("generation"), status.get("observedGeneration")))
for condition in conditions:
    print("condition %s=%s reason=%s" %
          (condition.get("type"), condition.get("status"), condition.get("reason", "")))

def walk(value, path="status"):
    if isinstance(value, dict):
        for key, child in value.items():
            new_path = path + "." + str(key)
            if "clusterid" in str(key).lower() or "cluster_id" in str(key).lower():
                print("%s=%r" % (new_path, child))
            walk(child, new_path)
    elif isinstance(value, list):
        for index, child in enumerate(value):
            walk(child, "%s[%d]" % (path, index))
walk(status)
PY
done
rm -f /tmp/cfk-component.json

echo
echo "=== 2. Application-onboarding ConfluentRolebinding state ==="
oc -n "$NS" get confluentrolebinding -l "$LABEL" -o json >/tmp/onboarding-rbac.json
set +e
python3 - "$USER_ID" "$GROUP_ID" </tmp/onboarding-rbac.json <<'PY'
import json, sys
user_id, group_id = sys.argv[1:]
obj = json.load(sys.stdin)
items = obj.get("items") or []
expected = {
    ("user", user_id, "ClusterAdmin", "kafka"),
    ("user", user_id, "SystemAdmin", "schemaRegistryClusterId"),
    ("user", user_id, "SystemAdmin", "connectClusterId"),
    ("group", group_id, "ClusterAdmin", "kafka"),
    ("group", group_id, "SystemAdmin", "schemaRegistryClusterId"),
    ("group", group_id, "SystemAdmin", "connectClusterId"),
}
observed = set()
not_ready = []

for item in sorted(items, key=lambda x: (x.get("metadata") or {}).get("name", "")):
    metadata = item.get("metadata") or {}
    spec = item.get("spec") or {}
    status = item.get("status") or {}
    principal = spec.get("principal") or {}
    scope = spec.get("clustersScopeByIds") or {}
    if "schemaRegistryClusterId" in scope:
        scope_type = "schemaRegistryClusterId"
        scope_value = scope.get(scope_type)
    elif "connectClusterId" in scope:
        scope_type = "connectClusterId"
        scope_value = scope.get(scope_type)
    else:
        scope_type = "kafka"
        scope_value = "KafkaRestClass/default"
    condition_map = dict((c.get("type"), c.get("status")) for c in (status.get("conditions") or []))
    ready = any((key == "app-ready" or key.endswith("/app-ready")) and value == "True"
                for key, value in condition_map.items())
    key = (principal.get("type"), principal.get("name"), spec.get("role"), scope_type)
    observed.add(key)
    print("name=%s principal=%s:%s role=%s scope=%s:%s app-ready=%s" %
          (metadata.get("name"), principal.get("type"), principal.get("name"),
           spec.get("role"), scope_type, scope_value, ready))
    if not ready:
        not_ready.append(metadata.get("name"))
    for field in ("clusterId", "kafkaClusterId", "schemaRegistryClusterId", "connectClusterId"):
        if field in status:
            print("  status.%s=%r" % (field, status.get(field)))

missing = sorted(expected - observed)
unexpected = sorted(observed - expected)
print("summary total=%d expected=%d missing=%d unexpected=%d not_ready=%d" %
      (len(items), len(expected), len(missing), len(unexpected), len(not_ready)))
for value in missing:
    print("MISSING: %r" % (value,))
for value in unexpected:
    print("UNEXPECTED: %r" % (value,))
for value in not_ready:
    print("NOT_READY: %s" % value)
if missing or not_ready:
    sys.exit(2)
PY
rbac_rc=$?
set -e
rm -f /tmp/onboarding-rbac.json
if [ "$rbac_rc" -ne 0 ]; then
  echo "FAIL: onboarding RBAC is incomplete or not reconciled."
else
  echo "PASS: all six expected onboarding bindings are app-ready."
fi

echo
echo "=== 3. Relevant Control Center authorization evidence (last 60m) ==="
if oc -n "$NS" get pod controlcenter-0 >/dev/null 2>&1; then
  oc -n "$NS" logs controlcenter-0 -c controlcenter --since=60m 2>&1 | \
    grep -Ei -C 3 "$USER_ID|$GROUP_ID|forbidden|not authorized|authorization denied|ClusterAdmin|SystemAdmin|role.?binding|principal|rbac|403" | \
    tail -n 300 || echo "INFO: no matching C3 log lines found"
else
  echo "FAIL: pod/controlcenter-0 does not exist"
fi

echo
echo "=== 4. Relevant Kafka/MDS authorization evidence (last 60m) ==="
for pod in $(oc -n "$NS" get pods -o name 2>/dev/null | sed -n 's#^pod/\(kafka-[0-9][0-9]*\)$#\1#p'); do
  echo "--- $pod ---"
  oc -n "$NS" logs "$pod" -c kafka --since=60m 2>&1 | \
    grep -Ei -C 3 "$USER_ID|$GROUP_ID|forbidden|not authorized|authorization denied|ClusterAdmin|SystemAdmin|role.?binding|principal|rbac|403" | \
    tail -n 200 || echo "INFO: no matching MDS log lines found in $pod"
done

echo
echo "=== 5. Recent rolebinding events ==="
oc -n "$NS" get events --sort-by=.lastTimestamp 2>/dev/null | \
  grep -Ei 'ConfluentRolebinding|rolebinding|FailedToDiscover|app-ready' | tail -n 100 || \
  echo "INFO: no matching rolebinding events"

echo
if [ "$rbac_rc" -ne 0 ]; then
  echo "RESULT: RBAC reconciliation failed. Fix the CRs before another C3 login test."
  exit "$rbac_rc"
fi
echo "RESULT: CRs are reconciled. Perform one fresh C3 sign-out/sign-in, then rerun this script immediately so Sections 3-4 capture the authenticated principal and denial."