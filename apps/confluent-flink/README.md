# Confluent Flink — Environment, Catalog, Database (and CFK templates)

This directory holds **two distinct kinds of YAML** that look superficially similar but go to different controllers. Read this header first or you'll get confused.

## What's actually deployed at FCB today

Per environment under `apps/confluent-flink/<env>/`:

| File | Kind | Applied via | Active? |
|------|------|-------------|---------|
| `environment.yaml` | CMF REST payload — Flink Environment | [`flink-environment.yaml`](../../.azure-pipelines/flink-environment.yaml) → `POST /cmf/api/v1/environments` | **Yes (dev)** |
| `kafka-catalog.yaml` | CMF REST payload — Kafka Catalog | [`kafka-catalog.yaml`](../../.azure-pipelines/kafka-catalog.yaml) → `POST /cmf/api/v1/catalogs/kafka` | **Yes (dev)** |
| `kafka-database.yaml` | CMF REST payload — Kafka Database | [`kafka-database.yaml`](../../.azure-pipelines/kafka-database.yaml) → `POST /cmf/api/v1/catalogs/kafka/<catalog>/databases` | **Yes (dev)** |

These are **not Kubernetes resources**. They're CMF REST API payloads, authored as YAML in Git for readability and converted to JSON in-flight by the pipeline (PyYAML) before posting.

Currently only **`dev/`** has these three files populated. `qa/`, `uat/`, `prd/` will get them when those envs come online.

## What's a template (not deployed)

Per environment under `apps/confluent-flink/<env>/`:

| File | Kind | Status |
|------|------|--------|
| `cmf-rest-class.yaml` | CFK CR — `CMFRestClass` | **Template only** |
| `flink-environment.yaml` | CFK CR — `FlinkEnvironment` (apiVersion `platform.confluent.io/v1beta1`) | **Template only** |
| `flink-pvc.yaml` | `PersistentVolumeClaim` for checkpoints | **Template only** (state goes to NetApp S3, not PVC) |
| `flink-session-cluster.yaml` | CFK CR — `FlinkDeployment` (session cluster) | **Template only** |

These all require **CFK (Confluent for Kubernetes)**, which **FCB does not run**. They're left in the tree as reference for a future world where CFK is adopted, or for non-FCB consumers of this repo.

⚠️ **Naming collision warning:** `flink-environment.yaml` (CFK CR) and `environment.yaml` (CMF REST payload) **both produce a Flink "Environment"**, but in different controllers. Don't mix them up — the CMF REST payload has no `apiVersion`/`kind`/`metadata` block; the CFK CR does.

## Per-env layout

```
apps/confluent-flink/
├── README.md  (this file)
└── <env>/
    ├── environment.yaml           # CMF REST — Flink Environment    (dev only today)
    ├── kafka-catalog.yaml         # CMF REST — Kafka Catalog        (dev only today)
    ├── kafka-database.yaml        # CMF REST — Kafka Database       (dev only today)
    ├── cmf-rest-class.yaml        # CFK CR — template
    ├── flink-environment.yaml     # CFK CR — template
    ├── flink-pvc.yaml             # PVC — template
    └── flink-session-cluster.yaml # CFK CR — template
```

## CMF REST payload — what they look like

### environment.yaml

Flat shape (no `apiVersion`/`kind`/`metadata`):

```yaml
name: dah-flink-dev
kubernetesNamespace: dah-flink-dev
flinkApplicationDefaults:
  spec:
    flinkConfiguration:
      taskmanager.numberOfTaskSlots: "2"
    jobManager: { resource: { memory: 4000m, cpu: 1 } }
    taskManager: { resource: { memory: 4000m, cpu: 1 } }
computePoolDefaults:
  clusterSpec:
    flinkVersion: v2_1
    image: artifactory.fcbint.net/.../cp-flink:2.1.1-cp1-java21
    flinkConfiguration: { taskmanager.numberOfTaskSlots: "2" }
```

### kafka-catalog.yaml + kafka-database.yaml

K8s-style shape (with `apiVersion: cmf.confluent.io/v1`, `kind`, `metadata`, `spec`) — but still served via CMF REST, **not** by the K8s API server. The shape is what CMF expects on POST.

The `kafka-database` pipeline reads `kafka-catalog.yaml` first to learn the **parent catalog name** for the URL path; if the catalog isn't already registered in CMF, the database pipeline aborts with a clear error pointing you to run `kafka-catalog` first.

## Run order

1. [`.azure-pipelines/flink-environment.yaml`](../../.azure-pipelines/flink-environment.yaml) — upserts the environment.
2. [`.azure-pipelines/kafka-catalog.yaml`](../../.azure-pipelines/kafka-catalog.yaml) — creates the catalog.
3. [`.azure-pipelines/kafka-database.yaml`](../../.azure-pipelines/kafka-database.yaml) — creates the database under the catalog.

All three are **idempotent** (env is upsert; catalog/database are create-if-missing) — re-running is safe.

## Cross-references

| Resource | Path |
|---|---|
| CMF Helm install | [`apps/confluent-cmf/`](../confluent-cmf/) |
| Three CMF REST pipelines | [`.azure-pipelines/flink-environment.yaml`](../../.azure-pipelines/flink-environment.yaml), [`.azure-pipelines/kafka-catalog.yaml`](../../.azure-pipelines/kafka-catalog.yaml), [`.azure-pipelines/kafka-database.yaml`](../../.azure-pipelines/kafka-database.yaml) |
| CFK-style CR pipeline (template, not active) | [`.azure-pipelines/flink-crs.yaml`](../../.azure-pipelines/flink-crs.yaml) |
