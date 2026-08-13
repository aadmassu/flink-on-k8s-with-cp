# Week 4 Wednesday — Lab: Inspect + Test Listeners

**Time**: ~4 hours

## Hands-on Lab — map every CFK listener

### Find every listener configured on the running cluster

```bash
oc get kafka kafka -o jsonpath='{.spec.listeners}' | python3 -m json.tool
```

In your runbook, fill in this table per listener:

| Name | Port | TLS | Auth | External? | Service / Route name |
|---|---|---|---|---|---|

Confirm against what's actually deployed:

```bash
oc get svc -l app=kafka
oc get route -l app=kafka 2>/dev/null
```

### Trace one cluster-internal connection (broker ↔ broker)

```bash
# Pick broker 0
oc exec kafka-0 -c kafka -- bash -c \
  "openssl s_client -connect kafka-1.kafka.svc.cluster.local:9091 -showcerts </dev/null 2>/dev/null | grep subject"
```

Verify the cert subject matches the broker's SAN.

### Trace one client → external listener connection

```bash
# Get the bootstrap server from the broker advertised listener
oc get kafka kafka -o jsonpath='{.status.kafkaListenerStatus.external.bootstrapServer}'

# From a client machine that can reach the corporate network:
openssl s_client -connect <bootstrap>:9092 -servername <bootstrap> -showcerts </dev/null
```

If you don't have an  the platform client reachable, use `oc debug node/<worker>` and run from there.

### Produce + consume via the external listener (smoke test)

```bash
# Create a topic via the in-cluster bootstrap
oc exec kafka-0 -c kafka -- kafka-topics --bootstrap-server kafka.<you>-training.svc.cluster.local:9092 \
  --create --topic week04-test --partitions 3 --replication-factor 3

# Produce
echo "hello-cfk" | oc exec -i kafka-0 -c kafka -- \
  kafka-console-producer --bootstrap-server kafka.<you>-training.svc.cluster.local:9092 --topic week04-test

# Consume
oc exec kafka-0 -c kafka -- \
  kafka-console-consumer --bootstrap-server kafka.<you>-training.svc.cluster.local:9092 --topic week04-test --from-beginning --max-messages 1 --timeout-ms 5000
```

## Troubleshooting Exercise — break the advertised listener

```bash
# Set advertised listener to something garbage
oc patch kafka kafka --type=merge -p '{"spec":{"listeners":{"external":{"advertisedListener":{"externalAccessType":"loadBalancer","prefix":"broken.example.invalid"}}}}}'

# Try connecting from outside the cluster — bootstrap works, first produce fails
# Read the error message — it should name the bogus host

# Revert
oc patch kafka kafka --type=merge -p '{"spec":{"listeners":{"external":{"advertisedListener":null}}}}'
```

## Deliverable — `deliverables/<you>/week04/wednesday.md`

1. **Listener inventory table** (the one above, filled in)
2. **One successful TLS connection trace** to each listener via `openssl s_client`
3. **One successful produce + consume** through the external listener
4. **Broken-advertised-listener experiment** — error message + your explanation of why bootstrap worked but produce didn't
5. **The three site-specific listener decisions** — why 9091 vs 9092 vs 9094 exist (cross-ref tracker 2.9 + 2.10)
