# Week 5 Friday — Lab: Full End-to-End Deploy

**Time**: ~4 hours

One long-form exercise: deploy a new Flink job from a clean state and time every step. This ties the whole week together.

Every `oc` command is paired with its `kubectl` equivalent.

---

## Prerequisite Setup

Shared sandbox from [`project-docs/training/lab-flink/`](../../lab-flink/). Today walks the FULL end-to-end deploy path — source change → JAR build → container image build → cluster load → CR apply → running job. This is exactly what `lab-flink/flink-job/` walks; today you'll time each stage.

### Confirm you have the custom-job build tools

Required on your laptop: Docker, Maven (`mvn`), JDK 11, `kind` (or `minikube` if that's your local K8s).

Sanity check:

```
mvn --version
docker version
kind get clusters   # expect: flink-lab
```

### Walk the E2E deploy of the event-counter custom job

Follow [`lab-flink/flink-job/README.md`](../../lab-flink/flink-job/README.md) → "Variant 2 — Custom event-counter":

```
cd ../../lab-flink/flink-job/src

# Stage 1 — JAR build (T0 → T1)
mvn package

# Stage 2 — image build (T1 → T2)
cp target/event-counter.jar .
docker build -t event-counter:local .

# Stage 3 — cluster load (T2 → T3)
kind load docker-image event-counter:local --name flink-lab

# Stage 4 — CR apply (T3 → T4)
cd ..
oc      apply -f flinkdeployment-custom.yaml -n flink-lab
kubectl apply -f flinkdeployment-custom.yaml -n flink-lab
```

Record the wall-clock delta at each `T*` — the Lab section below uses those numbers.

Application-mode Flink only accepts `local://` jarURIs — the JAR must be baked INTO the image, not fetched at runtime. The lab-flink Dockerfile is a 2-line derivative of `flink:1.18` that copies the JAR to `/opt/flink/usrlib/`.

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
