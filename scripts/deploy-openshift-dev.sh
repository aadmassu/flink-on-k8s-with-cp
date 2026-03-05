#!/usr/bin/env bash
set -euo pipefail

# Full deploy script for the dev environment on OpenShift.
# Uses the OpenShift GitOps Operator (ArgoCD in openshift-gitops namespace)
# to deploy cert-manager, Confluent Operator (CFK), Flink Operator, CMF,
# Confluent Platform (local Kafka), and Flink infrastructure CRs.
#
# Usage:
#   ./scripts/deploy-openshift-dev.sh
#
# Prerequisites:
#   - oc CLI configured and logged in with cluster-admin access
#   - OpenShift GitOps Operator installed

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ENV="dev"
ARGOCD_NS="openshift-gitops"

echo "==> Verifying cluster connectivity..."
oc cluster-info || { echo "ERROR: Cannot reach the cluster. Check your kubeconfig / oc login."; exit 1; }

# ── Step 1: Verify OpenShift GitOps Operator ─────────────────────────────────
echo ""
echo "==> Verifying OpenShift GitOps Operator..."
if ! oc get pods -n "$ARGOCD_NS" -l app.kubernetes.io/name=openshift-gitops-server --no-headers 2>/dev/null | grep -q Running; then
  echo "ERROR: OpenShift GitOps ArgoCD server is not running in $ARGOCD_NS."
  echo "       Install the OpenShift GitOps Operator from OperatorHub first."
  exit 1
fi
echo "    OpenShift GitOps Operator is running."

# ── Step 1a: Configure ArgoCD repo credentials ──────────────────────────────
echo ""
echo "==> Configuring ArgoCD repo credentials..."
if [ -z "${ARGOCD_SSH_KEY:-}" ]; then
  echo "WARNING: ARGOCD_SSH_KEY environment variable is not set."
  echo "         Skipping repo secret — ArgoCD may not be able to clone the repo."
  echo "         To configure: export ARGOCD_SSH_KEY=\$(cat ~/.ssh/id_rsa)"
else
  ARGOCD_SSH_KEY="$ARGOCD_SSH_KEY" envsubst < "$REPO_ROOT/gitops-config/openshift/argocd-repo-secret.yaml" \
    | oc apply -f -
  echo "    Repo credentials configured."
fi

# ── Step 2: Create and label namespaces ──────────────────────────────────────
echo ""
echo "==> Creating and labeling namespaces..."
for NS in "confluent-$ENV" "cert-manager"; do
  oc create namespace "$NS" --dry-run=client -o yaml | oc apply -f -
  oc label namespace "$NS" argocd.argoproj.io/managed-by="$ARGOCD_NS" --overwrite
  echo "    Namespace $NS labeled for OpenShift GitOps management."
done

# ── Step 3: Apply OpenShift prerequisites (SCC + bindings) ───────────────────
echo ""
echo "==> Applying OpenShift prerequisites (SCC + bindings)..."
oc apply -f "$REPO_ROOT/openshift-prereqs/$ENV/manifests/"
echo "    SCC and ClusterRoleBindings applied."

# ── Step 4: Deploy cert-manager (skip if already installed) ──────────────────
echo ""
echo "==> Deploying cert-manager..."
if oc get pods -n cert-manager 2>/dev/null | grep -q Running || \
   oc get pods -n openshift-cert-manager 2>/dev/null | grep -q Running; then
  echo "    cert-manager already running — skipping."
else
  oc apply -f "$REPO_ROOT/gitops-config/openshift/$ENV/cert-manager-application-set.yaml"
  echo "    Waiting for cert-manager to become Healthy..."
  oc wait --for=jsonpath='{.status.health.status}'=Healthy \
    application/cert-manager-$ENV -n "$ARGOCD_NS" --timeout=180s
fi

# ── Step 4a: Wait for cert-manager CRDs ─────────────────────────────────────
echo ""
echo "==> Verifying cert-manager CRDs are established..."
# CRDs may not exist yet when ArgoCD first reports Healthy — retry until they appear
for CRD in certificates.cert-manager.io issuers.cert-manager.io; do
  echo "    Waiting for CRD $CRD to be registered..."
  RETRIES=0
  MAX_RETRIES=30
  until oc get crd "$CRD" &>/dev/null; do
    RETRIES=$((RETRIES + 1))
    if [ "$RETRIES" -ge "$MAX_RETRIES" ]; then
      echo "ERROR: CRD $CRD not found after ${MAX_RETRIES} retries."
      exit 1
    fi
    sleep 2
  done
  oc wait --for=condition=Established "crd/$CRD" --timeout=60s
done
echo "    cert-manager CRDs are ready."

# ── Step 5: Deploy Confluent Operator & Flink Operator ───────────────────────
echo ""
echo "==> Deploying Confluent Operator..."
oc apply -f "$REPO_ROOT/gitops-config/openshift/$ENV/confluent-operator-application-set.yaml"

echo "==> Deploying Flink Operator..."
oc apply -f "$REPO_ROOT/gitops-config/openshift/$ENV/confluent-flink-operator-application-set.yaml"

echo "    Waiting for both operators to become Healthy..."
oc wait --for=jsonpath='{.status.health.status}'=Healthy \
  application/confluent-operator-$ENV \
  application/confluent-flink-operator-$ENV \
  -n "$ARGOCD_NS" --timeout=180s

# ── Phase-II ────────────────────────────────────────────────────────────────

# ── Step 6: Deploy CMF ─────────────────────────────────────────────────────
echo ""
echo "==> Deploying Confluent Manager for Apache Flink (CMF)..."
oc apply -f "$REPO_ROOT/gitops-config/openshift/$ENV/confluent-cmf-application-set.yaml"
echo "    Waiting for CMF to become Healthy..."
oc wait --for=jsonpath='{.status.health.status}'=Healthy \
  application/confluent-cmf-$ENV -n "$ARGOCD_NS" --timeout=180s

# ── Step 7: Deploy Confluent Platform (local Kafka for PoC) ───────────────
echo ""
echo "==> Deploying Confluent Platform (local Kafka for PoC)..."
oc apply -f "$REPO_ROOT/gitops-config/openshift/$ENV/confluent-platform-application-set.yaml"
echo "    Waiting for Confluent Platform to sync and become Healthy..."
oc wait --for=jsonpath='{.status.sync.status}'=Synced \
  application/confluent-platform-$ENV -n "$ARGOCD_NS" --timeout=300s
oc wait --for=jsonpath='{.status.health.status}'=Healthy \
  application/confluent-platform-$ENV -n "$ARGOCD_NS" --timeout=300s

# ── Step 7a: Wait for Kafka to be ready ──────────────────────────────────
echo ""
echo "==> Waiting for Kafka to reach RUNNING state..."
# Kafka CR may not exist yet — wait for ArgoCD to create it
RETRIES=0
MAX_RETRIES=60
until oc get kafka kafka -n confluent-$ENV &>/dev/null; do
  RETRIES=$((RETRIES + 1))
  if [ "$RETRIES" -ge "$MAX_RETRIES" ]; then
    echo "ERROR: Kafka CR not found after ${MAX_RETRIES} retries."
    exit 1
  fi
  sleep 5
done
oc wait --for=jsonpath='{.status.phase}'=RUNNING kafka/kafka \
  -n confluent-$ENV --timeout=300s
echo "    Kafka is RUNNING."

# ── Step 8: Deploy Flink infrastructure (CMFRestClass, FlinkEnvironment, PVC, Session Cluster)
echo ""
echo "==> Deploying Flink infrastructure CRs and session cluster..."
oc apply -f "$REPO_ROOT/gitops-config/openshift/$ENV/confluent-flink-application-set.yaml"
echo "    Waiting for Flink app to sync..."
oc wait --for=jsonpath='{.status.sync.status}'=Synced \
  application/confluent-flink-$ENV -n "$ARGOCD_NS" --timeout=180s

# ── Step 8a: Wait for Flink session cluster to be ready ──────────────────
echo ""
echo "==> Waiting for Flink session cluster to be ready..."
# FlinkDeployment may not exist yet — wait for ArgoCD to create it
RETRIES=0
MAX_RETRIES=30
until oc get flinkdeployment flink-session -n confluent-$ENV &>/dev/null; do
  RETRIES=$((RETRIES + 1))
  if [ "$RETRIES" -ge "$MAX_RETRIES" ]; then
    echo "ERROR: FlinkDeployment flink-session not found after ${MAX_RETRIES} retries."
    exit 1
  fi
  sleep 5
done
oc wait --for=jsonpath='{.status.jobManagerDeploymentStatus}'=READY \
  flinkdeployment/flink-session -n confluent-$ENV --timeout=300s
echo "    Flink session cluster is READY."
echo "    Access Flink UI: oc port-forward svc/flink-session-rest 8081:8081 -n confluent-$ENV"

# ── Step 9: Print summary ──────────────────────────────────────────────────
echo ""
echo "========================================"
echo "  OpenShift Deployment complete!"
echo "========================================"
echo ""
echo "--- ArgoCD Applications ---"
oc get applications -n "$ARGOCD_NS"
echo ""
echo "--- Pods in confluent-$ENV ---"
oc get pods -n confluent-$ENV
echo ""
echo "--- cert-manager Pods ---"
oc get pods -n cert-manager 2>/dev/null || echo "  (using OpenShift-provided cert-manager)"
echo ""

# Print ArgoCD access info
ARGOCD_URL=$(oc get route openshift-gitops-server -n "$ARGOCD_NS" \
  -o jsonpath='{.spec.host}' 2>/dev/null || true)

echo "--- ArgoCD Access ---"
if [ -n "$ARGOCD_URL" ]; then
  echo "  URL:      https://$ARGOCD_URL"
else
  echo "  URL:      (Run: oc get route -n $ARGOCD_NS)"
fi
echo "  Username: admin"
echo "  Password: oc -n $ARGOCD_NS get secret openshift-gitops-cluster -o jsonpath='{.data.admin\\.password}' | base64 -d"
echo ""
