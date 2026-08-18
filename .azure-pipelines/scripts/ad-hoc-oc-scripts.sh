#!/usr/bin/env bash
set -uo pipefail

# Focused truststore validation for kafka-tls-cfk and CFK-generated PKCS12.
# Outputs only data needed to verify CA chain completeness and mount paths.

NAMESPACE="${1:-${NAMESPACE:-dah-flink-dev}}"

section() {
  printf '\n%s\n%s\n%s\n' \
    '================================================================================' \
    "$1" \
    '================================================================================'
}

main() {
  section "Truststore Validation: kafka-tls-cfk and CFK-generated PKCS12"

  section "1. kafka-tls-cfk Secret — data keys"
  oc -n "$NAMESPACE" get secret kafka-tls-cfk -o jsonpath='{range .data}{.key}{"\n"}{end}' 2>/dev/null || echo "[NOT FOUND]"

  section "2. Count and list CAs in kafka-tls-cfk ca.crt"
  WORK_DIR=$(mktemp -d)
  trap "rm -rf $WORK_DIR" RETURN

  if oc -n "$NAMESPACE" get secret kafka-tls-cfk -o jsonpath='{.data.ca\.crt}' 2>/dev/null | base64 -d > "$WORK_DIR/ca.crt" 2>/dev/null; then
    NUM_CERTS=$(grep -c "BEGIN CERTIFICATE" "$WORK_DIR/ca.crt" 2>/dev/null || echo 0)
    printf 'Total certificates: %d\n' "$NUM_CERTS"
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
    echo "[FAILED TO EXTRACT ca.crt]"
  fi

  section "3. CFK-generated PKCS12 secrets"
  oc -n "$NAMESPACE" get secret -o name 2>/dev/null | grep -iE 'pkcs12|keystore|truststore' || echo "[NONE FOUND]"

  section "4. Pod volumes in kafka-2"
  printf 'Volume name → Secret/ConfigMap\n'
  oc -n "$NAMESPACE" get pod kafka-2 -o jsonpath='{range .spec.volumes[*]}{.name}{"\t"}{.secret.secretName // .configMap.name}{"\n"}{end}' 2>/dev/null || echo "[FAILED]"

  section "5. Mounted filesystem paths (truststore/keystore) in kafka-2"
  oc -n "$NAMESPACE" exec kafka-2 -c kafka -- \
    find /mnt /var -type f \( -name '*truststore*' -o -name '*keystore*' -o -name 'jksPassword*' \) 2>/dev/null || echo "[NONE FOUND]"

  section "6. Container volume mounts for kafka-2"
  oc -n "$NAMESPACE" get pod kafka-2 \
    -o jsonpath='{range .spec.containers[?(@.name=="kafka")].volumeMounts[*]}{.name}{" → "}{.mountPath}{"\n"}{end}' 2>/dev/null || echo "[FAILED]"

  printf '\n[END]\n'
}

main
