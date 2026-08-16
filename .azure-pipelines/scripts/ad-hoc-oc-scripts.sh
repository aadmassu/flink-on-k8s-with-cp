#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# Configuration
###############################################################################

NAMESPACE="${1:-dah-flink-dev}"
KAFKA_POD="${KAFKA_POD:-kafka-1}"
C3_POD="${C3_POD:-controlcenter-0}"
C3_CR="${C3_CR:-controlcenter}"
ROLEBINDING="${ROLEBINDING:-controlcenter-systemadmin}"
EXPECTED_CLIENT_ID="${EXPECTED_CLIENT_ID:-0oa1ov6h5mwmQTCKI358}"

KAFKA_WAIT_SECONDS="${KAFKA_WAIT_SECONDS:-900}"
C3_WAIT_SECONDS="${C3_WAIT_SECONDS:-600}"
LOG_SINCE="${LOG_SINCE:-15m}"
OUTPUT_DIR="${AGENT_TEMPDIRECTORY:-/tmp}/cfk-c3-mds-diagnostic"

mkdir -p "${OUTPUT_DIR}"

echo "============================================================"
echo "Kafka MDS and Control Center recovery"
echo "Namespace:        ${NAMESPACE}"
echo "Kafka pod:        ${KAFKA_POD}"
echo "Control Center:   ${C3_POD}"
echo "Role binding:     ${ROLEBINDING}"
echo "Expected client:  ${EXPECTED_CLIENT_ID}"
echo "Output directory: ${OUTPUT_DIR}"
echo "============================================================"

###############################################################################
# Utility functions
###############################################################################

fatal()
{
  echo
  echo "FATAL: $*"
  exit 1
}

pod_phase()
{
  oc -n "${NAMESPACE}" get pod "$1" \
    -o jsonpath='{.status.phase}' 2>/dev/null || true
}

pod_ready()
{
  oc -n "${NAMESPACE}" get pod "$1" \
    -o jsonpath='{range .status.conditions[?(@.type=="Ready")]}{.status}{end}' \
    2>/dev/null || true
}

pod_uid()
{
  oc -n "${NAMESPACE}" get pod "$1" \
    -o jsonpath='{.metadata.uid}' 2>/dev/null || true
}

wait_for_replacement()
{
  local pod_name="$1"
  local old_uid="$2"
  local timeout_seconds="$3"
  local elapsed=0
  local current_uid=""

  while (( elapsed < timeout_seconds )); do
    current_uid="$(pod_uid "${pod_name}")"

    if [[ -n "${current_uid}" && "${current_uid}" != "${old_uid}" ]]; then
      echo "Replacement ${pod_name} detected."
      echo "Old UID: ${old_uid}"
      echo "New UID: ${current_uid}"
      return 0
    fi

    sleep 5
    elapsed=$((elapsed + 5))

    if (( elapsed % 60 == 0 )); then
      echo "Waiting for replacement ${pod_name}: ${elapsed}s elapsed"
    fi
  done

  return 1
}

wait_for_ready()
{
  local pod_name="$1"
  local timeout_seconds="$2"

  if ! oc -n "${NAMESPACE}" wait \
    --for=condition=Ready \
    "pod/${pod_name}" \
    --timeout="${timeout_seconds}s"; then

    echo
    echo "${pod_name} did not become Ready."

    oc -n "${NAMESPACE}" get pod "${pod_name}" -o wide || true
    oc -n "${NAMESPACE}" describe pod "${pod_name}" || true

    echo
    echo "----- ${pod_name} logs -----"

    oc -n "${NAMESPACE}" logs "${pod_name}" \
      --all-containers=true \
      --timestamps \
      --tail=500 || true

    return 1
  fi

  return 0
}

collect_matching_logs()
{
  local pod_name="$1"
  local destination="$2"

  oc -n "${NAMESPACE}" logs "${pod_name}" \
    --all-containers=true \
    --timestamps \
    --since="${LOG_SINCE}" >"${destination}" 2>&1 || true
}

###############################################################################
# 1. Validate oc access
###############################################################################

echo
echo "=== 1. Validating OpenShift access ==="

command -v oc >/dev/null 2>&1 ||
  fatal "oc is not installed or not available in PATH."

oc whoami >/dev/null 2>&1 ||
  fatal "The Azure agent is not logged into OpenShift."

oc get namespace "${NAMESPACE}" >/dev/null 2>&1 ||
  fatal "Namespace ${NAMESPACE} does not exist or is inaccessible."

echo "OpenShift user: $(oc whoami)"
echo "PASS: OpenShift access is available."

###############################################################################
# 2. Validate Control Center role binding
###############################################################################

echo
echo "=== 2. Validating Control Center role binding ==="

oc -n "${NAMESPACE}" get confluentrolebinding "${ROLEBINDING}" \
  >/dev/null 2>&1 ||
  fatal "ConfluentRolebinding/${ROLEBINDING} does not exist."

RB_PRINCIPAL="$(
  oc -n "${NAMESPACE}" get confluentrolebinding "${ROLEBINDING}" \
    -o jsonpath='{.status.principal}'
)"

RB_ROLE="$(
  oc -n "${NAMESPACE}" get confluentrolebinding "${ROLEBINDING}" \
    -o jsonpath='{.status.role}'
)"

RB_STATE="$(
  oc -n "${NAMESPACE}" get confluentrolebinding "${ROLEBINDING}" \
    -o jsonpath='{.status.state}'
)"

RB_READY="$(
  oc -n "${NAMESPACE}" get confluentrolebinding "${ROLEBINDING}" \
    -o jsonpath='{range .status.conditions[?(@.type=="platform.confluent.io/app-ready")]}{.status}{end}'
)"

RB_CLUSTER_ID="$(
  oc -n "${NAMESPACE}" get confluentrolebinding "${ROLEBINDING}" \
    -o jsonpath='{.status.kafkaClusterID}'
)"

RB_MDS_ENDPOINT="$(
  oc -n "${NAMESPACE}" get confluentrolebinding "${ROLEBINDING}" \
    -o jsonpath='{.status.mdsEndpoint}'
)"

echo "Principal:        ${RB_PRINCIPAL:-<missing>}"
echo "Role:             ${RB_ROLE:-<missing>}"
echo "State:            ${RB_STATE:-<missing>}"
echo "Ready:            ${RB_READY:-<missing>}"
echo "Kafka cluster ID: ${RB_CLUSTER_ID:-<missing>}"
echo "MDS endpoint:     ${RB_MDS_ENDPOINT:-<missing>}"

[[ "${RB_PRINCIPAL}" == "User:${EXPECTED_CLIENT_ID}" ]] ||
  fatal "Role-binding principal does not match User:${EXPECTED_CLIENT_ID}."

[[ "${RB_ROLE}" == "SystemAdmin" ]] ||
  fatal "Expected SystemAdmin; found ${RB_ROLE:-missing}."

[[ "${RB_STATE^^}" == "CREATED" ]] ||
  fatal "Role binding is not in CREATED state."

[[ "${RB_READY}" == "True" ]] ||
  fatal "Role binding does not report app-ready=True."

echo "PASS: Control Center SystemAdmin binding is reconciled."

###############################################################################
# 2b. Validate Kafka embedded REST role binding (DEV-specific)
###############################################################################

echo
echo "=== 2b. Validating Kafka embedded REST role binding ==="

EMBEDDED_RB="kafka-embedded-rest-systemadmin"

EMBEDDED_READY="$(
  oc -n "${NAMESPACE}" get confluentrolebinding "${EMBEDDED_RB}" \
    -o jsonpath='{.status.conditions[?(@.type=="platform.confluent.io/app-ready")].status}' \
    2>/dev/null || true
)"

EMBEDDED_PRINCIPAL="$(
  oc -n "${NAMESPACE}" get confluentrolebinding "${EMBEDDED_RB}" \
    -o jsonpath='{.status.principal}' 2>/dev/null || true
)"

echo "Principal: ${EMBEDDED_PRINCIPAL:-<missing>}"
echo "Ready:     ${EMBEDDED_READY:-<missing>}"

[[ "${EMBEDDED_PRINCIPAL}" == \
   "User:kafka.dah-flink-dev.svc.cluster.local" ]] ||
  fatal "${EMBEDDED_RB} has the wrong or missing principal."

[[ "${EMBEDDED_READY}" == "True" ]] ||
  fatal "${EMBEDDED_RB} is not app-ready=True."

echo "PASS: Kafka embedded REST binding is reconciled."

###############################################################################
# 3. Validate Kafka cluster and C3 resources
###############################################################################

echo
echo "=== 3. Validating Kafka and Control Center resources ==="

for POD in kafka-0 kafka-1 kafka-2; do
  oc -n "${NAMESPACE}" get pod "${POD}" >/dev/null 2>&1 ||
    fatal "Kafka broker pod ${POD} does not exist."

  PHASE="$(pod_phase "${POD}")"
  READY="$(pod_ready "${POD}")"

  echo "${POD}: phase=${PHASE:-unknown}, ready=${READY:-unknown}"

  [[ "${PHASE}" == "Running" && "${READY}" == "True" ]] ||
    fatal "${POD} is not Running and Ready."
done

oc -n "${NAMESPACE}" get controlcenter "${C3_CR}" >/dev/null 2>&1 ||
  fatal "ControlCenter/${C3_CR} does not exist."

oc -n "${NAMESPACE}" get pod "${C3_POD}" >/dev/null 2>&1 ||
  fatal "Control Center pod ${C3_POD} does not exist."

echo "PASS: Kafka and Control Center resources exist."

###############################################################################
# 4. Capture pre-restart evidence
###############################################################################

echo
echo "=== 4. Capturing pre-restart evidence ==="

oc -n "${NAMESPACE}" get pods -o wide \
  >"${OUTPUT_DIR}/pods-before.txt"

oc -n "${NAMESPACE}" get confluentrolebinding "${ROLEBINDING}" -o yaml \
  >"${OUTPUT_DIR}/controlcenter-rolebinding.yaml"

collect_matching_logs \
  "${KAFKA_POD}" \
  "${OUTPUT_DIR}/${KAFKA_POD}-before.log"

collect_matching_logs \
  "${C3_POD}" \
  "${OUTPUT_DIR}/${C3_POD}-before.log"

echo "Evidence saved under ${OUTPUT_DIR}."

###############################################################################
# 5. Restart only kafka-1
###############################################################################

echo
echo "=== 5. Restarting ${KAFKA_POD} ==="

OLD_KAFKA_UID="$(pod_uid "${KAFKA_POD}")"

[[ -n "${OLD_KAFKA_UID}" ]] ||
  fatal "Could not determine the UID of ${KAFKA_POD}."

echo "Deleting ${KAFKA_POD} with UID ${OLD_KAFKA_UID}..."

oc -n "${NAMESPACE}" delete pod "${KAFKA_POD}" --wait=false

if ! wait_for_replacement \
  "${KAFKA_POD}" \
  "${OLD_KAFKA_UID}" \
  "${KAFKA_WAIT_SECONDS}"; then

  fatal "Replacement ${KAFKA_POD} was not created within ${KAFKA_WAIT_SECONDS}s."
fi

echo "Waiting for ${KAFKA_POD} to become Ready..."

if ! wait_for_ready "${KAFKA_POD}" "${KAFKA_WAIT_SECONDS}"; then
  fatal "${KAFKA_POD} failed to become Ready."
fi

echo "PASS: ${KAFKA_POD} replacement is Ready."

###############################################################################
# 6. Ensure the complete Kafka cluster is Ready
###############################################################################

echo
echo "=== 6. Verifying all Kafka brokers after restart ==="

for POD in kafka-0 kafka-1 kafka-2; do
  PHASE="$(pod_phase "${POD}")"
  READY="$(pod_ready "${POD}")"

  echo "${POD}: phase=${PHASE:-unknown}, ready=${READY:-unknown}"

  [[ "${PHASE}" == "Running" && "${READY}" == "True" ]] ||
    fatal "${POD} is not healthy after restarting ${KAFKA_POD}."
done

KAFKA_CR_READY="$(
  oc -n "${NAMESPACE}" get kafka kafka \
    -o jsonpath='{range .status.conditions[?(@.type=="platform.confluent.io/cluster-ready")]}{.status}{end}' \
    2>/dev/null ||
  true
)"

echo "Kafka CR cluster-ready: ${KAFKA_CR_READY:-<not reported>}"

if [[ -n "${KAFKA_CR_READY}" && "${KAFKA_CR_READY}" != "True" ]]; then
  fatal "Kafka CR does not report cluster-ready=True."
fi

echo "PASS: Kafka cluster is ready."

###############################################################################
# 7. Restart Control Center
###############################################################################

echo
echo "=== 7. Restarting ${C3_POD} ==="

OLD_C3_UID="$(pod_uid "${C3_POD}")"

[[ -n "${OLD_C3_UID}" ]] ||
  fatal "Could not determine the UID of ${C3_POD}."

echo "Deleting ${C3_POD} with UID ${OLD_C3_UID}..."

oc -n "${NAMESPACE}" delete pod "${C3_POD}" --wait=false

if ! wait_for_replacement \
  "${C3_POD}" \
  "${OLD_C3_UID}" \
  "${C3_WAIT_SECONDS}"; then

  fatal "Replacement ${C3_POD} was not created within ${C3_WAIT_SECONDS}s."
fi

echo "Waiting for ${C3_POD} to become Ready..."

if ! wait_for_ready "${C3_POD}" "${C3_WAIT_SECONDS}"; then
  fatal "${C3_POD} failed to become Ready."
fi

echo "PASS: ${C3_POD} replacement is Ready."

###############################################################################
# 8. Allow post-start health checks to execute
###############################################################################

echo
echo "=== 8. Allowing C3 health checks to execute ==="

echo "Waiting 45 seconds for MDS, Connect and Schema Registry checks..."

for COUNTDOWN in 45 30 15; do
  echo "${COUNTDOWN}s remaining..."
  sleep 15
done

###############################################################################
# 9. Capture post-restart logs
###############################################################################

echo
echo "=== 9. Capturing post-restart evidence ==="

collect_matching_logs \
  "${C3_POD}" \
  "${OUTPUT_DIR}/${C3_POD}-after.log"

for POD in kafka-0 kafka-1 kafka-2; do
  collect_matching_logs \
    "${POD}" \
    "${OUTPUT_DIR}/${POD}-after.log"
done

oc -n "${NAMESPACE}" get pods -o wide \
  >"${OUTPUT_DIR}/pods-after.txt"

oc -n "${NAMESPACE}" get controlcenter "${C3_CR}" -o yaml \
  >"${OUTPUT_DIR}/controlcenter-after.yaml"

###############################################################################
# 10. Display significant C3 results
###############################################################################

echo
echo "=== 10. Control Center results ==="

C3_LOG="${OUTPUT_DIR}/${C3_POD}-after.log"

grep -Ei \
  'Invalid Token|User Identity not found|Failed to authenticate|first health check failed|New endpoints|Started NetworkTraffic|License for control-center|License\(s\) found|PKIX|SSLHandshakeException|Connection refused' \
  "${C3_LOG}" |
  tail -250 ||
true

###############################################################################
# 11. Display broker-side MDS results
###############################################################################

echo
echo "=== 11. Broker-side MDS results ==="

for POD in kafka-0 kafka-1 kafka-2; do
  echo
  echo "----- ${POD} -----"

  BROKER_LOG="${OUTPUT_DIR}/${POD}-after.log"

  grep -Ei \
    "${EXPECTED_CLIENT_ID}|Invalid Token|User Identity not found|Failed to authenticate|/security/1.0/authenticate" \
    "${BROKER_LOG}" |
    tail -150 ||
  true
done

###############################################################################
# 12. Evaluate results
###############################################################################

echo
echo "=== 12. Final evaluation ==="

C3_FAILURE=0
C3_LISTENER=0
C3_LICENSE=0
BROKER_401=0

if grep -Eqi \
  'Invalid Token : User Identity not found|Failed to authenticate' \
  "${C3_LOG}"; then
  C3_FAILURE=1
fi

if grep -Eq \
  'Started NetworkTrafficServerConnector.*9021' \
  "${C3_LOG}"; then
  C3_LISTENER=1
fi

if grep -Eq \
  'License for control-center expires|License\(s\) found' \
  "${C3_LOG}"; then
  C3_LICENSE=1
fi

for POD in kafka-0 kafka-1 kafka-2; do
  BROKER_LOG="${OUTPUT_DIR}/${POD}-after.log"

  if grep -Eq \
    'GET /security/1.0/authenticate HTTP/[0-9.]+\" 401' \
    "${BROKER_LOG}"; then
    BROKER_401=1
  fi
done

echo "C3 pod Ready:              $(pod_ready "${C3_POD}")"
echo "C3 HTTPS 9021 started:     ${C3_LISTENER}"
echo "C3 license loaded:         ${C3_LICENSE}"
echo "C3 identity failure found: ${C3_FAILURE}"
echo "Broker MDS 401 found:      ${BROKER_401}"

echo
echo "Current resources:"

oc -n "${NAMESPACE}" get pods \
  kafka-0 kafka-1 kafka-2 "${C3_POD}" \
  -o wide

echo
echo "Control Center CR conditions:"

oc -n "${NAMESPACE}" get controlcenter "${C3_CR}" \
  -o jsonpath='{range .status.conditions[*]}{.type}={.status}{"  reason="}{.reason}{"  message="}{.message}{"\n"}{end}' ||
true

###############################################################################
# 13. Final decision
###############################################################################

if [[ "${C3_FAILURE}" -ne 0 || "${BROKER_401}" -ne 0 ]]; then
  echo
  echo "NO-GO: MDS continues to reject the Control Center OAuth identity."
  echo "Evidence directory: ${OUTPUT_DIR}"
  echo
  echo "Do not restart additional brokers automatically."
  echo "The next step is to compare MDS OAuth configuration and token claims."
  exit 1
fi

if [[ "${C3_LISTENER}" -ne 1 ]]; then
  echo
  echo "NO-GO: Control Center did not start its HTTPS listener on port 9021."
  echo "Evidence directory: ${OUTPUT_DIR}"
  exit 1
fi

if [[ "${C3_LICENSE}" -ne 1 ]]; then
  echo
  echo "WARNING: C3 started, but explicit license confirmation was not captured."
fi

echo
echo "GO: Kafka-1 and Control Center recovered without the known MDS error."
echo "Evidence directory: ${OUTPUT_DIR}"
exit 0