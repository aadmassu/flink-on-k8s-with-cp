# Confluent Flink Manager (CMF) -- ArgoCD Application Manifests

This directory contains **ArgoCD `Application` resources** that deploy [Confluent Manager for Apache Flink (CMF)](https://docs.confluent.io/confluent-manager-for-apache-flink/current/overview.html) via the official Confluent Helm chart onto Red Hat OpenShift clusters. Each environment (dev, qa, stg, prd) has its own manifest under the `openshift/` subdirectory.

These manifests follow the **app-of-apps pattern** in ArgoCD. A parent `ApplicationSet` or root `Application` references this directory, and ArgoCD reconciles the child `Application` resources defined here. Each child `Application` points to the `confluent-manager-for-apache-flink` Helm chart hosted at `https://packages.confluent.io/helm` and renders it with environment-specific Helm parameters. The ArgoCD Application CRs are created in the `openshift-gitops` namespace, which is where the OpenShift GitOps operator installs ArgoCD by default.

## Directory Structure

```
confluent-flink/
├── README.md
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
3. Deploys the rendered resources to the target OpenShift cluster and namespace.
4. Optionally enables automated sync (pruning and self-healing) depending on the environment.

## Dependencies

- **ArgoCD** (OpenShift GitOps) must be installed and operational on the management cluster.
- **Flink Kubernetes Operator** must already be running in the target cluster (see `../confluent-flink-operator/`).

---

## Manifest Field Reference

**Path pattern:** `openshift/{dev,qa,stg,prd}/manifests/confluent-flink-manager.yaml`

These manifests target Red Hat OpenShift clusters. The ArgoCD Application CR is created in the `openshift-gitops` namespace, and inline Helm values are used to nullify security context fields so that OpenShift's Security Context Constraints (SCCs) can assign appropriate UID/GID values automatically.

### Full Field Reference (dev example)

| Key | Value | Description |
|-----|-------|-------------|
| `apiVersion` | `argoproj.io/v1alpha1` | ArgoCD Application API version. |
| `kind` | `Application` | Kubernetes resource kind; declares this as an ArgoCD Application. |
| `metadata.name` | `confluent-flink-manager-dev` | Unique name for this ArgoCD Application. Suffixed with the environment name (`-dev`, `-qa`, `-stg`, `-prd`). |
| `metadata.namespace` | `openshift-gitops` | Namespace where the ArgoCD Application CR is created. On OpenShift this is `openshift-gitops` (installed by the OpenShift GitOps operator). |
| `metadata.annotations.argocd.argoproj.io/sync-wave` | `"0"` | Sync wave ordering. Wave `0` means this Application is synced in the first wave, ensuring CMF is deployed early in the overall sync sequence. |
| `spec.project` | `default` | ArgoCD project this Application belongs to. `default` is the built-in project that permits all sources and destinations. |
| `spec.source.repoURL` | `https://packages.confluent.io/helm` | Helm repository URL for the Confluent Helm charts. |
| `spec.source.chart` | `confluent-manager-for-apache-flink` | Name of the Helm chart to install. This is the official CMF chart published by Confluent. |
| `spec.source.targetRevision` | `1.*` | SemVer constraint for the chart version. `1.*` matches the latest `1.x` release, allowing automatic minor/patch upgrades within the v1 line. |
| `spec.source.helm.parameters[0].name` | `cmf.sql.production` | Helm value key that controls whether CMF operates in production mode for Flink SQL. |
| `spec.source.helm.parameters[0].value` | `"false"` (dev/qa) or `"true"` (stg/prd) | Non-production mode for lower environments; production mode for staging and production. |
| `spec.source.helm.values` | *(inline YAML -- see below)* | Inline Helm values block used to override chart defaults. This is where OpenShift-specific security context nullification is applied. |
| `spec.source.helm.values.podSecurity.securityContext.fsGroup` | `null` | Explicitly nullifies the `fsGroup` field so that OpenShift's SCC can assign the appropriate group ID from the namespace's allocated range. |
| `spec.source.helm.values.podSecurity.securityContext.runAsUser` | `null` | Explicitly nullifies the `runAsUser` field so that OpenShift's SCC can assign the appropriate user ID from the namespace's allocated UID range. |
| `spec.destination.server` | `https://<env>-cluster.example.com` | Kubernetes API server URL of the target OpenShift cluster. Varies per environment. |
| `spec.destination.namespace` | `confluent-<env>` | Target namespace on the destination cluster where CMF will be deployed. |
| `spec.syncPolicy.automated.prune` | `true` (dev only) | Automatic pruning of orphaned resources. Only enabled for the dev environment. |
| `spec.syncPolicy.automated.selfHeal` | `true` (dev only) | Automatic revert of out-of-band changes. Only enabled for the dev environment. |
| `spec.syncPolicy.syncOptions[0]` | `CreateNamespace=true` | Creates the destination namespace if it does not exist. |
| `spec.syncPolicy.syncOptions[1]` | `ServerSideApply=true` | Uses server-side apply for resource patching, which avoids client-side merge conflicts and supports large CRDs. |

### Inline Helm Values

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

The following table summarizes what varies across environments. Fields not listed here are identical across all environments.

| Field | dev | qa | stg | prd |
|-------|-----|----|-----|-----|
| `metadata.name` | `confluent-flink-manager-dev` | `confluent-flink-manager-qa` | `confluent-flink-manager-stg` | `confluent-flink-manager-prd` |
| `spec.destination.server` | `https://dev-cluster.example.com` | `https://qa-cluster.example.com` | `https://stg-cluster.example.com` | `https://prd-cluster.example.com` |
| `spec.destination.namespace` | `confluent-dev` | `confluent-qa` | `confluent-stg` | `confluent-prd` |
| `spec.source.helm.parameters[0].value` (`cmf.sql.production`) | `"false"` | `"false"` | `"true"` | `"true"` |
| `spec.syncPolicy.automated` | `{ prune: true, selfHeal: true }` | *(not set -- manual sync)* | *(not set -- manual sync)* | *(not set -- manual sync)* |

**Key observations:**

- **Automated sync is only enabled in dev.** The qa, stg, and prd environments require manual sync triggers (or external CI/CD pipelines) to deploy changes, providing a safety gate for higher environments.
- **Production SQL mode** (`cmf.sql.production`) is `"false"` for dev and qa (lower environments) and `"true"` for stg and prd (upper environments). This controls resource allocation and validation strictness in Flink SQL operations.
- **Cluster URLs and namespaces** follow a consistent naming convention (`<env>-cluster` and `confluent-<env>`), varying only by the environment prefix.
