# Deploying on OpenShift with ArgoCD

This guide covers the **full end-to-end deployment** of **Confluent Platform**, **Confluent Flink Manager (CMF)**, and all supporting operators on **Red Hat OpenShift**, using the **OpenShift GitOps Operator** (built-in ArgoCD).

For generic Kubernetes instructions, see the main [README.md](README.md).

---

## Table of Contents

- [Prerequisites](#prerequisites)
- [Assumptions](#assumptions)
- [Repository Structure — OpenShift Files](#repository-structure--openshift-files)
- [Option A - OpenShift GitOps Operator (Recommended)](#option-a---openshift-gitops-operator-recommended)
  - [A1 - Install OpenShift GitOps Operator](#a1---install-openshift-gitops-operator)
  - [A2 - Verify OpenShift GitOps](#a2---verify-openshift-gitops)
  - [A3 - Access the ArgoCD UI](#a3---access-the-argocd-ui)
- [Option B - Standalone ArgoCD via Helm](#option-b---standalone-argocd-via-helm)
  - [B1 - Add Helm Repositories](#b1---add-helm-repositories)
  - [B2 - Install ArgoCD via Helm](#b2---install-argocd-via-helm)
  - [B3 - Create a Route for ArgoCD](#b3---create-a-route-for-argocd)
  - [B4 - Access the ArgoCD UI](#b4---access-the-argocd-ui)
- [Deploy the Full Stack](#deploy-the-full-stack)
  - [Step 1 - Create and Label Namespaces](#step-1---create-and-label-namespaces)
  - [Step 2 - Deploy OpenShift Prerequisites (SCCs)](#step-2---deploy-openshift-prerequisites-sccs)
  - [Step 3 - Deploy cert-manager](#step-3---deploy-cert-manager)
  - [Step 4 - Deploy Confluent Operator (CFK) and Flink Operator](#step-4---deploy-confluent-operator-cfk-and-flink-operator)
  - [Step 5 - Deploy Confluent Platform](#step-5---deploy-confluent-platform)
  - [Step 6 - Deploy Confluent Flink Manager (CMF)](#step-6---deploy-confluent-flink-manager-cmf)
- [Verify All Applications](#verify-all-applications)
- [Deployment Order](#deployment-order)
- [OpenShift Routes for External Access](#openshift-routes-for-external-access)
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
- The ApplicationSet files in `gitops-config/openshift/` contain **placeholder cluster URLs**. Update the `url` field in each ApplicationSet's generator list with your actual cluster API server endpoint (dev is pre-configured to `https://kubernetes.default.svc`).
- OpenShift may already have cert-manager installed via the Red Hat cert-manager Operator. If so, skip the cert-manager deployment step.

---

## Repository Structure — OpenShift Files

OpenShift-specific configuration lives in a separate directory tree, parallel to the vanilla Kubernetes config:

```
apps/
  cert-manager/openshift-overlay.yaml                          # Helm overrides (disable PSP)
  confluent-operator/openshift-overlay.yaml                    # Helm overrides (null security context)
  confluent-flink-operator/openshift-overlay.yaml              # Helm overrides (null security context)
  confluent-flink/openshift/{dev,qa,stg,prd}/manifests/
    confluent-flink-manager.yaml                               # CMF with namespace=openshift-gitops
  openshift-prereqs/{dev,qa,stg,prd}/manifests/
    confluent-scc.yaml                                         # Custom SCC (cluster-scoped)
    scc-bindings.yaml                                          # SA → SCC bindings (per-env)

gitops-config/openshift/{dev,qa,stg,prd}/
  cert-manager-application-set.yaml                            # Base values + openshift-overlay
  confluent-operator-application-set.yaml
  confluent-flink-operator-application-set.yaml
  confluent-platform-application-set.yaml                      # Points to SAME base CP manifests
  confluent-flink-application-set.yaml                         # Points to openshift CMF manifests
  openshift-prereqs-application-set.yaml                       # Deploys SCC + bindings

scripts/
  deploy-openshift-dev.sh                                      # Full OpenShift deploy
  destroy-openshift-dev.sh                                     # OpenShift teardown
```

**Key design decisions:**
- **Confluent Platform manifests are shared** — the OpenShift `confluent-platform-application-set.yaml` points to the same `apps/confluent-platform/<env>/manifests/` as vanilla K8s. CP CRDs contain no platform-specific config.
- **CMF manifests are separate** — they embed `namespace: openshift-gitops` (instead of `argocd`) which is a structural change that cannot be overlaid.
- **SCCs are declarative** — deployed via ArgoCD ApplicationSet instead of imperative `oc adm policy` commands. This makes SCCs GitOps-native, auditable, and versionable.

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

> **Note:** When using OpenShift GitOps, the ArgoCD namespace is `openshift-gitops` (not `argocd`). The ApplicationSets in `gitops-config/openshift/` are already configured with this namespace.

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

> **Important:** When using standalone ArgoCD, update `namespace: openshift-gitops` to `namespace: argocd` in all ApplicationSet files under `gitops-config/openshift/`.

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

## Deploy the Full Stack

These steps apply regardless of whether you used Option A or Option B. Set the namespace variable:

```bash
# Set this to match your ArgoCD namespace
ARGOCD_NS=openshift-gitops   # or "argocd" for standalone Helm installs
ENV=dev                       # Change to qa, stg, or prd as needed
```

### Step 1 - Create and Label Namespaces

OpenShift GitOps requires namespaces to be labeled before ArgoCD can manage them:

```bash
# Create namespaces
oc create namespace confluent-${ENV} --dry-run=client -o yaml | oc apply -f -
oc create namespace cert-manager --dry-run=client -o yaml | oc apply -f -

# Label for OpenShift GitOps management
oc label namespace confluent-${ENV} argocd.argoproj.io/managed-by=${ARGOCD_NS} --overwrite
oc label namespace cert-manager argocd.argoproj.io/managed-by=${ARGOCD_NS} --overwrite
```

### Step 2 - Deploy OpenShift Prerequisites (SCCs)

Deploy the custom Security Context Constraints and service account bindings. These are managed declaratively via an ArgoCD ApplicationSet:

```bash
oc apply -f gitops-config/openshift/${ENV}/openshift-prereqs-application-set.yaml
```

Wait for healthy:

```bash
oc wait --for=jsonpath='{.status.health.status}'=Healthy \
  application/openshift-prereqs-${ENV} -n ${ARGOCD_NS} --timeout=120s
```

This creates:
- **`confluent-scc`** — a custom SCC with `RunAsAny` for UID/GID/FSGroup, drops ALL capabilities, allows PVC/configMap/secret/emptyDir volumes
- **ClusterRoleBindings** — binds `default`, `confluent-operator`, and `flink-kubernetes-operator` service accounts in `confluent-${ENV}` (plus cert-manager service accounts in `cert-manager`) to the custom SCC

### Step 3 - Deploy cert-manager

cert-manager provides TLS certificates required by the Flink operator webhooks.

> **Note:** OpenShift may already have cert-manager installed. Check first:
> ```bash
> oc get pods -n cert-manager 2>/dev/null || oc get pods -n openshift-cert-manager 2>/dev/null
> ```
> If cert-manager is already running, skip this step.

```bash
oc apply -f gitops-config/openshift/${ENV}/cert-manager-application-set.yaml
```

Wait for healthy:

```bash
oc wait --for=jsonpath='{.status.health.status}'=Healthy \
  application/cert-manager-${ENV} -n ${ARGOCD_NS} --timeout=180s
```

Verify:

```bash
oc get pods -n cert-manager
```

Expected: 3 pods running (cert-manager, cainjector, webhook).

### Step 4 - Deploy Confluent Operator (CFK) and Flink Operator

```bash
oc apply -f gitops-config/openshift/${ENV}/confluent-operator-application-set.yaml
oc apply -f gitops-config/openshift/${ENV}/confluent-flink-operator-application-set.yaml
```

Wait for healthy:

```bash
oc wait --for=jsonpath='{.status.health.status}'=Healthy \
  application/confluent-operator-${ENV} \
  application/confluent-flink-operator-${ENV} \
  -n ${ARGOCD_NS} --timeout=180s
```

Verify:

```bash
oc get pods -n confluent-${ENV}
```

Expected:

```
confluent-operator-...                 1/1     Running
flink-kubernetes-operator-...          2/2     Running
```

### Step 5 - Deploy Confluent Platform

Deploy KRaft controllers, Kafka, Schema Registry, Connect, ksqlDB, and Control Center:

```bash
oc apply -f gitops-config/openshift/${ENV}/confluent-platform-application-set.yaml
```

Wait for healthy (Confluent Platform takes longer to provision):

```bash
oc wait --for=jsonpath='{.status.health.status}'=Healthy \
  application/confluent-platform-${ENV} -n ${ARGOCD_NS} --timeout=600s
```

Verify:

```bash
oc get pods -n confluent-${ENV}
```

Expected (dev): KRaftController, Kafka, SchemaRegistry, Connect, KsqlDB, and ControlCenter pods all `Running`.

> **Note:** The OpenShift ApplicationSet points to the **same** base manifests (`apps/confluent-platform/<env>/manifests/`) as vanilla Kubernetes. CP CRDs contain no platform-specific configuration.

### Step 6 - Deploy Confluent Flink Manager (CMF)

```bash
oc apply -f gitops-config/openshift/${ENV}/confluent-flink-application-set.yaml
```

Wait for healthy:

```bash
oc wait --for=jsonpath='{.status.health.status}'=Healthy \
  application/confluent-flink-${ENV} -n ${ARGOCD_NS} --timeout=300s
```

Verify the CMF nested Application:

```bash
oc get applications -n ${ARGOCD_NS} | grep flink-manager
```

> **Note:** CMF manifests are OpenShift-specific (under `apps/confluent-flink/openshift/<env>/manifests/`) because they embed `namespace: openshift-gitops` and null security contexts.

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
openshift-prereqs-dev           Healthy   Synced   openshift-gitops
cert-manager-dev                Healthy   Synced   cert-manager
confluent-operator-dev          Healthy   Synced   confluent-dev
confluent-flink-operator-dev    Healthy   Synced   confluent-dev
confluent-platform-dev          Healthy   Synced   confluent-dev
confluent-flink-dev             Healthy   Synced   confluent-dev
confluent-flink-manager-dev     Healthy   Synced   confluent-dev
```

---

## Deployment Order

```
┌─────────────────────────────────────────────┐
│  1. Create + Label Namespaces               │
│     (confluent-<env>, cert-manager)         │
└──────────────────┬──────────────────────────┘
                   │
┌──────────────────▼──────────────────────────┐
│  2. OpenShift Prerequisites                 │
│     (SCC + ClusterRoleBindings)             │
└──────────────────┬──────────────────────────┘
                   │
┌──────────────────▼──────────────────────────┐
│  3. cert-manager                            │
│     (skip if OpenShift-provided)            │
└──────────────────┬──────────────────────────┘
                   │
┌──────────────────▼──────────────────────────┐
│  4. Confluent Operator + Flink Operator     │
│     (deploy in parallel)                    │
└──────────────────┬──────────────────────────┘
                   │
┌──────────────────▼──────────────────────────┐
│  5. Confluent Platform                      │
│     (KRaft → Kafka → SR/Connect → ksqlDB)  │
└──────────────────┬──────────────────────────┘
                   │
┌──────────────────▼──────────────────────────┐
│  6. Confluent Flink Manager (CMF)           │
└─────────────────────────────────────────────┘
```

---

## OpenShift Routes for External Access

OpenShift uses Routes instead of Ingress/LoadBalancer for external access. Below are examples for exposing Confluent Platform services.

### Kafka Bootstrap Route

```yaml
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: kafka-bootstrap
  namespace: confluent-dev
spec:
  host: kafka-bootstrap.apps.example.com
  port:
    targetPort: external
  tls:
    termination: passthrough
  to:
    kind: Service
    name: kafka-bootstrap
```

### Schema Registry Route

```yaml
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: schemaregistry
  namespace: confluent-dev
spec:
  host: schema-registry.apps.example.com
  port:
    targetPort: external
  tls:
    termination: edge
  to:
    kind: Service
    name: schemaregistry
```

### Control Center Route

```yaml
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: controlcenter
  namespace: confluent-dev
spec:
  host: controlcenter.apps.example.com
  port:
    targetPort: external
  tls:
    termination: edge
  to:
    kind: Service
    name: controlcenter
```

> **Note:** Routes are optional and customer-specific. Adjust `host`, `tls.termination`, and `targetPort` to match your environment. For TLS passthrough, the service must terminate TLS. For edge termination, the Route handles TLS.

---

## OpenShift-Specific Considerations

### Security Context Constraints (SCCs)

OpenShift enforces Security Context Constraints (SCCs) that restrict pod security settings. This repository uses a **declarative approach** — a custom `confluent-scc` SCC and ClusterRoleBindings are deployed via the `openshift-prereqs` ArgoCD ApplicationSet.

The custom SCC (`apps/openshift-prereqs/<env>/manifests/confluent-scc.yaml`) provides:
- `runAsUser: RunAsAny` — allows containers to run as any UID
- `fsGroup: RunAsAny` — allows any fsGroup
- Drops ALL capabilities
- Allows volumes: configMap, emptyDir, PVC, projected, secret, downwardAPI

Service account bindings (`apps/openshift-prereqs/<env>/manifests/scc-bindings.yaml`) map:
- `default`, `confluent-operator`, `flink-kubernetes-operator` in `confluent-<env>` → `confluent-scc`
- `cert-manager`, `cert-manager-webhook`, `cert-manager-cainjector` in `cert-manager` → `confluent-scc`

**Manual alternative:** If you prefer imperative SCC commands instead of the declarative approach:

```bash
oc adm policy add-scc-to-user anyuid -z default -n confluent-${ENV}
oc adm policy add-scc-to-user anyuid -z confluent-operator -n confluent-${ENV}
oc adm policy add-scc-to-user anyuid -z flink-kubernetes-operator -n confluent-${ENV}
oc adm policy add-scc-to-user anyuid -z cert-manager -n cert-manager
oc adm policy add-scc-to-user anyuid -z cert-manager-webhook -n cert-manager
oc adm policy add-scc-to-user anyuid -z cert-manager-cainjector -n cert-manager
```

> **Tip:** Start with `restricted-v2` (OpenShift default) and only escalate to the custom SCC if pods fail to start with `CrashLoopBackOff` or `CreateContainerConfigError` due to security context violations. Check pod events for details: `oc describe pod <pod-name> -n <namespace>`.

### OpenShift GitOps Namespace Restrictions

By default, the OpenShift GitOps ArgoCD instance can only manage resources in its own namespace (`openshift-gitops`). To deploy to other namespaces, you must grant permissions.

**Option 1 - Label managed namespaces (recommended):**

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
- Update ApplicationSet paths from `gitops-config/aws-us-east-2/` to `gitops-config/openshift/`

See the main [README.md](README.md#cicd-pipelines) for full pipeline documentation.

---

## Quick Deploy Script (OpenShift)

A full deploy script is available for the dev environment:

```bash
./scripts/deploy-openshift-dev.sh
```

This script automates all deployment steps:
1. Verifies OpenShift GitOps Operator is running
2. Creates and labels namespaces
3. Deploys OpenShift prerequisites (SCC + bindings)
4. Deploys cert-manager (skips if already installed)
5. Deploys Confluent Operator and Flink Operator
6. Deploys Confluent Platform
7. Deploys Confluent Flink Manager (CMF)
8. Prints deployment summary and ArgoCD access info

To tear down:

```bash
./scripts/destroy-openshift-dev.sh
```

---

## Troubleshooting

### Pods stuck in CrashLoopBackOff due to SCC

```
Error: container has runAsNonRoot and image will run as root
```

Verify the SCC prerequisites were deployed:

```bash
oc get scc confluent-scc
oc get clusterrolebinding | grep confluent-scc
```

If the SCC exists but pods still fail, check which SCC is being used:

```bash
oc get pod <pod-name> -n <namespace> -o jsonpath='{.metadata.annotations.openshift\.io/scc}'
```

If it shows `restricted-v2` instead of `confluent-scc`, the ClusterRoleBinding may be missing for that service account.

### ArgoCD cannot create resources in target namespace

```
Namespace "confluent-dev" for Application ... is not managed
```

Label the namespace for OpenShift GitOps:

```bash
oc label namespace confluent-dev argocd.argoproj.io/managed-by=openshift-gitops
```

### Confluent Platform pods stuck in Pending

```
0/3 nodes are available: pod has unbound immediate PersistentVolumeClaims
```

Verify that your OpenShift cluster has a default StorageClass:

```bash
oc get storageclass
```

If no default StorageClass is set, add `storageClassName` to the CP manifests or set one as default.

### CMF Application shows "Missing" in ArgoCD

The CMF manifest creates a nested ArgoCD Application. Ensure the `openshift-gitops` namespace is accessible:

```bash
oc get application confluent-flink-manager-${ENV} -n openshift-gitops
```

If the Application exists but shows `Unknown`, the Helm chart repository may be unreachable. Check ArgoCD repo-server logs:

```bash
oc logs deployment/openshift-gitops-repo-server -n openshift-gitops
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
