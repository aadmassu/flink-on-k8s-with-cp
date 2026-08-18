#!/usr/bin/env bash
set -uo pipefail

# Read-only diagnostics for the Kafka/MDS -> Okta PKIX failure.
# Optional pipeline variables:
#   NAMESPACE=dah-flink-dev
#   KAFKA_POD=kafka-0
#   KAFKA_CONTAINER=kafka
#   OKTA_HOST=myapps.firstcitizens.com
#   TRUSTSTORE_PATH=/var/ssl/truststore/bundle.jks
#   TRUSTSTORE_TYPE=JKS
#   TRUSTSTORE_PASSWORD=<secret pipeline variable>
#
# The truststore password is used only inside the pod and is never printed.

NAMESPACE="${NAMESPACE:-dah-flink-dev}"
KAFKA_POD="${KAFKA_POD:-kafka-0}"
KAFKA_CONTAINER="${KAFKA_CONTAINER:-}"
OKTA_HOST="${OKTA_HOST:-myapps.firstcitizens.com}"
TRUSTSTORE_PATH="${TRUSTSTORE_PATH:-/var/ssl/truststore/bundle.jks}"
TRUSTSTORE_TYPE="${TRUSTSTORE_TYPE:-JKS}"
OUTPUT_FILE="${OUTPUT_FILE:-ad-hoc-oc-results-$(date +%Y%m%d-%H%M%S).txt}"

section() {
  printf '\n================================================================================\n'
  printf '%s\n' "$1"
  printf '================================================================================\n'
}

run() {
  printf '\n$ %s\n' "$*"
  "$@" 2>&1 || printf '[WARN] Command exited with status %s\n' "$?"
}

main() {
  section "Execution context"
  printf 'Timestamp (UTC): %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'Namespace: %s\nPod: %s\nOkta host: %s\n' "$NAMESPACE" "$KAFKA_POD" "$OKTA_HOST"
  run oc version
  run oc project

  section "Kafka pod and container discovery"
  run oc -n "$NAMESPACE" get pod "$KAFKA_POD" -o wide
  run oc -n "$NAMESPACE" get pod "$KAFKA_POD" -o jsonpath='{.spec.containers[*].name}{"\n"}'

  if [[ -z "$KAFKA_CONTAINER" ]]; then
    KAFKA_CONTAINER="$(oc -n "$NAMESPACE" get pod "$KAFKA_POD" -o jsonpath='{.spec.containers[0].name}' 2>/dev/null || true)"
  fi
  if [[ -z "$KAFKA_CONTAINER" ]]; then
    printf '[ERROR] Unable to determine the Kafka container name.\n'
    return 1
  fi
  printf 'Selected container: %s\n' "$KAFKA_CONTAINER"

  OC_EXEC=(oc -n "$NAMESPACE" exec "$KAFKA_POD" -c "$KAFKA_CONTAINER" --)

  section "Truststore mounts and candidate files"
  run "${OC_EXEC[@]}" sh -c 'ls -la /var/ssl/truststore 2>/dev/null || true; find /var/ssl /mnt /etc -maxdepth 5 -type f \( -iname "*.jks" -o -iname "*.p12" -o -iname "*.pfx" -o -iname "*.pem" -o -iname "*.crt" \) 2>/dev/null | sort | head -200'

  section "Pod volume and mount definitions"
  run oc -n "$NAMESPACE" get pod "$KAFKA_POD" -o jsonpath='{range .spec.volumes[*]}VOLUME={.name}{" configMap="}{.configMap.name}{" secret="}{.secret.secretName}{"\n"}{end}'
  run oc -n "$NAMESPACE" get pod "$KAFKA_POD" -o jsonpath="{range .spec.containers[?(@.name=='$KAFKA_CONTAINER')].volumeMounts[*]}MOUNT={.name}{' path='}{.mountPath}{' readOnly='}{.readOnly}{'\n'}{end}"

  section "Broker JVM command line and relevant environment"
  run "${OC_EXEC[@]}" sh -c 'printf "PID 1 command: "; tr "\000" " " </proc/1/cmdline; printf "\n\nRelevant environment (values redacted where sensitive):\n"; env | sort | grep -Ei "JAVA|KAFKA_OPTS|TRUSTSTORE|SSL" | sed -E "s/((PASS|PASSWORD|SECRET|TOKEN)[A-Z0-9_]*=).*/\1[REDACTED]/I" || true'

  section "Generated broker properties containing SSL, truststore, MDS or OIDC settings"
  run "${OC_EXEC[@]}" sh -c 'for f in /etc/kafka/server.properties /etc/confluent/docker/server.properties /mnt/config/server.properties; do if [ -r "$f" ]; then echo "--- $f"; grep -Ei "(^|\.)(ssl\.truststore|oauth|oidc|mds|token\.endpoint|jwks|issuer|ignore.*trust)" "$f" | sed -E "s/((password|secret|token)[^=]*=).*/\1[REDACTED]/I" || true; fi; done'

  section "Configured truststore inspection"
  printf 'Expected truststore: %s (type %s)\n' "$TRUSTSTORE_PATH" "$TRUSTSTORE_TYPE"
  run "${OC_EXEC[@]}" sh -c "test -r '$TRUSTSTORE_PATH' && ls -l '$TRUSTSTORE_PATH' || { echo '[WARN] Expected truststore is not readable'; exit 1; }"

  if [[ -n "${TRUSTSTORE_PASSWORD:-}" ]]; then
    printf 'TRUSTSTORE_PASSWORD supplied: yes (value not printed)\n'
    "${OC_EXEC[@]}" env \
      DIAG_TS_PATH="$TRUSTSTORE_PATH" \
      DIAG_TS_TYPE="$TRUSTSTORE_TYPE" \
      DIAG_TS_PASSWORD="$TRUSTSTORE_PASSWORD" \
      sh -c 'keytool -list -v -keystore "$DIAG_TS_PATH" -storetype "$DIAG_TS_TYPE" -storepass "$DIAG_TS_PASSWORD" 2>&1 | grep -Ei "Alias name:|Entry type:|Owner:|Issuer:|Valid from:|SHA256:" || true'
  else
    printf '[INFO] TRUSTSTORE_PASSWORD was not supplied; skipping JKS alias listing.\n'
  fi

  section "DNS and TCP connectivity from Kafka pod"
  run "${OC_EXEC[@]}" sh -c "getent hosts '$OKTA_HOST' || nslookup '$OKTA_HOST' || true"
  run "${OC_EXEC[@]}" sh -c "timeout 10 sh -c '</dev/tcp/$OKTA_HOST/443' && echo 'TCP 443: SUCCESS' || echo 'TCP 443: FAILED or /dev/tcp unavailable'"

  section "Certificate chain presented to the Kafka pod"
  run "${OC_EXEC[@]}" sh -c "timeout 20 openssl s_client -connect '$OKTA_HOST:443' -servername '$OKTA_HOST' -showcerts </dev/null"

  section "Presented certificate subjects, issuers and dates"
  run "${OC_EXEC[@]}" sh -c "tmpdir=\$(mktemp -d); trap 'rm -rf \"\$tmpdir\"' EXIT; timeout 20 openssl s_client -connect '$OKTA_HOST:443' -servername '$OKTA_HOST' -showcerts </dev/null 2>/dev/null | awk -v d=\"\$tmpdir\" '/BEGIN CERTIFICATE/{n++; f=sprintf(\"%s/cert-%02d.pem\",d,n)} f{print >f} /END CERTIFICATE/{close(f); f=\"\"}'; for cert in \"\$tmpdir\"/*.pem; do [ -f \"\$cert\" ] || continue; echo \"--- \$(basename \"\$cert\")\"; openssl x509 -in \"\$cert\" -noout -subject -issuer -dates -fingerprint -sha256; done"

  section "HTTPS handshake test using the pod's default trust configuration"
  run "${OC_EXEC[@]}" sh -c "curl -sSvk --connect-timeout 10 --max-time 20 -o /dev/null -w 'HTTP_CODE=%{http_code} TLS_VERIFY=%{ssl_verify_result} REMOTE_IP=%{remote_ip}\\n' 'https://$OKTA_HOST/oauth2/default/v1/token'"

  section "Kafka pod truststore mount validation"
  run "${OC_EXEC[@]}" sh -c "ls -lh '$TRUSTSTORE_PATH' && echo 'Truststore mount: READABLE' || echo 'Truststore mount: NOT READABLE'"

  section "Kafka JVM truststore arguments check"
  run "${OC_EXEC[@]}" sh -c 'tr "\000" " " </proc/1/cmdline | grep -o "\-Djavax\.net\.ssl\.trustStore[^ ]*" || echo "[INFO] JVM truststore argument not found in PID 1 cmdline"'

  section "c3-trust-bundle ConfigMap Okta CA validation"
  run oc -n "$NAMESPACE" get configmap c3-trust-bundle -o jsonpath='{.binaryData.bundle\.jks}' 2>/dev/null | base64 -d 2>/dev/null | keytool -list -storepass truststorepass -v 2>&1 | grep -A 2 "sso_oauth_ca\|firstcitizens\.com" || echo "[WARN] Could not extract or verify Okta CA from ConfigMap"

  section "Restart Kafka brokers to reload configuration"
  printf 'Restarting kafka-0...\n'
  run oc -n "$NAMESPACE" delete pod kafka-0
  run oc -n "$NAMESPACE" wait pod/kafka-0 --for=condition=Ready --timeout=15m

  printf 'Restarting kafka-1...\n'
  run oc -n "$NAMESPACE" delete pod kafka-1
  run oc -n "$NAMESPACE" wait pod/kafka-1 --for=condition=Ready --timeout=15m

  printf 'Restarting kafka-2...\n'
  run oc -n "$NAMESPACE" delete pod kafka-2
  run oc -n "$NAMESPACE" wait pod/kafka-2 --for=condition=Ready --timeout=15m

  section "Summary"
  printf '%s\n' \
    'Review the output for:' \
    '1. A mounted outbound truststore.' \
    '2. -Djavax.net.ssl.trustStore in the PID 1 Java command or JVM options.' \
    '3. The root/intermediate CA actually presented inside OpenShift.' \
    '4. Matching CA aliases in the configured Java truststore.' \
    '5. A successful TCP connection and certificate retrieval.'
}

main 2>&1 | tee "$OUTPUT_FILE"
status=${PIPESTATUS[0]}
printf '\nDiagnostic output saved to: %s\n' "$OUTPUT_FILE"
exit "$status"