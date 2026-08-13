# Week 5 — Flink Platform Architecture

**Goal**: every engineer can name the moving parts of a Flink deployment on OpenShift — JobManager, TaskManager, slots, operator, CMF, checkpoint storage, catalog, artifact storage — and trace one job from `git push` to a running JVM.

**Why "Platform Architecture" and not "Infrastructure"**: infrastructure alone sounds like Kubernetes nodes and networking (which Weeks 1-3 cover). This week is about the Flink ecosystem — the operator, runtime, and enterprise components. Application concerns are Week 6.

## Daily plan

| Day | Topic | Focus | Lab |
|---|---|---|---|
| **[Monday](01-Monday/discussion.md)** | Flink Architecture | Why Flink, streaming vs batch, stateful processing, high-level architecture, job lifecycle | [`lab.md`](01-Monday/lab.md) |
| **[Tuesday](02-Tuesday/discussion.md)** | Flink Operator | FlinkDeployment CR, FlinkSessionJob CR, reconciliation, HA, upgrades, K8s resources emitted | [`lab.md`](02-Tuesday/lab.md) |
| **[Wednesday](03-Wednesday/discussion.md)** | Flink Runtime | JobManager, TaskManager, slots, parallelism, resource allocation, checkpoint coordinator | [`lab.md`](03-Wednesday/lab.md) |
| **[Thursday](04-Thursday/discussion.md)** | Enterprise Components | CMF, Catalog, SQL Gateway, DB, artifact storage, HA metadata, savepoint storage — why each exists | [`lab.md`](04-Thursday/lab.md) |
| **[Friday](05-Friday/discussion.md)** | End-to-End Deployment | Developer → git push → CI/CD → CR → operator → Pods → JM → TMs → Kafka (capstone for the week) | [`lab.md`](05-Friday/lab.md) |

## End-of-week deliverable — `week-05-runbook.md`

1. **Flink architecture cheat sheet** — the four pieces (JM / TM / Sources / Checkpoint storage) with one sentence each
2. **FlinkDeployment CR reference** — every spec field mapped to a runtime effect
3. **Slot arithmetic worksheet** — given (replicas, slots/TM, parallelism), predict slot usage
4. **Dependencies map** — for one job, every external system it touches + failure blast radius
5. **End-to-end deploy timing** — annotated timeline of one deploy, "where does the time go"
6. **Personal troubleshooting checklist v5** — append Flink platform-side patterns

## End-of-week review

- [`06-Review/knowledge-check.md`](06-Review/knowledge-check.md) — 10 self-quiz concept questions
- [`06-Review/skill-check.md`](06-Review/skill-check.md) — hands-on tasks that produce runbook artifacts
- [`06-Review/qa.md`](06-Review/qa.md) — 20 Q&A reinforcing the week's key concepts

> Week 6 shifts from platform to application — the DataStream API, state, checkpoints, fault tolerance, and everything a Flink *developer* touches. Once you understand this week's platform, application concepts will have context.
