# OpenShift ArgoCD ApplicationSet Definitions

This directory contains ArgoCD **ApplicationSet** definitions for deploying the complete Confluent Platform and Flink stack on **Red Hat OpenShift** clusters. Each environment (dev, qa, stg, prd) has its own subdirectory with six ApplicationSet manifests that, together, provision all required infrastructure, operators, and workloads.

These ApplicationSets are the OpenShift-specific counterpart to the vanilla Kubernetes definitions found under `gitops-config/aws-us-east-2/`. The key differences are documented in the [Comparison with Vanilla Kubernetes ApplicationSets](#comparison-with-vanilla-kubernetes-applicationsets) section.

---

## Table of Contents

- [Directory Structure](#directory-structure)
- [ApplicationSet Types](#applicationset-types)
  - [1. openshift-prereqs-application-set.yaml](#1-openshift-prereqs-application-setyaml)
  - [2. cert-manager-application-set.yaml](#2-cert-manager-application-setyaml)
  - [3. confluent-operator-application-set.yaml](#3-confluent-operator-application-setyaml)
  - [4. confluent-flink-operator-application-set.yaml](#4-confluent-flink-operator-application-setyaml)
  - [5. confluent-platform-application-set.yaml](#5-confluent-platform-application-setyaml)
  - [6. confluent-flink-application-set.yaml](#6-confluent-flink-application-setyaml)
- [Per-Environment Differences](#per-environment-differences)
  - [Cluster URLs](#cluster-urls)
  - [Sync Policies](#sync-policies)
  - [Namespace Targets](#namespace-targets)
- [Deployment Order](#deployment-order)
- [Comparison with Vanilla Kubernetes ApplicationSets](#comparison-with-vanilla-kubernetes-applicationsets)

---

## Directory Structure

```
gitops-config/openshift/
├── README.md
├── dev/
│   ├── openshift-prereqs-application-set.yaml
│   ├── cert-manager-application-set.yaml
│   ├── confluent-operator-application-set.yaml
│   ├── confluent-flink-operator-application-set.yaml
│   ├── confluent-platform-application-set.yaml
│   └── confluent-flink-application-set.yaml
├── qa/
│   ├── openshift-prereqs-application-set.yaml
│   ├── cert-manager-application-set.yaml
│   ├── confluent-operator-application-set.yaml
│   ├── confluent-flink-operator-application-set.yaml
│   ├── confluent-platform-application-set.yaml
│   └── confluent-flink-application-set.yaml
├── stg/
│   ├── openshift-prereqs-application-set.yaml
│   ├── cert-manager-application-set.yaml
│   ├── confluent-operator-application-set.yaml
│   ├── confluent-flink-operator-application-set.yaml
│   ├── confluent-platform-application-set.yaml
│   └── confluent-flink-application-set.yaml
└── prd/
    ├── openshift-prereqs-application-set.yaml
    ├── cert-manager-application-set.yaml
    ├── confluent-operator-application-set.yaml
    ├── confluent-flink-operator-application-set.yaml
    ├── confluent-platform-application-set.yaml
    └── confluent-flink-application-set.yaml
```

---

## ApplicationSet Types

### 1. openshift-prereqs-application-set.yaml

**Purpose:** Deploys OpenShift-specific prerequisites that must exist before any other component is installed. This includes custom SecurityContextConstraints (SCCs) and their RoleBindings that allow Confluent and Flink pods to run with the required Linux capabilities on OpenShift. This ApplicationSet has **no equivalent** in the vanilla Kubernetes configuration -- it is unique to OpenShift.

**Source type:** Single-source (Git directory)

**What it deploys:** Raw Kubernetes manifests from `apps/openshift-prereqs/{{environment}}/manifests/`, which contain:
- `confluent-scc.yaml` -- Custom SecurityContextConstraint for Confluent workloads
- `scc-bindings.yaml` -- ClusterRoleBindings that grant the SCC to the appropriate service accounts

#### Field Reference

| Key | Value | Description |
|-----|-------|-------------|
| `apiVersion` | `argoproj.io/v1alpha1` | ArgoCD ApplicationSet API version |
| `kind` | `ApplicationSet` | Kubernetes resource kind |
| `metadata.name` | `openshift-prereqs-{env}` | Unique name per environment (e.g., `openshift-prereqs-dev`) |
| `metadata.namespace` | `openshift-gitops` | Namespace where the OpenShift GitOps operator manages ArgoCD resources |
| `spec.generators[0].list.elements[0].cluster` | `{env}-cluster` | Logical cluster name used in templates (e.g., `dev-cluster`) |
| `spec.generators[0].list.elements[0].url` | Cluster API URL | Kubernetes API server URL for the target cluster (see [Cluster URLs](#cluster-urls)) |
| `spec.generators[0].list.elements[0].environment` | `dev` / `qa` / `stg` / `prd` | Environment identifier used in template parameter substitution |
| `spec.template.metadata.name` | `openshift-prereqs-{{environment}}` | Generated ArgoCD Application name using the environment template variable |
| `spec.template.metadata.namespace` | `openshift-gitops` | Namespace for the generated ArgoCD Application resource |
| `spec.template.spec.project` | `default` | ArgoCD project that governs access controls |
| `spec.template.spec.source.repoURL` | `git@github.com:aadmassu/flink-on-k8s-with-cp.git` | Git repository containing the manifests |
| `spec.template.spec.source.path` | `apps/openshift-prereqs/{{environment}}/manifests` | Path within the Git repo to the raw manifest directory |
| `spec.template.spec.source.targetRevision` | `HEAD` | Git revision to track (latest commit on default branch) |
| `spec.template.spec.destination.server` | `{{url}}` | Target cluster API URL, resolved from generator list |
| `spec.template.spec.destination.namespace` | `openshift-gitops` | Destination namespace for deployed resources |
| `spec.template.spec.syncPolicy.automated.prune` | `true` (dev only) | Automatically delete resources removed from Git (dev only; absent in qa/stg/prd) |
| `spec.template.spec.syncPolicy.automated.selfHeal` | `true` (dev only) | Automatically revert manual changes to match Git state (dev only; absent in qa/stg/prd) |
| `spec.template.spec.syncPolicy.syncOptions[0]` | `CreateNamespace=true` | Create the destination namespace if it does not exist |
| `spec.template.spec.syncPolicy.syncOptions[1]` | `SkipDryRunOnMissingResource=true` | Skip dry-run validation for CRDs or resources whose types are not yet registered in the cluster |

---

### 2. cert-manager-application-set.yaml

**Purpose:** Deploys [cert-manager](https://cert-manager.io/) using the official Jetstack Helm chart with OpenShift-specific value overrides. cert-manager provides automated TLS certificate management for Confluent Platform components.

**Source type:** Multi-source (Helm chart + Git values)

**What it deploys:** The `cert-manager` Helm chart from `https://charts.jetstack.io` at version `1.*`, with values from:
1. `apps/cert-manager/{{environment}}/values.yaml` -- environment-specific values
2. `apps/cert-manager/openshift-overlay.yaml` -- OpenShift-specific overrides (disables PodSecurityPolicy since OpenShift uses SCCs instead)

#### Field Reference

| Key | Value | Description |
|-----|-------|-------------|
| `apiVersion` | `argoproj.io/v1alpha1` | ArgoCD ApplicationSet API version |
| `kind` | `ApplicationSet` | Kubernetes resource kind |
| `metadata.name` | `cert-manager-{env}` | Unique name per environment (e.g., `cert-manager-dev`) |
| `metadata.namespace` | `openshift-gitops` | Namespace where the OpenShift GitOps operator manages ArgoCD resources |
| `spec.generators[0].list.elements[0].cluster` | `{env}-cluster` | Logical cluster name used in templates |
| `spec.generators[0].list.elements[0].url` | Cluster API URL | Kubernetes API server URL for the target cluster (see [Cluster URLs](#cluster-urls)) |
| `spec.generators[0].list.elements[0].environment` | `dev` / `qa` / `stg` / `prd` | Environment identifier used in template parameter substitution |
| `spec.template.metadata.name` | `cert-manager-{{environment}}` | Generated ArgoCD Application name |
| `spec.template.metadata.namespace` | `openshift-gitops` | Namespace for the generated ArgoCD Application resource |
| `spec.template.spec.project` | `default` | ArgoCD project that governs access controls |
| `spec.template.spec.sources[0].repoURL` | `https://charts.jetstack.io` | Helm chart repository URL for cert-manager |
| `spec.template.spec.sources[0].chart` | `cert-manager` | Name of the Helm chart to install |
| `spec.template.spec.sources[0].targetRevision` | `1.*` | Helm chart version constraint (any 1.x release) |
| `spec.template.spec.sources[0].helm.valueFiles[0]` | `$values/apps/cert-manager/{{environment}}/values.yaml` | Environment-specific Helm values file, referenced via the `$values` Git repo alias |
| `spec.template.spec.sources[0].helm.valueFiles[1]` | `$values/apps/cert-manager/openshift-overlay.yaml` | OpenShift-specific overrides (disables `global.podSecurityPolicy.enabled`) |
| `spec.template.spec.sources[1].repoURL` | `git@github.com:aadmassu/flink-on-k8s-with-cp.git` | Git repository providing the Helm values files |
| `spec.template.spec.sources[1].targetRevision` | `HEAD` | Git revision to track |
| `spec.template.spec.sources[1].ref` | `values` | Reference name used by `$values` in the Helm valueFiles paths |
| `spec.template.spec.destination.server` | `{{url}}` | Target cluster API URL, resolved from generator list |
| `spec.template.spec.destination.namespace` | `cert-manager` | Destination namespace for cert-manager resources |
| `spec.template.spec.syncPolicy.automated.prune` | `true` (dev only) | Automatically delete resources removed from Git (dev only; absent in qa/stg/prd) |
| `spec.template.spec.syncPolicy.automated.selfHeal` | `true` (dev only) | Automatically revert manual changes (dev only; absent in qa/stg/prd) |
| `spec.template.spec.syncPolicy.syncOptions[0]` | `CreateNamespace=true` | Create the `cert-manager` namespace if it does not exist |
| `spec.template.spec.syncPolicy.syncOptions[1]` | `ServerSideApply=true` | Use server-side apply for large CRD manifests that exceed client-side annotation limits |

---

### 3. confluent-operator-application-set.yaml

**Purpose:** Deploys the [Confluent for Kubernetes (CFK)](https://docs.confluent.io/operator/current/overview.html) operator using the official Confluent Helm chart with OpenShift-specific value overrides. CFK manages the lifecycle of Confluent Platform components (Kafka, Schema Registry, Connect, etc.).

**Source type:** Multi-source (Helm chart + Git values)

**What it deploys:** The `confluent-for-kubernetes` Helm chart from `https://packages.confluent.io/helm` at version `0.*`, with values from:
1. `apps/confluent-operator/{{environment}}/values.yaml` -- environment-specific values
2. `apps/confluent-operator/openshift-overlay.yaml` -- OpenShift-specific overrides (nullifies `fsGroup` and `runAsUser` so that OpenShift's SCC-assigned UIDs are used)

#### Field Reference

| Key | Value | Description |
|-----|-------|-------------|
| `apiVersion` | `argoproj.io/v1alpha1` | ArgoCD ApplicationSet API version |
| `kind` | `ApplicationSet` | Kubernetes resource kind |
| `metadata.name` | `confluent-operator-{env}` | Unique name per environment (e.g., `confluent-operator-dev`) |
| `metadata.namespace` | `openshift-gitops` | Namespace where the OpenShift GitOps operator manages ArgoCD resources |
| `spec.generators[0].list.elements[0].cluster` | `{env}-cluster` | Logical cluster name used in templates |
| `spec.generators[0].list.elements[0].url` | Cluster API URL | Kubernetes API server URL for the target cluster (see [Cluster URLs](#cluster-urls)) |
| `spec.generators[0].list.elements[0].environment` | `dev` / `qa` / `stg` / `prd` | Environment identifier used in template parameter substitution |
| `spec.template.metadata.name` | `confluent-operator-{{environment}}` | Generated ArgoCD Application name |
| `spec.template.metadata.namespace` | `openshift-gitops` | Namespace for the generated ArgoCD Application resource |
| `spec.template.spec.project` | `default` | ArgoCD project that governs access controls |
| `spec.template.spec.sources[0].repoURL` | `https://packages.confluent.io/helm` | Confluent Helm chart repository URL |
| `spec.template.spec.sources[0].chart` | `confluent-for-kubernetes` | Name of the CFK Helm chart |
| `spec.template.spec.sources[0].targetRevision` | `0.*` | Helm chart version constraint (any 0.x release) |
| `spec.template.spec.sources[0].helm.valueFiles[0]` | `$values/apps/confluent-operator/{{environment}}/values.yaml` | Environment-specific Helm values file |
| `spec.template.spec.sources[0].helm.valueFiles[1]` | `$values/apps/confluent-operator/openshift-overlay.yaml` | OpenShift-specific overrides (nullifies `podSecurity.securityContext.fsGroup` and `runAsUser`) |
| `spec.template.spec.sources[1].repoURL` | `git@github.com:aadmassu/flink-on-k8s-with-cp.git` | Git repository providing the Helm values files |
| `spec.template.spec.sources[1].targetRevision` | `HEAD` | Git revision to track |
| `spec.template.spec.sources[1].ref` | `values` | Reference name used by `$values` in the Helm valueFiles paths |
| `spec.template.spec.destination.server` | `{{url}}` | Target cluster API URL, resolved from generator list |
| `spec.template.spec.destination.namespace` | `confluent-{{environment}}` | Destination namespace (e.g., `confluent-dev`, `confluent-qa`) |
| `spec.template.spec.syncPolicy.automated.prune` | `true` (dev only) | Automatically delete resources removed from Git (dev only; absent in qa/stg/prd) |
| `spec.template.spec.syncPolicy.automated.selfHeal` | `true` (dev only) | Automatically revert manual changes (dev only; absent in qa/stg/prd) |
| `spec.template.spec.syncPolicy.syncOptions[0]` | `CreateNamespace=true` | Create the destination namespace if it does not exist |
| `spec.template.spec.syncPolicy.syncOptions[1]` | `ServerSideApply=true` | Use server-side apply for large CRD manifests |

---

### 4. confluent-flink-operator-application-set.yaml

**Purpose:** Deploys the [Confluent Flink Kubernetes Operator](https://docs.confluent.io/confluent-manager-for-apache-flink/current/overview.html) using the official Confluent Helm chart with OpenShift-specific value overrides. This operator manages the lifecycle of Apache Flink clusters and jobs on Kubernetes.

**Source type:** Multi-source (Helm chart + Git values)

**What it deploys:** The `flink-kubernetes-operator` Helm chart from `https://packages.confluent.io/helm` at version `1.*`, with values from:
1. `apps/confluent-flink-operator/{{environment}}/values.yaml` -- environment-specific values
2. `apps/confluent-flink-operator/openshift-overlay.yaml` -- OpenShift-specific overrides (nullifies `runAsUser`, `runAsGroup`, and `fsGroup` in `podSecurityContext`)

#### Field Reference

| Key | Value | Description |
|-----|-------|-------------|
| `apiVersion` | `argoproj.io/v1alpha1` | ArgoCD ApplicationSet API version |
| `kind` | `ApplicationSet` | Kubernetes resource kind |
| `metadata.name` | `confluent-flink-operator-{env}` | Unique name per environment (e.g., `confluent-flink-operator-dev`) |
| `metadata.namespace` | `openshift-gitops` | Namespace where the OpenShift GitOps operator manages ArgoCD resources |
| `spec.generators[0].list.elements[0].cluster` | `{env}-cluster` | Logical cluster name used in templates |
| `spec.generators[0].list.elements[0].url` | Cluster API URL | Kubernetes API server URL for the target cluster (see [Cluster URLs](#cluster-urls)) |
| `spec.generators[0].list.elements[0].environment` | `dev` / `qa` / `stg` / `prd` | Environment identifier used in template parameter substitution |
| `spec.template.metadata.name` | `confluent-flink-operator-{{environment}}` | Generated ArgoCD Application name |
| `spec.template.metadata.namespace` | `openshift-gitops` | Namespace for the generated ArgoCD Application resource |
| `spec.template.spec.project` | `default` | ArgoCD project that governs access controls |
| `spec.template.spec.sources[0].repoURL` | `https://packages.confluent.io/helm` | Confluent Helm chart repository URL |
| `spec.template.spec.sources[0].chart` | `flink-kubernetes-operator` | Name of the Flink operator Helm chart |
| `spec.template.spec.sources[0].targetRevision` | `1.*` | Helm chart version constraint (any 1.x release) |
| `spec.template.spec.sources[0].helm.valueFiles[0]` | `$values/apps/confluent-flink-operator/{{environment}}/values.yaml` | Environment-specific Helm values file |
| `spec.template.spec.sources[0].helm.valueFiles[1]` | `$values/apps/confluent-flink-operator/openshift-overlay.yaml` | OpenShift-specific overrides (nullifies `podSecurityContext.runAsUser`, `runAsGroup`, `fsGroup`) |
| `spec.template.spec.sources[1].repoURL` | `git@github.com:aadmassu/flink-on-k8s-with-cp.git` | Git repository providing the Helm values files |
| `spec.template.spec.sources[1].targetRevision` | `HEAD` | Git revision to track |
| `spec.template.spec.sources[1].ref` | `values` | Reference name used by `$values` in the Helm valueFiles paths |
| `spec.template.spec.destination.server` | `{{url}}` | Target cluster API URL, resolved from generator list |
| `spec.template.spec.destination.namespace` | `confluent-{{environment}}` | Destination namespace (e.g., `confluent-dev`, `confluent-qa`) |
| `spec.template.spec.syncPolicy.automated.prune` | `true` (dev only) | Automatically delete resources removed from Git (dev only; absent in qa/stg/prd) |
| `spec.template.spec.syncPolicy.automated.selfHeal` | `true` (dev only) | Automatically revert manual changes (dev only; absent in qa/stg/prd) |
| `spec.template.spec.syncPolicy.syncOptions[0]` | `CreateNamespace=true` | Create the destination namespace if it does not exist |
| `spec.template.spec.syncPolicy.syncOptions[1]` | `ServerSideApply=true` | Use server-side apply for large CRD manifests |

---

### 5. confluent-platform-application-set.yaml

**Purpose:** Deploys the Confluent Platform data-plane components (Kafka, ZooKeeper, Schema Registry, Connect, ksqlDB, Control Center, etc.) as CFK custom resources. These are raw YAML manifests managed by the Confluent for Kubernetes operator installed in step 3.

**Source type:** Single-source (Git directory)

**What it deploys:** Raw Kubernetes manifests (CFK custom resources) from `apps/confluent-platform/{{environment}}/manifests/`. This path is **shared** with the vanilla Kubernetes configuration -- unlike the Flink ApplicationSet, the Confluent Platform manifests do not require an OpenShift-specific subdirectory because the CFK operator handles platform differences internally.

#### Field Reference

| Key | Value | Description |
|-----|-------|-------------|
| `apiVersion` | `argoproj.io/v1alpha1` | ArgoCD ApplicationSet API version |
| `kind` | `ApplicationSet` | Kubernetes resource kind |
| `metadata.name` | `confluent-platform-{env}` | Unique name per environment (e.g., `confluent-platform-dev`) |
| `metadata.namespace` | `openshift-gitops` | Namespace where the OpenShift GitOps operator manages ArgoCD resources |
| `spec.generators[0].list.elements[0].cluster` | `{env}-cluster` | Logical cluster name used in templates |
| `spec.generators[0].list.elements[0].url` | Cluster API URL | Kubernetes API server URL for the target cluster (see [Cluster URLs](#cluster-urls)) |
| `spec.generators[0].list.elements[0].environment` | `dev` / `qa` / `stg` / `prd` | Environment identifier used in template parameter substitution |
| `spec.template.metadata.name` | `confluent-platform-{{environment}}` | Generated ArgoCD Application name |
| `spec.template.metadata.namespace` | `openshift-gitops` | Namespace for the generated ArgoCD Application resource |
| `spec.template.spec.project` | `default` | ArgoCD project that governs access controls |
| `spec.template.spec.source.repoURL` | `git@github.com:aadmassu/flink-on-k8s-with-cp.git` | Git repository containing the manifests |
| `spec.template.spec.source.path` | `apps/confluent-platform/{{environment}}/manifests` | Path within the Git repo to the manifest directory |
| `spec.template.spec.source.targetRevision` | `HEAD` | Git revision to track (latest commit on default branch) |
| `spec.template.spec.destination.server` | `{{url}}` | Target cluster API URL, resolved from generator list |
| `spec.template.spec.destination.namespace` | `confluent-{{environment}}` | Destination namespace (e.g., `confluent-dev`, `confluent-qa`) |
| `spec.template.spec.ignoreDifferences[0].group` | `platform.confluent.io` | API group for Confluent CRDs |
| `spec.template.spec.ignoreDifferences[0].kind` | `*` | Apply to all CFK custom resource kinds |
| `spec.template.spec.ignoreDifferences[0].jsonPointers[0]` | `/status` | Ignore `/status` diffs so the operator-managed status subresource does not trigger spurious out-of-sync states |
| `spec.template.spec.syncPolicy.automated.prune` | `true` (dev only) | Automatically delete resources removed from Git (dev only; absent in qa/stg/prd) |
| `spec.template.spec.syncPolicy.automated.selfHeal` | `true` (dev only) | Automatically revert manual changes (dev only; absent in qa/stg/prd) |
| `spec.template.spec.syncPolicy.syncOptions[0]` | `CreateNamespace=true` | Create the destination namespace if it does not exist |
| `spec.template.spec.syncPolicy.syncOptions[1]` | `SkipDryRunOnMissingResource=true` | Skip dry-run validation for CFK CRDs that may not yet be registered when the Application is first created |

---

### 6. confluent-flink-application-set.yaml

**Purpose:** Deploys Confluent Flink workloads (FlinkDeployment / CMF Manager custom resources) as raw manifests. On OpenShift, these manifests come from an **OpenShift-specific subdirectory** (`apps/confluent-flink/openshift/{{environment}}/manifests/`) that may include SCC-aware configurations, unlike the vanilla K8s path (`apps/confluent-flink/{{environment}}/manifests/`).

**Source type:** Single-source (Git directory)

**What it deploys:** Raw Kubernetes manifests from `apps/confluent-flink/openshift/{{environment}}/manifests/`, which contain:
- `confluent-flink-manager.yaml` -- Confluent Manager for Apache Flink (CMF) deployment resource

#### Field Reference

| Key | Value | Description |
|-----|-------|-------------|
| `apiVersion` | `argoproj.io/v1alpha1` | ArgoCD ApplicationSet API version |
| `kind` | `ApplicationSet` | Kubernetes resource kind |
| `metadata.name` | `confluent-flink-{env}` | Unique name per environment (e.g., `confluent-flink-dev`) |
| `metadata.namespace` | `openshift-gitops` | Namespace where the OpenShift GitOps operator manages ArgoCD resources |
| `spec.generators[0].list.elements[0].cluster` | `{env}-cluster` | Logical cluster name used in templates |
| `spec.generators[0].list.elements[0].url` | Cluster API URL | Kubernetes API server URL for the target cluster (see [Cluster URLs](#cluster-urls)) |
| `spec.generators[0].list.elements[0].environment` | `dev` / `qa` / `stg` / `prd` | Environment identifier used in template parameter substitution |
| `spec.template.metadata.name` | `confluent-flink-{{environment}}` | Generated ArgoCD Application name |
| `spec.template.metadata.namespace` | `openshift-gitops` | Namespace for the generated ArgoCD Application resource |
| `spec.template.spec.project` | `default` | ArgoCD project that governs access controls |
| `spec.template.spec.source.repoURL` | `git@github.com:aadmassu/flink-on-k8s-with-cp.git` | Git repository containing the manifests |
| `spec.template.spec.source.path` | `apps/confluent-flink/openshift/{{environment}}/manifests` | OpenShift-specific path within the Git repo (note the `openshift/` segment) |
| `spec.template.spec.source.targetRevision` | `HEAD` | Git revision to track (latest commit on default branch) |
| `spec.template.spec.destination.server` | `{{url}}` | Target cluster API URL, resolved from generator list |
| `spec.template.spec.destination.namespace` | `confluent-{{environment}}` | Destination namespace (e.g., `confluent-dev`, `confluent-qa`) |
| `spec.template.spec.syncPolicy.automated.prune` | `true` (dev only) | Automatically delete resources removed from Git (dev only; absent in qa/stg/prd) |
| `spec.template.spec.syncPolicy.automated.selfHeal` | `true` (dev only) | Automatically revert manual changes (dev only; absent in qa/stg/prd) |
| `spec.template.spec.syncPolicy.syncOptions[0]` | `CreateNamespace=true` | Create the destination namespace if it does not exist |
| `spec.template.spec.syncPolicy.syncOptions[1]` | `SkipDryRunOnMissingResource=true` | Skip dry-run validation for Flink CRDs that may not yet be registered when the Application is first created |

---

## Per-Environment Differences

### Cluster URLs

| Environment | Cluster Name | API Server URL |
|-------------|-------------|----------------|
| **dev** | `dev-cluster` | `https://kubernetes.default.svc` (in-cluster) |
| **qa** | `qa-cluster` | `https://qa-cluster.aws-us-east-2.example.com` |
| **stg** | `stg-cluster` | `https://stg-cluster.aws-us-east-2.example.com` |
| **prd** | `prd-cluster` | `https://prd-cluster.aws-us-east-2.example.com` |

> **Note:** The `dev` environment uses the in-cluster service URL (`https://kubernetes.default.svc`), meaning ArgoCD and the dev workloads run on the same cluster. The qa, stg, and prd environments target remote clusters registered in ArgoCD.

### Sync Policies

| Environment | Automated Sync | Prune | Self-Heal | Description |
|-------------|---------------|-------|-----------|-------------|
| **dev** | Yes | Yes | Yes | Fully automated -- changes in Git are automatically applied, orphaned resources are pruned, and manual drift is corrected |
| **qa** | No | No | No | Manual sync only -- a human must trigger sync from the ArgoCD UI or CLI |
| **stg** | No | No | No | Manual sync only -- requires explicit approval before changes are applied |
| **prd** | No | No | No | Manual sync only -- strictest controls for production stability |

> **Note:** In qa, stg, and prd, the `syncPolicy` block contains only `syncOptions` (e.g., `CreateNamespace=true`) but no `automated` section, which means ArgoCD will detect drift and show out-of-sync status but will **not** automatically reconcile.

### Namespace Targets

| ApplicationSet | dev | qa | stg | prd |
|---------------|-----|-----|-----|-----|
| `openshift-prereqs` | `openshift-gitops` | `openshift-gitops` | `openshift-gitops` | `openshift-gitops` |
| `cert-manager` | `cert-manager` | `cert-manager` | `cert-manager` | `cert-manager` |
| `confluent-operator` | `confluent-dev` | `confluent-qa` | `confluent-stg` | `confluent-prd` |
| `confluent-flink-operator` | `confluent-dev` | `confluent-qa` | `confluent-stg` | `confluent-prd` |
| `confluent-platform` | `confluent-dev` | `confluent-qa` | `confluent-stg` | `confluent-prd` |
| `confluent-flink` | `confluent-dev` | `confluent-qa` | `confluent-stg` | `confluent-prd` |

> **Note:** The `openshift-prereqs` resources (SCCs and bindings) are cluster-scoped but the ArgoCD Application itself targets the `openshift-gitops` namespace. The `cert-manager` namespace is fixed across all environments. All Confluent components share a single per-environment namespace using the `confluent-{{environment}}` pattern.

---

## Deployment Order

The ApplicationSets must be applied in a specific order because later components depend on resources created by earlier ones.

```
Step 1: openshift-prereqs-application-set.yaml
         |
         |  SCCs and bindings must exist before any Confluent/Flink pods start
         v
Step 2: cert-manager-application-set.yaml
         |
         |  TLS certificate infrastructure must be available for operator webhooks
         v
Step 3: confluent-operator-application-set.yaml
         |
         |  CFK operator and its CRDs must be registered before CP resources
         v
Step 4: confluent-flink-operator-application-set.yaml
         |
         |  Flink operator and its CRDs must be registered before Flink workloads
         v
Step 5: confluent-platform-application-set.yaml
         |
         |  Confluent Platform components (Kafka, SR, Connect, etc.) should be running
         |  before Flink jobs that depend on them
         v
Step 6: confluent-flink-application-set.yaml
```

| Step | ApplicationSet | Reason |
|------|---------------|--------|
| 1 | `openshift-prereqs` | SecurityContextConstraints and bindings must exist so that pods in subsequent steps can be scheduled by OpenShift's admission controller |
| 2 | `cert-manager` | Provides the certificate issuance infrastructure needed by operator webhook TLS certificates |
| 3 | `confluent-operator` | Installs the CFK operator and registers Confluent CRDs (`Kafka`, `SchemaRegistry`, `Connect`, etc.) |
| 4 | `confluent-flink-operator` | Installs the Flink operator and registers Flink CRDs (`FlinkDeployment`, etc.) |
| 5 | `confluent-platform` | Deploys Confluent Platform data-plane components as CFK custom resources (requires CFK CRDs from step 3) |
| 6 | `confluent-flink` | Deploys Flink workloads as Flink operator custom resources (requires Flink CRDs from step 4 and optionally a running Kafka from step 5) |

> **Tip:** To apply all ApplicationSets for a given environment in order:
> ```bash
> ENV=dev  # change to qa, stg, or prd as needed
> oc apply -f gitops-config/openshift/${ENV}/openshift-prereqs-application-set.yaml
> oc apply -f gitops-config/openshift/${ENV}/cert-manager-application-set.yaml
> oc apply -f gitops-config/openshift/${ENV}/confluent-operator-application-set.yaml
> oc apply -f gitops-config/openshift/${ENV}/confluent-flink-operator-application-set.yaml
> oc apply -f gitops-config/openshift/${ENV}/confluent-platform-application-set.yaml
> oc apply -f gitops-config/openshift/${ENV}/confluent-flink-application-set.yaml
> ```

---

## Comparison with Vanilla Kubernetes ApplicationSets

The vanilla Kubernetes ApplicationSets are located under `gitops-config/aws-us-east-2/` and target standard (non-OpenShift) EKS clusters. The table below summarizes every difference between the two variants.

### Structural Differences

| Aspect | OpenShift (`gitops-config/openshift/`) | Vanilla K8s (`gitops-config/aws-us-east-2/`) |
|--------|---------------------------------------|----------------------------------------------|
| **ArgoCD namespace** | `openshift-gitops` | `argocd` |
| **ApplicationSet metadata.namespace** | `openshift-gitops` | `argocd` |
| **Template metadata.namespace** | `openshift-gitops` | `argocd` |
| **Number of ApplicationSet types** | 6 (includes `openshift-prereqs`) | 5 (no prereqs ApplicationSet) |
| **`openshift-prereqs` ApplicationSet** | Present -- deploys SCCs and SCC bindings | Absent -- not needed on vanilla K8s |
| **OpenShift overlay values files** | Included as a second `valueFiles` entry (`openshift-overlay.yaml`) on all Helm-based ApplicationSets | Not present -- only environment-specific `values.yaml` is used |
| **Flink manifests path** | `apps/confluent-flink/openshift/{{environment}}/manifests` | `apps/confluent-flink/{{environment}}/manifests` |
| **Confluent Platform manifests path** | `apps/confluent-platform/{{environment}}/manifests` (shared) | `apps/confluent-platform/{{environment}}/manifests` (shared) |

### OpenShift Overlay Files

The Helm-based ApplicationSets (cert-manager, confluent-operator, confluent-flink-operator) include an additional `openshift-overlay.yaml` values file that is **not** present in the vanilla K8s variant. These overlays adapt the Helm charts for OpenShift's security model:

| Overlay File | Key Overrides | Purpose |
|-------------|---------------|---------|
| `apps/cert-manager/openshift-overlay.yaml` | `global.podSecurityPolicy.enabled: false` | Disables PodSecurityPolicy (PSP) since OpenShift uses SecurityContextConstraints (SCCs) instead |
| `apps/confluent-operator/openshift-overlay.yaml` | `podSecurity.securityContext.fsGroup: null`, `podSecurity.securityContext.runAsUser: null` | Removes hardcoded UID/GID so that OpenShift's SCC-assigned arbitrary UIDs are used |
| `apps/confluent-flink-operator/openshift-overlay.yaml` | `podSecurityContext.runAsUser: null`, `podSecurityContext.runAsGroup: null`, `podSecurityContext.fsGroup: null` | Removes hardcoded UID/GID for Flink operator pods to be compatible with OpenShift's restricted SCC |

### Summary of All Differences at a Glance

| Feature | OpenShift | Vanilla K8s |
|---------|-----------|-------------|
| ArgoCD managed by | OpenShift GitOps Operator | Community ArgoCD installation |
| ArgoCD namespace | `openshift-gitops` | `argocd` |
| Pod security model | SecurityContextConstraints (SCCs) | PodSecurityPolicy / Pod Security Standards |
| SCC prereqs ApplicationSet | Required | Not applicable |
| Helm overlay files | `openshift-overlay.yaml` per chart | None |
| Flink manifest path | `apps/confluent-flink/openshift/...` | `apps/confluent-flink/...` |
| CLI tool | `oc apply -f` | `kubectl apply -f` |
