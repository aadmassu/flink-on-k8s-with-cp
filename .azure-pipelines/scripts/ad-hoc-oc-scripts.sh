#!/usr/bin/env bash
set -u

NS="dah-flink-dev"
STORE="/var/ssl/truststore/bundle.p12"
PASSWORD="changeit"

echo "=== 1. Validate the actual Kafka/MDS PKCS12 truststore ==="
oc -n "$NS" exec kafka-0 -c kafka -- \
  keytool -list -v \
  -keystore "$STORE" \
  -storetype PKCS12 \
  -storepass "$PASSWORD" 2>&1 |
  grep -E 'Your keystore contains|Alias name:|Owner:|Issuer:|SHA256:' ||
  echo "FAIL: unable to inspect $STORE"

echo
echo "=== 2. Kafka JVM truststore arguments ==="
oc -n "$NS" exec kafka-0 -c kafka -- sh -c \
  'tr "\000" " " </proc/1/cmdline |
   grep -o -- "-Djavax.net.ssl.trustStore[^ ]*\\|-Djavax.net.ssl.trustStorePassword[^ ]*\\|-Djavax.net.ssl.trustStoreType[^ ]*"'

echo
echo "=== 3. Control Center JVM truststore arguments ==="
oc -n "$NS" exec controlcenter-0 -c controlcenter -- sh -c \
  'tr "\000" " " </proc/1/cmdline |
   grep -o -- "-Djavax.net.ssl.trustStore[^ ]*\\|-Djavax.net.ssl.trustStorePassword[^ ]*\\|-Djavax.net.ssl.trustStoreType[^ ]*"'

echo
echo "=== 4. Confirm truststore files exist ==="
oc -n "$NS" exec kafka-0 -c kafka -- ls -l "$STORE"
oc -n "$NS" exec controlcenter-0 -c controlcenter -- ls -l "$STORE"

echo
echo "=== 5. Actual Control Center callback errors ==="
oc -n "$NS" logs controlcenter-0 -c controlcenter --since=20m |
  grep -Ei -C 15 \
  'authorization-code|oidc|oauth|callback|PKIX|SSLHandshake|certificate_unknown|ProcessingException|SunCertPath' ||
  echo "No matching C3 entries captured."

echo
echo "=== 6. Actual Kafka/MDS callback errors ==="
for pod in kafka-0 kafka-1 kafka-2; do
  echo "--- $pod ---"
  oc -n "$NS" logs "$pod" -c kafka --since=20m |
    grep -Ei -C 20 \
    'authorization-code|oidc|oauth|token.base|PKIX|SSLHandshake|certificate_unknown|ProcessingException|SunCertPath' ||
    echo "No matching MDS entries captured from $pod."
done

echo
echo "=== 7. Rendered MDS SSO and truststore properties ==="
oc -n "$NS" exec kafka-0 -c kafka -- sh -c \
  'grep -Ei "confluent\\.oidc\\.|confluent\\.metadata\\.ssl\\.truststore" /opt/confluentinc/etc/kafka/kafka.properties |
   sed -E "s/(client\\.secret=).*/\\1***REDACTED***/I"'