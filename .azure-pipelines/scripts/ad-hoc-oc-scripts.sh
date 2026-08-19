#!/usr/bin/env bash
set -euo pipefail

NS="dah-flink-dev"
POD="$(oc -n "$NS" get pod -l app.kubernetes.io/name=kafka \
  -o jsonpath='{.items[0].metadata.name}')"

echo "=== Kafka pod: $POD ==="

echo "=== 1. JVM truststore arguments ==="
oc -n "$NS" exec "$POD" -c kafka -- sh -c \
  'tr "\000" "\n" </proc/1/cmdline |
   grep -E "javax.net.ssl.trustStore(=|Password=|Type=)"'

echo "=== 2. Truststore inventory ==="
oc -n "$NS" exec "$POD" -c kafka -- sh -c \
  'keytool -list -v \
    -keystore /var/ssl/truststore/bundle.p12 \
    -storetype PKCS12 \
    -storepass changeit |
   grep -E "Alias name:|Owner:|Issuer:|SHA256:"'

echo "=== 3. Certificate chain presented to Kafka ==="
oc -n "$NS" exec "$POD" -c kafka -- sh -c \
  'echo | openssl s_client \
    -connect myapps.firstcitizens.com:443 \
    -servername myapps.firstcitizens.com \
    -showcerts 2>&1' |
grep -E 'subject=|issuer=|BEGIN CERTIFICATE|END CERTIFICATE|Verify return code'

echo "=== 4. Validate using bundle.p12 converted to PEM ==="
oc -n "$NS" exec "$POD" -c kafka -- sh -c '
  tmpdir=$(mktemp -d)
  trap "rm -rf $tmpdir" EXIT

  keytool -importkeystore \
    -srckeystore /var/ssl/truststore/bundle.p12 \
    -srcstoretype PKCS12 \
    -srcstorepass changeit \
    -destkeystore "$tmpdir/bundle.p12" \
    -deststoretype PKCS12 \
    -deststorepass changeit >/dev/null 2>&1

  keytool -list \
    -keystore "$tmpdir/bundle.p12" \
    -storetype PKCS12 \
    -storepass changeit >/dev/null

  curl -sv \
    --connect-timeout 15 \
    https://myapps.firstcitizens.com/oauth2/default/v1/keys \
    -o /dev/null
'

echo "=== 5. Recent JWKS/PKIX evidence ==="
oc -n "$NS" logs "$POD" -c kafka --since=15m |
  grep -Ei -C 20 \
  'HttpsJwks|resolveKey|PKIX|certificate_unknown|SSLHandshakeException' ||
  true