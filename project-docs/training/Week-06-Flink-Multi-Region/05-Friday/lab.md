# Week 6 Friday — Lab: DR Drill (Final Exercise)

**Time**: ~4 hours
**SAFETY**: training project ONLY. Confirm scenario with instructor.

## Hands-on Lab — pick one scenario, run the full cycle

Pick one of A-F from the discussion. Walk the full cycle. Document everything.

### Cycle steps (apply to whichever scenario you pick)

1. **Pre-state capture** — `oc get nodes`, `oc get kafka -o yaml`, Kafka topic describe, current consumer lag, Flink job status, NetApp S3 reachable from a TM pod
2. **Trigger the failure** — see scenario-specific commands below
3. **Detection** — what metric or status condition first reflected the failure? How fast?
4. **Diagnosis** — which layer? Walk top-down using the four-layer framework
5. **Recovery** — apply the fix
6. **Verification** — pre-state matches post-state for the things that should be unchanged
7. **Postmortem** — write up the timeline + lesson

### Scenario A — CFK operator dies

```bash
# Scale operator Deployment to 0
oc -n confluent-operator scale deployment confluent-operator --replicas=0

# Observe: existing Pods keep running; new CR applies don't take effect
# Try applying a small change to verify it doesn't reconcile
oc patch kafka kafka --type=merge -p '{"spec":{"podTemplate":{"annotations":{"test-mark":"AAAA"}}}}'
oc get kafka kafka -o jsonpath='{.status.conditions}' | python3 -m json.tool

# Recovery
oc -n confluent-operator scale deployment confluent-operator --replicas=1
```

Document: did existing brokers serve traffic during the outage?

### Scenario B — one AZ down (simulated)

```bash
# Cordon all nodes in one AZ
ZONE=$(oc get nodes -L topology.kubernetes.io/zone | awk 'NR==2{print $6}')
oc get nodes -l topology.kubernetes.io/zone=$ZONE
oc adm cordon <each-node-in-zone>

# Delete pods on those nodes to force rescheduling
for n in <nodes>; do
  oc get pods --field-selector=spec.nodeName=$n --all-namespaces
done

# Observe Kafka ISR, KRaft quorum, Flink job state

# Recovery
oc adm uncordon <each-node-in-zone>
```

### Scenario C — NetApp S3 unreachable

```bash
# Patch FlinkApplication CR with bad s3.endpoint
oc patch flinkapplication training-tap-XXXX --type=merge -p \
  '{"spec":{"flinkConfiguration":{"s3.endpoint":"https://no-such-host.example"}}}'

# Watch Flink checkpoint failures
oc port-forward svc/training-tap-XXXX 8081:8081 &
# UI shows checkpoint failures stacking up
# After 3 failed checkpoints in a row, job typically restarts

# Recovery — revert
oc patch flinkapplication training-tap-XXXX --type=merge -p \
  '{"spec":{"flinkConfiguration":{"s3.endpoint":"https://netapp-s3.example.com"}}}'
```

### Scenario D — Okta egress blocked

Confirm with instructor — needs NetworkPolicy permission. If allowed:

```bash
# Apply egress block (replace Okta CIDR with the actual one for your env)
cat <<EOF | oc apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: block-okta
spec:
  podSelector: {}
  policyTypes: [Egress]
  egress:
    - to:
        - ipBlock:
            cidr: 0.0.0.0/0
            except: [<OKTA-IP-CIDR>]
EOF

# Existing connections should work; new client logins should fail
# Test: try a new OAuth login from a fresh client

oc delete networkpolicy block-okta
```

### Scenario E — Schema Registry data loss

```bash
# Scale SR to 0 and delete its persistent state (if applicable)
oc scale deployment schemaregistry --replicas=0
# (SR state is in __schemas topic; you'd delete that topic in a real drill — DON'T)

# Restart SR; it rebuilds from __schemas topic
oc scale deployment schemaregistry --replicas=1
```

### Scenario F — CMF DB unreachable

Confirm with instructor.

```bash
# CMF stores state in SQL Server. Block egress to the DB.
# Running Flink jobs: should keep running (they have their own state)
# CMF API: should fail
# New job submissions: should fail
```

## Deliverable — `deliverables/<you>/week06/friday.md` + final personal runbook

1. **Pre-state capture** — every layer
2. **Scenario picked + trigger time**
3. **Full investigation log** — what you tried, in order, with timestamps
4. **Detection time** (trigger → first alert/symptom)
5. **Recovery time** (first action → verified recovery)
6. **Postmortem** — timeline + 3 lessons
7. **Personal Master Runbook v5 — final** — combine your weekly v1-v5 into one document
   - Per-layer troubleshooting checklist
   - "Common Common production symptoms" cheat sheet
   - Diagnostic command reference
   - Escalation contacts (Rick, Tom, Maha, Tushar)

This is the artifact you carry forward from the bootcamp.
