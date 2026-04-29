# Apps — Helm Values & Kubernetes Manifests

Helm values and Kubernetes/CMF manifests for the FCB stack, deployed via the pipelines in [`.azure-pipelines/`](../.azure-pipelines/).

## Subdirectories

| Directory | Type | Deployed today? | Pipeline |
|-----------|------|-----------------|----------|
| [`confluent-cmf/`](confluent-cmf/) | Helm values for the local CMF chart | **Yes** | [`cmf.yaml`](../.azure-pipelines/cmf.yaml) |
| [`confluent-flink/<env>/`](confluent-flink/) (`environment.yaml`, `kafka-catalog.yaml`, `kafka-database.yaml`) | CMF REST API payloads, expressed as YAML | **Yes (dev populated; qa/uat/prd to follow)** | [`flink-environment`](../.azure-pipelines/flink-environment.yaml), [`kafka-catalog`](../.azure-pipelines/kafka-catalog.yaml), [`kafka-database`](../.azure-pipelines/kafka-database.yaml) |
| [`confluent-flink/<env>/`](confluent-flink/) (`cmf-rest-class.yaml`, `flink-environment.yaml`, `flink-pvc.yaml`, `flink-session-cluster.yaml`) | CFK-based Flink CRs | **No** — kept as template; FCB doesn't run CFK today | [`flink-crs.yaml`](../.azure-pipelines/flink-crs.yaml) (not active) |
| [`confluent-platform/`](confluent-platform/) | CFK-based Kafka / SR / Connect / C3 CRs | **No** — FCB uses VM Kafka, not in-cluster | (none) |

The CMF REST API YAMLs and the CFK-based CRs share similar names (`flink-environment.yaml`!), so be careful: they target completely different controllers.

## Per-environment layout

```
apps/<component>/
├── dev/...
├── qa/...
├── uat/...
└── prd/...
```

Each env folder holds either Helm values (CMF), CMF REST API payloads (Flink dev), or CFK-style CRs (other Flink files + confluent-platform).

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
  -f apps/confluent-cmf/openshift-overlay.yaml \
  --set namespaced=true
```

Driven by [`.azure-pipelines/cmf.yaml`](../.azure-pipelines/cmf.yaml).

### CMF REST API payloads (Flink Environment, Kafka Catalog, Kafka Database)

```bash
# YAML manifests at apps/confluent-flink/<env>/{environment,kafka-catalog,kafka-database}.yaml
# Each pipeline reads its own manifest, converts YAML -> JSON via PyYAML, and POSTs to CMF.
```

Driven by [`.azure-pipelines/flink-environment.yaml`](../.azure-pipelines/flink-environment.yaml), [`.azure-pipelines/kafka-catalog.yaml`](../.azure-pipelines/kafka-catalog.yaml), [`.azure-pipelines/kafka-database.yaml`](../.azure-pipelines/kafka-database.yaml).

### CFK-based CRs (template only)

`oc apply -f` of CFK CRDs (`CMFRestClass`, `FlinkEnvironment`, `FlinkDeployment`, `Kafka`, `SchemaRegistry`, `Connect`, `ControlCenter`). Not used at FCB today; left in the tree as reference for a future world where CFK is adopted or for non-FCB environments.
