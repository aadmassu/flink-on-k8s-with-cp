# Helm Values Reference -- Operator Charts

This document provides a consolidated reference for the Helm values used to deploy the **Confluent for Kubernetes (CFK) Operator** and the **Flink Kubernetes Operator** across all environments. Both operators are deployed via ArgoCD ApplicationSets using the Helm multi-source pattern.

For per-operator deep-dives (overlay mechanics, ApplicationSet wiring, prerequisites), see:

- [`apps/confluent-operator/README.md`](../apps/confluent-operator/README.md) -- CFK operator
- [`apps/confluent-flink-operator/README.md`](../apps/confluent-flink-operator/README.md) -- Flink operator

---

## Chart Versions

| Operator | Chart | Repository | Version |
|----------|-------|-----------|---------|
| Confluent (CFK) | `confluent-for-kubernetes` | `https://packages.confluent.io/helm` | `0.1351.59` |
| Flink | `flink-kubernetes-operator` | `https://packages.confluent.io/helm` | `1.130.2` |

---

## Confluent Operator (CFK) Default Values

### Common Settings (all environments)

| Key | Value | Description |
|-----|-------|-------------|
| `licenseSecretRef` | `confluent-license` | References a K8s Secret containing the Confluent license key. |
| `imagePullSecretRef` | `null` | No image pull secret. Set when using a private registry. |
| `image.registry` | `docker.io` | Container registry. Change for air-gapped deployments. |
| `image.repository` | `confluentinc/confluent-operator` | Operator image path. |
| `namespaced` | `true` | Restricts the operator to watch only `namespaceList`. |
| `kRaftEnabled` | `true` | KRaft consensus mode (no ZooKeeper dependency). |
| `enableCMFDay2Ops` | `true` | CMF Day-2 operations support for Flink lifecycle management. |
| `fipsmode` | `true` | FIPS 140-2 compliant cryptography. |
| `podSecurity.enabled` | `false` | Lets OpenShift SCC manage security contexts. |
| `serviceAccount.create` | `true` | Helm creates the ServiceAccount. |
| `serviceAccount.name` | `confluent` | SA name (must match SCC bindings). |
| `rbac` | `false` | RBAC provisioned out-of-band by cluster admin. |
| `clusterRole.openshift` | `true` | Expect OpenShift-specific permissions (SCC, Routes). |
| `webhooks.enabled` | `false` | Admission webhooks disabled; validation via CI/CD. |
| `pod.annotations` | Prometheus scrape | `prometheus.io/scrape: "true"`, `prometheus.io/port: "7778"` |
| `pod.labels` | `{}` | No additional labels. |
| `affinity` | `{}` | No scheduling constraints (customize per-cluster). |
| `tolerations` | `[]` | No tolerations (customize if using dedicated nodes). |

### Per-Environment Differences

| Key | dev | qa | stg | prd |
|-----|-----|----|-----|-----|
| `replicas` | 1 | 2 | 2 | 2 |
| `namespaceList` | `[confluent-dev]` | `[confluent-qa]` | `[confluent-stg]` | `[confluent-prd]` |
| `resources.requests.cpu` | 100m | 200m | 200m | 200m |
| `resources.requests.memory` | 256Mi | 256Mi | 512Mi | 512Mi |
| `resources.limits.cpu` | 500m | 500m | 1 | 1 |
| `resources.limits.memory` | 512Mi | 512Mi | 1Gi | 1Gi |

### Resource Sizing Rationale

- **dev**: Single replica, minimal resources. Cost-efficient for development.
- **qa**: 2 replicas for HA testing. Same limits as dev since QA workloads are lighter.
- **stg/prd**: 2 replicas with production-grade limits (1 CPU, 1Gi memory). Memory request set to 512Mi (50% of limit) to avoid OOM under sustained reconciliation load.

---

## Flink Kubernetes Operator Default Values

### Common Settings (all environments)

| Key | Value | Description |
|-----|-------|-------------|
| `imagePullSecretRef` | `null` | No image pull secret. Set when using a private registry. |
| `image.registry` | `docker.io` | Container registry. Change for air-gapped deployments. |
| `image.repository` | `confluentinc/confluent-operator-flink` | Flink operator image path. |
| `podSecurityContext.enabled` | `false` | Lets OpenShift SCC manage security contexts. |
| `serviceAccount.create` | `true` | Helm creates the ServiceAccount. |
| `serviceAccount.name` | `flink-kubernetes-operator` | SA name (must match SCC bindings). |
| `metrics.prometheus.enabled` | `true` | Exposes Prometheus metrics endpoint on the operator. |
| `logging.level` | `INFO` | Operator log verbosity. Set to `DEBUG` for troubleshooting. |
| `webhook.create` | `true` | Creates ValidatingWebhookConfiguration for Flink CRDs. TLS handled by cert-manager. |
| `podAnnotations` | Prometheus scrape | `prometheus.io/scrape: "true"`, `prometheus.io/port: "9999"` |
| `podLabels` | `{}` | No additional labels. |
| `affinity` | `{}` | No scheduling constraints (customize per-cluster). |
| `tolerations` | `[]` | No tolerations (customize if using dedicated nodes). |

### Default Flink Configuration

The `defaultConfiguration` block injects base `flink-conf.yaml` settings into all Flink workloads managed by the operator. Individual `FlinkDeployment` or `FlinkSessionJob` CRs can override these.

```yaml
defaultConfiguration:
  flink-conf.yaml: |
    kubernetes.operator.metrics.reporter.prom.factory.class: org.apache.flink.metrics.prometheus.PrometheusReporterFactory
    kubernetes.operator.metrics.reporter.prom.port: "9999"
```

This enables Prometheus metrics collection for Flink jobs by default, matching the operator-level metrics configuration.

### Per-Environment Differences

| Key | dev | qa | stg | prd |
|-----|-----|----|-----|-----|
| `replicas` | 1 | 2 | 2 | 2 |
| `watchNamespaces` | `[confluent-dev]` | `[confluent-qa]` | `[confluent-stg]` | `[confluent-prd]` |
| `resources.requests.cpu` | 100m | 200m | 200m | 200m |
| `resources.requests.memory` | 256Mi | 256Mi | 512Mi | 512Mi |
| `resources.limits.cpu` | 500m | 500m | 1 | 1 |
| `resources.limits.memory` | 512Mi | 512Mi | 1Gi | 1Gi |

### Resource Sizing Rationale

- **dev**: Single replica, lightweight. Sufficient for development-time Flink job submission.
- **qa**: 2 replicas for HA. Same limits as dev.
- **stg/prd**: 2 replicas with production-grade limits (1 CPU, 1Gi memory). Memory request bumped to 512Mi to accommodate larger Flink cluster reconciliation (more pods, more state).

---

## OpenShift Overlays

Both operators include an `openshift-overlay.yaml` that nulls out pod security context fields, allowing OpenShift's SCC admission controller to inject the correct UID/GID values.

### CFK Operator (`apps/confluent-operator/openshift-overlay.yaml`)

```yaml
podSecurity:
  securityContext:
    fsGroup: null
    runAsUser: null
```

### Flink Operator (`apps/confluent-flink-operator/openshift-overlay.yaml`)

```yaml
podSecurityContext:
  runAsUser: null
  runAsGroup: null
  fsGroup: null
```

These overlays are applied as the **second** values file in the ApplicationSet Helm configuration (last file wins).

> **Note:** With `podSecurity.enabled: false` (CFK) and `podSecurityContext.enabled: false` (Flink) set in the base values, the overlays are redundant but retained as a safety net.

---

## Comparison: CFK vs Flink Operator

| Aspect | CFK Operator | Flink Operator |
|--------|-------------|----------------|
| **Pod security** | `podSecurity.enabled: false` | `podSecurityContext.enabled: false` |
| **Webhooks** | Disabled (validation via CI/CD) | Enabled (cert-manager provides TLS) |
| **RBAC** | Disabled (provisioned externally) | Chart default (Helm-managed) |
| **FIPS mode** | Enabled | N/A (not a chart option) |
| **Metrics port** | 7778 | 9999 |
| **Dependencies** | None (first operator deployed) | cert-manager (for webhook certs) |
| **SA name** | `confluent` | `flink-kubernetes-operator` |

---

## Customization Guide

### Air-Gapped / Private Registry

Update `image.registry` in all values files:

```yaml
# CFK
image:
  registry: registry.example.com
  repository: confluentinc/confluent-operator
imagePullSecretRef: registry-credentials

# Flink
image:
  registry: registry.example.com
  repository: confluentinc/confluent-operator-flink
imagePullSecretRef: registry-credentials
```

### Node Affinity / Dedicated Nodes

Add to stg/prd values to spread operator replicas:

```yaml
affinity:
  podAntiAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        podAffinityTerm:
          labelSelector:
            matchExpressions:
              - key: app.kubernetes.io/name
                operator: In
                values:
                  - confluent-operator  # or flink-kubernetes-operator
          topologyKey: kubernetes.io/hostname
```

### Dedicated Tainted Nodes

```yaml
tolerations:
  - key: "confluent.io/dedicated"
    operator: "Equal"
    value: "operators"
    effect: "NoSchedule"
```
