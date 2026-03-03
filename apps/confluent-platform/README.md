# Confluent Platform CRD Manifests

This directory contains [Confluent for Kubernetes (CFK)](https://docs.confluent.io/operator/current/overview.html) Custom Resource Definition (CRD) manifests that declaratively define the entire Confluent Platform deployment. Each environment (dev, qa, stg, prd) has its own set of manifests with configuration tuned for that tier. These manifests are consumed by Argo CD ApplicationSets for GitOps-driven deployment, and they require the [Confluent Operator](../confluent-operator/) to already be running in the target cluster.

All CRDs use API version **`platform.confluent.io/v1beta1`**, which is the CFK v2.x custom resource API. This API version is the current stable interface provided by Confluent for Kubernetes and replaces the legacy v1 operator CRDs. The `v1beta1` designation indicates the API is feature-complete but may receive minor additive changes in future CFK releases.

---

## Directory Structure

```
confluent-platform/
|-- README.md
|-- dev/
|   +-- manifests/
|       |-- kraft-controller.yaml    # KRaft consensus controller
|       |-- kafka.yaml               # Kafka brokers
|       |-- schema-registry.yaml     # Schema Registry
|       |-- connect.yaml             # Kafka Connect
|       |-- ksqldb.yaml              # ksqlDB stream processing
|       +-- control-center.yaml      # Confluent Control Center UI
|-- qa/
|   +-- manifests/
|       |-- kraft-controller.yaml
|       |-- kafka.yaml
|       |-- schema-registry.yaml
|       |-- connect.yaml
|       |-- ksqldb.yaml
|       +-- control-center.yaml
|-- stg/
|   +-- manifests/
|       |-- kraft-controller.yaml
|       |-- kafka.yaml
|       |-- schema-registry.yaml
|       |-- connect.yaml
|       |-- ksqldb.yaml
|       +-- control-center.yaml
+-- prd/
    +-- manifests/
        |-- kraft-controller.yaml
        |-- kafka.yaml
        |-- schema-registry.yaml
        |-- connect.yaml
        |-- ksqldb.yaml
        +-- control-center.yaml
```

Each environment directory contains identical file names. The per-environment differences are limited to namespace targeting, replica counts, storage sizes, and Kafka broker configuration overrides.

---

## Component Manifests

### 1. KRaft Controller (`kraft-controller.yaml`)

**Purpose:** The KRaft Controller replaces Apache ZooKeeper as the metadata and consensus layer for Kafka. It implements the KRaft (Kafka Raft) protocol to manage cluster metadata, broker registration, topic partition leadership election, and configuration propagation. KRaft controllers form their own quorum and must be fully available before Kafka brokers can start.

#### Manifest Specification (dev environment shown)

```yaml
apiVersion: platform.confluent.io/v1beta1
kind: KRaftController
metadata:
  name: kraftcontroller
  namespace: confluent-dev
  annotations:
    argocd.argoproj.io/sync-wave: "0"
spec:
  replicas: 1
  dataVolumeCapacity: 10Gi
```

#### Field Reference

| Key | Value (dev) | Description |
|-----|-------------|-------------|
| `apiVersion` | `platform.confluent.io/v1beta1` | CFK custom resource API version for all Confluent Platform components |
| `kind` | `KRaftController` | The CFK custom resource kind that represents a KRaft metadata controller quorum |
| `metadata.name` | `kraftcontroller` | The Kubernetes resource name; also used by other components to reference this controller via `clusterRef` |
| `metadata.namespace` | `confluent-dev` | The target Kubernetes namespace; varies per environment (`confluent-dev`, `confluent-qa`, `confluent-stg`, `confluent-prd`) |
| `metadata.annotations.argocd.argoproj.io/sync-wave` | `"0"` | Argo CD sync wave ordering; `"0"` means this resource is deployed first, before all other Confluent components |
| `spec.replicas` | `1` | Number of KRaft controller pods to run; dev uses 1 for minimal resources, qa/stg/prd use 3 for a fault-tolerant quorum |
| `spec.dataVolumeCapacity` | `10Gi` | Size of the persistent volume claim for KRaft metadata logs; 10Gi across all environments since metadata volume is small |

---

### 2. Kafka (`kafka.yaml`)

**Purpose:** Kafka brokers are the core of the Confluent Platform. They handle message production and consumption, topic partition management, data replication, and client connections. This manifest defines the Kafka broker StatefulSet, its persistent storage, broker configuration overrides, and the dependency on the KRaft controller for cluster metadata.

#### Manifest Specification (dev environment shown)

```yaml
apiVersion: platform.confluent.io/v1beta1
kind: Kafka
metadata:
  name: kafka
  namespace: confluent-dev
  annotations:
    argocd.argoproj.io/sync-wave: "1"
spec:
  replicas: 1
  dataVolumeCapacity: 50Gi
  configOverrides:
    server:
      - default.replication.factor=1
      - min.insync.replicas=1
      - offsets.topic.replication.factor=1
      - transaction.state.log.replication.factor=1
      - transaction.state.log.min.isr=1
  dependencies:
    kRaftController:
      clusterRef:
        name: kraftcontroller
```

#### Field Reference

| Key | Value (dev) | Description |
|-----|-------------|-------------|
| `apiVersion` | `platform.confluent.io/v1beta1` | CFK custom resource API version |
| `kind` | `Kafka` | The CFK custom resource kind representing a Kafka broker cluster |
| `metadata.name` | `kafka` | Kubernetes resource name; used in service DNS entries (e.g., `kafka.confluent-dev.svc.cluster.local`) |
| `metadata.namespace` | `confluent-dev` | Target Kubernetes namespace; varies per environment |
| `metadata.annotations.argocd.argoproj.io/sync-wave` | `"1"` | Argo CD sync wave; `"1"` ensures Kafka deploys after the KRaft controller (wave `"0"`) |
| `spec.replicas` | `1` | Number of Kafka broker pods; dev uses 1, qa/stg/prd use 3 for replication and high availability |
| `spec.dataVolumeCapacity` | `50Gi` | Persistent volume size for Kafka log data per broker; varies by environment (dev=50Gi, qa/stg=100Gi, prd=200Gi) |
| `spec.configOverrides.server` | (list of strings) | Kafka broker `server.properties` overrides applied at startup; values differ between dev and higher environments |
| `spec.configOverrides.server[0]` | `default.replication.factor=1` | Default replication factor for automatically created topics; dev=1 (single broker), qa/stg/prd=3 |
| `spec.configOverrides.server[1]` | `min.insync.replicas=1` | Minimum number of replicas that must acknowledge a write for it to be considered successful; dev=1, qa/stg/prd=2 |
| `spec.configOverrides.server[2]` | `offsets.topic.replication.factor=1` | Replication factor for the `__consumer_offsets` internal topic; dev=1, qa/stg/prd=3 |
| `spec.configOverrides.server[3]` | `transaction.state.log.replication.factor=1` | Replication factor for the `__transaction_state` internal topic; dev=1, qa/stg/prd=3 |
| `spec.configOverrides.server[4]` | `transaction.state.log.min.isr=1` | Minimum in-sync replicas for the transaction state log topic; dev=1, qa/stg/prd=2 |
| `spec.dependencies.kRaftController.clusterRef.name` | `kraftcontroller` | Reference to the KRaftController CR name that this Kafka cluster should use for metadata management |

---

### 3. Schema Registry (`schema-registry.yaml`)

**Purpose:** Schema Registry provides a centralized repository for managing and validating Avro, Protobuf, and JSON schemas. It enables schema evolution with compatibility enforcement, ensuring producers and consumers agree on data formats. Schema Registry stores its schemas in a Kafka topic and therefore depends on Kafka being available.

#### Manifest Specification (dev environment shown)

```yaml
apiVersion: platform.confluent.io/v1beta1
kind: SchemaRegistry
metadata:
  name: schemaregistry
  namespace: confluent-dev
  annotations:
    argocd.argoproj.io/sync-wave: "2"
spec:
  replicas: 1
  dependencies:
    kafka:
      bootstrapEndpoint: kafka.confluent-dev.svc.cluster.local:9071
```

#### Field Reference

| Key | Value (dev) | Description |
|-----|-------------|-------------|
| `apiVersion` | `platform.confluent.io/v1beta1` | CFK custom resource API version |
| `kind` | `SchemaRegistry` | The CFK custom resource kind representing a Schema Registry cluster |
| `metadata.name` | `schemaregistry` | Kubernetes resource name; used in service DNS entries (e.g., `schemaregistry.confluent-dev.svc.cluster.local`) |
| `metadata.namespace` | `confluent-dev` | Target Kubernetes namespace; varies per environment |
| `metadata.annotations.argocd.argoproj.io/sync-wave` | `"2"` | Argo CD sync wave; `"2"` ensures Schema Registry deploys after Kafka (wave `"1"`) is ready |
| `spec.replicas` | `1` | Number of Schema Registry pods; dev=1, qa=2, stg/prd=3 |
| `spec.dependencies.kafka.bootstrapEndpoint` | `kafka.confluent-dev.svc.cluster.local:9071` | Kafka bootstrap server address for Schema Registry to connect to; uses the CFK internal listener on port 9071; namespace portion varies per environment |

---

### 4. Kafka Connect (`connect.yaml`)

**Purpose:** Kafka Connect is a framework for streaming data between Apache Kafka and external systems using source and sink connectors. It enables scalable, reliable data integration without custom code. Connect workers run connector tasks and manage their configuration, offsets, and status in internal Kafka topics.

#### Manifest Specification (dev environment shown)

```yaml
apiVersion: platform.confluent.io/v1beta1
kind: Connect
metadata:
  name: connect
  namespace: confluent-dev
  annotations:
    argocd.argoproj.io/sync-wave: "2"
spec:
  replicas: 1
  dependencies:
    kafka:
      bootstrapEndpoint: kafka.confluent-dev.svc.cluster.local:9071
```

#### Field Reference

| Key | Value (dev) | Description |
|-----|-------------|-------------|
| `apiVersion` | `platform.confluent.io/v1beta1` | CFK custom resource API version |
| `kind` | `Connect` | The CFK custom resource kind representing a Kafka Connect cluster |
| `metadata.name` | `connect` | Kubernetes resource name; used in service DNS entries (e.g., `connect.confluent-dev.svc.cluster.local`) |
| `metadata.namespace` | `confluent-dev` | Target Kubernetes namespace; varies per environment |
| `metadata.annotations.argocd.argoproj.io/sync-wave` | `"2"` | Argo CD sync wave; `"2"` deploys Connect alongside Schema Registry, after Kafka is available |
| `spec.replicas` | `1` | Number of Connect worker pods; dev/qa=1, stg/prd=2 |
| `spec.dependencies.kafka.bootstrapEndpoint` | `kafka.confluent-dev.svc.cluster.local:9071` | Kafka bootstrap server address for Connect workers; uses the CFK internal listener on port 9071; namespace portion varies per environment |

---

### 5. ksqlDB (`ksqldb.yaml`)

**Purpose:** ksqlDB is a streaming SQL engine built on top of Kafka Streams. It allows users to build real-time data pipelines and streaming applications using SQL-like syntax. ksqlDB servers process continuous queries against Kafka topics and materialize results into new topics or queryable tables. It requires persistent storage for its state stores and RocksDB instances.

#### Manifest Specification (dev environment shown)

```yaml
apiVersion: platform.confluent.io/v1beta1
kind: KsqlDB
metadata:
  name: ksqldb
  namespace: confluent-dev
  annotations:
    argocd.argoproj.io/sync-wave: "3"
spec:
  replicas: 1
  dataVolumeCapacity: 10Gi
  dependencies:
    kafka:
      bootstrapEndpoint: kafka.confluent-dev.svc.cluster.local:9071
```

#### Field Reference

| Key | Value (dev) | Description |
|-----|-------------|-------------|
| `apiVersion` | `platform.confluent.io/v1beta1` | CFK custom resource API version |
| `kind` | `KsqlDB` | The CFK custom resource kind representing a ksqlDB server cluster |
| `metadata.name` | `ksqldb` | Kubernetes resource name; used in service DNS entries (e.g., `ksqldb.confluent-dev.svc.cluster.local`) |
| `metadata.namespace` | `confluent-dev` | Target Kubernetes namespace; varies per environment |
| `metadata.annotations.argocd.argoproj.io/sync-wave` | `"3"` | Argo CD sync wave; `"3"` ensures ksqlDB deploys last, after all upstream dependencies (Kafka, Schema Registry, Connect) are ready |
| `spec.replicas` | `1` | Number of ksqlDB server pods; dev/qa=1, stg/prd=2 |
| `spec.dataVolumeCapacity` | `10Gi` | Persistent volume size for ksqlDB state stores (RocksDB); 10Gi across all environments |
| `spec.dependencies.kafka.bootstrapEndpoint` | `kafka.confluent-dev.svc.cluster.local:9071` | Kafka bootstrap server address for ksqlDB; uses the CFK internal listener on port 9071; namespace portion varies per environment |

---

### 6. Control Center (`control-center.yaml`)

**Purpose:** Confluent Control Center is a web-based graphical user interface for managing and monitoring the Confluent Platform. It provides visibility into Kafka cluster health, topic throughput, consumer lag, Schema Registry subjects, Connect connector status, and ksqlDB queries. It aggregates metrics by consuming from internal monitoring topics and depends on all other Confluent Platform components.

#### Manifest Specification (dev environment shown)

```yaml
apiVersion: platform.confluent.io/v1beta1
kind: ControlCenter
metadata:
  name: controlcenter
  namespace: confluent-dev
  annotations:
    argocd.argoproj.io/sync-wave: "3"
spec:
  replicas: 1
  dataVolumeCapacity: 10Gi
  dependencies:
    kafka:
      bootstrapEndpoint: kafka.confluent-dev.svc.cluster.local:9071
    schemaRegistry:
      url: http://schemaregistry.confluent-dev.svc.cluster.local:8081
    connect:
      - name: connect
        url: http://connect.confluent-dev.svc.cluster.local:8083
    ksqldb:
      - name: ksqldb
        url: http://ksqldb.confluent-dev.svc.cluster.local:8088
```

#### Field Reference

| Key | Value (dev) | Description |
|-----|-------------|-------------|
| `apiVersion` | `platform.confluent.io/v1beta1` | CFK custom resource API version |
| `kind` | `ControlCenter` | The CFK custom resource kind representing a Confluent Control Center deployment |
| `metadata.name` | `controlcenter` | Kubernetes resource name; used in service DNS entries (e.g., `controlcenter.confluent-dev.svc.cluster.local`) |
| `metadata.namespace` | `confluent-dev` | Target Kubernetes namespace; varies per environment |
| `metadata.annotations.argocd.argoproj.io/sync-wave` | `"3"` | Argo CD sync wave; `"3"` deploys Control Center last alongside ksqlDB, after all monitored components are running |
| `spec.replicas` | `1` | Number of Control Center pods; always 1 across all environments (Control Center is a singleton monitoring application) |
| `spec.dataVolumeCapacity` | `10Gi` | Persistent volume size for Control Center's internal monitoring data and aggregation state; 10Gi across all environments |
| `spec.dependencies.kafka.bootstrapEndpoint` | `kafka.confluent-dev.svc.cluster.local:9071` | Kafka bootstrap server address; Control Center consumes metrics and monitoring interceptor data from Kafka; namespace portion varies per environment |
| `spec.dependencies.schemaRegistry.url` | `http://schemaregistry.confluent-dev.svc.cluster.local:8081` | Schema Registry REST API URL; enables Control Center to display schema subjects and versions; namespace portion varies per environment |
| `spec.dependencies.connect[0].name` | `connect` | Logical name for the Connect cluster registration in Control Center's configuration |
| `spec.dependencies.connect[0].url` | `http://connect.confluent-dev.svc.cluster.local:8083` | Kafka Connect REST API URL; enables Control Center to display and manage connectors; namespace portion varies per environment |
| `spec.dependencies.ksqldb[0].name` | `ksqldb` | Logical name for the ksqlDB cluster registration in Control Center's configuration |
| `spec.dependencies.ksqldb[0].url` | `http://ksqldb.confluent-dev.svc.cluster.local:8088` | ksqlDB REST API URL; enables Control Center to display and manage ksqlDB queries; namespace portion varies per environment |

---

## Per-Environment Differences

All environment manifests share the same structure and field names. The differences are limited to namespace, replica counts, storage sizes, and Kafka broker configuration values. The following tables summarize every difference.

### Namespaces

| Environment | Namespace |
|-------------|-----------|
| dev | `confluent-dev` |
| qa | `confluent-qa` |
| stg | `confluent-stg` |
| prd | `confluent-prd` |

### Replica Counts

| Component | dev | qa | stg | prd |
|-----------|-----|-----|-----|-----|
| KRaftController | 1 | 3 | 3 | 3 |
| Kafka | 1 | 3 | 3 | 3 |
| SchemaRegistry | 1 | 2 | 3 | 3 |
| Connect | 1 | 1 | 2 | 2 |
| KsqlDB | 1 | 1 | 2 | 2 |
| ControlCenter | 1 | 1 | 1 | 1 |

### Storage Sizes (dataVolumeCapacity)

| Component | dev | qa | stg | prd |
|-----------|-----|-----|-----|-----|
| KRaftController | 10Gi | 10Gi | 10Gi | 10Gi |
| Kafka | 50Gi | 100Gi | 100Gi | 200Gi |
| SchemaRegistry | N/A | N/A | N/A | N/A |
| Connect | N/A | N/A | N/A | N/A |
| KsqlDB | 10Gi | 10Gi | 10Gi | 10Gi |
| ControlCenter | 10Gi | 10Gi | 10Gi | 10Gi |

> **N/A** indicates the component does not define a `dataVolumeCapacity` field. Schema Registry and Connect are stateless with respect to local disk and store all persistent state in Kafka topics.

### Kafka Broker Configuration Overrides (`spec.configOverrides.server`)

| Configuration Property | dev | qa | stg | prd |
|------------------------|-----|-----|-----|-----|
| `default.replication.factor` | 1 | 3 | 3 | 3 |
| `min.insync.replicas` | 1 | 2 | 2 | 2 |
| `offsets.topic.replication.factor` | 1 | 3 | 3 | 3 |
| `transaction.state.log.replication.factor` | 1 | 3 | 3 | 3 |
| `transaction.state.log.min.isr` | 1 | 2 | 2 | 2 |

### Dependency Endpoint URLs

All service endpoints follow the pattern `<service>.<namespace>.svc.cluster.local:<port>`. The only variable across environments is the namespace segment. The ports are fixed:

| Service | Port | Protocol | Used By |
|---------|------|----------|---------|
| Kafka (internal listener) | 9071 | TCP (plaintext) | SchemaRegistry, Connect, KsqlDB, ControlCenter |
| Schema Registry REST API | 8081 | HTTP | ControlCenter |
| Connect REST API | 8083 | HTTP | ControlCenter |
| ksqlDB REST API | 8088 | HTTP | ControlCenter |

---

## Sync-Wave Ordering

Argo CD [sync waves](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/) control the order in which Kubernetes resources are applied during a sync operation. Each resource is annotated with `argocd.argoproj.io/sync-wave` and Argo CD processes them in ascending numeric order, waiting for resources in a given wave to become healthy before proceeding to the next wave.

The Confluent Platform components are deployed in the following wave order:

```
Wave 0: KRaftController
         |
         v
Wave 1: Kafka
         |
         v
Wave 2: SchemaRegistry, Connect       (deployed in parallel)
         |
         v
Wave 3: KsqlDB, ControlCenter         (deployed in parallel)
```

| Sync Wave | Components | Rationale |
|-----------|------------|-----------|
| `"0"` | KRaftController | Must be running first; provides the metadata quorum that Kafka brokers require to start. Without a healthy KRaft controller quorum, brokers cannot register or elect partition leaders. |
| `"1"` | Kafka | Depends on KRaftController. Kafka brokers must be fully operational before any client-facing services can connect and create their internal topics. |
| `"2"` | SchemaRegistry, Connect | Both depend directly on Kafka. They are independent of each other, so they deploy in the same wave to reduce total startup time. Schema Registry needs Kafka to store schemas in the `_schemas` topic. Connect needs Kafka for its config, offset, and status topics. |
| `"3"` | KsqlDB, ControlCenter | Depend on Kafka (and optionally on Schema Registry and Connect). Deployed last because ksqlDB may reference schemas and Control Center must connect to all other components for full monitoring. ControlCenter also depends on Schema Registry, Connect, and ksqlDB endpoints being resolvable. |

> **Note:** Components within the same sync wave are applied simultaneously by Argo CD. There is no guaranteed ordering between resources sharing the same wave number.

---

## CFK CRD API Version Notes

All manifests in this directory use:

```yaml
apiVersion: platform.confluent.io/v1beta1
```

Key details about this API version:

- **Provider:** Confluent for Kubernetes (CFK), also known as the Confluent Operator v2.x series.
- **Stability:** The `v1beta1` API is the primary and recommended API for CFK v2.x deployments. Despite the "beta" naming, it is production-ready and the only supported CRD API in the CFK 2.x line.
- **CRD Installation:** These CRDs are installed automatically when the Confluent Operator Helm chart is deployed (see [`../confluent-operator/`](../confluent-operator/)). The operator must be running before any of these custom resources can be applied.
- **Scope:** Each CRD is namespace-scoped, meaning Confluent Platform components are isolated to their respective namespaces per environment.
- **Controller:** The CFK operator watches for these CRDs and reconciles the desired state into underlying Kubernetes StatefulSets, Services, ConfigMaps, PersistentVolumeClaims, and other native resources.

---

## Dependencies

- **Confluent Operator (CFK):** Must be installed and running before applying any manifests in this directory. See [`../confluent-operator/`](../confluent-operator/).
- **Persistent Storage:** A default `StorageClass` must be available in the cluster (or explicitly specified in the manifests) to provision PersistentVolumeClaims for KRaftController, Kafka, KsqlDB, and ControlCenter.
- **Namespaces:** The target namespaces (`confluent-dev`, `confluent-qa`, `confluent-stg`, `confluent-prd`) must exist before these resources are applied. They are typically created by the Argo CD ApplicationSet or a prerequisite namespace manifest.
