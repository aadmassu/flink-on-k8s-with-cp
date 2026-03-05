# Scripts

This directory contains deployment, teardown, and verification scripts for the **dev** environment on **OpenShift** clusters. The deployment script installs the full Phase-I and Phase-II stack -- operators, CMF, local Kafka, and Flink infrastructure -- using ArgoCD ApplicationSet resources managed via OpenShift GitOps.

---

## Table of Contents

- [Script Inventory](#script-inventory)
- [deploy-openshift-dev.sh](#deploy-openshift-devsh)
- [destroy-openshift-dev.sh](#destroy-openshift-devsh)
- [verify-openshift-dev.sh](#verify-openshift-devsh)

---

## Script Inventory

| Script | Platform | Action |
|---|---|---|
| `deploy-openshift-dev.sh` | OpenShift | Full deploy: Phase-I operators + Phase-II (CMF, CP, Flink) |
| `destroy-openshift-dev.sh` | OpenShift | Full teardown in reverse order |
| `verify-openshift-dev.sh` | OpenShift | Health checks for all components |
| `discover-charts-and-images.sh` | Any | Image/chart discovery for air-gapped mirroring |
| `validate-resolvable-versions.sh` | Any | Validate pinned chart versions resolve |

---

## `deploy-openshift-dev.sh`

### Purpose

Performs a full end-to-end deployment of the **dev** environment on an **OpenShift** cluster. Expects the **OpenShift GitOps Operator** to already be installed. Applies OpenShift prerequisites (SCC + bindings), deploys Phase-I operators, then Phase-II components with retry loops for CRD and CR readiness.

### Usage

```bash
# Optional: set repo credentials for ArgoCD
export ARGOCD_SSH_KEY=$(cat ~/.ssh/id_rsa)

./scripts/deploy-openshift-dev.sh
```

### Prerequisites

- `oc` CLI installed and logged in with **cluster-admin** access
- **OpenShift GitOps Operator** installed from OperatorHub
- Network connectivity to Helm chart repositories (or internal mirror)

### Step-by-Step Breakdown

**Phase-I:**

1. **Verify cluster connectivity** -- `oc cluster-info`
2. **Verify OpenShift GitOps Operator** -- Checks ArgoCD server pod in `openshift-gitops`
3. **Configure ArgoCD repo credentials** -- Applies `argocd-repo-secret.yaml` via envsubst (skips if `ARGOCD_SSH_KEY` not set)
4. **Create and label namespaces** -- `confluent-dev`, `cert-manager` with managed-by label
5. **Apply OpenShift prerequisites** -- SCC + ClusterRoleBindings
6. **Deploy cert-manager** -- Skips if already running; waits for Healthy, retries CRD registration
7. **Deploy operators** -- CFK + FKO in parallel, waits for Healthy

**Phase-II:**

8. **Deploy CMF** -- Helm via ArgoCD, waits for Healthy
9. **Deploy Confluent Platform** -- Local Kafka CRDs, waits for Synced + Healthy, then retries Kafka CR readiness until RUNNING
10. **Deploy Flink infrastructure** -- CMFRestClass, FlinkEnvironment, PVC, session cluster; retries FlinkDeployment until READY
11. **Print summary** -- Applications, pods, ArgoCD access info

---

## `destroy-openshift-dev.sh`

### Purpose

Tears down everything deployed by `deploy-openshift-dev.sh`. Removes ApplicationSets in reverse order, clears finalizers from stuck CFK/Flink CRs and ArgoCD Applications, deletes SCC resources, and deletes namespaces. Does **not** remove the OpenShift GitOps Operator.

### Usage

```bash
./scripts/destroy-openshift-dev.sh
```

### Step-by-Step Breakdown

1. **Delete Phase-II ApplicationSets** -- confluent-flink, confluent-platform, confluent-cmf
2. **Delete Phase-I ApplicationSets** -- flink-operator, confluent-operator, cert-manager
3. **Clear finalizers** -- Patches `metadata.finalizers: null` on stuck CFK/Flink CRs
4. **Clear ArgoCD Application finalizers** -- Prevents stuck Application deletions
5. **Delete OpenShift prerequisites** -- SCC + ClusterRoleBindings
6. **Delete namespaces** -- `confluent-dev`, `cert-manager` (preserves `openshift-gitops`)

---

## `verify-openshift-dev.sh`

### Purpose

Runs health checks on all Phase-I and Phase-II components. Returns exit code 0 if all checks pass, or the number of failures.

### Usage

```bash
./scripts/verify-openshift-dev.sh
```

### Checks Performed

1. **Cluster connectivity** -- `oc cluster-info`
2. **ArgoCD Applications** -- Checks Health=Healthy and Sync=Synced for all 6 apps:
   - `cert-manager-dev`
   - `confluent-operator-dev`
   - `confluent-flink-operator-dev`
   - `confluent-cmf-dev`
   - `confluent-platform-dev`
   - `confluent-flink-dev`
3. **CMF pod** -- Running pod with CMF label
4. **Kafka status** -- `kafka/kafka` resource phase = RUNNING
5. **Confluent Platform pods** -- All pods in confluent-dev are Running
6. **Flink infrastructure CRs** -- CMFRestClass, FlinkEnvironment, PVC exist
7. **Flink session cluster** -- FlinkDeployment `flink-session` status = READY
8. **cert-manager pods** -- Running in cert-manager or openshift-cert-manager namespace
