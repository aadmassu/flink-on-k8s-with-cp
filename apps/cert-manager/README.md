# cert-manager

X.509 certificate management for Kubernetes. Required as a **prerequisite** for the Flink Kubernetes Operator, which uses cert-manager to provision TLS certificates for its webhook endpoints.

## Helm Chart

| Field | Value |
|-------|-------|
| **Chart** | `cert-manager` |
| **Repository** | `https://charts.jetstack.io` |
| **Version** | `1.*` |

## Directory Structure

```
cert-manager/
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
| `crds.enabled` | `true` | Install cert-manager CRDs (Certificate, Issuer, etc.) |
| `resources.requests.cpu` | `50m` | Minimal CPU request |
| `resources.requests.memory` | `128Mi` | Minimal memory request |
| `resources.limits.cpu` | `250m` | CPU limit |
| `resources.limits.memory` | `256Mi` | Memory limit |

## Target Namespace

Deployed to the `cert-manager` namespace (created automatically via `CreateNamespace=true` sync option).

## Sync Policy

| Environment | Policy |
|-------------|--------|
| dev | Automated (prune + selfHeal) |
| qa / stg / prd | Manual |

## Dependencies

- **Required by:** Flink Operator (for webhook TLS certificates)
- **Depends on:** ArgoCD (must be running to process the Application resource)

## Deployment

```bash
kubectl apply -f gitops-config/aws-us-east-2/dev/cert-manager-application-set.yaml

# Wait for healthy
kubectl wait --for=jsonpath='{.status.health.status}'=Healthy \
  application/cert-manager-dev -n argocd --timeout=180s
```

## Verification

```bash
kubectl get pods -n cert-manager
```

Expected: 3 pods (cert-manager, cainjector, webhook).
