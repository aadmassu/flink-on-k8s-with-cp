# Week 5 Tuesday — Lab: Trace a FlinkDeployment CR

**Time**: ~3 hours

Three exercises: read a CR end-to-end, watch reconciliation happen live, and trigger a controlled upgrade to see the savepoint flow.

Every `oc` command below is paired with its `kubectl` equivalent (training convention).

---

## Prerequisite Setup

The baseline `kind` + CFK + Flink Operator + MinIO cluster from [Week 5 Monday's lab](../01-Monday/lab.md#prerequisite-setup--minimal-cfk--flink-cluster-week-56-baseline) is the sandbox for today. If it's still running, keep it. If you tore it down, re-run steps 1–6 there and reapply the `wordcount` FlinkDeployment.

Today's exercises need the operator running and one FlinkDeployment CR to trace. No extra deploys required.

Quick health check:

```
oc      get pods -n flink-operator
kubectl get pods -n flink-operator
oc      get flinkdeployment -n bootcamp
kubectl get flinkdeployment -n bootcamp
```

You should see 1 `flink-kubernetes-operator-*` Pod and the `wordcount` FlinkDeployment in `RUNNING`.

---

## Lab 1 — Read a FlinkDeployment CR line-by-line

**Goal**: understand every top-level `spec.*` field on a real FCB FlinkDeployment.

### 1a. Get the raw CR

```bash
oc      get flinkdeployment -n <namespace> <flinkdeployment-name> -o yaml > /tmp/flinkdeployment.yaml
kubectl get flinkdeployment -n <namespace> <flinkdeployment-name> -o yaml > /tmp/flinkdeployment.yaml
```

### 1b. Walk each spec block, write down what it does

Open `/tmp/flinkdeployment.yaml`. For each of these fields, write one sentence in your notes:

- `spec.image` — Flink container image + tag
- `spec.flinkVersion` — the API version the operator uses to render config
- `spec.jobManager.resource.cpu / memory / replicas`
- `spec.taskManager.resource.cpu / memory / replicas`
- `spec.flinkConfiguration."high-availability.type"` — none / kubernetes / zookeeper
- `spec.flinkConfiguration."state.checkpoints.dir"` — where checkpoints go
- `spec.flinkConfiguration."state.savepoints.dir"` — where savepoints go
- `spec.job.jarURI` — the JAR to run
- `spec.job.parallelism` — how many parallel operator instances
- `spec.job.upgradeMode` — savepoint / last-state / stateless

Cross-check against your understanding — anything not matching what discussion.md described gets flagged.

---

## Lab 2 — Watch reconciliation happen live

**Goal**: see the operator do its work in real time.

### 2a. Force a reconcile by re-applying with no changes

```bash
oc      apply -f /tmp/flinkdeployment.yaml
kubectl apply -f /tmp/flinkdeployment.yaml
```

### 2b. Watch the operator log

```bash
oc      logs -n flink-operator deployment/flink-kubernetes-operator --tail 100 -f
kubectl logs -n flink-operator deployment/flink-kubernetes-operator --tail 100 -f
```

You should see log lines starting with the CR name, walking through validation → reconcile → child object apply.

### 2c. Watch child objects update

```bash
oc      get deployment,svc,configmap -n <namespace> -l app=<flinkdeployment-name> -w
kubectl get deployment,svc,configmap -n <namespace> -l app=<flinkdeployment-name> -w
```

In your notes: how long did reconcile take from `apply` to steady state?

---

## Lab 3 — Trigger a savepoint upgrade

**Goal**: see the `savepoint` upgrade mode in action — stop with savepoint → upgrade → restart from savepoint.

### 3a. Bump the image tag (a no-op upgrade if you use the same version explicitly)

Edit `/tmp/flinkdeployment.yaml` — change `spec.image: flink:1.20.0` → `spec.image: flink:1.20.0` (yes the same tag, but the operator will still cycle the Pods). Or bump to a patch version if available.

Ensure `spec.job.upgradeMode: savepoint` is set.

```bash
oc      apply -f /tmp/flinkdeployment.yaml
kubectl apply -f /tmp/flinkdeployment.yaml
```

### 3b. Follow the state transitions

```bash
oc      get flinkdeployment -n <namespace> <flinkdeployment-name> -o jsonpath='{.status.jobStatus.state}'
```

Repeat every 10 seconds. Expected sequence:
- `RUNNING`
- `SUSPENDED` (operator triggered a savepoint before shutting down)
- `RECONCILING`
- `RUNNING` (came back from the savepoint)

### 3c. Verify state continuity

If the job aggregates data (e.g., a running count per key), consume from the output Kafka topic before and after the upgrade — the count should be *continuous*, not reset to zero. That's the whole point of savepoint upgrade mode.

---

## Deliverable — `deliverables/<you>/week05/tuesday.md`

1. **spec breakdown** — one sentence per top-level field in the FlinkDeployment CR
2. **Reconciliation log excerpt** — 5-10 lines from the operator log annotated with which reconcile step (validate/render/apply)
3. **Upgrade state trace** — the sequence of `status.jobStatus.state` transitions during Lab 3
4. **Continuity check result** — did the output stream stay continuous across the upgrade? Yes/no + evidence
5. **Two questions** — anything about the operator you can't answer from reading a CR + log
