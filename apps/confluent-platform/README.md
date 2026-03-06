# Confluent Platform — Local Kafka CRDs (Phase-II)

Kustomize manifests for deploying a **local Kafka cluster on K8s** using CFK (Confluent for Kubernetes) custom resources. This provides a PoC Kafka environment for Flink SQL development.

---

## Components

| CR | File | Description |
|----|------|-------------|
| **KRaftController** | `kraft-controller.yaml` | KRaft consensus controller (replaces ZooKeeper) |
| **Kafka** | `kafka.yaml` | Kafka broker with KRaft dependency |
| **SchemaRegistry** | `schema-registry.yaml` | Schema Registry for Flink SQL schema discovery |
| **Connect** | `connect.yaml` | Kafka Connect for connectors |
| **ControlCenter** | `control-center.yaml` | Confluent Control Center UI |
| **KafkaRestClass** | `kafka-rest-class.yaml` | REST proxy endpoint for CFK internal use |

---

## Directory Structure

```
apps/confluent-platform/
├── README.md
├── base/
│   ├── kustomization.yaml
│   ├── kraft-controller.yaml
│   ├── kafka.yaml
│   ├── schema-registry.yaml
│   ├── connect.yaml
│   ├── control-center.yaml
│   └── kafka-rest-class.yaml
├── dev/kustomization.yaml      # namespace: confluent-dev, patches endpoints
├── qa/kustomization.yaml
├── stg/kustomization.yaml
└── prd/kustomization.yaml
```

---

## Image Versions

| Image | Version |
|-------|---------|
| `confluentinc/cp-server` | 8.1.1 |
| `confluentinc/cp-schema-registry` | 8.1.1 |
| `confluentinc/cp-server-connect` | 8.1.1 |
| `confluentinc/cp-enterprise-control-center-next-gen` | 2.3.2 |
| `confluentinc/confluent-init-container` | 3.1.1 |

The init-container handles CFK-specific initialization.

---

## Storage

Base manifests do not specify a `storageClassName` — the OpenShift cluster default storage class is used.

| Component | Volume | Default Size |
|-----------|--------|-------------|
| KRaftController | data | 10G |
| Kafka | data | 10G |

---

## Per-Environment Overlays

Each overlay sets `namespace` and patches service endpoints to use the correct namespace:

- **ControlCenter** — `schemaRegistry.url` and `connect.url` patched to `confluent-<env>` namespace
- **KafkaRestClass** — `kafkaRest.endpoint` patched to `confluent-<env>` namespace

---

## Dependencies

- **CFK operator** must be running (reconciles all CRs in this directory)
- **cert-manager** must be running (CFK webhooks require TLS certificates)

---

## Cross-References

| Resource | Path |
|----------|------|
| ApplicationSet | [`gitops-config/openshift/dev/confluent-platform-application-set.yaml`](../../gitops-config/openshift/dev/confluent-platform-application-set.yaml) |
| CFK operator values | [`apps/confluent-operator/`](../confluent-operator/) |
| Phase-II guide | [`README-PHASE-II.md`](../../docs/README-PHASE-II.md) |
