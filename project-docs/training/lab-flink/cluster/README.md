# cluster — Light Kafka + topics + producer

Item 2 in the lab: bring up the smallest working KRaft-mode Kafka via CFK, create the source/sink topics, and start a producer that streams synthetic events.

## Contents

- `kafka.yaml` — 1 KRaftController + 1 Kafka broker
- `topic.yaml` — `events-in` (source) + `counts-out` (sink), 3 partitions each
- `producer.yaml` — Kubernetes Job that emits `user-N|action|timestamp` lines to `events-in`

## Apply order

Order matters — the CFK operator reconciles from KRaft → Kafka → Topics → Producer. Apply top-down:

```
oc      apply -f kafka.yaml    -n flink-lab
kubectl apply -f kafka.yaml    -n flink-lab

# Wait for both kraftcontroller-0 and kafka-0 to be Ready (~3 min)
oc      wait --for=condition=Ready pod/kafka-0 -n flink-lab --timeout=300s
kubectl wait --for=condition=Ready pod/kafka-0 -n flink-lab --timeout=300s

oc      apply -f topic.yaml    -n flink-lab
oc      apply -f producer.yaml -n flink-lab
kubectl apply -f topic.yaml    -n flink-lab
kubectl apply -f producer.yaml -n flink-lab
```

## Verify events are flowing

```
oc      logs -n flink-lab job/event-generator --tail 20
kubectl logs -n flink-lab job/event-generator --tail 20
```

You should see lines like:

```
user-3|click|1720123456
user-7|view|1720123456
user-1|purchase|1720123457
...
```

## Inspect the topics from inside the broker

```
oc      exec -n flink-lab kafka-0 -- kafka-console-consumer \
  --bootstrap-server localhost:9092 --topic events-in --from-beginning --max-messages 5
kubectl exec -n flink-lab kafka-0 -- kafka-console-consumer \
  --bootstrap-server localhost:9092 --topic events-in --from-beginning --max-messages 5
```

## Why 3 partitions

The lab's Flink job runs at parallelism 3 to demonstrate one source task per Kafka partition — a canonical mapping. If you drop to 1 partition, all events land on one source task and parallelism is wasted.

## Why plain-text (not Avro)

To keep the lab focused on Flink concepts (Week 5 Mon + Tue), we skip Schema Registry. In production every event is Avro-encoded against a Schema Registry — Week 4 Wednesday covered that. See [Week 4 CFK](../../Week-04-CFK/03-Wednesday/discussion.md) for the SR story.
