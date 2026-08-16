#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# Non-destructive Control Center OAuth/MDS identity and two-account audit
#
# Requirements:
#   - oc, curl, base64
#   - Python 3.6 or newer (stdlib only; jq is not required)
#
# This script validates:
#   A. Kubernetes Secrets (oauth-controlcenter, oauth-mds-sso)
#   B. Live Kafka MDS SSO configuration
#   C. Live Control Center OAuth dependencies
#   D. ConfluentRolebinding reconciliation
#   E. Machine-token validity (fresh client_credentials token)
#   F. Current runtime logs for authentication failures
#
# This script does NOT restart, patch, apply, or delete any resource.
###############################################################################

NAMESPACE="${1:-dah-flink-dev}"
C3_POD="${C3_POD:-controlcenter-0}"
C3_SECRET="${C3_SECRET:-oauth-controlcenter}"
SSO_SECRET="${SSO_SECRET:-oauth-mds-sso}"
C3_ROLEBINDING="${C3_ROLEBINDING:-controlcenter-systemadmin}"
EXPECTED_C3_ID="${EXPECTED_C3_ID:-0oa1ov6h5mwmQTCKI358}"
EXPECTED_SSO_ID="${EXPECTED_SSO_ID:-0oa1o0ea1m26pITBQ358}"
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
echo "DEV Two-Account Control Center OAuth/MDS Identity Audit"
echo "============================================================"
echo "Namespace:           ${NAMESPACE}"
echo "Control Center pod:  ${C3_POD}"
echo "Machine OAuth:       ${C3_SECRET} (expected ID: ${EXPECTED_C3_ID})"
echo "SSO OAuth:           ${SSO_SECRET} (expected ID: ${EXPECTED_SSO_ID})"
echo "Role binding:        ${C3_ROLEBINDING}"
echo ""

command -v oc >/dev/null 2>&1 || fatal "oc is not available in PATH."
command -v curl >/dev/null 2>&1 || fatal "curl is not available in PATH."
command -v base64 >/dev/null 2>&1 || fatal "base64 is not available in PATH."
PYTHON_BIN="$(find_python)" || fatal "Python 3.6 or newer is required."

oc whoami >/dev/null 2>&1 || fatal "The agent is not logged into OpenShift."
oc get namespace "${NAMESPACE}" >/dev/null 2>&1 || \
  fatal "Namespace ${NAMESPACE} is missing or inaccessible."

OVERALL_PASS=1

# ============================================================
# A. Kubernetes Secrets Validation
# ============================================================
echo "=== A. Kubernetes Secrets Validation ==="
echo ""

# oauth-controlcenter (machine identity)
if ! oc -n "${NAMESPACE}" get secret "${C3_SECRET}" >/dev/null 2>&1; then
  echo "FAIL: Secret/${C3_SECRET} does not exist"
  OVERALL_PASS=0
else
  echo "PASS: Secret/${C3_SECRET} exists"

  C3_ID="$(decode_secret_key "${C3_SECRET}" clientId client-id client_id 2>/dev/null || true)"
  if [[ -z "${C3_ID}" ]]; then
    echo "FAIL: Secret/${C3_SECRET} has no client-ID key"
    OVERALL_PASS=0
  elif [[ "${C3_ID}" != "${EXPECTED_C3_ID}" ]]; then
    echo "FAIL: Secret/${C3_SECRET} clientId=${C3_ID}, expected ${EXPECTED_C3_ID}"
    OVERALL_PASS=0
  else
    echo "PASS: Secret/${C3_SECRET} clientId is correct (${EXPECTED_C3_ID})"
  fi

  if oc -n "${NAMESPACE}" get secret "${C3_SECRET}" -o jsonpath='{.data.clientSecret}' 2>/dev/null | grep -q .; then
    echo "PASS: Secret/${C3_SECRET} has clientSecret (value suppressed)"
  else
    echo "FAIL: Secret/${C3_SECRET} missing clientSecret"
    OVERALL_PASS=0
  fi
fi

echo ""

# oauth-mds-sso (interactive SSO identity)
if ! oc -n "${NAMESPACE}" get secret "${SSO_SECRET}" >/dev/null 2>&1; then
  echo "FAIL: Secret/${SSO_SECRET} does not exist"
  OVERALL_PASS=0
else
  echo "PASS: Secret/${SSO_SECRET} exists"

  SSO_ID="$(decode_secret_key "${SSO_SECRET}" clientId client-id client_id 2>/dev/null || true)"
  if [[ -z "${SSO_ID}" ]]; then
    echo "FAIL: Secret/${SSO_SECRET} has no client-ID key"
    OVERALL_PASS=0
  elif [[ "${SSO_ID}" != "${EXPECTED_SSO_ID}" ]]; then
    echo "FAIL: Secret/${SSO_SECRET} clientId=${SSO_ID}, expected ${EXPECTED_SSO_ID}"
    OVERALL_PASS=0
  else
    echo "PASS: Secret/${SSO_SECRET} clientId is correct (${EXPECTED_SSO_ID})"
  fi

  if oc -n "${NAMESPACE}" get secret "${SSO_SECRET}" -o jsonpath='{.data.clientSecret}' 2>/dev/null | grep -q .; then
    echo "PASS: Secret/${SSO_SECRET} has clientSecret (value suppressed)"
  else
    echo "FAIL: Secret/${SSO_SECRET} missing clientSecret"
    OVERALL_PASS=0
  fi

  if oc -n "${NAMESPACE}" get secret "${SSO_SECRET}" -o jsonpath='{.data.oidcClientSecret\.txt}' 2>/dev/null | grep -q .; then
    echo "PASS: Secret/${SSO_SECRET} has oidcClientSecret.txt (value suppressed)"
  else
    echo "FAIL: Secret/${SSO_SECRET} missing oidcClientSecret.txt"
    OVERALL_PASS=0
  fi
fi

echo ""

# Identity separation check
if [[ -n "${C3_ID:-}" && -n "${SSO_ID:-}" ]]; then
  if [[ "${C3_ID}" != "${SSO_ID}" ]]; then
    echo "PASS: Two client IDs are different (identity separation confirmed)"
  else
    echo "FAIL: Both secrets have the same client ID (separation violated)"
    OVERALL_PASS=0
  fi
fi

# ============================================================
# B. Live Kafka MDS SSO Configuration Validation
# ============================================================
echo ""
echo "=== B. Live Kafka MDS SSO Configuration Validation ==="
echo ""

if ! oc -n "${NAMESPACE}" get kafka kafka >/dev/null 2>&1; then
  echo "FAIL: Kafka/kafka does not exist"
  OVERALL_PASS=0
else
  echo "PASS: Kafka/kafka exists"

  SSO_SECRET_REF="$(oc -n "${NAMESPACE}" get kafka kafka -o jsonpath='{.spec.services.mds.provider.sso.clientCredentials.secretRef}' 2>/dev/null || true)"
  if [[ "${SSO_SECRET_REF}" == "oauth-mds-sso" ]]; then
    echo "PASS: Kafka MDS SSO uses oauth-mds-sso"
  else
    echo "FAIL: Kafka MDS SSO uses ${SSO_SECRET_REF:-<missing>}, expected oauth-mds-sso"
    OVERALL_PASS=0
  fi

  GROUPS_CLAIM="$(oc -n "${NAMESPACE}" get kafka kafka -o jsonpath='{.spec.services.mds.provider.sso.configurations.groupsClaimName}' 2>/dev/null || true)"
  if [[ "${GROUPS_CLAIM}" == "dahDev_groups" ]]; then
    echo "PASS: Kafka MDS SSO groupsClaimName = dahDev_groups"
  else
    echo "FAIL: Kafka MDS SSO groupsClaimName = ${GROUPS_CLAIM:-<missing>}, expected dahDev_groups"
    OVERALL_PASS=0
  fi

  SUB_CLAIM="$(oc -n "${NAMESPACE}" get kafka kafka -o jsonpath='{.spec.services.mds.provider.sso.configurations.subClaimName}' 2>/dev/null || true)"
  if [[ "${SUB_CLAIM}" == "sub" ]]; then
    echo "PASS: Kafka MDS SSO subClaimName = sub"
  else
    echo "FAIL: Kafka MDS SSO subClaimName = ${SUB_CLAIM:-<missing>}, expected sub"
    OVERALL_PASS=0
  fi

  GROUPS_SCOPE="$(oc -n "${NAMESPACE}" get kafka kafka -o jsonpath='{.spec.services.mds.provider.sso.configurations.groupsClaimScope}' 2>/dev/null || true)"
  if [[ "${GROUPS_SCOPE}" == "11547.DAH(Dev)" ]]; then
    echo "PASS: Kafka MDS SSO groupsClaimScope = 11547.DAH(Dev)"
  else
    echo "FAIL: Kafka MDS SSO groupsClaimScope = ${GROUPS_SCOPE:-<missing>}, expected 11547.DAH(Dev)"
    OVERALL_PASS=0
  fi

  REFRESH_TOKEN="$(oc -n "${NAMESPACE}" get kafka kafka -o jsonpath='{.spec.services.mds.provider.sso.configurations.refreshToken}' 2>/dev/null || true)"
  if [[ "${REFRESH_TOKEN}" == "true" ]]; then
    echo "PASS: Kafka MDS SSO refreshToken = true"
  else
    echo "FAIL: Kafka MDS SSO refreshToken = ${REFRESH_TOKEN:-<missing>}, expected true"
    OVERALL_PASS=0
  fi
fi

# ============================================================
# C. Live Control Center OAuth Dependencies Validation
# ============================================================
echo ""
echo "=== C. Live Control Center OAuth Dependencies Validation ==="
echo ""

if ! oc -n "${NAMESPACE}" get controlcenter controlcenter >/dev/null 2>&1; then
  echo "FAIL: ControlCenter/controlcenter does not exist"
  OVERALL_PASS=0
else
  echo "PASS: ControlCenter/controlcenter exists"

  # Kafka dependency
  KAFKA_AUTH="$(oc -n "${NAMESPACE}" get controlcenter controlcenter -o jsonpath='{.spec.dependencies.kafka.authentication.jaasConfig.secretRef}' 2>/dev/null || true)"
  if [[ "${KAFKA_AUTH}" == "oauth-controlcenter" ]]; then
    echo "PASS: Control Center Kafka dependency uses oauth-controlcenter"
  else
    echo "FAIL: Control Center Kafka dependency uses ${KAFKA_AUTH:-<missing>}, expected oauth-controlcenter"
    OVERALL_PASS=0
  fi

  # MDS dependency
  MDS_AUTH="$(oc -n "${NAMESPACE}" get controlcenter controlcenter -o jsonpath='{.spec.dependencies.mds.authentication.oauth.secretRef}' 2>/dev/null || true)"
  if [[ "${MDS_AUTH}" == "oauth-controlcenter" ]]; then
    echo "PASS: Control Center MDS dependency uses oauth-controlcenter"
  else
    echo "FAIL: Control Center MDS dependency uses ${MDS_AUTH:-<missing>}, expected oauth-controlcenter"
    OVERALL_PASS=0
  fi

  # Schema Registry dependency
  SR_AUTH="$(oc -n "${NAMESPACE}" get controlcenter controlcenter -o jsonpath='{.spec.dependencies.schemaRegistry.authentication.oauth.secretRef}' 2>/dev/null || true)"
  if [[ "${SR_AUTH}" == "oauth-controlcenter" ]]; then
    echo "PASS: Control Center Schema Registry dependency uses oauth-controlcenter"
  else
    echo "FAIL: Control Center Schema Registry dependency uses ${SR_AUTH:-<missing>}, expected oauth-controlcenter"
    OVERALL_PASS=0
  fi

  # Connect dependencies
  CONNECT_COUNT="$(oc -n "${NAMESPACE}" get controlcenter controlcenter -o go-template='{{len .spec.dependencies.connect}}' 2>/dev/null || echo 0)"
  if [[ "${CONNECT_COUNT}" -gt 0 ]]; then
    for ((i=0; i<CONNECT_COUNT; i++)); do
      CONNECT_NAME="$(oc -n "${NAMESPACE}" get controlcenter controlcenter -o jsonpath="{.spec.dependencies.connect[$i].name}" 2>/dev/null || true)"
      CONNECT_AUTH="$(oc -n "${NAMESPACE}" get controlcenter controlcenter -o jsonpath="{.spec.dependencies.connect[$i].authentication.oauth.secretRef}" 2>/dev/null || true)"
      if [[ "${CONNECT_AUTH}" == "oauth-controlcenter" ]]; then
        echo "PASS: Control Center Connect[${CONNECT_NAME}] uses oauth-controlcenter"
      else
        echo "FAIL: Control Center Connect[${CONNECT_NAME}] uses ${CONNECT_AUTH:-<missing>}, expected oauth-controlcenter"
        OVERALL_PASS=0
      fi
    done
  fi

  # MDS SSO Protocol
  SSO_PROTOCOL="$(oc -n "${NAMESPACE}" get controlcenter controlcenter -o jsonpath='{.spec.dependencies.mds.ssoProtocol}' 2>/dev/null || true)"
  if [[ "${SSO_PROTOCOL}" == "oidc" ]]; then
    echo "PASS: Control Center MDS ssoProtocol = oidc"
  else
    echo "FAIL: Control Center MDS ssoProtocol = ${SSO_PROTOCOL:-<missing>}, expected oidc"
    OVERALL_PASS=0
  fi

  # Check for prohibited basic-auth on C3 UI/MDS login
  BASIC_AUTH="$(oc -n "${NAMESPACE}" get controlcenter controlcenter -o jsonpath='{.spec.dependencies.mds.authentication.basic}' 2>/dev/null || true)"
  if [[ -z "${BASIC_AUTH}" ]]; then
    echo "PASS: No basic-auth configured on Control Center MDS"
  else
    echo "FAIL: Control Center MDS has basic-auth configured (not allowed)"
    OVERALL_PASS=0
  fi
fi

# ============================================================
# D. ConfluentRolebinding Reconciliation Validation
# ============================================================
echo ""
echo "=== D. ConfluentRolebinding Reconciliation Validation ==="
echo ""

if ! oc -n "${NAMESPACE}" get confluentrolebinding "${C3_ROLEBINDING}" >/dev/null 2>&1; then
  echo "FAIL: ConfluentRolebinding/${C3_ROLEBINDING} does not exist"
  OVERALL_PASS=0
else
  echo "PASS: ConfluentRolebinding/${C3_ROLEBINDING} exists"

  # Spec principal
  SPEC_PRINCIPAL="$(oc -n "${NAMESPACE}" get confluentrolebinding "${C3_ROLEBINDING}" -o jsonpath='{.spec.principal.name}' 2>/dev/null || true)"
  if [[ "${SPEC_PRINCIPAL}" == "${EXPECTED_C3_ID}" ]]; then
    echo "PASS: ${C3_ROLEBINDING} spec.principal.name = ${EXPECTED_C3_ID}"
  else
    echo "FAIL: ${C3_ROLEBINDING} spec.principal.name = ${SPEC_PRINCIPAL:-<missing>}, expected ${EXPECTED_C3_ID}"
    OVERALL_PASS=0
  fi

  # Status principal
  STATUS_PRINCIPAL="$(oc -n "${NAMESPACE}" get confluentrolebinding "${C3_ROLEBINDING}" -o jsonpath='{.status.principal}' 2>/dev/null || true)"
  if [[ "${STATUS_PRINCIPAL}" == "User:${EXPECTED_C3_ID}" ]]; then
    echo "PASS: ${C3_ROLEBINDING} status.principal = User:${EXPECTED_C3_ID}"
  else
    echo "FAIL: ${C3_ROLEBINDING} status.principal = ${STATUS_PRINCIPAL:-<missing>}, expected User:${EXPECTED_C3_ID}"
    OVERALL_PASS=0
  fi

  # Role
  RB_ROLE="$(oc -n "${NAMESPACE}" get confluentrolebinding "${C3_ROLEBINDING}" -o jsonpath='{.status.role}' 2>/dev/null || true)"
  if [[ "${RB_ROLE}" == "SystemAdmin" ]]; then
    echo "PASS: ${C3_ROLEBINDING} role = SystemAdmin"
  else
    echo "FAIL: ${C3_ROLEBINDING} role = ${RB_ROLE:-<missing>}, expected SystemAdmin"
    OVERALL_PASS=0
  fi

  # Readiness condition
  RB_READY="$(oc -n "${NAMESPACE}" get confluentrolebinding "${C3_ROLEBINDING}" -o jsonpath='{range .status.conditions[?(@.type=="platform.confluent.io/app-ready")]}{.status}{end}' 2>/dev/null || true)"
  if [[ "${RB_READY}" == "True" ]]; then
    echo "PASS: ${C3_ROLEBINDING} app-ready condition = True"
  else
    echo "FAIL: ${C3_ROLEBINDING} app-ready condition = ${RB_READY:-<missing>}, expected True"
    OVERALL_PASS=0
  fi
fi

# ============================================================
# E. Machine-Token Validity and Claims Validation
# ============================================================
echo ""
echo "=== E. Machine-Token Validity and Claims Validation ==="
echo ""

if [[ -z "${C3_ID:-}" ]]; then
  echo "FAIL: Machine client ID not available from Secret/${C3_SECRET}"
  OVERALL_PASS=0
else
  C3_SECRET_DATA="$(decode_secret_key "${C3_SECRET}" clientSecret client-secret client_secret password 2>/dev/null || true)"

  if [[ -z "${C3_SECRET_DATA}" ]]; then
    echo "FAIL: Cannot decode client secret from Secret/${C3_SECRET}"
    OVERALL_PASS=0
  else
    HTTP_CODE="$(curl --silent --show-error \
      --connect-timeout 15 --max-time 45 \
      --output "${TOKEN_RESPONSE}" --write-out '%{http_code}' \
      --user "${C3_ID}:${C3_SECRET_DATA}" \
      --header 'Accept: application/json' \
      --data-urlencode 'grant_type=client_credentials' \
      --data-urlencode "scope=${OAUTH_SCOPE}" \
      "${TOKEN_ENDPOINT}" 2>/dev/null || echo "000")"

    unset C3_SECRET_DATA

    if [[ "${HTTP_CODE}" == "200" ]]; then
      echo "PASS: Okta issued access token for machine identity (HTTP ${HTTP_CODE})"

      ${PYTHON_BIN} - "${TOKEN_RESPONSE}" "${TOKEN_FILE}" <<'PY'
import json
import os
import sys
try:
    with open(sys.argv[1], "r") as handle:
        data = json.load(handle)
    token = data.get("access_token", "")
    if not token:
        raise SystemExit("access_token missing from response")
    with open(sys.argv[2], "w") as handle:
        handle.write(token)
    os.chmod(sys.argv[2], 0o600)
except Exception as e:
    raise SystemExit(str(e))
PY

      ${PYTHON_BIN} - "${TOKEN_FILE}" "${CLAIMS_FILE}" "${EXPECTED_C3_ID}" "${EXPECTED_ISSUER}" "${OAUTH_SCOPE}" <<'PY'
from __future__ import print_function
import base64
import json
import sys
import time

token_path = sys.argv[1]
output_path = sys.argv[2]
expected_id = sys.argv[3]
expected_issuer = sys.argv[4]
expected_scope = sys.argv[5]

with open(token_path, "r") as handle:
    token = handle.read().strip()

parts = token.split(".")
if len(parts) != 3:
    raise SystemExit("access_token is not a three-part JWT")

payload = parts[1]
payload += "=" * ((4 - len(payload) % 4) % 4)
claims = json.loads(base64.urlsafe_b64decode(payload.encode("ascii")).decode("utf-8"))

selected_names = ("sub", "cid", "client_id", "iss", "aud", "scp", "scope", "dahDev_groups", "exp")
selected = dict((name, claims.get(name)) for name in selected_names if name in claims)
with open(output_path, "w") as handle:
    json.dump(selected, handle, indent=2, sort_keys=True)
    handle.write("\n")

print(json.dumps(selected, indent=2, sort_keys=True))

# Validate critical claims
errors = []
subject = claims.get("sub")
client_id_claim = claims.get("cid", claims.get("client_id"))
issuer = claims.get("iss")
scopes = claims.get("scp", claims.get("scope", []))
exp_time = claims.get("exp")

if isinstance(scopes, str):
    scopes = scopes.split()

if subject != expected_id:
    errors.append("sub={0!r}, expected {1!r}".format(subject, expected_id))
if client_id_claim and client_id_claim != expected_id:
    errors.append("cid/client_id={0!r}, expected {1!r}".format(client_id_claim, expected_id))
if issuer != expected_issuer:
    errors.append("iss={0!r}, expected {1!r}".format(issuer, expected_issuer))
if expected_scope not in scopes:
    errors.append("required scope {0!r} is absent".format(expected_scope))
if not exp_time:
    errors.append("exp claim is missing")
elif exp_time <= int(time.time()):
    errors.append("token has expired (exp={0})".format(exp_time))

if errors:
    print("\nTOKEN CLAIM VALIDATION FAILED:", file=sys.stderr)
    for error in errors:
        print("  - " + error, file=sys.stderr)
    raise SystemExit(2)
else:
    print("\nToken claims validated successfully")
PY

      TOKEN_VALIDATION=$?
      if [[ $TOKEN_VALIDATION -ne 0 ]]; then
        echo "FAIL: JWT claims validation failed"
        OVERALL_PASS=0
      else
        echo "PASS: JWT subject, issuer, client ID, scope and expiration valid"
      fi

      echo ""
      echo "Token claims (selected, secrets redacted):"
      cat "${CLAIMS_FILE}"

      # Report dahDev_groups presence (not root-cause conclusion)
      echo ""
      GROUPS_CLAIM=$(${PYTHON_BIN} -c "import json; claims=json.load(open('${CLAIMS_FILE}')); print(claims.get('dahDev_groups', '<absent>'))" 2>/dev/null || echo "<absent>")
      if [[ "${GROUPS_CLAIM}" == "<absent>" ]]; then
        echo "NOTE: dahDev_groups claim is absent from token (may be expected for machine identity)"
      elif [[ -z "${GROUPS_CLAIM}" ]]; then
        echo "NOTE: dahDev_groups claim is empty in token"
      else
        echo "NOTE: dahDev_groups claim is present in token"
      fi

    else
      echo "FAIL: Okta returned HTTP ${HTTP_CODE}"
      if [[ -f "${TOKEN_RESPONSE}" ]]; then
        ${PYTHON_BIN} - "${TOKEN_RESPONSE}" <<'PY'
import json
import sys
try:
    with open(sys.argv[1], "r") as handle:
        data = json.load(handle)
    print("Error: {0}; Description: {1}".format(
        data.get("error", "unknown"), data.get("error_description", "not supplied")))
except Exception:
    print("Response was not valid JSON")
PY
      fi
      OVERALL_PASS=0
    fi
  fi
fi

# ============================================================
# F. Current Runtime Evidence and Logs
# ============================================================
echo ""
echo "=== F. Current Runtime Evidence and Logs ==="
echo ""

if ! oc -n "${NAMESPACE}" get pod "${C3_POD}" >/dev/null 2>&1; then
  echo "FAIL: Control Center pod ${C3_POD} does not exist"
  OVERALL_PASS=0
else
  C3_POD_IP="$(oc -n "${NAMESPACE}" get pod "${C3_POD}" -o jsonpath='{.status.podIP}' 2>/dev/null || true)"
  echo "Control Center pod IP: ${C3_POD_IP:-<missing>}"

  oc -n "${NAMESPACE}" logs "${C3_POD}" --all-containers=true --since="${LOG_SINCE}" --timestamps \
    >"${OUTPUT_DIR}/controlcenter.log" 2>&1 || true

  if grep -Eiq 'Invalid Token|User Identity not found|Failed to authenticate' \
    "${OUTPUT_DIR}/controlcenter.log"; then
    echo "FAIL: Control Center logs contain authentication errors"
    OVERALL_PASS=0
  else
    echo "PASS: No authentication errors in Control Center logs (last ${LOG_SINCE})"
  fi

  # Broker-side correlation: Check if brokers rejected the current C3 pod IP within the time window
  echo ""
  echo "Broker-side MDS authentication correlation (last ${LOG_SINCE}):"

  if [[ -n "${C3_POD_IP}" ]]; then
    failures=0

    # kafka-0
    if oc -n "${NAMESPACE}" logs kafka-0 --all-containers=true \
        --since="${LOG_SINCE}" 2>/dev/null | \
       grep -F "${C3_POD_IP}" | \
       grep -Eq 'GET /security/1\.0/authenticate HTTP/[0-9.]+" 401'; then
      echo "  FAIL: kafka-0 returned a recent 401 to Control Center IP ${C3_POD_IP}"
      failures=$((failures + 1))
      OVERALL_PASS=0
    else
      echo "  PASS: kafka-0 — no recent MDS 401"
    fi

    # kafka-1
    if oc -n "${NAMESPACE}" logs kafka-1 --all-containers=true \
        --since="${LOG_SINCE}" 2>/dev/null | \
       grep -F "${C3_POD_IP}" | \
       grep -Eq 'GET /security/1\.0/authenticate HTTP/[0-9.]+" 401'; then
      echo "  FAIL: kafka-1 returned a recent 401 to Control Center IP ${C3_POD_IP}"
      failures=$((failures + 1))
      OVERALL_PASS=0
    else
      echo "  PASS: kafka-1 — no recent MDS 401"
    fi

    # kafka-2
    if oc -n "${NAMESPACE}" logs kafka-2 --all-containers=true \
        --since="${LOG_SINCE}" 2>/dev/null | \
       grep -F "${C3_POD_IP}" | \
       grep -Eq 'GET /security/1\.0/authenticate HTTP/[0-9.]+" 401'; then
      echo "  FAIL: kafka-2 returned a recent 401 to Control Center IP ${C3_POD_IP}"
      failures=$((failures + 1))
      OVERALL_PASS=0
    else
      echo "  PASS: kafka-2 — no recent MDS 401"
    fi

    if [[ $failures -eq 0 ]]; then
      echo "  ✓ All brokers: No recent MDS 401 responses to Control Center IP"
    fi
  else
    echo "  FAIL: Control Center pod IP could not be determined"
    OVERALL_PASS=0
  fi
fi

echo ""
echo "=== Summary ==="
if [[ "${OVERALL_PASS}" -eq 0 ]]; then
  echo "RESULT: FAIL — one or more validation(s) failed"
  echo "Evidence directory: ${OUTPUT_DIR}"
  exit 1
else
  echo "RESULT: PASS — DEV two-account identity model correctly configured"
  echo "Evidence directory: ${OUTPUT_DIR}"
  exit 0
fi
