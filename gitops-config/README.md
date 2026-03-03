# GitOps Config -- ArgoCD ApplicationSet Definitions

This directory contains **ArgoCD ApplicationSet** definitions that drive the multi-cluster deployment of Confluent and Flink operators on **Red Hat OpenShift**. ApplicationSets are organized by **environment** (dev, qa, stg, prd), enabling a single Git repository to declaratively manage deployments across all clusters.

Each ApplicationSet uses a **list generator** to enumerate target clusters. When applied to the ArgoCD management cluster, it produces one ArgoCD `Application` resource per cluster entry, substituting template variables (`{{cluster}}`, `{{url}}`, `{{environment}}`) into the generated Application spec.

---

## Table of Contents

- [Directory Structure](#directory-structure)
- [OpenShift Platform Details](#openshift-platform-details)
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
+-- openshift/                         # Platform: Red Hat OpenShift
    |-- dev/
    |   |-- cert-manager-application-set.yaml
    |   |-- confluent-operator-application-set.yaml
    |   +-- confluent-flink-operator-application-set.yaml
    |-- qa/
    |   |-- cert-manager-application-set.yaml
    |   |-- confluent-operator-application-set.yaml
    |   +-- confluent-flink-operator-application-set.yaml
    |-- stg/
    |   |-- cert-manager-application-set.yaml
    |   |-- confluent-operator-application-set.yaml
    |   +-- confluent-flink-operator-application-set.yaml
    +-- prd/
        |-- cert-manager-application-set.yaml
        |-- confluent-operator-application-set.yaml
        +-- confluent-flink-operator-application-set.yaml
```

Each environment contains **3 ApplicationSets**, for a total of **12 files**.

---

## OpenShift Platform Details

These ApplicationSets target OpenShift clusters managed by **OpenShift GitOps** (the Red Hat-supported ArgoCD distribution). Key characteristics:

- ArgoCD namespace is `openshift-gitops`.
- Helm-based charts layer an **OpenShift overlay** values file on top of the per-environment values (e.g., `openshift-overlay.yaml`).
- OpenShift prerequisites (SCCs, ClusterRoleBindings) are applied separately via `oc apply -f openshift-prereqs/<env>/manifests/` -- they are **not** managed by ArgoCD. See [`../openshift-prereqs/`](../openshift-prereqs/).

### OpenShift Overlay Files

The following Helm-based ApplicationSets include an additional overlay values file that adjusts configuration for OpenShift compatibility (e.g., security contexts, service account annotations, route/ingress configuration):

| ApplicationSet | Overlay file referenced |
|---|---|
| `cert-manager` | `apps/cert-manager/openshift-overlay.yaml` |
| `confluent-operator` | `apps/confluent-operator/openshift-overlay.yaml` |
| `confluent-flink-operator` | `apps/confluent-flink-operator/openshift-overlay.yaml` |

---

## Environments and Sync Policies

Each environment subdirectory differs primarily in its **sync policy** and **target cluster URL**.

| Environment | Directory | Sync Policy | Cluster URL | Description |
|---|---|---|---|---|
| **dev** | `dev/` | **Automated** (`prune: true`, `selfHeal: true`) | `https://kubernetes.default.svc` (in-cluster) | Development -- changes sync automatically, drift is auto-corrected |
| **qa** | `qa/` | **Manual** (syncOptions only, no `automated` block) | `https://qa-cluster.example.com` | QA -- requires manual sync trigger in ArgoCD UI or CLI |
| **stg** | `stg/` | **Manual** (syncOptions only, no `automated` block) | `https://stg-cluster.example.com` | Staging -- requires manual sync, pre-production validation |
| **prd** | `prd/` | **Manual** (syncOptions only, no `automated` block) | `https://prd-cluster.example.com` | Production -- requires manual sync, change-controlled |

### Sync Policy Details

**Dev (automated):**

```yaml
syncPolicy:
  automated:
    prune: true
    selfHeal: true
  syncOptions:
    - CreateNamespace=true
    - ServerSideApply=true
```

- `prune: true` -- Resources removed from Git are deleted from the cluster.
- `selfHeal: true` -- Manual cluster changes are reverted to match Git state.

**QA / STG / PRD (manual):**

```yaml
syncPolicy:
  syncOptions:
    - CreateNamespace=true
    - ServerSideApply=true
```

- No `automated` block -- sync must be triggered explicitly via `argocd app sync` or the ArgoCD UI.
- This prevents unintended changes from reaching higher environments without human review.

> **Note:** The cluster URLs in qa, stg, and prd files are placeholder values (e.g., `https://prd-cluster.example.com`). Replace these with your actual OpenShift API server endpoints before applying.

---

## ApplicationSet Types

These three ApplicationSet types are present in every environment:

| ApplicationSet | File Name | Source Type | Helm Chart | Target Namespace | syncOptions |
|---|---|---|---|---|---|
| **cert-manager** | `cert-manager-application-set.yaml` | Helm (multi-source) | `cert-manager` from `charts.jetstack.io` (`v1.19.4`) | `cert-manager` | `CreateNamespace=true`, `ServerSideApply=true` |
| **confluent-operator** | `confluent-operator-application-set.yaml` | Helm (multi-source) | `confluent-for-kubernetes` from `packages.confluent.io/helm` (`0.1351.59`) | `confluent-{{environment}}` | `CreateNamespace=true`, `ServerSideApply=true` |
| **confluent-flink-operator** | `confluent-flink-operator-application-set.yaml` | Helm (multi-source) | `flink-kubernetes-operator` from `packages.confluent.io/helm` (`1.130.2`) | `confluent-{{environment}}` | `CreateNamespace=true`, `ServerSideApply=true` |

### Source Type Details

**Helm (multi-source)** ApplicationSets use the `sources` (plural) field with two entries:

1. The Helm chart repository (e.g., `charts.jetstack.io`) with a `targetRevision` semver constraint.
2. A Git repository reference (`ref: values`) that provides the `valueFiles` for Helm. This pattern allows Helm values to be version-controlled in Git while the chart itself comes from an external registry.

---

## Deployment Order

The ApplicationSets must be applied in a specific order due to inter-component dependencies. Operators and prerequisites must be running before their dependent CRD-based resources can be deployed.

> **Prerequisite:** Before applying any ApplicationSets, apply the OpenShift prerequisites (SCCs + ClusterRoleBindings) directly via `oc apply -f openshift-prereqs/<env>/manifests/`. See [`../openshift-prereqs/`](../openshift-prereqs/) for details.

```
0. (one-time) oc apply -f openshift-prereqs/<env>/manifests/   (SCCs + ClusterRoleBindings)
1. cert-manager                  (TLS certificate management -- required by Flink operator webhooks)
2. confluent-operator            (Installs the CFK operator -- manages Confluent Platform CRDs)
3. confluent-flink-operator      (Installs the Flink K8s operator -- manages Flink CRDs)
```

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
| `{{url}}` | OpenShift API server URL | `https://kubernetes.default.svc` |
| `{{environment}}` | Environment identifier | `dev` |

These variables appear in:

- `metadata.name` -- e.g., `cert-manager-{{environment}}`
- `destination.server` -- e.g., `{{url}}`
- `destination.namespace` -- e.g., `confluent-{{environment}}`
- `helm.valueFiles` -- e.g., `$values/apps/confluent-operator/{{environment}}/values.yaml`

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
oc apply -f gitops-config/openshift/dev/cert-manager-application-set.yaml
```

### Applying All ApplicationSets for an Environment

```bash
# OpenShift dev -- all 3 ApplicationSets
oc apply -f gitops-config/openshift/dev/
```

### Pre-Flight Checklist

Before applying ApplicationSets, ensure:

1. **OpenShift GitOps is installed** in the `openshift-gitops` namespace.
2. **OpenShift prerequisites are applied** -- run `oc apply -f openshift-prereqs/<env>/manifests/` for each target environment.
3. **Cluster URLs are updated** -- replace placeholder URLs (e.g., `https://prd-cluster.example.com`) with actual OpenShift API server endpoints.
4. **Git repository access is configured** -- ArgoCD must have credentials to clone `git@github.com:aadmassu/flink-on-k8s-with-cp.git`.
5. **Helm repositories are accessible** -- ArgoCD must be able to reach `charts.jetstack.io` and `packages.confluent.io/helm`.

---

## Cross-References

| Resource | Path | Description |
|---|---|---|
| Application source definitions | [`apps/`](../apps/) | Helm values, Kustomize overlays, and raw manifests consumed by these ApplicationSets |
| cert-manager values | [`apps/cert-manager/`](../apps/cert-manager/) | Per-environment values and OpenShift overlay for cert-manager |
| Confluent operator values | [`apps/confluent-operator/`](../apps/confluent-operator/) | Per-environment values and OpenShift overlay for CFK |
| Flink operator values | [`apps/confluent-flink-operator/`](../apps/confluent-flink-operator/) | Per-environment values and OpenShift overlay for Flink operator |
| OpenShift prerequisites | [`../openshift-prereqs/`](../openshift-prereqs/) | SCCs and ClusterRoleBindings (applied directly via `oc apply`, not via ArgoCD) |
