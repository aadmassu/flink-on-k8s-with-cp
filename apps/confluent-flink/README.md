# Confluent Flink Manager (CMF)

> **Coming soon.** This component's deployment guide will be added in a future update.

Confluent Manager for Apache Flink (CMF) CRD manifests for managing Flink SQL workloads on Kubernetes. Requires the [Flink Operator](../confluent-flink-operator/) to be running.

## Directory Structure

```
confluent-flink/
|-- dev/
|   |-- app.yaml       # ArgoCD Application resource (directory source)
|   +-- manifests/     # Kubernetes CRD manifest files
|       +-- confluent-flink-manager.yaml
|-- qa/
|-- stg/
+-- prd/
```

## Dependencies

- **Depends on:** Flink Kubernetes Operator must be running
