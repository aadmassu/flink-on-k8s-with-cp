# ArgoCD

ArgoCD Helm values and self-management Application manifests for deploying a standalone ArgoCD instance on OpenShift. These files support **Option B -- Standalone ArgoCD via Helm**, which is an alternative to the recommended approach of using the OpenShift GitOps Operator.

> **Recommended path:** Install the **OpenShift GitOps Operator** from OperatorHub. When using the operator, ArgoCD is pre-installed and managed in the `openshift-gitops` namespace, and these Helm values are **not used**. See [OpenShift GitOps Operator Relationship](#openshift-gitops-operator-relationship) for details.

---

## Table of Contents

- [Helm Chart](#helm-chart)
- [Directory Structure](#directory-structure)
- [File Descriptions](#file-descriptions)
  - [dev/values.yaml](#devvaluesyaml)
  - [dev/app.yaml](#devappyaml)
  - [qa/values.yaml](#qavaluesyaml)
  - [qa/app.yaml](#qaappyaml)
  - [stg/values.yaml](#stgvaluesyaml)
  - [stg/app.yaml](#stgappyaml)
  - [prd/values.yaml](#prdvaluesyaml)
  - [prd/app.yaml](#prdappyaml)
- [Per-Environment Differences](#per-environment-differences)
  - [Replica Counts](#replica-counts)
  - [Resource Requests and Limits](#resource-requests-and-limits)
  - [Configuration Differences](#configuration-differences)
  - [app.yaml Sync Policy Differences](#appyaml-sync-policy-differences)
- [How These Values Are Consumed](#how-these-values-are-consumed)
- [OpenShift GitOps Operator Relationship](#openshift-gitops-operator-relationship)
- [Installation](#installation)

---

## Helm Chart

| Field | Value |
|-------|-------|
| **Chart** | `argo-cd` |
| **Repository** | `https://argoproj.github.io/argo-helm` |
| **Version** | `9.*` (dev/qa) / `9.4.7` (stg/prd) |

---

## Directory Structure

```
apps/argocd/
|-- README.md
|-- dev/
|   |-- app.yaml          # ArgoCD Application resource for self-management (dev)
|   +-- values.yaml       # Helm values for dev (single-replica, non-HA)
|-- qa/
|   |-- app.yaml          # ArgoCD Application resource for self-management (qa)
|   +-- values.yaml       # Helm values for QA (single-replica)
|-- stg/
|   |-- app.yaml          # ArgoCD Application resource for self-management (stg)
|   +-- values.yaml       # Helm values for staging (HA, 2 replicas)
+-- prd/
    |-- app.yaml          # ArgoCD Application resource for self-management (prd)
    +-- values.yaml       # Helm values for production (HA, 2 replicas)
```

---

## File Descriptions

### dev/values.yaml

Helm values for the **dev** environment. Single-replica, non-HA configuration with lower resource allocations. Enables insecure (HTTP) server access and sets a bcrypt-hashed admin password.

| Key | Value | Description |
|-----|-------|-------------|
| `global.domain` | `argocd-dev.example.com` | The external domain name for the ArgoCD UI in dev |
| `server.replicas` | `1` | Number of ArgoCD API server replicas |
| `server.service.type` | `LoadBalancer` | Service type used to expose the ArgoCD server |
| `server.resources.requests.cpu` | `250m` | CPU request for each ArgoCD server pod |
| `server.resources.requests.memory` | `256Mi` | Memory request for each ArgoCD server pod |
| `server.resources.limits.cpu` | `500m` | CPU limit for each ArgoCD server pod |
| `server.resources.limits.memory` | `512Mi` | Memory limit for each ArgoCD server pod |
| `controller.replicas` | `1` | Number of ArgoCD application controller replicas |
| `controller.resources.requests.cpu` | `250m` | CPU request for each controller pod |
| `controller.resources.requests.memory` | `512Mi` | Memory request for each controller pod |
| `controller.resources.limits.cpu` | `1` | CPU limit for each controller pod |
| `controller.resources.limits.memory` | `1Gi` | Memory limit for each controller pod |
| `repoServer.replicas` | `1` | Number of ArgoCD repo server replicas |
| `repoServer.resources.requests.cpu` | `250m` | CPU request for each repo server pod |
| `repoServer.resources.requests.memory` | `256Mi` | Memory request for each repo server pod |
| `repoServer.resources.limits.cpu` | `500m` | CPU limit for each repo server pod |
| `repoServer.resources.limits.memory` | `512Mi` | Memory limit for each repo server pod |
| `applicationSet.replicas` | `1` | Number of ApplicationSet controller replicas |
| `configs.params.server.insecure` | `true` | Allows HTTP access to the ArgoCD server (TLS is terminated at the Route or ingress) |
| `configs.secret.argocdServerAdminPassword` | `$2b$12$VaK...` (bcrypt hash) | Bcrypt-hashed admin password for the ArgoCD `admin` user |
| `configs.rbac.policy.default` | `role:readonly` | Default RBAC policy applied to unauthenticated or unmapped users |

### dev/app.yaml

ArgoCD `Application` resource that enables **self-management** of the ArgoCD installation in the dev environment. After the initial Helm bootstrap, this Application keeps ArgoCD in sync with the declared values in Git.

| Key | Value | Description |
|-----|-------|-------------|
| `apiVersion` | `argoproj.io/v1alpha1` | ArgoCD Application API version |
| `kind` | `Application` | Kubernetes resource kind |
| `metadata.name` | `argocd-dev` | Name of the ArgoCD Application resource |
| `metadata.namespace` | `argocd` | Namespace where the Application resource is created |
| `spec.project` | `default` | ArgoCD project that this Application belongs to |
| `spec.source.repoURL` | `https://argoproj.github.io/argo-helm` | Helm chart repository URL |
| `spec.source.chart` | `argo-cd` | Helm chart name |
| `spec.source.targetRevision` | `9.*` | Helm chart version constraint (latest 9.x patch) |
| `spec.source.helm.valueFiles[0]` | `values.yaml` | Path to the Helm values file used for rendering |
| `spec.destination.server` | `https://dev-cluster.example.com` | OpenShift API server URL for the dev cluster |
| `spec.destination.namespace` | `argocd` | Target namespace for the ArgoCD installation |
| `spec.syncPolicy.automated.prune` | `true` | Automatically delete resources that are no longer defined in Git |
| `spec.syncPolicy.automated.selfHeal` | `true` | Automatically revert manual changes made to live resources |
| `spec.syncPolicy.syncOptions[0]` | `CreateNamespace=true` | Create the target namespace if it does not exist |
| `spec.syncPolicy.syncOptions[1]` | `ServerSideApply=true` | Use server-side apply for resource reconciliation |

### qa/values.yaml

Helm values for the **QA** environment. Single-replica configuration with resource allocations identical to dev. Enables insecure server access but does **not** set an admin password (uses the auto-generated one).

| Key | Value | Description |
|-----|-------|-------------|
| `global.domain` | `argocd-qa.example.com` | The external domain name for the ArgoCD UI in QA |
| `server.replicas` | `1` | Number of ArgoCD API server replicas |
| `server.resources.requests.cpu` | `250m` | CPU request for each ArgoCD server pod |
| `server.resources.requests.memory` | `256Mi` | Memory request for each ArgoCD server pod |
| `server.resources.limits.cpu` | `500m` | CPU limit for each ArgoCD server pod |
| `server.resources.limits.memory` | `512Mi` | Memory limit for each ArgoCD server pod |
| `controller.replicas` | `1` | Number of ArgoCD application controller replicas |
| `controller.resources.requests.cpu` | `250m` | CPU request for each controller pod |
| `controller.resources.requests.memory` | `512Mi` | Memory request for each controller pod |
| `controller.resources.limits.cpu` | `1` | CPU limit for each controller pod |
| `controller.resources.limits.memory` | `1Gi` | Memory limit for each controller pod |
| `repoServer.replicas` | `1` | Number of ArgoCD repo server replicas |
| `repoServer.resources.requests.cpu` | `250m` | CPU request for each repo server pod |
| `repoServer.resources.requests.memory` | `256Mi` | Memory request for each repo server pod |
| `repoServer.resources.limits.cpu` | `500m` | CPU limit for each repo server pod |
| `repoServer.resources.limits.memory` | `512Mi` | Memory limit for each repo server pod |
| `applicationSet.replicas` | `1` | Number of ApplicationSet controller replicas |
| `configs.params.server.insecure` | `true` | Allows HTTP access to the ArgoCD server (TLS terminated externally) |
| `configs.rbac.policy.default` | `role:readonly` | Default RBAC policy applied to unauthenticated or unmapped users |

### qa/app.yaml

ArgoCD `Application` resource for self-management in the QA environment. Does **not** enable automated sync (no `automated` block) -- syncs must be triggered manually or via CI/CD.

| Key | Value | Description |
|-----|-------|-------------|
| `apiVersion` | `argoproj.io/v1alpha1` | ArgoCD Application API version |
| `kind` | `Application` | Kubernetes resource kind |
| `metadata.name` | `argocd-qa` | Name of the ArgoCD Application resource |
| `metadata.namespace` | `argocd` | Namespace where the Application resource is created |
| `spec.project` | `default` | ArgoCD project that this Application belongs to |
| `spec.source.repoURL` | `https://argoproj.github.io/argo-helm` | Helm chart repository URL |
| `spec.source.chart` | `argo-cd` | Helm chart name |
| `spec.source.targetRevision` | `9.*` | Helm chart version constraint |
| `spec.source.helm.valueFiles[0]` | `values.yaml` | Path to the Helm values file |
| `spec.destination.server` | `https://qa-cluster.example.com` | OpenShift API server URL for the QA cluster |
| `spec.destination.namespace` | `argocd` | Target namespace for the ArgoCD installation |
| `spec.syncPolicy.syncOptions[0]` | `CreateNamespace=true` | Create the target namespace if it does not exist |
| `spec.syncPolicy.syncOptions[1]` | `ServerSideApply=true` | Use server-side apply for resource reconciliation |

### stg/values.yaml

Helm values for the **staging** environment. HA configuration with 2 replicas for all components and higher resource allocations. Does **not** enable insecure server mode or set an admin password.

| Key | Value | Description |
|-----|-------|-------------|
| `global.domain` | `argocd-stg.example.com` | The external domain name for the ArgoCD UI in staging |
| `server.replicas` | `2` | Number of ArgoCD API server replicas (HA) |
| `server.resources.requests.cpu` | `500m` | CPU request for each ArgoCD server pod |
| `server.resources.requests.memory` | `512Mi` | Memory request for each ArgoCD server pod |
| `server.resources.limits.cpu` | `1` | CPU limit for each ArgoCD server pod |
| `server.resources.limits.memory` | `1Gi` | Memory limit for each ArgoCD server pod |
| `controller.replicas` | `2` | Number of ArgoCD application controller replicas (HA) |
| `controller.resources.requests.cpu` | `500m` | CPU request for each controller pod |
| `controller.resources.requests.memory` | `1Gi` | Memory request for each controller pod |
| `controller.resources.limits.cpu` | `2` | CPU limit for each controller pod |
| `controller.resources.limits.memory` | `2Gi` | Memory limit for each controller pod |
| `repoServer.replicas` | `2` | Number of ArgoCD repo server replicas (HA) |
| `repoServer.resources.requests.cpu` | `500m` | CPU request for each repo server pod |
| `repoServer.resources.requests.memory` | `512Mi` | Memory request for each repo server pod |
| `repoServer.resources.limits.cpu` | `1` | CPU limit for each repo server pod |
| `repoServer.resources.limits.memory` | `1Gi` | Memory limit for each repo server pod |
| `applicationSet.replicas` | `2` | Number of ApplicationSet controller replicas (HA) |
| `configs.rbac.policy.default` | `role:readonly` | Default RBAC policy applied to unauthenticated or unmapped users |

### stg/app.yaml

ArgoCD `Application` resource for self-management in the staging environment. Manual sync only (no `automated` block).

| Key | Value | Description |
|-----|-------|-------------|
| `apiVersion` | `argoproj.io/v1alpha1` | ArgoCD Application API version |
| `kind` | `Application` | Kubernetes resource kind |
| `metadata.name` | `argocd-stg` | Name of the ArgoCD Application resource |
| `metadata.namespace` | `argocd` | Namespace where the Application resource is created |
| `spec.project` | `default` | ArgoCD project that this Application belongs to |
| `spec.source.repoURL` | `https://argoproj.github.io/argo-helm` | Helm chart repository URL |
| `spec.source.chart` | `argo-cd` | Helm chart name |
| `spec.source.targetRevision` | `9.4.7` | Helm chart version (pinned for staging) |
| `spec.source.helm.valueFiles[0]` | `values.yaml` | Path to the Helm values file |
| `spec.destination.server` | `https://stg-cluster.example.com` | OpenShift API server URL for the staging cluster |
| `spec.destination.namespace` | `argocd` | Target namespace for the ArgoCD installation |
| `spec.syncPolicy.syncOptions[0]` | `CreateNamespace=true` | Create the target namespace if it does not exist |
| `spec.syncPolicy.syncOptions[1]` | `ServerSideApply=true` | Use server-side apply for resource reconciliation |

### prd/values.yaml

Helm values for the **production** environment. HA configuration identical to staging. Does **not** enable insecure server mode, set an admin password, or set `server.service.type` (defaults to `ClusterIP`).

| Key | Value | Description |
|-----|-------|-------------|
| `global.domain` | `argocd-prd.example.com` | The external domain name for the ArgoCD UI in production |
| `server.replicas` | `2` | Number of ArgoCD API server replicas (HA) |
| `server.resources.requests.cpu` | `500m` | CPU request for each ArgoCD server pod |
| `server.resources.requests.memory` | `512Mi` | Memory request for each ArgoCD server pod |
| `server.resources.limits.cpu` | `1` | CPU limit for each ArgoCD server pod |
| `server.resources.limits.memory` | `1Gi` | Memory limit for each ArgoCD server pod |
| `controller.replicas` | `2` | Number of ArgoCD application controller replicas (HA) |
| `controller.resources.requests.cpu` | `500m` | CPU request for each controller pod |
| `controller.resources.requests.memory` | `1Gi` | Memory request for each controller pod |
| `controller.resources.limits.cpu` | `2` | CPU limit for each controller pod |
| `controller.resources.limits.memory` | `2Gi` | Memory limit for each controller pod |
| `repoServer.replicas` | `2` | Number of ArgoCD repo server replicas (HA) |
| `repoServer.resources.requests.cpu` | `500m` | CPU request for each repo server pod |
| `repoServer.resources.requests.memory` | `512Mi` | Memory request for each repo server pod |
| `repoServer.resources.limits.cpu` | `1` | CPU limit for each repo server pod |
| `repoServer.resources.limits.memory` | `1Gi` | Memory limit for each repo server pod |
| `applicationSet.replicas` | `2` | Number of ApplicationSet controller replicas (HA) |
| `configs.rbac.policy.default` | `role:readonly` | Default RBAC policy applied to unauthenticated or unmapped users |

### prd/app.yaml

ArgoCD `Application` resource for self-management in the production environment. Manual sync only (no `automated` block).

| Key | Value | Description |
|-----|-------|-------------|
| `apiVersion` | `argoproj.io/v1alpha1` | ArgoCD Application API version |
| `kind` | `Application` | Kubernetes resource kind |
| `metadata.name` | `argocd-prd` | Name of the ArgoCD Application resource |
| `metadata.namespace` | `argocd` | Namespace where the Application resource is created |
| `spec.project` | `default` | ArgoCD project that this Application belongs to |
| `spec.source.repoURL` | `https://argoproj.github.io/argo-helm` | Helm chart repository URL |
| `spec.source.chart` | `argo-cd` | Helm chart name |
| `spec.source.targetRevision` | `9.4.7` | Helm chart version (pinned for production) |
| `spec.source.helm.valueFiles[0]` | `values.yaml` | Path to the Helm values file |
| `spec.destination.server` | `https://prd-cluster.example.com` | OpenShift API server URL for the production cluster |
| `spec.destination.namespace` | `argocd` | Target namespace for the ArgoCD installation |
| `spec.syncPolicy.syncOptions[0]` | `CreateNamespace=true` | Create the target namespace if it does not exist |
| `spec.syncPolicy.syncOptions[1]` | `ServerSideApply=true` | Use server-side apply for resource reconciliation |

---

## Per-Environment Differences

### Replica Counts

| Component | dev | qa | stg | prd |
|-----------|-----|----|-----|-----|
| `server.replicas` | 1 | 1 | 2 | 2 |
| `controller.replicas` | 1 | 1 | 2 | 2 |
| `repoServer.replicas` | 1 | 1 | 2 | 2 |
| `applicationSet.replicas` | 1 | 1 | 2 | 2 |

### Resource Requests and Limits

| Component | Resource | dev | qa | stg | prd |
|-----------|----------|-----|----|-----|-----|
| **server** | requests.cpu | 250m | 250m | 500m | 500m |
| **server** | requests.memory | 256Mi | 256Mi | 512Mi | 512Mi |
| **server** | limits.cpu | 500m | 500m | 1 | 1 |
| **server** | limits.memory | 512Mi | 512Mi | 1Gi | 1Gi |
| **controller** | requests.cpu | 250m | 250m | 500m | 500m |
| **controller** | requests.memory | 512Mi | 512Mi | 1Gi | 1Gi |
| **controller** | limits.cpu | 1 | 1 | 2 | 2 |
| **controller** | limits.memory | 1Gi | 1Gi | 2Gi | 2Gi |
| **repoServer** | requests.cpu | 250m | 250m | 500m | 500m |
| **repoServer** | requests.memory | 256Mi | 256Mi | 512Mi | 512Mi |
| **repoServer** | limits.cpu | 500m | 500m | 1 | 1 |
| **repoServer** | limits.memory | 512Mi | 512Mi | 1Gi | 1Gi |

### Configuration Differences

| Setting | dev | qa | stg | prd |
|---------|-----|----|-----|-----|
| `global.domain` | `argocd-dev.example.com` | `argocd-qa.example.com` | `argocd-stg.example.com` | `argocd-prd.example.com` |
| `server.service.type` | `LoadBalancer` | _(not set -- chart default)_ | _(not set -- chart default)_ | _(not set -- chart default)_ |
| `configs.params.server.insecure` | `true` | `true` | _(not set -- defaults to `false`)_ | _(not set -- defaults to `false`)_ |
| `configs.secret.argocdServerAdminPassword` | bcrypt hash (set) | _(not set -- auto-generated)_ | _(not set -- auto-generated)_ | _(not set -- auto-generated)_ |
| `configs.rbac.policy.default` | `role:readonly` | `role:readonly` | `role:readonly` | `role:readonly` |

### app.yaml Sync Policy Differences

| Setting | dev | qa | stg | prd |
|---------|-----|----|-----|-----|
| `syncPolicy.automated.prune` | `true` | _(not set)_ | _(not set)_ | _(not set)_ |
| `syncPolicy.automated.selfHeal` | `true` | _(not set)_ | _(not set)_ | _(not set)_ |
| `syncOptions: CreateNamespace` | `true` | `true` | `true` | `true` |
| `syncOptions: ServerSideApply` | `true` | `true` | `true` | `true` |
| `destination.server` | `https://dev-cluster.example.com` | `https://qa-cluster.example.com` | `https://stg-cluster.example.com` | `https://prd-cluster.example.com` |

> **Note:** Only dev has automated sync with prune and self-heal enabled on the ArgoCD self-management Application. QA, staging, and production require manual sync triggers, providing an additional safety gate for ArgoCD upgrades in higher environments.

---

## How These Values Are Consumed

These files are consumed only when using **Option B -- Standalone ArgoCD via Helm** on OpenShift. If you are using the OpenShift GitOps Operator (Option A, recommended), these files are not needed.

### 1. Initial Bootstrap via Helm CLI

ArgoCD is installed directly via `helm install` using the `values.yaml` for the target environment:

```bash
helm upgrade --install argocd argo-cd/argo-cd \
  --namespace argocd \
  --create-namespace \
  -f apps/argocd/<env>/values.yaml \
  --wait --timeout 5m
```

This can be performed by:
- `.github/workflows/full-deploy.yaml` -- GitHub Actions CI/CD pipeline
- `.azure-pipelines/full-deploy.yaml` -- Azure DevOps CI/CD pipeline

### 2. Self-Management via app.yaml

After the initial Helm bootstrap, the `app.yaml` in each environment directory can be applied to enable **ArgoCD self-management** (the "App of Apps" pattern for ArgoCD itself):

```bash
oc apply -f apps/argocd/<env>/app.yaml
```

Once applied, ArgoCD monitors its own Helm chart and values, automatically (dev) or manually (qa/stg/prd) reconciling any drift between the desired state in Git and the live state on the cluster.

### 3. Air-Gapped / Internal Registry Scenarios

In air-gapped or restricted network environments, the `values.yaml` files may need to be updated to reference an internal Helm chart repository and container image registry. See `README-INTERNAL-REGISTRY.md` for the full list of files that require modification.

---

## OpenShift GitOps Operator Relationship

There are two supported approaches for running ArgoCD on OpenShift:

### Option A -- OpenShift GitOps Operator (Recommended)

The OpenShift GitOps Operator installs and manages its own ArgoCD instance in the `openshift-gitops` namespace. In this scenario:

- The `apps/argocd/` Helm values and `app.yaml` files are **not used**.
- ArgoCD is managed by the OpenShift operator, not by Helm or by itself.
- The deployment script `scripts/deploy-openshift-dev.sh` skips the Helm install step entirely and instead **verifies** that the OpenShift GitOps ArgoCD server is already running.
- Namespaces must be labeled with `argocd.argoproj.io/managed-by=openshift-gitops` to allow the operator-managed ArgoCD to deploy into them.
- ApplicationSet resources are deployed from `gitops-config/openshift/<env>/`.
- The ArgoCD UI is accessible via an OpenShift Route rather than a LoadBalancer Service.
- The admin password is stored in the `openshift-gitops-cluster` Secret, not set via Helm values.

### Option B -- Standalone ArgoCD via Helm

If you prefer to manage ArgoCD yourself rather than using the operator, you can install it using the Helm chart with the values from this directory. This is the scenario where `apps/argocd/` is directly consumed.

- ArgoCD is installed into the `argocd` namespace via `helm install`.
- Self-management is enabled by applying the per-environment `app.yaml`.
- You are responsible for upgrades and lifecycle management.
- ApplicationSet resources are still deployed from `gitops-config/openshift/<env>/`.

---

## Installation

### Option A -- OpenShift GitOps Operator (Recommended)

```bash
# 1. Install the OpenShift GitOps Operator from OperatorHub (via UI or CLI)

# 2. Verify the operator-managed ArgoCD is running
oc get pods -n openshift-gitops -l app.kubernetes.io/name=openshift-gitops-server

# 3. Proceed directly to deploying ApplicationSets from gitops-config/openshift/<env>/
#    The apps/argocd/ values are not needed.
```

### Option B -- Standalone ArgoCD via Helm

```bash
# Add the Helm repository
helm repo add argo-cd https://argoproj.github.io/argo-helm
helm repo update

# Install ArgoCD for the target environment (e.g., dev)
helm install argocd argo-cd/argo-cd \
  --namespace argocd \
  --create-namespace \
  -f apps/argocd/dev/values.yaml \
  --wait --timeout 5m

# (Optional) Enable self-management
oc apply -f apps/argocd/dev/app.yaml
```
