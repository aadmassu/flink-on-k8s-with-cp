# Monday — Flink Architecture on K8s

**Time**: ~90 min
**Diagram**: [`60-flink-network.drawio`](60-flink-network.drawio)

## Learning objective

> **What does Flink actually do, where do its pieces sit on K8s, and how does the platform's CMF + Flink Operator deployment fit together?**

## Architecture Discussion (~45 min)

Apache Flink is a stream-processing engine. The unit of work is a **Flink job** — a directed graph of operators (source, transform, sink) running across multiple tasks in parallel.

### The Flink components

- **JobManager (JM)** — coordinator. Accepts job submissions, schedules tasks, handles checkpointing, recovers from failures. One per Flink cluster.
- **TaskManager (TM)** — workers. Each TM has N task slots; each slot runs a parallel subtask. Scale TMs to scale throughput.
- **State backend** — where Flink keeps operator state (in-memory, RocksDB on disk). Disk state is checkpointed to a durable store.
- **Checkpoint store** — durable storage for state snapshots. the platform uses NetApp S3 (project memory `project_infrastructure`).

### Deployment topology

```
┌─────────────────────────────────────────────────────┐
│  cmf namespace                                       │
│    Confluent Manager for Flink (CMF) — REST API     │
│    Stores: catalogs, environments, jobs (in SQL DB)  │
└─────────────────────────────────────────────────────┘
          ↓ submits FlinkApplication CR
┌─────────────────────────────────────────────────────┐
│  flink-operator namespace                            │
│    Apache Flink Operator (platform-installed)             │
│    Watches FlinkApplication CRs across all NS        │
└─────────────────────────────────────────────────────┘
          ↓ renders Deployments / Services / ConfigMaps
┌─────────────────────────────────────────────────────┐
│  dah-flink-dev namespace                             │
│    JobManager Deployment (HA: 1 leader + standbys)   │
│    TaskManager Deployment (N replicas)               │
│    Job-specific Service for REST + UI                │
└─────────────────────────────────────────────────────┘
```

### CMF vs Flink Operator — two layers

Confluent Manager for Flink (**CMF**) is the API gateway + multi-tenant control:
- Catalogs (logical Kafka cluster + schema registry pointers)
- Environments (dev/qa/uat/prd grouping)
- Statements (SQL jobs)
- Translates SQL/Table API to underlying Flink jobs

The **Flink Operator** is the K8s primitive:
- Watches FlinkApplication / FlinkDeployment CRs
- Spins up JM + TM Pods
- Handles failover, savepoint, upgrade

CMF talks to the operator by creating CRs.

### site-specific facts

- CMF image must be **`2.3.0-preview-2`** (project memory `project_cmf_image_tag`)
- CMF deploys with **namespace-scoped RBAC** (project memory `project_cmf_namespace_scoped`)
- CMF DB is **SQL Server** (project memory `project_infrastructure`)
- Flink Operator log config uses **`append: false`** (project memory `project_flink_operator_log_config`)
- Flink jobs in production target **VM CP Kafka** until cluster-link migration completes (project memory `project_flink_targets_vm_cp`)
- Checkpoints go to **NetApp S3** (not AWS S3)

### What a Flink "job" looks like

A typical  the platform job:

```yaml
apiVersion: cmf.confluent.io/v1
kind: FlinkApplication
metadata:
  name: enrich-orders
spec:
  image: flink:1.20
  flinkVersion: v1_20
  flinkConfiguration:
    state.backend: rocksdb
    state.checkpoints.dir: s3://netapp-bucket/checkpoints/enrich-orders
    state.savepoints.dir: s3://netapp-bucket/savepoints/enrich-orders
    s3.endpoint: https://netapp-s3.example.com
  jobManager:
    replicas: 1
  taskManager:
    replicas: 4
  job:
    jarURI: artifactory://flink-jobs/enrich-orders-1.0.0.jar
    parallelism: 4
```

When applied, the operator creates the JM + TMs, and Flink runs the job.

## Diagram Walkthrough (~30 min)

Open `60-flink-network.drawio` (the platform's canonical diagram). Walk:
- CMF → FlinkApplication CR → Operator → JM/TM Pods
- JM ↔ TM coordination
- TM → VM CP Kafka (source/sink)
- TM → NetApp S3 (checkpoints)
- TM → VM Schema Registry (Avro/Protobuf)

## Failure Scenarios

| Symptom | Where to look |
|---|---|
| FlinkApplication CR applied; no JM Pod | operator logs in `flink-operator` namespace |
| JM up but no TMs | operator can't reconcile TM deployment; quota? |
| Job RUNNING but no progress | source can't read from Kafka — auth/network/topic permissions |
| Checkpoints failing | NetApp S3 endpoint / credentials |

## Q&A

1. Why does Flink have its own state model rather than using Kafka topics for state?
2. What's the difference between a savepoint and a checkpoint?
3. Why does the platform use a separate Flink Operator + CMF rather than just Flink Operator?
4. How does Flink achieve "exactly once" when its source is Kafka?


## Added Enhancement — Flink Operational Architecture

Topics:
- JobManager responsibilities
- TaskManager responsibilities
- Resource scheduling
- Failure recovery

Failure Scenario:
JobManager unavailable.

Students explain impact and recovery process.
