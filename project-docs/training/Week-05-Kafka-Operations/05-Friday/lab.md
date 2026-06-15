# Week 5 Friday — Lab: Six Failure Modes

**Time**: ~4 hours
**SAFETY**: training project only. Confirm with instructor before each.

## Hands-on Lab — six scenarios, six diagnoses

For each scenario, capture: **symptom → metric/log signature → diagnostic command → recovery**.

### Scenario 1 — fill the disk

```bash
# Quickly fill a broker's data volume
oc exec kafka-2 -c kafka -- bash -c \
  'dd if=/dev/zero of=/var/lib/kafka/data/filler bs=1M count=8192'

# Watch broker behavior
oc logs kafka-2 -c kafka --tail=50 -f | grep -i -E 'space|disk'

# Recovery
oc exec kafka-2 -c kafka -- rm /var/lib/kafka/data/filler
oc delete pod kafka-2  # restart to clear partition error state
```

### Scenario 2 — slow broker (CPU saturation)

```bash
# Pin CPU on one broker
oc exec kafka-1 -c kafka -- bash -c 'yes > /dev/null &' &

# Observe ISR shrink in metrics
oc port-forward kafka-0 7203:7203 &
curl -s http://localhost:7203/metrics | grep under_replicated

# Recovery
oc delete pod kafka-1
```

### Scenario 3 — network partition (NetworkPolicy block)

```bash
# Apply a deny-all NetworkPolicy in your training namespace
cat <<EOF | oc apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-broker
spec:
  podSelector:
    matchLabels:
      statefulset.kubernetes.io/pod-name: kafka-2
  policyTypes: [Egress]
EOF

# Watch ISR collapse for partitions where kafka-2 was a replica
oc exec kafka-0 -c kafka -- kafka-topics --bootstrap-server kafka:9092 --describe --topic orders

# Recovery
oc delete networkpolicy deny-broker
```

### Scenario 4 — ACL regression

```bash
# Add a deny ACL for your test principal
oc exec kafka-0 -c kafka -- kafka-acls \
  --bootstrap-server kafka:9092 \
  --add --deny-principal 'User:CN=test' \
  --operation Write --topic orders

# Try to produce — should fail with TOPIC_AUTHORIZATION_FAILED
echo "should-fail" | oc exec -i kafka-0 -c kafka -- \
  kafka-console-producer --bootstrap-server kafka:9092 --topic orders \
  --producer-property security.protocol=SSL

# Recovery
oc exec kafka-0 -c kafka -- kafka-acls \
  --bootstrap-server kafka:9092 \
  --remove --deny-principal 'User:CN=test' \
  --operation Write --topic orders
```

### Scenario 5 — Schema Registry down

```bash
# Scale SR to 0
oc scale deployment schemaregistry --replicas=0

# Try to register a schema (will fail — connection refused)
# Recovery
oc scale deployment schemaregistry --replicas=1
```

### Scenario 6 — cluster-link cert expired (simulated)

Confirm with instructor — this one needs an actual cluster link configured. If not, observe via configuration inspection:

```bash
oc get kafka kafka -o jsonpath='{.spec.clusterLink}' 2>/dev/null
oc exec kafka-0 -c kafka -- kafka-cluster-links --bootstrap-server kafka:9092 --list
```

## Deliverable — `deliverables/<you>/week05/friday.md` + cheat-sheet

A one-page "Kafka Failure Cheat Sheet":

| Failure | Customer symptom | First diagnostic | Recovery |
|---|---|---|---|
| Disk full | producer NotEnoughReplicas | `oc exec kafka-N -- df -h` | clear / extend / restart |
| Slow broker | ISR shrinks | request_handler_avg_idle % | restart broker |
| Network partition | all brokers isolated | NetworkPolicy check | remove block |
| Auth regression | TOPIC_AUTHORIZATION_FAILED | kafka-acls --list | restore ACL |
| SR down | Avro/Proto clients fail | `oc get pod -l app=schemaregistry` | scale SR back up |
| Link cert | dest lag growing | `kafka-cluster-links --describe` | rotate cert |

Plus:

1. **Per-scenario notes** — what surprised you about diagnosis order
2. **Your personal ordering** — which of the 6 would you check first when a customer says "Kafka is down"
3. **Reflection** — what does Week 5 add that Week 4 didn't (Kafka data plane vs CFK control plane)
