# Flink Kubernetes Operator

The **Confluent Flink Kubernetes Operator** manages the lifecycle of Apache Flink workloads on Kubernetes. It watches for Flink custom resources and handles deployment, scaling, and upgrades of Flink applications.

## Helm Chart

| Field | Value |
|-------|-------|
| **Chart** | `flink-kubernetes-operator` |
| **Repository** | `https://packages.confluent.io/helm` |
| **Version** | `1.*` |

## Directory Structure

```
confluent-flink-operator/
|-- dev/
|   |-- app.yaml       # ArgoCD Application resource
|   +-- values.yaml    # Helm values (reference copy)
|-- qa/
|-- stg/
+-- prd/
```

## Configuration

The `app.yaml` uses inline `valuesObject` for Helm values. The `values.yaml` is a reference copy.

| Setting | Value | Purpose |
|---------|-------|---------|
| `watchNamespaces` | `["confluent-<env>"]` | Scoped to the environment namespace |
| `metrics.prometheus.enabled` | `true` | Exposes Prometheus metrics endpoint |
| `resources.requests.cpu` | `100m` | CPU request |
| `resources.requests.memory` | `256Mi` | Memory request |
| `resources.limits.cpu` | `500m` | CPU limit |
| `resources.limits.memory` | `512Mi` | Memory limit |

### Key design choices

- **Scoped watch namespaces** (`watchNamespaces`): The operator only watches its specific environment namespace, providing isolation between environments.
- **Prometheus metrics** (`metrics.prometheus.enabled: true`): Enables monitoring of the operator via Prometheus. Useful for tracking operator health and Flink job metrics.

## Prerequisites

**cert-manager must be deployed and healthy before installing this operator.** The Flink operator uses cert-manager to provision TLS certificates for its admission webhook endpoints. Without cert-manager, the installation will fail with:

```
no matches for kind "Certificate" in version "cert-manager.io/v1"
```

## Target Namespace

Deployed to `confluent-<env>` (same namespace as the Confluent Operator). Created automatically via `CreateNamespace=true` sync option.

## Sync Policy

| Environment | Policy |
|-------------|--------|
| dev | Automated (prune + selfHeal) |
| qa / stg / prd | Manual |

## Dependencies

- **Required by:** Confluent Flink Manager CRDs
- **Depends on:** cert-manager (for webhook TLS certificates), ArgoCD

## Deployment

```bash
# Ensure cert-manager is healthy first
kubectl wait --for=jsonpath='{.status.health.status}'=Healthy \
  application/cert-manager-dev -n argocd --timeout=180s

# Deploy the Flink operator
kubectl apply -f apps/confluent-flink-operator/dev/app.yaml

# Wait for healthy
kubectl wait --for=jsonpath='{.status.health.status}'=Healthy \
  application/confluent-flink-operator-dev -n argocd --timeout=180s
```

## Verification

```bash
kubectl get pods -n confluent-dev
```

Expected: `flink-kubernetes-operator-...` pod with 2/2 containers running (operator + webhook).
