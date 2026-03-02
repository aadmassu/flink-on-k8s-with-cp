# Deploying on OpenShift with ArgoCD

This guide covers deploying **cert-manager**, **Confluent Operator (CFK)**, and **Flink Operator** on **Red Hat OpenShift**, using either the **OpenShift GitOps Operator** (built-in ArgoCD) or a **standalone ArgoCD** installation.

For generic Kubernetes instructions, see the main [README.md](README.md).

> **Current scope:** This guide covers operator installation only. Confluent Platform CRDs and Confluent Flink Manager deployment will be covered in a future update.

---

## Table of Contents

- [Prerequisites](#prerequisites)
- [Assumptions](#assumptions)
- [Option A - OpenShift GitOps Operator (Recommended)](#option-a---openshift-gitops-operator-recommended)
  - [A1 - Install OpenShift GitOps Operator](#a1---install-openshift-gitops-operator)
  - [A2 - Verify OpenShift GitOps](#a2---verify-openshift-gitops)
  - [A3 - Access the ArgoCD UI](#a3---access-the-argocd-ui)
- [Option B - Standalone ArgoCD via Helm](#option-b---standalone-argocd-via-helm)
  - [B1 - Add Helm Repositories](#b1---add-helm-repositories)
  - [B2 - Install ArgoCD via Helm](#b2---install-argocd-via-helm)
  - [B3 - Create a Route for ArgoCD](#b3---create-a-route-for-argocd)
  - [B4 - Access the ArgoCD UI](#b4---access-the-argocd-ui)
- [Deploy the Operators](#deploy-the-operators)
  - [Step 1 - Prepare App Definitions for OpenShift](#step-1---prepare-app-definitions-for-openshift)
  - [Step 2 - Deploy cert-manager](#step-2---deploy-cert-manager)
  - [Step 3 - Deploy Confluent Operator (CFK)](#step-3---deploy-confluent-operator-cfk)
  - [Step 4 - Deploy Flink Operator](#step-4---deploy-flink-operator)
- [Verify All Applications](#verify-all-applications)
- [OpenShift-Specific Considerations](#openshift-specific-considerations)
  - [Security Context Constraints (SCCs)](#security-context-constraints-sccs)
  - [OpenShift GitOps Namespace Restrictions](#openshift-gitops-namespace-restrictions)
  - [cert-manager on OpenShift](#cert-manager-on-openshift)
- [CI/CD Pipelines](#cicd-pipelines)
- [Quick Deploy Script (OpenShift)](#quick-deploy-script-openshift)
- [Troubleshooting](#troubleshooting)

---

## Prerequisites

| Requirement | Details |
|-------------|---------|
| **OpenShift** | 4.12+ cluster with cluster-admin access |
| **oc** | OpenShift CLI, logged in (`oc login`) |
| **kubectl** | 1.28+ (bundled with `oc`) |
| **helm** | 3.14+ / 4.x |

Verify connectivity:

```bash
oc whoami
oc cluster-info
oc version
```

---

## Assumptions

- An OpenShift 4.12+ cluster is provisioned and accessible via `oc` CLI.
- The deploying user or service account has **cluster-admin** privileges (required for creating namespaces, CRDs, SCCs, and ClusterRoles).
- Helm chart repositories (`charts.jetstack.io`, `packages.confluent.io`) are reachable from the cluster.
- The `app.yaml` files contain **placeholder values** for `spec.destination.server`. Update these with your actual cluster API server endpoint (use `https://kubernetes.default.svc` for the local cluster).
- If using OpenShift GitOps (Option A), you must update `metadata.namespace` from `argocd` to `openshift-gitops` in each `app.yaml`.
- OpenShift may already have cert-manager installed via the Red Hat cert-manager Operator. If so, skip the cert-manager deployment step.

---

## Option A - OpenShift GitOps Operator (Recommended)

The OpenShift GitOps Operator provides a supported, integrated ArgoCD instance managed by Red Hat.

### A1 - Install OpenShift GitOps Operator

Install the operator from OperatorHub via the CLI:

```bash
oc apply -f - <<EOF
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: openshift-gitops-operator
  namespace: openshift-operators
spec:
  channel: latest
  installPlanApproval: Automatic
  name: openshift-gitops-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF
```

Wait for the operator to install:

```bash
oc wait --for=condition=Ready pod -l app.kubernetes.io/name=openshift-gitops-operator \
  -n openshift-operators --timeout=120s
```

The operator automatically creates an ArgoCD instance in the `openshift-gitops` namespace.

### A2 - Verify OpenShift GitOps

```bash
# Check the ArgoCD instance is running
oc get pods -n openshift-gitops

# Verify the ArgoCD server
oc get argocd -n openshift-gitops
```

Expected: ArgoCD controller, server, repo-server, redis, and dex pods all `Running`.

### A3 - Access the ArgoCD UI

OpenShift GitOps automatically creates a Route:

```bash
# Get the ArgoCD URL
oc get route openshift-gitops-server -n openshift-gitops -o jsonpath='{.spec.host}'
```

Retrieve the admin password:

```bash
oc -n openshift-gitops get secret openshift-gitops-cluster -o jsonpath='{.data.admin\.password}' | base64 -d
```

| Field | Value |
|-------|-------|
| **URL** | `https://<route-hostname>` from the command above |
| **Username** | `admin` |
| **Password** | Retrieved from the secret above |

> **Note:** When using OpenShift GitOps, the ArgoCD namespace is `openshift-gitops` (not `argocd`). You will need to update the `metadata.namespace` field in each `app.yaml` accordingly.

---

## Option B - Standalone ArgoCD via Helm

Use this option if you prefer to manage ArgoCD independently of the OpenShift GitOps Operator.

### B1 - Add Helm Repositories

```bash
helm repo add argo-cd https://argoproj.github.io/argo-helm
helm repo add confluent https://packages.confluent.io/helm
helm repo add jetstack https://charts.jetstack.io
helm repo update
```

### B2 - Install ArgoCD via Helm

```bash
# Create the namespace
oc new-project argocd || oc project argocd

# Install ArgoCD
helm install argocd argo-cd/argo-cd \
  --namespace argocd \
  -f apps/argocd/dev/values.yaml \
  --wait --timeout 5m
```

Verify:

```bash
oc get pods -n argocd
```

### B3 - Create a Route for ArgoCD

OpenShift uses Routes instead of LoadBalancer services. Create a passthrough Route to expose the ArgoCD UI:

```bash
oc create route passthrough argocd-server \
  --service=argocd-server \
  --port=https \
  --namespace=argocd
```

### B4 - Access the ArgoCD UI

```bash
# Get the Route URL
oc get route argocd-server -n argocd -o jsonpath='{.spec.host}'
```

Retrieve the admin password:

```bash
oc -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

---

## Deploy the Operators

These steps apply regardless of whether you used Option A or Option B. The only difference is the ArgoCD namespace:

| ArgoCD Install Method | Namespace |
|----------------------|-----------|
| OpenShift GitOps (Option A) | `openshift-gitops` |
| Standalone Helm (Option B) | `argocd` |

Set the namespace variable for the commands below:

```bash
# Set this to match your ArgoCD namespace
ARGOCD_NS=openshift-gitops   # or "argocd" for standalone Helm installs
ENV=dev                       # Change to qa, stg, or prd as needed
```

### Step 1 - Prepare App Definitions for OpenShift

If using OpenShift GitOps (Option A), update the namespace in each `app.yaml` to `openshift-gitops`:

```bash
# Update namespace in all app.yaml files for your environment
for app in cert-manager confluent-operator confluent-flink-operator; do
  sed -i "s/namespace: argocd/namespace: ${ARGOCD_NS}/" apps/${app}/${ENV}/app.yaml
done
```

> **Important:** Also verify that `spec.destination.server` is set to `https://kubernetes.default.svc` for deploying to the local cluster.

### Step 2 - Deploy cert-manager

cert-manager provides TLS certificates required by the Flink operator webhooks.

> **Note:** OpenShift may already have cert-manager installed. Check first:
> ```bash
> oc get pods -n cert-manager 2>/dev/null || oc get pods -n openshift-cert-manager 2>/dev/null
> ```
> If cert-manager is already running, skip this step.

```bash
oc apply -f apps/cert-manager/${ENV}/app.yaml
```

Wait for it to become healthy:

```bash
oc wait --for=jsonpath='{.status.health.status}'=Healthy \
  application/cert-manager-${ENV} -n ${ARGOCD_NS} --timeout=180s
```

Verify:

```bash
oc get pods -n cert-manager
```

Expected: 3 pods running (cert-manager, cainjector, webhook).

### Step 3 - Deploy Confluent Operator (CFK)

```bash
oc apply -f apps/confluent-operator/${ENV}/app.yaml
```

Wait for healthy:

```bash
oc wait --for=jsonpath='{.status.health.status}'=Healthy \
  application/confluent-operator-${ENV} -n ${ARGOCD_NS} --timeout=180s
```

### Step 4 - Deploy Flink Operator

Requires cert-manager to be running.

```bash
oc apply -f apps/confluent-flink-operator/${ENV}/app.yaml
```

Wait for healthy:

```bash
oc wait --for=jsonpath='{.status.health.status}'=Healthy \
  application/confluent-flink-operator-${ENV} -n ${ARGOCD_NS} --timeout=180s
```

Verify both operators:

```bash
oc get pods -n confluent-${ENV}
```

Expected:

```
confluent-operator-...                 1/1     Running
flink-kubernetes-operator-...          2/2     Running
```

---

## Verify All Applications

```bash
oc get applications -n ${ARGOCD_NS} -o custom-columns=\
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
```

---

## OpenShift-Specific Considerations

### Security Context Constraints (SCCs)

OpenShift enforces Security Context Constraints (SCCs) that restrict pod security settings. Some components may need elevated SCCs.

**Grant the required SCC to service accounts:**

```bash
# Confluent operator
oc adm policy add-scc-to-user anyuid -z default -n confluent-${ENV}
oc adm policy add-scc-to-user anyuid -z confluent-operator -n confluent-${ENV}

# Flink operator
oc adm policy add-scc-to-user anyuid -z flink-kubernetes-operator -n confluent-${ENV}

# cert-manager
oc adm policy add-scc-to-user anyuid -z cert-manager -n cert-manager
oc adm policy add-scc-to-user anyuid -z cert-manager-webhook -n cert-manager
oc adm policy add-scc-to-user anyuid -z cert-manager-cainjector -n cert-manager
```

> **Tip:** Start with `restricted-v2` (OpenShift default) and only escalate to `anyuid` or `nonroot-v2` if pods fail to start with `CrashLoopBackOff` or `CreateContainerConfigError` due to security context violations. Check pod events for details: `oc describe pod <pod-name> -n <namespace>`.

### OpenShift GitOps Namespace Restrictions

By default, the OpenShift GitOps ArgoCD instance can only manage resources in its own namespace (`openshift-gitops`). To deploy to other namespaces, you must grant permissions.

**Option 1 - Label managed namespaces:**

```bash
oc label namespace confluent-${ENV} argocd.argoproj.io/managed-by=openshift-gitops
oc label namespace cert-manager argocd.argoproj.io/managed-by=openshift-gitops
```

**Option 2 - Grant cluster-admin to the ArgoCD controller:**

```bash
oc adm policy add-cluster-role-to-user cluster-admin \
  system:serviceaccount:openshift-gitops:openshift-gitops-argocd-application-controller
```

> **Note:** Option 2 gives ArgoCD broad cluster access. Use Option 1 for a more restricted approach.

### cert-manager on OpenShift

OpenShift 4.x may include a built-in cert-manager via the **cert-manager Operator for Red Hat OpenShift**. If it is already installed:

1. Check for existing installation:
   ```bash
   oc get pods -n cert-manager 2>/dev/null
   oc get pods -n openshift-cert-manager 2>/dev/null
   ```

2. If cert-manager is already running, **skip the cert-manager deployment step**. The existing installation will satisfy the Flink operator's webhook certificate requirements.

3. If you deploy your own cert-manager alongside the OpenShift-provided one, there may be conflicts. Avoid running two cert-manager instances.

---

## CI/CD Pipelines

This repository includes CI/CD pipeline definitions that can be adapted for OpenShift deployments.

| Platform | Scenario | Pipeline File |
|----------|----------|--------------|
| **GitHub Actions** | Full Deploy (ArgoCD + Operators) | [`.github/workflows/full-deploy.yaml`](../.github/workflows/full-deploy.yaml) |
| **GitHub Actions** | Deploy Operators (Existing ArgoCD) | [`.github/workflows/deploy-operators.yaml`](../.github/workflows/deploy-operators.yaml) |
| **Azure DevOps** | Full Deploy (ArgoCD + Operators) | [`.azure-pipelines/full-deploy.yaml`](../.azure-pipelines/full-deploy.yaml) |
| **Azure DevOps** | Deploy Operators (Existing ArgoCD) | [`.azure-pipelines/deploy-operators.yaml`](../.azure-pipelines/deploy-operators.yaml) |

**OpenShift adaptation notes:**
- Update the cluster authentication step to use `oc login` with a service account token
- If using OpenShift GitOps, set `argocd_namespace` to `openshift-gitops`
- Add SCC and namespace labeling steps before deploying operators

See the main [README.md](README.md#cicd-pipelines) for full pipeline documentation.

---

## Quick Deploy Script (OpenShift)

```bash
ENV=dev
ARGOCD_NS=openshift-gitops   # or "argocd" for standalone Helm installs

# Update namespace in app definitions (only needed for OpenShift GitOps)
if [ "${ARGOCD_NS}" != "argocd" ]; then
  for app in cert-manager confluent-operator confluent-flink-operator; do
    sed -i "s/namespace: argocd/namespace: ${ARGOCD_NS}/" apps/${app}/${ENV}/app.yaml
  done
fi

# Grant SCC permissions
oc adm policy add-scc-to-user anyuid -z default -n confluent-${ENV}
oc adm policy add-scc-to-user anyuid -z confluent-operator -n confluent-${ENV}
oc adm policy add-scc-to-user anyuid -z flink-kubernetes-operator -n confluent-${ENV}

# Label namespaces for OpenShift GitOps access
oc create namespace confluent-${ENV} --dry-run=client -o yaml | oc apply -f -
oc create namespace cert-manager --dry-run=client -o yaml | oc apply -f -
oc label namespace confluent-${ENV} argocd.argoproj.io/managed-by=${ARGOCD_NS} --overwrite
oc label namespace cert-manager argocd.argoproj.io/managed-by=${ARGOCD_NS} --overwrite

# 1. cert-manager (skip if already installed on OpenShift)
if ! oc get pods -n cert-manager 2>/dev/null | grep -q Running; then
  oc apply -f apps/cert-manager/${ENV}/app.yaml
  oc wait --for=jsonpath='{.status.health.status}'=Healthy \
    application/cert-manager-${ENV} -n ${ARGOCD_NS} --timeout=180s
else
  echo "cert-manager already running, skipping..."
fi

# 2. Both operators
oc apply -f apps/confluent-operator/${ENV}/app.yaml
oc apply -f apps/confluent-flink-operator/${ENV}/app.yaml
oc wait --for=jsonpath='{.status.health.status}'=Healthy \
  application/confluent-operator-${ENV} \
  application/confluent-flink-operator-${ENV} \
  -n ${ARGOCD_NS} --timeout=180s

# 3. Verify
echo ""
echo "=== All Applications ==="
oc get applications -n ${ARGOCD_NS}
echo ""
echo "=== ArgoCD URL ==="
oc get route -n ${ARGOCD_NS} -o jsonpath='{.items[0].spec.host}' 2>/dev/null || echo "No route found"
```

---

## Troubleshooting

### Pods stuck in CrashLoopBackOff due to SCC

```
Error: container has runAsNonRoot and image will run as root
```

Grant the appropriate SCC to the service account:

```bash
# Check which service account the pod uses
oc get pod <pod-name> -n <namespace> -o jsonpath='{.spec.serviceAccountName}'

# Grant anyuid SCC
oc adm policy add-scc-to-user anyuid -z <service-account> -n <namespace>
```

### ArgoCD cannot create resources in target namespace

```
Namespace "confluent-dev" for Application ... is not managed
```

Label the namespace for OpenShift GitOps:

```bash
oc label namespace confluent-dev argocd.argoproj.io/managed-by=openshift-gitops
```

### OpenShift GitOps admin password not working

The password secret name differs from standalone ArgoCD:

```bash
# OpenShift GitOps
oc -n openshift-gitops get secret openshift-gitops-cluster -o jsonpath='{.data.admin\.password}' | base64 -d

# Standalone ArgoCD
oc -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

### Flink operator fails - cert-manager CRDs not found

```
no matches for kind "Certificate" in version "cert-manager.io/v1"
```

Ensure cert-manager is fully running before deploying the Flink operator:

```bash
oc get pods -n cert-manager
oc get crd certificates.cert-manager.io
```

### Route not created automatically

If using standalone ArgoCD (Option B), create the Route manually:

```bash
oc create route passthrough argocd-server \
  --service=argocd-server \
  --port=https \
  --namespace=argocd
```

### Checking ArgoCD Application status

```bash
# List all applications
oc get applications -n ${ARGOCD_NS}

# Describe a specific application
oc describe application confluent-operator-dev -n ${ARGOCD_NS}

# Get sync status
oc get application confluent-operator-dev -n ${ARGOCD_NS} -o jsonpath='{.status.sync.status}'
```
