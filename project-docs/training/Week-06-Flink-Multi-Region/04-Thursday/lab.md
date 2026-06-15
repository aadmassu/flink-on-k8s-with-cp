# Week 6 Thursday — Lab: Rack Awareness + DR Design

**Time**: ~4 hours (lighter — mostly design)

## Hands-on Lab — rack-aware placement

CFK supports rack-aware partition placement via OCP node topology labels.

### Step 1 — inspect node topology labels

```bash
oc get nodes -o json | python3 -c '
import json, sys
d = json.load(sys.stdin)
for n in d["items"]:
  labels = n["metadata"]["labels"]
  zone = labels.get("topology.kubernetes.io/zone")
  rack = labels.get("topology.kubernetes.io/region")
  print(f"{n[\"metadata\"][\"name\"]}: zone={zone} region={rack}")
'
```

For ROSA, nodes are labeled with AWS AZ as `topology.kubernetes.io/zone`.

### Step 2 — confirm brokers are rack-aware

```bash
oc get kafka kafka -o jsonpath='{.spec.rackAssignment}' ; echo
oc exec kafka-0 -c kafka -- cat /opt/kafka/config/server.properties | grep -i rack
```

If `broker.rack` is set per Pod, replicas should distribute across AZs.

### Step 3 — verify partition distribution

```bash
# Use kafka-topics --describe and check that replicas of each partition land on brokers in different racks
oc exec kafka-0 -c kafka -- kafka-topics \
  --bootstrap-server kafka:9092 --describe --topic source-orders
```

Cross-reference broker.id with node label.

## Hands-on Lab Part 2 — design a DR runbook

(No commands — pure design exercise. Bring it to Friday's DR drill.)

For your training cluster, document:

### Section A — current state

- How many brokers, which AZs?
- KRaftController quorum size + AZ placement
- Cluster-link destination (if any)
- Checkpoint store location (NetApp S3 — in production, is it multi-region?)

### Section B — failure mode catalog

For each:
1. Single broker dies — RTO?
2. Single AZ dies (1 broker + 1 controller) — RTO?
3. Full region dies — RTO + RPO?
4. NetApp S3 dies — Flink impact?
5. Okta dies — auth impact?

### Section C — runbook for each scenario

- Detection (alert)
- Decision (manual or automatic cutover?)
- Action steps (ordered)
- Verification
- Rollback

### Section D — practice schedule

- How often to drill?
- What's the test environment for DR?
- Who owns the runbook?

## Troubleshooting Exercise — broker kill in non-rack-aware deployment

In a copy of the cluster, set `broker.rack` to the same value on all brokers (or empty), then kill all brokers in one AZ. Observe ISR collapse on all topics whose replicas happen to share the AZ.

Compare with the rack-aware version: ISR loses 1 replica per partition (acceptable, min.insync=2 still met).

## Deliverable — `deliverables/<you>/week06/thursday.md`

1. **Node topology mapping** — your training cluster's broker → node → AZ table
2. **Rack-aware partition distribution proof** — `kafka-topics --describe` showing replicas on different broker.racks
3. **DR runbook draft** — Sections A-D
4. **Comparison: MRC vs cluster-link** — for the platform's current size + risk profile, your recommendation with reasoning
