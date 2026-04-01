#!/usr/bin/env bash
set -euo pipefail

# Flink-only deploy script for the dev environment on OpenShift ROSA.
# Everything deployed via Helm and oc apply — no ArgoCD, no Kustomize.
#
# Usage:
#   ./scripts/deploy-flink-only-dev.sh
#
# Prerequisites:
#   - oc CLI logged in with cluster-admin
#   - helm CLI installed

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ENV="dev"
NS="dah-kafka-$ENV"

echo "==> Verifying cluster connectivity..."
oc cluster-info || { echo "ERROR: Cannot reach the cluster."; exit 1; }

# ── Step 1: Create and label namespace ───────────────────────────────────────
echo ""
echo "==> Creating namespace..."
oc create namespace "$NS" --dry-run=client -o yaml | oc apply -f -
oc create namespace cert-manager --dry-run=client -o yaml | oc apply -f -

# ── Step 2: Apply OpenShift prerequisites (SCC + bindings) ───────────────────
echo ""
echo "==> Applying OpenShift prerequisites (SCC + bindings)..."
oc apply -f "$REPO_ROOT/openshift-prereqs/$ENV/manifests/"
echo "    SCC and ClusterRoleBindings applied."

# ── Step 2a: Create Confluent license secret ─────────────────────────────────
echo ""
echo "==> Creating Confluent license secret..."
if [ -z "${CONFLUENT_LICENSE:-}" ]; then
  echo "WARNING: CONFLUENT_LICENSE not set. CFK will run in eval mode."
else
  oc create secret generic confluent-license \
    --from-literal=license.txt="$CONFLUENT_LICENSE" \
    -n "$NS" --dry-run=client -o yaml | oc apply -f -
  echo "    License secret created."
fi

# ── Step 3: Install cert-manager ─────────────────────────────────────────────
echo ""
echo "==> Installing cert-manager..."
if oc get pods -n cert-manager 2>/dev/null | grep -q Running; then
  echo "    cert-manager already running — skipping."
else
  helm repo add jetstack https://charts.jetstack.io 2>/dev/null || true
  helm repo update jetstack
  helm upgrade --install cert-manager jetstack/cert-manager \
    --namespace cert-manager \
    --version v1.19.4 \
    -f "$REPO_ROOT/apps/cert-manager/$ENV/values.yaml" \
    -f "$REPO_ROOT/apps/cert-manager/openshift-overlay.yaml" \
    --wait --timeout 600s
  echo "    cert-manager installed."
fi

# Wait for CRDs
echo "    Verifying cert-manager CRDs..."
for CRD in certificates.cert-manager.io issuers.cert-manager.io; do
  RETRIES=0
  until oc get crd "$CRD" &>/dev/null; do
    RETRIES=$((RETRIES + 1))
    if [ "$RETRIES" -ge 30 ]; then echo "ERROR: CRD $CRD not found."; exit 1; fi
    sleep 2
  done
  oc wait --for=condition=Established "crd/$CRD" --timeout=60s
done
echo "    cert-manager CRDs ready."

# ── Step 4: Apply CFK webhook TLS manifests (must exist before operator pods start)
echo ""
echo "==> Applying CFK webhook TLS manifests..."
helm repo add confluent https://packages.confluent.io/helm 2>/dev/null || true
helm repo update confluent
oc apply -n "$NS" -f - <<'CERT_EOF'
---
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: cfk-selfsigned-issuer
spec:
  selfSigned: {}
---
apiVersion: v1
kind: Secret
metadata:
  name: cfk-jks-password
stringData:
  password: changeit
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: confluent-operator-serving-cert
spec:
  secretName: confluent-operator-serving-cert
  issuerRef:
    name: cfk-selfsigned-issuer
    kind: Issuer
  dnsNames:
    - confluent-operator.dah-kafka-dev.svc
    - confluent-operator.dah-kafka-dev.svc.cluster.local
  duration: 8760h
  renewBefore: 720h
  keystores:
    pkcs12:
      create: true
      passwordSecretRef:
        name: cfk-jks-password
        key: password
---
apiVersion: v1
kind: Secret
metadata:
  name: cfk-jks-password-file
stringData:
  jksPassword.txt: "jksPassword=changeit"
CERT_EOF
oc wait --for=condition=Ready certificate/confluent-operator-serving-cert \
  -n "$NS" --timeout=120s
echo "    CFK webhook TLS ready."

# ── Step 4a: Install CFK Operator ────────────────────────────────────────────
echo ""
echo "==> Installing Confluent Operator (CFK)..."
helm upgrade --install confluent-operator confluent/confluent-for-kubernetes \
  --namespace "$NS" \
  --version 0.1351.59 \
  -f "$REPO_ROOT/apps/confluent-operator/$ENV/values.yaml" \
  -f "$REPO_ROOT/apps/confluent-operator/openshift-overlay.yaml" \
  --wait --timeout 600s
echo "    CFK Operator installed."

# ── Step 4b: Wait for CFK CRDs ──────────────────────────────────────────────
echo ""
echo "==> Verifying CFK CRDs..."
for CRD in flinkenvironments.platform.confluent.io cmfrestclasses.platform.confluent.io; do
  RETRIES=0
  until oc get crd "$CRD" &>/dev/null; do
    RETRIES=$((RETRIES + 1))
    if [ "$RETRIES" -ge 30 ]; then echo "ERROR: CRD $CRD not found."; exit 1; fi
    sleep 2
  done
  oc wait --for=condition=Established "crd/$CRD" --timeout=60s
done
echo "    CFK CRDs ready."

# ── Step 5: Install Flink Operator ───────────────────────────────────────────
echo ""
echo "==> Installing Flink Operator..."
helm upgrade --install confluent-flink-operator confluent/flink-kubernetes-operator \
  --namespace "$NS" \
  --version 1.130.2 \
  -f "$REPO_ROOT/apps/confluent-flink-operator/$ENV/values.yaml" \
  -f "$REPO_ROOT/apps/confluent-flink-operator/openshift-overlay.yaml" \
  --wait --timeout 600s
echo "    Flink Operator installed."

# ── Step 6: Install CMF ──────────────────────────────────────────────────────
echo ""
echo "==> Installing CMF..."
helm upgrade --install confluent-cmf "$REPO_ROOT/charts/confluent-manager-for-apache-flink" \
  --namespace "$NS" \
  -f "$REPO_ROOT/apps/confluent-cmf/$ENV/values.yaml" \
  -f "$REPO_ROOT/apps/confluent-cmf/openshift-overlay.yaml" \
  --wait --timeout 600s
echo "    CMF installed."

# ── Step 7: Apply Flink CRs ─────────────────────────────────────────────────
echo ""
echo "==> Applying Flink CRs..."
oc apply -f "$REPO_ROOT/apps/confluent-flink/$ENV/"
echo "    Flink CRs applied."

# ── Step 7a: Wait for Flink session cluster ──────────────────────────────────
echo ""
echo "==> Waiting for Flink session cluster..."
RETRIES=0
until oc get flinkdeployment flink-session -n "$NS" &>/dev/null; do
  RETRIES=$((RETRIES + 1))
  if [ "$RETRIES" -ge 30 ]; then echo "ERROR: FlinkDeployment not found."; exit 1; fi
  sleep 5
done
oc wait --for=jsonpath='{.status.jobManagerDeploymentStatus}'=READY \
  flinkdeployment/flink-session -n "$NS" --timeout=300s
echo "    Flink session cluster is READY."

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "========================================"
echo "  Flink-Only Deployment complete!"
echo "========================================"
echo ""
echo "--- Helm Releases ---"
helm list -n "$NS"
helm list -n cert-manager
echo ""
echo "--- Pods in $NS ---"
oc get pods -n "$NS"
echo ""
echo "--- Flink CRs ---"
oc get flinkdeployment,flinkenvironment,cmfrestclass -n "$NS" 2>/dev/null || true
echo ""
echo "Flink UI: oc port-forward svc/flink-session-rest 8081:8081 -n $NS"
echo ""
