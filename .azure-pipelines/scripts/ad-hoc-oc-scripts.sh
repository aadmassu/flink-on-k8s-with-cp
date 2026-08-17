#!/usr/bin/env bash
set -uo pipefail

# Read-only Control Center OIDC truststore validation.
# Called by validate-confluent-platform.yaml as:
#   .azure-pipelines/scripts/ad-hoc-oc-scripts.sh "$OC_NS"
# No jq/Python required. No secrets, tokens, client IDs, or passwords printed.

NS="${1:-${OC_NS:-dah-flink-dev}}"
C3_POD="${C3_POD:-controlcenter-0}"
C3_CONTAINER="controlcenter"
CM_NAME="c3-trust-bundle"
CM_KEY="bundle.jks"
MOUNTED_STORE="/var/ssl/truststore/bundle.jks"
REFERENCE_STORE=".azure-pipelines/truststore-references/qa-reference.jks"
STORE_PASSWORD="truststorepass"
EXPECTED_SHA="8e2df54bb8070b07770896dfd1984c83302db6130bdb27cdca7bb44eb4014768"
FAILED=0
TMP_DIR="$(mktemp -d "${AGENT_TEMPDIRECTORY:-/tmp}/c3-trust.XXXXXX")"
LIVE_STORE="$TMP_DIR/live-c3-truststore.jks"
trap 'find "$TMP_DIR" -type f -delete 2>/dev/null || true; rmdir "$TMP_DIR" 2>/dev/null || true' EXIT

heading() { printf '\n=== %s ===\n' "$*"; }
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*" >&2; FAILED=1; }
fatal() { echo "FATAL: $*" >&2; exit 1; }

command -v oc >/dev/null 2>&1 || fatal "oc is unavailable"
command -v base64 >/dev/null 2>&1 || fatal "base64 is unavailable"
command -v sha256sum >/dev/null 2>&1 || fatal "sha256sum is unavailable"
command -v keytool >/dev/null 2>&1 || fatal "keytool is unavailable on the build agent"
oc whoami >/dev/null 2>&1 || fatal "not logged into OpenShift"
oc get namespace "$NS" >/dev/null 2>&1 || fatal "namespace $NS is inaccessible"

heading "Target"
echo "Namespace:  $NS"
echo "Pod:        $C3_POD"
echo "ConfigMap:  $CM_NAME"
echo "Reference:  $REFERENCE_STORE"

heading "Repository reference truststore"
[ -f "$REFERENCE_STORE" ] || fatal "reference truststore is missing: $REFERENCE_STORE"
REF_SHA="$(sha256sum "$REFERENCE_STORE" | awk '{print $1}')"
REF_TYPE="$(keytool -list -keystore "$REFERENCE_STORE" -storepass "$STORE_PASSWORD" 2>&1 | sed -n 's/^Keystore type: //p' | head -n 1)"
REF_COUNT="$(keytool -list -keystore "$REFERENCE_STORE" -storepass "$STORE_PASSWORD" 2>&1 | sed -n 's/^Your keystore contains \([0-9][0-9]*\) entr.*/\1/p' | head -n 1)"
echo "SHA-256:    $REF_SHA"
echo "Store type: ${REF_TYPE:-unknown}"
echo "Entries:    ${REF_COUNT:-unknown}"
[ "$REF_SHA" = "$EXPECTED_SHA" ] && pass "repository reference matches the reviewed file" || fail "repository reference hash differs from $EXPECTED_SHA"
echo "Required aliases and owners:"
keytool -list -v -keystore "$REFERENCE_STORE" -storepass "$STORE_PASSWORD" 2>&1 | grep -E '^(Alias name:|Owner:)' || true

heading "Live ConfigMap truststore"
oc -n "$NS" get configmap "$CM_NAME" >/dev/null 2>&1 || fatal "ConfigMap/$CM_NAME does not exist"
echo "ResourceVersion: $(oc -n "$NS" get configmap "$CM_NAME" -o jsonpath='{.metadata.resourceVersion}')"
echo "Created:         $(oc -n "$NS" get configmap "$CM_NAME" -o jsonpath='{.metadata.creationTimestamp}')"
ENCODED="$(oc -n "$NS" get configmap "$CM_NAME" -o 'jsonpath={.binaryData.bundle\.jks}' 2>/dev/null || true)"
[ -n "$ENCODED" ] || ENCODED="$(oc -n "$NS" get configmap "$CM_NAME" -o 'jsonpath={.data.bundle\.jks}' 2>/dev/null || true)"
[ -n "$ENCODED" ] || fatal "ConfigMap/$CM_NAME does not contain $CM_KEY"
printf '%s' "$ENCODED" | base64 --decode >"$LIVE_STORE" 2>/dev/null || fatal "could not decode $CM_NAME/$CM_KEY"

LIVE_SHA="$(sha256sum "$LIVE_STORE" | awk '{print $1}')"
LIVE_TYPE="$(keytool -list -keystore "$LIVE_STORE" -storepass "$STORE_PASSWORD" 2>&1 | sed -n 's/^Keystore type: //p' | head -n 1)"
LIVE_COUNT="$(keytool -list -keystore "$LIVE_STORE" -storepass "$STORE_PASSWORD" 2>&1 | sed -n 's/^Your keystore contains \([0-9][0-9]*\) entr.*/\1/p' | head -n 1)"
echo "SHA-256:    $LIVE_SHA"
echo "Store type: ${LIVE_TYPE:-unreadable}"
echo "Entries:    ${LIVE_COUNT:-unknown}"
if keytool -list -keystore "$LIVE_STORE" -storepass "$STORE_PASSWORD" >/dev/null 2>&1; then
  pass "live ConfigMap opens with password truststorepass"
else
  fail "live ConfigMap cannot be opened with password truststorepass"
fi
[ "$LIVE_SHA" = "$REF_SHA" ] && pass "live ConfigMap is byte-for-byte identical to repository reference" || fail "live ConfigMap differs from repository reference"

for required_owner in 'CN=FCB Root CA 1' 'CN=FCB Root CA 2' 'CN=FCB Issuing CA 1' 'CN=firstcitizens.com'; do
  if keytool -list -v -keystore "$LIVE_STORE" -storepass "$STORE_PASSWORD" 2>&1 | grep -Fq "Owner: $required_owner"; then
    pass "live ConfigMap contains $required_owner"
  else
    fail "live ConfigMap is missing $required_owner"
  fi
done

heading "Mounted truststore in the Control Center container"
oc -n "$NS" get pod "$C3_POD" >/dev/null 2>&1 || fatal "Pod/$C3_POD does not exist"
READY="$(oc -n "$NS" get pod "$C3_POD" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')"
echo "Pod Ready: $READY"
[ "$READY" = "True" ] || fail "Control Center pod is not Ready"

MOUNT_SHA="$(oc -n "$NS" exec "$C3_POD" -c "$C3_CONTAINER" -- sha256sum "$MOUNTED_STORE" 2>/dev/null | awk '{print $1}' || true)"
echo "Mounted SHA-256: ${MOUNT_SHA:-unavailable}"
[ -n "$MOUNT_SHA" ] || fail "cannot read $MOUNTED_STORE from container $C3_CONTAINER"
[ "$MOUNT_SHA" = "$LIVE_SHA" ] && pass "mounted truststore matches the live ConfigMap" || fail "mounted truststore differs from the live ConfigMap"

heading "Effective Control Center JVM arguments"
JVM_ARGS="$(oc -n "$NS" exec "$C3_POD" -c "$C3_CONTAINER" -- sh -c 'tr "\000" " " </proc/1/cmdline; echo' 2>/dev/null || true)"
printf '%s\n' "$JVM_ARGS" | sed -E 's/(-D[^ =]*(password|secret)[^ =]*=)[^ ]+/\1<redacted>/Ig'
for required_arg in \
  "-Djavax.net.ssl.trustStore=$MOUNTED_STORE" \
  "-Djavax.net.ssl.trustStorePassword=$STORE_PASSWORD"; do
  printf '%s' "$JVM_ARGS" | grep -Fq -- "$required_arg" && pass "JVM has ${required_arg%%=*}" || fail "JVM is missing ${required_arg%%=*}"
done

JVM_DECLARED_TYPE="$(printf '%s\n' "$JVM_ARGS" | sed -n 's/.*-Djavax.net.ssl.trustStoreType=\([^ ]*\).*/\1/p' | head -n 1)"
echo "JVM declared store type: ${JVM_DECLARED_TYPE:-not set}"
echo "Actual reference type:   ${REF_TYPE:-unknown}"
if [ -n "$JVM_DECLARED_TYPE" ] && [ "$JVM_DECLARED_TYPE" != "$REF_TYPE" ]; then
  fail "JVM declares $JVM_DECLARED_TYPE but the truststore is $REF_TYPE"
elif [ -n "$JVM_DECLARED_TYPE" ]; then
  pass "JVM truststore type matches the actual store type"
fi

heading "Generated Control Center trust properties"
PROPS="$(oc -n "$NS" exec "$C3_POD" -c "$C3_CONTAINER" -- sh -c 'grep -E "^(confluent\.metadata|confluent\.controlcenter\.streams).*ssl\.truststore\.(location|password|type)=" /mnt/config/control-center.properties 2>/dev/null || grep -E "^(confluent\.metadata|confluent\.controlcenter\.streams).*ssl\.truststore\.(location|password|type)=" /mnt/config/controlcenter.properties 2>/dev/null || true' 2>/dev/null || true)"
printf '%s\n' "$PROPS" | sed -E 's/(password=).*/\1<redacted>/I'
[ -n "$PROPS" ] || fail "could not locate generated C3 truststore properties"

heading "Recent Control Center OIDC/TLS errors"
LOG_MATCHES="$(oc -n "$NS" logs "$C3_POD" -c "$C3_CONTAINER" --since=30m 2>&1 | grep -Ei 'PKIX|SSLHandshake|certificate_unknown|certification path|authorization-code|oidc' || true)"
if [ -n "$LOG_MATCHES" ]; then
  printf '%s\n' "$LOG_MATCHES" | tail -n 80 | sed -E 's/(code=)[^& ]+/\1<redacted>/g'
else
  echo "No matching lines in the last 30 minutes."
fi

heading "Decision"
if [ "$FAILED" -ne 0 ]; then
  echo "RESULT: FAIL — truststore deployment or JVM wiring is inconsistent."
  exit 1
fi
echo "RESULT: PASS — reference, ConfigMap, mount, password, type, and JVM wiring are consistent."
echo "If a fresh SSO attempt still produces PKIX, capture the new C3 log immediately; the failing TLS target must then be identified from its stack trace."
