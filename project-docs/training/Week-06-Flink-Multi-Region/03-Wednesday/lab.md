# Week 6 Wednesday — Lab: Stand Up a Cluster Link (Training)

**Time**: ~4 hours

## Hands-on Lab — link two CFK clusters

Since the training project can't actually touch VM CP, simulate by linking two CFK clusters in the training project (a "source" and a "destination"), both deployed via CR.

### Step 1 — verify both clusters exist

If only one cluster was deployed earlier, deploy a second one (`kafka-src`).

```bash
oc get kafka  # should see kafka and kafka-src
```

### Step 2 — produce data on source

```bash
oc exec kafka-src-0 -c kafka -- kafka-topics --bootstrap-server kafka-src:9092 \
  --create --topic source-orders --partitions 3 --replication-factor 3

for i in $(seq 1 500); do
  echo "src-msg-$i"
done | oc exec -i kafka-src-0 -c kafka -- \
  kafka-console-producer --bootstrap-server kafka-src:9092 --topic source-orders
```

### Step 3 — create the cluster link from kafka → kafka-src

```bash
cat <<EOF | oc apply -f -
apiVersion: platform.confluent.io/v1beta1
kind: ClusterLink
metadata:
  name: src-to-dst
spec:
  destinationKafkaRest:
    endpoint: https://kafka.svc.cluster.local:8090
  sourceKafkaCluster:
    bootstrapEndpoint: kafka-src.svc.cluster.local:9091
  mirrorTopics:
    - name: source-orders
EOF
```

Watch:

```bash
oc get clusterlink src-to-dst -o yaml | grep -A 20 '^status:'
```

### Step 4 — verify mirror topic on destination

```bash
oc exec kafka-0 -c kafka -- kafka-topics --bootstrap-server kafka:9092 --list
oc exec kafka-0 -c kafka -- kafka-topics --bootstrap-server kafka:9092 \
  --describe --topic source-orders

# Consume from destination — should see the messages produced to source
oc exec kafka-0 -c kafka -- kafka-console-consumer \
  --bootstrap-server kafka:9092 --topic source-orders --from-beginning \
  --max-messages 10 --timeout-ms 10000
```

### Step 5 — measure lag

```bash
oc exec kafka-0 -c kafka -- kafka-cluster-links \
  --bootstrap-server kafka:9092 \
  --describe --link src-to-dst
```

### Step 6 — simulate cutover

```bash
# Pause source — stop producing to kafka-src
# Wait for destination lag to reach 0

# Promote: in a real production environment this means producers/consumers switch bootstrap
# For training, just confirm offsets match

oc exec kafka-src-0 -c kafka -- kafka-run-class kafka.tools.GetOffsetShell \
  --broker-list kafka-src:9092 --topic source-orders --time -1

oc exec kafka-0 -c kafka -- kafka-run-class kafka.tools.GetOffsetShell \
  --broker-list kafka:9092 --topic source-orders --time -1
```

Should be equal.

## Troubleshooting Exercise — break the link

### A — wrong bootstrap

Patch the ClusterLink to point at a non-existent source. Capture:
- `oc get clusterlink ... -o yaml` status
- operator log

### B — auth mismatch

If you can configure mTLS, do so but with a wrong client cert. Capture handshake failure in source broker log.

### C — network policy

Apply NetworkPolicy blocking destination → source. Lag grows. Capture metric.

## Deliverable — `deliverables/<you>/week06/wednesday.md`

1. **The ClusterLink CR + status** — showing connected + replicating
2. **Producer → consumer end-to-end trace** through the link
3. **Lag measurement** — at producer rest, lag should reach 0
4. **Cutover dry-run** — your step list for migrating ONE production topic in production
5. **One observation about the firewall** — what would tracker 2.10 need to permit in a real VM→CFK scenario?
