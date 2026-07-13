# Week 6 Wednesday — Q&A Answers

Answers to the discussion Q&A in [`discussion.md`](discussion.md#qa).

---

## 1. Physical difference between `ValueState<T>` and `MapState<K,V>` when stored in RocksDB?

- **`ValueState<T>`** — one RocksDB entry per Flink key. RocksDB key = `flink_key + operator_state_id`; RocksDB value = serialized `T`. To update, Flink reads the full `T`, mutates in memory, writes the full `T` back.

- **`MapState<K,V>`** — many RocksDB entries per Flink key. RocksDB has one entry per `(flink_key, user_map_key)` tuple. Reading a single map entry is a point lookup; writing one entry writes one RocksDB entry. Iterating the map scans a prefix.

**Practical implication**: if your value would otherwise be a large `Map<K,V>` inside a `ValueState`, use `MapState` instead. You get per-map-key access without paying to serialize the whole map every access.

Example: tracking per-user "seen products" (potentially thousands of products per user) → `MapState<ProductId, Timestamp>`. Adding one product touches one RocksDB entry. As a `ValueState<HashMap<ProductId, Timestamp>>` it would serialize/deserialize the whole map every access.

## 2. Why does HashMap state backend get faster reads than RocksDB, and why isn't it the default in production?

**Faster because:**

- All state is in JVM heap — no disk I/O per access
- No serialize/deserialize round-trip per read/write (RocksDB requires both because values live as byte arrays on disk)
- No RocksDB block cache miss penalty

**Not default in production because:**

- **State size bounded by TM heap** — 10s of GB max per TM, and you're now competing with GC for that heap. Job state that grows beyond heap OOMs the TM.
- **Full-state checkpoints only** — HashMap doesn't support incremental checkpoints. On checkpoint, the entire state is serialized and uploaded to S3. Slow at scale, expensive network.
- **GC pressure** — large object graphs pin heap regions, cause long GC pauses during checkpoint alignment

RocksDB trades per-access speed for scalability (TB per TM, incremental checkpoints, low heap footprint).

Use HashMap for small stateful jobs where latency matters more than scale (test jobs, small deduplication caches). Use RocksDB for anything production-facing.

## 3. If a TM dies mid-checkpoint, what happens to the checkpoint-in-progress? Does the job lose state changes since the last successful checkpoint?

**Checkpoint-in-progress is aborted** — the JM's Checkpoint Coordinator marks it failed when it detects the missing TM heartbeat. Any partial state files uploaded to S3 by other TMs for that checkpoint are orphaned (Flink cleans them up on next successful checkpoint or per retention).

Job restarts (per its restart strategy) and rewinds to the **last successful checkpoint**. State changes made after that last checkpoint but before TM death are **not preserved in Flink state**, but they are **re-derived** by replaying source records from the Kafka offsets stored in that last checkpoint.

Not "lost" in the data-loss sense (assuming source is replayable) — the records are reprocessed. The invariant Flink preserves: exactly-once state semantics *end to end*, given a replayable source and a checkpointed offset.

## 4. Operator state redistributes on rescale. Keyed state redistributes on hash. In which scenario is redistribution *problematic*?

**Operator state redistribution** (list-style): the framework redistributes list items across the new parallelism. Problematic when items are correlated — e.g., a stateful join operator maintaining "buffered records from side A" and "buffered records from side B" as two separate operator state lists. If the redistribution splits them across different instances, joins break.

Fix: use `UnionListState` (all instances see all items on restore) or keyed state with a synthetic join key.

**Keyed state redistribution** (by hash): fine in principle — each key still ends up on exactly one instance. Problematic when keys are **extremely skewed**. Example: 10M events, 99% share the key `NULL`. Rescaling from parallelism 4 → 8 still puts all NULL-keyed traffic on one instance. Rescaling doesn't fix skew.

Fix: pre-key with a random salt (`(salt, key)` for aggregation, then final aggregation on `key`) — the classic "two-stage aggregation" trick.

## 5. Why is state TTL a job-level concern rather than automatic?

Because retention policy is **workload-specific and business-driven**:

- "Session state expires after 30 min of inactivity" — behavioral
- "Fraud detection state kept for 90 days" — regulatory
- "Aggregation state persists forever" — analytical

Flink can't infer this from operator semantics. If it defaulted to auto-TTL, it would either be **too aggressive** (silently drop still-valid state → wrong outputs) or **too permissive** (never expire → disk fills eventually).

Flink provides the mechanism (`StateTtlConfig` on each state descriptor: TTL duration, update strategy, visibility strategy, cleanup strategy). The job chooses the policy per state. It's the state analog of "how long should we keep this record" in a database — application-owned, not infrastructure-owned.
