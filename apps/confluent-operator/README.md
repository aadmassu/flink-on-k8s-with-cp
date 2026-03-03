# Confluent Operator (CFK) -- Helm Values

This directory contains the **Helm values files** for deploying the [Confluent for Kubernetes (CFK)](https://docs.confluent.io/operator/current/overview.html) operator across all environments on OpenShift. CFK is the Kubernetes operator that manages the full lifecycle of Confluent Platform components -- it watches for custom resources such as `KRaftController`, `Kafka`, `SchemaRegistry`, `Connect`, `ksqlDB`, and `ControlCenter`, and reconciles them to the desired state.

The values files here are **not applied directly**. They are consumed by ArgoCD ApplicationSets in `gitops-config/openshift/` via the Helm multi-source `$values/` reference pattern.

## Helm Chart

| Field | Value |
|-------|-------|
| **Chart** | `confluent-for-kubernetes` |
| **Repository** | `https://packages.confluent.io/helm` |
| **Version** | `0.1351.59` (pinned) |

## Directory Structure

```
apps/confluent-operator/
|-- README.md                  # This file
|-- openshift-overlay.yaml     # OpenShift-specific overrides (nulls security contexts)
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

## Base Values (`<env>/values.yaml`)

Each per-environment `values.yaml` configures the CFK operator Helm chart. The table below documents every field present in these files.

| Key | Value | Description |
|-----|-------|-------------|
| `namespaced` | `true` | Restricts the operator to watch only its own namespace instead of the entire cluster. Each environment gets its own isolated operator instance deployed into `confluent-<env>`. |
| `kRaftEnabled` | `true` | Enables KRaft consensus mode for Kafka clusters managed by this operator. Eliminates the dependency on ZooKeeper, reducing operational complexity. |
| `resources.requests.cpu` | `100m` (dev) / `200m` (qa, stg, prd) | CPU resource request for the operator pod. The scheduler uses this to place the pod on a node with sufficient capacity. |
| `resources.requests.memory` | `256Mi` | Memory resource request for the operator pod. Identical across all environments. |
| `resources.limits.cpu` | `500m` (dev, qa) / `1` (stg, prd) | Maximum CPU the operator pod may consume. Higher environments use a full core to handle larger reconciliation workloads. |
| `resources.limits.memory` | `512Mi` (dev, qa) / `1Gi` (stg, prd) | Maximum memory the operator pod may consume. Higher environments double the limit to accommodate more concurrent CRD reconciliation. |

### Key Design Choices

- **Namespaced mode** (`namespaced: true`) -- The operator only manages Confluent resources within its own namespace (`confluent-<env>`). This provides strong environment isolation: each environment gets its own independent operator instance and there is no cross-environment blast radius.
- **KRaft mode** (`kRaftEnabled: true`) -- Uses the KRaft consensus protocol built into Kafka itself, removing the need for a separate ZooKeeper ensemble and simplifying the overall architecture.

---

## OpenShift Overlay (`openshift-overlay.yaml`)

### Purpose

On OpenShift, pods run under [Security Context Constraints (SCCs)](https://docs.openshift.com/container-platform/latest/authentication/managing-security-context-constraints.html). The default `restricted` SCC assigns UIDs and `fsGroup` values dynamically from the namespace's allocated range. When a Helm chart hard-codes `runAsUser` or `fsGroup` to a specific numeric value, those values conflict with the SCC and the pod fails to schedule.

The `openshift-overlay.yaml` file **nulls out** the security context fields so that OpenShift's SCC admission controller can inject the correct values automatically.

### How It Is Applied

The ApplicationSet adds this file as a **second** values file after the per-environment values file. Because Helm merges values files in order (last wins), the overlay's `null` values overwrite any defaults baked into the upstream chart:

```yaml
helm:
  valueFiles:
    - $values/apps/confluent-operator/{{environment}}/values.yaml
    - $values/apps/confluent-operator/openshift-overlay.yaml    # <-- overlay applied second
```

### Field Reference

| Key | Value | Description |
|-----|-------|-------------|
| `podSecurity.securityContext.fsGroup` | `null` | Removes any hard-coded `fsGroup` from the operator pod spec. Allows OpenShift's SCC to inject the namespace-allocated supplemental group, ensuring the pod can write to mounted volumes. |
| `podSecurity.securityContext.runAsUser` | `null` | Removes any hard-coded `runAsUser` from the operator pod spec. Allows OpenShift's SCC to assign a UID from the namespace's allocated UID range, satisfying the `restricted` SCC policy. |

---

## Per-Environment Differences

The table below summarizes every value that varies across the four environments. Fields not listed here are **identical** in all environments.

| Key | dev | qa | stg | prd |
|-----|-----|----|-----|-----|
| `resources.requests.cpu` | `100m` | `200m` | `200m` | `200m` |
| `resources.requests.memory` | `256Mi` | `256Mi` | `256Mi` | `256Mi` |
| `resources.limits.cpu` | `500m` | `500m` | `1` | `1` |
| `resources.limits.memory` | `512Mi` | `512Mi` | `1Gi` | `1Gi` |

> **Note:** `namespaced` and `kRaftEnabled` are set to `true` in every environment and are not expected to vary.

### Resource Scaling Rationale

| Tier | Environments | CPU Request | CPU Limit | Memory Request | Memory Limit |
|------|-------------|-------------|-----------|----------------|--------------|
| Lower | dev | 100m | 500m | 256Mi | 512Mi |
| Mid | qa | 200m | 500m | 256Mi | 512Mi |
| Upper | stg, prd | 200m | 1 | 256Mi | 1Gi |

Lower environments use minimal resources to reduce cost. Staging and production mirror each other and receive higher limits to handle larger cluster sizes and faster reconciliation loops.

---

## How These Values Are Consumed by the ApplicationSet

The CFK operator is deployed through ArgoCD **ApplicationSets** located under `gitops-config/openshift/`:

| Environment | ApplicationSet Location | Values Files Used |
|-------------|------------------------|-------------------|
| dev | `gitops-config/openshift/dev/confluent-operator-application-set.yaml` | `apps/confluent-operator/dev/values.yaml` + `apps/confluent-operator/openshift-overlay.yaml` |
| qa | `gitops-config/openshift/qa/confluent-operator-application-set.yaml` | `apps/confluent-operator/qa/values.yaml` + `apps/confluent-operator/openshift-overlay.yaml` |
| stg | `gitops-config/openshift/stg/confluent-operator-application-set.yaml` | `apps/confluent-operator/stg/values.yaml` + `apps/confluent-operator/openshift-overlay.yaml` |
| prd | `gitops-config/openshift/prd/confluent-operator-application-set.yaml` | `apps/confluent-operator/prd/values.yaml` + `apps/confluent-operator/openshift-overlay.yaml` |

Each ApplicationSet uses the ArgoCD **multi-source** pattern with a `$values` ref:

1. **Source 1 (Helm chart):** Points to `https://packages.confluent.io/helm` with `chart: confluent-for-kubernetes` and `targetRevision: 0.1351.59`. The `helm.valueFiles` array references paths under `$values/apps/confluent-operator/`.
2. **Source 2 (Git ref):** Points to this Git repository and is aliased as `ref: values`. This allows Source 1 to resolve `$values/` paths against the repo contents.

### Sync Policy

| Environment | Sync Policy | Prune | Self-Heal |
|-------------|-------------|-------|-----------|
| dev | Automated | Yes | Yes |
| qa | Manual | -- | -- |
| stg | Manual | -- | -- |
| prd | Manual | -- | -- |

All environments use `CreateNamespace=true` and `ServerSideApply=true` as sync options.

---

## Target Namespace

The operator is deployed into a namespace following the convention `confluent-<env>`:

| Environment | Namespace |
|-------------|-----------|
| dev | `confluent-dev` |
| qa | `confluent-qa` |
| stg | `confluent-stg` |
| prd | `confluent-prd` |

The namespace is created automatically by ArgoCD via the `CreateNamespace=true` sync option.

---

## Dependencies

| Direction | Component | Relationship |
|-----------|-----------|-------------|
| **Required by** | Confluent Platform CRDs (`KRaftController`, `Kafka`, `SchemaRegistry`, `Connect`, `ksqlDB`, `ControlCenter`) | The operator must be running before any Confluent Platform custom resources can be reconciled. |
| **Depends on** | OpenShift GitOps | Must be running to process the ApplicationSet and deploy the operator. |

---

## Deployment

```bash
# Apply the ApplicationSet for the desired environment
oc apply -f gitops-config/openshift/dev/confluent-operator-application-set.yaml

# Wait for the Application to become healthy
oc wait --for=jsonpath='{.status.health.status}'=Healthy \
  application/confluent-operator-dev -n openshift-gitops --timeout=180s
```

## Verification

```bash
# Check the operator pod is running
oc get pods -n confluent-dev -l app=confluent-operator

# Expected: 1 pod in Running state
```
