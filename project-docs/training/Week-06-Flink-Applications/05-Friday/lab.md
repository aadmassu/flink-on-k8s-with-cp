# Week 6 Friday — Lab: Full-Stack Operations Drill

**Time**: ~4 hours (last lab of the bootcamp)

Three exercises: one production upgrade, one debugging session, and the final Personal Master Runbook consolidation.

Every `oc` command is paired with its `kubectl` equivalent.

---

## Prerequisite Setup

Shared sandbox from [`project-docs/training/lab-flink/`](../../lab-flink/) with the `fault-drill` job from [Thursday](../04-Thursday/lab.md#prerequisite-setup) still running. Today's upgrade drill savepoints it and re-launches on `flink:1.18.1` (a patch bump proxy for a real image swap).

### Confirm fault-drill is running

If Thursday's `fault-drill` is gone, redeploy it:

```
oc      apply -f fault-drill-flinkdeployment.yaml
kubectl apply -f fault-drill-flinkdeployment.yaml
```

### Trigger the savepoint upgrade

Edit `fault-drill-flinkdeployment.yaml` — change `spec.image: flink:1.18` → `flink:1.18.1` and bump `spec.job.savepointTriggerNonce` (e.g., `1`). Apply:

```
oc      apply -f fault-drill-flinkdeployment.yaml
kubectl apply -f fault-drill-flinkdeployment.yaml
```

The Flink Kubernetes Operator will:
1. Trigger a savepoint via the JM REST API
2. Wait for the savepoint to land in `s3://flink-checkpoints/fault-drill/savepoints/`
3. Stop the job
4. Redeploy JM+TMs with the new image
5. Start the job from the savepoint

Watch the CR status:

```
oc      get flinkdeployment fault-drill -n flink-lab -w
kubectl get flinkdeployment fault-drill -n flink-lab -w
```

You should see `jobStatus.state` cycle `RUNNING → RECONCILING → SUSPENDED → RUNNING`, with `savepointInfo.lastSavepoint.path` updated.

### Roll-back path (if the new image misbehaves)

Change `spec.image` back to `flink:1.18` and bump `savepointTriggerNonce` again. The saved savepoint from the forward upgrade is the rollback point — same file, other direction.

---

## Lab 1 — Real upgrade in dev

**Goal**: perform a savepoint upgrade on a running Flink job, verify continuity.

### 1a. Pick a job, capture pre-upgrade baseline

For the target job:

- Current `spec.image` (write it down for rollback)
- Current `status.jobStatus.jobId`
- Latest checkpoint size and duration
- Sample of last 5 output-topic messages (for continuity comparison)

### 1b. Trigger savepoint upgrade

Edit CR:

```yaml
spec:
  job:
    upgradeMode: savepoint
  image: <new-image-tag>
```

Apply:

```bash
oc      apply -f /tmp/updated-cr.yaml -n <namespace>
kubectl apply -f /tmp/updated-cr.yaml -n <namespace>
```

### 1c. Watch state transitions

Poll `status.jobStatus.state`. Expected sequence:

- `RUNNING`
- `SUSPENDED` (operator took a savepoint before shutdown)
- `RECONCILING`
- `RUNNING` (new image, restored from savepoint)

Record wall-clock timestamps for each transition.

### 1d. Verify continuity

Consume the output topic for the next 5 minutes. Compare against pre-upgrade sample:

- No gap in message timestamps?
- No duplicates around the upgrade time?

If both hold: upgrade succeeded end-to-end.

---

## Lab 2 — Debug a broken job (instructor-injected fault or self-inflicted)

**Goal**: use the 5-step triage flow from discussion.md to root-cause one problem.

Setup (one of these):
- **Instructor-led**: cohort lead breaks one job in a way not yet seen
- **Self-inflicted**: pick one of the 6 common failures and reproduce (state growth, sink ACL revoke, checkpoint S3 revoke, ...)

Then triage:

1. **Read `status.jobStatus.state`** — first signal
2. **Open Flink UI Overview** — DAG-level view
3. **JM log** — decisions the JM made
4. **TM log(s)** — operator-level failures
5. **External check** — Kafka, S3, DB reachable?

For each step, record:
- What you saw
- What it ruled out
- What it pointed to

At the end: what was the root cause? How long from "job broken" to "root cause identified" to "job recovering"?

---

## Lab 3 — Personal Master Runbook v6 (final consolidation)

**Goal**: produce the single document you'll reference on-call.

Structure it around the capstone diagram in discussion.md. One page per layer, top to bottom:

1. **Kafka Topic (source/sink)** — health signals, common broker issues, ACL patterns
2. **Kafka Client / Source Operator** — connect strings, OAuth token flow, MDS auth failures
3. **Flink Operators (Map/KeyBy/Window/Aggregate/Sink)** — where custom code lives; how to read the DAG
4. **Checkpoint Coordinator** — checkpoint success/failure signals, S3 dependency
5. **JobManager** — HA lease, restart strategy, savepoint triggers
6. **TaskManagers** — sizing, backpressure, RocksDB disk
7. **Flink Kubernetes Operator** — reconciliation loop; where to look for CR issues
8. **Kubernetes** — Pods, Services, Secrets, ConfigMaps; RBAC gotchas
9. **PKI / TLS / OAuth** — cert-manager, Keyfactor, Okta, MDS
10. **NetApp S3 / Artifactory** — checkpoint + JAR distribution health

For each layer, three bullets:

- **What breaks** — the top 1-3 symptoms you'll actually see
- **How to detect** — the specific log line, metric, or CR field that surfaces it
- **How to fix** — the pipeline action / config change / ticket to open

Total: 10-page document. This is the deliverable of the bootcamp.

---

## Deliverable — `deliverables/<you>/week06/friday.md` + `personal-master-runbook.md`

1. **Upgrade trace** — pre-image, post-image, state transitions with timestamps, continuity check result
2. **Debugging session writeup** — the 5-step triage output, root cause, resolution time
3. **Personal Master Runbook v6** — the 10-page consolidation described above

The Personal Master Runbook is the artifact you take away from six weeks of bootcamp. It's what you reference when the pager goes off at 3am and you don't have time to look everything up.
