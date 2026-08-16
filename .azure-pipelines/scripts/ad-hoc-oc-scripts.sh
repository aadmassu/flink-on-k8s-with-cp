#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# Non-destructive Control Center OAuth/MDS identity audit
#
# Requirements:
#   - oc, curl, base64
#   - Python 3.6 or newer (stdlib only; jq is not required)
#
# This script does NOT restart, patch, apply, or delete any resource.
###############################################################################

NAMESPACE="${1:-dah-flink-dev}"
C3_POD="${C3_POD:-controlcenter-0}"
C3_SECRET="${C3_SECRET:-oauth-controlcenter}"
C3_ROLEBINDING="${C3_ROLEBINDING:-controlcenter-systemadmin}"
EXPECTED_CLIENT_ID="${EXPECTED_CLIENT_ID:-0oa1ov6h5mwmQTCKI358}"
TOKEN_ENDPOINT="${TOKEN_ENDPOINT:-https://myapps.firstcitizens.com/oauth2/default/v1/token}"
OAUTH_SCOPE="${OAUTH_SCOPE:-11547.DAH(Dev)}"
EXPECTED_ISSUER="${EXPECTED_ISSUER:-https://myapps.firstcitizens.com/oauth2/default}"
LOG_SINCE="${LOG_SINCE:-15m}"
OUTPUT_DIR="${AGENT_TEMPDIRECTORY:-/tmp}/cfk-c3-oauth-audit"

mkdir -p "${OUTPUT_DIR}"
chmod 700 "${OUTPUT_DIR}"

TOKEN_RESPONSE="${OUTPUT_DIR}/token-response.json"
TOKEN_FILE="${OUTPUT_DIR}/access-token.txt"
CLAIMS_FILE="${OUTPUT_DIR}/jwt-claims-selected.json"
trap 'rm -f "${TOKEN_RESPONSE}" "${TOKEN_FILE}"' EXIT

fatal() {
  echo >&2
  echo "FATAL: $*" >&2
  exit 1
}

find_python() {
  local candidate
  for candidate in python3 python; do
    if command -v "${candidate}" >/dev/null 2>&1 && \
       "${candidate}" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 6) else 1)' 2>/dev/null; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done
  return 1
}

decode_secret_key() {
  local secret_name="$1"
  shift
  local key encoded

  for key in "$@"; do
    encoded="$(oc -n "${NAMESPACE}" get secret "${secret_name}" \
      -o "jsonpath={.data['${key}']}" 2>/dev/null || true)"
    if [[ -n "${encoded}" ]]; then
      printf '%s' "${encoded}" | base64 --decode
      return 0
    fi
  done
  return 1
}

echo "============================================================"
echo "Control Center OAuth/MDS identity audit"
echo "Namespace:          ${NAMESPACE}"
echo "Control Center pod: ${C3_POD}"
echo "OAuth Secret:       ${C3_SECRET}"
echo "Role binding:       ${C3_ROLEBINDING}"
echo "Expected client ID: ${EXPECTED_CLIENT_ID}"
echo "============================================================"

command -v oc >/dev/null 2>&1 || fatal "oc is not available in PATH."
command -v curl >/dev/null 2>&1 || fatal "curl is not available in PATH."
command -v base64 >/dev/null 2>&1 || fatal "base64 is not available in PATH."
PYTHON_BIN="$(find_python)" || fatal "Python 3.6 or newer is required."

oc whoami >/dev/null 2>&1 || fatal "The agent is not logged into OpenShift."
oc get namespace "${NAMESPACE}" >/dev/null 2>&1 || \
  fatal "Namespace ${NAMESPACE} is missing or inaccessible."

echo
echo "=== 1. Resource and Secret checks ==="

oc -n "${NAMESPACE}" get pod "${C3_POD}" >/dev/null 2>&1 || \
  fatal "Pod/${C3_POD} does not exist."
oc -n "${NAMESPACE}" get secret "${C3_SECRET}" >/dev/null 2>&1 || \
  fatal "Secret/${C3_SECRET} does not exist."
oc -n "${NAMESPACE}" get confluentrolebinding "${C3_ROLEBINDING}" >/dev/null 2>&1 || \
  fatal "ConfluentRolebinding/${C3_ROLEBINDING} does not exist."

echo "Secret keys (values suppressed):"
oc -n "${NAMESPACE}" get secret "${C3_SECRET}" \
  -o go-template='{{range $key, $value := .data}}{{printf "  %s\n" $key}}{{end}}'

CLIENT_ID="$(decode_secret_key "${C3_SECRET}" clientId client-id client_id username)" || \
  fatal "Secret/${C3_SECRET} has no supported client-ID key."
CLIENT_SECRET="$(decode_secret_key "${C3_SECRET}" clientSecret client-secret client_secret password)" || \
  fatal "Secret/${C3_SECRET} has no supported client-secret key."

[[ -n "${CLIENT_ID//[[:space:]]/}" ]] || fatal "Decoded client ID is empty."
[[ -n "${CLIENT_SECRET//[[:space:]]/}" ]] || fatal "Decoded client secret is empty."

echo "Secret clientId: ${CLIENT_ID}"
if [[ "${CLIENT_ID}" != "${EXPECTED_CLIENT_ID}" ]]; then
  fatal "Secret clientId differs from EXPECTED_CLIENT_ID=${EXPECTED_CLIENT_ID}."
fi
echo "PASS: Secret contains the expected Control Center client ID."

echo
echo "=== 2. ConfluentRolebinding check ==="

RB_PRINCIPAL="$(oc -n "${NAMESPACE}" get confluentrolebinding "${C3_ROLEBINDING}" -o jsonpath='{.status.principal}')"
RB_ROLE="$(oc -n "${NAMESPACE}" get confluentrolebinding "${C3_ROLEBINDING}" -o jsonpath='{.status.role}')"
RB_STATE="$(oc -n "${NAMESPACE}" get confluentrolebinding "${C3_ROLEBINDING}" -o jsonpath='{.status.state}')"
RB_READY="$(oc -n "${NAMESPACE}" get confluentrolebinding "${C3_ROLEBINDING}" -o jsonpath='{range .status.conditions[?(@.type=="platform.confluent.io/app-ready")]}{.status}{end}')"

echo "Principal: ${RB_PRINCIPAL:-<missing>}"
echo "Role:      ${RB_ROLE:-<missing>}"
echo "State:     ${RB_STATE:-<missing>}"
echo "Ready:     ${RB_READY:-<missing>}"

[[ "${RB_PRINCIPAL}" == "User:${EXPECTED_CLIENT_ID}" ]] || \
  fatal "Role-binding principal must be User:${EXPECTED_CLIENT_ID}."
[[ "${RB_ROLE}" == "SystemAdmin" ]] || fatal "Role binding is not SystemAdmin."
[[ "${RB_STATE^^}" == "CREATED" ]] || fatal "Role binding state is not CREATED."
[[ "${RB_READY}" == "True" ]] || fatal "Role binding is not app-ready=True."
echo "PASS: Control Center SystemAdmin role binding is reconciled."

echo
echo "=== 3. Obtain a fresh Okta client-credentials token ==="

HTTP_CODE="$(curl --silent --show-error \
  --connect-timeout 15 --max-time 45 \
  --output "${TOKEN_RESPONSE}" --write-out '%{http_code}' \
  --user "${CLIENT_ID}:${CLIENT_SECRET}" \
  --header 'Accept: application/json' \
  --data-urlencode 'grant_type=client_credentials' \
  --data-urlencode "scope=${OAUTH_SCOPE}" \
  "${TOKEN_ENDPOINT}")" || fatal "Unable to reach the Okta token endpoint."

unset CLIENT_SECRET
chmod 600 "${TOKEN_RESPONSE}"

if [[ "${HTTP_CODE}" != "200" ]]; then
  ERROR_SUMMARY="$(${PYTHON_BIN} - "${TOKEN_RESPONSE}" <<'PY'
import json
import sys
try:
    with open(sys.argv[1], "r") as handle:
        data = json.load(handle)
    print("error={0}; description={1}".format(
        data.get("error", "unknown"), data.get("error_description", "not supplied")))
except Exception:
    print("response was not valid JSON")
PY
)"
  fatal "Okta returned HTTP ${HTTP_CODE}: ${ERROR_SUMMARY}"
fi

${PYTHON_BIN} - "${TOKEN_RESPONSE}" "${TOKEN_FILE}" <<'PY'
import json
import os
import sys
with open(sys.argv[1], "r") as handle:
    data = json.load(handle)
token = data.get("access_token", "")
if not token:
    raise SystemExit("access_token is missing from the Okta response")
with open(sys.argv[2], "w") as handle:
    handle.write(token)
os.chmod(sys.argv[2], 0o600)
PY

echo "PASS: Okta issued an access token (token value suppressed)."

echo
echo "=== 4. Decode and validate selected JWT claims ==="

${PYTHON_BIN} - "${TOKEN_FILE}" "${CLAIMS_FILE}" \
  "${EXPECTED_CLIENT_ID}" "${EXPECTED_ISSUER}" "${OAUTH_SCOPE}" <<'PY'
from __future__ import print_function
import base64
import json
import sys

token_path, output_path, expected_id, expected_issuer, expected_scope = sys.argv[1:]
with open(token_path, "r") as handle:
    token = handle.read().strip()

parts = token.split(".")
if len(parts) != 3:
    raise SystemExit("FATAL: access token is not a three-part JWT")

payload = parts[1]
payload += "=" * ((4 - len(payload) % 4) % 4)
claims = json.loads(base64.urlsafe_b64decode(payload.encode("ascii")).decode("utf-8"))

selected_names = (
    "sub", "cid", "client_id", "iss", "aud", "scp", "scope", "dahDev_groups"
)
selected = dict((name, claims.get(name)) for name in selected_names if name in claims)
with open(output_path, "w") as handle:
    json.dump(selected, handle, indent=2, sort_keys=True)
    handle.write("\n")

print(json.dumps(selected, indent=2, sort_keys=True))

subject = claims.get("sub")
client_claim = claims.get("cid", claims.get("client_id"))
issuer = claims.get("iss")
scopes = claims.get("scp", claims.get("scope", []))
if isinstance(scopes, str):
    scopes = scopes.split()

errors = []
if subject != expected_id:
    errors.append("sub={0!r}, expected {1!r}".format(subject, expected_id))
if client_claim is not None and client_claim != expected_id:
    errors.append("cid/client_id={0!r}, expected {1!r}".format(client_claim, expected_id))
if issuer != expected_issuer:
    errors.append("iss={0!r}, expected {1!r}".format(issuer, expected_issuer))
if expected_scope not in scopes:
    errors.append("required scope {0!r} is absent".format(expected_scope))

if errors:
    print("\nTOKEN CLAIM VALIDATION FAILED:", file=sys.stderr)
    for error in errors:
        print("  - " + error, file=sys.stderr)
    raise SystemExit(2)
PY

echo "PASS: JWT subject, issuer, client identity and scope match the DEV contract."

echo
echo "=== 5. Compare the running Control Center configuration ==="

oc -n "${NAMESPACE}" exec "${C3_POD}" -- sh -c \
  'grep -hE "^(confluent\.metadata\.(oauthbearer\.login\.)?(client\.id|client\.secret|scope|token\.endpoint\.uri)|confluent\.metadata\.oauthbearer\.login\.(client\.id|scope|token\.endpoint\.uri))=" /mnt/config/* 2>/dev/null | sed -E "s/(client\.secret=).*/\1<redacted>/" | sort -u' \
  >"${OUTPUT_DIR}/controlcenter-oauth-config.txt" 2>/dev/null || true

if [[ -s "${OUTPUT_DIR}/controlcenter-oauth-config.txt" ]]; then
  cat "${OUTPUT_DIR}/controlcenter-oauth-config.txt"
else
  echo "WARNING: Could not locate generated OAuth properties in ${C3_POD}."
fi

echo
echo "=== 6. Correlate current Control Center and broker logs ==="

C3_IP="$(oc -n "${NAMESPACE}" get pod "${C3_POD}" -o jsonpath='{.status.podIP}')"
echo "Current Control Center pod IP: ${C3_IP:-<missing>}"

oc -n "${NAMESPACE}" logs "${C3_POD}" --all-containers=true \
  --since="${LOG_SINCE}" --timestamps \
  >"${OUTPUT_DIR}/controlcenter.log" 2>&1 || true

grep -Ei 'Invalid Token|User Identity not found|Failed to authenticate|OAuth login|Principal|8090|License for control-center' \
  "${OUTPUT_DIR}/controlcenter.log" | tail -200 || true

BROKER_FAILURE=0
for pod in kafka-0 kafka-1 kafka-2; do
  log_file="${OUTPUT_DIR}/${pod}.log"
  oc -n "${NAMESPACE}" logs "${pod}" --all-containers=true \
    --since="${LOG_SINCE}" --timestamps >"${log_file}" 2>&1 || true

  if [[ -n "${C3_IP}" ]] && grep -F "${C3_IP}" "${log_file}" | \
    grep -Eq 'GET /security/1.0/authenticate HTTP/[0-9.]+" 401'; then
    echo "${pod}: MDS returned 401 to current Control Center IP ${C3_IP}."
    BROKER_FAILURE=1
  fi
done

C3_FAILURE=0
if grep -Eqi 'Invalid Token : User Identity not found|Failed to authenticate' \
  "${OUTPUT_DIR}/controlcenter.log"; then
  C3_FAILURE=1
fi

echo
echo "=== Final decision ==="
if [[ "${C3_FAILURE}" -eq 1 || "${BROKER_FAILURE}" -eq 1 ]]; then
  echo "NO-GO: The token claims match the manifest identity, but MDS still rejects it."
  echo "This isolates the remaining defect to MDS/Okta identity resolution, not RBAC, TLS,"
  echo "networking, storage, Kafka readiness, or the embedded REST principal."
  echo "Give jwt-claims-selected.json and the redacted OAuth configuration to the Okta/MDS team."
  echo "Evidence directory: ${OUTPUT_DIR}"
  exit 1
fi

echo "GO: No current Control Center OAuth/MDS identity rejection was detected."
echo "Evidence directory: ${OUTPUT_DIR}"
exit 0
