# Deploying into an Existing OpenShift GitOps / ArgoCD

This guide provides step-by-step instructions for deploying the Confluent and Flink operators into an OpenShift cluster that **already has ArgoCD running** (via OpenShift GitOps Operator or standalone).

If you need to install ArgoCD from scratch, see the main [README.md](README.md).

---

## Table of Contents

- [Prerequisites](#prerequisites)
- [Assumptions](#assumptions)
- [Deployment Order](#deployment-order)
- [Step 1 - Verify ArgoCD Is Running](#step-1---verify-argocd-is-running)
- [Step 2 - Clone This Repository](#step-2---clone-this-repository)
- [Step 3 - Review and Customize ApplicationSet Definitions](#step-3---review-and-customize-applicationset-definitions)
- [Step 4 - Create and Label Namespaces](#step-4---create-and-label-namespaces)
- [Step 5 - Apply OpenShift Prerequisites (SCCs)](#step-5---apply-openshift-prerequisites-sccs)
- [Step 6 - Deploy cert-manager](#step-6---deploy-cert-manager)
- [Step 7 - Deploy Confluent Operator (CFK) and Flink Operator](#step-7---deploy-confluent-operator-cfk-and-flink-operator)
- [Verify All Applications](#verify-all-applications)
- [CI/CD Pipelines](#cicd-pipelines)
- [Quick Deploy Script](#quick-deploy-script)
- [Troubleshooting](#troubleshooting)

---

## Prerequisites

| Requirement | Details |
|-------------|---------|
| **ArgoCD** | Running and accessible (OpenShift GitOps in `openshift-gitops` or standalone in custom namespace) |
| **oc / kubectl** | Configured with access to the target cluster |
| **Cluster access** | Permissions to create namespaces, CRDs, SCCs, and ArgoCD ApplicationSet resources |

Verify your cluster connectivity:

```bash
oc cluster-info
oc get pods -n openshift-gitops   # or your ArgoCD namespace
```

---

## Assumptions

- ArgoCD is **already installed and healthy** on the target OpenShift cluster. If not, see the main [README.md](README.md).
- The deploying user has permissions to create ArgoCD `ApplicationSet` resources in the ArgoCD namespace and create namespaces/SCCs on the cluster.
- Helm chart repositories (`charts.jetstack.io`, `packages.confluent.io`) are reachable from the cluster.
- The ApplicationSet files in `gitops-config/openshift/` are configured with `namespace: openshift-gitops`. If ArgoCD is in a different namespace, update accordingly.
- The ApplicationSet files contain **placeholder cluster URLs**. Update the `url` field in each ApplicationSet's generator list with your actual cluster API server endpoint.

---

## Deployment Order

```
Namespaces + Labels  -->  SCCs (direct oc apply)  -->  cert-manager  -->  Operators (CFK + Flink)
```

- **Namespaces** must be created and labeled before ArgoCD can manage them.
- **SCCs** must be applied directly (one-time cluster prerequisite, not an ArgoCD app).
- **cert-manager** must be healthy before the Flink operator (webhook certificates).
- **Confluent Operator** and **Flink Operator** can be deployed in parallel after cert-manager.

---

## Step 1 - Verify ArgoCD Is Running

```bash
# Check ArgoCD pods
oc get pods -n openshift-gitops

# Verify the ApplicationSet CRD exists
oc get crd applicationsets.argoproj.io
```

Expected: All ArgoCD pods in `Running` state and the `applicationsets.argoproj.io` CRD exists.

---

## Step 2 - Clone This Repository

```bash
git clone <your-repo-url>
cd <repo-directory>
```

---

## Step 3 - Review and Customize ApplicationSet Definitions

Set environment variables:

```bash
ARGOCD_NS=openshift-gitops   # Update if ArgoCD is in a different namespace
ENV=dev                       # Change to qa, stg, or prd as needed
```

Key fields to check in each ApplicationSet under `gitops-config/openshift/${ENV}/`:

| Field | What to verify |
|-------|----------------|
| `metadata.namespace` | Must match your ArgoCD namespace (default: `openshift-gitops`) |
| Generator `url` | Must point to your target cluster API server |
| `spec.template.spec.destination.namespace` | Target namespace for the application |

---

## Step 4 - Create and Label Namespaces

```bash
oc create namespace confluent-${ENV} --dry-run=client -o yaml | oc apply -f -
oc create namespace cert-manager --dry-run=client -o yaml | oc apply -f -

oc label namespace confluent-${ENV} argocd.argoproj.io/managed-by=${ARGOCD_NS} --overwrite
oc label namespace cert-manager argocd.argoproj.io/managed-by=${ARGOCD_NS} --overwrite
```

---

## Step 5 - Apply OpenShift Prerequisites (SCCs)

Apply the SCC and ClusterRoleBindings directly (one-time cluster prerequisite, not managed by ArgoCD):

```bash
oc apply -f openshift-prereqs/${ENV}/manifests/
```

Verify:

```bash
oc get scc confluent-scc
oc get clusterrolebinding | grep confluent-scc
```

---

## Step 6 - Deploy cert-manager

> **Note:** Skip if OpenShift already has cert-manager running:
> ```bash
> oc get pods -n cert-manager 2>/dev/null || oc get pods -n openshift-cert-manager 2>/dev/null
> ```

```bash
oc apply -f gitops-config/openshift/${ENV}/cert-manager-application-set.yaml
oc wait --for=jsonpath='{.status.health.status}'=Healthy \
  application/cert-manager-${ENV} -n ${ARGOCD_NS} --timeout=180s
```

---

## Step 7 - Deploy Confluent Operator (CFK) and Flink Operator

```bash
oc apply -f gitops-config/openshift/${ENV}/confluent-operator-application-set.yaml
oc apply -f gitops-config/openshift/${ENV}/confluent-flink-operator-application-set.yaml
oc wait --for=jsonpath='{.status.health.status}'=Healthy \
  application/confluent-operator-${ENV} \
  application/confluent-flink-operator-${ENV} \
  -n ${ARGOCD_NS} --timeout=180s
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

## CI/CD Pipelines

The **"Deploy Operators"** pipeline scenario is designed for this use case (existing ArgoCD).

| Platform | Pipeline File |
|----------|--------------|
| **GitHub Actions** | [`.github/workflows/deploy-operators.yaml`](.github/workflows/deploy-operators.yaml) |
| **Azure DevOps** | [`.azure-pipelines/deploy-operators.yaml`](.azure-pipelines/deploy-operators.yaml) |

Adapt for OpenShift:
- Use `oc login` for cluster authentication
- Set `argocd_namespace` to `openshift-gitops`
- Update ApplicationSet paths to `gitops-config/openshift/`

---

## Quick Deploy Script

```bash
./scripts/deploy-openshift-dev.sh
```

This script handles all steps including namespace creation, labeling, SCC deployment, and operator installation. See the main [README.md](README.md#quick-deploy-script) for details.

---

## Troubleshooting

### ArgoCD namespace mismatch

If you see `Error from server (NotFound): applications.argoproj.io "..." not found`, ArgoCD may be in a different namespace. Update `metadata.namespace` in each ApplicationSet file:

```bash
oc get pods --all-namespaces | grep argocd
```

### Application stuck in "Unknown" health

Check ArgoCD controller logs:

```bash
oc logs -n openshift-gitops -l app.kubernetes.io/name=openshift-gitops-application-controller --tail=50
```

### SCC-related pod failures

```bash
oc get scc confluent-scc
oc get pod <pod-name> -n <namespace> -o jsonpath='{.metadata.annotations.openshift\.io/scc}'
```

### cert-manager CRDs not ready

```bash
oc get pods -n cert-manager -l app.kubernetes.io/component=webhook
oc get crd certificates.cert-manager.io
```

### Deploying to a different environment

Replace `dev` with your target environment:

```bash
for file in gitops-config/openshift/qa/*.yaml; do
  oc apply -f "$file"
done
```

Note that `qa`, `stg`, and `prd` use **manual sync**. Trigger syncs via the ArgoCD UI or CLI.
