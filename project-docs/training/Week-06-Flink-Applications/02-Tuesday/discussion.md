# Tuesday — Job Types (Streaming, Batch, Bounded vs Unbounded, Pipelines)

**Time**: ~90 min

## Learning objective

> **Flink treats batch as bounded streaming. What does that mean at the API level, and what shape of workload should be streaming vs batch vs a hybrid pipeline?** By the end of the session you should be able to pick the right job type for a given business problem and know the operational tradeoffs of each.

## Architecture Discussion (~45 min)

### The bounded / unbounded axis

Every Flink data source is one of:

- **Bounded** — the source has an end. `KafkaSource` reading a fixed offset range, an HDFS file, a JDBC query result.
- **Unbounded** — the source runs forever. `KafkaSource` reading `latest` continuously, a Kinesis stream.

Flink can handle both with the same engine. Two settings drive the behavior:

- **`RuntimeExecutionMode.STREAMING`** — pipelined processing, checkpointing, watermarks, long-running.
- **`RuntimeExecutionMode.BATCH`** — blocking / stage-by-stage processing, no checkpointing (uses failure re-runs), no watermarks (sorted input assumed).
- **`RuntimeExecutionMode.AUTOMATIC`** — Flink decides based on the source's boundedness.

`env.setRuntimeMode(RuntimeExecutionMode.BATCH)` is what makes a job batch even if the source could be unbounded.

### Streaming jobs — the default at FCB

Characteristics:

- Source is unbounded (typically Kafka `latest`)
- Watermarks + windows + state
- Checkpoints for fault tolerance
- Runs indefinitely — restart on Pod death, resume from checkpoint

Business use cases:
- Real-time enrichment (parse events, look up reference data, emit enriched events)
- Aggregations on a rolling window (5-min counts, hourly percentiles)
- Detection (fraud patterns, anomalies, threshold alerts)
- Change-data-capture propagation (DB CDC topic → transformed downstream topic)

### Batch jobs — one-shot execution

Characteristics:

- Source is bounded (JDBC query, parquet file, Kafka offset range)
- No watermarks (sorted input assumed)
- No checkpointing (uses task-level retries — a failed task re-runs from its input)
- Job exits (`FINISHED`) when input is consumed

Business use cases:
- End-of-day reconciliation
- Historical backfill (re-process last month of data)
- One-time data migration
- Reporting queries too big for a standard SQL engine

### Bounded-source streaming — the hybrid

You *can* run a bounded source in streaming mode (watermarks + checkpoints + windowed processing). Result: a job that streams through fixed input, applies all the streaming machinery, then exits when input is done. Useful for:

- Historical replay with the same operator DAG as production
- "Batch" jobs where you want checkpointing (large state that would take too long to reprocess on failure)

### Pipelines — chaining multiple jobs

A pipeline is not a Flink concept — it's an orchestration pattern. Two shapes:

- **Kafka-topic-linked pipelines** — Job A writes to Topic X; Job B reads Topic X, writes to Topic Y; Job C reads Topic Y. Loose coupling; each job independently deployable, checkpointable, restartable. FCB standard for streaming.
- **Airflow-orchestrated pipelines** — batch jobs chained by an external scheduler (Airflow, ADO). Each job runs to `FINISHED`, then the next kicks off. Standard for nightly / EOD workflows.

FCB uses topic-linked pipelines for real-time flows and Airflow-driven batch chains for scheduled workflows.

### When to pick which

| Business requirement | Job type |
|---|---|
| "Emit fraud alerts within 5 sec of the event" | Streaming |
| "Every night at 3am, refresh the daily-summary table" | Batch |
| "Backfill last week of enriched events to a new topic" | Streaming with `earliest` starting offset, run once, cancel manually when caught up |
| "Reconcile end-of-day balances against ledger" | Batch |
| "Continuous CDC replication into an analytical store" | Streaming |
| "Compute quarterly-close metrics" | Batch |

### FCB-specific: CMF SQL statements are typically streaming

CMF's `CREATE TABLE ... AS SELECT` SQL statements default to streaming mode. Batch is opt-in via `SET 'execution.runtime-mode' = 'batch';` at the SQL Gateway level. Most FCB workloads today are streaming; batch is used for scheduled analytical jobs.

## Diagram Walkthrough (~30 min)

Draw two pipelines side by side:

- **Streaming pipeline**: Topic → Job A → Topic → Job B → Topic → Job C → Downstream sink. Each job unbounded, always-on, checkpointed.
- **Batch pipeline**: JDBC/file → Job A → intermediate table → Job B → intermediate table → Job C → target table. Airflow-orchestrated, each job one-shot.

For each, name the failure recovery pattern (checkpoint restore vs re-run from last stage).

## Failure Scenarios

| Symptom | Where to look |
|---|---|
| Batch job never exits, keeps consuming | Source not actually bounded (streaming mode set on unbounded source) |
| Streaming job "finished" unexpectedly | Bounded source (like Kafka `latest` with fixed offset range) drained |
| Batch job re-processes data on restart | No checkpointing (expected for batch); the input-level retry is the mechanism |
| Streaming job restart re-processes recent window | Checkpoint from before the window fire; the window will re-fire (idempotent if sink allows) |
| Pipeline stage lags behind upstream | Downstream job's parallelism too low; backpressure propagates upstream |

## Q&A

1. If Flink can handle both bounded and unbounded input, why does batch mode exist at all — what does it save?
2. In a topic-linked streaming pipeline, if Job B goes down for 4 hours, what happens to Job A's output? What happens to Job C when Job B comes back?
3. When would you deliberately run a bounded source in streaming mode instead of batch mode?
4. In FCB's CMF, what's the config setting that switches a SQL statement from streaming to batch?
5. A team asks: "should we use Flink batch or Spark for our nightly EOD job?" What's the framing you use to decide?

## Added Enhancement

Pick one existing streaming job at FCB. Ask: "if we wanted to backfill 30 days of historical data, could we run this same job in batch mode, or would we need to change the code?" Trace what would break (watermark strategy, exactly-once sink transactions, checkpointing behavior).
