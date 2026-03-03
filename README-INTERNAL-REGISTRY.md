# Using Internal Helm and Container Registries

This guide explains how to redirect all Helm chart downloads and container image pulls from their default public sources to your organization's internal registries.

---

## Table of Contents

- [When to Use This Guide](#when-to-use-this-guide)
- [Overview of Changes](#overview-of-changes)
- [Prerequisites](#prerequisites)
- [Inventory: Helm Charts to Mirror](#inventory-helm-charts-to-mirror)
- [Inventory: Container Images to Mirror](#inventory-container-images-to-mirror)
- [Step 1 — Mirror Helm Charts](#step-1--mirror-helm-charts)
- [Step 2 — Mirror Container Images](#step-2--mirror-container-images)
- [Step 3 — Create Image Pull Secrets](#step-3--create-image-pull-secrets)
- [Step 4 — Update ApplicationSet Files (Helm Chart URLs)](#step-4--update-applicationset-files-helm-chart-urls)
- [Step 5 — Update Helm Values Files (Container Image Overrides)](#step-5--update-helm-values-files-container-image-overrides)
- [Step 6 — Update ArgoCD Application Manifests](#step-6--update-argocd-application-manifests)
- [Step 7 — Update Confluent Platform CRD Manifests (Optional)](#step-7--update-confluent-platform-crd-manifests-optional)
- [Step 8 — Update CI/CD Pipelines and Scripts](#step-8--update-cicd-pipelines-and-scripts)
- [Step 9 — Configure ArgoCD Repository Credentials](#step-9--configure-argocd-repository-credentials)
- [Verification](#verification)
- [Complete File Change Checklist](#complete-file-change-checklist)
- [Troubleshooting](#troubleshooting)

---

## When to Use This Guide

- **Air-gapped / disconnected clusters** — your Kubernetes nodes cannot reach the public internet.
- **Security and compliance** — corporate policy requires image scanning, Software Bill of Materials (SBOM) tracking, or supply-chain controls before deployment.
- **Performance and reliability** — avoid Docker Hub rate limits, reduce image pull latency, and eliminate external dependencies during deployments.

---

## Target Versions

This guide targets the latest versions for a greenfield deployment. Mirror these specific versions (or newer) to your internal registries.

| Component | Version | Helm Chart | Chart Version |
|---|---|---|---|
| **Confluent Platform** | 8.1.1 | — (deployed via CFK CRDs) | — |
| **Confluent for Kubernetes (CFK)** | 3.1.1 | `confluent-for-kubernetes` | `0.*` (latest: `0.1351.59`) |
| **Flink Kubernetes Operator** | 1.13.x | `flink-kubernetes-operator` | `1.*` (latest: `~1.130.0`) |
| **Confluent Manager for Apache Flink (CMF)** | 2.2.x | `confluent-manager-for-apache-flink` | `2.*` (latest: `~2.2.0`) |
| **Apache Flink runtime** | 1.18.x – 2.1.x | — (job images) | — |
| **cert-manager** | 1.19.4 | `cert-manager` | `1.*` (latest: `1.19.4`) |
| **ArgoCD** | 2.14.x | `argo-cd` | `7.*` (latest: `7.8.0`) |

> Verify exact chart versions with `helm search repo <repo>/<chart> --versions` after adding the public repos.

---

## Overview of Changes

| What Changes | Which Files | Nature of Change |
|---|---|---|
| Helm chart source URLs | ApplicationSet YAMLs, ArgoCD app manifests, CI/CD pipelines, scripts | Replace public `repoURL` with internal URL |
| Container image registries | Helm `values.yaml` files | Add `image.registry` / `image.repository` overrides |
| Image pull credentials | Kubernetes secrets | Create `imagePullSecret` per namespace |
| ArgoCD repo credentials | Kubernetes secret | Add auth for internal Helm repo |

> **Placeholder convention:** This guide uses `registry.example.com` as the internal registry hostname throughout. Replace it with your actual registry (e.g., `artifactory.mycompany.com`, `nexus.mycompany.com`).

---

## Prerequisites

| Requirement | Details |
|---|---|
| Internal Helm repository | JFrog Artifactory, Sonatype Nexus, Harbor, or any OCI/HTTP Helm repo |
| Internal container registry | Same tool, or a dedicated container registry (ECR, GCR, ACR, etc.) |
| CLI tools | `docker` or `podman`, `helm` 3.14+, `oc` |
| Registry credentials | Push access (for mirroring) and pull access (for Kubernetes nodes) |

---

## Inventory: Helm Charts to Mirror

| Chart | Source Repository | Version Constraint | Referenced By |
|---|---|---|---|
| `cert-manager` | `https://charts.jetstack.io` | `1.*` | `gitops-config/openshift/{dev,qa,stg,prd}/cert-manager-application-set.yaml` |
| `confluent-for-kubernetes` | `https://packages.confluent.io/helm` | `0.*` | `gitops-config/openshift/{dev,qa,stg,prd}/confluent-operator-application-set.yaml` |
| `flink-kubernetes-operator` | `https://packages.confluent.io/helm` | `1.*` | `gitops-config/openshift/{dev,qa,stg,prd}/confluent-flink-operator-application-set.yaml` |
| `confluent-manager-for-apache-flink` | `https://packages.confluent.io/helm` | `1.*` | `apps/confluent-flink/openshift/{dev,qa,stg,prd}/manifests/confluent-flink-manager.yaml` |
| `argo-cd` | `https://argoproj.github.io/argo-helm` | `7.*` | `apps/argocd/{dev,qa,stg,prd}/app.yaml`, CI/CD pipelines |

---

## Inventory: Container Images to Mirror

The Helm charts pull the images listed below. No container image registries are referenced directly in this repository — they are embedded in the upstream charts. You must mirror these images so that your cluster nodes can pull them.

### cert-manager

| Image | Default Registry | Tag |
|---|---|---|
| `cert-manager-controller` | `quay.io/jetstack/cert-manager-controller` | `v1.19.4` |
| `cert-manager-webhook` | `quay.io/jetstack/cert-manager-webhook` | `v1.19.4` |
| `cert-manager-cainjector` | `quay.io/jetstack/cert-manager-cainjector` | `v1.19.4` |
| `cert-manager-startupapicheck` | `quay.io/jetstack/cert-manager-startupapicheck` | `v1.19.4` |
| `cert-manager-acmesolver` | `quay.io/jetstack/cert-manager-acmesolver` | `v1.19.4` |

### ArgoCD

| Image | Default Registry | Tag |
|---|---|---|
| `argocd` | `quay.io/argoproj/argocd` | `v2.14.0` |
| `dex` | `ghcr.io/dexidp/dex` | `v2.41.1` |
| `redis` | `docker.io/library/redis` | `7.4.2-alpine` |

### Confluent for Kubernetes Operator (CFK)

| Image | Default Registry | Tag |
|---|---|---|
| `confluent-operator` | `docker.io/confluentinc/confluent-operator` | `0.1351.59` |
| `confluent-init-container` | `docker.io/confluentinc/confluent-init-container` | `3.1.1` |

### Flink Kubernetes Operator

| Image | Default Registry | Tag |
|---|---|---|
| `confluent-flink-kubernetes-operator` | `docker.io/confluentinc/confluent-flink-kubernetes-operator` | `1.130.0` |

### Confluent Manager for Apache Flink (CMF)

| Image | Default Registry | Tag |
|---|---|---|
| `cp-cmf` | `docker.io/confluentinc/cp-cmf` | `2.2.0` |

### Confluent Platform (managed by CFK operator)

| Image | Default Registry | Tag |
|---|---|---|
| `cp-server` (Kafka / KRaft) | `docker.io/confluentinc/cp-server` | `8.1.1` |
| `cp-enterprise-control-center-next-gen` | `docker.io/confluentinc/cp-enterprise-control-center-next-gen` | `8.1.1` |
| `cp-enterprise-control-center` (classic) | `docker.io/confluentinc/cp-enterprise-control-center` | `8.1.1` |
| `cp-schema-registry` | `docker.io/confluentinc/cp-schema-registry` | `8.1.1` |
| `cp-server-connect` | `docker.io/confluentinc/cp-server-connect` | `8.1.1` |
| `cp-ksqldb-server` | `docker.io/confluentinc/cp-ksqldb-server` | `8.1.1` |
| `cp-kafka-rest` | `docker.io/confluentinc/cp-kafka-rest` | `8.1.1` |
| `confluent-init-container` | `docker.io/confluentinc/confluent-init-container` | `3.1.1` |

> **Key:** CFK controls Confluent Platform images via the `global.provider.registry.fqdn` Helm value on the operator chart. Setting this value once (Step 5b) means the CRD manifests (`kafka.yaml`, `schema-registry.yaml`, etc.) do **not** need individual image overrides.

---

## Step 1 — Mirror Helm Charts

### JFrog Artifactory

**Option A — Remote (proxy) repository** (non-air-gapped)

Create a remote Helm repository in Artifactory that proxies the upstream source. Artifactory caches charts on first request.

1. In Artifactory, create a **Remote** repository of type **Helm** for each upstream:
   - `helm-jetstack-remote` → `https://charts.jetstack.io`
   - `helm-confluent-remote` → `https://packages.confluent.io/helm`
   - `helm-argoproj-remote` → `https://argoproj.github.io/argo-helm`
2. Optionally create a **Virtual** repository (`helm-virtual`) that aggregates all three remotes.
3. Use the virtual repo URL as your single internal Helm URL:
   ```
   https://registry.example.com/artifactory/helm-virtual
   ```

**Option B — Local (hosted) repository** (air-gapped)

Download each chart and upload it manually.

```bash
# Add public repos temporarily on a machine with internet access
helm repo add jetstack https://charts.jetstack.io
helm repo add confluent https://packages.confluent.io/helm
helm repo add argo-cd https://argoproj.github.io/argo-helm
helm repo update

# Pull charts (latest versions for CP 8.1.1 greenfield deployment)
helm pull jetstack/cert-manager --version 1.19.4
helm pull confluent/confluent-for-kubernetes --version 0.1351.59
helm pull confluent/flink-kubernetes-operator --version 1.130.0
helm pull confluent/confluent-manager-for-apache-flink --version 2.2.0
helm pull argo-cd/argo-cd --version 7.8.0

# Upload to Artifactory local repo
for tgz in *.tgz; do
  curl -u "$ARTIFACTORY_USER:$ARTIFACTORY_TOKEN" \
    -T "$tgz" \
    "https://registry.example.com/artifactory/helm-local/$tgz"
done
```

> Adjust chart versions to match your target versions.

### Sonatype Nexus

**Option A — Proxy repository** (non-air-gapped)

1. In Nexus, create a **Proxy** repository of type **helm (proxy)** for each upstream.
2. Create a **Group** repository that combines them.
3. Use the group repo URL: `https://registry.example.com/repository/helm-group`

**Option B — Hosted repository** (air-gapped)

```bash
# Pull charts (same as Artifactory Option B above)
# Then upload to Nexus hosted repo:
for tgz in *.tgz; do
  curl -u "$NEXUS_USER:$NEXUS_PASSWORD" \
    --upload-file "$tgz" \
    "https://registry.example.com/repository/helm-hosted/$tgz"
done
```

### Verify Mirrored Charts

```bash
helm repo add internal https://registry.example.com/helm \
  --username "$REGISTRY_USER" --password "$REGISTRY_TOKEN"
helm repo update

helm search repo internal/cert-manager
helm search repo internal/confluent-for-kubernetes
helm search repo internal/flink-kubernetes-operator
helm search repo internal/confluent-manager-for-apache-flink
helm search repo internal/argo-cd
```

All five charts should appear with the expected versions.

---

## Step 2 — Mirror Container Images

### Pull, Tag, and Push (single image example)

```bash
# Pull from public registry
docker pull quay.io/jetstack/cert-manager-controller:v1.19.4

# Tag for internal registry
docker tag quay.io/jetstack/cert-manager-controller:v1.19.4 \
  registry.example.com/jetstack/cert-manager-controller:v1.19.4

# Push to internal registry
docker push registry.example.com/jetstack/cert-manager-controller:v1.19.4
```

### Bulk Mirror Script

```bash
#!/usr/bin/env bash
set -euo pipefail

INTERNAL_REGISTRY="registry.example.com"

IMAGES=(
  # cert-manager (v1.19.4)
  "quay.io/jetstack/cert-manager-controller:v1.19.4"
  "quay.io/jetstack/cert-manager-webhook:v1.19.4"
  "quay.io/jetstack/cert-manager-cainjector:v1.19.4"
  "quay.io/jetstack/cert-manager-startupapicheck:v1.19.4"
  "quay.io/jetstack/cert-manager-acmesolver:v1.19.4"

  # ArgoCD (v2.14.0)
  "quay.io/argoproj/argocd:v2.14.0"
  "ghcr.io/dexidp/dex:v2.41.1"
  "docker.io/library/redis:7.4.2-alpine"

  # CFK Operator (3.1.1)
  "docker.io/confluentinc/confluent-operator:0.1351.59"
  "docker.io/confluentinc/confluent-init-container:3.1.1"

  # Flink Operator (1.130.0)
  "docker.io/confluentinc/confluent-flink-kubernetes-operator:1.130.0"

  # Confluent Manager for Apache Flink (2.2.0)
  "docker.io/confluentinc/cp-cmf:2.2.0"

  # Confluent Platform (8.1.1)
  "docker.io/confluentinc/cp-server:8.1.1"
  "docker.io/confluentinc/cp-enterprise-control-center-next-gen:8.1.1"
  "docker.io/confluentinc/cp-enterprise-control-center:8.1.1"
  "docker.io/confluentinc/cp-schema-registry:8.1.1"
  "docker.io/confluentinc/cp-server-connect:8.1.1"
  "docker.io/confluentinc/cp-ksqldb-server:8.1.1"
  "docker.io/confluentinc/cp-kafka-rest:8.1.1"
)

for img in "${IMAGES[@]}"; do
  # Derive internal path: replace original registry prefix with internal registry
  # e.g. quay.io/jetstack/foo → registry.example.com/jetstack/foo
  src_without_registry="${img#*/}"
  internal_img="${INTERNAL_REGISTRY}/${src_without_registry}"

  echo "==> Mirroring: ${img} -> ${internal_img}"
  docker pull "$img"
  docker tag "$img" "$internal_img"
  docker push "$internal_img"
done

echo "Done. Mirrored ${#IMAGES[@]} images."
```

> Adjust image tags/versions to match the versions you are deploying.

### skopeo Alternative (air-gapped, registry-to-registry)

If you cannot use a Docker daemon (e.g., no root access), use `skopeo` to copy directly between registries:

```bash
skopeo copy \
  docker://quay.io/jetstack/cert-manager-controller:v1.19.4 \
  docker://registry.example.com/jetstack/cert-manager-controller:v1.19.4 \
  --dest-creds "$REGISTRY_USER:$REGISTRY_TOKEN"
```

---

## Step 3 — Create Image Pull Secrets

Each namespace that runs pods needs a pull secret for your internal registry.

```bash
# cert-manager namespace
oc create secret docker-registry internal-registry \
  --docker-server=registry.example.com \
  --docker-username="$REGISTRY_USER" \
  --docker-password="$REGISTRY_TOKEN" \
  -n cert-manager

# ArgoCD namespace (OpenShift GitOps)
oc create secret docker-registry internal-registry \
  --docker-server=registry.example.com \
  --docker-username="$REGISTRY_USER" \
  --docker-password="$REGISTRY_TOKEN" \
  -n openshift-gitops

# Per-environment Confluent namespaces
for ENV in dev qa stg prd; do
  oc create secret docker-registry internal-registry \
    --docker-server=registry.example.com \
    --docker-username="$REGISTRY_USER" \
    --docker-password="$REGISTRY_TOKEN" \
    -n "confluent-${ENV}"
done
```

### OpenShift Alternative

On OpenShift, you can add the credential to the global pull secret instead of per-namespace:

```bash
oc set data secret/pull-secret -n openshift-config \
  --from-file=.dockerconfigjson=<path-to-auth.json>
```

---

## Step 4 — Update ApplicationSet Files (Helm Chart URLs)

These files tell ArgoCD where to fetch each Helm chart.

### 4a. cert-manager (4 files)

Files:

```
gitops-config/openshift/dev/cert-manager-application-set.yaml
gitops-config/openshift/qa/cert-manager-application-set.yaml
gitops-config/openshift/stg/cert-manager-application-set.yaml
gitops-config/openshift/prd/cert-manager-application-set.yaml
```

Change:

```yaml
# Before
        - repoURL: https://charts.jetstack.io
          chart: cert-manager

# After
        - repoURL: https://registry.example.com/helm
          chart: cert-manager
```

### 4b. Confluent Operator (4 files)

Files:

```
gitops-config/openshift/dev/confluent-operator-application-set.yaml
gitops-config/openshift/qa/confluent-operator-application-set.yaml
gitops-config/openshift/stg/confluent-operator-application-set.yaml
gitops-config/openshift/prd/confluent-operator-application-set.yaml
```

Change:

```yaml
# Before
        - repoURL: https://packages.confluent.io/helm
          chart: confluent-for-kubernetes

# After
        - repoURL: https://registry.example.com/helm
          chart: confluent-for-kubernetes
```

### 4c. Flink Operator (4 files)

Files:

```
gitops-config/openshift/dev/confluent-flink-operator-application-set.yaml
gitops-config/openshift/qa/confluent-flink-operator-application-set.yaml
gitops-config/openshift/stg/confluent-flink-operator-application-set.yaml
gitops-config/openshift/prd/confluent-flink-operator-application-set.yaml
```

Change:

```yaml
# Before
        - repoURL: https://packages.confluent.io/helm
          chart: flink-kubernetes-operator

# After
        - repoURL: https://registry.example.com/helm
          chart: flink-kubernetes-operator
```

### Bulk sed one-liner for all 12 files

```bash
# cert-manager
sed -i 's|repoURL: https://charts.jetstack.io|repoURL: https://registry.example.com/helm|' \
  gitops-config/openshift/*/cert-manager-application-set.yaml

# Confluent Operator + Flink Operator
sed -i 's|repoURL: https://packages.confluent.io/helm|repoURL: https://registry.example.com/helm|' \
  gitops-config/openshift/*/confluent-operator-application-set.yaml \
  gitops-config/openshift/*/confluent-flink-operator-application-set.yaml
```

> **Note:** The `confluent-platform-application-set.yaml` and `confluent-flink-application-set.yaml` files point to a **Git** repository (not a Helm repo) — no change needed.

---

## Step 5 — Update Helm Values Files (Container Image Overrides)

These changes tell each Helm chart to pull container images from your internal registry instead of the default public registries.

### 5a. cert-manager (4 files)

Files:

```
apps/cert-manager/dev/values.yaml
apps/cert-manager/qa/values.yaml
apps/cert-manager/stg/values.yaml
apps/cert-manager/prd/values.yaml
```

Add these keys (merge with existing content):

```yaml
image:
  registry: registry.example.com
  repository: jetstack/cert-manager-controller

webhook:
  image:
    registry: registry.example.com
    repository: jetstack/cert-manager-webhook

cainjector:
  image:
    registry: registry.example.com
    repository: jetstack/cert-manager-cainjector

startupapicheck:
  image:
    registry: registry.example.com
    repository: jetstack/cert-manager-startupapicheck

global:
  imagePullSecrets:
    - name: internal-registry
```

### 5b. Confluent Operator / CFK (4 files)

Files:

```
apps/confluent-operator/dev/values.yaml
apps/confluent-operator/qa/values.yaml
apps/confluent-operator/stg/values.yaml
apps/confluent-operator/prd/values.yaml
```

Add these keys (merge with existing content):

```yaml
image:
  registry: registry.example.com
  repository: confluentinc/confluent-operator

# This single setting controls images for ALL Confluent Platform
# components (Kafka, KRaft, Schema Registry, Connect, ksqlDB,
# Control Center) deployed via CFK CRD manifests.
global:
  provider:
    registry:
      fqdn: registry.example.com

imagePullSecrets:
  - name: internal-registry
```

> **Key:** Setting `global.provider.registry.fqdn` means the CRD manifests under `apps/confluent-platform/` do **not** need individual image overrides. CFK automatically prefixes this registry to all Confluent Platform component images.

### 5c. Flink Operator (4 files)

Files:

```
apps/confluent-flink-operator/dev/values.yaml
apps/confluent-flink-operator/qa/values.yaml
apps/confluent-flink-operator/stg/values.yaml
apps/confluent-flink-operator/prd/values.yaml
```

Add these keys (merge with existing content):

```yaml
image:
  repository: registry.example.com/confluentinc/confluent-flink-kubernetes-operator

imagePullSecrets:
  - name: internal-registry
```

> The Flink operator chart uses `image.repository` as the full image path including registry prefix.

### 5d. ArgoCD (4 files)

Files:

```
apps/argocd/dev/values.yaml
apps/argocd/qa/values.yaml
apps/argocd/stg/values.yaml
apps/argocd/prd/values.yaml
```

Add/merge these keys. Note that `global:` already exists in these files (it contains `domain:`), so merge carefully:

```yaml
global:
  # domain: argocd-dev.example.com   # <-- already present, keep it
  image:
    registry: registry.example.com
    repository: argoproj/argocd
  imagePullSecrets:
    - name: internal-registry

dex:
  image:
    registry: registry.example.com
    repository: dexidp/dex

redis:
  image:
    registry: registry.example.com
    repository: library/redis
```

---

## Step 6 — Update ArgoCD Application Manifests

### 6a. ArgoCD Self-Management (4 files)

Files:

```
apps/argocd/dev/app.yaml
apps/argocd/qa/app.yaml
apps/argocd/stg/app.yaml
apps/argocd/prd/app.yaml
```

Change:

```yaml
# Before
  source:
    repoURL: https://argoproj.github.io/argo-helm
    chart: argo-cd

# After
  source:
    repoURL: https://registry.example.com/helm
    chart: argo-cd
```

### 6b. Confluent Flink Manager (4 files)

Files:

```
apps/confluent-flink/openshift/dev/manifests/confluent-flink-manager.yaml
apps/confluent-flink/openshift/qa/manifests/confluent-flink-manager.yaml
apps/confluent-flink/openshift/stg/manifests/confluent-flink-manager.yaml
apps/confluent-flink/openshift/prd/manifests/confluent-flink-manager.yaml
```

Change the `repoURL` and add image override parameters:

```yaml
# Before
  source:
    repoURL: https://packages.confluent.io/helm
    chart: confluent-manager-for-apache-flink
    targetRevision: 1.*
    helm:
      parameters:
        - name: cmf.sql.production
          value: "false"

# After
  source:
    repoURL: https://registry.example.com/helm
    chart: confluent-manager-for-apache-flink
    targetRevision: 1.*
    helm:
      parameters:
        - name: cmf.sql.production
          value: "false"
        - name: image.registry
          value: registry.example.com
        - name: image.repository
          value: confluentinc/cp-cmf
        - name: imagePullSecrets[0].name
          value: internal-registry
```

### Bulk sed for repoURL changes

```bash
# ArgoCD app manifests
sed -i 's|repoURL: https://argoproj.github.io/argo-helm|repoURL: https://registry.example.com/helm|' \
  apps/argocd/*/app.yaml

# Confluent Flink Manager manifests
sed -i 's|repoURL: https://packages.confluent.io/helm|repoURL: https://registry.example.com/helm|' \
  apps/confluent-flink/openshift/*/manifests/confluent-flink-manager.yaml
```

> The image override parameters for CMF must be added manually (see diff above).

---

## Step 7 — Update Confluent Platform CRD Manifests (Optional)

If you set `global.provider.registry.fqdn` in the Confluent Operator values (Step 5b), the CRD manifests under `apps/confluent-platform/` do **not** require changes. CFK automatically applies the internal registry to all managed component images.

However, if you need **per-component** image control (e.g., different tags per component), you can add explicit overrides to individual CRD manifests:

```yaml
# Example: apps/confluent-platform/dev/manifests/kafka.yaml
apiVersion: platform.confluent.io/v1beta1
kind: Kafka
metadata:
  name: kafka
  namespace: confluent-dev
spec:
  replicas: 1
  image:
    application: registry.example.com/confluentinc/cp-server:8.1.1
    init: registry.example.com/confluentinc/confluent-init-container:3.1.1
  podTemplate:
    spec:
      imagePullSecrets:
        - name: internal-registry
  # ... rest of spec unchanged
```

This is optional and only needed for fine-grained control beyond what `global.provider.registry.fqdn` provides.

---

## Step 8 — Update CI/CD Pipelines and Scripts

### 8a. GitHub Actions (2 files)

**`.github/workflows/full-deploy.yaml`** (lines 70–72)

```yaml
# Before
helm repo add argo-cd https://argoproj.github.io/argo-helm 2>/dev/null || true
helm repo add confluent https://packages.confluent.io/helm 2>/dev/null || true
helm repo add jetstack https://charts.jetstack.io 2>/dev/null || true

# After
helm repo add argo-cd https://registry.example.com/helm --username "$REGISTRY_USER" --password "$REGISTRY_TOKEN" 2>/dev/null || true
helm repo add confluent https://registry.example.com/helm --username "$REGISTRY_USER" --password "$REGISTRY_TOKEN" 2>/dev/null || true
helm repo add jetstack https://registry.example.com/helm --username "$REGISTRY_USER" --password "$REGISTRY_TOKEN" 2>/dev/null || true
```

> If all charts are in a single internal virtual repo, you can simplify to one `helm repo add` call.

The `helm upgrade --install argocd argo-cd/argo-cd` command on line 79 does not change because it references the local repo alias, not the URL.

**`.github/workflows/deploy-operators.yaml`**

This workflow does not add Helm repos (it only runs `oc apply`), so no changes are needed.

### 8b. Azure DevOps (2 files)

**`.azure-pipelines/full-deploy.yaml`** (lines 71–73)

Same change as GitHub Actions — replace the three `helm repo add` URLs with internal URLs.

**`.azure-pipelines/deploy-operators.yaml`**

No Helm repos referenced — no changes needed.

### 8c. Scripts

**`scripts/deploy-openshift-dev.sh`**

This script deploys via ArgoCD ApplicationSets and does not call `helm repo add` directly. Helm repository URLs are defined inside the ApplicationSet YAML files (updated in Steps 1–4 above), so no changes are needed in the script itself.

---

## Step 9 — Configure ArgoCD Repository Credentials

If your internal Helm repository requires authentication, ArgoCD needs credentials to pull charts. Create a Kubernetes secret with the `argocd.argoproj.io/secret-type: repository` label:

```bash
oc create secret generic internal-helm-repo \
  --namespace openshift-gitops \
  --from-literal=type=helm \
  --from-literal=name=internal-helm \
  --from-literal=url=https://registry.example.com/helm \
  --from-literal=username="$REGISTRY_USER" \
  --from-literal=password="$REGISTRY_TOKEN"

oc label secret internal-helm-repo -n openshift-gitops \
  argocd.argoproj.io/secret-type=repository
```

This allows ArgoCD to authenticate when fetching Helm charts from `https://registry.example.com/helm`.

---

## Verification

After completing all steps, verify the migration:

**1. Helm charts resolve from internal repo:**

```bash
helm search repo internal/
```

All five charts should be listed.

**2. Container images are accessible:**

```bash
docker pull registry.example.com/jetstack/cert-manager-controller:v1.19.4
docker pull registry.example.com/confluentinc/confluent-operator:0.1351.59
```

**3. Running pods use internal images:**

```bash
oc get pods -n cert-manager -o jsonpath='{range .items[*]}{.spec.containers[*].image}{"\n"}{end}'
oc get pods -n openshift-gitops -o jsonpath='{range .items[*]}{.spec.containers[*].image}{"\n"}{end}'
oc get pods -n confluent-dev -o jsonpath='{range .items[*]}{.spec.containers[*].image}{"\n"}{end}'
```

All images should show `registry.example.com/...` prefixes.

**4. No public URLs remain in config files:**

```bash
grep -r "charts.jetstack.io\|packages.confluent.io\|argoproj.github.io/argo-helm" \
  gitops-config/ apps/ scripts/ .github/ .azure-pipelines/
```

This should return no results.

**5. ArgoCD applications are healthy:**

```bash
oc get applications -n openshift-gitops \
  -o custom-columns=NAME:.metadata.name,HEALTH:.status.health.status,SYNC:.status.sync.status
```

All applications should show `Healthy` / `Synced`.

---

## Complete File Change Checklist

| # | File | Change Type |
|---|---|---|
| | **ApplicationSets — Helm chart URLs** | |
| 1 | `gitops-config/openshift/dev/cert-manager-application-set.yaml` | `repoURL` |
| 2 | `gitops-config/openshift/qa/cert-manager-application-set.yaml` | `repoURL` |
| 3 | `gitops-config/openshift/stg/cert-manager-application-set.yaml` | `repoURL` |
| 4 | `gitops-config/openshift/prd/cert-manager-application-set.yaml` | `repoURL` |
| 5 | `gitops-config/openshift/dev/confluent-operator-application-set.yaml` | `repoURL` |
| 6 | `gitops-config/openshift/qa/confluent-operator-application-set.yaml` | `repoURL` |
| 7 | `gitops-config/openshift/stg/confluent-operator-application-set.yaml` | `repoURL` |
| 8 | `gitops-config/openshift/prd/confluent-operator-application-set.yaml` | `repoURL` |
| 9 | `gitops-config/openshift/dev/confluent-flink-operator-application-set.yaml` | `repoURL` |
| 10 | `gitops-config/openshift/qa/confluent-flink-operator-application-set.yaml` | `repoURL` |
| 11 | `gitops-config/openshift/stg/confluent-flink-operator-application-set.yaml` | `repoURL` |
| 12 | `gitops-config/openshift/prd/confluent-flink-operator-application-set.yaml` | `repoURL` |
| | **Helm values — container image overrides** | |
| 13 | `apps/cert-manager/dev/values.yaml` | Image registry + pull secret |
| 14 | `apps/cert-manager/qa/values.yaml` | Image registry + pull secret |
| 15 | `apps/cert-manager/stg/values.yaml` | Image registry + pull secret |
| 16 | `apps/cert-manager/prd/values.yaml` | Image registry + pull secret |
| 17 | `apps/confluent-operator/dev/values.yaml` | Image registry + `global.provider.registry.fqdn` + pull secret |
| 18 | `apps/confluent-operator/qa/values.yaml` | Image registry + `global.provider.registry.fqdn` + pull secret |
| 19 | `apps/confluent-operator/stg/values.yaml` | Image registry + `global.provider.registry.fqdn` + pull secret |
| 20 | `apps/confluent-operator/prd/values.yaml` | Image registry + `global.provider.registry.fqdn` + pull secret |
| 21 | `apps/confluent-flink-operator/dev/values.yaml` | Image repository + pull secret |
| 22 | `apps/confluent-flink-operator/qa/values.yaml` | Image repository + pull secret |
| 23 | `apps/confluent-flink-operator/stg/values.yaml` | Image repository + pull secret |
| 24 | `apps/confluent-flink-operator/prd/values.yaml` | Image repository + pull secret |
| 25 | `apps/argocd/dev/values.yaml` | Image registry + pull secret |
| 26 | `apps/argocd/qa/values.yaml` | Image registry + pull secret |
| 27 | `apps/argocd/stg/values.yaml` | Image registry + pull secret |
| 28 | `apps/argocd/prd/values.yaml` | Image registry + pull secret |
| | **ArgoCD Application manifests** | |
| 29 | `apps/argocd/dev/app.yaml` | `repoURL` |
| 30 | `apps/argocd/qa/app.yaml` | `repoURL` |
| 31 | `apps/argocd/stg/app.yaml` | `repoURL` |
| 32 | `apps/argocd/prd/app.yaml` | `repoURL` |
| 33 | `apps/confluent-flink/openshift/dev/manifests/confluent-flink-manager.yaml` | `repoURL` + image params |
| 34 | `apps/confluent-flink/openshift/qa/manifests/confluent-flink-manager.yaml` | `repoURL` + image params |
| 35 | `apps/confluent-flink/openshift/stg/manifests/confluent-flink-manager.yaml` | `repoURL` + image params |
| 36 | `apps/confluent-flink/openshift/prd/manifests/confluent-flink-manager.yaml` | `repoURL` + image params |
| | **CI/CD pipelines and scripts** | |
| 37 | `.github/workflows/full-deploy.yaml` | `helm repo add` URLs |
| 38 | `.azure-pipelines/full-deploy.yaml` | `helm repo add` URLs |
| 39 | `scripts/deploy-openshift-dev.sh` | No changes needed (uses ApplicationSets) |
| | **Documentation** | |
| 40 | `README.md` | Update references if needed |

> Total: **~40 files**. The `deploy-operators.yaml` pipelines (GitHub + Azure) and `confluent-platform/` CRD manifests do not require changes.

---

## Troubleshooting

### ImagePullBackOff after switching registries

```bash
oc describe pod <pod-name> -n <namespace>
```

Check the Events section for the exact error. Common causes:
- Image pull secret not created in the target namespace (Step 3)
- Image not mirrored to internal registry (Step 2)
- Wrong image path in values override (typo in registry or repository)

### Helm chart not found in internal repo

```bash
helm search repo internal/<chart-name>
```

If the chart is missing:
- Verify it was uploaded / proxied correctly
- Run `helm repo update` to refresh the index
- Check that the version constraint (e.g., `1.*`) resolves to an available version

### ArgoCD cannot pull Helm chart (authentication error)

ArgoCD needs repository credentials for authenticated Helm repos. See [Step 9](#step-9--configure-argocd-repository-credentials).

Check if the credential secret exists:

```bash
oc get secret -n openshift-gitops -l argocd.argoproj.io/secret-type=repository
```

### Version wildcards don't resolve in hosted repos

Hosted/local Helm repos (as opposed to proxy repos) must have the exact chart version uploaded. Version wildcards like `1.*` resolve against the repository index — ensure the index includes your uploaded version.

```bash
# Verify what's in the repo
helm search repo internal/<chart-name> --versions
```

### Confluent Platform pods still pulling from docker.io

This means `global.provider.registry.fqdn` was not set in the Confluent Operator values. Verify:

```bash
oc get application confluent-operator-dev -n openshift-gitops -o jsonpath='{.status.sync.status}'
```

Look for:

```yaml
global:
  provider:
    registry:
      fqdn: registry.example.com
```

If missing, update `apps/confluent-operator/<env>/values.yaml` and sync the ArgoCD application.
