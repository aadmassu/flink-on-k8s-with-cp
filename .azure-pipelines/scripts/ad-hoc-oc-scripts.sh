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
