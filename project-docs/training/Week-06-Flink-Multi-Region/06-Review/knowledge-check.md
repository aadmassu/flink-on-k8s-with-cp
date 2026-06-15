# Week 6 — Knowledge Check

## Flink + multi-region + DR (10 concept questions)

1. Walk the Flink deployment topology in production: CMF → Operator → JM/TM. Who does what?
2. What's the difference between a JobManager and a TaskManager? How do you scale each?
3. Define checkpoint, savepoint, and watermark — and when each one matters.
4. Walk Flink's exactly-once guarantee with Kafka source + Kafka sink.
5. State backend choices: in-memory vs RocksDB. When does  the platform use which?
6. Cluster linking — explain why it preserves consumer offset positions.
7. The VM CP → CFK migration cutover steps (per env). What's the safe order?
8. MRC (single cluster across regions) vs cluster-linked dual cluster — which does  the platform use today and why?
9. The 4-layer mental model (workloads → Kafka → CFK → OCP/AWS) — when triaging, do you go top-down or bottom-up? Why?
10. RTO vs RPO — and what the platform's targets are (or should be) for prd-1 region loss.

## Self-scoring

- 8-10: ready to support Flink + multi-region on call
- 5-7: re-read checkpoints (Tue) + cluster linking (Wed); these have the most surprises
- < 5: revisit Week 6 fully — DR scenarios are non-negotiable on-call material
