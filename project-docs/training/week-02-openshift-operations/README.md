# Week 2 — OpenShift Operations

**Goal**: every engineer can operate the platform — RBAC, operators, monitoring, GitOps, quotas. These are the things CFK depends on; if you can't operate the platform, you can't operate CFK.

## Daily plan

| Day | Topic | Diagram | Lab |
|---|---|---|---|
| **[Monday](monday/discussion.md)** | RBAC (Subject → RoleBinding → Role → Resources) | `20-rbac-binding.drawio` | [`labs/week02/monday.md`](../labs/week02/monday.md) |
| **[Tuesday](tuesday/discussion.md)** | **Operators (the reconciliation loop)** — the most important day before CFK | `21-operator-reconciliation.drawio` | [`labs/week02/tuesday.md`](../labs/week02/tuesday.md) |
| **[Wednesday](wednesday/discussion.md)** | Monitoring (Pod → /metrics → Prometheus → PromQL → Grafana) | `22-monitoring-flow.drawio` | [`labs/week02/wednesday.md`](../labs/week02/wednesday.md) |
| **[Thursday](thursday/discussion.md)** | GitOps (Git → ArgoCD → OpenShift) | `23-gitops.drawio` | [`labs/week02/thursday.md`](../labs/week02/thursday.md) |
| **[Friday](friday/discussion.md)** | **Quotas + Limits — break deployments via exhaustion** (the FCB DEV tracker 2.5 / runbook A3 story) | `24-quota-failures.drawio` | [`labs/week02/friday.md`](../labs/week02/friday.md) |

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
