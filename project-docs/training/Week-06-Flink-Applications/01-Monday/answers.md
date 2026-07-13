# Week 6 Monday — Q&A Answers

Answers to the discussion Q&A in [`discussion.md`](discussion.md#qa).

---

## 1. Why is `keyBy` a partitioning operator, not a transformation — what physically happens between the upstream and downstream operators?

`keyBy` doesn't transform records — it **shuffles them by key**. Physically:

- Upstream operator has *N* parallel instances; downstream has *M*
- For each record, Flink computes `partition = hash(key) % M`
- Record is sent (over the network, or across slot boundaries) to `downstream_instance[partition]`

All records with the same key land on the same downstream instance. That's what makes **keyed state** possible — the operator processing key `X` always sees every event for `X` on that same instance, so per-key state has a home.

This is a physical partitioning boundary — records travel via network shuffle (or at minimum cross the slot boundary if instances co-locate). It also breaks the operator chain — you can't chain through a `keyBy`.

## 2. When would you choose a session window over a tumbling window? Give a concrete example.

**Tumbling window** — fixed-duration, aligned intervals. Every 5 minutes on the clock. Use when the boundary is *time* — "per-hour transaction volume," "per-day error count."

**Session window** — dynamic bounds defined by a gap of inactivity. Window closes when no event for that key arrives within the gap. Use when the boundary is *behavior*, not time.

**Concrete example — user click sessions:**
- User A clicks at T=0, T=5s, T=12s, then goes silent
- Session gap = 30s
- Session window for user A closes at T=42s (12s + 30s gap), containing 3 clicks
- If user A comes back at T=60s, a new session window opens

Session windows are per-key by definition (a session is bounded by that user's own inactivity, not global time). Tumbling windows can be per-key (aggregate per user per hour) or global.

## 3. If a source emits a message at `T=10s` but Flink's watermark is at `T=5s`, what happens to the message when it arrives?

**Nothing unusual — the message is processed normally** and routed to its window (whichever covers T=10s).

The message has timestamp 10s, the watermark is at 5s. Watermark means "we've committed to processing everything up to 5s." A message with timestamp *ahead of* the watermark is on-time.

A **late** message is one whose timestamp is *behind* the watermark — e.g., a message with timestamp 3s arriving now (when watermark is already at 5s). Late messages either get dropped, sent to a side output, or trigger allowed-lateness re-fire of the window depending on job config.

## 4. Exactly-once delivery in the sink requires Kafka transactions. What's the tradeoff — why isn't every job using it?

Requires `transactional.id` on the Kafka producer + a two-phase commit tied to Flink's checkpoint. Costs:

- **Latency** — records aren't visible to consumers until the transaction commits, which happens on checkpoint boundary. If your checkpoint interval is 60s, worst-case sink latency is up to 60s.
- **Throughput** — transactional producer has more per-batch overhead than a plain producer
- **Broker resources** — Kafka's transaction coordinator holds per-transaction state; high-fanout transactional pipelines pressure it
- **Consumer requirement** — downstream consumers must use `isolation.level: read_committed` to see the exactly-once contract

Use exactly-once for financial / correctness-critical sinks. Skip it (use `AT_LEAST_ONCE`) when the sink is idempotent (upsert by primary key, content-addressed blob writes) or when duplicates are tolerable (metrics, logs).

## 5. Between DataStream API and Flink SQL, when do you write a job in Java rather than SQL?

**Java (DataStream API) when:**

- Custom keyed state with per-key timers (`KeyedProcessFunction`)
- Custom source or sink connectors not covered by table connectors
- Non-declarative logic — conditional side outputs, dynamic operator selection, per-record routing rules
- Fine control over serializers, watermark generation strategies, restart handlers
- Integration with libraries that don't have SQL equivalents

**SQL when:**

- Standard aggregations, joins, windowed operations
- Rapid iteration where an analyst (not a Java engineer) authors the pipeline
- CMF SQL Gateway workflow — trainees / analysts submit statements via the CMF UI
- Simple event-time transforms where SQL syntax is more readable than DataStream

At FCB the split is: prod streaming JARs → Java for the deep integrations, CMF SQL statements for lighter-weight per-topic transforms and analytical pipelines.
