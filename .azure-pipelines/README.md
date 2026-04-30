# Azure DevOps Pipelines

The pipelines in this folder operate against FCB's on-prem OpenShift, deploying CMF and registering Flink resources against the existing VM Kafka cluster. Each pipeline takes an `environment` parameter (`dev`, `qa`, `uat`, `prd`) and loads the corresponding `<env>-openshift-credentials` variable group.

## Pipelines

| File | Purpose | What it does |
|------|---------|--------------|
| [`verify-flink-setup.yaml`](verify-flink-setup.yaml) | End-to-end health check | Single read-only pipeline that verifies every layer of the stack in `dah-flink-<env>`: CLI tools, OpenShift login, namespace + `flink-operator` SA + RBAC, `keyfactor` ClusterIssuer, `cmf-tls` Certificate + Secret, CMF pod Ready, `cmf-service` on port 443, CMF REST endpoint reachable over HTTPS, Environment / Kafka Catalog / Kafka Database registered. Always finishes with a diagnostic dump (pods / events / secrets / CRDs). Does not deploy anything; for external connectivity tests use `connectivity-test.yaml`. |
| [`connectivity-test.yaml`](connectivity-test.yaml) | Network diagnostics | Pushes busybox to Artifactory, deploys a pod inside `dah-flink-<env>`, and runs DNS + TCP probes against VM Kafka brokers, Schema Registry, REST Proxy, SQL Server, and NetApp S3. |
| [`push-image.yaml`](push-image.yaml) | Image promotion | Push CMF or utility container images from a tarball into FCB Artifactory. |
| [`cmf.yaml`](cmf.yaml) | Install CMF | Helm install of `confluent-manager-for-apache-flink` from the local `charts/` copy. Creates `cmf-db-credentials`, `cmf-encryption-key`, `confluent-license` Secrets from variable-group values, then runs `helm upgrade --install`. |
| [`flink-environments.yaml`](flink-environments.yaml) | CMF REST | Single pipeline that POSTs three CMF resources in order: Flink Environment (`apps/confluent-flink/<env>/environment.yaml`) as upsert, Kafka Catalog (`kafka-catalog.yaml`) and Kafka Database (`kafka-database.yaml`) as create-if-missing. Authored as YAML in Git, converted to JSON in-flight (PyYAML) before posting. |
| [`flink-crs.yaml`](flink-crs.yaml) | CFK-style CRs | Applies CFK-based Flink CRs (`CMFRestClass`, `FlinkEnvironment`, etc.). **Template only** — FCB doesn't run CFK today; not used until/unless that changes. |

## Variable group: `<env>-openshift-credentials`

Each environment has a variable group with this naming pattern. All pipelines reference variables generically (`$(openshift-dev-api)`, `$(openshift-service-account-name)`, `$(<env>-cmf-sql-server-jdbc-url)`, etc.) so changing the `environment` parameter swaps the entire backing variable set.

### Cluster + namespace

| Name | Type | Example |
|------|------|---------|
| `openshift-dev-api` | string | `https://api.dv-p.ocp.fcbint.net:6443` (per-env value) |
| `openshift-dev-namespace` | string | `dah-flink-dev` (per-env value) |
| `openshift-service-account-name` | string | per-env service account |
| `openshift-service-account-pwd` | secret | service account password |

### Artifactory

| Name | Type |
|------|------|
| `artifactory-svc-user` | string |
| `artifactory-svc-user-password` | secret |

### CMF + downstream (env-prefixed)

| Name | Type |
|------|------|
| `<env>-cmf-sql-server-jdbc-url` | string |
| `<env>-cmf-sql-server-user` | string |
| `<env>-cmf-sql-server-user-password` | secret |
| `<env>-cmf-encryption-key` | secret — AES-GCM, **never rotate** |
| `<env>-confluent-license` | secret (locked) |
| `<env>-kafka-broker-hosts` | string — comma-separated |
| `<env>-kafka-rest-proxy-hosts` | string — comma-separated |
| `<env>-schema-registry-hosts` | string — comma-separated |
| `<env>-net-app-s3-url` | string |

## Templates

| File | Purpose |
|------|---------|
| [`templates/install-tools.yaml`](templates/install-tools.yaml) | Downloads `oc`, `helm`, `kubectl` from Artifactory and prepends them to `PATH`. Imported by every pipeline. |

## Run order

> **`cmf-tls` MUST run before `cmf`.** The `cmf` pipeline has a pre-flight check for `secret/cmf-tls` and aborts if it's missing. The Helm install never runs in that case — no harm done, but the cutover doesn't progress until `cmf-tls` completes successfully.

First-time-per-env order:

1. `connectivity-test` — confirm cluster can reach Kafka / SR / SQL Server / NetApp S3.
2. **`cmf-tls`** — applies the cert-manager `Certificate`, waits up to 10 minutes for Keyfactor approval, produces `secret/cmf-tls` with `tls.crt` + `tls.key` + `ca.crt`.
3. `cmf` — Helm-installs CMF (mounts `cmf-tls`, serves HTTPS on `cmf-service:443`).
4. `flink-environments` — registers the Flink environment, Kafka catalog, and Kafka database via CMF's REST API.
5. `verify-flink-setup` — end-to-end read-only health check; summary table confirms every layer is green.

`flink-environments` is idempotent (environment is upsert; catalog/database are create-if-missing) — re-running is safe. `cmf-tls` is bootstrap-once per env; cert-manager handles renewal silently after that.

## Cross-references

| Resource | Path |
|---|---|
| Helm values, manifests | [`apps/`](../apps/) |
| Vendored CMF chart | [`charts/confluent-manager-for-apache-flink/`](../charts/confluent-manager-for-apache-flink/) |
| FCB pre-created RBAC | [`openshift-prereqs/`](../openshift-prereqs/) |
