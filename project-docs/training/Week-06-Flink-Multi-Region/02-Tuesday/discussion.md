# Tuesday — Flink Checkpoints + Savepoints

**Time**: ~90 min
**Diagram**: [`61-flink-checkpoints.drawio`](61-flink-checkpoints.drawio)

## Learning objective

> **How does Flink achieve exactly-once with Kafka?** Understand checkpoints, savepoints, two-phase commit, and recovery.

## Architecture Discussion (~45 min)

Stream processing's hardest problem: you read events, you do work, you produce results. If anything crashes, what guarantees do you have?

Flink's answer is **distributed snapshots** of operator state, combined with two-phase commit on the sinks.

### Checkpoints — the recurring snapshot

Every `checkpoint.interval.ms` (e.g. 60s):

1. JM injects a **checkpoint barrier** into each source
2. Barrier flows through the job graph as a "marker"
3. When an operator sees the barrier, it snapshots its state to the checkpoint store
4. When all operators have snapshotted, the checkpoint is complete
5. JM persists the metadata (which checkpoint ID is the latest complete one)

Properties:
- **Asynchronous** — operator keeps processing while writing the snapshot
- **Aligned** — operator waits until barrier arrives on ALL input streams before snapshotting (exactly-once)
- **Unaligned** (newer) — operator snapshots immediately, captures in-flight records (lower latency but more storage)

### Savepoints — manual, durable snapshot

A **savepoint** is like a checkpoint but explicitly triggered. Used for:

- Job upgrade (stop with savepoint → upgrade jar → start from savepoint)
- Migration to new cluster
- "Rescale": stop, change parallelism, restart from savepoint

Difference from checkpoint:
- Always written to a stable format (forward-compatible)
- Doesn't auto-delete on job stop
- More expensive to take

### The checkpoint store in production

NetApp S3. From the FlinkApplication CR:

```yaml
flinkConfiguration:
  state.backend: rocksdb
  state.checkpoints.dir: s3://netapp/checkpoints/<job>
  state.savepoints.dir: s3://netapp/savepoints/<job>
  s3.endpoint: https://netapp-s3.example.com
  s3.access-key-id: ${AWS_ACCESS_KEY_ID}
  s3.secret-access-key: ${AWS_SECRET_ACCESS_KEY}
```

S3 credentials are provided via a K8s Secret created by ESO from CyberArk.

### Exactly-once with Kafka

Two-phase commit:

1. TM consuming from Kafka source — committed offsets stored in Flink checkpoint (NOT in Kafka)
2. TM producing to Kafka sink — uses Kafka transactions
   - Phase 1 (pre-commit): write to Kafka in transaction, but don't commit
   - Phase 2 (commit): once checkpoint completes, commit the transaction

If TM crashes between phase 1 and phase 2, on recovery Kafka aborts the transaction; the records are not visible to downstream consumers.

If TM crashes between two checkpoints, on recovery Flink restores from the previous checkpoint and re-reads from the committed source offset.

Result: each record from source goes through processing **exactly once** to the sink.

### Failure recovery flow

When JM detects TM failure:

1. JM cancels the job
2. JM finds the latest complete checkpoint
3. JM starts new TMs (operator + K8s replicas)
4. TMs load state from checkpoint
5. Source resets to the offset stored in that checkpoint
6. Processing resumes — duplicate records (since last checkpoint) are reprocessed but absorbed by the transaction logic

### What you can't have

- Exactly-once requires **idempotent or transactional sinks**. Plain HTTP POST to a webhook isn't exactly-once unless the receiver dedupes.
- Exactly-once requires **transactional producer** on Kafka sink. Flink does this by default with Kafka connector v3+.

## Diagram Walkthrough (~30 min)

Open `61-flink-checkpoints.drawio`. Walk:
- Barrier injection at source
- Barrier flowing through operators
- State snapshots being written to NetApp S3
- Completion ack to JM
- Recovery path on failure

## Failure Scenarios

| Symptom | Where to look |
|---|---|
| Checkpoint timeouts | NetApp S3 latency; alignment lag from backpressure |
| Recovery loops — restarting forever | checkpoint can't be loaded; state corruption |
| "Checkpoint expired" warning | checkpoint took longer than `checkpoint.timeout` |
| Duplicate records at sink | sink not transactional, or `delivery-guarantee` not exactly-once |

## Q&A

1. If your job has parallelism 4 and one TM crashes, do you lose 1/4 of your state?
2. Why doesn't Flink rely on Kafka's consumer group offsets?
3. When would you take a savepoint instead of relying on checkpoints?
4. In production, what would break if NetApp S3 went down for 10 minutes?


## Added Enhancement — State Management Troubleshooting

Topics:
- Stateful operators
- State backends
- Checkpoints
- Savepoints

Exercise:
Compare checkpoint recovery versus savepoint recovery.

Students explain when each should be used.
