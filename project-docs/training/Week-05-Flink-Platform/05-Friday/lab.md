# Week 5 Friday — Lab: Full End-to-End Deploy

**Time**: ~4 hours

One long-form exercise: deploy a new Flink job from a clean state and time every step. This ties the whole week together.

Every `oc` command is paired with its `kubectl` equivalent.

---

## Prerequisite Setup

Baseline cluster from [Week 5 Monday's lab](../01-Monday/lab.md#prerequisite-setup--minimal-cfk--flink-cluster-week-56-baseline). Today simulates a real Artifactory-backed deploy — deploy a JAR-hosting file server so the FlinkDeployment CR fetches the JAR over HTTP instead of using the baked-in image path.

### Deploy a stand-in "Artifactory" — nginx serving a JAR

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: jar-repo
  namespace: bootcamp
spec:
  replicas: 1
  selector: {matchLabels: {app: jar-repo}}
  template:
    metadata: {labels: {app: jar-repo}}
    spec:
      initContainers:
      - name: seed-jar
        image: flink:1.18
        command: ["sh","-c","cp /opt/flink/examples/streaming/WordCount.jar /www/wordcount.jar"]
        volumeMounts: [{name: www, mountPath: /www}]
      containers:
      - name: nginx
        image: nginx:1.25-alpine
        volumeMounts: [{name: www, mountPath: /usr/share/nginx/html}]
      volumes: [{name: www, emptyDir: {}}]
---
apiVersion: v1
kind: Service
metadata: {name: jar-repo, namespace: bootcamp}
spec:
  selector: {app: jar-repo}
  ports: [{port: 80, targetPort: 80}]
```

```
oc      apply -f jar-repo.yaml
kubectl apply -f jar-repo.yaml
```

### Deploy a Flink job that fetches the JAR over HTTP

```yaml
apiVersion: flink.apache.org/v1beta1
kind: FlinkDeployment
metadata:
  name: e2e-demo
  namespace: bootcamp
spec:
  image: flink:1.18
  flinkVersion: v1_18
  serviceAccount: flink
  jobManager: {resource: {memory: "1024m", cpu: 0.5}}
  taskManager: {resource: {memory: "1024m", cpu: 0.5}}
  job:
    jarURI: http://jar-repo.bootcamp.svc/wordcount.jar
    parallelism: 2
    upgradeMode: stateless
```

Now you can trace the full deploy: `apply` → operator reconciles → JAR downloaded from `jar-repo` → JM starts → TMs claim slots → RUNNING. Time each transition.

---

## Lab 1 — Deploy one job end-to-end, timed

**Goal**: pick a small Flink job (WordCount-style, or a simple filter), take it from JAR-in-Artifactory to running-in-cluster, and time each step.

### 1a. Prep — record start time

Write down: **T0** = `date -u +"%FT%TZ"`

### 1b. Confirm JAR is in Artifactory

If you're re-deploying an existing job, the JAR is already there. If deploying a new job, confirm the CI/CD pipeline produced a JAR:

```bash
curl -sSf -o /dev/null -w "%{http_code}\n" \
  https://<artifactory-host>/flink-jars/<your-jar>-<version>.jar
```

Expected: `200`. Not 200 → back to CI/CD.

### 1c. Author the FlinkDeployment CR

Copy an existing CR from `apps/confluent-platform/<env>/` — no wait, wrong location — from wherever your Flink CRs live in the repo, or from the CMF SQL Gateway examples. Update:

- `spec.image` — Flink runtime image
- `spec.job.jarURI` — point at your JAR
- `spec.job.parallelism` — start with 2
- `spec.taskManager.replicas` — 1 or 2 for a small test

Save to `/tmp/my-flink-job.yaml`.

### 1d. Apply the CR

```bash
oc      apply -f /tmp/my-flink-job.yaml -n <namespace>
kubectl apply -f /tmp/my-flink-job.yaml -n <namespace>
```

Record **T1** = time of apply.

### 1e. Watch the operator process it

```bash
oc      logs -n flink-operator deployment/flink-kubernetes-operator -f | grep <flinkdeployment-name>
kubectl logs -n flink-operator deployment/flink-kubernetes-operator -f | grep <flinkdeployment-name>
```

You should see: validate → render → apply children → wait for TMs to register → job accepted.

### 1f. Watch Pods come up

Second terminal:

```bash
oc      get pods -n <namespace> -l app=<flinkdeployment-name> -w
kubectl get pods -n <namespace> -l app=<flinkdeployment-name> -w
```

Expected sequence: JM Pod `Pending` → `ContainerCreating` → `Running`, then TM Pods do the same. Record **T2** = time all Pods `Running`.

### 1g. Wait for job RUNNING state

```bash
oc      get flinkdeployment -n <namespace> <flinkdeployment-name> \
  -o jsonpath='{.status.jobStatus.state}'
```

Poll every 10 sec. Record **T3** = first time it returns `RUNNING`.

---

## Lab 2 — Trace the deploy step-by-step

**Goal**: from your timing above, break down where the time went.

For each of these segments, compute the elapsed time:

| Segment | Elapsed |
|---|---|
| Author CR to apply (T1 - T0) | you decide manually |
| Apply to Pods Running (T2 - T1) | k8s scheduling + Pod init |
| Pods Running to job RUNNING (T3 - T2) | JAR download + JM init + TM registration + JobGraph deploy |

The dominant segment is what you'd optimize first.

---

## Lab 3 — Verify data actually flows

**Goal**: prove the job is doing what it says, not just showing `RUNNING`.

For your test job — consume the output Kafka topic:

```bash
oc      exec -n <namespace> <a-kafka-pod> -- \
  kafka-console-consumer --bootstrap-server <broker>:9092 \
  --topic <output-topic> --from-beginning --max-messages 5
```

kubectl equivalent identical (swap `oc exec` → `kubectl exec`).

If you get 5 messages, the job is actually processing.

---

## Deliverable — `deliverables/<you>/week05/friday.md`

1. **Timing table** — T0/T1/T2/T3 + the three elapsed segments in the "trace" section
2. **Dominant bottleneck** — which segment was slowest, and one concrete suggestion for what to change
3. **Output-topic verification** — the first 5 message payloads, confirming data flow
4. **Full-week runbook draft** — 1-page cheat sheet answering: "if I need to deploy a Flink job in FCB, what do I do in what order, what pipelines do I run, what do I check?"
