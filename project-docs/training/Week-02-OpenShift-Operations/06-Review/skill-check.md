# Week 2 — Skill Check

Each task produces a runbook artifact. Training project only.

## Task 1 — Build a minimal RBAC stack (Mon)

1. Create a ServiceAccount `app-reader`
2. Create a Role granting `get,list,watch` on Pods + ConfigMaps in your namespace
3. Bind via RoleBinding
4. From a Pod running with that SA, prove it can `kubectl get pods` but cannot `kubectl get secrets`

**Verifies**: Subject → Role → RoleBinding chain (Mon)

## Task 2 — SCC inspection (Mon, plus original docx topic)

1. Find which SCCs the default ServiceAccount in your namespace can use (`oc adm policy who-can use scc/*`)
2. Identify the difference between `restricted-v2` and `anyuid`
3. Document which CFK Pods in production run under which SCC

**Verifies**: SCC concept (called out as gap vs original plan)

## Task 3 — Watch an Operator reconcile (Tue)

1. Install any non-CFK Operator from OperatorHub (e.g. Grafana Operator) into a test namespace
2. Apply a Custom Resource for it
3. Use `oc logs -f` on the operator pod to capture the reconcile sequence
4. Edit the CR; capture how the operator reacts within 30s

**Verifies**: Operator pattern in motion (Tue)

## Task 4 — Add a Prometheus query (Wed)

1. Identify the OpenShift monitoring stack's Prometheus
2. Run a PromQL query for "pod restart count over last hour"
3. Build a 1-panel ad-hoc Grafana dashboard from that query
4. Save the JSON export

**Verifies**: Pod → metrics → Prometheus → PromQL → Grafana (Wed)

## Task 5 — One ArgoCD app (Thu)

1. Create an ArgoCD Application CR pointing at a sample manifest in git
2. Confirm Sync status went `OutOfSync` → `Synced` → `Healthy`
3. Modify the cluster object directly (e.g. scale Deployment); watch ArgoCD self-heal or report drift

**Verifies**: Git → ArgoCD → Cluster (Thu)

## Task 6 — Quota exhaustion (Fri)

1. Apply a small ResourceQuota in your test namespace (e.g. 2 CPU, 4Gi memory)
2. Try to deploy a Pod that would exceed it
3. Capture the admission error verbatim
4. Document the difference between Quota rejection and LimitRange defaulting

**Verifies**: Admission control (Fri) + tracker 2.5 / runbook A3 context

## Submission

`deliverables/<you>/week02/` with files for each task.
