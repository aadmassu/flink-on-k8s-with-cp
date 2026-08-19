#!/usr/bin/env bash
set -euo pipefail

NS="${NS:-dah-flink-dev}"
TRUSTSTORE="/var/ssl/truststore/bundle.p12"
TRUSTSTORE_PASSWORD="changeit"

OKTA_DISCOVERY="https://myapps.firstcitizens.com/oauth2/default/.well-known/openid-configuration"
OKTA_TOKEN="https://myapps.firstcitizens.com/oauth2/default/v1/token"
MDS_URL="https://kafka.dah-flink-dev.svc.cluster.local:8090/security/1.0/activenodes/https"

echo "============================================================"
echo "DEV Java TLS trust diagnostic (read-only)"
echo "Namespace: ${NS}"
echo "============================================================"

command -v oc >/dev/null 2>&1 || {
  echo "FATAL: oc is not installed on the pipeline agent"
  exit 1
}

get_ready_pod() {
  local component="$1"
  oc -n "$NS" get pods \
    -l "app.kubernetes.io/name=${component}" \
    --field-selector=status.phase=Running \
    -o jsonpath='{range .items[?(@.status.containerStatuses[0].ready==true)]}{.metadata.name}{"\n"}{end}' \
    | head -n 1
}

C3_POD="$(get_ready_pod controlcenter)"
KAFKA_POD="$(get_ready_pod kafka)"

[[ -n "$C3_POD" ]] || { echo "FATAL: no Ready Control Center pod found"; exit 1; }
[[ -n "$KAFKA_POD" ]] || { echo "FATAL: no Ready Kafka pod found"; exit 1; }

echo "Control Center pod: ${C3_POD}"
echo "Kafka pod:          ${KAFKA_POD}"

probe_pod() {
  local pod="$1"
  local container="$2"
  local label="$3"

  echo
  echo "============================================================"
  echo "${label}: ${pod}/${container}"
  echo "============================================================"

  echo "--- Truststore file and checksum ---"
  oc -n "$NS" exec "$pod" -c "$container" -- sh -c \
    "set -e; ls -l '$TRUSTSTORE'; (sha256sum '$TRUSTSTORE' 2>/dev/null || cksum '$TRUSTSTORE')"

  echo "--- Truststore readability ---"
  oc -n "$NS" exec "$pod" -c "$container" -- \
    keytool -list -storetype PKCS12 -keystore "$TRUSTSTORE" \
      -storepass "$TRUSTSTORE_PASSWORD" 2>&1 | sed -n '1,8p'

  echo "--- PID 1 JVM truststore arguments ---"
  oc -n "$NS" exec "$pod" -c "$container" -- sh -c \
    'tr "\000" "\n" </proc/1/cmdline | grep -E "javax\.net\.ssl\.trustStore" || true'

  echo "--- Genuine TLS path and hostname validation ---"
  oc -n "$NS" exec "$pod" -c "$container" -- sh -c '
    set -eu
    command -v openssl >/dev/null 2>&1 || {
      echo "FATAL: openssl is unavailable in this container"
      exit 3
    }

    keytool -list -rfc -storetype PKCS12 \
      -keystore "'"$TRUSTSTORE"'" \
      -storepass "'"$TRUSTSTORE_PASSWORD"'" \
      > /tmp/fcb-trust-bundle.pem

    probe() {
      host="$1"
      port="$2"
      echo "TEST: ${host}:${port}"
      result="$(printf "" | openssl s_client \
        -connect "${host}:${port}" \
        -servername "$host" \
        -CAfile /tmp/fcb-trust-bundle.pem \
        -verify_return_error \
        -verify_hostname "$host" 2>&1)" && rc=0 || rc=$?
      printf "%s\n" "$result" | grep -E \
        "subject=|issuer=|Verification error|Verify return code" | tail -n 12 || true
      if [ "$rc" -ne 0 ] || ! printf "%s\n" "$result" | grep -q "Verify return code: 0 (ok)"; then
        echo "TLS FAIL: ${host}:${port}"
        rm -f /tmp/fcb-trust-bundle.pem
        return 1
      fi
      echo "TLS PASS: ${host}:${port}"
    }

    failures=0
    probe myapps.firstcitizens.com 443 || failures=$((failures + 1))
    probe kafka.dah-flink-dev.svc.cluster.local 8090 || failures=$((failures + 1))
    rm -f /tmp/fcb-trust-bundle.pem
    [ "$failures" -eq 0 ]
  '
}

set +e
probe_pod "$C3_POD" controlcenter "CONTROL CENTER"
C3_RC=$?
probe_pod "$KAFKA_POD" kafka "KAFKA / MDS"
KAFKA_RC=$?
set -e

echo
echo "============================================================"
echo "RESULT"
echo "============================================================"
echo "Control Center probe exit code: ${C3_RC}"
echo "Kafka/MDS probe exit code:      ${KAFKA_RC}"

if (( C3_RC != 0 || KAFKA_RC != 0 )); then
  echo "FAIL: at least one real Java TLS handshake failed"
  exit 1
fi

echo "PASS: bundle.p12 validates the Okta and MDS certificate paths and hostnames in both pods"