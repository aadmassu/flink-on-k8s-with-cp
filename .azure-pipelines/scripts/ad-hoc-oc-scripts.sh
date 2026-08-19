#!/usr/bin/env bash
set -euo pipefail

NS="dah-flink-dev"
TRUSTSTORE="/var/ssl/truststore/bundle.p12"
STOREPASS="changeit"

echo "=== 1. Wait for Control Center and Kafka ==="
oc -n "$NS" wait pod/controlcenter-0 --for=condition=Ready --timeout=15m
oc -n "$NS" wait pod/kafka-0 --for=condition=Ready --timeout=15m

run_tls_probes() {
  pod="$1"
  container="$2"
  echo "=== TLS probes from ${pod}/${container} ==="

  oc -n "$NS" exec "$pod" -c "$container" -- sh -s -- \
    "$TRUSTSTORE" "$STOREPASS" <<'REMOTE'
set -eu
truststore="$1"
storepass="$2"
pem_bundle="/tmp/fcb-c3-ca-bundle.pem"

command -v openssl >/dev/null 2>&1 || {
  echo "FATAL: openssl is not installed in this container"
  exit 1
}
test -r "$truststore" || {
  echo "FATAL: truststore is not readable: $truststore"
  exit 1
}

echo "Truststore: $truststore"
keytool -list -keystore "$truststore" -storetype PKCS12 \
  -storepass "$storepass" | sed -n '1,6p'

rm -f "$pem_bundle"
openssl pkcs12 -in "$truststore" -passin "pass:$storepass" \
  -nokeys -out "$pem_bundle" >/dev/null 2>&1
test -s "$pem_bundle" || {
  echo "FATAL: unable to extract CA certificates from $truststore"
  exit 1
}

probe() {
  host="$1"
  port="$2"
  label="$3"
  output="/tmp/tls-probe-${port}.txt"
  echo "--- $label: ${host}:${port} ---"
  if openssl s_client -connect "${host}:${port}" -servername "$host" \
      -CAfile "$pem_bundle" -verify_return_error -verify_hostname "$host" \
      </dev/null >"$output" 2>&1; then
    grep -E 'subject=|issuer=|Verify return code' "$output" | tail -n 6
    echo "TLS PASS: $label"
  else
    grep -E 'subject=|issuer=|verify error|Verify return code|certificate verify failed' \
      "$output" | tail -n 12 || tail -n 20 "$output"
    echo "TLS FAIL: $label"
    return 1
  fi
}

failures=0
probe myapps.firstcitizens.com 443 "Okta" || failures=$((failures + 1))
probe kafka.dah-flink-dev.svc.cluster.local 8090 "Kafka MDS" || failures=$((failures + 1))
rm -f "$pem_bundle" /tmp/tls-probe-443.txt /tmp/tls-probe-8090.txt

if [ "$failures" -ne 0 ]; then
  echo "RESULT: FAIL ($failures TLS probe(s) failed)"
  exit 1
fi
echo "RESULT: PASS (all TLS handshakes succeeded)"
REMOTE
}

run_tls_probes controlcenter-0 controlcenter
run_tls_probes kafka-0 kafka

echo "=== 2. Supported C3 REST truststore properties ==="
oc -n "$NS" exec controlcenter-0 -c controlcenter -- sh -c \
  'grep -E "^confluent\.controlcenter\.rest\.ssl\.(truststore|endpoint)" /opt/confluentinc/etc/controlcenter/controlcenter.properties'

echo "=== 3. Kafka/MDS OIDC and truststore properties ==="
oc -n "$NS" exec kafka-0 -c kafka -- sh -c \
  'grep -E "^(confluent\.oidc\.idp\.|confluent\.metadata\.ssl\.truststore\.)" /mnt/config/server.properties | sed -E "s/(client\.secret=).*/\1[REDACTED]/"'

echo "=== 4. Callback-correlated Control Center logs ==="
oc -n "$NS" logs controlcenter-0 -c controlcenter --since=20m | \
  grep -Ei -C 15 \
    'authorization-code/callback|PKIX|SSLHandshakeException|certificate_unknown|ProcessingException' \
  || true

echo "=== 5. Callback-correlated Kafka/MDS logs ==="
oc -n "$NS" logs kafka-0 -c kafka --since=20m | \
  grep -Ei -C 15 \
    'oidc|PKIX|SSLHandshakeException|certificate_unknown|ProcessingException|/security/1.0' \
  || true

echo "PASS: Focused C3 and MDS TLS diagnostics completed."