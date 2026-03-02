# ArgoCD

ArgoCD self-provisioning configuration. This is the only component installed directly via `helm install` - it then manages all other applications in this repository.

## Helm Chart

| Field | Value |
|-------|-------|
| **Chart** | `argo-cd` |
| **Repository** | `https://argoproj.github.io/argo-helm` |
| **Version** | `7.*` |

## Directory Structure

```
argocd/
|-- dev/
|   |-- app.yaml       # ArgoCD Application resource
|   +-- values.yaml    # Helm values
|-- qa/
|-- stg/
+-- prd/
```

## Configuration per Environment

| Setting | Dev | QA / STG / PRD |
|---------|-----|----------------|
| Server replicas | 1 | Varies |
| Controller replicas | 1 | Varies |
| Repo server replicas | 1 | Varies |
| Service type | LoadBalancer | Varies |
| `server.insecure` | `true` | Varies |
| RBAC default | `role:readonly` | `role:readonly` |

## Key Values

- `configs.params.server.insecure: true` - Allows HTTP access (TLS terminated at load balancer/route)
- `configs.secret.argocdServerAdminPassword` - Bcrypt-hashed admin password
- `configs.rbac.policy.default: role:readonly` - Default RBAC policy for unauthenticated users

## Installation

ArgoCD is installed directly via Helm (not through ArgoCD itself):

```bash
helm install argocd argo-cd/argo-cd \
  --namespace argocd \
  --create-namespace \
  -f apps/argocd/dev/values.yaml \
  --wait --timeout 5m
```

The `app.yaml` in each environment is used for ArgoCD self-management after the initial bootstrap.
