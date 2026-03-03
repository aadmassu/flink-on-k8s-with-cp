# Confluent Flink Kubernetes Operator

## Overview

This directory contains the **Helm values files** for deploying the [Confluent Flink Kubernetes Operator](https://docs.confluent.io/confluent-operator/current/flink-operator.html) via ArgoCD ApplicationSets on OpenShift. The Flink Kubernetes Operator manages the full lifecycle of Apache Flink workloads on OpenShift -- it watches for Flink custom resources (`FlinkDeployment`, `FlinkSessionJob`, etc.) and handles deployment, scaling, upgrades, and teardown of Flink applications.

The Helm chart is pulled directly from the Confluent Helm repository (`https://packages.confluent.io/helm`) at deploy time. The files in this directory only supply the **values overrides**; the chart itself is not vendored into this repository.

### Helm Chart Reference

| Field | Value |
|-------|-------|
| **Chart name** | `flink-kubernetes-operator` |
| **Repository** | `https://packages.confluent.io/helm` |
| **Version** | `1.130.2` (pinned) |

---

## Directory Structure

```
apps/confluent-flink-operator/
|-- README.md                  # This file
|-- openshift-overlay.yaml     # OpenShift-specific overrides (nulls pod security contexts)
|-- dev/
|   +-- values.yaml            # Helm values for the dev environment
|-- qa/
|   +-- values.yaml            # Helm values for the qa environment
|-- stg/
|   +-- values.yaml            # Helm values for the stg environment
+-- prd/
    +-- values.yaml            # Helm values for the prd environment
```

---

## Base Values (Per-Environment `values.yaml`)

Each environment directory (`dev/`, `qa/`, `stg/`, `prd/`) contains a `values.yaml` that overrides the chart defaults. The tables below document every field present in these files.

### `dev/values.yaml`

| Key | Value | Description |
|-----|-------|-------------|
| `watchNamespaces[0]` | `confluent-dev` | Restricts the operator to only watch for Flink custom resources in the `confluent-dev` namespace, providing environment isolation. |
| `metrics.prometheus.enabled` | `true` | Enables the Prometheus metrics endpoint on the operator pod, allowing scraping of operator health and Flink job metrics. |
| `resources.requests.cpu` | `100m` | Minimum CPU reservation for the operator pod. The scheduler uses this to place the pod on a node with sufficient capacity. |
| `resources.requests.memory` | `256Mi` | Minimum memory reservation for the operator pod. |
| `resources.limits.cpu` | `500m` | Maximum CPU the operator pod is allowed to consume. The container will be throttled if it exceeds this. |
| `resources.limits.memory` | `512Mi` | Maximum memory the operator pod is allowed to consume. The container will be OOM-killed if it exceeds this. |

### `qa/values.yaml`

| Key | Value | Description |
|-----|-------|-------------|
| `watchNamespaces[0]` | `confluent-qa` | Restricts the operator to only watch the `confluent-qa` namespace. |
| `metrics.prometheus.enabled` | `true` | Enables the Prometheus metrics endpoint. |
| `resources.requests.cpu` | `200m` | Minimum CPU reservation (higher than dev to handle QA test workloads). |
| `resources.requests.memory` | `256Mi` | Minimum memory reservation. |
| `resources.limits.cpu` | `500m` | Maximum CPU the operator pod may consume. |
| `resources.limits.memory` | `512Mi` | Maximum memory the operator pod may consume. |

### `stg/values.yaml`

| Key | Value | Description |
|-----|-------|-------------|
| `watchNamespaces[0]` | `confluent-stg` | Restricts the operator to only watch the `confluent-stg` namespace. |
| `metrics.prometheus.enabled` | `true` | Enables the Prometheus metrics endpoint. |
| `resources.requests.cpu` | `200m` | Minimum CPU reservation. |
| `resources.requests.memory` | `256Mi` | Minimum memory reservation. |
| `resources.limits.cpu` | `1` | Maximum CPU (1 full core -- higher than lower environments to support pre-production load). |
| `resources.limits.memory` | `1Gi` | Maximum memory (1 GiB -- doubled from lower environments). |

### `prd/values.yaml`

| Key | Value | Description |
|-----|-------|-------------|
| `watchNamespaces[0]` | `confluent-prd` | Restricts the operator to only watch the `confluent-prd` namespace. |
| `metrics.prometheus.enabled` | `true` | Enables the Prometheus metrics endpoint. |
| `resources.requests.cpu` | `200m` | Minimum CPU reservation. |
| `resources.requests.memory` | `256Mi` | Minimum memory reservation. |
| `resources.limits.cpu` | `1` | Maximum CPU (1 full core -- matches staging for production-grade capacity). |
| `resources.limits.memory` | `1Gi` | Maximum memory (1 GiB -- matches staging). |

---

## Per-Environment Differences

The following table highlights what varies across the four environments. Fields not listed here are identical in all environments.

| Key | dev | qa | stg | prd |
|-----|-----|----|-----|-----|
| `watchNamespaces[0]` | `confluent-dev` | `confluent-qa` | `confluent-stg` | `confluent-prd` |
| `resources.requests.cpu` | `100m` | `200m` | `200m` | `200m` |
| `resources.requests.memory` | `256Mi` | `256Mi` | `256Mi` | `256Mi` |
| `resources.limits.cpu` | `500m` | `500m` | `1` | `1` |
| `resources.limits.memory` | `512Mi` | `512Mi` | `1Gi` | `1Gi` |
| `metrics.prometheus.enabled` | `true` | `true` | `true` | `true` |

**Pattern:** Resource requests and limits increase as you move from dev toward production. Dev has the lightest footprint (`100m` CPU request, `500m` CPU limit, `512Mi` memory limit), while stg and prd share identical, higher allocations (`200m` CPU request, `1` CPU limit, `1Gi` memory limit).

---

## OpenShift Overlay (`openshift-overlay.yaml`)

### Purpose

On OpenShift clusters, pod security is managed by [Security Context Constraints (SCCs)](https://docs.openshift.com/container-platform/latest/authentication/managing-security-context-constraints.html) rather than native `securityContext` fields. When a Helm chart sets explicit `runAsUser`, `runAsGroup`, or `fsGroup` values, those can conflict with the UID/GID ranges assigned by the OpenShift SCC admission controller.

The `openshift-overlay.yaml` file **nulls out** all pod-level security context fields so that OpenShift's SCC mechanism can assign the correct values automatically. This overlay is layered **on top of** the per-environment `values.yaml` using Helm's multi-value-file merging (last file wins).

### Field Reference

| Key | Value | Description |
|-----|-------|-------------|
| `podSecurityContext.runAsUser` | `null` | Removes any explicit user ID so OpenShift SCC can assign the UID from the namespace's allowed range. |
| `podSecurityContext.runAsGroup` | `null` | Removes any explicit group ID so OpenShift SCC can assign the GID from the namespace's allowed range. |
| `podSecurityContext.fsGroup` | `null` | Removes any explicit filesystem group ID so OpenShift SCC can assign the `fsGroup` from the namespace's allowed range. Affects volume ownership for any mounted volumes. |

### How the Overlay Is Applied

The OpenShift ApplicationSets include the overlay as a second values file, merged on top of the per-environment values:

```yaml
helm:
  valueFiles:
    - $values/apps/confluent-flink-operator/{{environment}}/values.yaml
    - $values/apps/confluent-flink-operator/openshift-overlay.yaml
```

---

## How These Values Are Consumed by the ApplicationSet

The Confluent Flink Operator is deployed using ArgoCD **ApplicationSets** located in `gitops-config/openshift/`. Each ApplicationSet uses the [multiple sources with `$values` ref](https://argo-cd.readthedocs.io/en/stable/user-guide/multiple_sources/#helm-value-files-from-external-git-repository) pattern:

1. **Source 1 -- Helm chart:** Pulls the `flink-kubernetes-operator` chart from `https://packages.confluent.io/helm` with pinned version `1.130.2`.
2. **Source 2 -- Git ref (`$values`):** Clones this Git repository and makes it available as `$values`, allowing `valueFiles` to reference paths like `$values/apps/confluent-flink-operator/dev/values.yaml`.

The ApplicationSet uses a **list generator** with `{{environment}}` as a template parameter, which resolves the correct per-environment `values.yaml` path at generation time.

### ApplicationSet Locations

| Environment | ApplicationSet Path |
|-------------|---------------------|
| dev | `gitops-config/openshift/dev/confluent-flink-operator-application-set.yaml` |
| qa | `gitops-config/openshift/qa/confluent-flink-operator-application-set.yaml` |
| stg | `gitops-config/openshift/stg/confluent-flink-operator-application-set.yaml` |
| prd | `gitops-config/openshift/prd/confluent-flink-operator-application-set.yaml` |

---

## cert-manager Dependency

> **cert-manager must be deployed and healthy before installing the Flink Kubernetes Operator.**

The Flink Kubernetes Operator Helm chart creates `Certificate` and `Issuer` custom resources (from the `cert-manager.io/v1` API group) to provision TLS certificates for its **admission webhook** endpoints. These webhooks validate and mutate Flink custom resources before they are persisted to etcd.

If cert-manager is not installed or its CRDs are not available, the Helm install will fail with:

```
no matches for kind "Certificate" in version "cert-manager.io/v1"
```

### Ensuring cert-manager Is Ready

```bash
# Wait for the cert-manager ArgoCD application to report Healthy
oc wait --for=jsonpath='{.status.health.status}'=Healthy \
  application/cert-manager-dev -n openshift-gitops --timeout=180s
```

The ApplicationSets in `gitops-config/openshift/` rely on deploying cert-manager **first** (via its own ApplicationSet) before applying the Flink operator ApplicationSet.

---

## Target Namespace

The operator is deployed to the `confluent-<env>` namespace (e.g., `confluent-dev`, `confluent-qa`). This is the same namespace used by the Confluent Operator (CFK). The namespace is created automatically via the `CreateNamespace=true` sync option in the ApplicationSet.

---

## Sync Policy

| Environment | Sync Policy | Prune | Self-Heal | Notes |
|-------------|-------------|-------|-----------|-------|
| dev | Automated | Yes | Yes | Changes in Git are automatically applied to the cluster. |
| qa | Automated | Yes | Yes | Changes in Git are automatically applied to the cluster. |
| stg | Automated | Yes | Yes | Changes in Git are automatically applied to the cluster. |
| prd | Automated | Yes | Yes | Changes in Git are automatically applied to the cluster. |

All environments use `ServerSideApply=true` to avoid field-manager conflicts with large CRDs.

---

## Sync Options

| Sync Option | Value | Description |
|-------------|-------|-------------|
| `CreateNamespace` | `true` | Automatically creates the target namespace (`confluent-<env>`) if it does not exist. |
| `ServerSideApply` | `true` | Uses server-side apply for resource reconciliation, which avoids annotation size limits and handles field ownership conflicts. |

---

## Dependencies

| Direction | Component | Relationship |
|-----------|-----------|--------------|
| **Depends on** | cert-manager | Provides the `Certificate` and `Issuer` CRDs required for webhook TLS certificates. |
| **Depends on** | OpenShift GitOps | Deploys and reconciles the Helm release via ApplicationSets. |
| **Required by** | Confluent Flink Manager CRDs | The Flink Manager requires the operator to be running before Flink workloads can be submitted. |

---

## Deployment

```bash
# 1. Ensure cert-manager is healthy
oc wait --for=jsonpath='{.status.health.status}'=Healthy \
  application/cert-manager-dev -n openshift-gitops --timeout=180s

# 2. Apply the ApplicationSet
oc apply -f gitops-config/openshift/dev/confluent-flink-operator-application-set.yaml

# 3. Wait for the Flink operator application to become Healthy
oc wait --for=jsonpath='{.status.health.status}'=Healthy \
  application/confluent-flink-operator-dev -n openshift-gitops --timeout=180s
```

---

## Verification

```bash
# Check that the operator pod is running (2/2 containers: operator + webhook)
oc get pods -n confluent-dev -l app.kubernetes.io/name=flink-kubernetes-operator

# Check the ArgoCD application status
oc get application confluent-flink-operator-dev -n openshift-gitops -o jsonpath='{.status.health.status}'
```

Expected output: the `flink-kubernetes-operator-*` pod should show `2/2` containers in `Running` state (the operator container and the webhook sidecar).
