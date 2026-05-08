# Confluent Flink — Environment, Catalog, Database (and CFK templates)

This directory holds **two distinct kinds of file** that look superficially similar but go to different controllers. Read this header first or you'll get confused.

## What's actually deployed at FCB today

Per environment under `apps/confluent-flink/<env>/`:

| File | Kind | Applied via | Active? |
|------|------|-------------|---------|
| `environment.json` | CMF REST payload — Flink Environment | [`flink-environments.yaml`](../../.azure-pipelines/flink-environments.yaml) → `POST /cmf/api/v1/environments` | **Yes (dev)** |
| `kafka-catalog.json` | CMF REST payload — Kafka Catalog | same pipeline → `POST /cmf/api/v1/catalogs/kafka` | **Yes (dev)** |
| `kafka-database.json` | CMF REST payload — Kafka Database | same pipeline → `POST /cmf/api/v1/catalogs/kafka/<catalog>/databases` | **Yes (dev)** |

These are **not Kubernetes resources**. They're CMF REST API payloads — authored as JSON so the pipeline can POST them as-is (no YAML→JSON conversion, no PyYAML).

`dev/` is fully populated and live. `qa/`, `uat/`, `prd/` ship with `REPLACE_WITH_*` placeholder hostnames in their Kafka broker / Schema Registry URL fields; the pipeline pre-flight aborts with a clear error if any are still unresolved. Replace those with the env-specific values before running the pipeline against that env.

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
    ├── environment.json           # CMF REST — Flink Environment    (live; placeholders in qa/uat/prd)
    ├── kafka-catalog.json         # CMF REST — Kafka Catalog        (live; placeholders in qa/uat/prd)
    ├── kafka-database.json        # CMF REST — Kafka Database       (live; placeholders in qa/uat/prd)
    ├── cmf-rest-class.yaml        # CFK CR — reference only
    ├── flink-environment.yaml     # CFK CR — reference only
    ├── flink-pvc.yaml             # PVC — reference only
    └── flink-session-cluster.yaml # CFK CR — reference only
```

## CMF REST payload — what they look like

### environment.json

Flat shape (no `apiVersion`/`kind`/`metadata`):

```json
{
  "name": "dah-flink-dev",
  "kubernetesNamespace": "dah-flink-dev",
  "flinkApplicationDefaults": { "spec": { "flinkConfiguration": { "taskmanager.numberOfTaskSlots": "2" }, "jobManager": { "resource": { "memory": "4000m", "cpu": 1 } }, "taskManager": { "resource": { "memory": "4000m", "cpu": 1 } } } },
  "computePoolDefaults": { "clusterSpec": { "flinkVersion": "v2_1", "image": "artifactory.fcbint.net/.../cp-flink:2.1.1-cp1-java21", "flinkConfiguration": { "taskmanager.numberOfTaskSlots": "2" } } }
}
```

### kafka-catalog.json + kafka-database.json

K8s-style shape (with `apiVersion: cmf.confluent.io/v1`, `kind`, `metadata`, `spec`) — but still served via CMF REST, **not** by the K8s API server. The shape is what CMF expects on POST.

The pipeline knows the catalog name (`fcb-catalog`, constant across envs) and the database name (`dah-kafka-<env>`) from the env parameter, so no JSON parsing is required at runtime.

## Run order

A single pipeline run applies all three resources in order:

1. Pre-flight: refuse to post if any `REPLACE_WITH_*` marker is still in the JSON (qa/uat/prd ship with placeholders).
2. POST `environment.json` to `/cmf/api/v1/environments` (upsert — always replace).
3. GET `/cmf/api/v1/catalogs/kafka/<catalog>` and POST `kafka-catalog.json` if absent (create-if-missing).
4. GET `/cmf/api/v1/catalogs/kafka/<catalog>/databases/<database>` and POST `kafka-database.json` if absent (create-if-missing).

The pipeline is idempotent — re-running is safe.

## Cross-references

| Resource | Path |
|---|---|
| CMF Helm install | [`apps/confluent-cmf/`](../confluent-cmf/) |
| CMF REST pipeline (single, applies all three) | [`.azure-pipelines/flink-environments.yaml`](../../.azure-pipelines/flink-environments.yaml) |
