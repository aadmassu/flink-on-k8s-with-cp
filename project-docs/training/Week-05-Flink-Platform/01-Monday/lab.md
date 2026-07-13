# Week 5 Monday — Lab: Reading a Live Flink Job

**Time**: ~3 hours

Two exercises: one to build the mental model on a canonical open-source example, one to read a real FCB Flink job in the cluster.

Every `oc` command below is paired with its `kubectl` equivalent (training convention). Use whichever is on your laptop.

---

## Lab 1 — Walk a canonical Flink example (before touching the cluster)

**Goal**: read the *shape* of a Flink DataStream job in Java without running it. This is the reference you'll compare cluster-side reality against.

Read `WordCount.java` from the Flink documentation ([flink.apache.org/docs](https://flink.apache.org/docs/stable/)) or use this shape:

```java
StreamExecutionEnvironment env = StreamExecutionEnvironment.getExecutionEnvironment();

DataStream<String> lines = env
    .fromSource(kafkaSource, WatermarkStrategy.noWatermarks(), "input-source");

DataStream<Tuple2<String, Integer>> counts = lines
    .flatMap(new Tokenizer())        // operator: splits lines into words
    .keyBy(value -> value.f0)        // operator: partitions by word (creates keyed state)
    .sum(1);                         // operator: keyed running sum

counts.sinkTo(kafkaSink);            // sink

env.execute("word-count");
```

In your notes:

- Name the **operators** (`flatMap`, `keyBy`, `sum`, `sinkTo`).
- Identify the **keyed state** (where does the running count live?).
- Identify the **source** and **sink** — same protocol, different topic.
- Sketch the DAG on paper: Source → flatMap → keyBy+sum → Sink.

---

## Lab 2 — Read a real Flink job running in the cluster

**Goal**: find a running Flink job in `dah-flink-<env>`, list its Pods, identify JM vs TM, and map back to the DAG shape from Lab 1.

### 2a. Find the FlinkDeployment CRs currently in the namespace

```bash
oc      get flinkdeployment -n <namespace>
kubectl get flinkdeployment -n <namespace>
```

Pick one CR name. Write down: `spec.job.jarURI` (the JAR), `spec.jobManager.replicas`, `spec.taskManager.replicas`.

### 2b. List Pods for that job

```bash
oc      get pods -n <namespace> -l app=<flinkdeployment-name>
kubectl get pods -n <namespace> -l app=<flinkdeployment-name>
```

Expected: 1 (or more, on HA) JobManager Pod + N TaskManager Pods. Identify which is which by pod name (`*-jobmanager-*` vs `*-taskmanager-*`).

### 2c. Inspect the JobManager

```bash
oc      logs -n <namespace> <jobmanager-pod-name> --tail 50
kubectl logs -n <namespace> <jobmanager-pod-name> --tail 50
```

Look for lines like `Received job graph...`, `Submitting job...`, `Job <id> switched from CREATED to RUNNING`.

### 2d. Inspect a TaskManager

```bash
oc      logs -n <namespace> <taskmanager-pod-name> --tail 50
kubectl logs -n <namespace> <taskmanager-pod-name> --tail 50
```

Look for the operator names (from Lab 1's DAG) and slot allocation messages.

---

## Lab 3 — Match the DAG to the platform

Open the Flink UI (via port-forward or the CMF UI's job link) for the job you picked in Lab 2. Compare its DAG panel side-by-side with Lab 1's WordCount shape. Even for a totally different workload, the primitives are the same: source → operators → sink, with keyed state where `keyBy` appears.

In your notes:

- The real job's DAG has how many operators?
- Which operators are stateful?
- What's the source and what's the sink?

---

## Deliverable — `deliverables/<you>/week05/monday.md`

1. **WordCount DAG diagram** — sketched from Lab 1, boxes and arrows.
2. **Real-job DAG diagram** — sketched from Lab 3.
3. **JM vs TM identification** — how you told them apart in the pod listing + logs.
4. **Two questions** — anything about the architecture you still can't answer from just reading a running job.
