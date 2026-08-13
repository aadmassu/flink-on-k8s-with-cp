# Week 1 — OpenShift Foundations

**Goal**: every engineer can deploy a stateless + stateful app, expose them with Services + Routes, mount config + storage, and triage a failed Pod by Friday EOD.

## Daily plan

| Day | Topic | Diagram (in `../diagrams/drawio/`) | Lab |
|---|---|---|---|
| **[Monday](01-Monday/discussion.md)** | Kubernetes Architecture | `01-k8s-architecture.drawio` | [`lab.md`](01-Monday/lab.md) |
| **[Tuesday](02-Tuesday/discussion.md)** | Pods · Deployments · StatefulSets | `02-k8s-components.drawio` | [`lab.md`](02-Tuesday/lab.md) |
| **[Wednesday](03-Wednesday/discussion.md)** | Services + Routes (traffic flow) | `10-services-routes-traffic-flow.drawio` | [`lab.md`](03-Wednesday/lab.md) |
| **[Thursday](04-Thursday/discussion.md)** | Storage (PVC + PV + StorageClass) | `11-storage-chain.drawio` | [`lab.md`](04-Thursday/lab.md) |
| **[Friday](05-Friday/discussion.md)** | **Troubleshooting Workflow — break-things day** | `12-troubleshooting-tree.drawio` | [`lab.md`](05-Friday/lab.md) |

## End-of-week deliverable

Each engineer commits a brief `week-01-runbook.md` under `deliverables/<engineer-name>/` covering:

1. `oc login` + how to list nodes / Pods / Services / Routes / ConfigMaps / Secrets / PVCs in a project
2. How to deploy a stateless app (Deployment) and a stateful app (StatefulSet) and observe the difference in restart behavior
3. How to expose a Deployment to external traffic via Service + Route
4. How to mount a ConfigMap + Secret + PVC into a Pod
5. **The personal troubleshooting checklist** they used Friday to investigate failures (3–5 things they check, in order)
6. Three things that surprised them about OpenShift vs vanilla K8s

The Friday troubleshooting checklist becomes the foundation of every subsequent week's troubleshooting story. Keep it short, real, and copy-paste-ready.

## End-of-week review

After Friday, before moving on:

- [`06-Review/knowledge-check.md`](06-Review/knowledge-check.md) — 10 self-quiz concept questions
- [`06-Review/skill-check.md`](06-Review/skill-check.md) — hands-on tasks that produce runbook artifacts
- [`06-Review/qa.md`](06-Review/qa.md) — 20 Q&A reinforcing the week's key concepts
