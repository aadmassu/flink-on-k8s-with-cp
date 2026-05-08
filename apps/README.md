# Apps — Helm Values & Kubernetes Manifests

Helm values and Kubernetes/CMF manifests for the FCB stack, deployed via the pipelines in [`.azure-pipelines/`](../.azure-pipelines/).

## Subdirectories

| Directory | Type | Deployed today? | Pipeline |
|-----------|------|-----------------|----------|
| [`confluent-cmf/`](confluent-cmf/) | Helm values for the local CMF chart | **Yes** | [`cmf.yaml`](../.azure-pipelines/cmf.yaml) |
| [`confluent-flink/<env>/`](confluent-flink/) (`environment.json`, `kafka-catalog.json`, `kafka-database.json`) | CMF REST API payloads, authored as JSON | **Yes (dev populated; qa/uat/prd ship with placeholder hostnames)** | [`flink-environments`](../.azure-pipelines/flink-environments.yaml) (single pipeline applies all three) |

## Per-environment layout

```
apps/<component>/
├── dev/...
├── qa/...
├── uat/...
└── prd/...
```

Each env folder holds either Helm values (CMF) or CMF REST API payloads (Flink env / catalog / database).

| Environment | Namespace |
|---|---|
| dev | `dah-flink-dev` |
| qa | `dah-flink-qa` |
| uat | `dah-flink-uat` |
| prd | `dah-flink-prd` |

## How each kind is applied

### Helm-based (CMF)

```bash
helm upgrade --install confluent-cmf charts/confluent-manager-for-apache-flink \
  --namespace dah-flink-<env> \
  -f apps/confluent-cmf/<env>/values.yaml \
  --set namespaced=true
```

Driven by [`.azure-pipelines/cmf.yaml`](../.azure-pipelines/cmf.yaml).

### CMF REST API payloads (Flink Environment, Kafka Catalog, Kafka Database)

JSON files at `apps/confluent-flink/<env>/{environment,kafka-catalog,kafka-database}.json` are POSTed verbatim to CMF — no YAML conversion, no PyYAML. The pipeline pre-flight aborts if any `REPLACE_WITH_*` placeholder is still present (qa/uat/prd ship with placeholders for env-specific Kafka brokers and Schema Registry URL).

Driven by [`.azure-pipelines/flink-environments.yaml`](../.azure-pipelines/flink-environments.yaml).
