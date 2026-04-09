# OpenShift Prerequisites — dev

Cluster-scoped and namespace-scoped resources that must be applied by the OpenShift platform team before running the Confluent Flink pipelines.

## Manifests

| File | Scope | Description |
|------|-------|-------------|
| `confluent-scc.yaml` | Cluster | SecurityContextConstraints for Confluent workloads (relaxed `RunAsAny` for UID/GID/SELinux, drops all capabilities) |
| `scc-bindings.yaml` | Cluster | ClusterRoleBindings granting the SCC to service accounts in `dah-kafka-dev` and `dah-flink-dev` |
| `cmf-rbac.yaml` | Namespace (`dah-flink-dev`) | ServiceAccount, Role, and RoleBinding for CMF to manage Flink resources at runtime |

## Apply order

1. `confluent-scc.yaml` — SCC must exist before bindings reference it
2. `scc-bindings.yaml` — grants the SCC to the relevant service accounts
3. `cmf-rbac.yaml` — creates the CMF service account and permissions

## Notes

- These are **platform team responsibilities** — the pipeline service account (`dv_db_dah_azdo-svc`) does not have permission to create these resources.
- The CMF Helm chart is installed with `rbac: false` and `serviceAccount.create: false`, expecting the SA and Role from `cmf-rbac.yaml` to already exist.
- For other environments (qa, stg, prd), replicate these manifests with updated namespace names.
