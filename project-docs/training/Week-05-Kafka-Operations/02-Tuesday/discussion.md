# Tuesday — Consumer Groups + Rebalance

**Time**: ~90 min
**Diagram**: [`51-consumer-group.drawio`](51-consumer-group.drawio)

## Learning objective

> **How does Kafka share work across multiple consumers**, and what happens (good and bad) during a rebalance?

## Architecture Discussion (~45 min)

A **consumer group** = N consumer instances that collectively read all partitions of a topic, each instance getting a non-overlapping subset.

### The mechanics

- Group has a **group ID** (string)
- Kafka assigns each consumer instance a set of partitions
- Each partition is assigned to **exactly one** consumer in the group
- If consumers > partitions, the extras sit idle
- If consumers < partitions, some consumers handle multiple partitions
- Each consumer maintains a **committed offset** per partition in a special internal topic `__consumer_offsets`

### The group coordinator

One broker is elected as the **group coordinator** for each group (based on hashing the group ID). The coordinator:

- Handles JoinGroup / SyncGroup requests
- Tracks heartbeats
- Initiates rebalance when members leave / join / time out

### Rebalance — the unavoidable pause

When membership changes (consumer dies, new consumer joins, partition added), the group **stops consuming briefly** while partitions are reassigned. This is the rebalance window. During it, no progress is made.

Two rebalance protocols:

- **Eager** (default older clients) — all consumers revoke ALL partitions, then receive new assignments. Big pause.
- **Cooperative / incremental** (newer) — only the partitions that need to move are revoked. Smaller pause.

Modern clients should use cooperative.

### Offset commit semantics

- **`enable.auto.commit=true`** — client commits every `auto.commit.interval.ms`. Can lose or duplicate messages on crash.
- **`enable.auto.commit=false`** — your code commits manually after processing. Recommended.

The choice between "commit before processing" (at-most-once) and "commit after processing" (at-least-once) is the most consequential design decision in stream processing.

### Consumer-group patterns in production

- **Flink consumer** — Flink owns its own offset state via checkpoints; uses Kafka source but doesn't trust Kafka offsets as authoritative
- **Connect sink consumers** — Connect manages offsets in `connect-offsets` topic, NOT in `__consumer_offsets`
- **Application consumers** — typical pattern; one consumer group per microservice + topic combination
- **`__consumer_offsets`** topic in production — replicated, retained 7 days; can be a sign of trouble if it grows fast

### What's a "stuck" consumer group?

Symptoms:
- High lag (offset committed << log end)
- No commit progress over time
- Frequent rebalance churn (group state oscillating)

Causes:
- Consumer crashing without committing
- Consumer too slow (processing > polling rate, `max.poll.interval.ms` exceeded → kicked out → rebalance → repeat)
- Group coordinator unavailable

## Diagram Walkthrough (~30 min)

Open `51-consumer-group.drawio`. Trace one rebalance event:

- Consumer-A leaves
- Coordinator detects heartbeat timeout
- Coordinator triggers rebalance
- Consumer-B + C revoke their partitions
- Coordinator computes new assignment
- B + C get new partitions
- Consumption resumes

## Failure Scenarios

| Symptom | Likely cause |
|---|---|
| Consumer lag growing | consumer too slow OR producer faster than consumer can handle |
| Rebalance every 30s | consumer exceeding `max.poll.interval.ms` |
| Offsets not advancing | auto-commit off + code never commits |
| `OffsetOutOfRangeException` | committed offset < log start (retention deleted data) |

## Q&A

1. If you have 6 partitions and 10 consumers, what happens?
2. Why does a Flink job not care about Kafka's committed offsets?
3. If `__consumer_offsets` topic loses ISR, what fails first?
4. How would you find the "noisiest" consumer group in production — the one rebalancing most?


## Added Enhancement — Consumer Group Troubleshooting

Topics:
- Rebalancing
- Offset commits
- Lag analysis
- Static membership

Exercise:
Investigate consumer lag using consumer group commands and metrics.

Failure Scenario:
Consumer lag grows despite healthy brokers.
