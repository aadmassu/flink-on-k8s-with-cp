# Week 1 — OpenShift Foundations

**Goal**: every engineer can deploy a stateless + stateful app, expose them with Services + Routes, mount config + storage, and triage a failed Pod by Friday EOD.

## Daily plan

| Day | Topic | Diagram (in `../diagrams/drawio/`) | Lab |
|---|---|---|---|
| **[Monday](monday/discussion.md)** | Kubernetes Architecture | `01-k8s-architecture.drawio` | [`labs/week01/monday.md`](../labs/week01/monday.md) |
| **[Tuesday](tuesday/discussion.md)** | Pods · Deployments · StatefulSets | `02-k8s-components.drawio` | [`labs/week01/tuesday.md`](../labs/week01/tuesday.md) |
| **[Wednesday](wednesday/discussion.md)** | Services + Routes (traffic flow) | `10-services-routes-traffic-flow.drawio` | [`labs/week01/wednesday.md`](../labs/week01/wednesday.md) |
| **[Thursday](thursday/discussion.md)** | Storage (PVC + PV + StorageClass) | `11-storage-chain.drawio` | [`labs/week01/thursday.md`](../labs/week01/thursday.md) |
| **[Friday](friday/discussion.md)** | **Troubleshooting Workflow — break-things day** | `12-troubleshooting-tree.drawio` | [`labs/week01/friday.md`](../labs/week01/friday.md) |

## End-of-week deliverable

Each engineer commits a brief `week-01-runbook.md` under `deliverables/<engineer-name>/` covering:

1. `oc login` + how to list nodes / Pods / Services / Routes / ConfigMaps / Secrets / PVCs in a project
2. How to deploy a stateless app (Deployment) and a stateful app (StatefulSet) and observe the difference in restart behavior
3. How to expose a Deployment to external traffic via Service + Route
4. How to mount a ConfigMap + Secret + PVC into a Pod
5. **The personal troubleshooting checklist** they used Friday to investigate failures (3–5 things they check, in order)
6. Three things that surprised them about OpenShift vs vanilla K8s

The Friday troubleshooting checklist becomes the foundation of every subsequent week's troubleshooting story. Keep it short, real, and copy-paste-ready.
