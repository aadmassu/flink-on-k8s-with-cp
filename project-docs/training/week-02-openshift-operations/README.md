# Week 2 — OpenShift Operations

**Goal**: every engineer can operate the platform — RBAC, operators, monitoring, GitOps, quotas. These are the things CFK depends on; if you can't operate the platform, you can't operate CFK.

## Daily plan

| Day | Topic | Diagram anchor | Friday-style break-things? |
|---|---|---|---|
| **Monday** | RBAC (User → RoleBinding → Role → Resources) | TBD: `20-rbac-binding.drawio` | — |
| **Tuesday** | **Operators** (the most important day before CFK — reconciliation loop) | TBD: `21-operator-reconciliation.drawio` | — |
| **Wednesday** | Monitoring (Application → Prometheus → Grafana) | TBD: `22-monitoring-flow.drawio` | — |
| **Thursday** | GitOps (Git → ArgoCD → OpenShift) | TBD: `23-gitops.drawio` | — |
| **Friday** | **Quotas + Limits — break deployments via exhaustion** (this is exactly the FCB DEV ResourceQuota story from tracker 2.5) | TBD: `24-quota-failures.drawio` | YES |

## End-of-week deliverable

Each engineer commits to `deliverables/<engineer-name>/week02/`:

1. **RBAC sandbox** — a working read-only "viewer" Role + RoleBinding for their own project; commands that verify it works
2. **Operator inspection** — install any community Operator (e.g. cert-manager Operator) and write up what the reconciliation loop did (5 sentences: what CR you created, what objects the Operator generated, how you'd debug if it didn't reconcile)
3. **One Prometheus query + one Grafana panel** built against the cluster's monitoring stack
4. **One ArgoCD Application** managing one of their Week 1 deployments via GitOps
5. **Quota exhaustion writeup** — break a deployment via quota, capture the symptom + the troubleshooting steps that named the cause
6. **Personal troubleshooting checklist v2** — append to Week 1 Friday's checklist with the new patterns from Week 2

## Status of this week

📝 Day-level discussion + lab content **to be written** before Week 2 Monday. The topics and the break-things Friday are locked in per the curriculum review.
