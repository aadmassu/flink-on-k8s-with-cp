# Week 6 — Q&A Bank

20 questions reinforcing the week.

## Monday — DataStream API

1. Why is `keyBy` a partitioning operator, not a transformation — what happens between upstream and downstream?
2. When would you use a session window over a tumbling window?
3. If a source emits an event at `T=10s` but the watermark is at `T=5s`, what happens when it arrives?
4. Exactly-once delivery in the sink requires Kafka transactions — what's the tradeoff?
5. Between DataStream API and Flink SQL, when do you write Java rather than SQL?

## Tuesday — Job Types

6. If Flink can handle both bounded and unbounded input, why does batch mode exist?
7. In a topic-linked pipeline, if Job B is down 4 hours, what happens to Job A?
8. When would you deliberately run a bounded source in streaming mode?
9. In CMF, what's the config that switches a SQL statement from streaming to batch?
10. Flink batch vs Spark for a nightly EOD job — how do you decide?

## Wednesday — State Management

11. Physical difference between `ValueState<T>` and `MapState<K,V>` in RocksDB?
12. Why does HashMap state backend get faster reads than RocksDB, and why isn't it the default in production?
13. If a TM dies mid-checkpoint, what happens to the checkpoint-in-progress?
14. Operator state redistributes on rescale, keyed state on hash. When is this problematic?
15. Why is state TTL a job-level concern rather than automatic?

## Thursday — Fault Tolerance

16. Specific difference between a checkpoint and a savepoint at the *storage* level?
17. Under EXACTLY_ONCE + Kafka sink, if TM dies mid-transaction, what does Kafka's transaction log show?
18. Why does checkpoint interval affect recovery time — what does a longer interval cost?
19. Under `failure-rate`, if the job fails 3× in 4 min then a 4th time, does it restart?
20. When would you deliberately choose AT_LEAST_ONCE over EXACTLY_ONCE?

---

## Bonus — the capstone question (Friday)

Given the 6-week capstone diagram: walk one hop where the platform (Weeks 1-4) enables the application (Weeks 5-6). Then reverse and walk it bottom to top. If both directions read cleanly, you're ready.
