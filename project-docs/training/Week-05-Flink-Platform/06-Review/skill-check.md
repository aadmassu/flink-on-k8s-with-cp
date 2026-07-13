# Week 5 — Skill Check

Hands-on tasks that produce runbook artifacts. Each should take 15-30 min.

## Task 1 — Read a FlinkDeployment CR (Tuesday)

Pick a real running FlinkDeployment. In your notes, list every top-level `spec.*` field with a one-sentence description of what it controls. Aim for 15-20 fields covered.

## Task 2 — Slot arithmetic (Wednesday)

For a real job, extract `taskManager.replicas`, `numberOfTaskSlots`, `job.parallelism` from the CR. Predict `slots_used` and `slots_free`. Verify in the Flink UI's Task Managers tab. Match?

## Task 3 — Dependencies map (Thursday)

For one FCB Flink job, produce a table with columns: dependency name / endpoint / credential Secret / outage-survival (yes/no/degraded). Should have 6-8 rows.

## Task 4 — End-to-end deploy timing (Friday)

Deploy one job (fresh or restart existing). Record T0 (CR apply) → T1 (Pods Running) → T2 (Job RUNNING). Compute the three segments; identify which dominates.

## Task 5 — Draw the runtime

By hand or in a text file: draw the running-cluster topology (1 JM Pod, N TM Pods, S slots each, current job's parallelism). Annotate: which operator is where, where state lives, checkpoint path.

---

Deliverable: `week-05-runbook.md` — combining Tasks 1-5 into one reference document. This is the artifact you'd hand a new engineer joining the team.
