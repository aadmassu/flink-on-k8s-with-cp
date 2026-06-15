# Week 6 — Skill Check

## Task 1 — Deploy a Flink job via CMF (Mon)

1. Submit a SELECT statement via CMF REST API
2. Verify the FlinkApplication CR landed; JM + TM Pods running
3. Open the JM UI; capture job graph
4. Confirm at least one successful checkpoint to NetApp S3

**Verifies**: Flink Architecture (Mon)

## Task 2 — Savepoint round-trip (Tue)

1. Trigger a manual savepoint on a running job
2. Stop the job with savepoint
3. Restart from the savepoint; confirm state continuity (e.g. same window aggregation totals)
4. Capture the savepoint S3 path

**Verifies**: Checkpoints + savepoints (Tue)

## Task 3 — Cluster link stand-up (Wed)

1. Create a ClusterLink CR linking two test Kafka clusters (or two CFK clusters in your training project)
2. Verify mirror topic appears on destination
3. Produce on source; consume on destination
4. Measure lag at producer rest — should reach 0

**Verifies**: Cluster linking (Wed)

## Task 4 — Rack-aware partition check (Thu)

1. Confirm broker.rack labels match node AZs
2. Describe a topic; verify replicas distribute across racks (not all on the same AZ)
3. Document what would change if  the platform went MRC (single cluster across regions)

**Verifies**: MRC + rack awareness (Thu)

## Task 5 — DR Drill (Fri — capstone)

Run one full DR scenario from Wk 6 Fri lab. Capture:

1. Pre-state snapshot (every layer)
2. Failure trigger
3. Detection signal + time
4. Diagnosis path
5. Recovery action + time
6. Verification
7. Postmortem with 3 lessons

This is your **Multi-Region DR Runbook** deliverable.

## Submission

`deliverables/<you>/week06/` — and aggregate into the **Personal Master Runbook v5 (Final)** which becomes the bootcamp's takeaway artifact.
