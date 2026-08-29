#!/usr/bin/env bash
set -euo pipefail

PIPELINE_FILE=.azure-pipelines/confluent-platform.yaml
ENDPOINT_VALIDATOR=.azure-pipelines/scripts/validate_endpointslices.py
LISTENER_VALIDATOR=.azure-pipelines/scripts/validate_listeners.py
PIPELINE_SHA=$(sha256sum "$PIPELINE_FILE" | awk '{print $1}')
passed=0
failed=0

record() {
  local name=$1
  shift
  if "$@"; then
    printf 'PASS: %s\n' "$name"
    passed=$((passed + 1))
  else
    printf 'FAIL: %s\n' "$name" >&2
    failed=$((failed + 1))
  fi
}

expect_failure() {
  if "$@" >/dev/null 2>&1; then return 1; else return 0; fi
}

test_complete_package() {
  local env
  for env in dev qa uat-p uat-s prd dr; do
    test -f "apps/confluent-platform/$env/kafka.yaml"
    test -f "apps/confluent-platform/$env/controlcenter.yaml"
  done
}

test_endpoint_positive() {
  local actual
  actual=$(printf '%s' '{"items":[{"endpoints":[{"conditions":{"ready":true},"addresses":["10.0.0.1","10.0.0.2"]},{"conditions":{"ready":false},"addresses":["10.0.0.3"]},{"addresses":["10.0.0.4"]}]},{"endpoints":[{"conditions":{"ready":true},"addresses":["10.0.0.5"]}]}]}' | python3 "$ENDPOINT_VALIDATOR")
  test "$actual" = 4
}

test_endpoint_empty() {
  test "$(printf '%s' '{"items":[]}' | python3 "$ENDPOINT_VALIDATOR")" = 0
}

test_listener_all_environments() {
  local env
  for env in dev qa uat-p uat-s prd dr; do
    python3 "$LISTENER_VALIDATOR" "apps/confluent-platform/$env" >/dev/null
  done
}

test_listener_negative() {
  local temp
  temp=$(mktemp -d)
  cp apps/confluent-platform/dev/{kafka,schemaregistry,connect,kafkarest,controlcenter}.yaml "$temp/"
  sed -i 's/:9092/:9071/g' "$temp/connect.yaml"
  expect_failure python3 "$LISTENER_VALIDATOR" "$temp"
  local result=$?
  rm -rf "$temp"
  return "$result"
}

test_listener_missing_is_fatal() {
  local temp
  temp=$(mktemp -d)
  cp apps/confluent-platform/dev/{kafka,schemaregistry,connect,kafkarest}.yaml "$temp/"
  expect_failure python3 "$LISTENER_VALIDATOR" "$temp"
  local result=$?
  rm -rf "$temp"
  return "$result"
}

test_external_secret_mapping() {
  grep -q 'ESO_CR_TO_TARGET\["$cr_name"\]="$target_name"' "$PIPELINE_FILE" &&
    grep -q 'get externalsecret "$es_cr_name"' "$PIPELINE_FILE" &&
    grep -q 'es_target_name="${ESO_CR_TO_TARGET\[$es_cr_name\]}"' "$PIPELINE_FILE"
}

test_mds_verified_tls() {
  grep -q 'exec -i kafka-0 -- bash -s' "$PIPELINE_FILE" &&
    grep -q -- '--cacert /tmp/ca-cert.pem' "$PIPELINE_FILE" &&
    grep -q -- '--fail --show-error' "$PIPELINE_FILE" &&
    ! grep -Eq 'curl[^\n]*-[A-Za-z]*k' "$PIPELINE_FILE"
}

test_readiness_condition() {
  local block
  block=$(sed -n '/wait_component_ready()/,/^                  }/p' "$PIPELINE_FILE")
  grep -q 'platform.confluent.io/cluster-ready' <<<"$block" &&
    ! grep -q 'type=="Ready"' <<<"$block"
}

test_certificate_order() {
  local dry apply wait dependent
  dry=$(grep -n 'PHASE 1: DRY-RUN Certificate' "$PIPELINE_FILE" | head -1 | cut -d: -f1)
  apply=$(grep -n 'PHASE 2: APPLY Certificate' "$PIPELINE_FILE" | head -1 | cut -d: -f1)
  wait=$(grep -n 'PHASE 3: WAIT' "$PIPELINE_FILE" | head -1 | cut -d: -f1)
  dependent=$(grep -n 'PHASE 4: DRY-RUN Dependent' "$PIPELINE_FILE" | head -1 | cut -d: -f1)
  test "$dry" -lt "$apply" && test "$apply" -lt "$wait" && test "$wait" -lt "$dependent" &&
    grep -q -- '-checkend 86400' "$PIPELINE_FILE" &&
    grep -q -- '-checkhost "$dns_name"' "$PIPELINE_FILE" &&
    grep -q 'tls.crt and tls.key do not match' "$PIPELINE_FILE"
}

test_namespace_before_prereqs() {
  local validate create
  validate=$(grep -n 'Validate canonical namespace before create-prereqs' "$PIPELINE_FILE" | head -1 | cut -d: -f1)
  create=$(grep -n 'Create prerequisite Opaque Secrets' "$PIPELINE_FILE" | head -1 | cut -d: -f1)
  test "$validate" -lt "$create"
}

# --- clientAuth EKU check: deterministic, not pipeline-exit-status dependent ---
# Mirrors the two-step form used at all three EKU sites in the pipeline.
eku_has_client_auth() {
  local cert=$1 eku_text
  eku_text=$(openssl x509 -in "$cert" -noout -ext extendedKeyUsage 2>/dev/null || true)
  grep -Fq "TLS Web Client Authentication" <<< "$eku_text"
}

EKU_TMP=$(mktemp -d)
trap 'rm -rf "$EKU_TMP"' EXIT

make_eku_cert() {
  local out=$1 eku=$2 sans=${3:-}
  {
    printf '[req]\ndistinguished_name=dn\n[dn]\n[v3]\nextendedKeyUsage=%s\n' "$eku"
    [ -n "$sans" ] && printf 'subjectAltName=%s\n' "$sans"
  } > "$EKU_TMP/req.cnf"
  openssl req -x509 -newkey rsa:2048 -keyout "$EKU_TMP/key.pem" -out "$out" \
    -days 2 -nodes -subj "/CN=cfk-operator-rbac.apps.pd.ocp.fcbint.net" \
    -extensions v3 -config "$EKU_TMP/req.cnf" 2>/dev/null
}

test_eku_accepts_client_auth() {
  make_eku_cert "$EKU_TMP/client.pem" clientAuth
  eku_has_client_auth "$EKU_TMP/client.pem"
}

test_eku_rejects_server_only() {
  make_eku_cert "$EKU_TMP/server.pem" serverAuth
  ! eku_has_client_auth "$EKU_TMP/server.pem"
}

# A large certificate makes the consumer exit long before the producer finishes.
# The two-step form must stay deterministic where a pipe into grep -q would not.
test_eku_large_cert_deterministic() {
  local sans i rc
  sans=$(for i in $(seq 1 1500); do printf 'DNS:h%05d.apps.pd.ocp.fcbint.net,' "$i"; done | sed 's/,$//')
  make_eku_cert "$EKU_TMP/big.pem" clientAuth "$sans"
  for i in $(seq 1 25); do
    eku_has_client_auth "$EKU_TMP/big.pem" || return 1
  done
  return 0
}

# No EKU extension at all must fail closed, not error out.
test_eku_missing_extension_fails() {
  openssl req -x509 -newkey rsa:2048 -keyout "$EKU_TMP/k3.pem" -out "$EKU_TMP/noeku.pem" \
    -days 2 -nodes -subj "/CN=no-eku.example.net" 2>/dev/null
  ! eku_has_client_auth "$EKU_TMP/noeku.pem"
}

# The fragile pattern must not exist in executable lines (comments may name it).
test_no_openssl_grep_q_patterns() {
  ! grep -nE 'openssl[^|]*\|[^|]*grep[[:space:]]+-q' "$PIPELINE_FILE" \
    | grep -vE '^[0-9]+:[[:space:]]*#'
}

test_eku_checks_use_captured_output() {
  local n
  n=$(grep -c 'grep -Fq "TLS Web Client Authentication" <<<' "$PIPELINE_FILE")
  test "$n" -eq 3
}

# The fix must be global: no environment-gated EKU logic.
test_eku_checks_are_environment_neutral() {
  ! grep -nE '(prd|dr|uat)[^\n]*TLS Web Client Authentication' "$PIPELINE_FILE"
}

printf 'Pipeline SHA-256: %s\n' "$PIPELINE_SHA"
record 'complete six-environment package' test_complete_package
record 'EndpointSlice counts ready/unspecified endpoints across all slices' test_endpoint_positive
record 'EndpointSlice empty list returns zero' test_endpoint_empty
record 'EndpointSlice invalid JSON fails' expect_failure bash -c "printf 'not-json' | python3 '$ENDPOINT_VALIDATOR'"
record 'listener contract passes all six environments' test_listener_all_environments
record 'listener validator rejects a managed component on the wrong port' test_listener_negative
record 'listener validator treats a missing manifest as fatal' test_listener_missing_is_fatal
record 'ExternalSecret CR and target names remain separate' test_external_secret_mapping
record 'MDS uses verified TLS and stdin-enabled oc exec' test_mds_verified_tls
record 'managed components use CFK cluster-ready condition' test_readiness_condition
record 'certificate phases are ordered before mutation/dependency validation' test_certificate_order
record 'namespace validation precedes prerequisite creation' test_namespace_before_prereqs
record 'clientAuth EKU check accepts a clientAuth certificate' test_eku_accepts_client_auth
record 'clientAuth EKU check rejects a serverAuth-only certificate' test_eku_rejects_server_only
record 'clientAuth EKU check rejects a certificate with no EKU extension' test_eku_missing_extension_fails
record 'clientAuth EKU check is deterministic on a large certificate' test_eku_large_cert_deterministic
record 'no openssl-piped-into-grep -q patterns remain' test_no_openssl_grep_q_patterns
record 'all three EKU checks search captured output' test_eku_checks_use_captured_output
record 'EKU checks are environment-neutral' test_eku_checks_are_environment_neutral

printf 'Passed: %d\nFailed: %d\n' "$passed" "$failed"
test "$failed" -eq 0
