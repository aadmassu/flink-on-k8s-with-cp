# cert-manager

X.509 certificate management for OpenShift. This directory contains the per-environment Helm values and an OpenShift overlay for the [cert-manager](https://cert-manager.io/) Helm chart. cert-manager is a **prerequisite** for the Flink Kubernetes Operator, which uses it to provision TLS certificates for its webhook endpoints.

## Helm Chart

| Field | Value |
|-------|-------|
| **Chart** | `cert-manager` |
| **Repository** | `https://charts.jetstack.io` |
| **Version** | `v1.19.4` (pinned) |

## Directory Structure

```
apps/cert-manager/
|-- README.md                  # This file
|-- openshift-overlay.yaml     # Additional overrides applied on OpenShift clusters
|-- dev/
|   +-- values.yaml            # Helm values for the dev environment
|-- qa/
|   +-- values.yaml            # Helm values for the qa environment
|-- stg/
|   +-- values.yaml            # Helm values for the stg environment
+-- prd/
    +-- values.yaml            # Helm values for the prd environment
```

## Base Values (per-environment `values.yaml`)

Each environment directory contains a `values.yaml` that is passed to the cert-manager Helm chart. The table below documents every field present in these files.

| Key | Default Value (dev/qa) | Description |
|-----|------------------------|-------------|
| `crds.enabled` | `true` | Install the cert-manager Custom Resource Definitions (Certificate, Issuer, ClusterIssuer, CertificateRequest, Order, Challenge). Required for cert-manager to function. |
| `resources.requests.cpu` | `50m` | CPU request for the main cert-manager controller pod. Determines the minimum CPU guaranteed by the scheduler. |
| `resources.requests.memory` | `128Mi` | Memory request for the main cert-manager controller pod. Determines the minimum memory guaranteed by the scheduler. |
| `resources.limits.cpu` | `250m` | CPU limit for the main cert-manager controller pod. The container will be throttled if it exceeds this value. |
| `resources.limits.memory` | `256Mi` | Memory limit for the main cert-manager controller pod. The container will be OOM-killed if it exceeds this value. |

## OpenShift Overlay (`openshift-overlay.yaml`)

### Purpose

On OpenShift clusters, this overlay file is applied **after** the environment-specific `values.yaml`. It disables PodSecurityPolicy (PSP) resources because OpenShift uses Security Context Constraints (SCCs) instead of PodSecurityPolicies. Applying PSPs on OpenShift is unnecessary and can cause conflicts with the SCC admission controller.

### How It Is Applied

The OpenShift ApplicationSets (in `gitops-config/openshift/`) include the overlay as a second valueFiles entry:

```yaml
helm:
  valueFiles:
    - $values/apps/cert-manager/{{environment}}/values.yaml
    - $values/apps/cert-manager/openshift-overlay.yaml
```

Because Helm merges value files in order, keys in `openshift-overlay.yaml` override any matching keys from the environment `values.yaml`.

### Fields

| Key | Value | Description |
|-----|-------|-------------|
| `global.podSecurityPolicy.enabled` | `false` | Disables creation of PodSecurityPolicy resources. OpenShift uses Security Context Constraints (SCCs) rather than PSPs, so PSP resources are not needed and would be ignored or cause issues. |

## Per-Environment Differences

The following table shows every field and how its value varies across the four environments. Fields that are identical in all environments are marked with the shared value; fields that differ are highlighted.

| Key | dev | qa | stg | prd |
|-----|-----|----|-----|-----|
| `crds.enabled` | `true` | `true` | `true` | `true` |
| `resources.requests.cpu` | `50m` | `50m` | **`100m`** | **`100m`** |
| `resources.requests.memory` | `128Mi` | `128Mi` | `128Mi` | `128Mi` |
| `resources.limits.cpu` | `250m` | `250m` | **`500m`** | **`500m`** |
| `resources.limits.memory` | `256Mi` | `256Mi` | **`512Mi`** | **`512Mi`** |

**Summary of differences:**

- **dev and qa** share identical, lower resource allocations (50m/128Mi requests, 250m/256Mi limits), appropriate for lightweight non-production workloads.
- **stg and prd** share identical, higher resource allocations (100m/128Mi requests, 500m/512Mi limits), sized for production-grade workloads and stability.

## How These Values Are Consumed by the ApplicationSet

The cert-manager ApplicationSets live under `gitops-config/openshift/` and use the ArgoCD **multi-source** pattern with `$values/` references:

1. **Source 1 -- Helm chart:** Points to the remote Helm repository (`https://charts.jetstack.io`, chart `cert-manager`, version `v1.19.4`). The `helm.valueFiles` field references paths resolved via the `$values` ref.
2. **Source 2 -- Git repo (ref: values):** Points to this Git repository at `HEAD`. This source is aliased as `values`, making the repo root available under the `$values/` prefix.

At sync time, ArgoCD resolves `$values/apps/cert-manager/{{environment}}/values.yaml` to the actual file in this repository, reads its contents, and passes them to `helm template` / `helm install`.

### ApplicationSet Locations

| Environment | ApplicationSet Path |
|-------------|---------------------|
| dev | `gitops-config/openshift/dev/cert-manager-application-set.yaml` |
| qa | `gitops-config/openshift/qa/cert-manager-application-set.yaml` |
| stg | `gitops-config/openshift/stg/cert-manager-application-set.yaml` |
| prd | `gitops-config/openshift/prd/cert-manager-application-set.yaml` |

### Sync Policy

All environments use automated sync with prune and self-heal enabled.

| Environment | Sync Policy | Prune | Self-Heal | Sync Options |
|-------------|-------------|-------|-----------|--------------|
| dev | Automated | Yes | Yes | `CreateNamespace=true`, `ServerSideApply=true` |
| qa | Automated | Yes | Yes | `CreateNamespace=true`, `ServerSideApply=true` |
| stg | Automated | Yes | Yes | `CreateNamespace=true`, `ServerSideApply=true` |
| prd | Automated | Yes | Yes | `CreateNamespace=true`, `ServerSideApply=true` |

## Target Namespace

Deployed to the `cert-manager` namespace. The namespace is created automatically via the `CreateNamespace=true` sync option.

## Dependencies

- **Required by:** Flink Kubernetes Operator (for webhook TLS certificates)
- **Depends on:** OpenShift GitOps (must be running to process the ApplicationSet resource)

## Deployment

```bash
# Apply the ApplicationSet for your target environment (e.g., dev)
oc apply -f gitops-config/openshift/dev/cert-manager-application-set.yaml

# Wait for the application to become healthy
oc wait --for=jsonpath='{.status.health.status}'=Healthy \
  application/cert-manager-dev -n openshift-gitops --timeout=180s
```

## Verification

```bash
# List cert-manager pods
oc get pods -n cert-manager
```

Expected output: 3 pods running -- `cert-manager` (controller), `cert-manager-cainjector`, and `cert-manager-webhook`.
