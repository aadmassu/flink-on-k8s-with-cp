# Week 6 Tuesday — Q&A Answers

Answers to the discussion Q&A in [`discussion.md`](discussion.md#qa).

---

## 1. If Flink can handle both bounded and unbounded input, why does batch mode exist at all — what does it save?

Batch mode enables **bounded-input-only optimizations** that streaming can't use:

- **Sort-based (blocking) shuffles** — batch materializes the full input for a stage, sorts it, then hands to the next stage. Streaming uses pipelined shuffles that pass records as they arrive.
- **No watermarks / late-data machinery** — bounded input has a definite end, no need to reason about "how late is late"
- **Aggressive join reordering** — planner has full-input statistics, can pick optimal join order
- **Resource lifecycle** — allocate TMs, run to completion, tear down. Streaming keeps TMs up forever.

Practical savings: lower memory per stage (materialize on disk vs pipeline in-memory), fewer failure-recovery complications, faster planner passes for large SQL.

If you run bounded input in streaming mode it *works* — you just leave those optimizations on the table.

## 2. In a topic-linked streaming pipeline, if Job B goes down for 4 hours, what happens to Job A's output? What happens to Job C when Job B comes back?

**Job A** keeps producing to its output topic — its consumers (B) not committing offsets is Job B's concern, not A's. Kafka buffers the records subject to retention settings (default 7d).

**Job C** stops receiving new data on B's output topic. C's own source lag grows; C's watermarks stall; C's windows don't fire on new data.

**When B comes back**:
- B resumes from its last committed consumer offset on A's output topic
- B replays 4h of accumulated data, catches up, emits its outputs
- C sees a burst of records on its input topic and processes them
- If B's checkpointed offset is older than A's topic retention, B has *lost* the wrapped-around records — a real data loss event

Design implication: sizing Kafka retention on B's input topic must consider max acceptable B downtime. Common pattern: 7-day retention gives you a weekend + a business week to recover.

## 3. When would you deliberately run a bounded source in streaming mode instead of batch mode?

- **Testing streaming logic against a fixed dataset** — same operator DAG, same watermark strategy, same checkpoint behavior, but with reproducible input. Great for CI tests.
- **Replay from a bounded archive Kafka topic** — a topic where writes have stopped (topic marked read-only, or all producers gone). Data is bounded but you want streaming semantics for consistency with the live pipeline.
- **Uniform operator behavior across environments** — dev uses a small bounded file, prod uses live Kafka, but the operator chain is identical. Avoids "works in batch, breaks in streaming" surprises.

## 4. In FCB's CMF, what's the config setting that switches a SQL statement from streaming to batch?

`execution.runtime-mode: BATCH` set on the SQL statement / statement session. Flink SQL detects bounded vs unbounded from the source connector's metadata by default, but this config forces the mode explicitly.

Corollary: `SET 'execution.runtime-mode' = 'STREAMING'` (or leave default) forces streaming behavior even on bounded input, useful for the testing scenario in question 3.

## 5. Should we use Flink batch or Spark for a nightly EOD job? Framing:

**Ask three questions:**

1. **Does the batch job share source data / state with our streaming jobs?** If yes → Flink batch. Reusing schemas, connectors, checkpoint storage, engineering skills across streaming + batch pays off.
2. **Is the batch workload pure warehouse ETL at massive scale?** If yes → Spark is more mature here. Delta Lake, MLlib, wide SQL optimizer for TB+ warehouse joins.
3. **Who owns the code?** If the streaming team owns it → Flink batch (one engine to know). If a data engineering team already lives in Spark → probably Spark (skill match matters more than tech match).

At FCB the platform is streaming-first, and the data pipelines are built around Kafka + Flink. Default answer for FCB is **Flink batch** unless the specific workload hits one of Spark's dominant strengths (MLlib training, Delta Lake operations, warehouse queries needing Spark SQL's optimizer). Avoid running two engines "just because" — the operational surface doubles.
