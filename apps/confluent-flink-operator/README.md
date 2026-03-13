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

## Values Reference

Each per-environment `values.yaml` configures the Flink Kubernetes Operator Helm chart. The sections below document every field and its implications.

### Image Configuration

| Key | Value | Description |
|-----|-------|-------------|
| `imagePullSecretRef` | `null` | Disables image pull secrets. Set to a Secret name if pulling from a private registry that requires authentication. |
| `image.registry` | `docker.io` | Container registry for the operator image. Change to an internal registry for air-gapped deployments. |
| `image.repository` | `confluentinc/confluent-operator-flink` | Image repository path. Combined with `image.registry` to form the full image reference. |

### Operator Deployment

| Key | Value | Description |
|-----|-------|-------------|
| `replicas` | `1` (dev) / `2` (qa, stg, prd) | Number of operator pod replicas. Multiple replicas enable leader-elected HA -- only one replica actively reconciles while the other stands by. |
| `watchNamespaces` | `[confluent-<env>]` | List of namespaces the operator watches for Flink custom resources. Provides environment isolation. |

> **Implications:**
> - **`replicas: 2`** -- In qa/stg/prd, two replicas run with leader election. If the active replica fails, the standby takes over within seconds. Dev uses a single replica to conserve resources.
> - **`watchNamespaces`** -- Each environment's operator is strictly isolated. The dev operator cannot see or modify resources in `confluent-qa`.

### Scheduling

| Key | Value | Description |
|-----|-------|-------------|
| `affinity` | `{}` | Pod affinity/anti-affinity rules. Empty means no scheduling constraints. |
| `tolerations` | `[]` | Pod tolerations for node taints. Empty means the operator pods will not schedule on tainted nodes. |

### Pod Security

| Key | Value | Description |
|-----|-------|-------------|
| `podSecurityContext.enabled` | `false` | Disables the chart's built-in pod security context settings. On OpenShift, the SCC admission controller injects `runAsUser`, `fsGroup`, and other security context fields automatically. |

### Service Account

| Key | Value | Description |
|-----|-------|-------------|
| `serviceAccount.create` | `true` | The Helm chart creates the ServiceAccount during installation. |
| `serviceAccount.name` | `flink-kubernetes-operator` | Name of the ServiceAccount used by the operator pods. Must match SCC bindings. |

### Metrics

| Key | Value | Description |
|-----|-------|-------------|
| `metrics.prometheus.enabled` | `true` | Enables the Prometheus metrics endpoint on the operator pod (port 9999). |

### Logging

| Key | Value | Description |
|-----|-------|-------------|
| `logging.level` | `INFO` | Operator log verbosity. Set to `DEBUG` for troubleshooting. |

### Webhook

| Key | Value | Description |
|-----|-------|-------------|
| `webhook.create` | `true` | Creates a ValidatingWebhookConfiguration for Flink CRDs. TLS certificates are provisioned automatically by cert-manager. |

### Pod Metadata

| Key | Value | Description |
|-----|-------|-------------|
| `podAnnotations` | Prometheus scrape | `prometheus.io/scrape: "true"` and `prometheus.io/port: "9999"`. Enables automatic Prometheus metrics collection. |
| `podLabels` | `{}` | Additional labels for operator pods. |

### Default Flink Configuration

The `defaultConfiguration` block injects base settings into all Flink workloads managed by the operator. Individual CRs can override these.

```yaml
defaultConfiguration:
  flink-conf.yaml: |
    kubernetes.operator.metrics.reporter.prom.factory.class: org.apache.flink.metrics.prometheus.PrometheusReporterFactory
    kubernetes.operator.metrics.reporter.prom.port: "9999"
```

This enables Prometheus metrics collection for Flink jobs by default, matching the operator-level metrics configuration.

### Resources

| Key | dev | qa | stg | prd |
|-----|-----|----|-----|-----|
| `resources.requests.cpu` | `100m` | `200m` | `200m` | `200m` |
| `resources.requests.memory` | `256Mi` | `256Mi` | `512Mi` | `512Mi` |
| `resources.limits.cpu` | `500m` | `500m` | `1` | `1` |
| `resources.limits.memory` | `512Mi` | `512Mi` | `1Gi` | `1Gi` |

Lower environments use minimal resources to reduce cost. Staging and production receive higher limits and a 512Mi memory request (50% of the 1Gi limit) to handle larger Flink cluster reconciliation and avoid OOM under sustained load.

---

## Per-Environment Differences

The following table highlights what varies across the four environments. Fields not listed here are identical in all environments.

| Key | dev | qa | stg | prd |
|-----|-----|----|-----|-----|
| `replicas` | `1` | `2` | `2` | `2` |
| `watchNamespaces[0]` | `confluent-dev` | `confluent-qa` | `confluent-stg` | `confluent-prd` |
| `resources.requests.cpu` | `100m` | `200m` | `200m` | `200m` |
| `resources.requests.memory` | `256Mi` | `256Mi` | `512Mi` | `512Mi` |
| `resources.limits.cpu` | `500m` | `500m` | `1` | `1` |
| `resources.limits.memory` | `512Mi` | `512Mi` | `1Gi` | `1Gi` |

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
