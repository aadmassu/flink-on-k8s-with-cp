# Azure DevOps Pipelines

This directory contains two Azure DevOps pipelines for deploying Confluent and Flink operators on **OpenShift** via the OpenShift GitOps Operator (ArgoCD).

## Pipelines

| Pipeline | File | Use When |
|---|---|---|
| **Full Deploy** | `full-deploy.yaml` | Deploying to a cluster that does **not** have ArgoCD installed |
| **Deploy Operators** | `deploy-operators.yaml` | ArgoCD (OpenShift GitOps) is **already** running on the cluster |

## Full Deploy (`full-deploy.yaml`)

Performs an end-to-end deployment:

1. Installs ArgoCD via Helm into the `openshift-gitops` namespace
2. Deploys cert-manager (via ArgoCD ApplicationSet)
3. Deploys Confluent Operator and Flink Operator (via ArgoCD ApplicationSets)

### Parameters

| Parameter | Default | Description |
|---|---|---|
| `environment` | `dev` | Target environment (`dev`, `qa`, `stg`, `prd`) |
| `kubernetesServiceConnection` | `<your-service-connection>` | Azure DevOps Kubernetes service connection name |
| `argocdNamespace` | `openshift-gitops` | Namespace for ArgoCD installation |

## Deploy Operators (`deploy-operators.yaml`)

Deploys operators into an existing ArgoCD instance:

1. Verifies ArgoCD is running
2. Deploys cert-manager, Confluent Operator, and Flink Operator via ApplicationSets

### Parameters

| Parameter | Default | Description |
|---|---|---|
| `environment` | `dev` | Target environment (`dev`, `qa`, `stg`, `prd`) |
| `kubernetesServiceConnection` | `<your-service-connection>` | Azure DevOps Kubernetes service connection name |
| `argocdNamespace` | `openshift-gitops` | Namespace where ArgoCD is installed |

## Prerequisites

- Azure DevOps Kubernetes service connection configured for the target OpenShift cluster
- OpenShift GitOps Operator installed (or standalone ArgoCD)
- Helm repositories accessible (`argoproj.github.io`, `packages.confluent.io`, `charts.jetstack.io`)
- ApplicationSet files in `gitops-config/openshift/<env>/` with correct cluster URLs
- OpenShift prerequisites (SCCs + bindings) applied via `openshift-prereqs/`

## Cross-References

| Resource | Path |
|---|---|
| GitHub Actions workflows | [`.github/workflows/`](../.github/workflows/) |
| ApplicationSet definitions | [`gitops-config/openshift/`](../gitops-config/openshift/) |
| OpenShift prerequisites | [`openshift-prereqs/`](../openshift-prereqs/) |
| Helm values and overlays | [`apps/`](../apps/) |
