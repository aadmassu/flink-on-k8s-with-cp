# Azure DevOps Pipelines

The pipelines in this folder operate against FCB's on-prem OpenShift, deploying CMF and registering Flink resources against the existing VM Kafka cluster. Each pipeline takes an `environment` parameter (`dev`, `qa`, `uat`, `prd`) and loads the corresponding `<env>-openshift-credentials` variable group.

## Pipelines

| File | Purpose | What it does |
|------|---------|--------------|
| [`verify-flink-setup.yaml`](verify-flink-setup.yaml) | End-to-end health check | Single read-only pipeline that verifies every layer of the stack in `dah-flink-<env>`: CLI tools, OpenShift login, namespace + `flink-operator` SA + RBAC, `keyfactor` ClusterIssuer, `cmf-tls` Certificate + Secret, CMF pod Ready, `cmf-service` on port 443, CMF REST endpoint reachable over HTTPS, Environment / Kafka Catalog / Kafka Database registered. Always finishes with a diagnostic dump (pods / events / secrets / CRDs). Does not deploy anything; for external connectivity tests use `connectivity-test.yaml`. |
| [`connectivity-test.yaml`](connectivity-test.yaml) | Network diagnostics | Pushes busybox to Artifactory, deploys a pod inside `dah-flink-<env>`, and runs DNS + TCP probes against VM Kafka brokers, Schema Registry, REST Proxy, SQL Server, and NetApp S3. |
| [`push-image.yaml`](push-image.yaml) | Image promotion | Push CMF or utility container images from a tarball into FCB Artifactory. Targets either `camdepositsharedservices-docker-dev` (selected via `artifactoryRepo: nonprod` — consumed by dev / qa / uat) or `camdepositsharedservices-docker-prod` (`artifactoryRepo: prd` — consumed by prd). |
| [`cmf.yaml`](cmf.yaml) | Install CMF | Helm install of `confluent-manager-for-apache-flink` from the local `charts/` copy. Creates `cmf-db-credentials`, `cmf-encryption-key`, `confluent-license` Secrets from variable-group values, then runs `helm upgrade --install`. |
| [`flink-environments.yaml`](flink-environments.yaml) | CMF REST | Single pipeline that POSTs three CMF resources in order: Flink Environment (`apps/confluent-flink/<env>/environment.json`) as upsert, Kafka Catalog (`kafka-catalog.json`) and Kafka Database (`kafka-database.json`) as create-if-missing. Authored as JSON and POSTed verbatim — no YAML conversion. Pre-flight aborts if any `REPLACE_WITH_*` placeholder is still present. |
| [`confluent-platform.yaml`](confluent-platform.yaml) | Manage CFK CP (`action: create-prereqs \| install \| uninstall`) | **`create-prereqs`** creates 11 Opaque Secrets (license, MDS keypair, SASL PLAIN, 6 OAuth client creds, 2 C3 basic-auth) from variable-group values and `oc describe`s each — values never appear in the log. **`install`** applies the cert-manager `Certificate` CRs under `apps/confluent-platform/<env>/prereqs/`, waits for the six `*-tls` Secrets, then applies the CFK CRs in dependency order (KafkaRestClass → KRaftController → Kafka → SR → Connect → REST → C3). Install pre-flight aborts if any of the 11 prereq Secrets is missing or any `REPLACE_WITH_*` marker remains. **`uninstall`** deletes CRs in reverse dependency order and the Certificates (cascading the `*-tls` Secrets); preserves the prereq Opaque Secrets and PVCs. |

> **Flink applications (`FlinkApplication` CRs) are not deployed from this repo.** Each Flink job ships from its own repo (job source code, container image build, deploy manifests, and CI/CD pipeline). This repo provisions the platform — CMF, the Flink Environment, and the Kafka Catalog/Database — that those job pipelines deploy into. The first such job is `aep-rate-limit-job`.

## Variable group: `<env>-openshift-credentials`

Each environment has a variable group with this naming pattern. All pipelines reference variables generically (`$(openshift-dev-api)`, `$(openshift-service-account-name)`, `$(<env>-cmf-sql-server-jdbc-url)`, etc.) so changing the `environment` parameter swaps the entire backing variable set.

### Cluster + namespace

> **Note on secret-type variables:** every entry marked `secret` below is **temporary, pipeline-managed**. These values will move out of Azure DevOps variable groups and into the **CyberArk** vault, sourced into the cluster as Kubernetes Secrets via the External Secrets Operator (ESO). The corresponding ADO secret variables get removed once that integration lands.

| Name | Type | Example | Lifecycle |
|------|------|---------|-----------|
| `openshift-dev-api` | string | `https://api.dv-p.ocp.fcbint.net:6443` (per-env value) | permanent |
| `openshift-dev-namespace` | string | `dah-flink-dev` (per-env value) | permanent |
| `openshift-service-account-name` | string | per-env service account | permanent |
| `openshift-service-account-pwd` | secret | service account password | **temp — pipeline-managed; moves to CyberArk via ESO** |

### Artifactory

| Name | Type | Lifecycle |
|------|------|-----------|
| `artifactory-svc-user` | string | permanent |
| `artifactory-svc-user-password` | secret | **temp — pipeline-managed; moves to CyberArk via ESO** |

### CMF + downstream (env-prefixed)

| Name | Type | Lifecycle |
|------|------|-----------|
| `<env>-cmf-sql-server-jdbc-url` | string | permanent |
| `<env>-cmf-sql-server-user` | string | permanent |
| `<env>-cmf-sql-server-user-password` | secret | **temp — pipeline-managed; moves to CyberArk via ESO** |
| `<env>-cmf-encryption-key` | secret — AES-GCM, **never rotate** | **temp — pipeline-managed; moves to CyberArk via ESO** |
| `<env>-confluent-license` | secret (locked) | **temp — pipeline-managed; moves to CyberArk via ESO** |
| `<env>-kafka-broker-hosts` | string — comma-separated | permanent |
| `<env>-kafka-rest-proxy-hosts` | string — comma-separated | permanent |
| `<env>-schema-registry-hosts` | string — comma-separated | permanent |
| `<env>-net-app-s3-url` | string | permanent |

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

After the platform is green, individual Flink job repos run their own CI/CD pipelines to deploy `FlinkApplication` CRs into the environment.

`flink-environments` is idempotent (environment is upsert; catalog/database are create-if-missing) — re-running is safe. `cmf-tls` is bootstrap-once per env; cert-manager handles renewal silently after that.

## Cross-references

| Resource | Path |
|---|---|
| Helm values, manifests | [`apps/`](../apps/) |
| Vendored CMF chart | [`charts/confluent-manager-for-apache-flink/`](../charts/confluent-manager-for-apache-flink/) |
| FCB pre-created RBAC | [`openshift-prereqs/`](../openshift-prereqs/) |
