# FCB - Multi-Environment Confluent Platform & Flink on Kubernetes

GitOps repository for deploying **Confluent Platform**, **Apache Flink** (via Confluent), and supporting infrastructure across multiple environments using **ArgoCD**.

---

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Environments](#environments)
- [Repository Structure](#repository-structure)
- [Prerequisites](#prerequisites)
- [Deployment Guide](#deployment-guide)
  - [Step 1 - Add Helm Repositories](#step-1---add-helm-repositories)
  - [Step 2 - Install ArgoCD](#step-2---install-argocd)
  - [Step 3 - Access ArgoCD UI](#step-3---access-argocd-ui)
  - [Step 4 - Deploy cert-manager](#step-4---deploy-cert-manager)
  - [Step 5 - Deploy Confluent Operator](#step-5---deploy-confluent-operator)
  - [Step 6 - Deploy Flink Operator](#step-6---deploy-flink-operator)
  - [Step 7 - Deploy Confluent Platform (CRDs)](#step-7---deploy-confluent-platform-crds)
  - [Step 8 - Deploy Confluent Flink Manager (CRDs)](#step-8---deploy-confluent-flink-manager-crds)
- [Full Deploy Script (Dev)](#full-deploy-script-dev)
- [Tear Down](#tear-down)
- [Sync Policies](#sync-policies)
- [Confluent Platform Component Sizing](#confluent-platform-component-sizing)
- [Confluent Platform Sync Wave Ordering](#confluent-platform-sync-wave-ordering)
- [Namespace Convention](#namespace-convention)
- [Helm Charts Reference](#helm-charts-reference)
- [Troubleshooting](#troubleshooting)

---

## Overview

This repository contains the complete GitOps configuration for:

| Component | Description |
|-----------|-------------|
| **ArgoCD** | GitOps continuous delivery tool - manages all other deployments |
| **cert-manager** | X.509 certificate management - required by Flink operator webhooks |
| **Confluent Operator (CFK)** | Confluent for Kubernetes operator - manages Confluent Platform CRDs |
| **Flink Operator** | Confluent's Flink Kubernetes operator - manages Flink workloads |
| **Confluent Platform** | Kafka, KRaft, Schema Registry, Connect, ksqlDB, Control Center |
| **Confluent Flink Manager (CMF)** | Manages Flink SQL workloads on Kubernetes |

All components except ArgoCD itself are deployed **through ArgoCD** as Application resources, achieving full GitOps management.

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
    +----+----+--------------------+------------------------+
    |         |                    |                        |
    v         v                    v                        v
cert-manager  confluent-operator   confluent-flink-operator confluent-platform
(cert-manager (confluent-<env>     (confluent-<env> ns)     (confluent-<env> ns)
 ns)           ns)                                          + confluent-flink
```

ArgoCD is the only component installed directly via `helm install`. Everything else is declared as an ArgoCD `Application` resource and applied with `kubectl apply`. ArgoCD then handles the actual deployment, monitoring, and reconciliation.

---

## Environments

| Environment | Cluster | Sync Policy | Use Case |
|-------------|---------|-------------|----------|
| **dev** | `cfk-eks` (us-east-2) | Automated (prune + selfHeal) | Development and testing |
| **qa** | qa-cluster | Manual | Quality assurance |
| **stg** | stg-cluster | Manual | Pre-production staging |
| **prd** | prd-cluster | Manual | Production |

Each environment has its own Kubernetes cluster, namespace, and resource sizing. The cluster inventory is defined in `hosts.yaml`.

---

## Repository Structure

```
FCB/
|
|-- README.md                          # This file
|-- .gitignore                         # Ignore secrets, IDE files, temp files
|-- .gitkeep
|-- hosts.yaml                         # Cluster inventory (4 clusters)
|-- secrets.yaml                       # Secret reference template
|
|-- apps/                              # Application definitions
|   |
|   |-- argocd/                        # ArgoCD self-provisioning (Helm)
|   |   |-- dev/
|   |   |   |-- app.yaml              #   ArgoCD Application resource
|   |   |   +-- values.yaml           #   Helm values (replicas, resources, LB, password)
|   |   |-- qa/  stg/  prd/           #   Same structure per environment
|   |
|   |-- cert-manager/                  # cert-manager (Helm) - Flink prerequisite
|   |   |-- dev/
|   |   |   |-- app.yaml              #   ArgoCD Application resource
|   |   |   +-- values.yaml           #   Helm values (CRDs enabled, resources)
|   |   |-- qa/  stg/  prd/
|   |
|   |-- confluent-operator/           # Confluent for Kubernetes operator (Helm)
|   |   |-- dev/
|   |   |   |-- app.yaml              #   ArgoCD Application (valuesObject inline)
|   |   |   +-- values.yaml           #   Reference values (namespaced, kRaft)
|   |   |-- qa/  stg/  prd/
|   |
|   |-- confluent-flink-operator/     # Flink Kubernetes operator (Helm)
|   |   |-- dev/
|   |   |   |-- app.yaml              #   ArgoCD Application (valuesObject inline)
|   |   |   +-- values.yaml           #   Reference values (watchNamespaces, metrics)
|   |   |-- qa/  stg/  prd/
|   |
|   |-- confluent-platform/           # Confluent Platform CRD manifests
|   |   |-- dev/
|   |   |   |-- app.yaml              #   ArgoCD Application (directory source)
|   |   |   +-- manifests/
|   |   |       |-- kraft-controller.yaml      # sync-wave: 0
|   |   |       |-- kafka.yaml                 # sync-wave: 1
|   |   |       |-- schema-registry.yaml       # sync-wave: 2
|   |   |       |-- connect.yaml               # sync-wave: 2
|   |   |       |-- ksqldb.yaml                # sync-wave: 3
|   |   |       +-- control-center.yaml        # sync-wave: 3
|   |   |-- qa/  stg/  prd/           #   Same structure, different sizing
|   |
|   |-- confluent-flink/              # Confluent Flink Manager CRD manifests
|   |   |-- dev/
|   |   |   |-- app.yaml
|   |   |   +-- manifests/
|   |   |       +-- confluent-flink-manager.yaml
|   |   |-- qa/  stg/  prd/
|   |
|   +-- gridgain/                     # Reserved for future use
|       +-- .gitkeep
|
+-- gitops-config/                     # ArgoCD ApplicationSet definitions
    +-- aws-us-east-2/
        |-- dev/
        |   |-- cert-manager-application-set.yaml
        |   |-- confluent-operator-application-set.yaml
        |   |-- confluent-flink-operator-application-set.yaml
        |   |-- confluent-platform-application-set.yaml
        |   +-- confluent-flink-application-set.yaml
        |-- qa/   (same 5 files, manual sync)
        |-- stg/  (same 5 files, manual sync)
        +-- prd/  (same 5 files, manual sync)
```

### Key directories

| Directory | Purpose |
|-----------|---------|
| `apps/<app>/<env>/app.yaml` | ArgoCD Application resource that tells ArgoCD *what* to deploy and *where* |
| `apps/<app>/<env>/values.yaml` | Helm values file (reference copy; dev app.yaml uses inline `valuesObject`) |
| `apps/<app>/<env>/manifests/` | Raw Kubernetes CRD manifests (for confluent-platform and confluent-flink) |
| `gitops-config/aws-us-east-2/<env>/` | ArgoCD ApplicationSet resources for multi-cluster orchestration |

---

## Prerequisites

Before deploying, ensure the following tools are installed and configured:

| Tool | Version | Purpose |
|------|---------|---------|
| `kubectl` | 1.28+ | Kubernetes CLI |
| `helm` | 3.14+ / 4.x | Helm package manager |
| `aws` CLI | 2.x | EKS authentication (must be on PATH) |

### AWS CLI PATH (Windows/Git Bash)

If `kubectl` fails with `executable aws not found`, add the AWS CLI to your PATH:

```bash
export PATH="$PATH:/c/Program Files/Amazon/AWSCLIV2"
```

### Kubeconfig

Ensure your kubeconfig is pointing to the target cluster:

```bash
# Verify context
kubectl config get-contexts

# Verify connectivity
kubectl cluster-info
```

---

## Deployment Guide

The deployment follows a strict ordering due to dependencies:

```
ArgoCD  -->  cert-manager  -->  confluent-operator     -->  confluent-platform
                            -->  confluent-flink-operator  -->  confluent-flink
```

- **ArgoCD** is installed first via Helm (the only direct Helm install).
- **cert-manager** must be healthy before the Flink operator (it provides TLS certificates for webhooks).
- **confluent-operator** and **confluent-flink-operator** can be deployed in parallel after cert-manager.
- **confluent-platform** and **confluent-flink** CRDs require their respective operators to be running.

All steps below use **dev** as the target environment. Replace `dev` with `qa`, `stg`, or `prd` for other environments.

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

The dev values file configures the ArgoCD server as a `LoadBalancer` service. Get the external URL:

```bash
kubectl get svc argocd-server -n argocd
```

| Field | Value |
|-------|-------|
| **URL** | `http://<EXTERNAL-IP>` (from the LoadBalancer output) |
| **Username** | `admin` |
| **Password** | `3qnIIsA5FZfG1Krq` (pre-configured in dev values.yaml) |

The ELB hostname changes on each fresh deploy. DNS propagation may take 1-2 minutes.

---

### Step 4 - Deploy cert-manager

cert-manager is required **before** the Flink operator. It provides TLS certificates for Flink operator webhook endpoints.

```bash
kubectl apply -f apps/cert-manager/dev/app.yaml
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
kubectl apply -f apps/confluent-operator/dev/app.yaml
```

Wait for healthy:

```bash
kubectl wait --for=jsonpath='{.status.health.status}'=Healthy \
  application/confluent-operator-dev -n argocd --timeout=180s
```

---

### Step 6 - Deploy Flink Operator

```bash
kubectl apply -f apps/confluent-flink-operator/dev/app.yaml
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

### Step 7 - Deploy Confluent Platform (CRDs)

> Requires the Confluent Operator to be running.

```bash
kubectl apply -f apps/confluent-platform/dev/app.yaml
```

ArgoCD will deploy the CRD manifests in sync-wave order:
1. KRaftController (wave 0)
2. Kafka (wave 1)
3. SchemaRegistry + Connect (wave 2)
4. ksqlDB + ControlCenter (wave 3)

---

### Step 8 - Deploy Confluent Flink Manager (CRDs)

> Requires the Flink Operator to be running.

```bash
kubectl apply -f apps/confluent-flink/dev/app.yaml
```

---

## Full Deploy Script (Dev)

Copy-paste this block to deploy everything from scratch on a clean cluster:

```bash
# Ensure AWS CLI is on PATH (Windows/Git Bash)
export PATH="$PATH:/c/Program Files/Amazon/AWSCLIV2"

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
kubectl apply -f apps/cert-manager/dev/app.yaml
kubectl wait --for=jsonpath='{.status.health.status}'=Healthy \
  application/cert-manager-dev -n argocd --timeout=180s

# 3. Deploy both operators
kubectl apply -f apps/confluent-operator/dev/app.yaml
kubectl apply -f apps/confluent-flink-operator/dev/app.yaml
kubectl wait --for=jsonpath='{.status.health.status}'=Healthy \
  application/confluent-operator-dev \
  application/confluent-flink-operator-dev \
  -n argocd --timeout=180s

# 4. Deploy Confluent Platform and Flink Manager CRDs
kubectl apply -f apps/confluent-platform/dev/app.yaml
kubectl apply -f apps/confluent-flink/dev/app.yaml

# 5. Print ArgoCD URL
echo ""
echo "=== ArgoCD ==="
echo "URL:      http://$(kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"
echo "Username: admin"
echo "Password: 3qnIIsA5FZfG1Krq"
echo ""

# 6. Show all ArgoCD applications
kubectl get applications -n argocd
```

---

## Tear Down

To completely remove everything and start fresh:

```bash
export PATH="$PATH:/c/Program Files/Amazon/AWSCLIV2"

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
| `SkipDryRunOnMissingResource=true` | CRD manifest apps | Allow applying CRs before CRDs are fully registered |

---

## Confluent Platform Component Sizing

| Component | Dev | QA | STG | PRD |
|-----------|-----|----|-----|-----|
| KRaftController | 1 replica | 3 | 3 | 3 |
| Kafka | 1 replica | 3 | 3 | 3 |
| SchemaRegistry | 1 replica | 2 | 3 | 3 |
| Connect | 1 replica | 1 | 2 | 2 |
| ControlCenter | 1 replica | 1 | 1 | 1 |
| ksqlDB | 1 replica | 1 | 2 | 2 |
| **Replication Factor** | **1** | **3** | **3** | **3** |

Dev uses `replication.factor=1` and `min.insync.replicas=1` for single-node operation. All other environments use `replication.factor=3` and `min.insync.replicas=2`.

---

## Confluent Platform Sync Wave Ordering

ArgoCD deploys Confluent Platform CRDs in a specific order using `argocd.argoproj.io/sync-wave` annotations:

| Wave | Components | Rationale |
|------|-----------|-----------|
| 0 | KRaftController | Must be running before Kafka brokers start |
| 1 | Kafka | Brokers depend on KRaft consensus layer |
| 2 | SchemaRegistry, Connect | Depend on Kafka bootstrap endpoint |
| 3 | ksqlDB, ControlCenter | Depend on Kafka, Schema Registry, and Connect |

---

## Namespace Convention

| Component | Namespace |
|-----------|-----------|
| ArgoCD | `argocd` |
| cert-manager | `cert-manager` |
| All Confluent components | `confluent-<env>` (e.g., `confluent-dev`, `confluent-prd`) |

---

## Helm Charts Reference

| Chart | Repository | Used For |
|-------|-----------|----------|
| `argo-cd` | `https://argoproj.github.io/argo-helm` | ArgoCD installation |
| `cert-manager` | `https://charts.jetstack.io` | TLS certificate management |
| `confluent-for-kubernetes` | `https://packages.confluent.io/helm` | Confluent Platform operator |
| `flink-kubernetes-operator` | `https://packages.confluent.io/helm` | Flink Kubernetes operator |
| `confluent-manager-for-apache-flink` | `https://packages.confluent.io/helm` | Flink SQL management (CMF) |

---

## Troubleshooting

### AWS CLI not found

```
Unable to connect to the server: getting credentials: exec: executable aws not found
```

Add the AWS CLI to your PATH:

```bash
export PATH="$PATH:/c/Program Files/Amazon/AWSCLIV2"
```

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

The dev environment has a pre-configured admin password: `3qnIIsA5FZfG1Krq`

For environments without a pre-configured password, retrieve the auto-generated one:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```
