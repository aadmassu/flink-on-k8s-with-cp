# Week 6 — Skill Check

Hands-on tasks feeding directly into the Personal Master Runbook (the bootcamp's final deliverable).

## Task 1 — Read a DataStream job (Monday)

Pick one FCB Flink job. In the Flink UI, list every operator, its parallelism, and whether it's chained. Match each UI vertex to a source-code operator.

## Task 2 — Watermark reading (Monday)

For the same job, note current watermark value + how far behind wall-clock time it is. If a window hasn't fired recently, is the watermark stuck?

## Task 3 — State inventory (Wednesday)

Latest checkpoint size for one job. Backend type. TM disk usage if RocksDB. Extrapolate: at current growth rate, when does the disk fill?

## Task 4 — Fault recovery trace (Thursday)

Force a TM Pod restart on a test job. Record: T0 (delete) → T1 (JM detected) → T2 (job RUNNING again). Verify downstream continuity.

## Task 5 — Savepoint round-trip (Thursday)

Take a savepoint, cancel the job, restart from savepoint. Verify state continuity via downstream output.

## Task 6 — Upgrade drill (Friday)

Savepoint upgrade of one job. Pre/post continuity check. Roll back to original image via same savepoint if the new image misbehaves.

## Task 7 — Personal Master Runbook (Friday)

Consolidate all prior weeks' runbook artifacts into the 10-page final document. One page per capstone-diagram layer, structured "what breaks / how to detect / how to fix."

---

Deliverable: `personal-master-runbook.md` — the bootcamp's takeaway artifact.
