# Week 1 — Skill Check

Hands-on verification. Each task produces an artifact you can show the instructor or paste into your runbook. Use the training project; clean up after each task.

## Task 1 — Deploy + expose a sample app (Mon-Wed)

1. Deploy an nginx Deployment with 3 replicas
2. Expose it via a ClusterIP Service
3. Expose externally via a Route with edge TLS
4. Curl the Route from outside the cluster and capture the response

**Verifies**: Pods, Deployments, Services, Routes (Wk1 Mon-Wed)

## Task 2 — StatefulSet with PVCs (Tue, Thu)

1. Deploy a 3-replica StatefulSet (any image with persistent disk — e.g. `redis`)
2. Confirm each Pod gets its own PVC bound to a PV
3. Delete one Pod; verify it returns with the SAME PVC attached
4. Capture `oc get pvc` before and after

**Verifies**: StatefulSet identity, PVC retention, PV lifecycle (Wk1 Tue + Thu)

## Task 3 — ConfigMap + Secret consumption (Wed)

1. Create a ConfigMap with two key/value pairs
2. Create a Secret with one key/value pair (note the base64 encoding)
3. Mount both into a Pod — ConfigMap as a file, Secret as an env var
4. `oc exec` into the Pod and prove both values are present

**Verifies**: ConfigMap + Secret consumption patterns (Wk1 Wed)

## Task 4 — Forced failures (Fri)

For each, induce the failure and capture the diagnostic command that revealed the cause:

1. **ImagePullBackOff** — point Deployment at non-existent image; capture `oc describe pod`
2. **CrashLoopBackOff** — set container command to `false`; capture `oc logs` excerpt
3. **OOMKilled** — set memory limit to 10Mi on a memory-hungry image; capture `oc describe pod` Reason field
4. **Pending** (unschedulable) — request 100 CPU cores; capture `Events:` from describe

**Verifies**: troubleshooting workflow (Wk1 Fri)

## Submission

Save under `deliverables/<you>/week01/` as:

- `task1-route.md` — Route URL + curl output
- `task2-statefulset.md` — PVC ownership before/after delete
- `task3-config.md` — Pod exec output proving values
- `task4-failures.md` — 4 failure scenarios, each with symptom + diagnostic command + log excerpt
