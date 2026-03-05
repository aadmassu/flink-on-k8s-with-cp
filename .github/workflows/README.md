# GitHub Actions Workflows

This directory contains two GitHub Actions workflows for deploying Confluent and Flink operators on **OpenShift** via the OpenShift GitOps Operator (ArgoCD).

## Workflows

| Workflow | File | Use When |
|---|---|---|
| **Full Deploy** | `full-deploy.yaml` | Deploying to a cluster that does **not** have ArgoCD installed |
| **Deploy Operators** | `deploy-operators.yaml` | ArgoCD (OpenShift GitOps) is **already** running on the cluster |

## Full Deploy (`full-deploy.yaml`)

Performs an end-to-end deployment:

1. Installs ArgoCD via Helm into the `openshift-gitops` namespace
2. Deploys cert-manager (via ArgoCD ApplicationSet)
3. Deploys Confluent Operator and Flink Operator (via ArgoCD ApplicationSets)

### Inputs

| Input | Required | Default | Description |
|---|---|---|---|
| `environment` | Yes | `dev` | Target environment (`dev`, `qa`, `stg`, `prd`) |
| `cluster_context` | Yes | -- | Kubeconfig context name for the target OpenShift cluster |

## Deploy Operators (`deploy-operators.yaml`)

Deploys operators into an existing ArgoCD instance:

1. Verifies ArgoCD is running
2. Deploys cert-manager, Confluent Operator, and Flink Operator via ApplicationSets

### Inputs

| Input | Required | Default | Description |
|---|---|---|---|
| `environment` | Yes | `dev` | Target environment (`dev`, `qa`, `stg`, `prd`) |
| `cluster_context` | Yes | -- | Kubeconfig context name for the target OpenShift cluster |
| `argocd_namespace` | Yes | `openshift-gitops` | Namespace where ArgoCD is installed |

## Prerequisites

- OpenShift cluster with `oc` CLI access configured
- OpenShift GitOps Operator installed (or standalone ArgoCD)
- Helm repositories accessible (`argoproj.github.io`, `packages.confluent.io`, `charts.jetstack.io`)
- ApplicationSet files in `gitops-config/openshift/<env>/` with correct cluster URLs
- OpenShift prerequisites (SCCs + bindings) applied via `openshift-prereqs/`

## Cross-References

| Resource | Path |
|---|---|
| Azure DevOps pipelines | [`.azure-pipelines/`](../../.azure-pipelines/) |
| ApplicationSet definitions | [`gitops-config/openshift/`](../../gitops-config/openshift/) |
| OpenShift prerequisites | [`openshift-prereqs/`](../../openshift-prereqs/) |
| Helm values and overlays | [`apps/`](../../apps/) |
