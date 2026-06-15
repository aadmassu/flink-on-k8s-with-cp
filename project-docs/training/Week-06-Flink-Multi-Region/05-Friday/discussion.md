# Friday — DR Exercise (break-things finale)

**Time**: ~90 min
**Diagram**: [`64-dr-failover.drawio`](64-dr-failover.drawio)

## Learning objective

> **Run a full DR drill in the training cluster — destroy half the cluster and recover. Practice the full chain Weeks 1-6 covered.**

## Architecture Discussion (~30 min)

Today integrates everything. You'll:

1. Pick a failure scenario from the catalog
2. Trigger it
3. Detect it (from metrics or status)
4. Diagnose (which layer broke — K8s? CFK? Kafka? Flink?)
5. Recover
6. Verify
7. Write the postmortem

### The four-layer mental model

```
Layer 4: Workloads        Flink jobs, application consumers/producers
Layer 3: Kafka data plane Topics, partitions, ISR, consumer groups
Layer 2: CFK control plane Operator, CRs, status conditions
Layer 1: OCP / AWS         Pods, nodes, network, storage, IAM
```

Most failures live in one layer but **manifest as a problem in a higher layer**. Triage means tracing from the symptom (top) to the cause (somewhere below).

### The investigation framework

When something breaks in production:

1. **Is anything alerting?** — check Grafana/Splunk first
2. **Layer 1 — are nodes Ready?** — `oc get nodes`
3. **Layer 2 — are CR statuses healthy?** — `oc get kafka,kraftcontroller,flinkapplication`
4. **Layer 3 — Kafka topic health?** — `kafka-topics --describe`, ISR, leader-not-available
5. **Layer 4 — workload symptoms?** — Flink job status, consumer lag

This is the inverse of the customer's perception (they see Layer 4 first). The skill is descending fast.

### DR drill scenarios (pick one)

A. **CFK operator dies** — operator namespace fails. Can workloads still serve?
B. **One AZ loses power** — 1/3 of broker + controller pods gone. Quorum at risk?
C. **NetApp S3 unreachable** — Flink can't checkpoint. How long until backpressure → job failure?
D. **Okta egress blocked** — no new OAuth tokens. Existing connections work?
E. **Schema Registry data loss** — `_schemas` topic corrupt. Recovery from cluster link?
F. **CMF DB unreachable** — SQL Server gone. Are running Flink jobs still running?

Each represents a real failure mode the team needs to be able to handle.

## DR Drill Lab (~60 min)

See `../05-friday/lab.md`.

## Q&A

1. Which of A-F has the worst RPO? Worst RTO?
2. Which of A-F can  the platform tolerate without operator action?
3. After completing the drill, what's the one alert you'd add immediately?
4. What's the postmortem template you'd advocate in production?


## Added Enhancement — Disaster Recovery Game Day

Scenario:

Region A Failure

Students must:

1. Validate cluster links
2. Validate topic replication
3. Validate consumer group migration
4. Recover Flink workloads
5. Restore application traffic

Final presentation required.
