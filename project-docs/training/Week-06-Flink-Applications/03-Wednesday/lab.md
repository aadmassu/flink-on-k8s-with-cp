# Week 6 Wednesday — Lab: Inspect Real State

**Time**: ~3 hours

Three exercises: read a running job's state stats, force state growth to see the effect, and experiment with TTL.

Every `oc` command is paired with its `kubectl` equivalent.

---

## Prerequisite Setup

Baseline cluster from [Week 5 Monday's lab](../../Week-05-Flink-Platform/01-Monday/lab.md#prerequisite-setup--minimal-cfk--flink-cluster-week-56-baseline). Today the goal is to *see state grow* — deploy a keyed windowed job whose per-key state is visible in checkpoint size.

### Deploy a stateful keyed-window job

Reuse [Thursday's `stateful-demo` from Week 5](../../Week-05-Flink-Platform/04-Thursday/lab.md#prerequisite-setup) if still running. Otherwise apply:

```yaml
apiVersion: flink.apache.org/v1beta1
kind: FlinkDeployment
metadata: {name: state-demo, namespace: bootcamp}
spec:
  image: flink:1.18
  flinkVersion: v1_18
  serviceAccount: flink
  flinkConfiguration:
    state.checkpoints.dir: "s3://flink-checkpoints/state-demo/"
    state.backend: rocksdb
    state.backend.incremental: "true"
    execution.checkpointing.interval: "10 s"
    s3.endpoint: "http://minio.bootcamp.svc:9000"
    s3.access-key: "minio"
    s3.secret-key: "minio123"
    s3.path.style.access: "true"
  jobManager: {resource: {memory: "1024m", cpu: 0.5}}
  taskManager: {resource: {memory: "2048m", cpu: 1}}
  job:
    jarURI: local:///opt/flink/examples/streaming/StateMachineExample.jar
    parallelism: 4
    upgradeMode: last-state
```

`StateMachineExample` maintains per-key state that grows over time — perfect for watching checkpoint size climb in the Flink UI. Let it run for ~10 minutes so you have several checkpoint sizes to compare.

### Optional — switch backends and re-observe

Change `state.backend: rocksdb` → `state.backend: hashmap` and redeploy. Observe:
- Faster reads (all state in JVM heap) — visible in Flink UI's checkpoint alignment time
- Higher TM memory pressure — visible in `kubectl top pod`
- Same checkpoint payload to S3 (state serialization is backend-agnostic)

---

## Lab 1 — Read state size + backend for a running job

**Goal**: for one FCB Flink job, find its state size, backend type, and per-checkpoint growth rate.

### 1a. Flink UI → Checkpoints tab

For the job, note:

- State backend type (HashMap or RocksDB) — from job overview
- Latest checkpoint size — from Checkpoints tab
- Latest checkpoint duration
- Delta from previous checkpoint (if incremental)

### 1b. TM disk usage for RocksDB (if applicable)

If the job uses RocksDB:

```bash
oc      exec -n <namespace> <taskmanager-pod-name> -- \
  df -h /tmp/flink-state-rocksdb 2>/dev/null || \
oc      exec -n <namespace> <taskmanager-pod-name> -- df -h /

kubectl exec -n <namespace> <taskmanager-pod-name> -- df -h /tmp/flink-state-rocksdb 2>/dev/null || \
kubectl exec -n <namespace> <taskmanager-pod-name> -- df -h /
```

The specific path may vary; check `spec.flinkConfiguration."state.backend.rocksdb.localdir"` in the CR. Record disk used and disk available.

### 1c. Compare local vs durable

Local RocksDB disk usage should be *similar* to the last checkpoint size (usually within 2×). If it's dramatically larger, the local copy has stale data waiting for compaction. If dramatically smaller, the checkpoint has data the TM doesn't currently need in memory (large key space, small hot set).

---

## Lab 2 — Force state growth (safe on a test job)

**Goal**: produce a keyBy job where the number of unique keys grows over time, watch state size grow.

Use a test SQL statement like:

```sql
CREATE TABLE unique_key_counter (
    key_val STRING,
    count_val BIGINT
) WITH ('connector' = 'kafka', 'topic' = 'test-uniques-output', ...);

INSERT INTO unique_key_counter
SELECT key_val, COUNT(*) FROM (
    SELECT UUID() AS key_val FROM my_source_topic
) GROUP BY key_val;
```

Every input event produces a *new* UUID key, so keyed state grows unboundedly. Watch:

- Checkpoint size (should climb each checkpoint)
- TM disk (should climb until it hits the limit)

Stop the job before disk fills. Note: how many events per GB of state?

---

## Lab 3 — Add TTL, watch state stabilize

**Goal**: same shape, TTL enabled, state stabilizes instead of growing.

For SQL, add the TTL config in Flink Environment:

```
SET 'table.exec.state.ttl' = '1 hour';
```

Re-submit the job (or a new one with the same query). Now keyed state entries expire after 1 hour of no access.

Run for at least 90 min. Expected: state size climbs then plateaus around "1 hour's worth of keys" times "per-key overhead."

In your notes: after 90 min, what's the ratio of state size (with TTL) to what it would have been (without TTL, from Lab 2)?

---

## Deliverable — `deliverables/<you>/week06/wednesday.md`

1. **State inventory** — for one real job: backend type, latest checkpoint size, TM disk used
2. **Growth experiment** — from Lab 2, chart of state size over time, key-count per GB
3. **TTL experiment** — from Lab 3, plateau size + comparison to no-TTL baseline
4. **One question about state management your labs raised**
