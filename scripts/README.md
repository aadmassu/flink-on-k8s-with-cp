# Scripts

This directory contains deployment and teardown scripts for provisioning the **dev** environment on **OpenShift** clusters. The deployment script installs the operator stack -- cert-manager, Confluent Operator (CFK), and Flink Operator -- using ArgoCD ApplicationSet resources managed via GitOps (with the OpenShift GitOps Operator providing ArgoCD). The destroy script reverses that process, deleting ApplicationSets, SCC resources, and namespaces in the correct order.

---

## Table of Contents

- [Script Inventory](#script-inventory)
- [deploy-openshift-dev.sh](#deploy-openshift-devsh)
- [destroy-openshift-dev.sh](#destroy-openshift-devsh)

---

## Script Inventory

| Script | Platform | Action |
|---|---|---|
| `deploy-openshift-dev.sh` | OpenShift | Deploy the dev operator stack |
| `destroy-openshift-dev.sh` | OpenShift | Tear down the dev operator stack |

---

## `deploy-openshift-dev.sh`

### Purpose

Performs a full end-to-end deployment of the **dev** environment on an **OpenShift** cluster. This script does **not** install ArgoCD via Helm. It expects the **OpenShift GitOps Operator** to already be installed (providing ArgoCD in the `openshift-gitops` namespace). The script applies OpenShift-specific prerequisites (SecurityContextConstraints and bindings) directly, then deploys cert-manager, the Confluent Operator (CFK), and the Flink Operator via ArgoCD ApplicationSets.

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
2. **Verify OpenShift GitOps Operator** -- Checks that the ArgoCD server pod is running in the `openshift-gitops` namespace. If not found, prints an error message and exits.
3. **Create and label namespaces** -- Creates (or no-ops if they exist) the `confluent-dev` and `cert-manager` namespaces. Labels each with `argocd.argoproj.io/managed-by=openshift-gitops` so that the OpenShift GitOps ArgoCD instance has permission to manage resources in those namespaces.
4. **Apply OpenShift prerequisites (SCC + bindings)** -- Applies the SCC and ClusterRoleBindings directly via `oc apply -f openshift-prereqs/dev/manifests/`. This is a one-time cluster prerequisite, not managed by ArgoCD.
5. **Deploy cert-manager** -- Checks if cert-manager pods are already running in `cert-manager` or `openshift-cert-manager` namespaces. If running, skips this step. Otherwise, applies the cert-manager ApplicationSet and waits up to 180 seconds for the `cert-manager-dev` Application to become `Healthy`.
6. **Deploy Confluent Operator and Flink Operator** -- Applies both operator ApplicationSets from `gitops-config/openshift/dev/`. Waits up to 180 seconds for both Applications (`confluent-operator-dev` and `confluent-flink-operator-dev`) to become `Healthy`.
7. **Print summary** -- Displays:
   - All ArgoCD Applications in the `openshift-gitops` namespace.
   - Operator pods in the `confluent-dev` namespace.
   - cert-manager pods (falls back to a note about OpenShift-provided cert-manager if the namespace is absent).
   - ArgoCD access information (URL from the OpenShift Route, username, and a command to retrieve the password from the cluster secret).

### GitOps Config Files Referenced

| ApplicationSet Manifest | ArgoCD Application Created |
|---|---|
| `gitops-config/openshift/dev/cert-manager-application-set.yaml` | `cert-manager-dev` |
| `gitops-config/openshift/dev/confluent-operator-application-set.yaml` | `confluent-operator-dev` |
| `gitops-config/openshift/dev/confluent-flink-operator-application-set.yaml` | `confluent-flink-operator-dev` |

---

## `destroy-openshift-dev.sh`

### Purpose

Tears down everything deployed by `deploy-openshift-dev.sh`. Removes all ArgoCD ApplicationSets in reverse order, deletes the SCC resources, and deletes the workload namespaces. It does **not** remove the OpenShift GitOps Operator or the `openshift-gitops` namespace, since those are managed by the OperatorHub subscription and may be shared with other teams.

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
   1. `confluent-flink-operator-dev`
   2. `confluent-operator-dev`
   3. `cert-manager-dev`

   Uses `--ignore-not-found` so the script does not fail if a resource has already been removed. After issuing deletes, waits (up to 120 seconds each) for all three ApplicationSets to be fully removed.
3. **Delete OpenShift prerequisites (SCC + bindings)** -- Deletes the SCC and ClusterRoleBindings directly via `oc delete -f openshift-prereqs/dev/manifests/`.
4. **Delete namespaces** -- Deletes the following namespaces (with `--ignore-not-found` and a 120-second timeout each):
   - `confluent-dev`
   - `cert-manager`

   **Does not** delete the `openshift-gitops` namespace.
5. **Print completion message** -- Displays a teardown-complete banner and a note reminding the user that the OpenShift GitOps Operator and its namespace were intentionally preserved.

### Resources Removed

| Resource Type | Names |
|---|---|
| ApplicationSets | `confluent-flink-operator-dev`, `confluent-operator-dev`, `cert-manager-dev` |
| SCC + ClusterRoleBindings | `confluent-scc`, `confluent-scc-confluent-dev`, `confluent-scc-cert-manager` |
| Namespaces | `confluent-dev`, `cert-manager` |

### Resources Intentionally Preserved

| Resource | Reason |
|---|---|
| `openshift-gitops` namespace | Managed by the OperatorHub subscription; may be shared across teams and environments. |
| OpenShift GitOps Operator | Cluster-scoped operator installed via OperatorHub; removal should be a separate, deliberate action. |
