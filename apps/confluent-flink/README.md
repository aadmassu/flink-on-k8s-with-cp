# Confluent Flink Manager (CMF) -- ArgoCD Application Manifests

This directory contains **ArgoCD `Application` resources** that deploy [Confluent Manager for Apache Flink (CMF)](https://docs.confluent.io/confluent-manager-for-apache-flink/current/overview.html) via the official Confluent Helm chart. Each environment (dev, qa, stg, prd) has its own manifest, and two platform variants are provided: a **base** variant for standard Kubernetes clusters and an **OpenShift** variant for Red Hat OpenShift clusters.

These manifests follow the **app-of-apps pattern** in ArgoCD. A parent `ApplicationSet` or root `Application` references this directory, and ArgoCD reconciles the child `Application` resources defined here. Each child `Application` points to the `confluent-manager-for-apache-flink` Helm chart hosted at `https://packages.confluent.io/helm` and renders it with environment-specific Helm parameters.

## Directory Structure

```
confluent-flink/
├── README.md
├── dev/
│   └── manifests/
│       └── confluent-flink-manager.yaml        # Base Kubernetes - Development
├── qa/
│   └── manifests/
│       └── confluent-flink-manager.yaml        # Base Kubernetes - QA
├── stg/
│   └── manifests/
│       └── confluent-flink-manager.yaml        # Base Kubernetes - Staging
├── prd/
│   └── manifests/
│       └── confluent-flink-manager.yaml        # Base Kubernetes - Production
└── openshift/
    ├── dev/
    │   └── manifests/
    │       └── confluent-flink-manager.yaml    # OpenShift - Development
    ├── qa/
    │   └── manifests/
    │       └── confluent-flink-manager.yaml    # OpenShift - QA
    ├── stg/
    │   └── manifests/
    │       └── confluent-flink-manager.yaml    # OpenShift - Staging
    └── prd/
        └── manifests/
            └── confluent-flink-manager.yaml    # OpenShift - Production
```

## How It Works

Each YAML file in this tree is an ArgoCD `Application` custom resource (`argoproj.io/v1alpha1`). When ArgoCD processes these resources it:

1. Pulls the `confluent-manager-for-apache-flink` Helm chart from the Confluent Helm repository.
2. Renders the chart with the Helm parameters and values specified in the manifest.
3. Deploys the rendered resources to the target Kubernetes cluster and namespace.
4. Optionally enables automated sync (pruning and self-healing) depending on the environment.

## Dependencies

- **ArgoCD** must be installed and operational on the management cluster.
- **Flink Kubernetes Operator** must already be running in the target cluster (see `../confluent-flink-operator/`).

---

## Base (Non-OpenShift) Manifest

**Path pattern:** `{dev,qa,stg,prd}/manifests/confluent-flink-manager.yaml`

These manifests target standard Kubernetes clusters (e.g., EKS, GKE, AKS) where ArgoCD is installed in the `argocd` namespace. No additional security-context overrides are needed because the default Helm chart values are compatible with standard Kubernetes pod security.

### Full Field Reference -- Base Manifest (dev example)

| Key | Value | Description |
|-----|-------|-------------|
| `apiVersion` | `argoproj.io/v1alpha1` | ArgoCD Application API version. |
| `kind` | `Application` | Kubernetes resource kind; declares this as an ArgoCD Application. |
| `metadata.name` | `confluent-flink-manager-dev` | Unique name for this ArgoCD Application. Suffixed with the environment name (`-dev`, `-qa`, `-stg`, `-prd`). |
| `metadata.namespace` | `argocd` | Namespace where the ArgoCD Application CR is created. On standard Kubernetes this is `argocd`. |
| `metadata.annotations.argocd.argoproj.io/sync-wave` | `"0"` | Sync wave ordering. Wave `0` means this Application is synced in the first wave, ensuring CMF is deployed early in the overall sync sequence. |
| `spec.project` | `default` | ArgoCD project this Application belongs to. `default` is the built-in project that permits all sources and destinations. |
| `spec.source.repoURL` | `https://packages.confluent.io/helm` | Helm repository URL for the Confluent Helm charts. |
| `spec.source.chart` | `confluent-manager-for-apache-flink` | Name of the Helm chart to install. This is the official CMF chart published by Confluent. |
| `spec.source.targetRevision` | `1.*` | SemVer constraint for the chart version. `1.*` matches the latest `1.x` release, allowing automatic minor/patch upgrades within the v1 line. |
| `spec.source.helm.parameters[0].name` | `cmf.sql.production` | Helm value key that controls whether CMF operates in production mode for Flink SQL. |
| `spec.source.helm.parameters[0].value` | `"false"` (dev/qa) or `"true"` (stg/prd) | When `"false"`, CMF runs in non-production mode (relaxed resource defaults). When `"true"`, production-grade settings are applied. |
| `spec.destination.server` | `https://<env>-cluster.aws-us-east-2.example.com` | Kubernetes API server URL of the target cluster. Varies per environment. |
| `spec.destination.namespace` | `confluent-<env>` | Target namespace on the destination cluster where CMF will be deployed (e.g., `confluent-dev`). |
| `spec.syncPolicy.automated.prune` | `true` (dev only) | When present, ArgoCD automatically deletes resources that are no longer defined in the source. Only enabled for the dev environment. |
| `spec.syncPolicy.automated.selfHeal` | `true` (dev only) | When present, ArgoCD automatically reverts manual changes made to live resources. Only enabled for the dev environment. |
| `spec.syncPolicy.syncOptions[0]` | `CreateNamespace=true` | Instructs ArgoCD to create the destination namespace if it does not already exist. |
| `spec.syncPolicy.syncOptions[1]` | `ServerSideApply=true` | Uses server-side apply for resource patching, which avoids client-side merge conflicts and supports large CRDs. |

---

## OpenShift Manifest

**Path pattern:** `openshift/{dev,qa,stg,prd}/manifests/confluent-flink-manager.yaml`

These manifests target Red Hat OpenShift clusters. They differ from the base manifests in two key ways:

1. **Namespace:** The ArgoCD Application CR is created in `openshift-gitops` instead of `argocd`, because OpenShift GitOps installs ArgoCD into the `openshift-gitops` namespace by default.
2. **Security context overrides:** OpenShift uses Security Context Constraints (SCCs) to manage pod security. The default Helm chart values for `fsGroup` and `runAsUser` conflict with OpenShift's SCC policies, so they are explicitly set to `null` to let OpenShift assign appropriate values automatically.

### Full Field Reference -- OpenShift Manifest (dev example)

| Key | Value | Description |
|-----|-------|-------------|
| `apiVersion` | `argoproj.io/v1alpha1` | ArgoCD Application API version. |
| `kind` | `Application` | Kubernetes resource kind; declares this as an ArgoCD Application. |
| `metadata.name` | `confluent-flink-manager-dev` | Unique name for this ArgoCD Application. Suffixed with the environment name (`-dev`, `-qa`, `-stg`, `-prd`). |
| `metadata.namespace` | `openshift-gitops` | Namespace where the ArgoCD Application CR is created. On OpenShift this is `openshift-gitops` (installed by the OpenShift GitOps operator). |
| `metadata.annotations.argocd.argoproj.io/sync-wave` | `"0"` | Sync wave ordering. Wave `0` means this Application is synced in the first wave. |
| `spec.project` | `default` | ArgoCD project this Application belongs to. |
| `spec.source.repoURL` | `https://packages.confluent.io/helm` | Helm repository URL for the Confluent Helm charts. |
| `spec.source.chart` | `confluent-manager-for-apache-flink` | Name of the Helm chart to install. |
| `spec.source.targetRevision` | `1.*` | SemVer constraint for the chart version. Matches the latest `1.x` release. |
| `spec.source.helm.parameters[0].name` | `cmf.sql.production` | Helm value key that controls whether CMF operates in production mode for Flink SQL. |
| `spec.source.helm.parameters[0].value` | `"false"` (dev/qa) or `"true"` (stg/prd) | Non-production mode for lower environments; production mode for staging and production. |
| `spec.source.helm.values` | *(inline YAML -- see below)* | Inline Helm values block used to override chart defaults. This is where OpenShift-specific security context nullification is applied. |
| `spec.source.helm.values.podSecurity.securityContext.fsGroup` | `null` | Explicitly nullifies the `fsGroup` field so that OpenShift's SCC can assign the appropriate group ID from the namespace's allocated range. |
| `spec.source.helm.values.podSecurity.securityContext.runAsUser` | `null` | Explicitly nullifies the `runAsUser` field so that OpenShift's SCC can assign the appropriate user ID from the namespace's allocated UID range. |
| `spec.destination.server` | `https://<env>-cluster.aws-us-east-2.example.com` | Kubernetes API server URL of the target OpenShift cluster. Varies per environment. |
| `spec.destination.namespace` | `confluent-<env>` | Target namespace on the destination cluster where CMF will be deployed. |
| `spec.syncPolicy.automated.prune` | `true` (dev only) | Automatic pruning of orphaned resources. Only enabled for the dev environment. |
| `spec.syncPolicy.automated.selfHeal` | `true` (dev only) | Automatic revert of out-of-band changes. Only enabled for the dev environment. |
| `spec.syncPolicy.syncOptions[0]` | `CreateNamespace=true` | Creates the destination namespace if it does not exist. |
| `spec.syncPolicy.syncOptions[1]` | `ServerSideApply=true` | Uses server-side apply for resource patching. |

### OpenShift Inline Helm Values

The `spec.source.helm.values` field contains the following YAML:

```yaml
podSecurity:
  securityContext:
    fsGroup: null
    runAsUser: null
```

This is necessary because OpenShift clusters enforce Security Context Constraints (SCCs). Setting these fields to `null` prevents the Helm chart from injecting hard-coded UID/GID values that would violate the `restricted` or `restricted-v2` SCC. OpenShift will automatically assign valid values from the namespace's annotation ranges (`openshift.io/sa.scc.uid-range` and `openshift.io/sa.scc.supplemental-groups`).

---

## Per-Environment Differences

The following table summarizes what varies across environments for **both** the base and OpenShift variants. Fields not listed here are identical across all environments.

| Field | dev | qa | stg | prd |
|-------|-----|----|-----|-----|
| `metadata.name` | `confluent-flink-manager-dev` | `confluent-flink-manager-qa` | `confluent-flink-manager-stg` | `confluent-flink-manager-prd` |
| `spec.destination.server` | `https://dev-cluster.aws-us-east-2.example.com` | `https://qa-cluster.aws-us-east-2.example.com` | `https://stg-cluster.aws-us-east-2.example.com` | `https://prd-cluster.aws-us-east-2.example.com` |
| `spec.destination.namespace` | `confluent-dev` | `confluent-qa` | `confluent-stg` | `confluent-prd` |
| `spec.source.helm.parameters[0].value` (`cmf.sql.production`) | `"false"` | `"false"` | `"true"` | `"true"` |
| `spec.syncPolicy.automated` | `{ prune: true, selfHeal: true }` | *(not set -- manual sync)* | *(not set -- manual sync)* | *(not set -- manual sync)* |

**Key observations:**

- **Automated sync is only enabled in dev.** The qa, stg, and prd environments require manual sync triggers (or external CI/CD pipelines) to deploy changes, providing a safety gate for higher environments.
- **Production SQL mode** (`cmf.sql.production`) is `"false"` for dev and qa (lower environments) and `"true"` for stg and prd (upper environments). This controls resource allocation and validation strictness in Flink SQL operations.
- **Cluster URLs and namespaces** follow a consistent naming convention (`<env>-cluster` and `confluent-<env>`), varying only by the environment prefix.

---

## Base vs OpenShift Comparison

| Aspect | Base (Kubernetes) | OpenShift |
|--------|-------------------|-----------|
| **Manifest path** | `{env}/manifests/confluent-flink-manager.yaml` | `openshift/{env}/manifests/confluent-flink-manager.yaml` |
| **`metadata.namespace`** | `argocd` | `openshift-gitops` |
| **`spec.source.helm.values`** | Not set (chart defaults used) | Inline YAML that sets `podSecurity.securityContext.fsGroup` and `podSecurity.securityContext.runAsUser` to `null` |
| **Security context handling** | Uses Helm chart defaults (explicit `fsGroup` and `runAsUser` values) | Nullifies `fsGroup` and `runAsUser` to comply with OpenShift SCCs |
| **`spec.source.helm.parameters`** | Same across both variants | Same across both variants |
| **`spec.destination.server`** | Same cluster URLs per environment | Same cluster URLs per environment |
| **`spec.destination.namespace`** | Same namespace per environment | Same namespace per environment |
| **`spec.syncPolicy`** | Same policy per environment | Same policy per environment |
| **`spec.project`** | `default` | `default` |
| **`spec.source.repoURL`** | `https://packages.confluent.io/helm` | `https://packages.confluent.io/helm` |
| **`spec.source.chart`** | `confluent-manager-for-apache-flink` | `confluent-manager-for-apache-flink` |
| **`spec.source.targetRevision`** | `1.*` | `1.*` |
| **Sync wave** | `"0"` | `"0"` |
