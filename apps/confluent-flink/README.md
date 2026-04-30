# Confluent Flink — Environment, Catalog, Database (and CFK templates)

This directory holds **two distinct kinds of YAML** that look superficially similar but go to different controllers. Read this header first or you'll get confused.

## What's actually deployed at FCB today

Per environment under `apps/confluent-flink/<env>/`:

| File | Kind | Applied via | Active? |
|------|------|-------------|---------|
| `environment.yaml` | CMF REST payload — Flink Environment | [`flink-environments.yaml`](../../.azure-pipelines/flink-environments.yaml) → `POST /cmf/api/v1/environments` | **Yes (dev)** |
| `kafka-catalog.yaml` | CMF REST payload — Kafka Catalog | same pipeline → `POST /cmf/api/v1/catalogs/kafka` | **Yes (dev)** |
| `kafka-database.yaml` | CMF REST payload — Kafka Database | same pipeline → `POST /cmf/api/v1/catalogs/kafka/<catalog>/databases` | **Yes (dev)** |

These are **not Kubernetes resources**. They're CMF REST API payloads, authored as YAML in Git for readability and converted to JSON in-flight by the pipeline (PyYAML) before posting.

Currently only **`dev/`** has these three files populated. `qa/`, `uat/`, `prd/` will get them when those envs come online.

## What's reference-only (not deployed; no pipeline)

Per environment under `apps/confluent-flink/<env>/`:

| File | Kind | Status |
|------|------|--------|
| `cmf-rest-class.yaml` | CFK CR — `CMFRestClass` | **Reference only** |
| `flink-environment.yaml` | CFK CR — `FlinkEnvironment` (apiVersion `platform.confluent.io/v1beta1`) | **Reference only** |
| `flink-pvc.yaml` | `PersistentVolumeClaim` for checkpoints | **Reference only** (state goes to NetApp S3, not PVC) |
| `flink-session-cluster.yaml` | CFK CR — `FlinkDeployment` (session cluster) | **Reference only** |

These all require **CFK (Confluent for Kubernetes)**, which **FCB does not run**. There's no pipeline that applies them — they're documented reference material for a future CFK-enabled environment.

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

Within a single `flink-environments` run the pipeline reads `kafka-catalog.yaml` to learn the parent catalog name and uses it when posting `kafka-database.yaml`.

## Run order

A single pipeline run applies all three resources in order:

1. POST `environment.yaml` to `/cmf/api/v1/environments` (upsert — always replace).
2. GET `/cmf/api/v1/catalogs/kafka/<catalog>` and POST `kafka-catalog.yaml` if absent (create-if-missing).
3. GET `/cmf/api/v1/catalogs/kafka/<catalog>/databases/<database>` and POST `kafka-database.yaml` if absent (create-if-missing).

The pipeline is idempotent — re-running is safe.

## Cross-references

| Resource | Path |
|---|---|
| CMF Helm install | [`apps/confluent-cmf/`](../confluent-cmf/) |
| CMF REST pipeline (single, applies all three) | [`.azure-pipelines/flink-environments.yaml`](../../.azure-pipelines/flink-environments.yaml) |
