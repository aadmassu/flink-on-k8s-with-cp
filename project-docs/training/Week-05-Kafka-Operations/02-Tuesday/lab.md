# Week 5 Tuesday — Lab: Consumer Groups + Rebalance

**Time**: ~4 hours

## Hands-on Lab — run a 3-consumer group; trigger rebalance

### Step 1 — produce a continuous stream

In Terminal A, run a continuous producer:

```bash
oc exec -i kafka-0 -c kafka -- bash -c \
  'for i in $(seq 1 100000); do echo "msg-$i" ; sleep 0.05 ; done | \
   kafka-console-producer --bootstrap-server kafka.<you>-training.svc.cluster.local:9092 --topic orders'
```

### Step 2 — start 3 consumers in the same group

In three separate terminals:

```bash
# Terminal B
oc exec -it kafka-0 -c kafka -- kafka-console-consumer \
  --bootstrap-server kafka.<you>-training.svc.cluster.local:9092 \
  --topic orders --group week5-group \
  --property "print.partition=true"
```

Repeat in Terminals C and D.

Observe: with 6 partitions and 3 consumers, each consumer gets ~2 partitions.

### Step 3 — describe the consumer group

```bash
oc exec kafka-0 -c kafka -- kafka-consumer-groups \
  --bootstrap-server kafka.<you>-training.svc.cluster.local:9092 \
  --describe --group week5-group
```

Capture:
- Consumer-IDs and host
- Partitions assigned per consumer
- Current offset, log-end offset, LAG

### Step 4 — kill one consumer; watch rebalance

```bash
# Ctrl-C Terminal C
# Within ~3-5s, the 6 partitions should redistribute to 2 consumers (3 each)

# Watch the rebalance in B + D outputs

oc exec kafka-0 -c kafka -- kafka-consumer-groups \
  --bootstrap-server kafka.<you>-training.svc.cluster.local:9092 \
  --describe --group week5-group
```

### Step 5 — rejoin the third consumer; second rebalance

Restart Terminal C's consumer. Observe second rebalance back to 2 partitions each.

## Troubleshooting Exercise — induce continuous rebalance

```bash
# Start a consumer that processes too slowly
oc exec -it kafka-0 -c kafka -- bash -c '
  kafka-console-consumer --bootstrap-server kafka.<you>-training.svc.cluster.local:9092 \
    --topic orders --group slow-group \
    --consumer-property max.poll.interval.ms=5000 \
    --consumer-property session.timeout.ms=3000 \
    | while read msg; do sleep 10 ; echo "processed: $msg" ; done
'
```

The `sleep 10` exceeds `max.poll.interval.ms=5000`, so the consumer gets kicked. New rebalance, same problem, repeat forever.

```bash
oc exec kafka-0 -c kafka -- kafka-consumer-groups \
  --bootstrap-server kafka.<you>-training.svc.cluster.local:9092 \
  --describe --group slow-group
```

Watch the lag climbing while assignments oscillate.

## Deliverable — `deliverables/<you>/week05/tuesday.md`

1. **Group state snapshots** — 3 consumers / 2 consumers / 3 consumers again, with partition assignments
2. **Rebalance timing** — seconds from "consumer killed" to "consumption resumed on other consumers"
3. **Slow-consumer diagnostic** — what does `kafka-consumer-groups --describe` show during continuous rebalance?
4. **Your fix recommendation** — for the slow-group, what config knobs would you change?
