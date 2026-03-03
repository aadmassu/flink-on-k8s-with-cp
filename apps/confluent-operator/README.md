# Confluent Operator (CFK)

The **Confluent for Kubernetes (CFK)** operator manages the lifecycle of Confluent Platform components on Kubernetes. It watches for Confluent Platform custom resources (KRaftController, Kafka, SchemaRegistry, Connect, ksqlDB, ControlCenter) and reconciles them to the desired state.

## Helm Chart

| Field | Value |
|-------|-------|
| **Chart** | `confluent-for-kubernetes` |
| **Repository** | `https://packages.confluent.io/helm` |
| **Version** | `0.*` |

## Directory Structure

```
confluent-operator/
|-- dev/
|   +-- values.yaml    # Helm values referenced by ApplicationSets via $values/
|-- qa/
|-- stg/
+-- prd/
```

## Configuration

Helm values are defined in `values.yaml` and referenced by the ApplicationSet in `gitops-config/` via the `$values/` multi-source pattern.

| Setting | Value | Purpose |
|---------|-------|---------|
| `namespaced` | `true` | Operator watches only its own namespace (not cluster-wide) |
| `kRaftEnabled` | `true` | Enables KRaft mode for Kafka (no ZooKeeper dependency) |
| `resources.requests.cpu` | `100m` | CPU request |
| `resources.requests.memory` | `256Mi` | Memory request |
| `resources.limits.cpu` | `500m` | CPU limit |
| `resources.limits.memory` | `512Mi` | Memory limit |

### Key design choices

- **Namespaced mode** (`namespaced: true`): The operator only manages Confluent resources in its deployed namespace (`confluent-<env>`). This provides environment isolation - each environment gets its own operator instance.
- **KRaft mode** (`kRaftEnabled: true`): Uses KRaft consensus protocol instead of ZooKeeper, reducing operational complexity.

## Target Namespace

Deployed to `confluent-<env>` (e.g., `confluent-dev`, `confluent-prd`). Created automatically via `CreateNamespace=true` sync option.

## Sync Policy

| Environment | Policy |
|-------------|--------|
| dev | Automated (prune + selfHeal) |
| qa / stg / prd | Manual |

## Dependencies

- **Required by:** Confluent Platform CRDs (KRaftController, Kafka, etc.)
- **Depends on:** ArgoCD (must be running to process the Application resource)

## Deployment

```bash
kubectl apply -f gitops-config/aws-us-east-2/dev/confluent-operator-application-set.yaml

# Wait for healthy
kubectl wait --for=jsonpath='{.status.health.status}'=Healthy \
  application/confluent-operator-dev -n argocd --timeout=180s
```

## Verification

```bash
kubectl get pods -n confluent-dev -l app=confluent-operator
```

Expected: 1 pod running.
