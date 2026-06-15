# Week 2 — OpenShift Operations

**Goal**: every engineer can operate the platform — RBAC, operators, monitoring, GitOps, quotas. These are the things CFK depends on; if you can't operate the platform, you can't operate CFK.

## Daily plan

| Day | Topic | Diagram | Lab |
|---|---|---|---|
| **[Monday](01-Monday/discussion.md)** | RBAC (Subject → RoleBinding → Role → Resources) | `20-rbac-binding.drawio` | [`lab.md`](01-Monday/lab.md) |
| **[Tuesday](02-Tuesday/discussion.md)** | **Operators (the reconciliation loop)** — the most important day before CFK | `21-operator-reconciliation.drawio` | [`lab.md`](02-Tuesday/lab.md) |
| **[Wednesday](03-Wednesday/discussion.md)** | Monitoring (Pod → /metrics → Prometheus → PromQL → Grafana) | `22-monitoring-flow.drawio` | [`lab.md`](03-Wednesday/lab.md) |
| **[Thursday](04-Thursday/discussion.md)** | GitOps (Git → ArgoCD → OpenShift) | `23-gitops.drawio` | [`lab.md`](04-Thursday/lab.md) |
| **[Friday](05-Friday/discussion.md)** | **Quotas + Limits — break deployments via exhaustion** (the DEV tracker 2.5 / runbook A3 story) | `24-quota-failures.drawio` | [`lab.md`](05-Friday/lab.md) |

## End-of-week deliverable

Each engineer commits to `deliverables/<engineer-name>/week02/`:

1. **RBAC sandbox** — a working read-only "viewer" Role + RoleBinding for their own project; commands that verify it works
2. **Operator inspection** — install any community Operator (e.g. cert-manager Operator) and write up what the reconciliation loop did (5 sentences: what CR you created, what objects the Operator generated, how you'd debug if it didn't reconcile)
3. **One Prometheus query + one Grafana panel** built against the cluster's monitoring stack
4. **One ArgoCD Application** managing one of their Week 1 deployments via GitOps
5. **Quota exhaustion writeup** — break a deployment via quota, capture the symptom + the troubleshooting steps that named the cause
6. **Personal troubleshooting checklist v2** — append to Week 1 Friday's checklist with the new patterns from Week 2

## Status of this week

✅ Fully written — ready to run Week 2 Monday. Five discussions, five labs, five diagrams.

## End-of-week review

After Friday, before moving on:

- [`06-Review/knowledge-check.md`](06-Review/knowledge-check.md) — 10 self-quiz concept questions
- [`06-Review/skill-check.md`](06-Review/skill-check.md) — hands-on tasks that produce runbook artifacts
- [`06-Review/qa.md`](06-Review/qa.md) — 20 Q&A reinforcing the week's key concepts
