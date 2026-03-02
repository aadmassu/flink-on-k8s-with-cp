# GitOps Config - ArgoCD ApplicationSets

This directory contains **ArgoCD ApplicationSet** definitions for multi-cluster orchestration. ApplicationSets are templates that generate ArgoCD Application resources dynamically based on a list of target clusters.

## Directory Structure

```
gitops-config/
+-- aws-us-east-2/                # Region
    |-- dev/                      # Environment
    |   |-- cert-manager-application-set.yaml
    |   |-- confluent-operator-application-set.yaml
    |   |-- confluent-flink-operator-application-set.yaml
    |   |-- confluent-platform-application-set.yaml
    |   +-- confluent-flink-application-set.yaml
    |-- qa/
    |-- stg/
    +-- prd/
```

## How ApplicationSets Work

Each ApplicationSet uses a **list generator** that defines target clusters. When applied, ArgoCD generates one Application resource per cluster entry.

Example generator:

```yaml
generators:
  - list:
      elements:
        - cluster: dev-cluster
          url: https://dev-cluster.example.com
          environment: dev
```

Template variables (`{{environment}}`, `{{url}}`, `{{cluster}}`) are substituted into the Application template to produce environment-specific resources.

## ApplicationSets per Environment

| ApplicationSet | Source | Description |
|----------------|--------|-------------|
| `cert-manager` | Helm chart from `charts.jetstack.io` | TLS certificate management |
| `confluent-operator` | Helm chart from `packages.confluent.io/helm` | Confluent Platform operator |
| `confluent-flink-operator` | Helm chart from `packages.confluent.io/helm` | Flink Kubernetes operator |
| `confluent-platform` | Git directory (`apps/confluent-platform/<env>/manifests`) | Confluent Platform CRDs |
| `confluent-flink` | Git directory (`apps/confluent-flink/<env>/manifests`) | Confluent Flink Manager CRDs |

## Sync Policies

| Environment | Sync Policy |
|-------------|-------------|
| dev | Automated (prune + selfHeal) |
| qa / stg / prd | Manual (syncOptions only, no automated block) |

## Usage

ApplicationSets are an alternative to applying individual `app.yaml` files. Apply an ApplicationSet to have ArgoCD automatically generate the corresponding Application:

```bash
kubectl apply -f gitops-config/aws-us-east-2/dev/cert-manager-application-set.yaml
```

> **Note:** Update the `url` field in each ApplicationSet's generator list to match your actual cluster API server endpoints before applying.
