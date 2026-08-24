#!/usr/bin/env bash

set -euo pipefail

NS="${1:?Usage: $0 <namespace>}"
OAUTH_SECRET="${OAUTH_SECRET:-oauth-connect}"
TOKEN_ENDPOINT="${TOKEN_ENDPOINT:-}"
OAUTH_SCOPE="${OAUTH_SCOPE:-}"

MDS_SERVICE="${MDS_SERVICE:-kafka}"
MDS_HOST="${MDS_HOST:-kafka.${NS}.svc.cluster.local}"
MDS_LOCAL_PORT="${MDS_LOCAL_PORT:-18090}"
MDS_REMOTE_PORT="${MDS_REMOTE_PORT:-8090}"
MDS_CA_SECRET="${MDS_CA_SECRET:-kafka-tls}"

CONNECT_SERVICE="${CONNECT_SERVICE:-connect}"
CONNECT_HOST="${CONNECT_HOST:-connect.${NS}.svc.cluster.local}"
CONNECT_LOCAL_PORT="${CONNECT_LOCAL_PORT:-18083}"
CONNECT_REMOTE_PORT="${CONNECT_REMOTE_PORT:-8083}"
CONNECT_CA_SECRET="${CONNECT_CA_SECRET:-connect-tls}"

WORK_DIR="$(mktemp -d)"
MDS_PF_PID=""
CONNECT_PF_PID=""

cleanup() {
  if [ -n "$MDS_PF_PID" ]; then kill "$MDS_PF_PID" 2>/dev/null || true; fi
  if [ -n "$CONNECT_PF_PID" ]; then kill "$CONNECT_PF_PID" 2>/dev/null || true; fi
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT INT TERM

fatal() {
  echo "FATAL: $*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fatal "Required command not found: $1"
}

secret_value() {
  local secret_name="$1"
  local key_name="$2"
  local encoded

  encoded="$(oc -n "$NS" get secret "$secret_name" \
    -o "jsonpath={.data.${key_name}}" 2>/dev/null || true)"
  [ -n "$encoded" ] || fatal "Secret/${secret_name} is missing data key ${key_name}"
  printf '%s' "$encoded" | base64 --decode
}

extract_ca() {
  local secret_name="$1"
  local output_file="$2"
  local encoded

  encoded="$(oc -n "$NS" get secret "$secret_name" \
    -o 'jsonpath={.data.ca\.crt}' 2>/dev/null || true)"
  [ -n "$encoded" ] || fatal "Secret/${secret_name} is missing data key ca.crt"
  printf '%s' "$encoded" | base64 --decode >"$output_file"
  [ -s "$output_file" ] || fatal "Extracted CA from Secret/${secret_name} is empty"
}

wait_for_port_forward() {
  local port="$1"
  local pid="$2"
  local log_file="$3"
  local attempt

  for attempt in $(seq 1 30); do
    kill -0 "$pid" 2>/dev/null || {
      echo "Port-forward output:" >&2
      sed -n '1,120p' "$log_file" >&2 || true
      fatal "Port-forward process exited before localhost:${port} became available"
    }

    if curl --insecure --silent --output /dev/null \
      --connect-timeout 1 --max-time 2 \
      "https://127.0.0.1:${port}/" 2>/dev/null; then
      return 0
    fi
    sleep 1
  done

  echo "Port-forward output:" >&2
  sed -n '1,120p' "$log_file" >&2 || true
  fatal "Timed out waiting for port-forward on localhost:${port}"
}

json_value() {
  local json_file="$1"
  local field_name="$2"
  python3 - "$json_file" "$field_name" <<'PY'
from __future__ import print_function
import json
import sys

with open(sys.argv[1], "r") as handle:
    payload = json.load(handle)
value = payload.get(sys.argv[2], "")
if value is None:
    value = ""
print(value)
PY
}

print_response_summary() {
  local label="$1"
  local status="$2"
  local body_file="$3"

  echo "${label} HTTP status: ${status}"
  python3 - "$body_file" <<'PY'
from __future__ import print_function
import json
import sys

path = sys.argv[1]
try:
    with open(path, "r") as handle:
        body = handle.read()
except Exception as exc:
    print("Response unreadable: {0}".format(exc))
    sys.exit(0)

try:
    value = json.loads(body)
except Exception:
    compact = " ".join(body.split())
    print("Response: {0}".format(compact[:600] if compact else "<empty>"))
    sys.exit(0)

if isinstance(value, list):
    names = []
    for item in value:
        if isinstance(item, dict):
            name = item.get("class") or item.get("name")
            if name:
                names.append(str(name))
    print("Plugin count: {0}".format(len(value)))
    if names:
        print("First plugins: {0}".format(", ".join(names[:10])))
elif isinstance(value, dict):
    safe = {}
    for key in ("error_code", "status_code", "message", "error", "error_description"):
        if key in value:
            safe[key] = value[key]
    print(json.dumps(safe if safe else value, indent=2)[:1000])
else:
    print(str(value)[:600])
PY
}

require_command oc
require_command curl
require_command base64
require_command python3

python3 - <<'PY'
import sys
if sys.version_info < (3, 6):
    raise SystemExit("FATAL: Python 3.6 or newer is required")
print("Python version: {0}.{1}.{2}".format(*sys.version_info[:3]))
PY

# Use the selected environment's live KafkaRestClass OAuth configuration.
# TOKEN_ENDPOINT and OAUTH_SCOPE may still be supplied explicitly as overrides.
if [ -z "$TOKEN_ENDPOINT" ]; then
  TOKEN_ENDPOINT="$(oc -n "$NS" get kafkarestclass default \
    -o 'jsonpath={.spec.kafkaRest.authentication.oauth.configuration.tokenEndpointUri}' 2>/dev/null || true)"
fi
if [ -z "$OAUTH_SCOPE" ]; then
  OAUTH_SCOPE="$(oc -n "$NS" get kafkarestclass default \
    -o 'jsonpath={.spec.kafkaRest.authentication.oauth.configuration.scope}' 2>/dev/null || true)"
fi

[ -n "$TOKEN_ENDPOINT" ] || fatal "Could not discover OAuth tokenEndpointUri from KafkaRestClass/default"
[ -n "$OAUTH_SCOPE" ] || fatal "Could not discover OAuth scope from KafkaRestClass/default"

echo "============================================================"
echo "Connect REST OAuth diagnostic"
echo "Namespace:       $NS"
echo "OAuth Secret:    $OAUTH_SECRET"
echo "OAuth scope:     $OAUTH_SCOPE"
echo "MDS endpoint:    https://${MDS_HOST}:${MDS_REMOTE_PORT}"
echo "Connect endpoint:https://${CONNECT_HOST}:${CONNECT_REMOTE_PORT}"
echo "============================================================"

echo
echo "=== 1. Validate resources and extract CA certificates ==="
oc -n "$NS" get secret "$OAUTH_SECRET" "$MDS_CA_SECRET" "$CONNECT_CA_SECRET" >/dev/null
oc -n "$NS" get service "$MDS_SERVICE" "$CONNECT_SERVICE" >/dev/null
extract_ca "$MDS_CA_SECRET" "$WORK_DIR/mds-ca.crt"
extract_ca "$CONNECT_CA_SECRET" "$WORK_DIR/connect-ca.crt"
echo "PASS: required Secrets, Services, and CA certificates exist"

echo
echo "=== 2. Obtain raw Okta access token for the Connect identity ==="
CLIENT_ID="$(secret_value "$OAUTH_SECRET" clientId)"
CLIENT_SECRET="$(secret_value "$OAUTH_SECRET" clientSecret)"

TOKEN_HTTP_STATUS="$(curl --silent --show-error \
  --output "$WORK_DIR/okta-token.json" \
  --write-out '%{http_code}' \
  --request POST "$TOKEN_ENDPOINT" \
  --user "${CLIENT_ID}:${CLIENT_SECRET}" \
  --header 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode 'grant_type=client_credentials' \
  --data-urlencode "scope=${OAUTH_SCOPE}")"

[ "$TOKEN_HTTP_STATUS" = "200" ] || {
  print_response_summary "Okta token request" "$TOKEN_HTTP_STATUS" "$WORK_DIR/okta-token.json"
  fatal "Could not obtain the Connect OAuth token"
}

OKTA_TOKEN="$(json_value "$WORK_DIR/okta-token.json" access_token)"
[ -n "$OKTA_TOKEN" ] || fatal "Okta response did not contain access_token"
echo "PASS: Okta access token obtained (token value suppressed)"

echo
echo "=== 3. Exchange/validate the Okta token with MDS ==="
oc -n "$NS" port-forward "service/${MDS_SERVICE}" \
  "${MDS_LOCAL_PORT}:${MDS_REMOTE_PORT}" >"$WORK_DIR/mds-port-forward.log" 2>&1 &
MDS_PF_PID=$!
wait_for_port_forward "$MDS_LOCAL_PORT" "$MDS_PF_PID" "$WORK_DIR/mds-port-forward.log"

MDS_HTTP_STATUS="$(curl --silent --show-error \
  --output "$WORK_DIR/mds-auth.json" \
  --write-out '%{http_code}' \
  --cacert "$WORK_DIR/mds-ca.crt" \
  --resolve "${MDS_HOST}:${MDS_LOCAL_PORT}:127.0.0.1" \
  --header "Authorization: Bearer ${OKTA_TOKEN}" \
  "https://${MDS_HOST}:${MDS_LOCAL_PORT}/security/1.0/authenticate")"

[ "$MDS_HTTP_STATUS" = "200" ] || {
  print_response_summary "MDS authentication" "$MDS_HTTP_STATUS" "$WORK_DIR/mds-auth.json"
  fatal "MDS rejected the Connect Okta identity"
}

MDS_TOKEN="$(json_value "$WORK_DIR/mds-auth.json" auth_token)"
[ -n "$MDS_TOKEN" ] || fatal "MDS response did not contain auth_token"
echo "PASS: MDS issued a Confluent token (token value suppressed)"

echo
echo "=== 4. Start trusted connection to the Connect REST API ==="
oc -n "$NS" port-forward "service/${CONNECT_SERVICE}" \
  "${CONNECT_LOCAL_PORT}:${CONNECT_REMOTE_PORT}" >"$WORK_DIR/connect-port-forward.log" 2>&1 &
CONNECT_PF_PID=$!
wait_for_port_forward "$CONNECT_LOCAL_PORT" "$CONNECT_PF_PID" "$WORK_DIR/connect-port-forward.log"
echo "PASS: Connect REST port-forward is available"

echo
echo "=== 5. Call /connector-plugins using the raw Okta token ==="
OKTA_CONNECT_STATUS="$(curl --silent --show-error \
  --output "$WORK_DIR/connect-okta.json" \
  --write-out '%{http_code}' \
  --cacert "$WORK_DIR/connect-ca.crt" \
  --resolve "${CONNECT_HOST}:${CONNECT_LOCAL_PORT}:127.0.0.1" \
  --header "Authorization: Bearer ${OKTA_TOKEN}" \
  "https://${CONNECT_HOST}:${CONNECT_LOCAL_PORT}/connector-plugins")"
print_response_summary "Raw Okta token" "$OKTA_CONNECT_STATUS" "$WORK_DIR/connect-okta.json"

echo
echo "=== 6. Call /connector-plugins using the MDS-issued token ==="
MDS_CONNECT_STATUS="$(curl --silent --show-error \
  --output "$WORK_DIR/connect-mds.json" \
  --write-out '%{http_code}' \
  --cacert "$WORK_DIR/connect-ca.crt" \
  --resolve "${CONNECT_HOST}:${CONNECT_LOCAL_PORT}:127.0.0.1" \
  --header "Authorization: Bearer ${MDS_TOKEN}" \
  "https://${CONNECT_HOST}:${CONNECT_LOCAL_PORT}/connector-plugins")"
print_response_summary "MDS-issued token" "$MDS_CONNECT_STATUS" "$WORK_DIR/connect-mds.json"

echo
echo "=== 7. Diagnosis ==="
if [ "$OKTA_CONNECT_STATUS" = "200" ] && [ "$MDS_CONNECT_STATUS" = "200" ]; then
  echo "RESULT: Both tokens work. Connect and MDS are healthy."
  echo "NEXT: Inspect the CFK operator's rendered/stale REST credentials and reconciliation behavior."
elif [ "$OKTA_CONNECT_STATUS" = "401" ] && [ "$MDS_CONNECT_STATUS" = "200" ]; then
  echo "RESULT: Connect rejects the raw Okta token but accepts the MDS-issued token."
  echo "NEXT: Correct the CFK operator-to-Connect REST authentication flow/configuration."
elif [ "$OKTA_CONNECT_STATUS" = "403" ] || [ "$MDS_CONNECT_STATUS" = "403" ]; then
  echo "RESULT: At least one token authenticated but lacks authorization for the Connect REST operation."
  echo "NEXT: Verify the SystemAdmin/SecurityAdmin binding scope for connect-cluster=${NS}.connect."
elif [ "$OKTA_CONNECT_STATUS" = "401" ] && [ "$MDS_CONNECT_STATUS" = "401" ]; then
  echo "RESULT: Connect rejects both valid token types."
  echo "NEXT: Inspect the rendered Connect REST OAuth/JWT server configuration."
else
  echo "RESULT: Unexpected status combination: Okta=${OKTA_CONNECT_STATUS}, MDS=${MDS_CONNECT_STATUS}."
  echo "NEXT: Use the response summaries above to identify TLS, routing, authentication, or server errors."
fi

echo
echo "Diagnostic complete. No token or client secret was printed."
