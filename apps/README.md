# Apps — Helm Values & Kubernetes Manifests

Helm values and Kubernetes/CMF manifests for the FCB stack, deployed via the pipelines in [`.azure-pipelines/`](../.azure-pipelines/).

## Subdirectories

| Directory | Type | Deployed today? | Pipeline |
|-----------|------|-----------------|----------|
| [`confluent-cmf/`](confluent-cmf/) | Helm values for the local CMF chart | **Yes** | [`cmf.yaml`](../.azure-pipelines/cmf.yaml) |
| [`confluent-flink/<env>/`](confluent-flink/) (`environment.yaml`, `kafka-catalog.yaml`, `kafka-database.yaml`) | CMF REST API payloads, expressed as YAML | **Yes (dev populated; qa/uat/prd to follow)** | [`flink-environments`](../.azure-pipelines/flink-environments.yaml) (single pipeline applies all three) |
| [`confluent-flink/<env>/`](confluent-flink/) (`cmf-rest-class.yaml`, `flink-environment.yaml`, `flink-pvc.yaml`, `flink-session-cluster.yaml`) | CFK-based Flink CRs (reference only) | **No** — FCB doesn't run CFK; kept as documented reference | None |

The CMF REST API YAMLs and the CFK-based CR templates share similar names (`flink-environment.yaml`!), so be careful: they target completely different controllers.

## Per-environment layout

```
apps/<component>/
├── dev/...
├── qa/...
├── uat/...
└── prd/...
```

Each env folder holds either Helm values (CMF), CMF REST API payloads (Flink dev), or CFK-style CR reference templates (other Flink files).

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

```bash
# YAML manifests at apps/confluent-flink/<env>/{environment,kafka-catalog,kafka-database}.yaml
# A single pipeline reads all three, converts YAML -> JSON via PyYAML, and POSTs them to CMF.
```

Driven by [`.azure-pipelines/flink-environments.yaml`](../.azure-pipelines/flink-environments.yaml).

### CFK-based CRs (reference templates)

The `cmf-rest-class.yaml`, `flink-environment.yaml`, `flink-pvc.yaml`, and `flink-session-cluster.yaml` files under `apps/confluent-flink/<env>/` use the CFK CRD shapes (`apiVersion: platform.confluent.io/v1beta1`). FCB does not run CFK, so there's **no pipeline** that applies them. They're reference material — kept as a documented starting point for a future CFK-enabled environment or for non-FCB consumers of this stack pattern.
