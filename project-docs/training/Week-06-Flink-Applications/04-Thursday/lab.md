# Week 6 Thursday — Lab: Break Things, Watch Recovery

**Time**: ~4 hours

Three exercises: trigger a checkpoint failure, force a Pod crash and watch recovery, and take a savepoint + restart from it.

Every `oc` command is paired with its `kubectl` equivalent.

---

## Lab 1 — Force a checkpoint failure (safe)

**Goal**: see what happens in the Flink UI + JM logs when a checkpoint declines.

### 1a. Pick a job and note current checkpoint stats

Flink UI → Checkpoints tab. Record:

- Latest checkpoint ID
- Latest checkpoint duration
- Latest checkpoint size

### 1b. Restrict S3 access briefly

Best safe way: edit the CR to use a bogus S3 path *just* for savepoints (not checkpoints — that would take down the job):

```yaml
spec:
  flinkConfiguration:
    state.savepoints.dir: s3://nonexistent-bucket/broken/
```

Apply. Then trigger a savepoint attempt (via CMF UI or `flink savepoint` command). Watch it fail.

### 1c. Restore

Revert the CR change. Next savepoint attempt should succeed.

In your notes: what error message did you see? Where did it surface — JM log, CR status, or Flink UI?

---

## Lab 2 — Kill a TM, watch recovery

**Goal**: observe the full restart sequence from Pod crash to job RUNNING again.

### 2a. Pick a healthy running job. Find its TMs

```bash
oc      get pods -n <namespace> -l app=<flinkdeployment-name>,component=taskmanager
kubectl get pods -n <namespace> -l app=<flinkdeployment-name>,component=taskmanager
```

Note current checkpoint ID + wall-clock time.

### 2b. Delete one TM Pod

```bash
oc      delete pod -n <namespace> <one-taskmanager-pod>
kubectl delete pod -n <namespace> <one-taskmanager-pod>
```

Record wall-clock time of delete.

### 2c. Watch the full recovery

```bash
oc      get flinkdeployment -n <namespace> <flinkdeployment-name> \
  -o jsonpath='{.status.jobStatus.state}'
```

Poll every 5 sec. Expected sequence:

- `RUNNING` (immediately after delete — JM hasn't noticed yet)
- `RECONCILING` or `RESTARTING` (JM detected the TM missing, initiating restart)
- `RUNNING` (job back up on a new TM Pod, state restored from checkpoint)

Record wall-clock time of each transition.

### 2d. Verify state continuity

If the job aggregates data (sums, counts), check downstream output — is there a *gap* between pre-crash and post-crash outputs? If EXACTLY_ONCE, there should be no duplicates. If AT_LEAST_ONCE, some duplicates near the crash time are expected.

---

## Lab 3 — Savepoint round-trip

**Goal**: take a savepoint, cancel the job, restart from the savepoint. Verify state continuity.

### 3a. Take a savepoint

Via CMF UI (Environment → Job → "Stop with savepoint") or via the operator CR annotation:

```bash
oc      annotate flinkdeployment -n <namespace> <flinkdeployment-name> \
  flinkdeployments.flink.apache.org/savepoint-trigger=<any-value>
kubectl annotate flinkdeployment -n <namespace> <flinkdeployment-name> \
  flinkdeployments.flink.apache.org/savepoint-trigger=<any-value>
```

The operator responds by triggering a savepoint. Path shows up in `status.jobStatus.savepointInfo.lastSavepoint.location`.

### 3b. Cancel the job

Cancel via CMF UI or:

```bash
oc      delete flinkdeployment -n <namespace> <flinkdeployment-name>
kubectl delete flinkdeployment -n <namespace> <flinkdeployment-name>
```

### 3c. Restart from savepoint

Re-apply the CR with `spec.job.initialSavepointPath: <the-savepoint-URI-from-3a>`:

```bash
oc      apply -f /tmp/flinkdeployment-with-savepoint.yaml -n <namespace>
kubectl apply -f /tmp/flinkdeployment-with-savepoint.yaml -n <namespace>
```

Watch the job come back. Check downstream output — same continuity check as Lab 2d.

---

## Deliverable — `deliverables/<you>/week06/thursday.md`

1. **Checkpoint-failure trace** — exact error message you triggered in Lab 1, where it surfaced, how long to appear
2. **TM-crash recovery timeline** — wall-clock T0 (delete) → T1 (JM noticed) → T2 (job back RUNNING). Compute total recovery time.
3. **Savepoint round-trip trace** — savepoint path, cancel + restart evidence
4. **Continuity check** — for both Lab 2 and Lab 3, was the downstream output continuous or gappy?
5. **One question** — anything about fault tolerance the labs didn't answer
