# Confluent Platform

> **Coming soon.** This component's deployment guide will be added in a future update.

Confluent Platform CRD manifests for deploying the full Kafka ecosystem. Requires the [Confluent Operator](../confluent-operator/) to be running.

## Components

| Component | Sync Wave | Description |
|-----------|-----------|-------------|
| KRaftController | 0 | KRaft consensus layer (replaces ZooKeeper) |
| Kafka | 1 | Kafka brokers |
| SchemaRegistry | 2 | Schema management for Kafka topics |
| Connect | 2 | Kafka Connect for data integration |
| ksqlDB | 3 | Stream processing SQL engine |
| ControlCenter | 3 | Web-based management UI |

## Directory Structure

```
confluent-platform/
|-- dev/
|   |-- app.yaml       # ArgoCD Application resource (directory source)
|   +-- manifests/     # Kubernetes CRD manifest files
|       |-- kraft-controller.yaml
|       |-- kafka.yaml
|       |-- schema-registry.yaml
|       |-- connect.yaml
|       |-- ksqldb.yaml
|       +-- control-center.yaml
|-- qa/
|-- stg/
+-- prd/
```

## Sync Wave Ordering

Components are deployed in order using `argocd.argoproj.io/sync-wave` annotations to respect startup dependencies.

## Dependencies

- **Depends on:** Confluent Operator (CFK) must be running
