# Week 6 — Flink Applications

**Goal**: every engineer can read a Flink DataStream (or SQL) job, understand its state model, reason about checkpoints and savepoints, and operate the job in production — upgrade, scale, debug, restore.

**Why applications after platform**: by now (post-Week 5) you know how Flink is *built*. This week is how Flink *does the work* — the DataStream API, state management, fault tolerance, and the day-2 operations any Flink engineer performs.

## Daily plan

| Day | Topic | Focus | Lab |
|---|---|---|---|
| **[Monday](01-Monday/discussion.md)** | DataStream API | Sources, operators, sinks, watermarks, windows | [`lab.md`](01-Monday/lab.md) |
| **[Tuesday](02-Tuesday/discussion.md)** | Job Types | Streaming, batch, bounded vs unbounded, pipelines | [`lab.md`](02-Tuesday/lab.md) |
| **[Wednesday](03-Wednesday/discussion.md)** | State Management | Keyed state, operator state, RocksDB, state backend, state lifecycle, TTL | [`lab.md`](03-Wednesday/lab.md) |
| **[Thursday](04-Thursday/discussion.md)** | Fault Tolerance | Checkpoints, savepoints, restart strategies, exactly-once, at-least-once, recovery | [`lab.md`](04-Thursday/lab.md) |
| **[Friday](05-Friday/discussion.md)** | Production Operations + 6-Week Capstone | Upgrades, scaling, rolling deploys, cancel-with-savepoint, restore, debugging, reading Flink UI, common failures — plus the full-stack capstone diagram tying Weeks 1-6 | [`lab.md`](05-Friday/lab.md) |

## End-of-week deliverable — `personal-master-runbook.md` (the final artifact)

The 6-week bootcamp deliverable. 10 pages, one per layer of the Friday capstone diagram (Kafka → Source → Operators → Coordinator → JM → TMs → Operator → K8s → PKI/TLS/OAuth → NetApp S3/Artifactory). Each page: "what breaks / how to detect / how to fix." This is what you reference at 3am on call for the next six months.

## End-of-week review

- [`06-Review/knowledge-check.md`](06-Review/knowledge-check.md) — 10 self-quiz concept questions
- [`06-Review/skill-check.md`](06-Review/skill-check.md) — hands-on tasks that produce runbook artifacts
- [`06-Review/qa.md`](06-Review/qa.md) — 20 Q&A reinforcing the week's key concepts

## The 6-week progression (Friday capstone summary)

By the end of this week, you can trace one Flink job through EVERY layer this bootcamp covered:

```
Kafka Topic  →  Source  →  Map  →  KeyBy  →  Window  →  Aggregate  →  Sink  →  Kafka Topic
                                                                                     │
                                     ─── Checkpoint Barrier ────►────►────►────►────►
                                                                                     │
                                     JobManager coordinates TaskManagers
                                     Flink Operator creates Pods
                                     Kubernetes schedules everything
                                     TLS on every hop; OAuth to MDS; PKI + cert-manager
                                     Inside a ROSA-on-AWS or on-prem cluster
```

Read Friday's discussion.md for the full annotated diagram — that's the diagram to walk into your next production incident with.
