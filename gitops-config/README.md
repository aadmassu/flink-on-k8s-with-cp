# GitOps Config -- ArgoCD ApplicationSet Definitions

This directory contains **ArgoCD ApplicationSet** definitions that drive the multi-cluster, multi-platform deployment of Confluent Platform and Confluent Flink on Kubernetes. ApplicationSets are organized by **platform** (the target Kubernetes distribution) and **environment** (dev, qa, stg, prd), enabling a single Git repository to declaratively manage deployments across all clusters.

Each ApplicationSet uses a **list generator** to enumerate target clusters. When applied to the ArgoCD management cluster, it produces one ArgoCD `Application` resource per cluster entry, substituting template variables (`{{cluster}}`, `{{url}}`, `{{environment}}`) into the generated Application spec.

---

## Table of Contents

- [Directory Structure](#directory-structure)
- [Platforms](#platforms)
- [Platform Comparison](#platform-comparison)
- [Environments and Sync Policies](#environments-and-sync-policies)
- [ApplicationSet Types](#applicationset-types)
- [Deployment Order](#deployment-order)
- [File Naming Convention](#file-naming-convention)
- [How ApplicationSets Work](#how-applicationsets-work)
- [Usage](#usage)
- [Cross-References](#cross-references)

---

## Directory Structure

```
gitops-config/
|-- README.md                          # <-- You are here
|
|-- aws-us-east-2/                     # Platform: vanilla Kubernetes on AWS (us-east-2 region)
|   |-- dev/
|   |   |-- cert-manager-application-set.yaml
|   |   |-- confluent-operator-application-set.yaml
|   |   |-- confluent-flink-operator-application-set.yaml
|   |   |-- confluent-platform-application-set.yaml
|   |   +-- confluent-flink-application-set.yaml
|   |-- qa/
|   |   |-- cert-manager-application-set.yaml
|   |   |-- confluent-operator-application-set.yaml
|   |   |-- confluent-flink-operator-application-set.yaml
|   |   |-- confluent-platform-application-set.yaml
|   |   +-- confluent-flink-application-set.yaml
|   |-- stg/
|   |   |-- cert-manager-application-set.yaml
|   |   |-- confluent-operator-application-set.yaml
|   |   |-- confluent-flink-operator-application-set.yaml
|   |   |-- confluent-platform-application-set.yaml
|   |   +-- confluent-flink-application-set.yaml
|   +-- prd/
|       |-- cert-manager-application-set.yaml
|       |-- confluent-operator-application-set.yaml
|       |-- confluent-flink-operator-application-set.yaml
|       |-- confluent-platform-application-set.yaml
|       +-- confluent-flink-application-set.yaml
|
+-- openshift/                         # Platform: Red Hat OpenShift
    |-- dev/
    |   |-- openshift-prereqs-application-set.yaml
    |   |-- cert-manager-application-set.yaml
    |   |-- confluent-operator-application-set.yaml
    |   |-- confluent-flink-operator-application-set.yaml
    |   |-- confluent-platform-application-set.yaml
    |   +-- confluent-flink-application-set.yaml
    |-- qa/
    |   |-- openshift-prereqs-application-set.yaml
    |   |-- cert-manager-application-set.yaml
    |   |-- confluent-operator-application-set.yaml
    |   |-- confluent-flink-operator-application-set.yaml
    |   |-- confluent-platform-application-set.yaml
    |   +-- confluent-flink-application-set.yaml
    |-- stg/
    |   |-- openshift-prereqs-application-set.yaml
    |   |-- cert-manager-application-set.yaml
    |   |-- confluent-operator-application-set.yaml
    |   |-- confluent-flink-operator-application-set.yaml
    |   |-- confluent-platform-application-set.yaml
    |   +-- confluent-flink-application-set.yaml
    +-- prd/
        |-- openshift-prereqs-application-set.yaml
        |-- cert-manager-application-set.yaml
        |-- confluent-operator-application-set.yaml
        |-- confluent-flink-operator-application-set.yaml
        |-- confluent-platform-application-set.yaml
        +-- confluent-flink-application-set.yaml
```

**File counts:**

| Platform | Files per environment | Total files |
|---|---|---|
| `aws-us-east-2` | 5 | 20 |
| `openshift` | 6 (includes `openshift-prereqs`) | 24 |

---

## Platforms

### `aws-us-east-2/` -- Vanilla Kubernetes on AWS

Targets standard (non-OpenShift) Kubernetes clusters running in the **AWS us-east-2** region. Uses the community ArgoCD installation with namespace `argocd`. Helm-based ApplicationSets reference only the per-environment `values.yaml` files -- no platform overlay is needed.

### `openshift/` -- Red Hat OpenShift

Targets OpenShift clusters managed by **OpenShift GitOps** (the Red Hat-supported ArgoCD distribution). Key differences from the AWS variant:

- ArgoCD namespace is `openshift-gitops` instead of `argocd`.
- Helm-based charts layer an **OpenShift overlay** values file on top of the per-environment values (e.g., `openshift-overlay.yaml`).
- An additional `openshift-prereqs` ApplicationSet deploys platform prerequisites (SCCs, ClusterRoles, etc.) that are specific to OpenShift.
- The `confluent-flink` ApplicationSet sources manifests from an OpenShift-specific path (`apps/confluent-flink/openshift/{{environment}}/manifests`) rather than the generic path.

---

## Platform Comparison

| Aspect | `aws-us-east-2` | `openshift` |
|---|---|---|
| **ArgoCD namespace** | `argocd` | `openshift-gitops` |
| **ArgoCD distribution** | Community ArgoCD | OpenShift GitOps (Red Hat) |
| **ApplicationSets per env** | 5 | 6 (adds `openshift-prereqs`) |
| **Helm overlay files** | None (env values only) | `openshift-overlay.yaml` for cert-manager, confluent-operator, confluent-flink-operator |
| **Confluent Flink manifests path** | `apps/confluent-flink/{{environment}}/manifests` | `apps/confluent-flink/openshift/{{environment}}/manifests` |
| **Confluent Platform manifests path** | `apps/confluent-platform/{{environment}}/manifests` | `apps/confluent-platform/{{environment}}/manifests` (same) |
| **Cluster URL pattern (dev)** | `https://kubernetes.default.svc` (in-cluster) | `https://kubernetes.default.svc` (in-cluster) |
| **Cluster URL pattern (qa)** | `https://qa-cluster.aws-us-east-2.example.com` | `https://qa-cluster.aws-us-east-2.example.com` |
| **Cluster URL pattern (stg)** | `https://stg-cluster.aws-us-east-2.example.com` | `https://stg-cluster.aws-us-east-2.example.com` |
| **Cluster URL pattern (prd)** | `https://prd-cluster.aws-us-east-2.example.com` | `https://prd-cluster.aws-us-east-2.example.com` |

### OpenShift Overlay Files

The following Helm-based ApplicationSets in the `openshift/` platform include an additional overlay values file that adjusts configuration for OpenShift compatibility (e.g., security contexts, service account annotations, route/ingress configuration):

| ApplicationSet | Overlay file referenced |
|---|---|
| `cert-manager` | `apps/cert-manager/openshift-overlay.yaml` |
| `confluent-operator` | `apps/confluent-operator/openshift-overlay.yaml` |
| `confluent-flink-operator` | `apps/confluent-flink-operator/openshift-overlay.yaml` |

The `confluent-platform` and `confluent-flink` ApplicationSets do not use Helm overlays -- they source raw Kubernetes manifests from Git directories instead.

---

## Environments and Sync Policies

Each platform contains four environment subdirectories. The key difference across environments is the **sync policy** and the **target cluster URL**.

| Environment | Directory | Sync Policy | Cluster URL | Description |
|---|---|---|---|---|
| **dev** | `dev/` | **Automated** (`prune: true`, `selfHeal: true`) | `https://kubernetes.default.svc` (in-cluster) | Development -- changes sync automatically, drift is auto-corrected |
| **qa** | `qa/` | **Manual** (syncOptions only, no `automated` block) | `https://qa-cluster.aws-us-east-2.example.com` | QA -- requires manual sync trigger in ArgoCD UI or CLI |
| **stg** | `stg/` | **Manual** (syncOptions only, no `automated` block) | `https://stg-cluster.aws-us-east-2.example.com` | Staging -- requires manual sync, pre-production validation |
| **prd** | `prd/` | **Manual** (syncOptions only, no `automated` block) | `https://prd-cluster.aws-us-east-2.example.com` | Production -- requires manual sync, change-controlled |

### Sync Policy Details

**Dev (automated):**

```yaml
syncPolicy:
  automated:
    prune: true
    selfHeal: true
  syncOptions:
    - CreateNamespace=true
    - ServerSideApply=true   # or SkipDryRunOnMissingResource=true
```

- `prune: true` -- Resources removed from Git are deleted from the cluster.
- `selfHeal: true` -- Manual cluster changes are reverted to match Git state.

**QA / STG / PRD (manual):**

```yaml
syncPolicy:
  syncOptions:
    - CreateNamespace=true
    - ServerSideApply=true   # or SkipDryRunOnMissingResource=true
```

- No `automated` block -- sync must be triggered explicitly via `argocd app sync` or the ArgoCD UI.
- This prevents unintended changes from reaching higher environments without human review.

> **Note:** The cluster URLs in qa, stg, and prd files are placeholder values (e.g., `https://prd-cluster.aws-us-east-2.example.com`). Replace these with your actual Kubernetes API server endpoints before applying.

---

## ApplicationSet Types

### Shared Across Both Platforms

These five ApplicationSet types are present in every environment on both `aws-us-east-2` and `openshift`:

| ApplicationSet | File Name | Source Type | Helm Chart / Git Path | Target Namespace | syncOptions |
|---|---|---|---|---|---|
| **cert-manager** | `cert-manager-application-set.yaml` | Helm (multi-source) | Chart: `cert-manager` from `charts.jetstack.io` (`1.*`) | `cert-manager` | `CreateNamespace=true`, `ServerSideApply=true` |
| **confluent-operator** | `confluent-operator-application-set.yaml` | Helm (multi-source) | Chart: `confluent-for-kubernetes` from `packages.confluent.io/helm` (`0.*`) | `confluent-{{environment}}` | `CreateNamespace=true`, `ServerSideApply=true` |
| **confluent-flink-operator** | `confluent-flink-operator-application-set.yaml` | Helm (multi-source) | Chart: `flink-kubernetes-operator` from `packages.confluent.io/helm` (`1.*`) | `confluent-{{environment}}` | `CreateNamespace=true`, `ServerSideApply=true` |
| **confluent-platform** | `confluent-platform-application-set.yaml` | Git directory | `apps/confluent-platform/{{environment}}/manifests` | `confluent-{{environment}}` | `CreateNamespace=true`, `SkipDryRunOnMissingResource=true` |
| **confluent-flink** | `confluent-flink-application-set.yaml` | Git directory | `apps/confluent-flink/{{environment}}/manifests` (AWS) or `apps/confluent-flink/openshift/{{environment}}/manifests` (OpenShift) | `confluent-{{environment}}` | `CreateNamespace=true`, `SkipDryRunOnMissingResource=true` |

### OpenShift-Only

| ApplicationSet | File Name | Source Type | Git Path | Target Namespace | syncOptions |
|---|---|---|---|---|---|
| **openshift-prereqs** | `openshift-prereqs-application-set.yaml` | Git directory | `apps/openshift-prereqs/{{environment}}/manifests` | `openshift-gitops` | `CreateNamespace=true`, `SkipDryRunOnMissingResource=true` |

### Source Type Details

**Helm (multi-source)** ApplicationSets use the `sources` (plural) field with two entries:

1. The Helm chart repository (e.g., `charts.jetstack.io`) with a `targetRevision` semver constraint.
2. A Git repository reference (`ref: values`) that provides the `valueFiles` for Helm. This pattern allows Helm values to be version-controlled in Git while the chart itself comes from an external registry.

**Git directory** ApplicationSets use the `source` (singular) field pointing to a directory of raw Kubernetes manifests within this repository.

### Special Configuration: `ignoreDifferences`

The `confluent-platform` ApplicationSet includes an `ignoreDifferences` block:

```yaml
ignoreDifferences:
  - group: platform.confluent.io
    kind: "*"
    jsonPointers:
      - /status
```

This instructs ArgoCD to ignore `/status` differences on all Confluent Platform CRDs, preventing constant drift detection caused by controller-managed status fields.

---

## Deployment Order

The ApplicationSets must be applied in a specific order due to inter-component dependencies. Operators and prerequisites must be running before their dependent CRD-based resources can be deployed.

### AWS (`aws-us-east-2`)

```
1. cert-manager                  (TLS certificate management -- required by Confluent components)
2. confluent-operator            (Installs the CFK operator -- manages Confluent Platform CRDs)
3. confluent-flink-operator      (Installs the Flink K8s operator -- manages Flink CRDs)
4. confluent-platform            (Deploys Confluent Platform components via CRDs)
5. confluent-flink               (Deploys Confluent Flink Manager via CRDs)
```

### OpenShift (`openshift`)

```
1. openshift-prereqs             (SCCs, ClusterRoles, and other OpenShift-specific prerequisites)
2. cert-manager                  (TLS certificate management -- required by Confluent components)
3. confluent-operator            (Installs the CFK operator -- manages Confluent Platform CRDs)
4. confluent-flink-operator      (Installs the Flink K8s operator -- manages Flink CRDs)
5. confluent-platform            (Deploys Confluent Platform components via CRDs)
6. confluent-flink               (Deploys Confluent Flink Manager via CRDs)
```

> **Important:** On OpenShift, `openshift-prereqs` must be applied **first**. It provisions SecurityContextConstraints (SCCs) and RBAC resources that the operators and workloads depend on.

---

## File Naming Convention

All files follow a consistent naming pattern:

```
<component>-application-set.yaml
```

Where `<component>` is one of:

| Component slug | Full name |
|---|---|
| `cert-manager` | cert-manager (Jetstack) |
| `confluent-operator` | Confluent for Kubernetes (CFK) operator |
| `confluent-flink-operator` | Confluent Flink Kubernetes operator |
| `confluent-platform` | Confluent Platform CRD instances |
| `confluent-flink` | Confluent Flink Manager CRD instances |
| `openshift-prereqs` | OpenShift prerequisites (SCCs, RBAC) |

The Kubernetes `metadata.name` for each ApplicationSet follows the pattern `<component>-<environment>` (e.g., `cert-manager-dev`, `confluent-operator-prd`).

---

## How ApplicationSets Work

Each ApplicationSet uses an ArgoCD **list generator** that defines one or more target clusters. When the ApplicationSet is applied, ArgoCD generates one `Application` resource per element in the list.

### Generator Example

```yaml
generators:
  - list:
      elements:
        - cluster: dev-cluster
          url: https://kubernetes.default.svc
          environment: dev
```

### Template Variable Substitution

The generator variables are substituted into the template:

| Variable | Description | Example value |
|---|---|---|
| `{{cluster}}` | Logical cluster name | `dev-cluster` |
| `{{url}}` | Kubernetes API server URL | `https://kubernetes.default.svc` |
| `{{environment}}` | Environment identifier | `dev` |

These variables appear in:

- `metadata.name` -- e.g., `cert-manager-{{environment}}`
- `destination.server` -- e.g., `{{url}}`
- `destination.namespace` -- e.g., `confluent-{{environment}}`
- `source.path` / `helm.valueFiles` -- e.g., `apps/confluent-platform/{{environment}}/manifests`

### Multi-Cluster Scaling

To deploy to multiple clusters in the same environment, add more elements to the generator list:

```yaml
generators:
  - list:
      elements:
        - cluster: dev-cluster-1
          url: https://dev-cluster-1.example.com
          environment: dev
        - cluster: dev-cluster-2
          url: https://dev-cluster-2.example.com
          environment: dev
```

ArgoCD will generate a separate Application for each cluster entry.

---

## Usage

### Applying a Single ApplicationSet

```bash
# AWS platform, dev environment
kubectl apply -f gitops-config/aws-us-east-2/dev/cert-manager-application-set.yaml

# OpenShift platform, dev environment
oc apply -f gitops-config/openshift/dev/openshift-prereqs-application-set.yaml
```

### Applying All ApplicationSets for an Environment

```bash
# AWS dev -- all 5 ApplicationSets
kubectl apply -f gitops-config/aws-us-east-2/dev/

# OpenShift dev -- all 6 ApplicationSets
oc apply -f gitops-config/openshift/dev/
```

### Pre-Flight Checklist

Before applying ApplicationSets, ensure:

1. **ArgoCD is installed** in the correct namespace (`argocd` for AWS, `openshift-gitops` for OpenShift).
2. **Cluster URLs are updated** -- replace placeholder URLs (e.g., `https://prd-cluster.aws-us-east-2.example.com`) with actual Kubernetes API server endpoints.
3. **Git repository access is configured** -- ArgoCD must have credentials to clone `git@github.com:aadmassu/flink-on-k8s-with-cp.git`.
4. **Helm repositories are accessible** -- ArgoCD must be able to reach `charts.jetstack.io` and `packages.confluent.io/helm`.

---

## Cross-References

| Resource | Path | Description |
|---|---|---|
| Application source definitions | [`apps/`](../apps/) | Helm values, Kustomize overlays, and raw manifests consumed by these ApplicationSets |
| cert-manager values | [`apps/cert-manager/`](../apps/cert-manager/) | Per-environment values and OpenShift overlay for cert-manager |
| Confluent operator values | [`apps/confluent-operator/`](../apps/confluent-operator/) | Per-environment values and OpenShift overlay for CFK |
| Flink operator values | [`apps/confluent-flink-operator/`](../apps/confluent-flink-operator/) | Per-environment values and OpenShift overlay for Flink operator |
| Confluent Platform manifests | [`apps/confluent-platform/`](../apps/confluent-platform/) | CRD manifests for Confluent Platform components |
| Confluent Flink manifests | [`apps/confluent-flink/`](../apps/confluent-flink/) | CRD manifests for Confluent Flink Manager (includes `openshift/` subdirectory) |
| OpenShift prerequisites | [`apps/openshift-prereqs/`](../apps/openshift-prereqs/) | SCCs, ClusterRoles, and other OpenShift-specific resources |

> **Subdirectory READMEs:** If platform-specific READMEs exist, see [`gitops-config/openshift/README.md`](openshift/README.md) and [`gitops-config/aws-us-east-2/README.md`](aws-us-east-2/README.md) for platform-level details.
