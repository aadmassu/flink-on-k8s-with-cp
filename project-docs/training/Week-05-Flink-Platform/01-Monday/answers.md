# Week 5 Monday — Q&A Answers

Answers to the discussion Q&A in [`discussion.md`](discussion.md#qa). Work through the questions on your own first — this file is the self-check.

---

## 1. What makes a Flink job "stateful" — where does the state physically live between events?

State lives inside the **operator instance** on the TaskManager JVM. Between events it sits in one of:

- **JVM heap** — HashMap state backend
- **RocksDB on local TM disk** — RocksDB state backend (the FCB default for anything non-trivial)

The event itself is not "the state." The state is the *accumulator* the operator maintains — a running count, joined record, in-progress window contents, keyed timer. On checkpoint interval Flink snapshots that state asynchronously to durable storage (NetApp S3 at FCB). On TM restart the operator reads back from the last successful checkpoint and resumes.

## 2. If Flink treats batch as bounded streaming, why does the SQL syntax often distinguish them?

Because bounded input unlocks optimizations that streaming can't use:

- **Sort-based (blocking) shuffles** instead of pipelined ones
- **Aggressive join reordering** with full-input statistics
- **No watermarks, no late-data handling** — the input has a definite end
- **Batch-friendly resource scheduling** (bring up TMs, run to completion, tear down)

The engine is the same but the *execution plan* differs. Flink SQL signals batch vs streaming via `execution.runtime-mode: BATCH` (statement/session level) or the source's `IS_BOUNDED` metadata. If you leave a bounded input in streaming mode, it works — but you leave batch optimizations on the table.

## 3. What's the smallest possible Flink deployment (how many JMs, how many TMs, how many slots) that can run one keyed-window job?

**1 JM + 1 TM + 1 slot**.

At parallelism 1, the whole DAG (source → keyBy → window → sink) chains into a single slot on the single TM. HA needs 2 JMs (one leader, one standby). Production practice recommends at least 2 TMs for redundancy, but the *smallest possible* answer is 1/1/1.

## 4. Who submits a job to the JobManager in FCB production — the developer, a CI pipeline, or CMF?

Depends on the job type:

- **SQL statements** — CMF SQL Gateway. Developer authors SQL in CMF UI or via `cmfctl`, CMF submits to a session cluster's JM.
- **Application JARs** — Azure DevOps pipeline applies a `FlinkDeployment` CR to OpenShift. The Flink Kubernetes Operator translates the CR into a JM job submission via the JM's REST endpoint.

Developers do not submit directly to JM in production. Direct `flink run` from a laptop is a dev-only pattern.

## 5. Name two things a JobManager does that a TaskManager doesn't.

Any two of:

- Coordinates checkpoints (broadcasts barriers, aggregates handles, marks the checkpoint complete)
- Owns job scheduling and slot allocation across TMs
- Serves the Flink REST API + Web UI
- Manages HA leader election (K8s Lease / ConfigMap)
- Decides restart-strategy actions on operator failure

TMs execute operator code; JMs orchestrate.
