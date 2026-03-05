# Confluent Manager for Apache Flink (CMF)

Helm values for the **CMF** chart, deployed via ArgoCD as a multi-source Helm ApplicationSet.

---

## Helm Chart

| Field | Value |
|-------|-------|
| **Chart** | `confluent-manager-for-apache-flink` |
| **Repository** | `https://packages.confluent.io/helm` |
| **Version** | 2.2.0 |

---

## Directory Structure

```
apps/confluent-cmf/
├── README.md
├── openshift-overlay.yaml    # OpenShift: null podSecurityContext (SCC assigns UIDs)
├── dev/values.yaml           # Dev: sql.production=false, low resources
├── qa/values.yaml
├── stg/values.yaml
└── prd/values.yaml
```

---

## Key Configuration

### openshift-overlay.yaml

Nullifies `podSecurityContext` fields to allow OpenShift SCCs to assign UIDs and GIDs:

```yaml
podSecurityContext:
  runAsUser: null
  runAsGroup: null
  fsGroup: null
```

### Per-Environment Values

| Key | Dev | Description |
|-----|-----|-------------|
| `cmf.sql.production` | `false` | Disables production-mode SQL guardrails |
| `resources.requests.cpu` | `100m` | CPU request |
| `resources.requests.memory` | `256Mi` | Memory request |
| `resources.limits.cpu` | `500m` | CPU limit |
| `resources.limits.memory` | `512Mi` | Memory limit |

> **Note:** On OpenShift, no `storageClassName` is set — the cluster default storage class is used.

---

## Dependencies

- **Flink Kubernetes Operator** must be running (CMF creates FlinkDeployment CRs)
- **CFK operator** must be running with `enableCMFDay2Ops: true` (provides CMFRestClass/FlinkEnvironment CRDs)

---

## Cross-References

| Resource | Path |
|----------|------|
| ApplicationSet | [`gitops-config/openshift/dev/confluent-cmf-application-set.yaml`](../../gitops-config/openshift/dev/confluent-cmf-application-set.yaml) |
| Flink infra CRs | [`apps/confluent-flink/`](../confluent-flink/) |
| Phase-II guide | [`README-PHASE-II.md`](../../README-PHASE-II.md) |
