# Week 5 Monday — Lab: Topic Lifecycle End-to-End

**Time**: ~4 hours

## Hands-on Lab — create, observe, mutate, delete

### Step 1 — apply a KafkaTopic CR

```bash
cat <<EOF | oc apply -f -
apiVersion: platform.confluent.io/v1beta1
kind: KafkaTopic
metadata:
  name: orders
spec:
  replicas: 3
  partitionCount: 6
  configs:
    cleanup.policy: delete
    retention.ms: "604800000"
    min.insync.replicas: "2"
  kafkaClusterRef:
    name: kafka
EOF

# Watch the status come up
oc get kafkatopic orders -w &
sleep 30 ; jobs %1 && kill %1 2>/dev/null
oc get kafkatopic orders -o yaml | grep -A 20 '^status:'
```

### Step 2 — inspect from Kafka's side

```bash
oc exec kafka-0 -c kafka -- kafka-topics \
  --bootstrap-server kafka.<you>-training.svc.cluster.local:9092 \
  --describe --topic orders
```

Capture: partition count, replicas list per partition, leader, ISR.

### Step 3 — produce + consume and watch replication

```bash
# In Terminal A — produce
for i in $(seq 1 100); do
  echo "msg-$i"
done | oc exec -i kafka-0 -c kafka -- \
  kafka-console-producer --bootstrap-server kafka.<you>-training.svc.cluster.local:9092 \
  --topic orders --property "acks=all"

# In Terminal B — consume
oc exec kafka-0 -c kafka -- \
  kafka-console-consumer --bootstrap-server kafka.<you>-training.svc.cluster.local:9092 \
  --topic orders --from-beginning --max-messages 100 --timeout-ms 10000
```

### Step 4 — kill the leader of partition 0; observe re-election

```bash
# Find current leader of partition 0
LEADER=$(oc exec kafka-0 -c kafka -- kafka-topics \
  --bootstrap-server kafka.<you>-training.svc.cluster.local:9092 \
  --describe --topic orders | grep 'Partition: 0' | awk '{print $8}')
echo "Leader is broker.id=$LEADER"

# Delete that Pod (StatefulSet recreates)
oc delete pod kafka-$LEADER

# In another terminal, immediately:
while true; do
  oc exec kafka-0 -c kafka -- kafka-topics --bootstrap-server kafka.<you>-training.svc.cluster.local:9092 --describe --topic orders 2>/dev/null | grep 'Partition: 0'
  sleep 1
done
```

Capture the leader transition and the time until ISR recovers.

### Step 5 — mutate via the CR (add partitions)

```bash
oc patch kafkatopic orders --type=merge -p '{"spec":{"partitionCount":12}}'

# Watch — should go from 6 to 12 partitions
sleep 30
oc exec kafka-0 -c kafka -- kafka-topics --bootstrap-server kafka.<you>-training.svc.cluster.local:9092 --describe --topic orders | head -20
```

Note: Kafka allows partition addition but NOT removal. A removal would require recreating the topic.

## Troubleshooting Exercise — break min.insync.replicas

```bash
# Patch to require all 3 ISR
oc patch kafkatopic orders --type=merge -p '{"spec":{"configs":{"min.insync.replicas":"3"}}}'

# Kill one broker
oc delete pod kafka-2

# Producer should now fail with NOT_ENOUGH_REPLICAS
echo "this-should-fail" | timeout 30 oc exec -i kafka-0 -c kafka -- \
  kafka-console-producer --bootstrap-server kafka.<you>-training.svc.cluster.local:9092 --topic orders --property "acks=all"
```

Revert:

```bash
oc patch kafkatopic orders --type=merge -p '{"spec":{"configs":{"min.insync.replicas":"2"}}}'
```

## Deliverable — `deliverables/<you>/week05/monday.md`

1. **Topic-describe output** for `orders` (initial + after partition expansion)
2. **Leader transition timeline** — captured from Step 4
3. **The producer error from Step 6** — paste verbatim
4. **Your understanding of acks=all + min.insync.replicas=2** — one paragraph: what's the durability + availability tradeoff?
