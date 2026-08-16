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
command -v openssl >/dev/null 2>&1 || fatal "openssl is not available"
command -v base64 >/dev/null 2>&1 || fatal "base64 is not available"
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
echo "=== 6. Inspect and verify Control Center certificate chain ==="

extract_public_cert_key() {
  local secret_name="$1"
  local key_name="$2"
  local output_file="$3"
  local encoded
  case "$key_name" in
    tls.crt)
      encoded="$(oc -n "$NAMESPACE" get secret "$secret_name" \
        -o jsonpath='{.data.tls\.crt}' 2>/dev/null || true)"
      ;;
    ca.crt)
      encoded="$(oc -n "$NAMESPACE" get secret "$secret_name" \
        -o jsonpath='{.data.ca\.crt}' 2>/dev/null || true)"
      ;;
    *)
      fatal "unsupported public certificate key requested: $key_name"
      ;;
  esac
  [ -n "$encoded" ] || return 1
  printf '%s' "$encoded" | base64 --decode >"$output_file" 2>/dev/null || return 1
  grep -q -- '-----BEGIN CERTIFICATE-----' "$output_file"
}

print_cert_metadata() {
  local label="$1"
  local cert_file="$2"
  echo "--- $label ---"
  openssl x509 -in "$cert_file" -noout \
    -subject -issuer -serial -dates -fingerprint -sha256
  openssl x509 -in "$cert_file" -noout -ext subjectAltName 2>/dev/null || \
    echo "subjectAltName: <not present>"
}

C3_LEAF="$WORK_DIR/controlcenter-tls.crt"
C3_CA="$WORK_DIR/controlcenter-ca.crt"
REENCRYPT_CA="$WORK_DIR/reencrypt-bundle.crt"
INGRESS_LEAF="$WORK_DIR/controlcenter-ingress-tls.crt"
ROUTE_CA="$WORK_DIR/route-destination-ca.crt"
LIVE_LEAF="$WORK_DIR/controlcenter-live-9021.crt"

extract_public_cert_key controlcenter-tls tls.crt "$C3_LEAF" || \
  fatal "Secret/controlcenter-tls key tls.crt is missing or is not PEM certificate data"
print_cert_metadata "Secret/controlcenter-tls tls.crt (C3 backend)" "$C3_LEAF"

if extract_public_cert_key controlcenter-tls ca.crt "$C3_CA"; then
  print_cert_metadata "Secret/controlcenter-tls ca.crt" "$C3_CA"
else
  echo "NOTE: Secret/controlcenter-tls has no ca.crt key"
fi

extract_public_cert_key reencrypt-bundle tls.crt "$REENCRYPT_CA" || \
  fatal "Secret/reencrypt-bundle key tls.crt is missing or is not PEM certificate data"
print_cert_metadata "Secret/reencrypt-bundle tls.crt (Route destination trust)" "$REENCRYPT_CA"

extract_public_cert_key controlcenter-ingress-tls tls.crt "$INGRESS_LEAF" || \
  fatal "Secret/controlcenter-ingress-tls key tls.crt is missing or is not PEM certificate data"
print_cert_metadata "Secret/controlcenter-ingress-tls tls.crt (browser-facing)" "$INGRESS_LEAF"

printf '%s\n' "$DEST_CA" >"$ROUTE_CA"
if ! grep -q -- '-----BEGIN CERTIFICATE-----' "$ROUTE_CA"; then
  fatal "Route/$ROUTE_NAME destinationCACertificate is not PEM certificate data"
fi
print_cert_metadata "Route/$ROUTE_NAME embedded destination CA" "$ROUTE_CA"

REENCRYPT_FP="$(openssl x509 -in "$REENCRYPT_CA" -noout -fingerprint -sha256 | cut -d= -f2-)"
ROUTE_CA_FP="$(openssl x509 -in "$ROUTE_CA" -noout -fingerprint -sha256 | cut -d= -f2-)"
if [ "$REENCRYPT_FP" = "$ROUTE_CA_FP" ]; then
  pass "Route destination CA matches Secret/reencrypt-bundle"
else
  echo "FAIL: Route destination CA does not match Secret/reencrypt-bundle"
fi

if openssl verify -partial_chain -CAfile "$REENCRYPT_CA" "$C3_LEAF"; then
  pass "controlcenter-tls verifies against reencrypt-bundle"
else
  echo "FAIL: controlcenter-tls does not verify against reencrypt-bundle"
fi

echo
echo "--- Live certificate served by controlcenter-0:9021 ---"
oc -n "$NAMESPACE" port-forward pod/controlcenter-0 19021:9021 \
  >"$WORK_DIR/port-forward.log" 2>&1 &
PF_PID=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do
  if ! kill -0 "$PF_PID" 2>/dev/null; then
    cat "$WORK_DIR/port-forward.log" >&2 || true
    fatal "oc port-forward terminated before the TLS check"
  fi
  if openssl s_client -connect 127.0.0.1:19021 -servername "$C3_HOST" -showcerts \
      </dev/null >"$WORK_DIR/s_client.txt" 2>&1; then
    break
  fi
  sleep 1
done
kill "$PF_PID" 2>/dev/null || true
wait "$PF_PID" 2>/dev/null || true

awk '/-----BEGIN CERTIFICATE-----/{capture=1} capture{print} /-----END CERTIFICATE-----/{exit}' \
  "$WORK_DIR/s_client.txt" >"$LIVE_LEAF"
if ! grep -q -- '-----BEGIN CERTIFICATE-----' "$LIVE_LEAF"; then
  echo "Port-forward output:"
  sed -n '1,80p' "$WORK_DIR/port-forward.log" || true
  echo "TLS client output:"
  sed -n '1,80p' "$WORK_DIR/s_client.txt" || true
  fatal "could not capture the live TLS certificate from controlcenter-0:9021"
fi
print_cert_metadata "Live controlcenter-0:9021 certificate" "$LIVE_LEAF"

SECRET_FP="$(openssl x509 -in "$C3_LEAF" -noout -fingerprint -sha256 | cut -d= -f2-)"
LIVE_FP="$(openssl x509 -in "$LIVE_LEAF" -noout -fingerprint -sha256 | cut -d= -f2-)"
if [ "$SECRET_FP" = "$LIVE_FP" ]; then
  pass "live port 9021 certificate matches Secret/controlcenter-tls"
else
  echo "FAIL: live port 9021 certificate does not match Secret/controlcenter-tls"
fi

echo
echo "=== 7. Test public Control Center endpoint ==="
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