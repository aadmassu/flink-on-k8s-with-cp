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

section "3.5. Verify running JVM truststore configuration (active pod state)"
echo "Checking if $C3_POD has the truststore properties in its active JVM cmdline:"
if oc -n "$NAMESPACE" get pod "$C3_POD" >/dev/null 2>&1; then
  JVM_CMDLINE="$(oc -n "$NAMESPACE" exec "$C3_POD" -c controlcenter -- sh -c 'tr "\000" " " </proc/1/cmdline; echo' 2>/dev/null || true)"
  if [ -z "$JVM_CMDLINE" ]; then
    warn "Could not read /proc/1/cmdline from $C3_POD (container may not allow exec)"
  else
    echo "JVM command line (truncated to truststore-related args):"
    echo "$JVM_CMDLINE" | tr ' ' '\n' | grep -i truststore || warn "No truststore properties found in cmdline"

    if echo "$JVM_CMDLINE" | grep -q -- '-Djavax.net.ssl.trustStore=/var/ssl/truststore/bundle.jks'; then
      pass "trustStore property IS ACTIVE in $C3_POD JVM"
    else
      warn "trustStore property NOT found in active JVM (pod may need restart)"
    fi
  fi

  echo
  echo "Verifying truststore is mounted and readable from $C3_POD:"
  if oc -n "$NAMESPACE" exec "$C3_POD" -c controlcenter -- sh -c 'ls -l /var/ssl/truststore/bundle.jks && test -r /var/ssl/truststore/bundle.jks' 2>/dev/null; then
    pass "Truststore is mounted and readable"
  else
    fail "Truststore not mounted or not readable at /var/ssl/truststore/bundle.jks"
  fi
else
  fail "Pod/$C3_POD does not exist or is not accessible"
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

section "7. Recovery guidance if truststore config is not active"
cat <<'EOF'
If section 3.5 shows:
  - "trustStore property NOT found in active JVM (pod may need restart)", OR
  - "Truststore not mounted or not readable"

Then restart Control Center:

  oc -n dah-flink-dev delete pod controlcenter-0

Wait for recovery (up to 10 minutes):

  oc -n dah-flink-dev wait pod/controlcenter-0 --for=condition=Ready --timeout=10m

After restart, verify logs for SSL/OIDC errors (last 10 minutes):

  oc -n dah-flink-dev logs controlcenter-0 -c controlcenter --since=10m | grep -Ei 'PKIX|SSLHandshake|certificate_unknown|oidc|authorization-code'

Real acceptance test: Log into Control Center UI with OIDC. No PKIX exception = truststore
is working. Do NOT use curl -v as proof; it tests OS truststore, not the JVM truststore.
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
