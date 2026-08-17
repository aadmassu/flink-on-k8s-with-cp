#!/usr/bin/env bash
set -uo pipefail

# Read-only Control Center OIDC/PKIX diagnostic.
# Called by validate-confluent-platform.yaml with the namespace as argument.
# No jq/PyYAML. Does not print Secret values, tokens, IDs, or passwords.

NAMESPACE="${1:-${OC_NS:-dah-flink-dev}}"
OKTA_HOST="${OKTA_HOST:-myapps.firstcitizens.com}"
OKTA_PORT="${OKTA_PORT:-443}"
C3_POD="${C3_POD:-controlcenter-0}"
TRUST_CONFIGMAP="${TRUST_CONFIGMAP:-fcb-trust-bundle}"
TRUSTSTORE_KEY="${TRUSTSTORE_KEY:-bundle.jks}"
TRUSTSTORE_PASSWORD="${TRUSTSTORE_PASSWORD:-changeit}"
FAILED=0
WORK_DIR="$(mktemp -d "${AGENT_TEMPDIRECTORY:-/tmp}/c3-pkix.XXXXXX")"
cleanup() { rm -rf "$WORK_DIR"; }
trap cleanup EXIT

section() { printf '\n============================================================\n%s\n============================================================\n' "$*"; }
pass() { echo "PASS: $*"; }
warn() { echo "WARN: $*"; }
fail() { echo "FAIL: $*" >&2; FAILED=1; }

command -v oc >/dev/null 2>&1 || { echo "FATAL: oc is unavailable" >&2; exit 1; }
command -v base64 >/dev/null 2>&1 || { echo "FATAL: base64 is unavailable" >&2; exit 1; }
oc whoami >/dev/null 2>&1 || { echo "FATAL: not logged into OpenShift" >&2; exit 1; }
oc get namespace "$NAMESPACE" >/dev/null 2>&1 || { echo "FATAL: namespace $NAMESPACE is inaccessible" >&2; exit 1; }

section "1. Workload and route state"
echo "Namespace: $NAMESPACE"
echo "OIDC host: $OKTA_HOST:$OKTA_PORT"
oc -n "$NAMESPACE" get pods -o wide
echo
oc -n "$NAMESPACE" get controlcenter controlcenter -o custom-columns='NAME:.metadata.name,READY:.status.conditions[?(@.type=="platform.confluent.io/cluster-ready")].status,REASON:.status.conditions[?(@.type=="platform.confluent.io/cluster-ready")].reason' 2>/dev/null || true
oc -n "$NAMESPACE" get kafka kafka -o custom-columns='NAME:.metadata.name,READY:.status.conditions[?(@.type=="platform.confluent.io/cluster-ready")].status,REASON:.status.conditions[?(@.type=="platform.confluent.io/cluster-ready")].reason' 2>/dev/null || true
echo
oc -n "$NAMESPACE" get route -o custom-columns='NAME:.metadata.name,HOST:.spec.host,TERMINATION:.spec.tls.termination,TARGET:.spec.to.name,PORT:.spec.port.targetPort,ADMITTED:.status.ingress[0].conditions[?(@.type=="Admitted")].status' 2>/dev/null || true
oc -n "$NAMESPACE" get pod "$C3_POD" >/dev/null 2>&1 || fail "Pod/$C3_POD does not exist"

section "2. Correlate the callback failure in component logs"
echo "Control Center matches from the last 30 minutes:"
if oc -n "$NAMESPACE" get pod "$C3_POD" >/dev/null 2>&1; then
  C3_MATCHES="$(oc -n "$NAMESPACE" logs "$C3_POD" --all-containers=true --since=30m 2>&1 | grep -Ei 'PKIX|SSLHandshake|certificate_unknown|certification path|oidc|authorization-code|token endpoint' || true)"
  if [ -n "$C3_MATCHES" ]; then
    printf '%s\n' "$C3_MATCHES" | tail -n 120
    printf '%s\n' "$C3_MATCHES" | grep -Eqi 'PKIX|SSLHandshake|certificate_unknown|certification path' && fail "Control Center logged an outbound TLS trust failure"
  else
    warn "No matching Control Center log lines found"
  fi
fi

echo
echo "Kafka/MDS matches from the last 30 minutes:"
KAFKA_MATCH_FOUND=0
for pod in $(oc -n "$NAMESPACE" get pods -o name 2>/dev/null | sed -n 's#^pod/\(kafka-[0-9][0-9]*\)$#\1#p'); do
  MATCHES="$(oc -n "$NAMESPACE" logs "$pod" --all-containers=true --since=30m 2>&1 | grep -Ei 'PKIX|SSLHandshake|certificate_unknown|certification path|oidc|token endpoint' || true)"
  if [ -n "$MATCHES" ]; then
    KAFKA_MATCH_FOUND=1
    echo "--- $pod ---"
    printf '%s\n' "$MATCHES" | tail -n 80
  fi
done
[ "$KAFKA_MATCH_FOUND" -eq 1 ] || warn "No matching Kafka/MDS log lines found"

section "3. Trust configuration (no credentials)"
echo "Control Center JVM overrides and mounted volumes:"
oc -n "$NAMESPACE" get controlcenter controlcenter -o jsonpath='{range .spec.configOverrides.jvm[*]}{.}{"\n"}{end}{range .spec.mountedVolumes.volumes[*]}volume={.name}{" configMap="}{.configMap.name}{" secret="}{.secret.secretName}{"\n"}{end}' 2>/dev/null || true
echo
echo "Kafka JVM overrides and mounted volumes:"
oc -n "$NAMESPACE" get kafka kafka -o jsonpath='{range .spec.configOverrides.jvm[*]}{.}{"\n"}{end}{range .spec.mountedVolumes.volumes[*]}volume={.name}{" configMap="}{.configMap.name}{" secret="}{.secret.secretName}{"\n"}{end}' 2>/dev/null || true

if oc -n "$NAMESPACE" get configmap "$TRUST_CONFIGMAP" >/dev/null 2>&1; then
  pass "ConfigMap/$TRUST_CONFIGMAP exists"
  oc -n "$NAMESPACE" get configmap "$TRUST_CONFIGMAP" -o jsonpath='{range $k,$v := .binaryData}{"binaryData key: "}{$k}{"\n"}{end}{range $k,$v := .data}{"data key: "}{$k}{"\n"}{end}'
else
  fail "ConfigMap/$TRUST_CONFIGMAP does not exist"
fi

section "3.5. Extract complete Okta certificate chain"
echo "Extracting certificate chain from $OKTA_HOST:$OKTA_PORT..."
OKTA_CHAIN="$WORK_DIR/okta-chain.pem"
if openssl s_client -connect "$OKTA_HOST:$OKTA_PORT" -showcerts </dev/null 2>/dev/null | sed -ne '/-BEGIN CERTIFICATE-/,/-END CERTIFICATE-/p' > "$OKTA_CHAIN"; then
  CERT_COUNT=$(grep -c "BEGIN CERTIFICATE" "$OKTA_CHAIN")
  echo "Found $CERT_COUNT certificate(s) in chain"
  if [ "$CERT_COUNT" -lt 2 ]; then
    warn "Chain may be incomplete (expected at least 2: leaf + intermediate/root)"
  else
    pass "Complete certificate chain extracted ($CERT_COUNT certs)"
  fi
  echo ""
  echo "Certificate chain (leaf to root):"
  openssl crl2pkcs7 -nocrl -certfile "$OKTA_CHAIN" 2>/dev/null | openssl pkcs7 -print_certs -noout 2>/dev/null | grep -E '^(Subject:|Issuer:)' | head -n 20
else
  fail "Could not extract certificate chain from $OKTA_HOST:$OKTA_PORT"
fi

section "4. Inspect the custom JKS trust bundle"
JKS_FILE="$WORK_DIR/$TRUSTSTORE_KEY"
JKS_B64="$(oc -n "$NAMESPACE" get configmap "$TRUST_CONFIGMAP" -o "jsonpath={.binaryData.${TRUSTSTORE_KEY//./\\.}}" 2>/dev/null || true)"
if [ -z "$JKS_B64" ]; then
  JKS_B64="$(oc -n "$NAMESPACE" get configmap "$TRUST_CONFIGMAP" -o "jsonpath={.data.${TRUSTSTORE_KEY//./\\.}}" 2>/dev/null || true)"
fi
if [ -z "$JKS_B64" ]; then
  fail "ConfigMap/$TRUST_CONFIGMAP does not contain $TRUSTSTORE_KEY"
elif ! printf '%s' "$JKS_B64" | base64 --decode >"$JKS_FILE" 2>/dev/null; then
  fail "Could not decode $TRUSTSTORE_KEY"
elif command -v keytool >/dev/null 2>&1; then
  echo "Aliases and certificate owners only:"
  if keytool -list -v -keystore "$JKS_FILE" -storepass "$TRUSTSTORE_PASSWORD" 2>&1 | grep -E '^(Alias name:|Owner:|Issuer:|Valid from:|SHA256:)' | head -n 300; then
    pass "Build-agent keytool opened the custom truststore"
  else
    fail "Build-agent keytool could not open the custom truststore"
  fi
else
  warn "Build agent has no keytool; pod-side checks continue"
fi

section "5. Test Okta TLS from Control Center and Kafka"
test_pod_tls() {
  pod="$1"
  echo
  echo "--- $pod -> $OKTA_HOST:$OKTA_PORT ---"
  if ! oc -n "$NAMESPACE" get pod "$pod" >/dev/null 2>&1; then
    fail "Pod/$pod does not exist"
    return
  fi

  if oc -n "$NAMESPACE" exec "$pod" -- sh -c 'command -v keytool >/dev/null 2>&1'; then
    echo "Certificate presented inside this pod (public certificate only):"
    oc -n "$NAMESPACE" exec "$pod" -- sh -c "keytool -printcert -sslserver '$OKTA_HOST:$OKTA_PORT' -rfc 2>&1" | sed -n '/BEGIN CERTIFICATE/,/END CERTIFICATE/p' | head -n 80 || true
    echo "Keytool connection result:"
    if oc -n "$NAMESPACE" exec "$pod" -- sh -c "keytool -printcert -sslserver '$OKTA_HOST:$OKTA_PORT' >/tmp/okta-keytool.out 2>&1; rc=\$?; tail -n 20 /tmp/okta-keytool.out; rm -f /tmp/okta-keytool.out; exit \$rc"; then
      pass "$pod can reach the Okta TLS endpoint with keytool"
    else
      fail "$pod keytool could not complete the Okta TLS connection"
    fi
  else
    warn "$pod has no keytool"
  fi

  if oc -n "$NAMESPACE" exec "$pod" -- sh -c 'command -v curl >/dev/null 2>&1'; then
    echo "OIDC discovery request (no client credentials):"
    if oc -n "$NAMESPACE" exec "$pod" -- sh -c "curl -sS --connect-timeout 10 --max-time 30 -o /dev/null -w 'HTTP %{http_code}; peer verify=%{ssl_verify_result}\\n' 'https://$OKTA_HOST/oauth2/default/.well-known/openid-configuration'"; then
      pass "$pod trusts Okta using curl's trust source"
    else
      fail "$pod curl does not trust or cannot reach Okta"
    fi
  else
    warn "$pod has no curl"
  fi

  echo "Truststore files visible in the pod:"
  oc -n "$NAMESPACE" exec "$pod" -- sh -c 'for f in /var/ssl/truststore/bundle.jks /mnt/sslcerts/truststore.jks /etc/ssl/certs/java/cacerts "$JAVA_HOME/lib/security/cacerts"; do [ -f "$f" ] && ls -l "$f"; done' 2>/dev/null || true
  if oc -n "$NAMESPACE" exec "$pod" -- sh -c '[ -f /var/ssl/truststore/bundle.jks ] && command -v keytool >/dev/null 2>&1'; then
    echo "Custom JKS aliases and certificate owners:"
    oc -n "$NAMESPACE" exec "$pod" -- sh -c "keytool -list -v -keystore /var/ssl/truststore/bundle.jks -storepass '$TRUSTSTORE_PASSWORD' 2>&1" | grep -E '^(Alias name:|Owner:|Issuer:|Valid from:|SHA256:)' | head -n 300 || fail "$pod could not inspect the custom JKS"
  fi
}

test_pod_tls "$C3_POD"
FIRST_KAFKA_POD="$(oc -n "$NAMESPACE" get pods -o name 2>/dev/null | sed -n 's#^pod/\(kafka-[0-9][0-9]*\)$#\1#p' | head -n 1)"
if [ -n "$FIRST_KAFKA_POD" ]; then
  test_pod_tls "$FIRST_KAFKA_POD"
else
  fail "No Kafka broker pod found"
fi

section "6. Relevant recent events"
oc -n "$NAMESPACE" get events --sort-by=.lastTimestamp 2>/dev/null | tail -n 80 || true

section "7. Import complete certificate chain into JKS truststore"
echo "Next steps to fix the PKIX path building error:"
cat <<'EOF'

1. If section 3.5 shows "Chain may be incomplete", get the full chain locally:

   openssl s_client -connect myapps.firstcitizens.com:443 -showcerts </dev/null 2>/dev/null | sed -ne '/-BEGIN CERTIFICATE-/,/-END CERTIFICATE-/p' > okta-chain.pem

2. Import the complete chain into the JKS:

   keytool -import -alias okta-chain -file okta-chain.pem -keystore bundle.jks -storepass changeit -noprompt

3. Update the fcb-trust-bundle ConfigMap with the new bundle.jks:

   oc -n dah-flink-dev create configmap fcb-trust-bundle --from-file=bundle.jks=./bundle.jks --dry-run=client -o yaml | oc apply -f -

4. Restart Control Center to pick up the updated truststore:

   oc -n dah-flink-dev delete pod controlcenter-0
   oc -n dah-flink-dev wait pod/controlcenter-0 --for=condition=Ready --timeout=10m

5. Test OIDC SSO (the real acceptance test):

   - Log into Control Center UI: https://controlcenter.apps.dv.ocp.fcbint.net
   - Click "Sign In with Single Sign-On"
   - If login succeeds with no PKIX exception, the truststore is fixed
   - Check logs: oc -n dah-flink-dev logs controlcenter-0 -c controlcenter --since=5m

If still seeing PKIX errors:
   - Verify all intermediates are in okta-chain.pem (should have leaf + 1+ intermediate + root)
   - Verify the JKS was updated: keytool -list -keystore bundle.jks -storepass changeit
EOF

section "Interpretation"
cat <<'EOF'
The authorization code in the browser callback proves the redirect URI and
user assignment now work. PKIX path building failed means the JVM performing
the code-for-token exchange does not trust the certificate chain it sees for
the Okta host. Repair the trust bundle of whichever component logs the error.
It must contain the full chain presented inside the cluster, including an FCB
TLS-inspection root/intermediate when applicable. Do not disable verification
and do not use curl -k.
EOF

if [ "$FAILED" -ne 0 ]; then
  echo "RESULT: Diagnostic failures found; review the output above."
  exit 1
fi
echo "RESULT: No failure detected by these checks."
