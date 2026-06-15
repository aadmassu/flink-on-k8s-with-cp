# Week 6 Monday — Lab: Deploy a Flink Job

**Time**: ~4 hours

## Prerequisites

CMF + Flink Operator already running in the cluster (`oc get pod -n cmf`, `oc get pod -n flink-operator`).

## Hands-on Lab — first Flink job

### Step 1 — confirm CMF reachable

```bash
# Get the CMF Route
oc get route -n cmf
CMF=$(oc get route -n cmf cmf -o jsonpath='{.spec.host}')

# Hit the version endpoint
curl -sk https://$CMF/cmf/api/v1/version | python3 -m json.tool
```

### Step 2 — list catalogs + environments

```bash
curl -sk https://$CMF/cmf/api/v1/catalogs    | python3 -m json.tool
curl -sk https://$CMF/cmf/api/v1/environments | python3 -m json.tool
```

The catalog points at the Kafka + Schema Registry endpoints. In production this is VM CP currently (`project_flink_targets_vm_cp`).

### Step 3 — apply a simple Flink job via CMF Statement API

A "statement" is a SQL job. Try one against the catalog:

```bash
cat <<EOF > /tmp/stmt.json
{
  "name": "training-tap",
  "environment": "training",
  "statement": "SELECT * FROM orders WHERE amount > 100 LIMIT 10"
}
EOF

curl -sk -X POST https://$CMF/cmf/api/v1/statements \
  -H "Content-Type: application/json" \
  -d @/tmp/stmt.json | python3 -m json.tool
```

### Step 4 — observe the FlinkApplication CR

```bash
# In the flink workload namespace
oc get flinkapplication -A
oc get flinkapplication training-tap-XXXX -o yaml | head -60

# Pods
oc get pod -l app.kubernetes.io/component=jobmanager
oc get pod -l app.kubernetes.io/component=taskmanager
```

### Step 5 — JM UI

```bash
oc port-forward svc/training-tap-XXXX 8081:8081 &
sleep 2
open http://localhost:8081  # or curl
```

Walk the UI: job graph, running tasks, checkpoint timeline.

### Step 6 — inspect a checkpoint

```bash
# Find the checkpoint path from job config
oc get flinkapplication training-tap-XXXX -o jsonpath='{.spec.flinkConfiguration.state\.checkpoints\.dir}'

# Verify checkpoints are landing (need NetApp S3 client)
# Instructor provides aws-cli aliased to NetApp:
NETAPP_S3="aws --endpoint-url https://netapp-s3.example.com s3"
$NETAPP_S3 ls s3://netapp-bucket/checkpoints/ | head
```

## Troubleshooting Exercise — three failures

### A — catalog has wrong bootstrap

Modify the catalog to point at a non-existent Kafka. Re-submit job. Capture:
- CMF response
- Operator log
- JM log

### B — TM cannot reach Kafka

If you have access, apply a NetworkPolicy blocking TM → Kafka. Observe `org.apache.kafka.common.errors.TimeoutException` in TM log.

### C — checkpoint store unreachable

Set `s3.endpoint` to a bad URL. Job stays RUNNING but checkpoints fail. JM shows checkpoint failures in UI + log.

## Deliverable — `deliverables/<you>/week06/monday.md`

1. **CMF inventory** — catalogs, environments, statements visible to you
2. **One successfully running job** — name + JM/TM pod counts + UI screenshot
3. **One checkpoint** — confirm it landed in NetApp S3
4. **Three failure modes** — symptom + root cause + recovery
