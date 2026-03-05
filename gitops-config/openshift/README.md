# OpenShift ArgoCD ApplicationSet Definitions

This directory contains ArgoCD **ApplicationSet** definitions for deploying the Confluent and Flink operator stack on **Red Hat OpenShift** clusters. Each environment (dev, qa, stg, prd) has its own subdirectory with three ApplicationSet manifests that, together, provision all required operators.

> **Prerequisite:** Before applying any ApplicationSets, OpenShift prerequisites (SCCs and ClusterRoleBindings) must be applied directly as a one-time cluster setup:
> ```bash
> oc apply -f openshift-prereqs/${ENV}/manifests/
> ```
> These resources are **not** managed by ArgoCD. See [`openshift-prereqs/`](../../openshift-prereqs/) for details.

---

## Table of Contents

- [Directory Structure](#directory-structure)
- [ApplicationSet Types](#applicationset-types)
  - [1. cert-manager-application-set.yaml](#1-cert-manager-application-setyaml)
  - [2. confluent-operator-application-set.yaml](#2-confluent-operator-application-setyaml)
  - [3. confluent-flink-operator-application-set.yaml](#3-confluent-flink-operator-application-setyaml)
- [Per-Environment Differences](#per-environment-differences)
  - [Cluster URLs](#cluster-urls)
  - [Sync Policies](#sync-policies)
  - [Namespace Targets](#namespace-targets)
- [Deployment Order](#deployment-order)

---

## Directory Structure

```
gitops-config/openshift/
├── README.md
├── argocd-repo-secret.yaml        # ArgoCD repository credential (envsubst template)
├── dev/
│   ├── cert-manager-application-set.yaml
│   ├── confluent-operator-application-set.yaml
│   ├── confluent-flink-operator-application-set.yaml
│   ├── confluent-cmf-application-set.yaml
│   ├── confluent-platform-application-set.yaml
│   └── confluent-flink-application-set.yaml
├── qa/
│   └── (same 6 ApplicationSets)
├── stg/
│   └── (same 6 ApplicationSets)
└── prd/
    └── (same 6 ApplicationSets)
```

Each environment contains **6 ApplicationSets**, for a total of **24 files**.

---

## ApplicationSet Types

### 1. cert-manager-application-set.yaml

**Purpose:** Deploys [cert-manager](https://cert-manager.io/) using the official Jetstack Helm chart with OpenShift-specific value overrides. cert-manager provides automated TLS certificate management required by Flink operator webhooks.

**Source type:** Multi-source (Helm chart + Git values)

**What it deploys:** The `cert-manager` Helm chart from `https://charts.jetstack.io` at version `v1.19.4`, with values from:
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
| `spec.generators[0].list.elements[0].url` | Cluster API URL | OpenShift API server URL for the target cluster (see [Cluster URLs](#cluster-urls)) |
| `spec.generators[0].list.elements[0].environment` | `dev` / `qa` / `stg` / `prd` | Environment identifier used in template parameter substitution |
| `spec.template.metadata.name` | `cert-manager-{{environment}}` | Generated ArgoCD Application name |
| `spec.template.metadata.namespace` | `openshift-gitops` | Namespace for the generated ArgoCD Application resource |
| `spec.template.spec.project` | `default` | ArgoCD project that governs access controls |
| `spec.template.spec.sources[0].repoURL` | `https://charts.jetstack.io` | Helm chart repository URL for cert-manager |
| `spec.template.spec.sources[0].chart` | `cert-manager` | Name of the Helm chart to install |
| `spec.template.spec.sources[0].targetRevision` | `v1.19.4` | Helm chart version (pinned) |
| `spec.template.spec.sources[0].helm.valueFiles[0]` | `$values/apps/cert-manager/{{environment}}/values.yaml` | Environment-specific Helm values file, referenced via the `$values` Git repo alias |
| `spec.template.spec.sources[0].helm.valueFiles[1]` | `$values/apps/cert-manager/openshift-overlay.yaml` | OpenShift-specific overrides (disables `global.podSecurityPolicy.enabled`) |
| `spec.template.spec.sources[1].repoURL` | `https://Psyncopate-Internal@dev.azure.com/Psyncopate-Internal/Confluent/_git/flink-on-k8s-with-cp` | Git repository providing the Helm values files |
| `spec.template.spec.sources[1].targetRevision` | `HEAD` | Git revision to track |
| `spec.template.spec.sources[1].ref` | `values` | Reference name used by `$values` in the Helm valueFiles paths |
| `spec.template.spec.destination.server` | `{{url}}` | Target cluster API URL, resolved from generator list |
| `spec.template.spec.destination.namespace` | `cert-manager` | Destination namespace for cert-manager resources |
| `spec.template.spec.syncPolicy.automated.prune` | `true` (dev only) | Automatically delete resources removed from Git (dev only; absent in qa/stg/prd) |
| `spec.template.spec.syncPolicy.automated.selfHeal` | `true` (dev only) | Automatically revert manual changes (dev only; absent in qa/stg/prd) |
| `spec.template.spec.syncPolicy.syncOptions[0]` | `CreateNamespace=true` | Create the `cert-manager` namespace if it does not exist |
| `spec.template.spec.syncPolicy.syncOptions[1]` | `ServerSideApply=true` | Use server-side apply for large CRD manifests that exceed client-side annotation limits |

---

### 2. confluent-operator-application-set.yaml

**Purpose:** Deploys the [Confluent for Kubernetes (CFK)](https://docs.confluent.io/operator/current/overview.html) operator using the official Confluent Helm chart with OpenShift-specific value overrides. CFK manages the lifecycle of Confluent Platform components (Kafka, Schema Registry, Connect, etc.).

**Source type:** Multi-source (Helm chart + Git values)

**What it deploys:** The `confluent-for-kubernetes` Helm chart from `https://packages.confluent.io/helm` at version `0.1351.59`, with values from:
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
| `spec.generators[0].list.elements[0].url` | Cluster API URL | OpenShift API server URL for the target cluster (see [Cluster URLs](#cluster-urls)) |
| `spec.generators[0].list.elements[0].environment` | `dev` / `qa` / `stg` / `prd` | Environment identifier used in template parameter substitution |
| `spec.template.metadata.name` | `confluent-operator-{{environment}}` | Generated ArgoCD Application name |
| `spec.template.metadata.namespace` | `openshift-gitops` | Namespace for the generated ArgoCD Application resource |
| `spec.template.spec.project` | `default` | ArgoCD project that governs access controls |
| `spec.template.spec.sources[0].repoURL` | `https://packages.confluent.io/helm` | Confluent Helm chart repository URL |
| `spec.template.spec.sources[0].chart` | `confluent-for-kubernetes` | Name of the CFK Helm chart |
| `spec.template.spec.sources[0].targetRevision` | `0.1351.59` | Helm chart version (pinned) |
| `spec.template.spec.sources[0].helm.valueFiles[0]` | `$values/apps/confluent-operator/{{environment}}/values.yaml` | Environment-specific Helm values file |
| `spec.template.spec.sources[0].helm.valueFiles[1]` | `$values/apps/confluent-operator/openshift-overlay.yaml` | OpenShift-specific overrides (nullifies `podSecurity.securityContext.fsGroup` and `runAsUser`) |
| `spec.template.spec.sources[1].repoURL` | `https://Psyncopate-Internal@dev.azure.com/Psyncopate-Internal/Confluent/_git/flink-on-k8s-with-cp` | Git repository providing the Helm values files |
| `spec.template.spec.sources[1].targetRevision` | `HEAD` | Git revision to track |
| `spec.template.spec.sources[1].ref` | `values` | Reference name used by `$values` in the Helm valueFiles paths |
| `spec.template.spec.destination.server` | `{{url}}` | Target cluster API URL, resolved from generator list |
| `spec.template.spec.destination.namespace` | `confluent-{{environment}}` | Destination namespace (e.g., `confluent-dev`, `confluent-qa`) |
| `spec.template.spec.syncPolicy.automated.prune` | `true` (dev only) | Automatically delete resources removed from Git (dev only; absent in qa/stg/prd) |
| `spec.template.spec.syncPolicy.automated.selfHeal` | `true` (dev only) | Automatically revert manual changes (dev only; absent in qa/stg/prd) |
| `spec.template.spec.syncPolicy.syncOptions[0]` | `CreateNamespace=true` | Create the destination namespace if it does not exist |
| `spec.template.spec.syncPolicy.syncOptions[1]` | `ServerSideApply=true` | Use server-side apply for large CRD manifests |

---

### 3. confluent-flink-operator-application-set.yaml

**Purpose:** Deploys the [Confluent Flink Kubernetes Operator](https://docs.confluent.io/confluent-manager-for-apache-flink/current/overview.html) using the official Confluent Helm chart with OpenShift-specific value overrides. This operator manages the lifecycle of Apache Flink clusters and jobs on OpenShift.

**Source type:** Multi-source (Helm chart + Git values)

**What it deploys:** The `flink-kubernetes-operator` Helm chart from `https://packages.confluent.io/helm` at version `1.130.2`, with values from:
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
| `spec.generators[0].list.elements[0].url` | Cluster API URL | OpenShift API server URL for the target cluster (see [Cluster URLs](#cluster-urls)) |
| `spec.generators[0].list.elements[0].environment` | `dev` / `qa` / `stg` / `prd` | Environment identifier used in template parameter substitution |
| `spec.template.metadata.name` | `confluent-flink-operator-{{environment}}` | Generated ArgoCD Application name |
| `spec.template.metadata.namespace` | `openshift-gitops` | Namespace for the generated ArgoCD Application resource |
| `spec.template.spec.project` | `default` | ArgoCD project that governs access controls |
| `spec.template.spec.sources[0].repoURL` | `https://packages.confluent.io/helm` | Confluent Helm chart repository URL |
| `spec.template.spec.sources[0].chart` | `flink-kubernetes-operator` | Name of the Flink operator Helm chart |
| `spec.template.spec.sources[0].targetRevision` | `1.130.2` | Helm chart version (pinned) |
| `spec.template.spec.sources[0].helm.valueFiles[0]` | `$values/apps/confluent-flink-operator/{{environment}}/values.yaml` | Environment-specific Helm values file |
| `spec.template.spec.sources[0].helm.valueFiles[1]` | `$values/apps/confluent-flink-operator/openshift-overlay.yaml` | OpenShift-specific overrides (nullifies `podSecurityContext.runAsUser`, `runAsGroup`, `fsGroup`) |
| `spec.template.spec.sources[1].repoURL` | `https://Psyncopate-Internal@dev.azure.com/Psyncopate-Internal/Confluent/_git/flink-on-k8s-with-cp` | Git repository providing the Helm values files |
| `spec.template.spec.sources[1].targetRevision` | `HEAD` | Git revision to track |
| `spec.template.spec.sources[1].ref` | `values` | Reference name used by `$values` in the Helm valueFiles paths |
| `spec.template.spec.destination.server` | `{{url}}` | Target cluster API URL, resolved from generator list |
| `spec.template.spec.destination.namespace` | `confluent-{{environment}}` | Destination namespace (e.g., `confluent-dev`, `confluent-qa`) |
| `spec.template.spec.syncPolicy.automated.prune` | `true` (dev only) | Automatically delete resources removed from Git (dev only; absent in qa/stg/prd) |
| `spec.template.spec.syncPolicy.automated.selfHeal` | `true` (dev only) | Automatically revert manual changes (dev only; absent in qa/stg/prd) |
| `spec.template.spec.syncPolicy.syncOptions[0]` | `CreateNamespace=true` | Create the destination namespace if it does not exist |
| `spec.template.spec.syncPolicy.syncOptions[1]` | `ServerSideApply=true` | Use server-side apply for large CRD manifests |

---

## Per-Environment Differences

### Cluster URLs

| Environment | Cluster Name | API Server URL |
|-------------|-------------|----------------|
| **dev** | `dev-cluster` | `https://kubernetes.default.svc` (in-cluster) |
| **qa** | `qa-cluster` | `https://qa-cluster.example.com` |
| **stg** | `stg-cluster` | `https://stg-cluster.example.com` |
| **prd** | `prd-cluster` | `https://prd-cluster.example.com` |

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
| `cert-manager` | `cert-manager` | `cert-manager` | `cert-manager` | `cert-manager` |
| `confluent-operator` | `confluent-dev` | `confluent-qa` | `confluent-stg` | `confluent-prd` |
| `confluent-flink-operator` | `confluent-dev` | `confluent-qa` | `confluent-stg` | `confluent-prd` |

> **Note:** The `cert-manager` namespace is fixed across all environments. All Confluent components share a single per-environment namespace using the `confluent-{{environment}}` pattern.

---

## Deployment Order

The ApplicationSets must be applied in a specific order because later components depend on resources created by earlier ones.

> **Prerequisite:** Before applying any ApplicationSets, apply the OpenShift prerequisites (SCCs + ClusterRoleBindings) directly:
> ```bash
> oc apply -f openshift-prereqs/${ENV}/manifests/
> ```
> See [`openshift-prereqs/`](../../openshift-prereqs/) for details.

```
Step 1: cert-manager-application-set.yaml
         |
         |  TLS certificate infrastructure must be available for operator webhooks
         v
Step 2: confluent-operator-application-set.yaml
         |
         |  CFK operator and its CRDs must be registered
         v
Step 3: confluent-flink-operator-application-set.yaml
```

| Step | ApplicationSet | Reason |
|------|---------------|--------|
| 1 | `cert-manager` | Provides the certificate issuance infrastructure needed by operator webhook TLS certificates |
| 2 | `confluent-operator` | Installs the CFK operator and registers Confluent CRDs (`Kafka`, `SchemaRegistry`, `Connect`, etc.) |
| 3 | `confluent-flink-operator` | Installs the Flink operator and registers Flink CRDs (`FlinkDeployment`, etc.) |

> **Tip:** To apply all ApplicationSets for a given environment in order:
> ```bash
> ENV=dev  # change to qa, stg, or prd as needed
> oc apply -f openshift-prereqs/${ENV}/manifests/
> oc apply -f gitops-config/openshift/${ENV}/cert-manager-application-set.yaml
> oc apply -f gitops-config/openshift/${ENV}/confluent-operator-application-set.yaml
> oc apply -f gitops-config/openshift/${ENV}/confluent-flink-operator-application-set.yaml
> ```
