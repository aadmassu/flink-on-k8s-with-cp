#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${1:-dah-flink-dev}"
C3_CR="${C3_CR:-controlcenter}"
ROLEBINDING="${ROLEBINDING:-controlcenter-systemadmin}"
EXPECTED_CLIENT_ID="${EXPECTED_CLIENT_ID:-0oa1ov6h5mwmQTCKI358}"
WAIT_SECONDS="${WAIT_SECONDS:-600}"
LOG_SINCE="${LOG_SINCE:-20m}"

echo "============================================================"
echo "Control Center OAuth/MDS diagnostic and restart"
echo "Namespace:       ${NAMESPACE}"
echo "Role binding:    ${ROLEBINDING}"
echo "Expected client: ${EXPECTED_CLIENT_ID}"
echo "============================================================"

command -v oc >/dev/null 2>&1 || {
  echo "FATAL: oc is not installed or not in PATH."
  exit 1
}

oc whoami >/dev/null 2>&1 || {
  echo "FATAL: The current session is not logged into OpenShift."
  exit 1
}

###############################################################################
# 1. Validate namespace and Control Center CR
###############################################################################

echo
echo "=== 1. Validating namespace and Control Center CR ==="

oc get namespace "${NAMESPACE}" >/dev/null

if ! oc -n "${NAMESPACE}" get controlcenter "${C3_CR}" >/dev/null 2>&1; then
  echo "FATAL: ControlCenter/${C3_CR} does not exist in ${NAMESPACE}."
  exit 1
fi

###############################################################################
# 2. Validate Control Center role binding
###############################################################################

echo
echo "=== 2. Validating Control Center SystemAdmin role binding ==="

if ! oc -n "${NAMESPACE}" get confluentrolebinding "${ROLEBINDING}" \
  >/dev/null 2>&1; then
  echo "FATAL: ConfluentRolebinding/${ROLEBINDING} does not exist."
  exit 1
fi

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

echo "Principal:       ${RB_PRINCIPAL:-<missing>}"
echo "Role:            ${RB_ROLE:-<missing>}"
echo "State:           ${RB_STATE:-<missing>}"
echo "ApplicationReady:${RB_READY:-<missing>}"
echo "Kafka cluster ID:${RB_CLUSTER_ID:-<missing>}"

if [[ "${RB_PRINCIPAL}" != "User:${EXPECTED_CLIENT_ID}" ]]; then
  echo "FATAL: Role-binding principal does not match the expected client ID."
  exit 1
fi

if [[ "${RB_ROLE}" != "SystemAdmin" ]]; then
  echo "FATAL: Expected role SystemAdmin; found '${RB_ROLE:-missing}'."
  exit 1
fi

if [[ "${RB_STATE^^}" != "CREATED" ]]; then
  echo "FATAL: Role binding is not in CREATED state."
  oc -n "${NAMESPACE}" describe confluentrolebinding "${ROLEBINDING}" || true
  exit 1
fi

if [[ "${RB_READY}" != "True" ]]; then
  echo "FATAL: Role binding does not report app-ready=True."
  oc -n "${NAMESPACE}" describe confluentrolebinding "${ROLEBINDING}" || true
  exit 1
fi

echo "PASS: Control Center SystemAdmin role binding is reconciled."

###############################################################################
# 3. Discover and validate Kafka broker pods
###############################################################################

echo
echo "=== 3. Validating Kafka broker readiness ==="

mapfile -t KAFKA_PODS < <(
  oc -n "${NAMESPACE}" get pods \
    -o custom-columns='NAME:.metadata.name' \
    --no-headers |
    grep -E '^kafka-[0-9]+$' |
    sort
)

if [[ "${#KAFKA_PODS[@]}" -eq 0 ]]; then
  echo "FATAL: No Kafka broker pods were found."
  exit 1
fi

echo "Kafka pods discovered: ${KAFKA_PODS[*]}"

KAFKA_NOT_READY=0

for POD in "${KAFKA_PODS[@]}"; do
  PHASE="$(
    oc -n "${NAMESPACE}" get pod "${POD}" \
      -o jsonpath='{.status.phase}'
  )"

  READY="$(
    oc -n "${NAMESPACE}" get pod "${POD}" \
      -o jsonpath='{range .status.conditions[?(@.type=="Ready")]}{.status}{end}'
  )"

  RESTARTS="$(
    oc -n "${NAMESPACE}" get pod "${POD}" \
      -o jsonpath='{range .status.containerStatuses[*]}{.restartCount}{" "}{end}'
  )"

  echo "${POD}: phase=${PHASE:-unknown}, ready=${READY:-unknown}, restarts=${RESTARTS:-unknown}"

  if [[ "${PHASE}" != "Running" || "${READY}" != "True" ]]; then
    KAFKA_NOT_READY=1
  fi
done

if [[ "${KAFKA_NOT_READY}" -ne 0 ]]; then
  echo "FATAL: One or more Kafka brokers are not Ready."
  oc -n "${NAMESPACE}" get pods -o wide
  exit 1
fi

echo "PASS: All Kafka broker pods are Running and Ready."

###############################################################################
# 4. Inspect recent MDS authentication events on every broker
###############################################################################

echo
echo "=== 4. Existing MDS events for the Control Center identity ==="

for POD in "${KAFKA_PODS[@]}"; do
  echo
  echo "----- ${POD} -----"

  MATCHES="$(
    oc -n "${NAMESPACE}" logs "${POD}" --since="${LOG_SINCE}" 2>&1 |
      grep -Ei \
        "${EXPECTED_CLIENT_ID}|Invalid Token|User Identity not found|Failed to authenticate|/security/1.0/authenticate" ||
      true
  )"

  if [[ -n "${MATCHES}" ]]; then
    printf '%s\n' "${MATCHES}" | tail -100
  else
    echo "No matching recent events."
  fi
done

###############################################################################
# 5. Locate the Control Center pod
###############################################################################

echo
echo "=== 5. Locating Control Center pod ==="

C3_POD="$(
  oc -n "${NAMESPACE}" get pods \
    -o custom-columns='NAME:.metadata.name' \
    --no-headers |
    grep -E '^controlcenter-[0-9]+$' |
    head -1 ||
  true
)"

if [[ -z "${C3_POD}" ]]; then
  echo "FATAL: No Control Center pod was found."
  oc -n "${NAMESPACE}" get pods
  exit 1
fi

echo "Control Center pod: ${C3_POD}"

###############################################################################
# 6. Save the current C3 log and restart the pod
###############################################################################

echo
echo "=== 6. Capturing current C3 log before restart ==="

PRE_RESTART_LOG="${AGENT_TEMPDIRECTORY:-/tmp}/${C3_POD}-before-restart.log"

oc -n "${NAMESPACE}" logs "${C3_POD}" \
  --all-containers=true \
  --timestamps >"${PRE_RESTART_LOG}" 2>&1 || true

echo "Pre-restart log: ${PRE_RESTART_LOG}"

echo
echo "=== 7. Restarting Control Center ==="

OLD_UID="$(
  oc -n "${NAMESPACE}" get pod "${C3_POD}" \
    -o jsonpath='{.metadata.uid}'
)"

oc -n "${NAMESPACE}" delete pod "${C3_POD}" --wait=false

echo "Waiting for the existing pod instance to terminate..."

ELAPSED=0
while (( ELAPSED < WAIT_SECONDS )); do
  CURRENT_UID="$(
    oc -n "${NAMESPACE}" get pod "${C3_POD}" \
      -o jsonpath='{.metadata.uid}' 2>/dev/null ||
    true
  )"

  if [[ -n "${CURRENT_UID}" && "${CURRENT_UID}" != "${OLD_UID}" ]]; then
    echo "Replacement pod detected with UID ${CURRENT_UID}."
    break
  fi

  sleep 5
  ELAPSED=$((ELAPSED + 5))
done

if (( ELAPSED >= WAIT_SECONDS )); then
  echo "FATAL: Replacement Control Center pod was not created within ${WAIT_SECONDS}s."
  oc -n "${NAMESPACE}" get pods -o wide
  exit 1
fi

###############################################################################
# 8. Wait for the replacement pod to become Ready
###############################################################################

echo
echo "=== 8. Waiting for replacement Control Center pod readiness ==="

if ! oc -n "${NAMESPACE}" wait \
  --for=condition=Ready \
  "pod/${C3_POD}" \
  --timeout="${WAIT_SECONDS}s"; then

  echo "FATAL: ${C3_POD} did not become Ready."

  oc -n "${NAMESPACE}" get pod "${C3_POD}" -o wide || true
  oc -n "${NAMESPACE}" describe pod "${C3_POD}" || true

  echo
  echo "----- Replacement C3 log -----"
  oc -n "${NAMESPACE}" logs "${C3_POD}" \
    --all-containers=true \
    --timestamps \
    --tail=500 || true

  exit 1
fi

echo "PASS: ${C3_POD} is Ready."

###############################################################################
# 9. Check the replacement C3 log
###############################################################################

echo
echo "=== 9. Evaluating replacement Control Center log ==="

POST_RESTART_LOG="${AGENT_TEMPDIRECTORY:-/tmp}/${C3_POD}-after-restart.log"

oc -n "${NAMESPACE}" logs "${C3_POD}" \
  --all-containers=true \
  --timestamps >"${POST_RESTART_LOG}" 2>&1

echo "Post-restart log: ${POST_RESTART_LOG}"

echo
echo "----- Significant Control Center messages -----"

grep -Ei \
  'Invalid Token|User Identity not found|Failed to authenticate|health check|Started NetworkTraffic|License for control-center|License\(s\) found|PKIX|SSLHandshakeException|Connection refused' \
  "${POST_RESTART_LOG}" |
  tail -200 ||
true

if grep -Eqi \
  'Invalid Token : User Identity not found|Failed to authenticate' \
  "${POST_RESTART_LOG}"; then

  echo
  echo "FATAL: Control Center still has an MDS identity/authentication failure."

  echo
  echo "=== Broker-side evidence after restart ==="

  for POD in "${KAFKA_PODS[@]}"; do
    echo
    echo "----- ${POD} -----"

    oc -n "${NAMESPACE}" logs "${POD}" --since="${LOG_SINCE}" 2>&1 |
      grep -Ei \
        "${EXPECTED_CLIENT_ID}|Invalid Token|User Identity not found|Failed to authenticate|/security/1.0/authenticate" |
      tail -150 ||
    true
  done

  exit 1
fi

###############################################################################
# 10. Final status
###############################################################################

echo
echo "=== 10. Final Control Center status ==="

oc -n "${NAMESPACE}" get controlcenter "${C3_CR}" \
  -o custom-columns='NAME:.metadata.name,STATE:.status.state,READY:.status.readyReplicas,REPLICAS:.status.replicas' ||
true

oc -n "${NAMESPACE}" get pod "${C3_POD}" -o wide

if ! grep -q 'Started NetworkTrafficServerConnector.*9021' "${POST_RESTART_LOG}"; then
  echo "WARNING: Port 9021 startup was not found in the captured log."
else
  echo "PASS: Control Center HTTPS listener started on port 9021."
fi

if grep -q 'License for control-center expires' "${POST_RESTART_LOG}"; then
  echo "PASS: Control Center loaded its enterprise license."
else
  echo "WARNING: No explicit Control Center license confirmation was found."
fi

echo
echo "SUCCESS: Control Center restarted without the known MDS identity error."