# Week 6 Monday — Lab: Author + Read a DataStream Job

**Time**: ~3 hours

Three exercises: read a DataStream job, understand watermark behavior in practice, and reason about window fire times.

Every `oc` command is paired with its `kubectl` equivalent.

---

## Lab 1 — Read a real DataStream job's operators

**Goal**: for a running FCB Flink job, identify every operator in the Flink UI and match it back to source-code intent.

### 1a. Open the Flink UI for a running job

```bash
oc      port-forward -n <namespace> svc/<flinkdeployment-name>-rest 8081:8081
kubectl port-forward -n <namespace> svc/<flinkdeployment-name>-rest 8081:8081
```

Browse to `http://localhost:8081/#/job/running`.

### 1b. Click into one job → "Overview" → JobGraph

For each vertex:
- Operator name (from source code)
- Parallelism
- In / out rates
- Whether it's chained with neighbors

### 1c. Trace back to source code

Ask the job owner (or read the repo) for the source. Map each Flink-UI vertex to the DataStream API call that created it. Note: chained operators appear as one UI vertex but are multiple source-code calls.

---

## Lab 2 — Watermark experiment

**Goal**: see watermarks affect window firing.

If you have a job with time windows, examine its watermark strategy in code. Then in the Flink UI:

- Watermarks tab per operator — shows current low-watermark per parallel instance
- Metric `numLateRecords` — count of events arriving too late for their window

In your notes:
- Which operator is the watermark source (`fromSource` binds the strategy)?
- What's the current low-watermark?
- Given your strategy (say `forBoundedOutOfOrderness(5s)`), how far behind wall-clock is that number?

If you can safely inject an artificially-late event (via a test topic), observe it landing in `numLateRecords`.

---

## Lab 3 — Predict window fire times

**Goal**: given the watermark strategy + window type, reason about when a window will fire.

Set up scenario:
- Job uses tumbling windows of 5 min, `forBoundedOutOfOrderness(30s)`
- At `wall-clock 12:00:00`, source emits event with `timestamp=11:59:55`
- At `wall-clock 12:04:30`, source emits event with `timestamp=12:04:00`
- At `wall-clock 12:05:35`, source emits event with `timestamp=12:04:59`

Question: when does the `12:00:00 → 12:05:00` window fire?

Answer: when the watermark crosses `12:05:00`. The watermark = `max(event_timestamp) - 30s`. So we need `max_event >= 12:05:30`. First event with `timestamp >= 12:05:30` triggers the fire. If no such event ever arrives, that window stays open forever (which is why session windows exist).

In your notes: work through 3-4 such scenarios with different window types and watermark strategies. This is the muscle memory you'll need when a stream job seems "stuck" — usually it's just waiting for a watermark advance.

---

## Deliverable — `deliverables/<you>/week06/monday.md`

1. **Operator inventory** — for the real job you inspected, table of vertex → source-code call → operator family (source/transform/sink)
2. **Watermark reading** — current watermark value + how far behind wall clock, for one operator
3. **Window-fire scenarios** — 3-4 worked examples, each showing (input timestamps, watermark trace, window fire time)
4. **One question about DataStream API that's not obvious from a running job's UI**
