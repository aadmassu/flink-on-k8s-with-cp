#!/usr/bin/env bash
set -uo pipefail

# JSSE+truststore diagnostic collector for Kafka/MDS OIDC PKIX failure.
# Prints all diagnostic output to pipeline log (no file generation).
# Prerequisites: kafka.yaml must have JSSE debugging enabled:
#   -Djavax.net.debug=ssl,handshake,trustmanager
#
# Run after enabling JSSE, then trigger ONE SSO attempt, then capture logs.

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
  section "=== COLLECTION START: $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="

  section "1. Source and deployed manifests"

  section "Live Kafka CR (oc get kafka kafka -o yaml)"
  run oc -n "$NAMESPACE" get kafka kafka -o yaml

  section "Live Control Center CR (oc get controlcenter controlcenter -o yaml)"
  run oc -n "$NAMESPACE" get controlcenter controlcenter -o yaml

  section "2. Kafka pod runtime configuration"

  for pod in kafka-0 kafka-1 kafka-2; do
    section "Pod manifest: $pod"
    run oc -n "$NAMESPACE" get pod "$pod" -o yaml

    section "Java command line: $pod (password redacted)"
    run oc -n "$NAMESPACE" exec "$pod" -c kafka -- sh -c \
      'tr "\000" " " </proc/1/cmdline' | \
      sed -E 's/(-Djavax\.net\.ssl\.trustStorePassword=)[^ ]*/\1[REDACTED]/g'

    section "Truststore SHA256: $pod"
    run oc -n "$NAMESPACE" exec "$pod" -c kafka -- \
      sha256sum /var/ssl/truststore/bundle.jks
  done

  section "3. Relevant generated Kafka properties"

  for pod in kafka-0 kafka-1 kafka-2; do
    section "Kafka properties from $pod (password redacted)"
    oc -n "$NAMESPACE" exec "$pod" -c kafka -- sh -c \
      'grep -Ein "oauth|oidc|mds|issuer|jwks|token|truststore|ssl" /opt/confluentinc/etc/kafka/kafka.properties 2>/dev/null || echo "[INFO] No matching properties found"' | \
      sed -E 's/((password|secret|token)[^=]*=)[^ ]*/\1[REDACTED]/I'
  done

  section "4. Truststore contents (keytool -list -v)"
  run oc -n "$NAMESPACE" exec kafka-0 -c kafka -- \
    keytool -list -v \
    -keystore /var/ssl/truststore/bundle.jks \
    -storetype PKCS12 \
    -storepass truststorepass

  section "5. ConfigMap c3-trust-bundle metadata (no base64 data)"
  oc -n "$NAMESPACE" get configmap c3-trust-bundle \
    -o jsonpath='name={.metadata.name}{"\n"}resourceVersion={.metadata.resourceVersion}{"\n"}created={.metadata.creationTimestamp}{"\n"}dataKeys={.data}{"\n"}binaryDataKeys={.binaryData}{"\n"}'

  section "6. Full Kafka logs (last 20min) with JSSE context — SENSITIVE"

  for pod in kafka-0 kafka-1 kafka-2; do
    section "Logs from $pod (code/state/Authorization redacted)"
    oc -n "$NAMESPACE" logs "$pod" -c kafka --since=20m 2>&1 | \
      sed -E 's/(code=)[^ &]*/\1[REDACTED]/g; s/(state=)[^ &]*/\1[REDACTED]/g; s/(client_secret=)[^ &]*/\1[REDACTED]/g; s/(Authorization: )[^ ]*/\1[REDACTED]/g'
  done

  section "7. Control Center logs (last 20min)"
  section "Logs from controlcenter-0"
  oc -n "$NAMESPACE" logs controlcenter-0 -c controlcenter --since=20m 2>&1

  section "8. Kafka CR description and events"
  run oc -n "$NAMESPACE" describe kafka kafka

  section "=== COLLECTION END ==="
}

main
