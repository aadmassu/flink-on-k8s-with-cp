# Scripts

This directory contains deployment and teardown (destroy) scripts for provisioning the **dev** environment on both vanilla Kubernetes (AWS EKS) and **OpenShift** clusters. Each deployment script installs the full stack -- ArgoCD, cert-manager, Confluent Operator, and Flink Operator -- using ArgoCD ApplicationSet resources managed via GitOps. Each destroy script reverses that process, deleting ApplicationSets, Helm releases, and namespaces in the correct order.

---

## Table of Contents

- [Script Inventory](#script-inventory)
- [deploy-dev.sh](#deploy-devsh)
- [destroy-dev.sh](#destroy-devsh)
- [deploy-openshift-dev.sh](#deploy-openshift-devsh)
- [destroy-openshift-dev.sh](#destroy-openshift-devsh)
- [Comparison: Deploy Scripts](#comparison-deploy-scripts)
- [Comparison: Destroy Scripts](#comparison-destroy-scripts)

---

## Script Inventory

| Script | Platform | Action |
|---|---|---|
| `deploy-dev.sh` | Kubernetes (AWS EKS) | Deploy the full dev stack |
| `destroy-dev.sh` | Kubernetes (AWS EKS) | Tear down the full dev stack |
| `deploy-openshift-dev.sh` | OpenShift | Deploy the full dev stack |
| `destroy-openshift-dev.sh` | OpenShift | Tear down the full dev stack |

---

## `deploy-dev.sh`

### Purpose

Performs a full end-to-end deployment of the **dev** environment on a vanilla Kubernetes cluster (targeting AWS EKS in `us-east-2`). It installs ArgoCD via Helm, then uses ArgoCD ApplicationSet resources to deploy cert-manager, the Confluent Operator, and the Confluent Flink Operator.

### Usage

```bash
./scripts/deploy-dev.sh
```

### Prerequisites

- `kubectl` installed and configured, pointing to the target Kubernetes cluster.
- `helm` 3.14+ or 4.x installed.
- Network connectivity from your workstation to the cluster API server.
- Network connectivity from the cluster to public Helm chart repositories (`argoproj.github.io`, `packages.confluent.io`, `charts.jetstack.io`).

### Configurable Variables

| Key | Default Value | Description |
|---|---|---|
| `SCRIPT_DIR` | *(auto-detected)* | Absolute path to the directory containing this script. Computed at runtime. |
| `REPO_ROOT` | *(auto-detected)* | Absolute path to the repository root (one level above `SCRIPT_DIR`). Computed at runtime. |
| `ENV` | `dev` | Environment name. Used to select the correct values files, ApplicationSet manifests, and namespace suffixes (e.g., `confluent-dev`). |
| `ARGOCD_NS` | `argocd` | Kubernetes namespace where ArgoCD is installed. |

### Step-by-Step Breakdown

1. **Verify cluster connectivity** -- Runs `kubectl cluster-info`. Exits with an error if the cluster is unreachable.
2. **Add Helm repositories** -- Adds three Helm repos (`argo-cd`, `confluent`, `jetstack`) and runs `helm repo update`. Existing repos are silently skipped.
3. **Install or upgrade ArgoCD** -- Checks if the `argocd` Helm release already exists in the `argocd` namespace.
   - If it exists, runs `helm upgrade` with the dev values file (`apps/argocd/dev/values.yaml`).
   - If it does not exist, runs `helm install` (creating the namespace if needed).
   - Waits up to 5 minutes for the Helm release and up to 300 seconds for all ArgoCD pods to become `Ready`.
4. **Deploy cert-manager** -- Applies the cert-manager ApplicationSet from `gitops-config/aws-us-east-2/dev/cert-manager-application-set.yaml`. Waits up to 180 seconds for the ArgoCD Application `cert-manager-dev` to report `Healthy` status.
5. **Deploy Confluent Operator and Flink Operator** -- Applies the Confluent Operator ApplicationSet (`confluent-operator-application-set.yaml`) and the Flink Operator ApplicationSet (`confluent-flink-operator-application-set.yaml`), both from `gitops-config/aws-us-east-2/dev/`. Waits up to 180 seconds for both Applications (`confluent-operator-dev` and `confluent-flink-operator-dev`) to become `Healthy`.
6. **Print summary** -- Displays:
   - All ArgoCD Applications in the `argocd` namespace.
   - Operator pods in the `confluent-dev` namespace.
   - cert-manager pods in the `cert-manager` namespace.
   - ArgoCD access information (URL from LoadBalancer ingress, username, and password).

### GitOps Config Files Referenced

| ApplicationSet Manifest | ArgoCD Application Created |
|---|---|
| `gitops-config/aws-us-east-2/dev/cert-manager-application-set.yaml` | `cert-manager-dev` |
| `gitops-config/aws-us-east-2/dev/confluent-operator-application-set.yaml` | `confluent-operator-dev` |
| `gitops-config/aws-us-east-2/dev/confluent-flink-operator-application-set.yaml` | `confluent-flink-operator-dev` |

---

## `destroy-dev.sh`

### Purpose

Tears down everything deployed by `deploy-dev.sh`. Removes ArgoCD ApplicationSets (which cascade-delete the managed Applications and their child resources), uninstalls the ArgoCD Helm release, and deletes the associated namespaces.

### Usage

```bash
./scripts/destroy-dev.sh
```

### Prerequisites

- `kubectl` installed and configured, pointing to the target Kubernetes cluster.
- `helm` 3.14+ or 4.x installed (required for uninstalling the ArgoCD Helm release).
- Network connectivity from your workstation to the cluster API server.

### Configurable Variables

| Key | Default Value | Description |
|---|---|---|
| `ENV` | `dev` | Environment name. Used to construct ApplicationSet names and namespace names. |
| `ARGOCD_NS` | `argocd` | Kubernetes namespace where ArgoCD is installed. ApplicationSets are deleted from this namespace. |

### Step-by-Step Breakdown

1. **Verify cluster connectivity** -- Runs `kubectl cluster-info`. Exits with an error if the cluster is unreachable.
2. **Delete ArgoCD ApplicationSets** -- Deletes ApplicationSets in reverse order of deployment:
   1. `confluent-flink-operator-dev`
   2. `confluent-operator-dev`
   3. `cert-manager-dev`

   Uses `--ignore-not-found` so the script does not fail if a resource has already been removed. After issuing deletes, waits (up to 120 seconds each) for all three ApplicationSets to be fully removed.
3. **Uninstall ArgoCD Helm release** -- Checks if the `argocd` Helm release exists. If found, runs `helm uninstall` with a 2-minute timeout. If not found, skips gracefully.
4. **Delete namespaces** -- Deletes the following namespaces (with `--ignore-not-found` and a 120-second timeout each):
   - `confluent-dev`
   - `cert-manager`
   - `argocd`
5. **Print completion message** -- Displays a teardown-complete banner.

### Resources Removed

| Resource Type | Names |
|---|---|
| ApplicationSets | `confluent-flink-operator-dev`, `confluent-operator-dev`, `cert-manager-dev` |
| Helm Releases | `argocd` (in `argocd` namespace) |
| Namespaces | `confluent-dev`, `cert-manager`, `argocd` |

---

## `deploy-openshift-dev.sh`

### Purpose

Performs a full end-to-end deployment of the **dev** environment on an **OpenShift** cluster. Unlike the vanilla Kubernetes variant, this script does **not** install ArgoCD via Helm. It expects the **OpenShift GitOps Operator** to already be installed (providing ArgoCD in the `openshift-gitops` namespace). The script deploys OpenShift-specific prerequisites (SecurityContextConstraints and bindings), cert-manager, the Confluent and Flink operators, the Confluent Platform, and Confluent Flink Manager (CMF).

### Usage

```bash
./scripts/deploy-openshift-dev.sh
```

### Prerequisites

- `oc` CLI installed and logged in with **cluster-admin** access.
- **OpenShift GitOps Operator** installed from OperatorHub (ArgoCD must be running in the `openshift-gitops` namespace).
- Network connectivity from your workstation to the OpenShift API server.
- Network connectivity from the cluster to public Helm chart repositories or an internal mirror.

### Configurable Variables

| Key | Default Value | Description |
|---|---|---|
| `SCRIPT_DIR` | *(auto-detected)* | Absolute path to the directory containing this script. Computed at runtime. |
| `REPO_ROOT` | *(auto-detected)* | Absolute path to the repository root (one level above `SCRIPT_DIR`). Computed at runtime. |
| `ENV` | `dev` | Environment name. Used to select the correct ApplicationSet manifests and namespace suffixes. |
| `ARGOCD_NS` | `openshift-gitops` | Namespace where the OpenShift GitOps Operator runs ArgoCD. |

### Step-by-Step Breakdown

1. **Verify cluster connectivity** -- Runs `oc cluster-info`. Exits with an error if the cluster is unreachable.
2. **Verify OpenShift GitOps Operator** -- Checks that the ArgoCD server pod is running in the `openshift-gitops` namespace. If not found, prints an error message referencing `README-OPENSHIFT.md` and exits.
3. **Create and label namespaces** -- Creates (or no-ops if they exist) the `confluent-dev` and `cert-manager` namespaces. Labels each with `argocd.argoproj.io/managed-by=openshift-gitops` so that the OpenShift GitOps ArgoCD instance has permission to manage resources in those namespaces.
4. **Deploy OpenShift prerequisites (SCC + bindings)** -- Applies the `openshift-prereqs-application-set.yaml` ApplicationSet from `gitops-config/openshift/dev/`. Waits up to 120 seconds for the `openshift-prereqs-dev` Application to become `Healthy`. This step creates SecurityContextConstraints and role bindings required by Confluent components on OpenShift.
5. **Deploy cert-manager** -- Checks if cert-manager pods are already running in `cert-manager` or `openshift-cert-manager` namespaces. If running, skips this step. Otherwise, applies the cert-manager ApplicationSet and waits up to 180 seconds for the `cert-manager-dev` Application to become `Healthy`.
6. **Deploy Confluent Operator and Flink Operator** -- Applies both operator ApplicationSets from `gitops-config/openshift/dev/`. Waits up to 180 seconds for both Applications (`confluent-operator-dev` and `confluent-flink-operator-dev`) to become `Healthy`.
7. **Deploy Confluent Platform** -- Applies the Confluent Platform ApplicationSet from `gitops-config/openshift/dev/confluent-platform-application-set.yaml`. Waits up to **600 seconds** (10 minutes) for the `confluent-platform-dev` Application to become `Healthy`. The longer timeout accounts for the time needed to provision brokers, ZooKeeper, Schema Registry, and other Confluent Platform components.
8. **Deploy Confluent Flink Manager (CMF)** -- Applies the Confluent Flink ApplicationSet from `gitops-config/openshift/dev/confluent-flink-application-set.yaml`. Waits up to 300 seconds for the `confluent-flink-dev` Application to become `Healthy`.
9. **Print summary** -- Displays:
   - All ArgoCD Applications in the `openshift-gitops` namespace.
   - Operator pods in the `confluent-dev` namespace.
   - cert-manager pods (falls back to a note about OpenShift-provided cert-manager if the namespace is absent).
   - ArgoCD access information (URL from the OpenShift Route, username, and a command to retrieve the password from the cluster secret).

### GitOps Config Files Referenced

| ApplicationSet Manifest | ArgoCD Application Created |
|---|---|
| `gitops-config/openshift/dev/openshift-prereqs-application-set.yaml` | `openshift-prereqs-dev` |
| `gitops-config/openshift/dev/cert-manager-application-set.yaml` | `cert-manager-dev` |
| `gitops-config/openshift/dev/confluent-operator-application-set.yaml` | `confluent-operator-dev` |
| `gitops-config/openshift/dev/confluent-flink-operator-application-set.yaml` | `confluent-flink-operator-dev` |
| `gitops-config/openshift/dev/confluent-platform-application-set.yaml` | `confluent-platform-dev` |
| `gitops-config/openshift/dev/confluent-flink-application-set.yaml` | `confluent-flink-dev` |

---

## `destroy-openshift-dev.sh`

### Purpose

Tears down everything deployed by `deploy-openshift-dev.sh`. Removes all ArgoCD ApplicationSets in reverse order and deletes the workload namespaces. Notably, it does **not** remove the OpenShift GitOps Operator or the `openshift-gitops` namespace, since those are managed by the OperatorHub subscription and may be shared with other teams.

### Usage

```bash
./scripts/destroy-openshift-dev.sh
```

### Prerequisites

- `oc` CLI installed and logged in with **cluster-admin** access.
- Network connectivity from your workstation to the OpenShift API server.

### Configurable Variables

| Key | Default Value | Description |
|---|---|---|
| `ENV` | `dev` | Environment name. Used to construct ApplicationSet names and namespace names. |
| `ARGOCD_NS` | `openshift-gitops` | Namespace where the OpenShift GitOps Operator runs ArgoCD. ApplicationSets are deleted from this namespace. |

### Step-by-Step Breakdown

1. **Verify cluster connectivity** -- Runs `oc cluster-info`. Exits with an error if the cluster is unreachable.
2. **Delete ArgoCD ApplicationSets** -- Deletes ApplicationSets in reverse order of deployment:
   1. `confluent-flink-dev`
   2. `confluent-platform-dev`
   3. `confluent-flink-operator-dev`
   4. `confluent-operator-dev`
   5. `cert-manager-dev`
   6. `openshift-prereqs-dev`

   Uses `--ignore-not-found` so the script does not fail if a resource has already been removed. After issuing deletes, waits (up to 120 seconds each) for all six ApplicationSets to be fully removed.
3. **Delete namespaces** -- Deletes the following namespaces (with `--ignore-not-found` and a 120-second timeout each):
   - `confluent-dev`
   - `cert-manager`

   **Does not** delete the `openshift-gitops` namespace.
4. **Print completion message** -- Displays a teardown-complete banner and a note reminding the user that the OpenShift GitOps Operator and its namespace were intentionally preserved.

### Resources Removed

| Resource Type | Names |
|---|---|
| ApplicationSets | `confluent-flink-dev`, `confluent-platform-dev`, `confluent-flink-operator-dev`, `confluent-operator-dev`, `cert-manager-dev`, `openshift-prereqs-dev` |
| Namespaces | `confluent-dev`, `cert-manager` |

### Resources Intentionally Preserved

| Resource | Reason |
|---|---|
| `openshift-gitops` namespace | Managed by the OperatorHub subscription; may be shared across teams and environments. |
| OpenShift GitOps Operator | Cluster-scoped operator installed via OperatorHub; removal should be a separate, deliberate action. |

---

## Comparison: Deploy Scripts

The table below compares `deploy-dev.sh` (vanilla Kubernetes / AWS EKS) with `deploy-openshift-dev.sh` (OpenShift).

| Aspect | `deploy-dev.sh` | `deploy-openshift-dev.sh` |
|---|---|---|
| **Target platform** | Vanilla Kubernetes (AWS EKS) | OpenShift |
| **CLI tool** | `kubectl` + `helm` | `oc` (no `helm` required) |
| **ArgoCD installation** | Installs ArgoCD via Helm (`helm install/upgrade`) | Expects OpenShift GitOps Operator pre-installed; verifies it is running |
| **ArgoCD namespace** | `argocd` | `openshift-gitops` |
| **Helm repo setup** | Adds `argo-cd`, `confluent`, `jetstack` repos and runs `helm repo update` | None (no Helm used directly) |
| **Namespace creation** | Handled implicitly by Helm and ApplicationSets | Explicitly creates and labels `confluent-dev` and `cert-manager` with `argocd.argoproj.io/managed-by` |
| **OpenShift prerequisites (SCC)** | Not applicable | Deploys `openshift-prereqs-application-set.yaml` (SecurityContextConstraints + bindings) |
| **cert-manager deployment** | Always deploys via ApplicationSet | Skips if cert-manager is already running (checks `cert-manager` and `openshift-cert-manager` namespaces) |
| **Confluent Platform** | Not deployed | Deployed via `confluent-platform-application-set.yaml` (600s timeout) |
| **Confluent Flink Manager (CMF)** | Not deployed | Deployed via `confluent-flink-application-set.yaml` (300s timeout) |
| **Total ApplicationSets deployed** | 3 (cert-manager, confluent-operator, confluent-flink-operator) | 6 (openshift-prereqs, cert-manager, confluent-operator, confluent-flink-operator, confluent-platform, confluent-flink) |
| **GitOps config path** | `gitops-config/aws-us-east-2/dev/` | `gitops-config/openshift/dev/` |
| **ArgoCD URL retrieval** | From LoadBalancer Service (`kubectl get svc`) | From OpenShift Route (`oc get route`) |
| **ArgoCD password** | Hardcoded in script output | Retrieved via `oc` command from `openshift-gitops-cluster` secret |
| **ArgoCD values file** | `apps/argocd/dev/values.yaml` | Not applicable (operator-managed) |

---

## Comparison: Destroy Scripts

The table below compares `destroy-dev.sh` (vanilla Kubernetes / AWS EKS) with `destroy-openshift-dev.sh` (OpenShift).

| Aspect | `destroy-dev.sh` | `destroy-openshift-dev.sh` |
|---|---|---|
| **Target platform** | Vanilla Kubernetes (AWS EKS) | OpenShift |
| **CLI tool** | `kubectl` + `helm` | `oc` (no `helm` required) |
| **ApplicationSets deleted** | 3 (`confluent-flink-operator-dev`, `confluent-operator-dev`, `cert-manager-dev`) | 6 (`confluent-flink-dev`, `confluent-platform-dev`, `confluent-flink-operator-dev`, `confluent-operator-dev`, `cert-manager-dev`, `openshift-prereqs-dev`) |
| **ArgoCD Helm release** | Uninstalled via `helm uninstall` | Not applicable (operator-managed; not touched) |
| **Namespaces deleted** | `confluent-dev`, `cert-manager`, `argocd` | `confluent-dev`, `cert-manager` |
| **ArgoCD namespace** | **Deleted** (`argocd`) | **Preserved** (`openshift-gitops`) |
| **Post-teardown note** | None | Prints reminder that OpenShift GitOps Operator was intentionally preserved |
| **Idempotency** | Yes -- uses `--ignore-not-found` on all deletes and checks Helm release existence before uninstall | Yes -- uses `--ignore-not-found` on all deletes |
