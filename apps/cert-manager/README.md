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
kubectl apply -f apps/cert-manager/dev/app.yaml

# Wait for healthy
kubectl wait --for=jsonpath='{.status.health.status}'=Healthy \
  application/cert-manager-dev -n argocd --timeout=180s
```

## Verification

```bash
kubectl get pods -n cert-manager
```

Expected: 3 pods (cert-manager, cainjector, webhook).
