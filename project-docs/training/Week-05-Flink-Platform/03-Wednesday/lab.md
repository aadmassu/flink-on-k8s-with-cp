# Week 5 Wednesday — Lab: Slots, Parallelism, and Backpressure

**Time**: ~3 hours

Three exercises: count the slots a running job needs, force a backpressure situation, and observe what changes on the JM.

Every `oc` command is paired with its `kubectl` equivalent.

---

## Prerequisite Setup

Shared sandbox from [`project-docs/training/lab-flink/`](../../lab-flink/). For today, deploy a job with `parallelism: 4` and `numberOfTaskSlots: 2` so slot arithmetic is visible.

Save as `slots-demo-flinkdeployment.yaml`:

```yaml
apiVersion: flink.apache.org/v1beta1
kind: FlinkDeployment
metadata:
  name: slots-demo
  namespace: flink-lab
spec:
  image: flink:1.18
  flinkVersion: v1_18
  serviceAccount: flink
  flinkConfiguration:
    taskmanager.numberOfTaskSlots: "2"
  jobManager:
    resource:
      memory: "1024m"
      cpu: 0.5
  taskManager:
    replicas: 2
    resource:
      memory: "1536m"
      cpu: 0.5
  job:
    jarURI: local:///opt/flink/examples/streaming/WindowJoin.jar
    parallelism: 4
    upgradeMode: stateless
```

```
oc      apply -f slots-demo-flinkdeployment.yaml
kubectl apply -f slots-demo-flinkdeployment.yaml
```

Expect: 2 TaskManager Pods × 2 slots = 4 slots total, exactly matching parallelism 4. If you drop `taskManager.replicas` to 1, the job stays `CREATED` waiting for slots — that's the demo.

---

## Lab 1 — Slot arithmetic on a real job

**Goal**: predict the slot count from the CR + operator DAG, then verify against the Flink UI.

### 1a. Read the CR

```bash
oc      get flinkdeployment -n <namespace> <flinkdeployment-name> -o jsonpath='{"replicas: "}{.spec.taskManager.replicas}{"\nslots/TM: "}{.spec.flinkConfiguration.taskmanager\.numberOfTaskSlots}{"\nparallelism: "}{.spec.job.parallelism}{"\n"}'
```

Same in kubectl:

```bash
kubectl get flinkdeployment -n <namespace> <flinkdeployment-name> -o jsonpath='{"replicas: "}{.spec.taskManager.replicas}{"\nslots/TM: "}{.spec.flinkConfiguration.taskmanager\.numberOfTaskSlots}{"\nparallelism: "}{.spec.job.parallelism}{"\n"}'
```

### 1b. Predict slot usage

Given the numbers above, compute:

- `slots_total = replicas × slots_per_TM`
- `slots_needed = job_parallelism` (assuming no per-operator parallelism override)
- `slots_free = slots_total - slots_needed`

Write down all four numbers.

### 1c. Verify in Flink UI

Open the Flink UI (port-forward the `<flinkdeployment-name>-rest` Service if not via CMF):

```bash
oc      port-forward -n <namespace> svc/<flinkdeployment-name>-rest 8081:8081
kubectl port-forward -n <namespace> svc/<flinkdeployment-name>-rest 8081:8081
```

Browse to `http://localhost:8081/#/task-managers`. Confirm your `slots_total`, `slots_needed`, and `slots_free` numbers match reality.

---

## Lab 2 — Read the operator DAG

**Goal**: map the DAG in the Flink UI to the operators declared in the job code.

Open the same job in Flink UI → "Overview" → click the running job. You'll see the JobGraph. For each vertex:

- Operator name (from the code)
- Parallelism
- Whether it's chained with its neighbors
- Bytes/records in and out

Note which chains exist. Chained operators appear as a single box with a compound name (e.g. `Source: kafka-source -> Map -> Filter`).

In your notes:
- How many *operators* in the DAG?
- How many *task chains* (chained groups)?
- Which operators are stateful (`keyBy` follows, or has `stateful` in its name)?

---

## Lab 3 — Force backpressure

**Goal**: observe what happens when downstream operators can't keep up.

### 3a. Find (or produce) a rate spike

Best option: use an existing test job with a `Thread.sleep` or artificially heavy operator downstream. Or produce a burst of messages to the source Kafka topic:

```bash
oc      exec -n <namespace> <a-producer-pod> -- \
  kafka-producer-perf-test --topic <source-topic> --num-records 1000000 \
  --record-size 512 --throughput 50000 --producer-props bootstrap.servers=<broker>:9092
```

kubectl equivalent is identical (swap `oc exec` for `kubectl exec`).

### 3b. Watch backpressure in Flink UI

In the UI → job's DAG view → each vertex has a "backpressure" indicator (green / yellow / red).

- Green = healthy
- Yellow = accepting slower than upstream is sending
- Red = downstream is the bottleneck; upstream is being throttled

Screenshot the DAG showing red backpressure.

### 3c. Read the metrics

For the red vertex, click "Metrics" tab and look at `numRecordsInPerSecond` and `numRecordsOutPerSecond`. When they diverge, that's your bottleneck.

---

## Deliverable — `deliverables/<you>/week05/wednesday.md`

1. **Slot arithmetic table** — predicted vs actual, one row per column
2. **DAG operator + chain inventory** — operators, chains, parallelism per vertex
3. **Backpressure screenshot + explanation** — which vertex was the bottleneck, why
4. **One tuning proposal** — given the backpressure you observed, would you (a) increase downstream parallelism, (b) disable chaining, (c) increase TM slots, or (d) reduce upstream input rate? Justify.
