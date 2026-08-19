#!/usr/bin/env bash
set -euo pipefail

NS="${NS:-dah-flink-dev}"
TRUSTSTORE="/var/ssl/truststore/bundle.p12"
TRUSTSTORE_PASSWORD="changeit"

echo "============================================================"
echo "DEV Java TLS trust diagnostic (read-only)"
echo "Namespace: ${NS}"
echo "============================================================"

command -v oc >/dev/null 2>&1 || {
  echo "FATAL: oc is not installed on the pipeline agent"
  exit 1
}
command -v openssl >/dev/null 2>&1 || {
  echo "FATAL: openssl is not installed on the pipeline agent"
  exit 1
}

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

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

  echo "--- Export trust anchors from the pod's mounted PKCS12 file ---"
  local pod_dir="$WORK_DIR/$pod"
  mkdir -p "$pod_dir"
  oc -n "$NS" exec "$pod" -c "$container" -- \
    keytool -list -rfc -storetype PKCS12 -keystore "$TRUSTSTORE" \
      -storepass "$TRUSTSTORE_PASSWORD" >"$pod_dir/trust-anchors.pem"

  local failures=0
  probe_endpoint "$pod" "$container" "$pod_dir" myapps.firstcitizens.com 443 || failures=$((failures + 1))
  probe_endpoint "$pod" "$container" "$pod_dir" kafka.dah-flink-dev.svc.cluster.local 8090 || failures=$((failures + 1))
  (( failures == 0 ))
}

probe_endpoint() {
  local pod="$1"
  local container="$2"
  local pod_dir="$3"
  local host="$4"
  local port="$5"
  local endpoint_dir="$pod_dir/${host}-${port}"
  local cert_count
  local i

  mkdir -p "$endpoint_dir"
  echo "TEST: ${pod} -> ${host}:${port}"

  # keytool performs the connection inside the selected pod. Its RFC output is
  # copied to the agent only for offline verification; no private keys exist in it.
  if ! oc -n "$NS" exec "$pod" -c "$container" -- \
      keytool -printcert -sslserver "${host}:${port}" -rfc \
      >"$endpoint_dir/peer-chain.txt" 2>"$endpoint_dir/keytool.err"; then
    echo "TLS FAIL: pod could not retrieve ${host}:${port} certificate chain"
    sed -n '1,20p' "$endpoint_dir/keytool.err"
    return 1
  fi

  awk -v dir="$endpoint_dir" '
    /-----BEGIN CERTIFICATE-----/ {n++; capture=1}
    capture {print > (dir "/cert-" n ".pem")}
    /-----END CERTIFICATE-----/ {capture=0; close(dir "/cert-" n ".pem")}
    END {print n+0 > (dir "/count")}
  ' "$endpoint_dir/peer-chain.txt"

  cert_count="$(cat "$endpoint_dir/count")"
  if [[ ! "$cert_count" =~ ^[0-9]+$ ]] || (( cert_count < 1 )); then
    echo "TLS FAIL: no peer certificate was captured from ${host}:${port}"
    return 1
  fi

  : >"$endpoint_dir/intermediates.pem"
  if (( cert_count > 1 )); then
    for ((i=2; i<=cert_count; i++)); do
      cat "$endpoint_dir/cert-${i}.pem" >>"$endpoint_dir/intermediates.pem"
    done
  fi

  echo "Leaf certificate:"
  openssl x509 -in "$endpoint_dir/cert-1.pem" -noout -subject -issuer -dates

  local verify_args=(verify -purpose sslserver -verify_hostname "$host"
    -CAfile "$pod_dir/trust-anchors.pem")
  if [[ -s "$endpoint_dir/intermediates.pem" ]]; then
    verify_args+=(-untrusted "$endpoint_dir/intermediates.pem")
  fi
  verify_args+=("$endpoint_dir/cert-1.pem")

  if openssl "${verify_args[@]}"; then
    echo "TLS PASS: ${pod} trusts ${host}:${port}; chain and hostname valid"
  else
    echo "TLS FAIL: ${pod} does not validate ${host}:${port} with bundle.p12"
    return 1
  fi
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