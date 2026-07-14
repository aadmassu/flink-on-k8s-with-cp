# Week 6 Tuesday — Lab: Streaming vs Batch on the Same Data

**Time**: ~3 hours

Two exercises: submit the same logic as a streaming job and a batch job, then compare behavior and output.

Every `oc` command is paired with its `kubectl` equivalent.

---

## Prerequisite Setup

Shared sandbox from [`project-docs/training/lab-flink/`](../../lab-flink/). Today runs the *same* logic once as streaming and once as batch.

### Streaming source — `events-in` (already running)

The lab-flink event-generator streams into `events-in` continuously — that's your streaming source. The `event-counter` FlinkDeployment from [Monday](../01-Monday/lab.md) is the streaming job.

### Batch source — a bounded ConfigMap-mounted CSV

```yaml
apiVersion: v1
kind: ConfigMap
metadata: {name: batch-input, namespace: flink-lab}
data:
  events.csv: |
    user-0,click,1
    user-1,click,2
    user-0,view,3
    user-2,click,4
    user-1,view,5
```

```
oc      apply -f batch-input-configmap.yaml
kubectl apply -f batch-input-configmap.yaml
```

Mount into a batch FlinkDeployment via `spec.podTemplate.spec.volumes`. In batch mode the job reads the file, emits the counts, and exits — the CR transitions `RUNNING → FINISHED` on its own.

### Two FlinkDeployment CRs — same JAR, different runtime mode

- **Streaming CR** (already the default): `spec.mode: native`, source = Kafka topic, sink = Kafka topic.
- **Batch CR**: add `spec.flinkConfiguration."execution.runtime-mode": "BATCH"`, swap source to the mounted CSV, sink to stdout / another topic.

Same operator DAG in both — the runtime picks bounded vs unbounded from the config.

---

## Lab 1 — Streaming job over a Kafka topic

**Goal**: process events as they arrive, emit per-minute counts.

### 1a. Author the SQL statement (via CMF UI or file)

```sql
SET 'execution.runtime-mode' = 'streaming';

CREATE TABLE input_stream (
    event_time TIMESTAMP(3),
    user_id STRING,
    amount DOUBLE,
    WATERMARK FOR event_time AS event_time - INTERVAL '5' SECOND
) WITH (
    'connector' = 'kafka',
    'topic' = '<input-topic>',
    'properties.bootstrap.servers' = 'kafka.dah-flink-<env>.svc.cluster.local:9092',
    'format' = 'json',
    'scan.startup.mode' = 'latest-offset'
);

CREATE TABLE output_stream (
    window_start TIMESTAMP(3),
    user_id STRING,
    total DOUBLE
) WITH (
    'connector' = 'kafka',
    'topic' = '<output-topic>',
    'properties.bootstrap.servers' = 'kafka.dah-flink-<env>.svc.cluster.local:9092',
    'format' = 'json'
);

INSERT INTO output_stream
SELECT
    TUMBLE_START(event_time, INTERVAL '1' MINUTE),
    user_id,
    SUM(amount)
FROM input_stream
GROUP BY TUMBLE(event_time, INTERVAL '1' MINUTE), user_id;
```

Submit via CMF SQL Gateway. Record the `job_id` returned.

### 1b. Watch it run

```bash
oc      get flinkdeployment -n <namespace> <derived-flinkdeployment-name> -o jsonpath='{.status.jobStatus.state}'
```

Should be `RUNNING` indefinitely. Consume the output topic to see per-minute aggregates emit.

---

## Lab 2 — Batch job over the same topic offset range

**Goal**: same logic, bounded input, exits when done.

### 2a. Same SQL, mode switched

```sql
SET 'execution.runtime-mode' = 'batch';

-- Same CREATE TABLEs as Lab 1a, but change:
--   'scan.startup.mode' = 'earliest-offset'
--   'scan.bounded.mode' = 'latest-offset'
```

The `scan.bounded.mode` setting is what makes the Kafka source bounded — Flink will read from `earliest` to `latest` (as of statement submission time) and then stop.

Submit and observe. Job should progress through partition reads and exit `FINISHED`.

### 2b. Compare behavior

| Metric | Streaming | Batch |
|---|---|---|
| Job final state | `RUNNING` (forever) | `FINISHED` |
| Checkpoints created | Yes, every N sec | None |
| Watermarks in UI | Advance in real time | Don't apply (batch mode) |
| Output rate | Steady per-minute | Bursty; one big output pass |
| Restart behavior on Pod fail | Resume from checkpoint | Retry the failing task |

Fill in your notes with the actual observed numbers.

---

## Lab 3 — Predict pipeline behavior

**Goal**: reason about a topic-linked streaming pipeline.

Imagine: Job A (streaming, unbounded) writes to Topic X. Job B (streaming, unbounded) reads Topic X, writes Topic Y.

Scenario questions (write your answer + reasoning):

1. Job B crashes and is down for 2 hours. What happens to Job A's output? What happens to Job A's Kafka producer memory?
2. Job B comes back after 2 hours. Will it re-process everything from Topic X that Job A produced during the outage? What determines yes/no?
3. Job A is upgraded (savepoint upgrade). Does Job B need to be restarted?
4. Topic X's retention is 6 hours. Job B is down for 8 hours. When Job B comes back, what data is lost?

---

## Deliverable — `deliverables/<you>/week06/tuesday.md`

1. **Streaming job trace** — SQL you submitted, `job_id`, first 3 output messages
2. **Batch job trace** — same shape, plus final state and elapsed time
3. **Comparison table** — the "streaming vs batch" table above, filled in with your actual observations
4. **Pipeline scenario answers** — 4 written responses to Lab 3
