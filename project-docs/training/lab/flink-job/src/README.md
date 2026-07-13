# src — Custom Flink job source

Minimal Maven project for the `event-counter` job — a per-user running count that keys `events-in` by user ID and writes `userId=count` records to `counts-out`.

## Build

```
cd src/
mvn package
```

The shaded JAR lands at `target/event-counter.jar`.

## Deploy to the lab

```
# Load the fresh JAR into a ConfigMap the jar-server serves
kubectl create configmap event-counter-jar \
  --from-file=event-counter.jar=target/event-counter.jar \
  -n flink-lab --dry-run=client -o yaml | kubectl apply -f -

# Roll the jar-server so it picks up the new JAR
kubectl rollout restart deployment/jar-server -n flink-lab

# Apply the FlinkDeployment CR (references http://jar-server.flink-lab.svc/event-counter.jar)
kubectl apply -f ../flinkdeployment-custom.yaml
```

For `oc`:

```
oc create configmap event-counter-jar \
  --from-file=event-counter.jar=target/event-counter.jar \
  -n flink-lab --dry-run=client -o yaml | oc apply -f -
oc rollout restart deployment/jar-server -n flink-lab
oc apply -f ../flinkdeployment-custom.yaml
```

## Verify the job

```
kubectl get flinkdeployment event-counter -n flink-lab
# spec.job.state should progress CREATED -> RECONCILING -> RUNNING

kubectl exec -n flink-lab kafka-0 -- kafka-console-consumer \
  --bootstrap-server localhost:9092 --topic counts-out --max-messages 20
# expect lines like: user-3=1, user-3=2, user-7=1, user-3=3, ...
```

## Code layout

```
src/
├── pom.xml
├── README.md   (this file)
└── src/main/java/dev/lab/
    └── EventCounter.java
```

## What the code demonstrates (mapping to bootcamp weeks)

| Concept | Where in EventCounter.java | Week / Day |
|---|---|---|
| Kafka source | `KafkaSource.builder()` | W5 Mon (sources) |
| keyBy partitioning | `.keyBy(userId -> userId)` | W5 Mon, W6 Mon |
| Keyed `ValueState` | `PerKeyCounter.countState` | W5 Mon (state), W6 Wed |
| Kafka sink + delivery guarantee | `KafkaSink.setDeliveryGuarantee(AT_LEAST_ONCE)` | W6 Thu |
| Operator naming | `.name("extract-userId")` etc. | W5 Wed (chains/tasks in the UI) |

## Extending

For further exercises the trainee can layer on:

- Swap `AT_LEAST_ONCE` for `EXACTLY_ONCE` and re-observe the sink latency (Week 6 Thu)
- Add a 1-minute tumbling window between `keyBy` and the counter (Week 6 Mon)
- Add state TTL to `PerKeyCounter` and observe cleanup (Week 6 Wed)
