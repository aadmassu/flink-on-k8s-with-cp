#!/usr/bin/env bash

# Read-only diagnostic for the CFK operator-to-MDS client certificate.
# Intended for execution through the ad-hoc OpenShift script pipeline.
#
# Pipeline usage (matches validate-confluent-platform.yaml):
#   ./ad-hoc-oc-cfk-operator-cert-diagnostic.sh [output-directory]
#
# The pipeline provides OC_NS and TARGET_ENV from the selected environment's
# variable group. Optional environment overrides:
#   CERT_NAME   (default: cfk-operator-mds-client)
#   SECRET_NAME (default: cfk-operator-mds-client-tls)
#
# This script deliberately exits 0 after collecting evidence, even when it
# reports failed validation checks. It does not print private keys, certificate
# PEM bodies, CSR bodies, OAuth credentials, or Kubernetes Secret values.

set -uo pipefail

OUTPUT_DIR="${1:-logs}"
TARGET_ENV="${TARGET_ENV:-unknown}"
CERT_NAME="${CERT_NAME:-cfk-operator-mds-client}"
SECRET_NAME="${SECRET_NAME:-cfk-operator-mds-client-tls}"

# OC_NS is the authoritative namespace selected by the Azure DevOps variable
# group. The current oc project is a convenience fallback for manual runs.
NS="${OC_NS:-}"
if [ -z "$NS" ] && command -v oc >/dev/null 2>&1; then
  NS="$(oc project -q 2>/dev/null || true)"
fi
NS="${NS:-UNKNOWN}"

mkdir -p "$OUTPUT_DIR" 2>/dev/null || true
REPORT_FILE="$OUTPUT_DIR/cfk-operator-cert-diagnostic-${TARGET_ENV}-$(date -u '+%Y%m%dT%H%M%SZ' 2>/dev/null || printf unknown).log"
if touch "$REPORT_FILE" 2>/dev/null; then
  # Stream to the Azure DevOps log and retain the same sanitized report as an
  # artifact under the output directory supplied by the validation pipeline.
  exec > >(tee -a "$REPORT_FILE") 2>&1
fi

WORK_DIR="$(mktemp -d 2>/dev/null || printf '/tmp/cfk-cert-diag.%s' "$$")"
mkdir -p "$WORK_DIR" 2>/dev/null || true

PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0

cleanup() {
  rm -rf "$WORK_DIR" 2>/dev/null || true
}

# The user requested an evidence-gathering script that never fails the ad-hoc
# pipeline. Preserve that contract even if an unexpected command fails.
finish() {
  local original_rc=$?
  trap - EXIT INT TERM
  cleanup
  echo
  echo "============================================================"
  echo "Diagnostic summary"
  echo "PASS: $PASS_COUNT"
  echo "WARN: $WARN_COUNT"
  echo "FAIL: $FAIL_COUNT"
  echo "Original internal status: $original_rc"
  echo "Script exit code: 0 (evidence collection mode)"
  echo "============================================================"
  exit 0
}
trap finish EXIT INT TERM

pass() { PASS_COUNT=$((PASS_COUNT + 1)); echo "PASS: $*"; }
warn() { WARN_COUNT=$((WARN_COUNT + 1)); echo "WARN: $*"; }
fail() { FAIL_COUNT=$((FAIL_COUNT + 1)); echo "FAIL: $*"; }

section() {
  echo
  echo "============================================================"
  echo "$*"
  echo "============================================================"
}

have() { command -v "$1" >/dev/null 2>&1; }

safe_oc() {
  oc "$@" 2>&1 || true
}

section "0. Dynatrace metrics wiring (expected result of the latest install-or-update)"
# Same checks as the validate pipeline, non-strict here; plus the per-pod scrape URLs for Dynatrace.
STRICT=0 OC_NS="$NS" TARGET_ENV="$TARGET_ENV" bash "$(dirname "$0")/validate-dynatrace-metrics.sh" || true
echo
echo "Per-pod scrape URLs (for the Dynatrace team):"
for pod in $(oc -n "$NS" get pods -l app.kubernetes.io/part-of=confluent-platform -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
  sub=$(oc -n "$NS" get pod "$pod" -o jsonpath='{.spec.subdomain}' 2>/dev/null)
  echo "  http://${pod}.${sub:-<no-subdomain>}.${NS}.svc.cluster.local:7778/metrics"
done
echo
echo "Dynatrace metrics Services (annotations as stored):"
safe_oc -n "$NS" get svc -l app.kubernetes.io/component=dynatrace-metrics \
  -o custom-columns='NAME:.metadata.name,SCRAPE:.metadata.annotations.metrics\.dynatrace\.com/scrape,PORT:.metadata.annotations.metrics\.dynatrace\.com/port,PATH:.metadata.annotations.metrics\.dynatrace\.com/path,SELECTOR:.spec.selector'

section "0b. Kafka client listener passthrough (runbook H10)"
STRICT=0 OC_NS="$NS" TARGET_ENV="$TARGET_ENV" ENV_DIR="apps/confluent-platform/$TARGET_ENV" bash "$(dirname "$0")/kafka-passthrough.sh" check || true
echo
echo "Routes generated from the passthrough Ingresses:"
safe_oc -n "$NS" get route -l app.kubernetes.io/component=kafka-passthrough -o custom-columns='NAME:.metadata.name,HOST:.spec.host,TERMINATION:.spec.tls.termination,SERVICE:.spec.to.name,PORT:.spec.port.targetPort,ADMITTED:.status.ingress[0].conditions[0].status'

section "CFK operator mTLS certificate diagnostic"
echo "Timestamp (UTC):  $(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || true)"
echo "Target environment:$TARGET_ENV"
echo "Namespace:        $NS"
echo "Certificate:      $CERT_NAME"
echo "Target Secret:    $SECRET_NAME"
echo "Requested EKU:    TLS Web Client Authentication (OID 1.3.6.1.5.5.7.3.2)"
echo "Read-only mode:   yes"
echo "Guaranteed exit:  0"
echo "Report file:      $REPORT_FILE"

if [ "$NS" = "UNKNOWN" ]; then
  fail "OC_NS was not supplied and the current OpenShift project could not be discovered."
  exit 0
fi

if ! have oc; then
  fail "oc command is unavailable; no cluster information can be collected."
  exit 0
fi

section "1. OpenShift context and access"
echo "API server: $(safe_oc whoami --show-server | tail -1)"
echo "User:       $(safe_oc whoami | tail -1)"

if oc get namespace "$NS" >/dev/null 2>&1; then
  pass "Namespace/$NS is accessible."
else
  fail "Namespace/$NS is not accessible or does not exist."
fi

for resource in certificates.cert-manager.io certificaterequests.cert-manager.io secrets events; do
  if oc auth can-i get "$resource" -n "$NS" 2>/dev/null | grep -qi '^yes$'; then
    pass "Current identity can read $resource in $NS."
  else
    warn "Current identity cannot confirm read access to $resource in $NS."
  fi
done

section "2. Certificate request declared by the application"
if oc -n "$NS" get certificate "$CERT_NAME" -o json >"$WORK_DIR/certificate.json" 2>"$WORK_DIR/certificate.err"; then
  pass "Certificate/$CERT_NAME exists."

  echo "Name:        $(oc -n "$NS" get certificate "$CERT_NAME" -o jsonpath='{.metadata.name}' 2>/dev/null || true)"
  echo "Namespace:   $(oc -n "$NS" get certificate "$CERT_NAME" -o jsonpath='{.metadata.namespace}' 2>/dev/null || true)"
  echo "CommonName:  $(oc -n "$NS" get certificate "$CERT_NAME" -o jsonpath='{.spec.commonName}' 2>/dev/null || true)"
  echo "DNS names:   $(oc -n "$NS" get certificate "$CERT_NAME" -o jsonpath='{range .spec.dnsNames[*]}{.}{" "}{end}' 2>/dev/null || true)"
  echo "Usages:      $(oc -n "$NS" get certificate "$CERT_NAME" -o jsonpath='{range .spec.usages[*]}{.}{" "}{end}' 2>/dev/null || true)"
  echo "Secret:      $(oc -n "$NS" get certificate "$CERT_NAME" -o jsonpath='{.spec.secretName}' 2>/dev/null || true)"
  echo "Duration:    $(oc -n "$NS" get certificate "$CERT_NAME" -o jsonpath='{.spec.duration}' 2>/dev/null || true)"
  echo "RenewBefore: $(oc -n "$NS" get certificate "$CERT_NAME" -o jsonpath='{.spec.renewBefore}' 2>/dev/null || true)"
  echo "Issuer:      $(oc -n "$NS" get certificate "$CERT_NAME" -o jsonpath='{.spec.issuerRef.group}{"/"}{.spec.issuerRef.kind}{"/"}{.spec.issuerRef.name}' 2>/dev/null || true)"
  echo "Environment: $(oc -n "$NS" get certificate "$CERT_NAME" -o 'jsonpath={.metadata.annotations.metadata\.command-issuer\.keyfactor\.com/Environment}' 2>/dev/null || true)"

  REQUESTED_USAGES="$(oc -n "$NS" get certificate "$CERT_NAME" -o jsonpath='{range .spec.usages[*]}{.}{"\n"}{end}' 2>/dev/null || true)"
  if printf '%s\n' "$REQUESTED_USAGES" | grep -Eqi '^client auth$'; then
    pass "Certificate spec explicitly requests client auth."
  else
    fail "Certificate spec does not explicitly request client auth."
  fi

  echo
  echo "Certificate conditions:"
  safe_oc -n "$NS" get certificate "$CERT_NAME" \
    -o custom-columns='TYPE:.status.conditions[*].type,STATUS:.status.conditions[*].status,REASON:.status.conditions[*].reason,MESSAGE:.status.conditions[*].message,NOT_AFTER:.status.notAfter,REVISION:.status.revision'
else
  fail "Certificate/$CERT_NAME could not be read."
  sed -n '1,80p' "$WORK_DIR/certificate.err" 2>/dev/null || true
fi

section "3. CertificateRequest evidence"
if oc -n "$NS" get certificaterequest -o json >"$WORK_DIR/requests.json" 2>"$WORK_DIR/requests.err"; then
  if have python3; then
    python3 - "$WORK_DIR/requests.json" "$CERT_NAME" <<'PY' || true
from __future__ import print_function
import json
import sys

path, certificate_name = sys.argv[1:3]
with open(path, "r") as handle:
    payload = json.load(handle)

matches = []
for item in payload.get("items", []):
    metadata = item.get("metadata", {})
    labels = metadata.get("labels", {})
    owners = metadata.get("ownerReferences", [])
    related = labels.get("cert-manager.io/certificate-name") == certificate_name
    related = related or any(owner.get("name") == certificate_name for owner in owners)
    related = related or metadata.get("name", "").startswith(certificate_name + "-")
    if related:
        matches.append(item)

matches.sort(key=lambda item: item.get("metadata", {}).get("creationTimestamp", ""))
print("Matching CertificateRequests: {0}".format(len(matches)))
for item in matches:
    metadata = item.get("metadata", {})
    spec = item.get("spec", {})
    status = item.get("status", {})
    print("---")
    print("Name:       {0}".format(metadata.get("name", "")))
    print("Created:    {0}".format(metadata.get("creationTimestamp", "")))
    print("Revision:   {0}".format(metadata.get("annotations", {}).get("cert-manager.io/certificate-revision", "")))
    print("Issuer:     {0}/{1}/{2}".format(
        spec.get("issuerRef", {}).get("group", ""),
        spec.get("issuerRef", {}).get("kind", ""),
        spec.get("issuerRef", {}).get("name", "")))
    print("Usages:     {0}".format(", ".join(spec.get("usages", []))))
    print("Duration:   {0}".format(spec.get("duration", "")))
    print("Conditions:")
    for condition in status.get("conditions", []):
        print("  {0}={1}; reason={2}; message={3}".format(
            condition.get("type", ""), condition.get("status", ""),
            condition.get("reason", ""), condition.get("message", "")))
PY
  else
    warn "python3 is unavailable; printing the CertificateRequest table only."
    safe_oc -n "$NS" get certificaterequest
  fi
else
  warn "CertificateRequests could not be listed."
  sed -n '1,80p' "$WORK_DIR/requests.err" 2>/dev/null || true
fi

section "4. Issued Secret inventory (values suppressed)"
if oc -n "$NS" get secret "$SECRET_NAME" -o json >"$WORK_DIR/secret.json" 2>"$WORK_DIR/secret.err"; then
  pass "Secret/$SECRET_NAME exists."
  echo "Secret type: $(oc -n "$NS" get secret "$SECRET_NAME" -o jsonpath='{.type}' 2>/dev/null || true)"
  echo "Data keys and encoded sizes (values are not printed):"
  if have python3; then
    python3 - "$WORK_DIR/secret.json" <<'PY' || true
from __future__ import print_function
import json
import sys
with open(sys.argv[1], "r") as handle:
    payload = json.load(handle)
for key in sorted(payload.get("data", {})):
    print("  {0}: {1} encoded bytes".format(key, len(payload["data"][key])))
PY
  else
    echo "  $(oc -n "$NS" get secret "$SECRET_NAME" -o go-template='{{range $k,$v := .data}}{{$k}} {{end}}' 2>/dev/null || true)"
  fi

  CERT_B64="$(oc -n "$NS" get secret "$SECRET_NAME" -o 'jsonpath={.data.tls\.crt}' 2>/dev/null || true)"
  if [ -n "$CERT_B64" ]; then
    if printf '%s' "$CERT_B64" | base64 --decode >"$WORK_DIR/tls.crt" 2>/dev/null && [ -s "$WORK_DIR/tls.crt" ]; then
      pass "tls.crt was extracted to temporary storage."
    else
      fail "tls.crt could not be decoded."
    fi
  else
    fail "Secret/$SECRET_NAME has no tls.crt value."
  fi

  if oc -n "$NS" get secret "$SECRET_NAME" -o 'jsonpath={.data.tls\.key}' 2>/dev/null | grep -q .; then
    pass "tls.key exists (value suppressed)."
  else
    fail "tls.key is missing or empty."
  fi

  if oc -n "$NS" get secret "$SECRET_NAME" -o 'jsonpath={.data.ca\.crt}' 2>/dev/null | grep -q .; then
    pass "ca.crt exists (value suppressed)."
  else
    warn "ca.crt is missing or empty."
  fi
else
  fail "Secret/$SECRET_NAME could not be read."
  sed -n '1,80p' "$WORK_DIR/secret.err" 2>/dev/null || true
fi

section "5. Issued X.509 certificate details"
if [ -s "$WORK_DIR/tls.crt" ] && have openssl; then
  openssl x509 -in "$WORK_DIR/tls.crt" -noout \
    -subject -issuer -serial -dates -fingerprint -sha256 2>&1 || true

  echo
  echo "Subject Alternative Names:"
  openssl x509 -in "$WORK_DIR/tls.crt" -noout -ext subjectAltName 2>&1 || true

  echo
  echo "Key Usage:"
  openssl x509 -in "$WORK_DIR/tls.crt" -noout -ext keyUsage 2>&1 || true

  echo
  echo "Extended Key Usage:"
  EKU_OUTPUT="$(openssl x509 -in "$WORK_DIR/tls.crt" -noout -ext extendedKeyUsage 2>&1 || true)"
  printf '%s\n' "$EKU_OUTPUT"

  echo
  echo "Basic Constraints:"
  openssl x509 -in "$WORK_DIR/tls.crt" -noout -ext basicConstraints 2>&1 || true

  if printf '%s\n' "$EKU_OUTPUT" | grep -Eq 'TLS Web Client Authentication|1\.3\.6\.1\.5\.5\.7\.3\.2'; then
    pass "Issued certificate contains the Client Authentication EKU."
  else
    fail "Issued certificate does not contain the Client Authentication EKU."
  fi

  if openssl x509 -in "$WORK_DIR/tls.crt" -noout -checkend 86400 >/dev/null 2>&1; then
    pass "Issued certificate remains valid for more than 24 hours."
  else
    fail "Issued certificate is invalid or expires within 24 hours."
  fi
else
  warn "OpenSSL inspection was skipped because openssl or a decoded certificate is unavailable."
fi

section "6. Requested-versus-issued conclusion"
if printf '%s\n' "${REQUESTED_USAGES:-}" | grep -Eqi '^client auth$'; then
  echo "Application request: client auth was requested."
else
  echo "Application request: client auth was NOT found in Certificate.spec.usages."
fi

if [ -n "${EKU_OUTPUT:-}" ] && printf '%s\n' "$EKU_OUTPUT" | grep -Eq 'TLS Web Client Authentication|1\.3\.6\.1\.5\.5\.7\.3\.2'; then
  echo "Issued certificate: Client Authentication EKU is present."
else
  echo "Issued certificate: Client Authentication EKU is absent."
fi

if printf '%s\n' "${REQUESTED_USAGES:-}" | grep -Eqi '^client auth$' \
   && ! printf '%s\n' "${EKU_OUTPUT:-}" | grep -Eq 'TLS Web Client Authentication|1\.3\.6\.1\.5\.5\.7\.3\.2'; then
  echo "RESULT: cert-manager requested client auth, but the issued certificate omitted it."
  echo "BOUNDARY: investigate the approved CertificateRequest, approver-policy, and Keyfactor Prod-Corp issuance profile/template."
  echo "REQUIRED EKU: TLS Web Client Authentication (OID 1.3.6.1.5.5.7.3.2)."
elif printf '%s\n' "${EKU_OUTPUT:-}" | grep -Eq 'TLS Web Client Authentication|1\.3\.6\.1\.5\.5\.7\.3\.2'; then
  echo "RESULT: requested and issued client-auth usage agree."
else
  echo "RESULT: evidence is incomplete; review the sections above."
fi

section "7. Approver-policy visibility (best effort)"
POLICY_RESOURCE="$(oc api-resources --api-group=policy.cert-manager.io -o name 2>/dev/null | grep -E 'certificaterequestpolic' | head -1 || true)"
if [ -z "$POLICY_RESOURCE" ]; then
  warn "CertificateRequestPolicy resource was not discoverable."
elif ! oc auth can-i list "$POLICY_RESOURCE" --all-namespaces 2>/dev/null | grep -qi '^yes$'; then
  warn "Current identity cannot list $POLICY_RESOURCE; the Container Platform team must inspect allowed usages."
else
  echo "Policy resource: $POLICY_RESOURCE"
  safe_oc get "$POLICY_RESOURCE" \
    -o custom-columns='NAME:.metadata.name,ALLOWED-USAGES:.spec.allowed.usages,MAX-DURATION:.spec.constraints.maxDuration,SELECTOR:.spec.selector'
  pass "Approver policies were listed; confirm an applicable policy permits client auth."
fi

section "8. Recent related events"
safe_oc -n "$NS" get events --sort-by='.lastTimestamp' | \
  grep -E "$CERT_NAME|$SECRET_NAME|CertificateRequest|Keyfactor|keyfactor|cert-manager" | tail -80 || true

echo
echo "Collection complete. No private key, CSR body, Secret value, token, or credential was printed."
exit 0