# Week 6 — Flink, Multi-Region, DR

**Goal**: deploy + operate Flink jobs in production, understand checkpointing + savepoints + exactly-once, execute the VM-CP → CFK cluster-link migration pattern, and run a full DR drill that exercises everything Weeks 1-5 covered.

## Daily plan

| Day | Topic | Diagram | Lab |
|---|---|---|---|
| **[Monday](01-Monday/discussion.md)** | Flink Architecture on K8s (CMF + Operator + JM + TM) | `60-flink-network.drawio` | [`lab.md`](01-Monday/lab.md) |
| **[Tuesday](02-Tuesday/discussion.md)** | Checkpoints + savepoints + exactly-once | `61-flink-checkpoints.drawio` | [`lab.md`](02-Tuesday/lab.md) |
| **[Wednesday](03-Wednesday/discussion.md)** | Cluster Linking (VM CP → CFK migration) | `62-cluster-link.drawio` | [`lab.md`](03-Wednesday/lab.md) |
| **[Thursday](04-Thursday/discussion.md)** | Multi-Region Clusters (MRC) + rack awareness | `63-mrc-topology.drawio` | [`lab.md`](04-Thursday/lab.md) |
| **[Friday](05-Friday/discussion.md)** | **DR Drill — final exercise** | `64-dr-failover.drawio` | [`lab.md`](05-Friday/lab.md) |

## End-of-week deliverable — `week-06-runbook.md`

1. **One Flink job deployed end-to-end** — CMF statement → CR → JM + TM Pods → checkpoint in NetApp S3
2. **One savepoint round-trip** — stop with savepoint, restart from savepoint, verified continuity
3. **One cluster link** — source-to-destination replication confirmed
4. **DR runbook** — sections A-D from Thursday's lab
5. **DR drill postmortem** — full timeline + lessons
6. **Personal Master Runbook v5 (final)** — the bootcamp's takeaway artifact

✅ Fully written — ready to run.

> The final deliverable, the Personal Master Runbook v5, is what you'll reference for your first six months on call.

## End-of-week review

After Friday, before moving on:

- [`06-Review/knowledge-check.md`](06-Review/knowledge-check.md) — 10 self-quiz concept questions
- [`06-Review/skill-check.md`](06-Review/skill-check.md) — hands-on tasks that produce runbook artifacts
- [`06-Review/qa.md`](06-Review/qa.md) — 20 Q&A reinforcing the week's key concepts
