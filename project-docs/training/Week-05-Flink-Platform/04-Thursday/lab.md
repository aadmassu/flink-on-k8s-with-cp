# Week 5 Thursday — Lab: Trace Every External Dependency

**Time**: ~3 hours

Three exercises: enumerate every external system a Flink job talks to, verify each one, and pick one to *simulate a fault* against so you see the symptom.

Every `oc` command is paired with its `kubectl` equivalent.

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
