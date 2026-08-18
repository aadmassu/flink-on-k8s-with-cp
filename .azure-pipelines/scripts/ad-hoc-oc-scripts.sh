#!/usr/bin/env bash
set -uo pipefail

# Focused MDS OIDC troubleshooting diagnostics.
# Collects truststore validation, config verification, and error logs.
# Prints all output to pipeline log (no file generation).

NAMESPACE="${NAMESPACE:-dah-flink-dev}"

section() {
  printf '\n%s\n%s\n%s\n' \
    '================================================================================' \
    "$1" \
    '================================================================================'
}

run() {
  printf '\n$ %s\n' "$*"
  "$@" 2>&1 || printf '[WARN] Command exited with status %s\n' "$?"
}

main() {
  section "=== OIDC DIAGNOSTICS START: $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="

  section "1. Truststore validation"

  section "1a. Truststore file existence and permissions (kafka-0)"
  run oc -n "$NAMESPACE" exec kafka-0 -c kafka -- \
    ls -lh /var/ssl/truststore/bundle.jks

  section "1b. Truststore content — list certificates"
  run oc -n "$NAMESPACE" exec kafka-0 -c kafka -- \
    keytool -list \
    -keystore /var/ssl/truststore/bundle.jks \
    -storetype PKCS12 \
    -storepass truststorepass 2>&1

  section "1c. Truststore contains Okta CA? (grep for 'firstcitizens\\|okta')"
  run oc -n "$NAMESPACE" exec kafka-0 -c kafka -- \
    keytool -list -v \
    -keystore /var/ssl/truststore/bundle.jks \
    -storetype PKCS12 \
    -storepass truststorepass 2>&1 | grep -i "owner\|issuer" | grep -i "firstcitizens\|okta"

  section "1d. ConfigMap c3-trust-bundle metadata"
  run oc -n "$NAMESPACE" get configmap c3-trust-bundle -o jsonpath='name={.metadata.name}{"\n"}size={.data.bundle\.jks | length}{"\n"}created={.metadata.creationTimestamp}{"\n"}'

  section "1e. Inspect kafka-tls-cfk Secret and CFK-generated truststore"

  section "1e-i. kafka-tls-cfk Secret — list data keys"
  run oc -n "$NAMESPACE" get secret kafka-tls-cfk -o jsonpath='{range .data}{.key}{"\n"}{end}' 2>/dev/null || echo "[INFO] kafka-tls-cfk Secret not found"

  section "1e-ii. Extract and count certificates in kafka-tls-cfk ca.crt"
  WORK_DIR=$(mktemp -d)
  trap "rm -rf $WORK_DIR" RETURN
  if oc -n "$NAMESPACE" get secret kafka-tls-cfk -o jsonpath='{.data.ca\.crt}' 2>/dev/null | base64 -d > "$WORK_DIR/ca.crt" 2>/dev/null; then
    NUM_CERTS=$(grep -c "BEGIN CERTIFICATE" "$WORK_DIR/ca.crt" 2>/dev/null || echo 0)
    printf 'Number of certificates in kafka-tls-cfk ca.crt: %d\n' "$NUM_CERTS"
    printf '\nCertificate subjects:\n'
    awk '/-----BEGIN CERTIFICATE-----/{flag=1; next} /-----END CERTIFICATE-----/{flag=0} flag' "$WORK_DIR/ca.crt" | \
      while IFS= read -r line; do
        if [[ "$line" =~ ^[A-Za-z0-9+/]+=?$ ]]; then
          echo "$line"
        fi
      done | while read -r b64_data; do
        echo "$b64_data" | base64 -d 2>/dev/null | openssl x509 -noout -subject 2>/dev/null | sed 's/^/  /'
      done
  else
    echo "[INFO] Could not extract ca.crt from kafka-tls-cfk"
  fi

  section "1e-iii. Find CFK-generated PKCS12 secrets (truststore/keystore)"
  run oc -n "$NAMESPACE" get secret -o name | grep -iE 'pkcs12|keystore|truststore' || echo "[INFO] No PKCS12 secrets found"

  section "1e-iv. Mount paths in kafka-2 pod (TLS/truststore related)"
  run oc -n "$NAMESPACE" get pod kafka-2 -o jsonpath='{range .spec.volumes[*]}{.name}{"\t"}{.secret.secretName // .configMap.name}{"\n"}{end}' | grep -iE 'tls|kafka|cert' || echo "[INFO] No matching volumes"

  section "1e-v. Actual filesystem mount points in kafka-2 container"
  run oc -n "$NAMESPACE" exec kafka-2 -c kafka -- \
    find /mnt /var -type f \( -name '*truststore*' -o -name '*keystore*' -o -name 'jksPassword*' \) 2>/dev/null | head -20

  section "2. MDS OAuth provider configuration"

  section "2a. Kafka CR MDS provider settings (OAuth endpoints and TLS)"
  run oc -n "$NAMESPACE" get kafka kafka -o jsonpath='{.spec.services.mds.provider}' | head -100

  section "3. JVM arguments and properties"

  section "3a. Java command line truststore config (kafka-0, password redacted)"
  run oc -n "$NAMESPACE" exec kafka-0 -c kafka -- \
    sh -c 'tr "\000" " " </proc/1/cmdline' | \
    grep -o "\-Djavax.net.ssl.trustStore[^ ]*" || echo "[INFO] No JVM trustStore arg found"

  section "3b. Kafka generated server properties — truststore and oauth (password redacted)"
  run oc -n "$NAMESPACE" exec kafka-0 -c kafka -- \
    sh -c 'grep -i "truststore\|oauth.*endpoint" /opt/confluentinc/etc/kafka/kafka.properties 2>/dev/null | head -20' | \
    sed -E 's/([=:]\s*[^ ]*password[^ ]*=)[^ ]*/\1[REDACTED]/I'

  section "4. Error logs focusing on OIDC/OAuth failures"

  section "4a. Kafka logs — last 30min, errors and warnings only (sensitive data redacted)"
  run oc -n "$NAMESPACE" logs kafka-0 -c kafka --since=30m 2>&1 | \
    grep -i "error\|exception\|pkix\|oauth\|oidc\|token.*failed\|invalid.*cert" | \
    sed -E 's/(Authorization: )[^ ]*/\1[REDACTED]/g; s/(code=)[^ &]*/\1[REDACTED]/g' | \
    tail -50

  section "4b. Control Center logs — last 30min, OIDC/auth errors only"
  run oc -n "$NAMESPACE" logs controlcenter-0 -c controlcenter --since=30min 2>&1 | \
    grep -i "oauth\|oidc\|token\|pkix\|certificate\|auth.*failed\|error" | \
    tail -50

  section "5. Resource status"

  section "5a. Kafka CR status (conditions and ready state)"
  run oc -n "$NAMESPACE" get kafka kafka -o jsonpath='{.status}' | head -50

  section "5b. Control Center CR status"
  run oc -n "$NAMESPACE" get controlcenter controlcenter -o jsonpath='{.status}' | head -50

  section "=== OIDC DIAGNOSTICS END ==="
}

main
