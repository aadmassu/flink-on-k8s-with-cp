# Azure DevOps Pipelines

Deployment pipelines for Confluent Platform and Flink on OpenShift. Run in order 1-6.

## Pipelines

| # | Pipeline | What it deploys |
|---|----------|-----------------|
| 1 | `1-prereqs.yaml` | Namespaces, SCC, ClusterRoleBindings, license secret |
| 2 | `2-cert-manager.yaml` | cert-manager via Helm |
| 3 | `3-cfk-operator.yaml` | CFK Operator via Helm + webhook TLS certs |
| 4 | `4-flink-operator.yaml` | Flink Kubernetes Operator via Helm |
| 5 | `5-cmf.yaml` | Confluent Manager for Apache Flink via Helm (local chart) |
| 6 | `6-flink-crs.yaml` | Flink CRs via `oc apply` (CMFRestClass, FlinkEnvironment, session cluster) |

## Prerequisites

### Variable Group

All pipelines use the `Openshift-ROSA-VAR-Groups` variable group. Create it in **Pipelines > Library**:

| Variable | Secret | Description |
|---|---|---|
| `OPENSHIFT_SERVER` | No | OpenShift API URL (e.g. `https://api.cluster.example.com:6443`) |
| `OPENSHIFT_TOKEN` | Yes | `oc login` token or service account token |
| `CONFLUENT_LICENSE` | Yes | Confluent license JWT |

### Cluster Requirements

- OpenShift 4.x cluster with `cluster-admin` access
- Helm chart repositories accessible (`charts.jetstack.io`, `packages.confluent.io`)

## Cross-References

| Resource | Path |
|---|---|
| Helm values and overlays | [`apps/`](../apps/) |
| Local Helm charts | [`charts/`](../charts/) |
