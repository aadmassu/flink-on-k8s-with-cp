# flink-job — Flink job artifacts

Item 3 in the lab: the Flink jobs that make the platform useful. Two variants — pick either depending on whether you want a code walkthrough or just want to see Flink work.

## Variants

| File | Purpose | Prereq |
|---|---|---|
| `flinkdeployment-example.yaml` | Zero-code demo using bundled `StateMachineExample.jar` | none |
| `flinkdeployment-custom.yaml` | Custom `event-counter` reading `events-in` → `counts-out` | build the JAR from `src/` |
| `jar-server.yaml` | nginx serving the custom JAR to the cluster | apply before custom variant |
| `src/` | Maven project for the custom job | JDK 17 + Maven |

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
# produces target/event-counter.jar (~30 MB shaded)
```

### Step 2 — deploy jar-server + ConfigMap the first time

```
oc      apply -f jar-server.yaml -n flink-lab
kubectl apply -f jar-server.yaml -n flink-lab

# ConfigMap seeded from the built JAR
kubectl create configmap event-counter-jar \
  --from-file=event-counter.jar=src/target/event-counter.jar \
  -n flink-lab --dry-run=client -o yaml | kubectl apply -f -

# Restart the nginx Pod so the JAR mount refreshes
kubectl rollout restart deployment/jar-server -n flink-lab
```

### Step 3 — apply the FlinkDeployment CR

```
oc      apply -f flinkdeployment-custom.yaml -n flink-lab
kubectl apply -f flinkdeployment-custom.yaml -n flink-lab
```

### Step 4 — verify

```
# CR status
kubectl get flinkdeployment event-counter -n flink-lab

# JobManager + TaskManager Pods
kubectl get pods -n flink-lab -l app=event-counter

# Output — user counts landing on counts-out
kubectl exec -n flink-lab kafka-0 -- kafka-console-consumer \
  --bootstrap-server localhost:9092 --topic counts-out --max-messages 20
# expect: user-3=1, user-7=1, user-3=2, user-3=3, user-1=1, ...
```

### Step 5 — Flink UI

```
kubectl port-forward -n flink-lab svc/event-counter-rest 8081:8081
# open http://localhost:8081
```

Inspect: DAG shape, running/idle slots, checkpoint history.

## What this covers for Week 5 Monday + Tuesday

**Monday — Flink Architecture**

- JM Pod = the master (`kubectl logs -n flink-lab event-counter-<jm-pod>` shows job graph submission + checkpoint coordination lines)
- TM Pods = the workers (logs show operator instantiation + slot allocation)
- MinIO Pod = state / checkpoint durability (see Enterprise Components — Week 5 Thu preview)
- Kafka Pods = sources + sinks

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
- **Week 5 Thu** — add MinIO checkpoints (already in `flinkdeployment-custom.yaml`); poke at CMF via port-forward
- **Week 5 Fri** — full E2E: rebuild the JAR, redeploy via ConfigMap swap, time each step
- **Week 6+** — see the extending suggestions in `src/README.md`
