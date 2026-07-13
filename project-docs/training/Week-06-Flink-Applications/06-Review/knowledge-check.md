# Week 6 — Knowledge Check

Concept-level self-quiz. Answer in your own words.

## DataStream API (Monday)

1. Why is `keyBy` a partitioning operator, not a transformation?
2. When would you use a session window over a tumbling window?
3. What does "watermark" mean, and what happens if a message arrives before its window's watermark advance?

## Job Types (Tuesday)

4. If Flink can handle both bounded and unbounded input, why does batch mode exist at all?
5. In a topic-linked streaming pipeline, if Job B is down 4 hours, what happens to Job A's output?

## State Management (Wednesday)

6. Physical difference between `ValueState<T>` and `MapState<K,V>` in RocksDB?
7. Why is HashMap state backend faster than RocksDB, and why isn't it the default in production?
8. Why is state TTL a job-level concern rather than automatic?

## Fault Tolerance (Thursday)

9. Specific difference between a checkpoint and a savepoint at the *storage* level?
10. Under `failure-rate` restart strategy, when does the job actually fail vs restart?

## Production Operations + Capstone (Friday)

11. Given the 6-week capstone diagram, walk one hop where the platform (Weeks 1-4) enables the application (Weeks 5-6) — top to bottom.

---

Self-scoring: **10+ correct** = ready for on-call; **8-9** = strong; **≤ 7** = revisit weak areas.
