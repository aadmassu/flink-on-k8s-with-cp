# Week 5 Thursday — Lab: Trace Every External Dependency

**Time**: ~3 hours

Three exercises: enumerate every external system a Flink job talks to, verify each one, and pick one to *simulate a fault* against so you see the symptom.

Every `oc` command is paired with its `kubectl` equivalent.

---

## Prerequisite Setup

Shared sandbox from [`project-docs/training/lab-flink/`](../../lab-flink/). For today, layer on CMF + MinIO so the "enterprise components" story is visible end-to-end.

### Enable CMF in the umbrella chart

Edit `lab-flink/platform-chart/values.yaml` → set `cmf.enabled: true` and provide a valid `cmf.license.secretRef` (CMF requires a Confluent license Secret in `flink-lab`). Then upgrade:

```
cd ../../lab-flink/platform-chart
helm upgrade lab-platform . -n flink-lab -f values.yaml
```

Wait until the `lab-platform-cmf-*` Pod is Ready.

### Install MinIO for the S3 checkpoint store

```
helm repo add minio https://charts.min.io/
helm repo update
helm install minio minio/minio \
  --namespace flink-lab \
  --set resources.requests.memory=512Mi \
  --set persistence.size=10Gi \
  --set rootUser=minio,rootPassword=minio123 \
  --set buckets[0].name=flink-checkpoints,buckets[0].policy=none
```

### Point a Flink job at MinIO for checkpoints

Save as `stateful-flinkdeployment.yaml`:

```yaml
apiVersion: flink.apache.org/v1beta1
kind: FlinkDeployment
metadata:
  name: stateful-demo
  namespace: flink-lab
spec:
  image: flink:1.18
  flinkVersion: v1_18
  serviceAccount: flink
  flinkConfiguration:
    state.checkpoints.dir: "s3://flink-checkpoints/stateful-demo/"
    state.backend: rocksdb
    execution.checkpointing.interval: "10 s"
    s3.endpoint: "http://minio.flink-lab.svc:9000"
    s3.access-key: "minio"
    s3.secret-key: "minio123"
    s3.path.style.access: "true"
  jobManager:
    resource: {memory: "1024m", cpu: 0.5}
  taskManager:
    resource: {memory: "1024m", cpu: 0.5}
  job:
    jarURI: local:///opt/flink/examples/streaming/StateMachineExample.jar
    parallelism: 2
    upgradeMode: last-state
```

```
oc      apply -f stateful-flinkdeployment.yaml
kubectl apply -f stateful-flinkdeployment.yaml
```

Verify checkpoints landing in MinIO:

```
oc      exec -n flink-lab deploy/minio -- ls /export/flink-checkpoints/
kubectl exec -n flink-lab deploy/minio -- ls /export/flink-checkpoints/
```

You should see checkpoint chunk directories appearing every ~10 s.

---

## Lab 1 — Enumerate dependencies for one job

**Goal**: for a specific FlinkDeployment CR, produce a full "external dependencies" list.

Pick a CR you used earlier this week. For each of the following, extract the actual endpoint from the CR + operator config + Flink config:

- **CMF endpoint** (from the deploy env)
- **Catalog** (from the CMF Environment/Catalog CRs — check `spec.kafkaCatalog` or `spec.hiveCatalog`)
- **JAR source** (from `spec.job.jarURI`)
- **HA metadata store** (from `spec.flinkConfiguration.high-availability.*`)
- **Checkpoint storage** (from `spec.flinkConfiguration.state.checkpoints.dir`)
- **Savepoint storage** (from `spec.flinkConfiguration.state.savepoints.dir`)
- **Metrics reporter target** (from `spec.flinkConfiguration.metrics.reporter.*`)

For each row, write down: (a) endpoint URL / path, (b) which credential Secret it uses (if any), (c) whether the job survives short outages of it.

---

## Lab 2 — Verify each dependency is actually reachable

**Goal**: prove each connection works, not just that the config exists.

For each dep from Lab 1:

### 2a. CMF ↔ database

```bash
oc      logs -n <namespace> deployment/confluent-manager-for-apache-flink --tail 100 | grep -iE "database|connection|jdbc"
kubectl logs -n <namespace> deployment/confluent-manager-for-apache-flink --tail 100 | grep -iE "database|connection|jdbc"
```

Look for successful DB connection lines. If you see reconnect loops → DB reachability issue.

### 2b. Checkpoint / Savepoint S3

Look at the last successful checkpoint timestamp in Flink UI (Checkpoints tab). Compare to now. If more than N × checkpoint-interval old, storage is broken.

### 2c. Artifactory JAR download

Check the job Pod's init logs for the JAR download step:

```bash
oc      logs -n <namespace> <flinkdeployment-name>-jobmanager-<pod-suffix> --tail 200 | grep -iE "downloading|fetch|artifactory"
```

Any 4xx / 5xx there is a JAR reachability problem.

### 2d. Metrics reporter → Prometheus / Dynatrace

Port-forward the JM REST and check `/metrics`:

```bash
oc      port-forward -n <namespace> svc/<flinkdeployment-name>-rest 8081:8081
curl -sf http://localhost:8081/jobs 2>&1 | head
```

If the metrics scrape endpoint works but Prometheus isn't picking it up, that's a ServiceMonitor / target-config issue on the Prom side (out of scope for Flink).

### 2e. Catalog lookup

If you have SQL Gateway access (via CMF), run:

```
SHOW CATALOGS;
SHOW TABLES;
```

Any table you defined earlier should appear. Missing = catalog persistence broken.

---

## Lab 3 — Simulate one dependency fault (controlled)

**Goal**: pick ONE non-load-bearing dependency, break it, see the resulting symptom.

**Safe options** (won't crash the job):

- **Metrics reporter** — misconfigure the Prometheus endpoint. Job keeps running; only observability degrades. Fix in a minute.
- **JAR source** — hard to do safely on a running job (it caches the JAR locally). Skip this one for live labs.

**Unsafe options** (will break the job):

- **Checkpoint storage** — revoke S3 credentials briefly. Watch checkpoint failures pile up in the Coordinator log until you restore.
- **HA metadata ConfigMap** — delete it. Watch the JM lose leadership and refuse new checkpoints.

Recommendation for this lab: pick the metrics reporter — safe and visible. Change `spec.flinkConfiguration.metrics.reporter.prom.host` to `nonexistent-host` for 10 min:

```bash
oc      edit flinkdeployment -n <namespace> <flinkdeployment-name>
kubectl edit flinkdeployment -n <namespace> <flinkdeployment-name>
```

Watch the JM log for Prometheus-reporter failures. Restore the value; watch the failures stop.

In your notes: exactly what log line surfaced the fault? How long after the config change did the symptom appear?

---

## Deliverable — `deliverables/<you>/week05/thursday.md`

1. **Dependencies inventory table** — one row per external system, with endpoint + credential Secret + outage-survival property
2. **Verification results** — pass/fail per dependency from Lab 2, with the specific log line or command output that proved it
3. **Fault simulation writeup** — which dep, how you broke it, what symptom, how long to appear, how to fix
4. **Two questions** — anything about the Enterprise Components stack you can't answer from the CRs + logs alone
