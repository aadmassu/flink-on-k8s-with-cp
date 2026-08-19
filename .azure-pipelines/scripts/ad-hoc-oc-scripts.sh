#!/usr/bin/env bash
set -euo pipefail

NS="dah-flink-dev"
POD="$(oc -n "$NS" get pod -l app.kubernetes.io/name=kafka -o jsonpath='{.items[0].metadata.name}')"

echo "=== Kafka pod ==="
echo "$POD"

echo "=== PID 1 JVM truststore arguments ==="
oc -n "$NS" exec "$POD" -c kafka -- sh -c \
  'tr "\000" "\n" </proc/1/cmdline | grep -E "javax.net.ssl.trustStore(=|Password=|Type=)"' ||
  echo "FAIL: JVM truststore arguments are absent"

echo "=== Mounted bundle ==="
oc -n "$NS" exec "$POD" -c kafka -- sh -c \
  'ls -l /var/ssl/truststore/bundle.p12 && sha256sum /var/ssl/truststore/bundle.p12'

echo "=== Effective JVM system properties ==="
oc -n "$NS" exec "$POD" -c kafka -- sh -c \
  'jcmd 1 VM.system_properties 2>/dev/null | grep -E "^javax.net.ssl.trustStore" || true'

echo "=== Truststore selected during recent failures ==="
oc -n "$NS" logs "$POD" -c kafka --since=30m |
  grep -E -C 5 \
  'trustStore is:|PKIX path building failed|HttpsJwks|RbacApiApplication|certificate_unknown' |
  tail -n 300