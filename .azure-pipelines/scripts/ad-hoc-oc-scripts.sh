#!/usr/bin/env bash

set -euo pipefail

NS="dah-flink-dev"
OKTA_HOST="myapps.firstcitizens.com"
OKTA_PORT="443"
TRUSTSTORE="/var/ssl/truststore/bundle.p12"
TRUSTSTORE_PASSWORD="changeit"

echo "============================================================"
echo "DEV Kafka/MDS Okta certificate-trust diagnostic"
echo "Namespace: $NS"
echo "Target:    ${OKTA_HOST}:${OKTA_PORT}"
echo "Read-only: this script does not modify cluster resources"
echo "============================================================"

echo "=== 1. Locate a running Kafka pod ==="
POD="$(oc -n "$NS" get pods \
  -l app.kubernetes.io/name=kafka \
  --field-selector=status.phase=Running \
  -o jsonpath='{.items[0].metadata.name}')"

if [[ -z "$POD" ]]; then
  echo "FATAL: No running Kafka pod found in namespace $NS"
  exit 1
fi

echo "Kafka pod: $POD"

echo "=== 2. Confirm PID 1 JVM truststore arguments ==="
JVM_TRUST_OUTPUT="$(oc -n "$NS" exec "$POD" -c kafka -- sh -c \
  'tr "\000" "\n" </proc/1/cmdline | grep -E "^-Djavax\.net\.ssl\.trustStore(=|Password=|Type=)"' || true)"

printf '%s\n' "$JVM_TRUST_OUTPUT"

for expected in \
  "-Djavax.net.ssl.trustStore=$TRUSTSTORE" \
  "-Djavax.net.ssl.trustStorePassword=$TRUSTSTORE_PASSWORD" \
  "-Djavax.net.ssl.trustStoreType=PKCS12"
do
  if ! grep -Fqx -- "$expected" <<<"$JVM_TRUST_OUTPUT"; then
    echo "FATAL: Missing JVM argument: $expected"
    exit 1
  fi
done

echo "PASS: Kafka PID 1 has the required JVM truststore arguments"

echo "=== 3. Confirm mounted truststore ==="
oc -n "$NS" exec "$POD" -c kafka -- sh -c \
  "test -r '$TRUSTSTORE' && ls -l '$TRUSTSTORE' && sha256sum '$TRUSTSTORE'"

echo "PASS: $TRUSTSTORE exists and is readable"

echo "=== 4. Verify the PKCS12 password and show relevant trust anchors ==="
TRUSTSTORE_LIST="$(oc -n "$NS" exec "$POD" -c kafka -- \
  keytool -list -v \
    -keystore "$TRUSTSTORE" \
    -storetype PKCS12 \
    -storepass "$TRUSTSTORE_PASSWORD")"

ENTRY_COUNT="$(grep -c '^Alias name:' <<<"$TRUSTSTORE_LIST" || true)"
echo "Truststore entry count: $ENTRY_COUNT"

echo "Relevant FCB/Zscaler entries:"
RELEVANT_ENTRIES="$(grep -Ei 'Alias name:|Owner:|Issuer:|SHA256:' <<<"$TRUSTSTORE_LIST" | \
  grep -Ei 'fcb|first.?citizens|zscaler' || true)"

if [[ -n "$RELEVANT_ENTRIES" ]]; then
  printf '%s\n' "$RELEVANT_ENTRIES"
else
  echo "WARNING: No FCB- or Zscaler-named certificate was found"
fi

echo "PASS: keytool opened the PKCS12 truststore successfully"

echo "=== 5. Capture the certificate chain presented to Kafka ==="
set +e
PRESENTED_CHAIN="$(oc -n "$NS" exec "$POD" -c kafka -- \
  keytool -printcert \
    -sslserver "${OKTA_HOST}:${OKTA_PORT}" \
    -v 2>&1)"
CHAIN_RC=$?
set -e

printf '%s\n' "$PRESENTED_CHAIN"

if [[ $CHAIN_RC -ne 0 ]]; then
  echo "WARNING: keytool returned exit code $CHAIN_RC while inspecting the endpoint"
fi

if ! grep -Eq 'Owner:|Subject:' <<<"$PRESENTED_CHAIN"; then
  echo "FATAL: The certificate presented by ${OKTA_HOST}:${OKTA_PORT} was not captured"
  exit 1
fi

echo "PASS: Presented certificate information was captured"

echo "=== 6. Compare presented issuers with named trust anchors ==="
echo "Presented certificate subjects and issuers:"
grep -E 'Owner:|Subject:|Issuer:|SHA256:' <<<"$PRESENTED_CHAIN" || true

if grep -Eqi 'zscaler' <<<"$PRESENTED_CHAIN"; then
  echo "OBSERVATION: Kafka receives a Zscaler-issued/intercepted certificate"
  if grep -Eqi 'zscaler' <<<"$TRUSTSTORE_LIST"; then
    echo "PASS: The truststore contains a Zscaler-named certificate"
  else
    echo "FAIL: The presented chain references Zscaler, but the truststore has no Zscaler-named certificate"
  fi
else
  echo "OBSERVATION: The captured chain contains no certificate named Zscaler"
fi

echo "=== 7. Recent MDS JWKS and PKIX evidence ==="
oc -n "$NS" logs "$POD" -c kafka --since=15m 2>&1 | \
  grep -Ei -C 12 \
    'HttpsJwks|resolveKey|PKIX|certificate_unknown|SSLHandshakeException|SunCertPathBuilderException' || true

echo "============================================================"
echo "Diagnostic collection completed."
echo "Send the complete pipeline output for certificate-chain comparison."
echo "============================================================"