#!/usr/bin/env bash
set -euo pipefail

# DEV Control Center ingress repair and verification.
# Run from the repository root through validate-confluent-platform.yaml.
# No jq dependency. Python 3.6+ stdlib only.

NAMESPACE="${1:-dah-flink-dev}"
NP_FILE="${NP_FILE:-apps/confluent-platform/dev/network-policy/network-policy.yaml}"
NP_NAME="${NP_NAME:-allow-from-confluent-operator}"
C3_HOST="${C3_HOST:-controlcenter.apps.dv.ocp.fcbint.net}"
C3_SERVICE="${C3_SERVICE:-controlcenter}"
C3_PORT="${C3_PORT:-9021}"
ROUTE_NAME="${ROUTE_NAME:-controlcenter-ggdn9}"

fatal() { echo "FATAL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

find_python() {
  local candidate
  for candidate in python3 python; do
    if command -v "$candidate" >/dev/null 2>&1 && \
       "$candidate" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3,6) else 1)' 2>/dev/null; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

command -v oc >/dev/null 2>&1 || fatal "oc is not available"
command -v curl >/dev/null 2>&1 || fatal "curl is not available"
PYTHON_BIN="$(find_python)" || fatal "Python 3.6 or newer is required"
WORK_DIR="$(mktemp -d "${AGENT_TEMPDIRECTORY:-/tmp}/c3-ingress-check.XXXXXX")"
cleanup() { rm -rf "$WORK_DIR"; }
trap cleanup EXIT
oc whoami >/dev/null 2>&1 || fatal "not logged into OpenShift"
oc -n "$NAMESPACE" get namespace "$NAMESPACE" >/dev/null 2>&1 || fatal "namespace $NAMESPACE is inaccessible"

echo "============================================================"
echo "DEV Control Center ingress repair and verification"
echo "Namespace: $NAMESPACE"
echo "Host:      $C3_HOST"
echo "============================================================"

echo
echo "=== 1. Apply repository-managed NetworkPolicy ==="
[ -f "$NP_FILE" ] || fatal "NetworkPolicy manifest not found: $NP_FILE (run from repository root)"
oc apply -f "$NP_FILE"

echo
echo "=== 2. Verify router selector and required ports ==="
oc -n "$NAMESPACE" get networkpolicy "$NP_NAME" -o json >"$WORK_DIR/networkpolicy.json"
"$PYTHON_BIN" - "$WORK_DIR/networkpolicy.json" "$C3_PORT" <<'PY'
import json, sys
required_port = int(sys.argv[2])
with open(sys.argv[1]) as stream:
    doc = json.load(stream)
matched = False
ports = set()
for rule in doc.get("spec", {}).get("ingress", []):
    for source in rule.get("from", []):
        labels = source.get("namespaceSelector", {}).get("matchLabels", {})
        if labels.get("kubernetes.io/metadata.name") == "openshift-ingress":
            matched = True
            for entry in rule.get("ports", []):
                try:
                    ports.add(int(entry.get("port")))
                except (TypeError, ValueError):
                    pass
if not matched:
    print("FATAL: policy has no openshift-ingress namespace-name selector", file=sys.stderr)
    raise SystemExit(1)
if required_port not in ports:
    print("FATAL: router rule does not permit TCP port %s" % required_port, file=sys.stderr)
    raise SystemExit(1)
print("PASS: router selector is kubernetes.io/metadata.name=openshift-ingress")
print("PASS: router rule permits ports: %s" % ", ".join(str(x) for x in sorted(ports)))
PY

echo
echo "=== 3. Verify Control Center pod and Service ==="
oc -n "$NAMESPACE" get pod controlcenter-0 >/dev/null 2>&1 || fatal "Pod/controlcenter-0 does not exist"
C3_READY="$(oc -n "$NAMESPACE" get pod controlcenter-0 -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')"
[ "$C3_READY" = "True" ] || fatal "Pod/controlcenter-0 is not Ready (Ready=$C3_READY)"
pass "Pod/controlcenter-0 is Ready"

SERVICE_PORT="$(oc -n "$NAMESPACE" get service "$C3_SERVICE" -o jsonpath='{.spec.ports[?(@.name=="external")].port}')"
[ "$SERVICE_PORT" = "$C3_PORT" ] || fatal "Service/$C3_SERVICE external port is ${SERVICE_PORT:-missing}; expected $C3_PORT"
pass "Service/$C3_SERVICE exposes external port $C3_PORT"

echo
echo "=== 4. Verify ready EndpointSlices across all slices ==="
oc -n "$NAMESPACE" get endpointslices.discovery.k8s.io \
  -l "kubernetes.io/service-name=$C3_SERVICE" -o json >"$WORK_DIR/endpointslices.json"
"$PYTHON_BIN" - "$WORK_DIR/endpointslices.json" <<'PY'
import json, sys
with open(sys.argv[1]) as stream:
    doc = json.load(stream)
ready = []
for item in doc.get("items", []):
    for endpoint in item.get("endpoints", []):
        condition = endpoint.get("conditions", {}).get("ready")
        addresses = endpoint.get("addresses") or []
        if addresses and condition is not False:
            ready.extend(addresses)
if not ready:
    print("FATAL: no ready Control Center endpoint exists", file=sys.stderr)
    raise SystemExit(1)
print("PASS: ready Control Center endpoint(s): %s" % ", ".join(ready))
PY

echo
echo "=== 5. Verify generated Route ==="
if ! oc -n "$NAMESPACE" get route "$ROUTE_NAME" >/dev/null 2>&1; then
  ROUTE_NAME="$(oc -n "$NAMESPACE" get route -l app.kubernetes.io/instance=controlcenter -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
fi
[ -n "$ROUTE_NAME" ] || fatal "no generated Control Center Route found"

ADMITTED="$(oc -n "$NAMESPACE" get route "$ROUTE_NAME" -o jsonpath='{.status.ingress[0].conditions[?(@.type=="Admitted")].status}')"
[ "$ADMITTED" = "True" ] || fatal "Route/$ROUTE_NAME is not admitted (Admitted=$ADMITTED)"
TERMINATION="$(oc -n "$NAMESPACE" get route "$ROUTE_NAME" -o jsonpath='{.spec.tls.termination}')"
[ "$TERMINATION" = "reencrypt" ] || fatal "Route/$ROUTE_NAME termination is ${TERMINATION:-missing}; expected reencrypt"
DEST_CA="$(oc -n "$NAMESPACE" get route "$ROUTE_NAME" -o jsonpath='{.spec.tls.destinationCACertificate}')"
[ -n "$DEST_CA" ] || fatal "Route/$ROUTE_NAME has no destination CA certificate"
TARGET_PORT="$(oc -n "$NAMESPACE" get route "$ROUTE_NAME" -o jsonpath='{.spec.port.targetPort}')"
[ "$TARGET_PORT" = "external" ] || fatal "Route/$ROUTE_NAME targetPort is ${TARGET_PORT:-missing}; expected external"
pass "Route/$ROUTE_NAME is admitted with reencrypt TLS, destination CA, and targetPort=external"

echo
echo "=== 6. Test public Control Center endpoint ==="
HTTP_CODE="$(curl -sS --connect-timeout 10 --max-time 30 -o "$WORK_DIR/c3-response" -w '%{http_code}' "https://$C3_HOST/" || true)"
case "$HTTP_CODE" in
  200|301|302|303|307|308|401|403)
    pass "https://$C3_HOST returned HTTP $HTTP_CODE (router and backend are reachable)"
    ;;
  503)
    fatal "https://$C3_HOST returned HTTP 503; inspect router-to-backend connectivity and C3 TLS logs"
    ;;
  000|"")
    fatal "unable to establish HTTPS connection to $C3_HOST"
    ;;
  *)
    fatal "https://$C3_HOST returned unexpected HTTP $HTTP_CODE"
    ;;
esac

echo
echo "SUCCESS: Control Center ingress repair and validation passed."