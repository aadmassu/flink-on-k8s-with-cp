# Deploying Operator Apps into an Existing ArgoCD

This guide provides step-by-step instructions for deploying the Confluent Platform and Flink operator applications into a cluster that **already has ArgoCD running**.

If you need to install ArgoCD from scratch, see the main [README.md](README.md).

---

## Table of Contents

- [Prerequisites](#prerequisites)
- [Deployment Order](#deployment-order)
- [Step 1 - Verify ArgoCD Is Running](#step-1---verify-argocd-is-running)
- [Step 2 - Clone This Repository](#step-2---clone-this-repository)
- [Step 3 - Review and Customize App Definitions](#step-3---review-and-customize-app-definitions)
- [Step 4 - Deploy cert-manager](#step-4---deploy-cert-manager)
- [Step 5 - Deploy Confluent Operator (CFK)](#step-5---deploy-confluent-operator-cfk)
- [Step 6 - Deploy Flink Operator](#step-6---deploy-flink-operator)
- [Step 7 - Deploy Confluent Platform](#step-7---deploy-confluent-platform)
- [Step 8 - Deploy Confluent Flink Manager](#step-8---deploy-confluent-flink-manager)
- [Verify All Applications](#verify-all-applications)
- [Quick Deploy Script](#quick-deploy-script)
- [Troubleshooting](#troubleshooting)

---

## Prerequisites

| Requirement | Details |
|-------------|---------|
| **ArgoCD** | Running and accessible in your cluster (namespace `argocd` or your custom namespace) |
| **kubectl** | 1.28+ configured with access to the target cluster |
| **Cluster access** | Permissions to create namespaces, CRDs, and ArgoCD Application resources |

Verify your cluster connectivity:

```bash
kubectl cluster-info
kubectl get pods -n argocd
```

---

## Deployment Order

Applications must be deployed in this order due to dependencies:

```
cert-manager  -->  confluent-operator     -->  confluent-platform
              -->  confluent-flink-operator  -->  confluent-flink
```

- **cert-manager** must be healthy before the Flink operator (provides TLS certificates for webhooks).
- **confluent-operator** and **confluent-flink-operator** can be deployed in parallel after cert-manager.
- **confluent-platform** and **confluent-flink** CRDs require their respective operators to be running.

---

## Step 1 - Verify ArgoCD Is Running

Confirm ArgoCD is healthy and the Application CRD is available:

```bash
# Check ArgoCD pods are running
kubectl get pods -n argocd

# Verify the Application CRD exists
kubectl get crd applications.argoproj.io
```

Expected: All ArgoCD pods should be in `Running` state and the `applications.argoproj.io` CRD should exist.

> **Note:** If ArgoCD is installed in a namespace other than `argocd`, update the `metadata.namespace` field in each `app.yaml` file before proceeding.

---

## Step 2 - Clone This Repository

```bash
git clone <your-repo-url>
cd <repo-directory>
```

---

## Step 3 - Review and Customize App Definitions

Before deploying, review and update the Application resources for your environment. Each app is defined in `apps/<app-name>/<env>/app.yaml`.

Key fields to check in each `app.yaml`:

| Field | What to verify |
|-------|----------------|
| `metadata.namespace` | Must match your ArgoCD namespace (default: `argocd`) |
| `spec.destination.server` | Must point to your target cluster API server (use `https://kubernetes.default.svc` for the local cluster) |
| `spec.destination.namespace` | Target namespace for the application (e.g., `confluent-dev`) |
| `spec.source.repoURL` | Git repository URL for this repo (for directory-based apps) or Helm chart URL |
| `spec.source.targetRevision` | Git branch or Helm chart version |

Example - check a dev app definition:

```bash
cat apps/cert-manager/dev/app.yaml
```

---

## Step 4 - Deploy cert-manager

cert-manager provides TLS certificates required by the Flink operator webhooks. Deploy it first.

**Apply the ArgoCD Application resource:**

```bash
kubectl apply -f apps/cert-manager/dev/app.yaml
```

**Wait for cert-manager to become healthy:**

```bash
kubectl wait --for=jsonpath='{.status.health.status}'=Healthy \
  application/cert-manager-dev -n argocd --timeout=180s
```

**Verify pods are running:**

```bash
kubectl get pods -n cert-manager
```

Expected output:

```
NAME                                       READY   STATUS    RESTARTS   AGE
cert-manager-...                           1/1     Running   0          ...
cert-manager-cainjector-...                1/1     Running   0          ...
cert-manager-webhook-...                   1/1     Running   0          ...
```

---

## Step 5 - Deploy Confluent Operator (CFK)

The Confluent for Kubernetes operator manages Confluent Platform CRDs.

**Apply the ArgoCD Application resource:**

```bash
kubectl apply -f apps/confluent-operator/dev/app.yaml
```

**Wait for healthy:**

```bash
kubectl wait --for=jsonpath='{.status.health.status}'=Healthy \
  application/confluent-operator-dev -n argocd --timeout=180s
```

**Verify:**

```bash
kubectl get pods -n confluent-dev -l app=confluent-operator
```

---

## Step 6 - Deploy Flink Operator

The Flink Kubernetes operator manages Flink workloads. Requires cert-manager to be running.

**Apply the ArgoCD Application resource:**

```bash
kubectl apply -f apps/confluent-flink-operator/dev/app.yaml
```

**Wait for healthy:**

```bash
kubectl wait --for=jsonpath='{.status.health.status}'=Healthy \
  application/confluent-flink-operator-dev -n argocd --timeout=180s
```

**Verify both operators:**

```bash
kubectl get pods -n confluent-dev
```

Expected:

```
confluent-operator-...                 1/1     Running
flink-kubernetes-operator-...          2/2     Running
```

---

## Step 7 - Deploy Confluent Platform

Deploys the full Confluent Platform stack (KRaft, Kafka, Schema Registry, Connect, ksqlDB, Control Center). Requires the Confluent Operator to be running.

**Apply the ArgoCD Application resource:**

```bash
kubectl apply -f apps/confluent-platform/dev/app.yaml
```

ArgoCD deploys the CRD manifests in sync-wave order:

| Wave | Components |
|------|-----------|
| 0 | KRaftController |
| 1 | Kafka |
| 2 | SchemaRegistry, Connect |
| 3 | ksqlDB, ControlCenter |

**Monitor deployment progress:**

```bash
kubectl get applications confluent-platform-dev -n argocd -w
```

**Verify Confluent Platform pods:**

```bash
kubectl get pods -n confluent-dev
```

---

## Step 8 - Deploy Confluent Flink Manager

Deploys the Confluent Manager for Apache Flink (CMF). Requires the Flink Operator to be running.

**Apply the ArgoCD Application resource:**

```bash
kubectl apply -f apps/confluent-flink/dev/app.yaml
```

**Monitor deployment:**

```bash
kubectl get applications confluent-flink-dev -n argocd -w
```

---

## Verify All Applications

After all applications are deployed, verify the full stack:

```bash
# List all ArgoCD-managed applications
kubectl get applications -n argocd

# Check health and sync status
kubectl get applications -n argocd -o custom-columns=\
NAME:.metadata.name,\
HEALTH:.status.health.status,\
SYNC:.status.sync.status,\
NAMESPACE:.spec.destination.namespace
```

Expected output:

```
NAME                            HEALTH    SYNC     NAMESPACE
cert-manager-dev                Healthy   Synced   cert-manager
confluent-operator-dev          Healthy   Synced   confluent-dev
confluent-flink-operator-dev    Healthy   Synced   confluent-dev
confluent-platform-dev          Healthy   Synced   confluent-dev
confluent-flink-dev             Healthy   Synced   confluent-dev
```

---

## Quick Deploy Script

Deploy all operator apps at once (respecting dependency order):

```bash
ENV=dev  # Change to qa, stg, or prd as needed

# 1. cert-manager (must be first)
kubectl apply -f apps/cert-manager/${ENV}/app.yaml
kubectl wait --for=jsonpath='{.status.health.status}'=Healthy \
  application/cert-manager-${ENV} -n argocd --timeout=180s

# 2. Both operators (can run in parallel)
kubectl apply -f apps/confluent-operator/${ENV}/app.yaml
kubectl apply -f apps/confluent-flink-operator/${ENV}/app.yaml
kubectl wait --for=jsonpath='{.status.health.status}'=Healthy \
  application/confluent-operator-${ENV} \
  application/confluent-flink-operator-${ENV} \
  -n argocd --timeout=180s

# 3. Platform CRDs and Flink Manager
kubectl apply -f apps/confluent-platform/${ENV}/app.yaml
kubectl apply -f apps/confluent-flink/${ENV}/app.yaml

# 4. Verify
echo ""
echo "=== All Applications ==="
kubectl get applications -n argocd
```

---

## Troubleshooting

### ArgoCD namespace mismatch

If you see `Error from server (NotFound): applications.argoproj.io "..." not found`, your ArgoCD may be in a different namespace. Update `metadata.namespace` in each `app.yaml`:

```bash
# Find where ArgoCD is running
kubectl get pods --all-namespaces | grep argocd
```

### Application stuck in "Unknown" health

The ArgoCD Application was created but ArgoCD hasn't processed it yet. Check ArgoCD controller logs:

```bash
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller --tail=50
```

### cert-manager CRDs not ready

If deploying the Flink operator fails with CRD errors, cert-manager may not be fully initialized:

```bash
# Check cert-manager webhook is ready
kubectl get pods -n cert-manager -l app.kubernetes.io/component=webhook

# Verify CRDs are registered
kubectl get crd certificates.cert-manager.io
```

### Destination cluster not reachable

If apps show `ComparisonError`, verify the destination cluster is registered with ArgoCD:

```bash
# For local cluster, use: https://kubernetes.default.svc
# List registered clusters
kubectl get secrets -n argocd -l argocd.argoproj.io/secret-type=cluster
```

### Deploying to a different environment

Replace `dev` with your target environment in all commands:

```bash
# Example for QA
kubectl apply -f apps/cert-manager/qa/app.yaml
kubectl apply -f apps/confluent-operator/qa/app.yaml
# ... etc.
```

Note that `qa`, `stg`, and `prd` environments use **manual sync** by default. You will need to trigger syncs manually via the ArgoCD UI or CLI after applying the Application resources.
