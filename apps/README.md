# Apps — Application Source Definitions

This directory contains all Helm values, Kustomize overlays, and raw Kubernetes manifests consumed by the ArgoCD ApplicationSets in [`gitops-config/`](../gitops-config/).

---

## Directory Overview

| Directory | Type | Phase | Description |
|-----------|------|-------|-------------|
| [`argocd/`](argocd/) | Helm values | Bootstrap | ArgoCD Helm values and self-management Application manifests |
| [`cert-manager/`](cert-manager/) | Helm values | Phase-I | cert-manager Helm values with OpenShift overlay |
| [`confluent-operator/`](confluent-operator/) | Helm values | Phase-I | CFK (Confluent for Kubernetes) operator Helm values with OpenShift overlay |
| [`confluent-flink-operator/`](confluent-flink-operator/) | Helm values | Phase-I | Flink Kubernetes Operator Helm values with OpenShift overlay |
| [`confluent-cmf/`](confluent-cmf/) | Helm values | Phase-II | Confluent Manager for Apache Flink (CMF) Helm values with OpenShift overlay |
| [`confluent-platform/`](confluent-platform/) | Kustomize | Phase-II | Confluent Platform CRDs (KRaft, Kafka, SR, Connect, C3) via CFK |
| [`confluent-flink/`](confluent-flink/) | Kustomize | Phase-II | Flink infrastructure CRs (CMFRestClass, FlinkEnvironment, session cluster, PVC) |

---

## Patterns

### Helm-based apps (ArgoCD, cert-manager, operators, CMF)

Each Helm-based app follows this structure:

```
apps/<component>/
├── dev/values.yaml            # Per-environment Helm overrides
├── qa/values.yaml
├── stg/values.yaml
├── prd/values.yaml
└── openshift-overlay.yaml     # Platform-specific overrides (null security contexts for SCC)
```

ArgoCD ApplicationSets use **multi-source Helm** — one source for the chart, one Git ref for `valueFiles`. The OpenShift overlay is layered on top of the per-environment values to nullify `podSecurityContext` fields, allowing OpenShift SCCs to assign UIDs.

### Kustomize-based apps (Confluent Platform, Flink CRs)

Each Kustomize-based app follows this structure:

```
apps/<component>/
├── base/                 # Base manifests (namespace-agnostic)
│   ├── kustomization.yaml
│   └── *.yaml
├── dev/kustomization.yaml    # Overlay — sets namespace, patches endpoints
├── qa/kustomization.yaml
├── stg/kustomization.yaml
└── prd/kustomization.yaml
```

ArgoCD ApplicationSets use **Git directory** source, pointing at the per-environment overlay directory. ArgoCD auto-detects Kustomize and runs `kustomize build`.

---

## Cross-References

| Resource | Path |
|----------|------|
| ArgoCD ApplicationSets | [`gitops-config/`](../gitops-config/) |
| OpenShift prerequisites (SCCs) | [`openshift-prereqs/`](../openshift-prereqs/) |
| Deploy script | [`scripts/deploy-openshift-dev.sh`](../scripts/deploy-openshift-dev.sh) |
| Phase-I guide | [`PHASE-I.md`](../docs/PHASE-I.md) |
| Phase-II guide | [`PHASE-II.md`](../docs/PHASE-II.md) |
