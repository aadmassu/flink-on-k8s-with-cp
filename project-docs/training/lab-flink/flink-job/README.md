# flink-job — Flink job artifacts

Item 3 in the lab: the Flink jobs that make the platform useful. Two variants — pick either depending on whether you want a code walkthrough or just want to see Flink work.

## Variants

| File | Purpose | Prereq |
|---|---|---|
| `flinkdeployment-example.yaml` | Zero-code demo using bundled `StateMachineExample.jar` | none |
| `flinkdeployment-custom.yaml` | Custom `event-counter` reading `events-in` → `counts-out` | build + load the JAR-in-image (see below) |
| `src/` | Maven project for the custom job + Dockerfile | JDK 11 + Maven |

## Why no HTTP-served JAR flow

Flink application mode (what `FlinkDeployment.spec.job` uses) only accepts `local://` JAR URIs. An HTTP `jarURI` is rejected with `Only "local" is supported as schema for application mode`. So the custom-job flow bakes the JAR into a Flink derivative image and loads it into the cluster's node cache.

## Variant 1 — Example JAR (fastest to see Flink running)

```
oc      apply -f flinkdeployment-example.yaml -n flink-lab
kubectl apply -f flinkdeployment-example.yaml -n flink-lab
```

Observe:

```
oc      get flinkdeployment example-statemachine -n flink-lab -o yaml
oc      get pods -n flink-lab -l app=example-statemachine
kubectl get flinkdeployment example-statemachine -n flink-lab -o yaml
kubectl get pods -n flink-lab -l app=example-statemachine
```

## Variant 2 — Custom event-counter (the pedagogical walkthrough)

### Step 1 — build the JAR

```
cd src/
mvn package
# produces target/event-counter.jar
```

### Step 2 — build the Flink image with the JAR inside

```
cp target/event-counter.jar .           # bring JAR next to the Dockerfile
docker build -t event-counter:local .
```

### Step 3 — load the image into your local Kubernetes

```
kind load docker-image event-counter:local --name flink-lab
```

For minikube: `minikube image load event-counter:local`.

### Step 4 — apply the FlinkDeployment CR

```
cd ..
oc      apply -f flinkdeployment-custom.yaml -n flink-lab
kubectl apply -f flinkdeployment-custom.yaml -n flink-lab
```

### Step 5 — verify

```
# CR status — should reach STABLE / RUNNING
kubectl get flinkdeployment event-counter -n flink-lab

# JobManager + TaskManager Pods
kubectl get pods -n flink-lab -l app=event-counter

# Output — user counts landing on counts-out
kubectl exec -n flink-lab kafka-0 -- kafka-console-consumer \
  --bootstrap-server localhost:9092 --topic counts-out --max-messages 20
# expect: user-3=1, user-7=1, user-3=2, user-3=3, user-1=1, ...
```

### Step 6 — Flink UI

```
kubectl port-forward -n flink-lab svc/event-counter-rest 8081:8081
# open http://localhost:8081
```

Inspect: DAG shape, running/idle slots, checkpoint history.

## What this covers for Week 5 Monday + Tuesday

**Monday — Flink Architecture**

- JM Pod = the master (`kubectl logs -n flink-lab event-counter-<jm-pod>` shows job graph submission + checkpoint coordination lines)
- TM Pods = the workers (logs show operator instantiation + slot allocation)
- Kafka Pods = sources + sinks
- (Optional) MinIO Pod = state / checkpoint durability — see the commented-out block in `flinkdeployment-custom.yaml` and install MinIO into the namespace when you're ready for Week 5 Thu

**Tuesday — Flink Operator**

Compare the CR to what actually got built:

```
# CR — one document, ~30 lines of spec
kubectl get flinkdeployment event-counter -n flink-lab -o yaml

# What the operator built
kubectl get deployment -n flink-lab -l app=event-counter
kubectl get service    -n flink-lab -l app=event-counter
kubectl get configmap  -n flink-lab -l app=event-counter
kubectl get pods       -n flink-lab -l app=event-counter
```

Every K8s object on the right came from the CR on the left — that's operator reconciliation in one glance.

Trace status transitions:

```
kubectl get flinkdeployment event-counter -n flink-lab -w
```

Watch `status.jobStatus.state` cycle `CREATED → RECONCILING → RUNNING`. If you edit `spec.job.parallelism` and re-apply, you'll see `RECONCILING → SUSPENDED → RECONCILING → RUNNING` on the redeploy — that's Week 5 Tue's upgrade-mode story in action.

## Extending after Week 5

- **Week 5 Wed** — bump `spec.job.parallelism` from 3 to 5, observe `CREATED` if you don't also bump `taskmanager.numberOfTaskSlots` or `taskManager.replicas`
- **Week 5 Thu** — install MinIO into `flink-lab`, un-comment the checkpoint config in `flinkdeployment-custom.yaml`, redeploy, watch checkpoints appear
- **Week 5 Fri** — full E2E: rebuild the JAR, rebuild + reload the image, delete + reapply the CR, time each step
- **Week 6+** — see the extending suggestions in `src/README.md`
