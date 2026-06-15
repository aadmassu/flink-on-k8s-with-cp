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

### Upstream Flink CRDs — FlinkDeployment vs FlinkSessionJob

CMF's `FlinkApplication` is Confluent's wrapper. Underneath, the **Apache Flink Kubernetes Operator** (the upstream open-source operator) ships two CRDs that emit very different K8s resources. Knowing the difference matters when you troubleshoot, because what gets created depends on which CRD the operator is acting on.

| CRD | What it represents | Native K8s resources emitted |
|---|---|---|
| **FlinkDeployment** (Application mode) | A complete Flink cluster + a single job that owns that cluster's lifecycle. When the job ends, the cluster goes away. | JobManager **Deployment** · TaskManager **Deployment** · **Services** (JM REST + UI) · **ConfigMaps** (`flink-conf.yaml`, log4j) · optional **PodDisruptionBudget** |
| **FlinkDeployment** (Session mode) | A long-running Flink cluster that accepts multiple jobs over its lifetime. | Same as above — but the cluster persists past any single job |
| **FlinkSessionJob** | A job submitted to an EXISTING Session-mode FlinkDeployment. | **None.** No new infrastructure. The CR's reconciliation hits the JM REST endpoint of the referenced FlinkDeployment to deploy the JAR/SQL. Status conditions track job state (submitted / running / finished / failed). |

So when an engineer reports "I applied a `FlinkSessionJob` and nothing happened in `oc get pods`" — that's expected. The job runs as work inside the existing TaskManagers from the FlinkDeployment it points at. Look at JM REST logs + the CR's status conditions, not at new Pods.

### Where "stateful vs stateless" actually changes K8s resources

A Flink job being stateful (keyed state, windows, ValueState) by itself does NOT change which K8s objects the operator emits. What DOES change them:

| Setting | Resource change |
|---|---|
| Single JM, HA disabled | JobManager = 1-replica Deployment |
| `high-availability: kubernetes` + JM replicas ≥ 2 | JobManager promoted to **multi-replica Deployment with leader election via a ConfigMap** (e.g. `<job>-cluster-config-map`); HA state path (S3 / PVC) referenced in config |
| State backend: HashMap | No extra K8s resources — state lives in JVM heap |
| State backend: RocksDB | No extra K8s resources at the orchestration layer — RocksDB writes to local Pod disk; checkpoints still flow to S3/PV |
| Reactive mode / autoscaling | No new resources; operator mutates `spec.replicas` on TM Deployment in-place |

The operator does NOT create PVCs for checkpoint/savepoint storage at the platform — it configures Flink Pods with the S3 endpoint, and Flink writes there directly via the S3 file-system plugin.

### CMF on top of all this

In the platform's deployment, CMF translates each statement into a **`FlinkApplication`** CR (Confluent's wrapper), which the Confluent-branded operator turns into a **`FlinkDeployment` in Application mode** (one cluster per statement, dedicated lifecycle). CMF does NOT typically use `FlinkSessionJob` here — every SQL statement gets its own cluster. That's why you see N JobManager + TaskManager pairs in `dah-flink-<env>` for N active CMF statements, rather than one shared session cluster.

Three layers to keep straight in your head:

```
1. CMF Statement (SQL or Table API)            ← what the engineer/analyst writes
   ↓
2. FlinkApplication CR (Confluent wrapper)     ← what CMF creates
   ↓
3. FlinkDeployment CR (upstream Apache CRD)    ← what the Confluent operator translates it into
   ↓
4. K8s primitives (Deployment, Service, ...)   ← what kubelet actually runs
```

When troubleshooting, descend the layers in order: CMF status → FlinkApplication CR → FlinkDeployment CR → Pods/Services.

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
5. An engineer applies a `FlinkSessionJob` and `oc get pods` shows no new Pods. Is something broken? Where do you look first?
6. A job uses RocksDB state backend and processes 50 GB of keyed state. Does the operator create any extra K8s resources (PVC, Volume, etc.) compared to the same job using HashMap state? Why or why not?
7. When you enable HA on a JobManager (replicas ≥ 2, `high-availability: kubernetes`), what specific K8s object appears that didn't exist before?
8. Why does CMF spin up N JobManager + TaskManager pairs for N concurrent statements rather than running them on one shared Session cluster via `FlinkSessionJob`?


## Added Enhancement — Flink Operational Architecture

Topics:
- JobManager responsibilities
- TaskManager responsibilities
- Resource scheduling
- Failure recovery

Failure Scenario:
JobManager unavailable.

Students explain impact and recovery process.
