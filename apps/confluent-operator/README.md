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

## Values Reference

Each per-environment `values.yaml` configures the CFK operator Helm chart. The sections below document every field and its implications.

### Licensing

| Key | Value | Description |
|-----|-------|-------------|
| `licenseSecretRef` | `confluent-license` | References a Kubernetes Secret containing the Confluent license key. The Secret must exist in the operator's namespace before deployment. Typically provisioned via an ExternalSecrets operator or manually created. |

> **Implication:** Without a valid license Secret, the operator starts in evaluation mode with a 30-day trial. After expiration, CFK stops reconciling CRDs. Ensure the Secret is provisioned before or alongside the operator deployment.

### Image Configuration

| Key | Value | Description |
|-----|-------|-------------|
| `imagePullSecretRef` | `null` | Disables image pull secrets. Set to a Secret name if pulling from a private registry that requires authentication. |
| `image.registry` | `docker.io` | Container registry for the operator image. Change to an internal registry (e.g., `registry.example.com`) when using an air-gapped or mirrored setup. |
| `image.repository` | `confluentinc/confluent-operator` | Image repository path. Combined with `image.registry` to form the full image reference. |

> **Implication:** When deploying to an environment with a private registry, update `image.registry` to point to the internal mirror. If the registry requires authentication, set `imagePullSecretRef` to the name of a pull secret containing the registry credentials.

### Operator Deployment

| Key | Value | Description |
|-----|-------|-------------|
| `replicas` | `1` (dev) / `2` (qa, stg, prd) | Number of operator pod replicas. Multiple replicas enable leader-elected high availability -- only one replica actively reconciles while the other stands by. |
| `namespaced` | `true` | Restricts the operator to watch only the namespaces listed in `namespaceList` instead of the entire cluster. Provides environment isolation. |
| `namespaceList` | `[confluent-<env>]` | List of namespaces the operator watches for Confluent CRDs. With `namespaced: true`, the operator ignores resources in all other namespaces. |
| `kRaftEnabled` | `true` | Enables KRaft consensus mode for Kafka clusters managed by this operator. Eliminates the dependency on ZooKeeper. |
| `enableCMFDay2Ops` | `true` | Enables Confluent Manager for Apache Flink (CMF) Day-2 operations support. Allows CMF to manage Flink application lifecycle through CFK. |
| `fipsmode` | `true` | Enables FIPS 140-2 compliant cryptography. The operator uses only FIPS-validated cryptographic modules for all TLS and encryption operations. |

> **Implications:**
> - **`replicas: 2`** -- In qa/stg/prd, two replicas run with leader election. If the active replica fails, the standby takes over within seconds. Dev uses a single replica to conserve resources.
> - **`namespaced: true` + `namespaceList`** -- Each environment's operator is strictly isolated. The dev operator cannot see or modify resources in `confluent-qa`. This prevents accidental cross-environment changes and limits blast radius.
> - **`fipsmode: true`** -- Required for environments subject to federal compliance (FedRAMP, FISMA, CMMC). Adds a small performance overhead due to FIPS-validated crypto implementations. All components managed by the operator (Kafka, SR, etc.) must also be configured for FIPS if end-to-end compliance is required.

### Scheduling

| Key | Value | Description |
|-----|-------|-------------|
| `affinity` | `{}` | Pod affinity/anti-affinity rules. Empty means no scheduling constraints beyond what Kubernetes assigns. |
| `tolerations` | `[]` | Pod tolerations for node taints. Empty means the operator pods will not schedule on tainted nodes. |

> **Implication:** These are left empty as placeholders. In production, consider adding:
> - **Anti-affinity** to spread operator replicas across nodes/zones for HA
> - **Tolerations** if Confluent workloads run on dedicated tainted nodes
>
> Example anti-affinity (add to stg/prd when needed):
> ```yaml
> affinity:
>   podAntiAffinity:
>     preferredDuringSchedulingIgnoredDuringExecution:
>       - weight: 100
>         podAffinityTerm:
>           labelSelector:
>             matchExpressions:
>               - key: app
>                 operator: In
>                 values:
>                   - confluent-operator
>           topologyKey: kubernetes.io/hostname
> ```

### Pod Security

| Key | Value | Description |
|-----|-------|-------------|
| `podSecurity.enabled` | `false` | Disables the chart's built-in pod security context settings. On OpenShift, the SCC admission controller injects `runAsUser`, `fsGroup`, and other security context fields automatically. |

> **Implication:** This replaces the `openshift-overlay.yaml` approach of nulling individual fields. With `podSecurity.enabled: false`, the chart skips all security context configuration entirely, letting OpenShift's SCC handle it. The `openshift-overlay.yaml` file is retained for backward compatibility but is no longer strictly necessary when this value is set.

### Service Account

| Key | Value | Description |
|-----|-------|-------------|
| `serviceAccount.create` | `true` | The Helm chart creates the ServiceAccount during installation. |
| `serviceAccount.name` | `confluent` | Name of the ServiceAccount used by the operator pods. |

> **Implication:** The SA name `confluent` (instead of the default `confluent-operator`) must match the SCC bindings. If using imperative SCC grants, update them:
> ```bash
> oc adm policy add-scc-to-user confluent-scc -z confluent -n confluent-<env>
> ```
> Any existing bindings for `confluent-operator` should be removed or updated.

### RBAC

| Key | Value | Description |
|-----|-------|-------------|
| `rbac` | `false` | Disables Helm-managed RBAC resources (ClusterRole, ClusterRoleBinding, Role, RoleBinding). The customer provisions these out-of-band through their own RBAC pipeline. |
| `clusterRole.openshift` | `true` | When RBAC is managed externally, this flag tells the operator to expect OpenShift-specific permissions (SCC access, Route management). |

> **Implications:**
> - **`rbac: false`** -- The Helm chart will NOT create any RBAC resources. The cluster administrator must pre-provision the required ClusterRoles and bindings before deploying the operator. Without them, the operator pod starts but cannot reconcile any Confluent CRDs (it will log permission errors).
> - **Required permissions** (must be granted externally):
>   - CRUD on all Confluent CRDs (`kafkas.platform.confluent.io`, `kraftcontrollers.platform.confluent.io`, etc.)
>   - CRUD on Pods, Services, ConfigMaps, Secrets, StatefulSets in the target namespace
>   - Watch/List on Namespaces (for namespaced mode)
>   - OpenShift: Use SCC (`confluent-scc`), manage Routes
> - **`clusterRole.openshift: true`** -- Ensures the operator attempts OpenShift-specific operations (SCC validation, Route creation). Without this on OpenShift, the operator may fail to create Routes for external access.

### Admission Webhooks

| Key | Value | Description |
|-----|-------|-------------|
| `webhooks.enabled` | `false` | Disables CFK's admission webhooks (ValidatingWebhookConfiguration). |
| `webhooks.port` | `8443` | Port the webhook server listens on (unused when disabled). |
| `webhooks.tls.secretRef` | `""` | TLS Secret for webhook server (unused when disabled). |
| `webhooks.tls.directoryPathInContainer` | `""` | Path to TLS certs in the container (unused when disabled). |

> **Implications:**
> - **`webhooks.enabled: false`** -- CFK will NOT validate Confluent CRDs at admission time. Invalid manifests (e.g., a Kafka CR with conflicting settings) will be accepted by the API server and only fail during reconciliation. This shifts error detection from apply-time to reconciliation-time.
> - **Why disable?** Webhook TLS certificate management adds operational complexity. The customer handles validation through CI/CD pipeline checks and GitOps review processes instead.
> - **Risk:** Misconfigurations reach the cluster unchecked. Ensure the CI/CD pipeline validates Confluent CRDs against the CFK schema before merging.

### Pod Metadata

| Key | Value | Description |
|-----|-------|-------------|
| `pod.annotations` | Prometheus scrape | Enables Prometheus metrics scraping: `prometheus.io/scrape: "true"` and `prometheus.io/port: "7778"`. Add additional annotations as needed. |
| `pod.labels` | `{}` | Additional labels for operator pods. Empty means only the chart's default labels are applied. |

> **Implication:** Prometheus scrape annotations are set explicitly so that metrics collection works out of the box. The CFK operator exposes metrics on port `7778`.

### Resources

| Key | dev | qa | stg | prd |
|-----|-----|----|-----|-----|
| `resources.requests.cpu` | `100m` | `200m` | `200m` | `200m` |
| `resources.requests.memory` | `256Mi` | `256Mi` | `512Mi` | `512Mi` |
| `resources.limits.cpu` | `500m` | `500m` | `1` | `1` |
| `resources.limits.memory` | `512Mi` | `512Mi` | `1Gi` | `1Gi` |

Lower environments use minimal resources to reduce cost. Staging and production receive higher limits and a 512Mi memory request (50% of the 1Gi limit) to handle larger cluster sizes and avoid OOM under sustained reconciliation load.

---

## Per-Environment Differences

| Key | dev | qa | stg | prd |
|-----|-----|----|-----|-----|
| `replicas` | `1` | `2` | `2` | `2` |
| `namespaceList` | `[confluent-dev]` | `[confluent-qa]` | `[confluent-stg]` | `[confluent-prd]` |
| `resources.requests.cpu` | `100m` | `200m` | `200m` | `200m` |
| `resources.requests.memory` | `256Mi` | `256Mi` | `512Mi` | `512Mi` |
| `resources.limits.cpu` | `500m` | `500m` | `1` | `1` |
| `resources.limits.memory` | `512Mi` | `512Mi` | `1Gi` | `1Gi` |

All other values are identical across environments.

---

## OpenShift Overlay (`openshift-overlay.yaml`)

### Purpose

The `openshift-overlay.yaml` nulls out `fsGroup` and `runAsUser` so OpenShift's SCC can inject the correct values. With `podSecurity.enabled: false` now set in all values files, this overlay is **redundant** but retained for backward compatibility.

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
| `podSecurity.securityContext.fsGroup` | `null` | Removes hard-coded `fsGroup`. Redundant when `podSecurity.enabled: false`. |
| `podSecurity.securityContext.runAsUser` | `null` | Removes hard-coded `runAsUser`. Redundant when `podSecurity.enabled: false`. |

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

## Prerequisites

Before deploying the operator, ensure:

1. **License Secret** -- A Secret named `confluent-license` containing the Confluent license key exists in the target namespace
2. **RBAC** -- Since `rbac: false`, the required ClusterRoles and bindings must be pre-provisioned by the cluster administrator
3. **SCC bindings** -- The ServiceAccount `confluent` must be bound to the `confluent-scc` SCC:
   ```bash
   oc adm policy add-scc-to-user confluent-scc -z confluent -n confluent-<env>
   ```

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

# Expected: 1 pod in Running state (dev) or 2 pods (qa/stg/prd)
```
