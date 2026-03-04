# Using JFrog Artifactory as Internal Helm and Container Registry

This guide explains how to redirect all Helm chart downloads and container image pulls from their default public sources to JFrog Artifactory (or a compatible OCI/HTTP registry) in an air-gapped environment.

---

## Table of Contents

- [When to Use This Guide](#when-to-use-this-guide)
- [Prerequisites](#prerequisites)
- [Inventory: Helm Charts](#inventory-helm-charts)
- [Inventory: Container Images](#inventory-container-images)
- [Step 1 — Pull and Upload Helm Charts](#step-1--pull-and-upload-helm-charts)
- [Step 2 — Pull, Tag, and Push Container Images](#step-2--pull-tag-and-push-container-images)
- [Step 3 — Create Image Pull Secrets](#step-3--create-image-pull-secrets)
- [Step 4 — Update ApplicationSet Files (Helm Chart URLs)](#step-4--update-applicationset-files-helm-chart-urls)
- [Step 5 — Update Helm Values Files (Container Image Overrides)](#step-5--update-helm-values-files-container-image-overrides)
- [Step 6 — Update ArgoCD Application Manifests](#step-6--update-argocd-application-manifests)
- [Step 7 — Update CI/CD Pipelines and Scripts](#step-7--update-cicd-pipelines-and-scripts)
- [Step 8 — Configure ArgoCD Repository Credentials](#step-8--configure-argocd-repository-credentials)
- [Verification](#verification)
- [Complete File Change Checklist](#complete-file-change-checklist)
- [Troubleshooting](#troubleshooting)

---

## When to Use This Guide

- **Air-gapped / disconnected clusters** — your Kubernetes nodes cannot reach the public internet.
- **Security and compliance** — corporate policy requires image scanning, Software Bill of Materials (SBOM) tracking, or supply-chain controls before deployment.
- **Performance and reliability** — avoid Docker Hub rate limits, reduce image pull latency, and eliminate external dependencies during deployments.

In short, if your environment cannot — or your organization prefers not to — pull container images and Helm charts directly from public registries (e.g., Confluent's Docker image repository, Helm package repositories, Docker Hub), and you instead need to host those artifacts in JFrog Artifactory, this guide is for you.

---

## Target Versions

All deployments use **pinned versions** for reproducibility and audit compliance. The discovery scripts in this repository are informational — the deployment always uses the pinned versions below. Pull, tag, and push these exact versions to Artifactory.

**Phase 1 — Operators:**

| Component | Version | Helm Chart | targetRevision |
|---|---|---|---|
| **Confluent for Kubernetes (CFK)** | 3.1.1 | `confluent-for-kubernetes` | `0.1351.59` |
| **Flink Kubernetes Operator** | 1.13.0-cp2 | `flink-kubernetes-operator` | `1.130.2` |
| **cert-manager** | 1.19.4 | `cert-manager` | `v1.19.4` |
| **ArgoCD** | 3.3.2 | `argo-cd` | `9.4.7` |

**Phase 2 — CMF + Flink Runtime** (add when deploying Flink on K8s):

| Component | Version | Helm Chart | Notes |
|---|---|---|---|
| **Confluent Manager for Apache Flink (CMF)** | 2.2.0 | `confluent-manager-for-apache-flink` | CMF operator |
| **Flink SQL Runtime** | 1.19.4-cp1 | — | Runtime image used by `FlinkApplication` / SQL statements |

**Phase 3 — Confluent Platform on K8s** (add when moving CP from VMs to K8s):

| Component | Version | Notes |
|---|---|---|
| **Confluent Platform** | 8.1.1 | CP component images (cp-server, cp-schema-registry, etc.) |
| **CFK init container** | 3.1.1 | `confluent-init-container` — used by CFK-managed CRs |

> **Versions verified as of March 2026.** CFK 3.1.1 aligns with CP 8.1.1 per [Confluent release notes](https://docs.confluent.io/operator/current/release-notes.html). CMF 2.2.0 per [Flink changelog](https://docs.confluent.io/cloud/current/flink/changelog.html). Check [cert-manager releases](https://github.com/cert-manager/cert-manager/releases) and [ArgoCD Helm chart releases](https://github.com/argoproj/argo-helm/releases) for updates.

### Wildcard vs. Pinned Version Constraints

All environments use **pinned versions** for fully reproducible, auditable deployments. The table below compares the two approaches for reference:

| Approach | Pros | Cons |
|---|---|---|
| **Wildcard** (`1.*`, `0.*`) | Automatically picks up patch/minor fixes on sync; no manual bumps needed; reduces maintenance overhead | May pull in breaking changes on minor bumps; harder to reproduce exact deployments; audit/compliance teams may flag non-deterministic versions |
| **Pinned** (`0.1351.59`, `1.130.2`) | Fully reproducible deployments; explicit change control; easier to audit and rollback; required for air-gapped environments | Requires manual version bumps in Git; easy to fall behind on security patches; more PR churn |

This repository uses **pinned versions across all environments** (dev, qa, stg, prd). When upgrading, update the pinned version in `dev` first, validate through `qa` and `stg`, then promote to `prd`.

### Discover Available Chart Versions

Add the public Helm repos and query each chart to find the latest available versions:

```bash
# Add repos
helm repo add jetstack https://charts.jetstack.io
helm repo add confluent https://packages.confluent.io/helm
helm repo add argo-cd https://argoproj.github.io/argo-helm
helm repo update

# Query latest versions
echo "=== cert-manager ==="
helm search repo jetstack/cert-manager --versions | head -5

echo ""
echo "=== confluent-for-kubernetes (CFK) ==="
helm search repo confluent/confluent-for-kubernetes --versions | head -5

echo ""
echo "=== flink-kubernetes-operator ==="
helm search repo confluent/flink-kubernetes-operator --versions | head -5

echo ""
echo "=== argo-cd ==="
helm search repo argo-cd/argo-cd --versions | head -5
```

### Validate Resolved Versions Against ApplicationSets

Use [`scripts/validate-resolvable-versions.sh`](scripts/validate-resolvable-versions.sh) to verify that pinned chart versions exist. The script uses `helm show chart` (which actually fetches chart metadata) for a stronger signal than `helm search`:

```bash
# Check public repos (internet-connected staging box)
./scripts/validate-resolvable-versions.sh

# Check your internal Artifactory repo (after uploading charts)
./scripts/validate-resolvable-versions.sh --internal
```

Example output:

```
ApplicationSet Pinned Version Check (public repos)
====================================
CHART                               PINNED          STATUS
-----------------------------------+--------------+----------
cert-manager                        v1.19.4        OK
confluent-for-kubernetes            0.1351.59      OK
flink-kubernetes-operator           1.130.2        OK
argo-cd                             9.4.7          OK
```

---

## Prerequisites

| Requirement | Details |
|---|---|
| JFrog Artifactory | Helm (virtual + local) repository and Docker registry configured |
| Internet-connected staging box | A machine with access to both the public internet and Artifactory — used to pull, tag, and push artifacts |
| CLI tools | `docker` or `podman`, `helm` 3.14+, `oc`, `curl` (for Artifactory API) |
| Artifactory credentials | Push access (for uploading) and pull access (for Kubernetes nodes) |

---

## Inventory: Helm Charts

| Chart | Source Repository | Pinned Version | Referenced By |
|---|---|---|---|
| `cert-manager` | `https://charts.jetstack.io` | `v1.19.4` | `gitops-config/openshift/{dev,qa,stg,prd}/cert-manager-application-set.yaml` |
| `confluent-for-kubernetes` | `https://packages.confluent.io/helm` | `0.1351.59` | `gitops-config/openshift/{dev,qa,stg,prd}/confluent-operator-application-set.yaml` |
| `flink-kubernetes-operator` | `https://packages.confluent.io/helm` | `1.130.2` | `gitops-config/openshift/{dev,qa,stg,prd}/confluent-flink-operator-application-set.yaml` |
| `argo-cd` | `https://argoproj.github.io/argo-helm` | `9.4.7` | `apps/argocd/{dev,qa,stg,prd}/app.yaml`, CI/CD pipelines |

**Phase 2 (add when deploying CMF + Flink on K8s):**

| Chart | Source Repository | Pinned Version | Notes |
|---|---|---|---|
| `confluent-manager-for-apache-flink` | `https://packages.confluent.io/helm` | `2.2.0` | CMF Helm chart; add when Phase 2 begins |

---

## Inventory: Container Images

The Helm charts pull the images listed below. No container image registries are referenced directly in this repository — they are embedded in the upstream charts. You must pull, tag, and push these images to your internal registry so that your cluster nodes can access them.

### Image Inventory Is Generated, Not Curated

> **The tables below are examples, not the source of truth.** Charts embed image references
> that change across versions — the only reliable inventory is the output of `helm template`
> with your pinned chart versions and values files.
>
> Run [`scripts/discover-charts-and-images.sh`](scripts/discover-charts-and-images.sh) to
> generate the authoritative image list. The script also writes `images-phase{1,2,3}.txt`
> files that can be fed directly into a bulk mirror script.
>
> **Always mirror what the script outputs, not what these tables say.** This prevents
> `ImagePullBackOff` failures caused by charts embedding images (e.g., a different Redis
> registry, updated dex version) that don't appear in a hand-maintained list.

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
| `argocd` | `quay.io/argoproj/argocd` | `v3.3.2` |
| `dex` | `ghcr.io/dexidp/dex` | `v2.44.0` |
| `redis` | `public.ecr.aws/docker/library/redis` | `7.4.2-alpine` |

> **Verify the Redis registry string.** The ArgoCD chart changed its default Redis image
> source across versions. Run `helm template` with your pinned chart version to confirm
> the exact registry and tag before mirroring.

### Confluent for Kubernetes Operator (CFK)

| Image | Default Registry | Tag |
|---|---|---|
| `confluent-operator` | `docker.io/confluentinc/confluent-operator` | `0.1351.59` |
| `confluent-init-container` | `docker.io/confluentinc/confluent-init-container` | `3.1.1` |

### Flink Kubernetes Operator

| Image | Default Registry | Tag |
|---|---|---|
| `cp-flink-kubernetes-operator` | `docker.io/confluentinc/cp-flink-kubernetes-operator` | `1.13.0-cp2` |

### Phase 2/3 Images (mirror when needed)

The images above cover **Phase 1 (operators only)**. When you move to later phases, you must also mirror these additional images into Artifactory. **Always regenerate from the script** — the tables below are examples.

**Phase 2 — CMF + Flink on K8s** (Confluent Platform stays on VMs):

| Image | Default Registry | Tag | Notes |
|---|---|---|---|
| `cp-cmf` | `docker.io/confluentinc/cp-cmf` | `2.2.0` | Confluent Manager for Apache Flink |
| `cp-flink` | `docker.io/confluentinc/cp-flink` | `1.19.4-cp1` | Flink SQL runtime image used by `FlinkApplication` CRs and SQL statements |

**Phase 3 — Confluent Platform on K8s via CFK** (add to Phase 1 + 2):

| Image | Default Registry | Tag | Notes |
|---|---|---|---|
| `confluent-init-container` | `docker.io/confluentinc/confluent-init-container` | `3.1.1` | CFK init container for all CP CRs |
| `cp-server` | `docker.io/confluentinc/cp-server` | `8.1.1` | Kafka broker (Confluent Server) |
| `cp-schema-registry` | `docker.io/confluentinc/cp-schema-registry` | `8.1.1` | Schema Registry |
| `cp-kafka-connect` | `docker.io/confluentinc/cp-kafka-connect` | `8.1.1` | Kafka Connect (if needed) |
| `cp-enterprise-control-center` | `docker.io/confluentinc/cp-enterprise-control-center` | `8.1.1` | Control Center (if needed) |
| `cp-ksqldb-server` | `docker.io/confluentinc/cp-ksqldb-server` | `8.1.1` | ksqlDB (if needed) |
| `cp-kafka-rest` | `docker.io/confluentinc/cp-kafka-rest` | `8.1.1` | REST Proxy (optional) |
| `cp-zookeeper` | `docker.io/confluentinc/cp-zookeeper` | `8.1.1` | Only if not using KRaft |

> **Generate the mirror manifest, don't copy-paste the tables:**
> ```bash
> ./scripts/discover-charts-and-images.sh --phase 2    # outputs images-phase2.txt
> ./scripts/discover-charts-and-images.sh --phase 3    # outputs images-phase3.txt
> ```
> Feed the generated `.txt` files directly into your bulk mirror script.

---

## Step 1 — Pull and Upload Helm Charts

Pull each chart from the public repository and upload it to your internal Helm repository.

```bash
# Add public repos on a machine with internet access
helm repo add jetstack https://charts.jetstack.io
helm repo add confluent https://packages.confluent.io/helm
helm repo add argo-cd https://argoproj.github.io/argo-helm
helm repo update

# Pull charts
helm pull jetstack/cert-manager --version v1.19.4
helm pull confluent/confluent-for-kubernetes --version 0.1351.59
helm pull confluent/flink-kubernetes-operator --version 1.130.2
helm pull argo-cd/argo-cd --version 9.4.7
```

Upload the `.tgz` files to JFrog Artifactory:

```bash
# Upload to Artifactory local Helm repo
for tgz in *.tgz; do
  curl -u "$ARTIFACTORY_USER:$ARTIFACTORY_TOKEN" \
    -T "$tgz" \
    "https://artifactory.example.com/artifactory/helm-local/$tgz"
done
```

> **Tip:** If you have a virtual Helm repo in Artifactory that aggregates `helm-local` + remote proxies, point `helm repo add` at the virtual repo URL for a unified view.

### Verify Charts in Internal Repo

```bash
helm repo add internal https://artifactory.example.com/artifactory/helm-virtual \
  --username "$ARTIFACTORY_USER" --password "$ARTIFACTORY_TOKEN"
helm repo update

helm search repo internal/cert-manager
helm search repo internal/confluent-for-kubernetes
helm search repo internal/flink-kubernetes-operator
helm search repo internal/argo-cd
```

All four charts should appear with the expected versions.

### Alternative: OCI-Based Helm Repository

JFrog Artifactory natively supports OCI artifacts. You can push and pull charts using `oci://` instead of managing an HTTP Helm repository index:

```bash
# Push a chart to an OCI registry
helm push cert-manager-v1.19.4.tgz oci://artifactory.example.com/helm-charts

# Pull from OCI (no helm repo add required)
helm pull oci://artifactory.example.com/helm-charts/cert-manager --version v1.19.4
```

OCI Helm avoids the index-management overhead of HTTP Helm repos. To use OCI with ArgoCD, set the ApplicationSet source to:

```yaml
- repoURL: artifactory.example.com/helm-charts
  chart: cert-manager
  targetRevision: v1.19.4
```

and configure the ArgoCD repository secret with `type: helm` and `enableOCI: "true"`. The rest of this guide assumes HTTP Helm repos as the primary path.

---

## Step 2 — Pull, Tag, and Push Container Images

### Single Image Example

```bash
# Pull from public registry
docker pull quay.io/jetstack/cert-manager-controller:v1.19.4

# Tag for internal registry
docker tag quay.io/jetstack/cert-manager-controller:v1.19.4 \
  artifactory.example.com/jetstack/cert-manager-controller:v1.19.4

# Push to internal registry
docker push artifactory.example.com/jetstack/cert-manager-controller:v1.19.4
```

### Bulk Pull, Tag, and Push Script

```bash
#!/usr/bin/env bash
set -euo pipefail

INTERNAL_REGISTRY="artifactory.example.com"

IMAGES=(
  # cert-manager (v1.19.4)
  "quay.io/jetstack/cert-manager-controller:v1.19.4"
  "quay.io/jetstack/cert-manager-webhook:v1.19.4"
  "quay.io/jetstack/cert-manager-cainjector:v1.19.4"
  "quay.io/jetstack/cert-manager-startupapicheck:v1.19.4"
  "quay.io/jetstack/cert-manager-acmesolver:v1.19.4"

  # ArgoCD (v3.3.2)
  "quay.io/argoproj/argocd:v3.3.2"
  "ghcr.io/dexidp/dex:v2.44.0"
  "public.ecr.aws/docker/library/redis:7.4.2-alpine"

  # CFK Operator (0.1351.59)
  "docker.io/confluentinc/confluent-operator:0.1351.59"

  # Flink Operator (1.13.0-cp2)
  "docker.io/confluentinc/cp-flink-kubernetes-operator:1.13.0-cp2"

)

for img in "${IMAGES[@]}"; do
  # Derive internal path: replace original registry prefix with internal registry
  # e.g. quay.io/jetstack/foo → artifactory.example.com/jetstack/foo
  src_without_registry="${img#*/}"
  internal_img="${INTERNAL_REGISTRY}/${src_without_registry}"

  echo "==> Pushing: ${img} -> ${internal_img}"
  docker pull "$img"
  docker tag "$img" "$internal_img"
  docker push "$internal_img"
done

echo "Done. Pushed ${#IMAGES[@]} images."
```

> Adjust image tags/versions to match the versions you are deploying.

---

## Step 3 — Create Image Pull Secrets

Each namespace that runs pods needs a pull secret for your internal registry.

```bash
# cert-manager namespace
oc create secret docker-registry internal-registry \
  --docker-server=artifactory.example.com \
  --docker-username="$ARTIFACTORY_USER" \
  --docker-password="$ARTIFACTORY_TOKEN" \
  -n cert-manager

# ArgoCD namespace (OpenShift GitOps)
oc create secret docker-registry internal-registry \
  --docker-server=artifactory.example.com \
  --docker-username="$ARTIFACTORY_USER" \
  --docker-password="$ARTIFACTORY_TOKEN" \
  -n openshift-gitops

# Per-environment Confluent namespaces
for ENV in dev qa stg prd; do
  oc create secret docker-registry internal-registry \
    --docker-server=artifactory.example.com \
    --docker-username="$ARTIFACTORY_USER" \
    --docker-password="$ARTIFACTORY_TOKEN" \
    -n "confluent-${ENV}"
done
```

### Recommended: OpenShift Global Pull Secret

On OpenShift, the simplest and most reliable approach is to add your internal registry credential to the **cluster-wide global pull secret**. This avoids creating and maintaining per-namespace secrets and ensures every namespace — including any added in future phases — can pull images automatically:

```bash
# Extract current global pull secret
oc get secret/pull-secret -n openshift-config \
  --template='{{index .data ".dockerconfigjson" | base64decode}}' > /tmp/pull-secret.json

# Merge your internal registry credential (use jq or manual edit)
# Then apply:
oc set data secret/pull-secret -n openshift-config \
  --from-file=.dockerconfigjson=/tmp/pull-secret.json
```

> **Note:** Updating the global pull secret triggers a rolling restart of all nodes (MachineConfig update). Plan this during a maintenance window.

If your security policy prohibits cluster-wide credentials, fall back to the per-namespace approach shown above.

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
        - repoURL: https://artifactory.example.com/artifactory/helm-virtual
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
        - repoURL: https://artifactory.example.com/artifactory/helm-virtual
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
        - repoURL: https://artifactory.example.com/artifactory/helm-virtual
          chart: flink-kubernetes-operator
```

### Bulk sed one-liner for all 12 files

```bash
# cert-manager
sed -i 's|repoURL: https://charts.jetstack.io|repoURL: https://artifactory.example.com/artifactory/helm-virtual|' \
  gitops-config/openshift/*/cert-manager-application-set.yaml

# Confluent Operator + Flink Operator
sed -i 's|repoURL: https://packages.confluent.io/helm|repoURL: https://artifactory.example.com/artifactory/helm-virtual|' \
  gitops-config/openshift/*/confluent-operator-application-set.yaml \
  gitops-config/openshift/*/confluent-flink-operator-application-set.yaml
```

> **Note:** Only the three operator ApplicationSets reference Helm repos. Other ApplicationSets (added in future phases) may point to Git repositories and would not need this change.

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
  registry: artifactory.example.com
  repository: jetstack/cert-manager-controller

webhook:
  image:
    registry: artifactory.example.com
    repository: jetstack/cert-manager-webhook

cainjector:
  image:
    registry: artifactory.example.com
    repository: jetstack/cert-manager-cainjector

startupapicheck:
  image:
    registry: artifactory.example.com
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
  registry: artifactory.example.com
  repository: confluentinc/confluent-operator

imagePullSecrets:
  - name: internal-registry
```

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
  repository: artifactory.example.com/confluentinc/cp-flink-kubernetes-operator

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
    registry: artifactory.example.com
    repository: argoproj/argocd
  imagePullSecrets:
    - name: internal-registry

dex:
  image:
    registry: artifactory.example.com
    repository: dexidp/dex

redis:
  image:
    registry: artifactory.example.com
    repository: docker/library/redis
```

---

## Step 6 — Update ArgoCD Application Manifests

### ArgoCD Self-Management (4 files)

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
    repoURL: https://artifactory.example.com/artifactory/helm-virtual
    chart: argo-cd
```

### Bulk sed for repoURL changes

```bash
# ArgoCD app manifests
sed -i 's|repoURL: https://argoproj.github.io/argo-helm|repoURL: https://artifactory.example.com/artifactory/helm-virtual|' \
  apps/argocd/*/app.yaml
```

---

## Step 7 — Update CI/CD Pipelines and Scripts

### 8a. GitHub Actions (2 files)

**`.github/workflows/full-deploy.yaml`** (lines 70–72)

```yaml
# Before
helm repo add argo-cd https://argoproj.github.io/argo-helm 2>/dev/null || true
helm repo add confluent https://packages.confluent.io/helm 2>/dev/null || true
helm repo add jetstack https://charts.jetstack.io 2>/dev/null || true

# After
helm repo add argo-cd https://artifactory.example.com/artifactory/helm-virtual --username "$ARTIFACTORY_USER" --password "$ARTIFACTORY_TOKEN" 2>/dev/null || true
helm repo add confluent https://artifactory.example.com/artifactory/helm-virtual --username "$ARTIFACTORY_USER" --password "$ARTIFACTORY_TOKEN" 2>/dev/null || true
helm repo add jetstack https://artifactory.example.com/artifactory/helm-virtual --username "$ARTIFACTORY_USER" --password "$ARTIFACTORY_TOKEN" 2>/dev/null || true
```

> If all charts are in a single Artifactory virtual Helm repo, you can simplify to one `helm repo add` call.

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

## Step 8 — Configure ArgoCD Repository Credentials

If your internal Helm repository requires authentication, ArgoCD needs credentials to pull charts. Create a Kubernetes secret with the `argocd.argoproj.io/secret-type: repository` label:

```bash
oc create secret generic internal-helm-repo \
  --namespace openshift-gitops \
  --from-literal=type=helm \
  --from-literal=name=internal-helm \
  --from-literal=url=https://artifactory.example.com/artifactory/helm-virtual \
  --from-literal=username="$ARTIFACTORY_USER" \
  --from-literal=password="$ARTIFACTORY_TOKEN"

oc label secret internal-helm-repo -n openshift-gitops \
  argocd.argoproj.io/secret-type=repository
```

This allows ArgoCD to authenticate when fetching Helm charts from Artifactory. The `helm-virtual` repo in Artifactory should aggregate your `helm-local` repository (where you uploaded the `.tgz` files) and optionally any remote proxies.

---

## Verification

After completing all steps, verify:

**1. Helm charts resolve from internal repo:**

```bash
helm search repo internal/
```

All five charts should be listed.

**2. Container images are accessible:**

```bash
docker pull artifactory.example.com/jetstack/cert-manager-controller:v1.19.4
docker pull artifactory.example.com/confluentinc/confluent-operator:0.1351.59
```

**3. Running pods use internal images:**

```bash
oc get pods -n cert-manager -o jsonpath='{range .items[*]}{.spec.containers[*].image}{"\n"}{end}'
oc get pods -n openshift-gitops -o jsonpath='{range .items[*]}{.spec.containers[*].image}{"\n"}{end}'
oc get pods -n confluent-dev -o jsonpath='{range .items[*]}{.spec.containers[*].image}{"\n"}{end}'
```

All images should show `artifactory.example.com/...` prefixes.

**4. No public URLs remain in config files:**

```bash
grep -r "charts.jetstack.io\|packages.confluent.io\|argoproj.github.io/argo-helm" \
  gitops-config/ apps/ scripts/ .github/ .azure-pipelines/
```

This should return no results.

**5. All rendered images exist in Artifactory:**

Render the charts with pinned versions and verify every image exists in Artifactory. This catches images missed during the pull/push step and is the most reliable pre-flight for air-gapped installs:

```bash
#!/usr/bin/env bash
set -euo pipefail

ARTIFACTORY_URL="https://artifactory.example.com"
DOCKER_REPO="docker-local"       # your Artifactory Docker repo name

# Step A — Render each chart with pinned versions + values
RENDERED=$(mktemp)
helm template cert-manager jetstack/cert-manager \
    --version v1.19.4 \
    -f apps/cert-manager/dev/values.yaml \
    -f apps/cert-manager/openshift-overlay.yaml >> "$RENDERED"
helm template cfk confluent/confluent-for-kubernetes \
    --version 0.1351.59 \
    -f apps/confluent-operator/dev/values.yaml \
    -f apps/confluent-operator/openshift-overlay.yaml >> "$RENDERED"
helm template flink confluent/flink-kubernetes-operator \
    --version 1.130.2 \
    -f apps/confluent-flink-operator/dev/values.yaml \
    -f apps/confluent-flink-operator/openshift-overlay.yaml >> "$RENDERED"
helm template argocd argo-cd/argo-cd \
    --version 9.4.7 \
    -f apps/argocd/dev/values.yaml >> "$RENDERED"

# Step B — Extract every unique image from rendered YAML
UNIQUE_IMAGES=$(grep -Eo 'image: *"?[^ "]+' "$RENDERED" \
  | sed 's/image: *"*//;s/"$//' \
  | sort -u)
rm -f "$RENDERED"

echo "Checking rendered images against Artifactory (${ARTIFACTORY_URL})..."
MISSING=0
while IFS= read -r img; do
  # Derive internal path: strip public registry prefix
  path_without_registry="${img#*/}"
  # Parse image path and tag
  img_path="${path_without_registry%%:*}"
  img_tag="${path_without_registry##*:}"

  # Query Artifactory Docker v2 API for the manifest
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    -u "$ARTIFACTORY_USER:$ARTIFACTORY_TOKEN" \
    "${ARTIFACTORY_URL}/v2/${DOCKER_REPO}/${img_path}/manifests/${img_tag}")

  if [ "$HTTP_CODE" = "200" ]; then
    printf "  OK   %s/%s:%s\n" "$DOCKER_REPO" "$img_path" "$img_tag"
  else
    printf "  MISS %s/%s:%s (HTTP %s)\n" "$DOCKER_REPO" "$img_path" "$img_tag" "$HTTP_CODE"
    MISSING=$((MISSING + 1))
  fi
done <<< "$UNIQUE_IMAGES"

if [ "$MISSING" -gt 0 ]; then
  echo "ERROR: ${MISSING} image(s) missing from Artifactory."
  exit 1
fi
echo "All rendered images found in Artifactory."
```

> **Tip:** If Docker CLI is available, you can substitute `docker manifest inspect artifactory.example.com/${img_path}:${img_tag}` for the `curl` check. The Artifactory API approach above works without Docker.

**6. ArgoCD applications are healthy:**

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
| 17 | `apps/confluent-operator/dev/values.yaml` | Image registry + pull secret |
| 18 | `apps/confluent-operator/qa/values.yaml` | Image registry + pull secret |
| 19 | `apps/confluent-operator/stg/values.yaml` | Image registry + pull secret |
| 20 | `apps/confluent-operator/prd/values.yaml` | Image registry + pull secret |
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
| | **CI/CD pipelines and scripts** | |
| 33 | `.github/workflows/full-deploy.yaml` | `helm repo add` URLs |
| 34 | `.azure-pipelines/full-deploy.yaml` | `helm repo add` URLs |
| 35 | `scripts/deploy-openshift-dev.sh` | No changes needed (uses ApplicationSets) |
| | **Documentation** | |
| 36 | `README.md` | Update references if needed |

> Total: **~36 files**. The `deploy-operators.yaml` pipelines (GitHub + Azure) do not require changes.

---

## Troubleshooting

### ImagePullBackOff after switching registries

```bash
oc describe pod <pod-name> -n <namespace>
```

Check the Events section for the exact error. Common causes:
- Image pull secret not created in the target namespace (Step 3)
- Image not pushed to internal registry (Step 2)
- Wrong image path in values override (typo in registry or repository)

### Helm chart not found in internal repo

```bash
helm search repo internal/<chart-name>
```

If the chart is missing:
- Verify it was uploaded / proxied correctly
- Run `helm repo update` to refresh the index
- Check that the pinned version (e.g., `1.130.2`) exists in the repository index

### ArgoCD cannot pull Helm chart (authentication error)

ArgoCD needs repository credentials for authenticated Helm repos. See [Step 8](#step-8--configure-argocd-repository-credentials).

Check if the credential secret exists:

```bash
oc get secret -n openshift-gitops -l argocd.argoproj.io/secret-type=repository
```

### Pinned version not found in internal repo

Your internal Helm repository must have the exact chart version uploaded. Ensure the chart `.tgz` was uploaded (Step 1) and the repository index includes it.

```bash
# Verify what's in the repo
helm search repo internal/<chart-name> --versions
```

