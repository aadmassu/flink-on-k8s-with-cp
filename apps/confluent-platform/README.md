# Confluent Platform — CFK CRs (Template Only — NOT Deployed at FCB)

⚠️ **Status: template / not deployed at FCB.**

The manifests in this directory are CFK (Confluent for Kubernetes) custom resources for an **in-cluster Kafka stack** (KRaft, Kafka, Schema Registry, Connect, Control Center). FCB **does not run CFK**. FCB's Kafka cluster runs on VMs, outside OpenShift; Flink/CMF connect out to those VM brokers via standard bootstrap servers.

These files are kept in the repo as:
- **Reference** for a future world where CFK is adopted at FCB
- **Reusable patterns** for non-FCB consumers of this repo

If you're deploying CMF + Flink at FCB today, you can ignore this whole directory.

## Components (when this stack is actually deployed)

| CR | File | Purpose |
|----|------|---------|
| `KRaftController` | `kraft-controller.yaml` | KRaft consensus controller (replaces ZooKeeper) |
| `Kafka` | `kafka.yaml` | Kafka brokers (depends on KRaft) |
| `SchemaRegistry` | `schema-registry.yaml` | Schema Registry |
| `Connect` | `connect.yaml` | Kafka Connect |
| `ControlCenter` | `control-center.yaml` | Confluent Control Center UI |
| `KafkaRestClass` | `kafka-rest-class.yaml` | Internal CFK REST proxy reference |
| `RoleBinding` | `rbac-rolebindings.yaml` | RBAC bindings for the components above |
| `Secret` | `secrets.yaml` | Component-level secrets (in CFK-managed format) |

## Layout

```
apps/confluent-platform/
├── README.md  (this file)
└── <env>/
    ├── kraft-controller.yaml
    ├── kafka.yaml
    ├── schema-registry.yaml
    ├── connect.yaml
    ├── control-center.yaml
    ├── kafka-rest-class.yaml
    ├── rbac-rolebindings.yaml
    └── secrets.yaml
```

Each env (`dev`, `qa`, `uat`, `prd`) has its own directory; namespace is hard-coded in each manifest as `dah-kafka-<env>` (separate from the `dah-flink-<env>` namespace where CMF runs).

## Pre-requisites if you ever do deploy this

- **CFK operator** running and reconciling these CRDs
- **cert-manager** running (CFK webhooks need TLS)
- The `dah-kafka-<env>` namespace pre-created with the right SCC bindings

None of this exists at FCB today.

## At FCB, the equivalents are

- Kafka brokers, Schema Registry, REST Proxy → on VMs at `d11547varc-*.fcpd.fcbint.net` ports 9094 / 8081 / 8082
- The `<env>-kafka-broker-hosts`, `<env>-schema-registry-hosts`, `<env>-kafka-rest-proxy-hosts` variables in the `<env>-openshift-credentials` ADO variable group hold the actual hostnames.
