# Week 5 — Runbook Deliverable Template

Submit at end of week as `deliverables/<you>/week05/runbook.md`.

## 1. Flink architecture cheat sheet

One sentence each on: JobManager, TaskManager, Sources, Sinks, Checkpoint Coordinator, State Backend, Slots, Parallelism.

## 2. FlinkDeployment CR field reference

Table of the 15-20 most important `spec.*` fields, one row each: field name / one-sentence description / typical value at FCB.

## 3. Slot arithmetic worksheet

For 3 different jobs in the cluster: `replicas`, `slots/TM`, `parallelism`, `slots_used`, `slots_free`. Verified against Flink UI.

## 4. Dependencies map

Table with columns: dependency / endpoint / credential Secret / outage-survival. 6-8 rows.

## 5. End-to-end deploy timing

Annotated timeline of one deploy: T0 → T1 → T2 → T3. Which segment dominates? What would you change to speed it up?

## 6. Personal troubleshooting checklist v5

Append these platform-side patterns to your running v4 (from Week 4):

- "Job stuck in CREATED" → check slot availability
- "Job cycling RESTARTING → RUNNING" → check restart-strategy config + TM logs
- "Checkpoint failures" → S3 access / state size / operator snapshot timeout
- "CMF UI can't list statements" → CMF ↔ DB connection
- "JAR download 404" → Artifactory perms / URL
- "Metrics missing in Prometheus" → reporter config + ServiceMonitor
