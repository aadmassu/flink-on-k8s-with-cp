#!/usr/bin/env bash

set -euo pipefail

NS="dah-flink-dev"
C3_POD="controlcenter-0"
C3_CONTAINER="controlcenter"
TRUSTSTORE="/var/ssl/truststore/bundle.p12"

echo "=== 1. Wait for Control Center ==="

oc -n "$NS" wait controlcenter/controlcenter \
  --for=condition=platform.confluent.io/cluster-ready=True \
  --timeout=15m

oc -n "$NS" wait pod/"$C3_POD" \
  --for=condition=Ready \
  --timeout=15m

echo "=== 2. Confirm rendered REST server and client truststore properties ==="

RENDERED_CONFIG="$(
  oc -n "$NS" exec "$C3_POD" -c "$C3_CONTAINER" -- sh -c \
    'grep -R -h -E "^confluent\.controlcenter\.rest(\.client)?\.ssl\." /opt/confluentinc/etc 2>/dev/null' \
    || true
)"

printf '%s\n' "$RENDERED_CONFIG"

require_rendered_property() {
  expected="$1"

  if printf '%s\n' "$RENDERED_CONFIG" | grep -Fqx "$expected"; then
    echo "PASS: $expected"
  else
    echo "FATAL: Missing rendered property: $expected"
    exit 1
  fi
}

require_rendered_property \
  "confluent.controlcenter.rest.ssl.truststore.location=${TRUSTSTORE}"
require_rendered_property \
  "confluent.controlcenter.rest.ssl.truststore.password=changeit"
require_rendered_property \
  "confluent.controlcenter.rest.ssl.truststore.type=PKCS12"

require_rendered_property \
  "confluent.controlcenter.rest.client.ssl.truststore.location=${TRUSTSTORE}"
require_rendered_property \
  "confluent.controlcenter.rest.client.ssl.truststore.password=changeit"
require_rendered_property \
  "confluent.controlcenter.rest.client.ssl.truststore.type=PKCS12"
require_rendered_property \
  "confluent.controlcenter.rest.client.ssl.endpoint.identification.algorithm=https"

echo "=== 3. Confirm JVM truststore ==="

JVM_ARGS="$(
  oc -n "$NS" exec "$C3_POD" -c "$C3_CONTAINER" -- sh -c \
    'tr "\000" "\n" </proc/1/cmdline'
)"

printf '%s\n' "$JVM_ARGS" |
  grep -E 'javax\.net\.ssl\.trustStore(=|Password=|Type=)'

printf '%s\n' "$JVM_ARGS" |
  grep -Fqx -- "-Djavax.net.ssl.trustStore=${TRUSTSTORE}" || {
    echo "FATAL: JVM is not using ${TRUSTSTORE}"
    exit 1
  }

printf '%s\n' "$JVM_ARGS" |
  grep -Fqx -- "-Djavax.net.ssl.trustStoreType=PKCS12" || {
    echo "FATAL: JVM truststore type is not PKCS12"
    exit 1
  }

echo "=== 4. Confirm effective outbound REST-client truststore ==="

C3_LOGS="$(
  oc -n "$NS" logs "$C3_POD" -c "$C3_CONTAINER" --since=30m
)"

if printf '%s\n' "$C3_LOGS" |
  grep -Eq 'client\.ssl\.truststore\.location[[:space:]]*=[[:space:]]*/var/ssl/truststore/bundle\.p12'; then
  echo "PASS: client.ssl.truststore.location = ${TRUSTSTORE}"
else
  echo "FATAL: Effective client.ssl.truststore.location is not ${TRUSTSTORE}"
  exit 1
fi

if printf '%s\n' "$C3_LOGS" |
  grep -Eq 'client\.ssl\.truststore\.type[[:space:]]*=[[:space:]]*PKCS12'; then
  echo "PASS: client.ssl.truststore.type = PKCS12"
else
  echo "FATAL: Effective client.ssl.truststore.type is not PKCS12"
  exit 1
fi

echo "=== 5. Recent C3 SSO and TLS errors ==="

printf '%s\n' "$C3_LOGS" |
  grep -Ei -C 10 \
    'PKIX|SSLHandshakeException|certificate_unknown|ProcessingException|oidc|authorization-code' \
  || true

echo "PASS: Control Center outbound REST-client truststore is correctly configured."
echo "PASS: Control Center is ready for another SSO test."