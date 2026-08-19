#!/usr/bin/env bash
set -u

NS="dah-flink-dev"
HOST="myapps.firstcitizens.com"
STORE="/var/ssl/truststore/bundle.p12"

echo "=== Certificate actually presented to Kafka/MDS ==="
oc -n "$NS" exec kafka-0 -c kafka -- \
  keytool -printcert -sslserver "${HOST}:443" -v 2>&1 |
  grep -E 'Owner:|Issuer:|Serial number:|SHA256:|Valid from:'

echo
echo "=== Certificate actually presented to Control Center ==="
oc -n "$NS" exec controlcenter-0 -c controlcenter -- \
  keytool -printcert -sslserver "${HOST}:443" -v 2>&1 |
  grep -E 'Owner:|Issuer:|Serial number:|SHA256:|Valid from:'

echo
echo "=== Search current platform truststore for likely issuer ==="
oc -n "$NS" exec kafka-0 -c kafka -- \
  keytool -list -v \
    -keystore "$STORE" \
    -storetype PKCS12 \
    -storepass changeit 2>&1 |
  grep -Ei 'Alias name:|Owner:|Issuer:' |
  grep -Ei 'zscaler|first citizens|fcb root|entrust|digicert' || true