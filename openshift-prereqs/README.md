# OpenShift Prerequisites: Security Context Constraints & Bindings

## Overview

This directory contains the OpenShift-specific prerequisites required before deploying Confluent Platform and Apache Flink on an OpenShift cluster. Specifically, it manages:

- **Security Context Constraints (SCCs):** A custom `confluent-scc` SCC that defines the pod security profile under which Confluent Platform, Flink Operator, and cert-manager workloads are permitted to run.
- **ClusterRoleBindings:** RBAC bindings that grant the `confluent-scc` SCC to the relevant service accounts in each environment namespace, as well as to cert-manager service accounts in the shared `cert-manager` namespace.

OpenShift enforces SCCs as the mechanism to control pod privileges (analogous to Kubernetes Pod Security Standards). Without these resources, Confluent Platform pods, Flink Operator pods, and cert-manager pods will fail to schedule due to SCC admission violations.

These manifests are organized per environment (`dev`, `qa`, `stg`, `prd`) and are applied directly via `oc apply` as a **one-time cluster prerequisite** before deploying any ArgoCD-managed applications. They are not managed by ArgoCD.

---

## Directory Structure

```
openshift-prereqs/
├── README.md                          # This file
├── dev/
│   └── manifests/
│       ├── confluent-scc.yaml         # SCC definition for dev
│       └── scc-bindings.yaml          # ClusterRoleBindings for dev
├── qa/
│   └── manifests/
│       ├── confluent-scc.yaml         # SCC definition for qa
│       └── scc-bindings.yaml          # ClusterRoleBindings for qa
├── stg/
│   └── manifests/
│       ├── confluent-scc.yaml         # SCC definition for stg
│       └── scc-bindings.yaml          # ClusterRoleBindings for stg
└── prd/
    └── manifests/
        ├── confluent-scc.yaml         # SCC definition for prd
        └── scc-bindings.yaml          # ClusterRoleBindings for prd
```

---

## Manifest Details

### 1. `confluent-scc.yaml` -- Security Context Constraints

**Purpose:** Defines a custom OpenShift SecurityContextConstraints resource named `confluent-scc`. This SCC is intentionally restrictive -- it drops all Linux capabilities, disables privileged containers, blocks host-level access (network, PID, IPC, ports, host directories), and allows only a curated set of volume types. The `RunAsAny` strategies for user, SELinux, fsGroup, and supplemental groups provide the flexibility Confluent Platform and Flink components need to run as their required UIDs without being locked to OpenShift's default restricted UID ranges.

> **Note:** The `confluent-scc.yaml` file is **identical** across all four environments (dev, qa, stg, prd). The SCC is a cluster-scoped resource and uses the same name (`confluent-scc`) in every environment.

#### Full Field Reference

| Key | Value | Description |
|-----|-------|-------------|
| `apiVersion` | `security.openshift.io/v1` | OpenShift API group and version for SecurityContextConstraints resources. |
| `kind` | `SecurityContextConstraints` | The Kubernetes resource kind. SCCs are cluster-scoped (not namespaced). |
| `metadata.name` | `confluent-scc` | The unique name of this SCC within the cluster. Referenced by ClusterRole `system:openshift:scc:confluent-scc`. |
| `metadata.annotations.argocd.argoproj.io/sync-wave` | `"0"` | Argo CD sync-wave annotation. Wave `0` ensures this SCC is created **before** the ClusterRoleBindings (wave `1`) that reference it. |
| `allowPrivilegedContainer` | `false` | Prevents pods from running in privileged mode (full host access). |
| `allowHostDirVolumePlugin` | `false` | Prevents pods from mounting host filesystem directories as volumes (`hostPath`). |
| `allowHostIPC` | `false` | Prevents pods from using the host's IPC namespace (inter-process communication). |
| `allowHostNetwork` | `false` | Prevents pods from using the host's network namespace (sharing the host IP and ports). |
| `allowHostPID` | `false` | Prevents pods from using the host's PID namespace (visibility into host processes). |
| `allowHostPorts` | `false` | Prevents pods from binding to host ports via `hostPort` in container specs. |
| `readOnlyRootFilesystem` | `false` | Does **not** force a read-only root filesystem. Pods are allowed to write to their root filesystem. Confluent components require writable root filesystems for temp files and logs. |
| `runAsUser.type` | `RunAsAny` | No restrictions on the UID a container can run as. Allows Confluent and Flink containers to run as their required non-root UIDs (e.g., `appuser` UID 1000) without being forced into OpenShift's allocated UID range. |
| `seLinuxContext.type` | `RunAsAny` | No restrictions on the SELinux context. Pods may run with any SELinux label. |
| `fsGroup.type` | `RunAsAny` | No restrictions on the filesystem group ID. Allows pods to set any `fsGroup` for volume ownership. |
| `supplementalGroups.type` | `RunAsAny` | No restrictions on supplemental group IDs. Pods may specify arbitrary supplemental groups. |
| `requiredDropCapabilities` | `[ALL]` | **All** Linux capabilities are dropped from every container by default. This is the most restrictive capability setting -- containers start with zero capabilities. |
| `volumes` | *(list, see below)* | Whitelist of allowed volume types. Only the following six volume plugins are permitted: |
| `volumes[0]` | `configMap` | Allows mounting ConfigMap volumes. |
| `volumes[1]` | `downwardAPI` | Allows mounting Downward API volumes (pod metadata injection). |
| `volumes[2]` | `emptyDir` | Allows mounting emptyDir volumes (ephemeral scratch space). |
| `volumes[3]` | `persistentVolumeClaim` | Allows mounting PersistentVolumeClaim volumes (persistent storage for Kafka, ZooKeeper, etc.). |
| `volumes[4]` | `projected` | Allows mounting projected volumes (composite of secrets, configmaps, downward API, and service account tokens). |
| `volumes[5]` | `secret` | Allows mounting Secret volumes (TLS certificates, credentials, etc.). |

---

### 2. `scc-bindings.yaml` -- ClusterRoleBindings

**Purpose:** Each `scc-bindings.yaml` file contains **two** ClusterRoleBinding resources that grant the `confluent-scc` SCC to the service accounts that need it. OpenShift automatically creates a ClusterRole named `system:openshift:scc:<scc-name>` for every SCC, so these bindings reference `system:openshift:scc:confluent-scc`.

#### Resource 1: Environment-Specific Confluent Binding

This binding grants the SCC to the three service accounts in the environment's Confluent namespace.

| Key | Value (dev) | Value (qa) | Value (stg) | Value (prd) | Description |
|-----|-------------|------------|-------------|-------------|-------------|
| `apiVersion` | `rbac.authorization.k8s.io/v1` | `rbac.authorization.k8s.io/v1` | `rbac.authorization.k8s.io/v1` | `rbac.authorization.k8s.io/v1` | Standard Kubernetes RBAC API version. |
| `kind` | `ClusterRoleBinding` | `ClusterRoleBinding` | `ClusterRoleBinding` | `ClusterRoleBinding` | Cluster-scoped RBAC binding (not namespaced). |
| `metadata.name` | `confluent-scc-confluent-dev` | `confluent-scc-confluent-qa` | `confluent-scc-confluent-stg` | `confluent-scc-confluent-prd` | Unique binding name. Follows the pattern `confluent-scc-confluent-<env>`. |
| `metadata.annotations.argocd.argoproj.io/sync-wave` | `"1"` | `"1"` | `"1"` | `"1"` | Argo CD sync-wave. Wave `1` ensures this binding is created **after** the SCC (wave `0`). |
| `roleRef.apiGroup` | `rbac.authorization.k8s.io` | `rbac.authorization.k8s.io` | `rbac.authorization.k8s.io` | `rbac.authorization.k8s.io` | API group for the referenced ClusterRole. |
| `roleRef.kind` | `ClusterRole` | `ClusterRole` | `ClusterRole` | `ClusterRole` | The type of RBAC role being referenced. |
| `roleRef.name` | `system:openshift:scc:confluent-scc` | `system:openshift:scc:confluent-scc` | `system:openshift:scc:confluent-scc` | `system:openshift:scc:confluent-scc` | Auto-generated ClusterRole that grants `use` verb on the `confluent-scc` SCC. |
| `subjects[0].kind` | `ServiceAccount` | `ServiceAccount` | `ServiceAccount` | `ServiceAccount` | The default service account in the Confluent namespace. Used by pods that don't specify a custom SA. |
| `subjects[0].name` | `default` | `default` | `default` | `default` | Service account name. |
| `subjects[0].namespace` | `confluent-dev` | `confluent-qa` | `confluent-stg` | `confluent-prd` | Target namespace for this environment. |
| `subjects[1].kind` | `ServiceAccount` | `ServiceAccount` | `ServiceAccount` | `ServiceAccount` | The Confluent for Kubernetes (CFK) operator service account. |
| `subjects[1].name` | `confluent-operator` | `confluent-operator` | `confluent-operator` | `confluent-operator` | Service account name for the CFK operator. |
| `subjects[1].namespace` | `confluent-dev` | `confluent-qa` | `confluent-stg` | `confluent-prd` | Target namespace for this environment. |
| `subjects[2].kind` | `ServiceAccount` | `ServiceAccount` | `ServiceAccount` | `ServiceAccount` | The Flink Kubernetes Operator service account. |
| `subjects[2].name` | `flink-kubernetes-operator` | `flink-kubernetes-operator` | `flink-kubernetes-operator` | `flink-kubernetes-operator` | Service account name for the Flink operator. |
| `subjects[2].namespace` | `confluent-dev` | `confluent-qa` | `confluent-stg` | `confluent-prd` | Target namespace for this environment. |

#### Resource 2: Cert-Manager Binding (Shared)

This binding grants the SCC to cert-manager service accounts in the `cert-manager` namespace. It is **identical** across all environments.

| Key | Value | Description |
|-----|-------|-------------|
| `apiVersion` | `rbac.authorization.k8s.io/v1` | Standard Kubernetes RBAC API version. |
| `kind` | `ClusterRoleBinding` | Cluster-scoped RBAC binding. |
| `metadata.name` | `confluent-scc-cert-manager` | Binding name. Same across all environments since it targets the shared `cert-manager` namespace. |
| `metadata.annotations.argocd.argoproj.io/sync-wave` | `"1"` | Argo CD sync-wave. Wave `1` ensures this is created after the SCC (wave `0`). |
| `roleRef.apiGroup` | `rbac.authorization.k8s.io` | API group for the referenced ClusterRole. |
| `roleRef.kind` | `ClusterRole` | The type of RBAC role being referenced. |
| `roleRef.name` | `system:openshift:scc:confluent-scc` | Auto-generated ClusterRole that grants `use` verb on the `confluent-scc` SCC. |
| `subjects[0].kind` | `ServiceAccount` | The core cert-manager controller service account. |
| `subjects[0].name` | `cert-manager` | Service account name. |
| `subjects[0].namespace` | `cert-manager` | The cert-manager namespace (shared across all environments). |
| `subjects[1].kind` | `ServiceAccount` | The cert-manager webhook service account. |
| `subjects[1].name` | `cert-manager-webhook` | Service account name. |
| `subjects[1].namespace` | `cert-manager` | The cert-manager namespace. |
| `subjects[2].kind` | `ServiceAccount` | The cert-manager CA injector service account. |
| `subjects[2].name` | `cert-manager-cainjector` | Service account name. |
| `subjects[2].namespace` | `cert-manager` | The cert-manager namespace. |

---

## Per-Environment Differences

The `confluent-scc.yaml` file is identical across all environments. The `scc-bindings.yaml` file contains two ClusterRoleBindings; the cert-manager binding is identical everywhere, while the Confluent/Flink binding varies only in the fields shown below.

| Field | dev | qa | stg | prd |
|-------|-----|----|-----|-----|
| **ClusterRoleBinding name** (Confluent) | `confluent-scc-confluent-dev` | `confluent-scc-confluent-qa` | `confluent-scc-confluent-stg` | `confluent-scc-confluent-prd` |
| **subjects[*].namespace** (Confluent) | `confluent-dev` | `confluent-qa` | `confluent-stg` | `confluent-prd` |

All other fields -- including the SCC definition, the cert-manager ClusterRoleBinding, role references, service account names, sync-wave annotations, and security policies -- are **identical** across all four environments.

### Summary of Service Accounts Per Environment

| Service Account | Namespace | Purpose |
|-----------------|-----------|---------|
| `default` | `confluent-<env>` | Default SA used by Confluent Platform component pods (Kafka, ZooKeeper, Schema Registry, etc.) that do not specify a dedicated service account. |
| `confluent-operator` | `confluent-<env>` | SA for the Confluent for Kubernetes (CFK) operator, which manages the lifecycle of Confluent Platform components. |
| `flink-kubernetes-operator` | `confluent-<env>` | SA for the Apache Flink Kubernetes Operator, which manages Flink job deployments and session clusters. |
| `cert-manager` | `cert-manager` | SA for the core cert-manager controller that issues and renews TLS certificates. |
| `cert-manager-webhook` | `cert-manager` | SA for the cert-manager webhook server that validates and mutates cert-manager CRDs. |
| `cert-manager-cainjector` | `cert-manager` | SA for the cert-manager CA injector that injects CA bundles into webhook configurations and CRDs. |

---

## Usage

Apply the prerequisites for your target environment before deploying any ArgoCD applications:

```bash
# Replace <env> with dev, qa, stg, or prd
oc apply -f openshift-prereqs/<env>/manifests/
```

Verify:

```bash
oc get scc confluent-scc
oc get clusterrolebinding | grep confluent-scc
```

The SCC manifest (`confluent-scc.yaml`) should be applied before the bindings (`scc-bindings.yaml`). When applied together via `oc apply -f <directory>/`, Kubernetes processes them in alphabetical order, and the sync-wave annotations (wave `0` for SCC, wave `1` for bindings) provide ordering guidance for tools that respect them.

> **Important:** These prerequisites must be applied before deploying any Confluent Platform, Flink Operator, or cert-manager workloads. They are a one-time cluster setup and are **not** managed by ArgoCD.
