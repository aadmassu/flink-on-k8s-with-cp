# Week 6 Thursday — Q&A Answers

Answers to the discussion Q&A in [`discussion.md`](discussion.md#qa).

---

## 1. What's the *specific* difference between a checkpoint and a savepoint at the storage level — files different, or just metadata?

**Same underlying file layout** — same state serializer, same operator-state file format. The differences are lifecycle + metadata:

- **Incrementality**: checkpoints can be *incremental* on RocksDB (only changed SSTables uploaded per checkpoint, deltas chained). Savepoints are *always full* (self-contained snapshot).
- **Retention ownership**: checkpoints are Flink-managed — Flink cleans them per `state.checkpoints.num-retained` (default 1). Savepoints are user-managed — Flink never deletes them; you own the retention.
- **Portability**: savepoints are portable across Flink versions (compatible state schemas) and across job graphs. Checkpoints assume the same Flink version and same job binary.
- **Location by convention**: `checkpoints/` vs `savepoints/` prefix in S3 — same bucket, different logical trees.

A savepoint restored on the same job is functionally equivalent to a checkpoint restore — the difference is a *management contract*, not a file format.

## 2. If EXACTLY_ONCE + Kafka sink, TM dies mid-transaction — what does Kafka's transaction log show?

Eventually shows **ABORT** for that transaction ID.

Sequence:

1. Flink transactional producer started `txnA` with `transactional.id: flink-sink-N`, wrote records with pending markers (invisible to `read_committed` consumers)
2. TM dies before the checkpoint's `commit` phase completes
3. Kafka's transaction coordinator waits for `transaction.timeout.ms` (default 15 min)
4. On timeout, coordinator writes `ABORT` for `txnA` — the pending records are marked aborted

**On Flink restart**:

- New producer initializes with the same `transactional.id`, which *fences* any lingering producer instance (older-epoch producers are rejected)
- Flink starts a fresh transaction from the last successful checkpoint's state + source offsets
- Records from `txnA` were never visible to `read_committed` consumers, so no consumer double-processed anything

**Consumer requirement**: the reading side must use `isolation.level: read_committed` to honor the transaction boundaries. Under `read_uncommitted`, aborted-transaction records ARE visible — exactly-once is broken.

## 3. Why does checkpoint interval affect recovery time — what specifically does a longer interval cost?

Recovery = restore state from last checkpoint + replay source from checkpoint-stored offsets. The longer the interval, the more source data has to be replayed on restart.

**Longer interval costs:**

- **Higher recovery time (RTO)** — more Kafka records to replay before the job catches up to now
- **Longer window of state divergence** — if you restart on Wednesday from Tuesday's checkpoint, 24h of state changes must be re-derived by replay

**Shorter interval costs:**

- **More S3 I/O** — every checkpoint uploads deltas (or full state)
- **More checkpoint-alignment pressure** — barriers flow through the DAG more often, aligning at joins imposes latency
- **Higher storage cost** — retention of multiple recent checkpoints multiplies with frequency
- **Backpressure risk** — if checkpoints don't complete before the next one starts, the coordinator falls behind

Tradeoff: pick an interval that meets your RTO with acceptable steady-state cost. Common FCB range: 30s–5m depending on state size and latency tolerance.

## 4. Under `failure-rate` restart strategy, 3 fails in 4 min then 4th — restart?

**Depends on the exact config** (`failure-rate-interval` and `max-failures-per-interval`).

- If configured as "3 failures per 4-minute window": the 4th failure within that window exceeds the rate → job is `FAILED` (no restart)
- If configured as "3 failures per 5-minute window": at the moment of the 4th failure, only 3 failures are within the last 5 min (assuming the first was ~4 min ago) — still within rate → restart

The interval is a **sliding window** — Flink counts failures within the trailing interval, not a fixed reset. So the answer hinges on both the interval and whether the earliest of the 3 failures has aged out by the time the 4th arrives.

Common FCB config: `max-failures-per-interval: 3`, `failure-rate-interval: 5 min`, `delay: 10 s`. Under that config, 3 fails within 4 min then a 4th → all four are within the sliding 5 min window → **job FAILED**.

## 5. When would you deliberately choose AT_LEAST_ONCE over EXACTLY_ONCE?

- **Sink is idempotent** — writing by primary key upsert (RDBMS, Redis SET), content-addressed writes to object store, HTTP PUT with idempotency keys. Duplicates are neutralized downstream at no cost.
- **Downstream tolerates duplicates** — metrics aggregation, log ingestion, ML training datasets. A duplicate row doesn't matter enough to justify the transaction overhead.
- **Latency dominates correctness** — records must be visible within seconds, transactional commit latency (checkpoint-boundary bound) is unacceptable. Real-time ad tech, live dashboards.
- **Kafka transactions unavailable or expensive** — some sinks aren't transactional (older HTTP endpoints, some databases). AT_LEAST_ONCE is the only option; you make duplicates safe at the sink level.
- **Kafka broker overhead** — high-fanout transactional pipelines put load on the transaction coordinator. If exactly-once isn't worth that cost for a particular workload, skip it.

EXACTLY_ONCE is the *default* to reach for when you can. AT_LEAST_ONCE is a conscious tradeoff when the sink or the latency budget forces it.
