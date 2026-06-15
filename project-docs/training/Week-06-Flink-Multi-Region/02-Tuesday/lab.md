# Week 6 Tuesday — Lab: Trigger a Savepoint + Recover

**Time**: ~4 hours

## Hands-on Lab — manual checkpoint, savepoint, recover

### Step 1 — start a long-running job

Use yesterday's training-tap job, but with a longer-running statement.

### Step 2 — observe checkpoint timeline

```bash
# JM UI shows checkpoint history
oc port-forward svc/training-tap-XXXX 8081:8081 &
# Visit http://localhost:8081/jobs/<id>/checkpoints
```

Capture:
- Checkpoint interval
- Average duration
- Size (state)

### Step 3 — list checkpoints in NetApp S3

```bash
NETAPP_S3="aws --endpoint-url https://netapp-s3.example.com s3"
$NETAPP_S3 ls s3://netapp-bucket/checkpoints/training-tap/ --recursive | head -20
```

Each completed checkpoint = a directory `chk-N` with the state files.

### Step 4 — take a savepoint via Flink REST

```bash
# JM REST endpoint via port-forward
curl -X POST http://localhost:8081/jobs/<job-id>/savepoints \
  -H "Content-Type: application/json" \
  -d '{"target-directory":"s3://netapp-bucket/savepoints/training-tap/"}'

# Returns a trigger-id; poll until completed
TID=<from above>
curl http://localhost:8081/jobs/<job-id>/savepoints/$TID | python3 -m json.tool
```

When complete, you'll have a path in S3.

### Step 5 — force a TM crash; observe recovery

```bash
# Delete a TM pod
oc get pod -l app.kubernetes.io/component=taskmanager
oc delete pod <one of them>

# Watch the UI: job should go FAILED → RECOVERING → RUNNING
# Look at exception in UI, then operator log, then JM log
```

Capture:
- Time from crash to job RUNNING again
- Which checkpoint Flink restored from

### Step 6 — stop with savepoint; restart from it

```bash
# Stop the job, generating a savepoint
curl -X POST http://localhost:8081/jobs/<job-id>/stop \
  -H "Content-Type: application/json" \
  -d '{"targetDirectory":"s3://netapp-bucket/savepoints/training-tap/stop1/"}'

# Job now in FINISHED state; savepoint path returned

# Re-submit job with savepoint reference
oc patch flinkapplication training-tap-XXXX --type=merge -p \
  '{"spec":{"job":{"initialSavepointPath":"s3://netapp-bucket/savepoints/training-tap/stop1/<file>"}}}'
```

Confirm the new run picked up where the old one left off.

## Troubleshooting Exercise — break a checkpoint

```bash
# Set checkpoint interval to a very small number so checkpoints fail
oc patch flinkapplication training-tap-XXXX --type=merge -p \
  '{"spec":{"flinkConfiguration":{"checkpoint.interval.ms":"1000"}}}'

# Or: misconfigure s3.endpoint to be unreachable
oc patch flinkapplication training-tap-XXXX --type=merge -p \
  '{"spec":{"flinkConfiguration":{"s3.endpoint":"https://no-such-host.example"}}}'

# Watch checkpoint failures stack up in JM UI
# Recover by setting back to good values
```

## Deliverable — `deliverables/<you>/week06/tuesday.md`

1. **Checkpoint timeline** — interval + duration + size for your job
2. **One savepoint path** — the S3 location, plus the JSON of the savepoint metadata
3. **TM crash recovery trace** — time from crash to RUNNING, checkpoint restored, log excerpt
4. **Stop-with-savepoint → start-from-savepoint** — confirmed continuity
5. **One question** — about exactly-once in production
