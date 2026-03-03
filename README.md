# Multi-Environment Confluent Platform & Flink on Kubernetes

GitOps repository for deploying **Confluent Platform**, **Apache Flink** (via Confluent), and supporting infrastructure across multiple environments using **ArgoCD**.

> **Current scope:** This guide covers the installation of **cert-manager**, **Confluent Operator (CFK)**, and **Flink Operator**. Confluent Platform CRDs and Confluent Flink Manager deployment guides will be added in a future update.

---

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Environments](#environments)
- [Prerequisites](#prerequisites)
- [Assumptions](#assumptions)
- [Repository Structure](#repository-structure)
- [Deployment Guide](#deployment-guide)
  - [Step 1 - Add Helm Repositories](#step-1---add-helm-repositories)
  - [Step 2 - Install ArgoCD](#step-2---install-argocd)
  - [Step 3 - Access ArgoCD UI](#step-3---access-argocd-ui)
  - [Step 4 - Deploy cert-manager](#step-4---deploy-cert-manager)
  - [Step 5 - Deploy Confluent Operator](#step-5---deploy-confluent-operator)
  - [Step 6 - Deploy Flink Operator](#step-6---deploy-flink-operator)
- [CI/CD Pipelines](#cicd-pipelines)
- [Full Deploy Script (Dev)](#full-deploy-script-dev)
- [Tear Down](#tear-down)
- [Sync Policies](#sync-policies)
- [Namespace Convention](#namespace-convention)
- [Helm Charts Reference](#helm-charts-reference)
- [Troubleshooting](#troubleshooting)
- [Additional Guides](#additional-guides)

---

## Overview

This repository contains the complete GitOps configuration for:

| Component | Description | Status |
|-----------|-------------|--------|
| **ArgoCD** | GitOps continuous delivery tool - manages all other deployments | Available |
| **cert-manager** | X.509 certificate management - required by Flink operator webhooks | Available |
| **Confluent Operator (CFK)** | Confluent for Kubernetes operator - manages Confluent Platform CRDs | Available |
| **Flink Operator** | Confluent's Flink Kubernetes operator - manages Flink workloads | Available |
| **Confluent Platform** | Kafka, KRaft, Schema Registry, Connect, ksqlDB, Control Center | Coming soon |
| **Confluent Flink Manager (CMF)** | Manages Flink SQL workloads on Kubernetes | Coming soon |

All components except ArgoCD itself are deployed **through ArgoCD** via ApplicationSet resources in `gitops-config/`, achieving full GitOps management.

---

## Architecture

```
+------------------+
|     ArgoCD       |  <-- Installed via Helm (bootstrap)
|  (argocd ns)     |
+--------+---------+
         |
         | manages (Application CRs)
         |
    +----+----+--------------------+
    |         |                    |
    v         v                    v
cert-manager  confluent-operator   confluent-flink-operator
(cert-manager (confluent-<env>     (confluent-<env> ns)
 ns)           ns)
```

ArgoCD is the only component installed directly via `helm install`. Everything else is declared as an ArgoCD `ApplicationSet` resource in `gitops-config/` and applied with `kubectl apply`. ArgoCD then generates the corresponding Application resources and handles deployment, monitoring, and reconciliation.

---

## Environments

| Environment | Sync Policy | Use Case |
|-------------|-------------|----------|
| **dev** | Automated (prune + selfHeal) | Development and testing |
| **qa** | Manual | Quality assurance |
| **stg** | Manual | Pre-production staging |
| **prd** | Manual | Production |

Each environment has its own Kubernetes namespace and resource sizing. The cluster inventory is defined in `hosts.yaml`. Update `hosts.yaml` with the actual cluster API endpoints for your infrastructure.

---

## Prerequisites

| Tool | Version | Purpose |
|------|---------|---------|
| `kubectl` | 1.28+ | Kubernetes CLI |
| `helm` | 3.14+ / 4.x | Helm package manager |
| Kubernetes cluster | 1.28+ | Target cluster with admin access |

### Kubeconfig

Ensure your kubeconfig is pointing to the target cluster:

```bash
# Verify context
kubectl config get-contexts

# Verify connectivity
kubectl cluster-info
```

---

## Assumptions

- A Kubernetes cluster (1.28+) is provisioned and accessible via `kubectl`.
- The deploying user or service account has **cluster-admin** privileges (required to create namespaces, CRDs, and ClusterRoles).
- Helm repositories are accessible from the cluster or CI/CD runner (no network restrictions on `argoproj.github.io`, `charts.jetstack.io`, `packages.confluent.io`).
- The ApplicationSet files in `gitops-config/` contain **placeholder cluster URLs**. Update the `url` field in each ApplicationSet's generator list with your actual cluster API server endpoints before deploying (dev is pre-configured to `https://kubernetes.default.svc`).
- For CI/CD pipelines, a Kubernetes service connection or kubeconfig secret is configured in your pipeline platform.

---

## Repository Structure

```
.
|
|-- README.md                          # This file
|-- README-EXISTING-ARGOCD.md          # Guide: deploy into an existing ArgoCD
|-- README-OPENSHIFT.md                # Guide: deploy on OpenShift
|-- hosts.yaml                         # Cluster inventory
|-- secrets.yaml                       # Secret reference template
|
|-- .github/workflows/                 # GitHub Actions pipelines
|   |-- full-deploy.yaml               # Scenario 1: ArgoCD + operators
|   +-- deploy-operators.yaml          # Scenario 2: operators only (existing ArgoCD)
|
|-- .azure-pipelines/                  # Azure DevOps pipelines
|   |-- full-deploy.yaml               # Scenario 1: ArgoCD + operators
|   +-- deploy-operators.yaml          # Scenario 2: operators only (existing ArgoCD)
|
|-- apps/                              # Application definitions
|   |-- argocd/                        # ArgoCD self-provisioning (Helm)
|   |-- cert-manager/                  # cert-manager (Helm) - Flink prerequisite
|   |-- confluent-operator/            # Confluent for Kubernetes operator (Helm)
|   |-- confluent-flink-operator/      # Flink Kubernetes operator (Helm)
|   |-- confluent-platform/            # Confluent Platform CRD manifests (coming soon)
|   +-- confluent-flink/               # Confluent Flink Manager CRD manifests (coming soon)
|
+-- gitops-config/                     # ArgoCD ApplicationSet definitions
    +-- <region>/
        |-- dev/  qa/  stg/  prd/      # Per-environment ApplicationSets
```

Each app folder contains a `README.md` with detailed documentation. See the [apps/](apps/) directory.

### Key directories

| Directory | Purpose |
|-----------|---------|
| `gitops-config/<region>/<env>/` | ArgoCD ApplicationSet resources — the entry point for deploying all components |
| `apps/<app>/<env>/values.yaml` | Helm values file referenced by ApplicationSets via `$values/` |

---

## Deployment Guide

The deployment follows a strict ordering due to dependencies:

```
ArgoCD  -->  cert-manager  -->  confluent-operator
                            -->  confluent-flink-operator
```

- **ArgoCD** is installed first via Helm (the only direct Helm install).
- **cert-manager** must be healthy before the Flink operator (it provides TLS certificates for webhooks).
- **confluent-operator** and **confluent-flink-operator** can be deployed in parallel after cert-manager.

All steps below use **dev** as the target environment. Replace `dev` with `qa`, `stg`, or `prd` for other environments.

> **Already have ArgoCD running?** Skip to [README-EXISTING-ARGOCD.md](README-EXISTING-ARGOCD.md) for a streamlined guide.
>
> **Deploying on OpenShift?** See [README-OPENSHIFT.md](README-OPENSHIFT.md) for OpenShift-specific instructions.
>
> **Prefer CI/CD?** See the [CI/CD Pipelines](#cicd-pipelines) section for GitHub Actions and Azure DevOps options.

---

### Step 1 - Add Helm Repositories

Only needed once per machine:

```bash
helm repo add argo-cd https://argoproj.github.io/argo-helm
helm repo add confluent https://packages.confluent.io/helm
helm repo add jetstack https://charts.jetstack.io
helm repo update
```

---

### Step 2 - Install ArgoCD

ArgoCD is the only component installed directly via Helm. All other apps are deployed through ArgoCD.

```bash
helm install argocd argo-cd/argo-cd \
  --namespace argocd \
  --create-namespace \
  -f apps/argocd/dev/values.yaml \
  --wait --timeout 5m
```

Verify:

```bash
kubectl get pods -n argocd
```

Expected output (all Running):

```
argocd-application-controller-0                    1/1     Running
argocd-applicationset-controller-...               1/1     Running
argocd-dex-server-...                              1/1     Running
argocd-notifications-controller-...                1/1     Running
argocd-redis-...                                   1/1     Running
argocd-repo-server-...                             1/1     Running
argocd-server-...                                  1/1     Running
```

---

### Step 3 - Access ArgoCD UI

Retrieve the ArgoCD server URL based on your platform's ingress method (LoadBalancer, NodePort, Ingress, or OpenShift Route).

```bash
# Check the service type
kubectl get svc argocd-server -n argocd
```

| Field | Value |
|-------|-------|
| **URL** | Depends on your service exposure method (LoadBalancer IP, Ingress hostname, or Route) |
| **Username** | `admin` |
| **Password** | Pre-configured in `values.yaml`, or retrieve auto-generated password (see below) |

Retrieve the auto-generated admin password:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

---

### Step 4 - Deploy cert-manager

cert-manager is required **before** the Flink operator. It provides TLS certificates for Flink operator webhook endpoints.

```bash
kubectl apply -f gitops-config/aws-us-east-2/dev/cert-manager-application-set.yaml
```

Wait for it to become healthy:

```bash
kubectl wait --for=jsonpath='{.status.health.status}'=Healthy \
  application/cert-manager-dev -n argocd --timeout=180s
```

Verify:

```bash
kubectl get pods -n cert-manager
```

Expected: 3 pods running (cert-manager, cainjector, webhook).

---

### Step 5 - Deploy Confluent Operator

```bash
kubectl apply -f gitops-config/aws-us-east-2/dev/confluent-operator-application-set.yaml
```

Wait for healthy:

```bash
kubectl wait --for=jsonpath='{.status.health.status}'=Healthy \
  application/confluent-operator-dev -n argocd --timeout=180s
```

Verify:

```bash
kubectl get pods -n confluent-dev -l app=confluent-operator
```

---

### Step 6 - Deploy Flink Operator

```bash
kubectl apply -f gitops-config/aws-us-east-2/dev/confluent-flink-operator-application-set.yaml
```

Wait for healthy:

```bash
kubectl wait --for=jsonpath='{.status.health.status}'=Healthy \
  application/confluent-flink-operator-dev -n argocd --timeout=180s
```

Verify both operators:

```bash
kubectl get pods -n confluent-dev
```

Expected:

```
confluent-operator-...                 1/1     Running
flink-kubernetes-operator-...          2/2     Running
```

---

## CI/CD Pipelines

This repository includes ready-to-use pipeline definitions for both **GitHub Actions** and **Azure DevOps**. Each platform provides two workflow scenarios.

### Scenarios

| Scenario | Description | When to use |
|----------|-------------|-------------|
| **Full Deploy** | Installs ArgoCD via Helm, then deploys all 3 operators | Fresh cluster with no ArgoCD |
| **Deploy Operators** | Deploys operators into an existing ArgoCD instance | ArgoCD already running on the cluster |

### GitHub Actions

| Workflow | File | Trigger |
|----------|------|---------|
| Full Deploy (ArgoCD + Operators) | [`.github/workflows/full-deploy.yaml`](.github/workflows/full-deploy.yaml) | `workflow_dispatch` (manual) |
| Deploy Operators (Existing ArgoCD) | [`.github/workflows/deploy-operators.yaml`](.github/workflows/deploy-operators.yaml) | `workflow_dispatch` (manual) |

**Usage:** Go to the **Actions** tab in GitHub, select the workflow, choose the target environment and cluster context, then click **Run workflow**.

### Azure DevOps

| Pipeline | File | Trigger |
|----------|------|---------|
| Full Deploy (ArgoCD + Operators) | [`.azure-pipelines/full-deploy.yaml`](.azure-pipelines/full-deploy.yaml) | Manual |
| Deploy Operators (Existing ArgoCD) | [`.azure-pipelines/deploy-operators.yaml`](.azure-pipelines/deploy-operators.yaml) | Manual |

**Usage:** Import the pipeline YAML files in Azure DevOps under **Pipelines > New Pipeline > Existing Azure Pipelines YAML file**. Configure the Kubernetes service connection parameter to point to your cluster.

### Pipeline parameters

Both platforms accept these inputs:

| Parameter | Description | Default |
|-----------|-------------|---------|
| `environment` | Target environment (`dev`, `qa`, `stg`, `prd`) | `dev` |
| `cluster_context` / `kubernetesServiceConnection` | Cluster access identifier | Required |
| `argocd_namespace` | ArgoCD namespace (Scenario 2 only) | `argocd` |

> **Note:** The pipelines include a placeholder step for cluster authentication. Update this step with your specific authentication method (cloud CLI, kubeconfig secret, service connection, etc.).

---

## Full Deploy Script (Dev)

Copy-paste this block to deploy the operators from scratch on a clean cluster:

```bash
# Add Helm repos (idempotent)
helm repo add argo-cd https://argoproj.github.io/argo-helm 2>/dev/null || true
helm repo add confluent https://packages.confluent.io/helm 2>/dev/null || true
helm repo add jetstack https://charts.jetstack.io 2>/dev/null || true
helm repo update

# 1. Install ArgoCD
helm install argocd argo-cd/argo-cd \
  --namespace argocd --create-namespace \
  -f apps/argocd/dev/values.yaml \
  --wait --timeout 5m

# 2. Deploy cert-manager (required before Flink operator)
kubectl apply -f gitops-config/aws-us-east-2/dev/cert-manager-application-set.yaml
kubectl wait --for=jsonpath='{.status.health.status}'=Healthy \
  application/cert-manager-dev -n argocd --timeout=180s

# 3. Deploy both operators
kubectl apply -f gitops-config/aws-us-east-2/dev/confluent-operator-application-set.yaml
kubectl apply -f gitops-config/aws-us-east-2/dev/confluent-flink-operator-application-set.yaml
kubectl wait --for=jsonpath='{.status.health.status}'=Healthy \
  application/confluent-operator-dev \
  application/confluent-flink-operator-dev \
  -n argocd --timeout=180s

# 4. Verify
echo ""
echo "=== All Applications ==="
kubectl get applications -n argocd
echo ""
echo "=== Operator Pods ==="
kubectl get pods -n confluent-dev
kubectl get pods -n cert-manager
```

---

## Tear Down

To completely remove everything and start fresh:

```bash
# Delete all ArgoCD-managed applications first
kubectl delete applications --all -n argocd

# Uninstall ArgoCD
helm uninstall argocd --namespace argocd

# Delete all namespaces
kubectl delete ns argocd confluent-dev cert-manager --wait --timeout=120s
```

After tear down, re-run the [Full Deploy Script](#full-deploy-script-dev) to rebuild.

---

## Sync Policies

| Environment | Sync Policy | Behavior |
|-------------|-------------|----------|
| **dev** | `automated` | ArgoCD automatically syncs changes, prunes removed resources, and self-heals drift |
| **qa** | `manual` | Changes must be synced manually through the ArgoCD UI or CLI |
| **stg** | `manual` | Same as QA |
| **prd** | `manual` | Same as QA |

All environments use these ArgoCD sync options:

| Option | Applied To | Purpose |
|--------|-----------|---------|
| `CreateNamespace=true` | All apps | Auto-create target namespace |
| `ServerSideApply=true` | Helm-based apps | Handle large CRDs without client-side limits |

---

## Namespace Convention

| Component | Namespace |
|-----------|-----------|
| ArgoCD | `argocd` |
| cert-manager | `cert-manager` |
| Confluent Operator | `confluent-<env>` (e.g., `confluent-dev`, `confluent-prd`) |
| Flink Operator | `confluent-<env>` (same namespace as Confluent Operator) |

---

## Helm Charts Reference

| Chart | Repository | Used For |
|-------|-----------|----------|
| `argo-cd` | `https://argoproj.github.io/argo-helm` | ArgoCD installation |
| `cert-manager` | `https://charts.jetstack.io` | TLS certificate management |
| `confluent-for-kubernetes` | `https://packages.confluent.io/helm` | Confluent Platform operator |
| `flink-kubernetes-operator` | `https://packages.confluent.io/helm` | Flink Kubernetes operator |

---

## Troubleshooting

### Flink operator fails to install without cert-manager

```
no matches for kind "Certificate" in version "cert-manager.io/v1"
```

cert-manager must be deployed and healthy **before** the Flink operator. Follow the deployment order in this guide.

### ArgoCD Application shows OutOfSync

For Helm-based apps (especially the Flink operator), a minor OutOfSync status on first deploy is expected. The Helm chart may generate annotations or labels that differ slightly from what ArgoCD tracks. The app will show `Healthy` and function correctly. A full tear-down and redeploy resolves this.

### Checking ArgoCD Application status from CLI

```bash
# List all applications
kubectl get applications -n argocd

# Describe a specific application
kubectl describe application confluent-operator-dev -n argocd

# Get sync status details
kubectl get application confluent-operator-dev -n argocd -o jsonpath='{.status.sync.status}'
```

### Viewing ArgoCD admin password

For environments without a pre-configured password, retrieve the auto-generated one:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

---

## Additional Guides

| Guide | Description |
|-------|-------------|
| [README-EXISTING-ARGOCD.md](README-EXISTING-ARGOCD.md) | Deploy operator apps into an existing ArgoCD instance |
| [README-OPENSHIFT.md](README-OPENSHIFT.md) | Deploy on OpenShift with ArgoCD (OpenShift GitOps or standalone) |
