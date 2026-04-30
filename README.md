# CMF + Flink on OpenShift @ FCB

Helm values, Kubernetes manifests, and Azure DevOps pipelines for deploying **Confluent Manager for Apache Flink (CMF)** and Apache Flink workloads on FCB's on-prem OpenShift, against the **existing Confluent Platform Kafka cluster running on VMs**.

## Stack at FCB

```
   Apache Flink (jobs)        ←  this repo deploys
   Confluent Manager for Flink (CMF)   ← this repo deploys
   Flink Kubernetes Operator           ← deployed by FCB Container Platforms via ArgoCD
   ───────────── OpenShift ────────────
   VM Kafka cluster (Confluent Platform on VMs)   ← existing, outside K8s
```

CFK (Confluent for Kubernetes) is **not** used at FCB. Kafka, Schema Registry, and REST Proxy run on FCB's existing VM cluster; Flink in OpenShift connects out to them via standard bootstrap servers.

## What this repo contains

```
apps/
├── confluent-cmf/          # Helm values for CMF — deployed by .azure-pipelines/cmf.yaml
├── confluent-flink/        # CMF REST API manifests (Environment, KafkaCatalog, KafkaDatabase)
│                           # plus CFK-style CR templates (kept for future use; not deployed today)
└── confluent-platform/     # CFK-based Kafka/SR/Connect/C3 templates (NOT deployed at FCB)

charts/
└── confluent-manager-for-apache-flink/   # Vendored CMF Helm chart (with FCB modifications)

openshift-prereqs/<env>/manifests/
└── flink-sa-role-rolebinding.yaml        # Pre-created by FCB Container Platforms team

.azure-pipelines/
├── verify-flink-setup.yaml       # End-to-end health check (RBAC, TLS, CMF, environment/catalog/database)
├── connectivity-test.yaml        # Busybox-based DNS + TCP probe to VM Kafka, SR, S3, SQL Server
├── push-image.yaml               # Push CMF / utility images to FCB Artifactory
├── cmf.yaml                      # Install CMF via Helm
├── flink-environments.yaml       # Apply Flink Environment + Kafka Catalog + Kafka Database to CMF (REST)
└── flink-crs.yaml                # CFK-style Flink CRs (template; not used until CFK lands)
```

## Environments

| Environment | Namespace (CMF + Flink workloads) |
|---|---|
| dev | `dah-flink-dev` |
| qa | `dah-flink-qa` |
| uat | `dah-flink-uat` |
| prd | `dah-flink-prd` |

Each environment has its own `<env>-openshift-credentials` variable group in Azure DevOps holding cluster API URL, service account credentials, SQL Server JDBC URL, Kafka broker hostnames, NetApp S3 endpoint, encryption key, and Confluent license.

## Deployment order

> **Strict order.** `cmf-tls` MUST run before `cmf` — the `cmf` pipeline has a pre-flight check for `secret/cmf-tls` and aborts if it's missing.

For a new environment:

1. **FCB Container Platforms team** creates the namespace `dah-flink-<env>`, applies `openshift-prereqs/<env>/manifests/flink-sa-role-rolebinding.yaml`, and ensures the Flink Kubernetes Operator's RBAC binds the `flink-operator` SA in that namespace (handled by the `fcb-security` ArgoCD chart).
2. Run `connectivity-test.yaml` from inside the namespace — verifies the pod can reach VM Kafka brokers, Schema Registry, REST Proxy, NetApp S3, and SQL Server.
3. Run `cmf-tls.yaml` — applies the cert-manager `Certificate`, waits for Keyfactor approval, produces `secret/cmf-tls` (`tls.crt`, `tls.key`, `ca.crt`).
4. Run `cmf.yaml` — installs CMF via Helm. Pre-flights `secret/cmf-tls`, then mounts it into the pod for HTTPS on the REST endpoint. Other secrets (DB password, encryption key, license) come from the ADO variable group today; ESO+CyberArk integration is the target state (separate branch).
5. Run `flink-environments.yaml` — registers the Flink environment, Kafka catalog, and Kafka database via CMF's REST API in a single run.
6. Run `verify-flink-setup.yaml` — end-to-end read-only health check; the summary table confirms each layer is green.

## FCB-specific operational notes

- All resources carry FCB-required labels (`app.kubernetes.io/{name,instance,component}`, `fcbint.net/app-id: 11547`) — enforced by the cluster's Common Metadata admission policy.
- All container images are pulled from `artifactory.fcbint.net/camdepositsharedservices-docker-dev/`.
- CMF state lives in an external SQL Server (FCB DBA team provisions the database per env); for envs where the DB isn't ready yet, CMF runs with `database.type: local` (SQLite on ephemeral pod storage) for short-term validation only.
- Flink checkpoints/savepoints target the on-prem NetApp S3 bucket per env.
- Secrets pulled from the `<env>-openshift-credentials` Azure DevOps variable group today; **target state is ESO + CyberArk** (FCB's standard).
