# Documentation

Supplementary documentation, decision records, and planning artifacts for the Flink-on-K8s deployment.

---

## Contents

| Path | Description |
|------|-------------|
| [`decisions/`](decisions/) | Architecture Decision Records (ADRs) and configuration checklists |

---

## Guides

| File | Description |
|------|-------------|
| [`README.md`](../README.md) | Project overview, repository structure, prerequisites |
| [`PHASE-I.md`](PHASE-I.md) | Phase-I deployment guide (operators) |
| [`PHASE-II.md`](PHASE-II.md) | Phase-II deployment guide (CMF + local Kafka + Flink) |
| [`INTERNAL-REGISTRY.md`](INTERNAL-REGISTRY.md) | Air-gapped / internal registry integration guide |
| [`EXISTING-ARGOCD.md`](EXISTING-ARGOCD.md) | Deploying into an existing ArgoCD installation |
| [`CHEATSHEET.md`](CHEATSHEET.md) | Diagnostic and troubleshooting commands |
| [`flink-cluster-modes.md`](flink-cluster-modes.md) | Flink session vs application cluster architecture |
| [`HELM-VALUES.md`](HELM-VALUES.md) | Helm values reference for CFK and Flink operators |
