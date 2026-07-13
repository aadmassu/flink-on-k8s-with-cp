# Week 6 Friday — Q&A Answers (Graduation)

Answers to the discussion Q&A in [`discussion.md`](discussion.md#qa--the-graduation-questions).

---

## 1. Walk the DAG in the capstone diagram top-to-bottom, naming every layer's role.

From closest-to-the-record down to closest-to-the-hardware:

1. **Kafka Topic** — the data itself, partitioned and retained. Sources and sinks of every job.
2. **Kafka Client / Source Operator** — the Flink adapter that reads (or writes) records via Kafka's protocol, handles offsets, negotiates OAUTHBEARER.
3. **Flink Operators** (Map / KeyBy / Window / Aggregate / Sink) — the actual per-record logic, chained into tasks, each parallel instance in a slot.
4. **Checkpoint Coordinator** — JM-side component that broadcasts checkpoint barriers, tracks operator ACKs, marks checkpoints complete or failed.
5. **JobManager** — job orchestrator: parses the DAG, schedules tasks into slots, coordinates checkpoints, decides restarts on failure.
6. **TaskManagers** — compute layer: JVM processes hosting slots, each slot running one parallel instance of one operator chain.
7. **Flink Kubernetes Operator** — reconciles the `FlinkDeployment` CR into JM Deployment + TM Deployment + Services + ConfigMaps + HA Lease.
8. **Kubernetes** — Pods, Services, RBAC, NetworkPolicy, ResourceQuota. The substrate every above layer runs on.
9. **PKI / TLS / OAuth** — identity + confidentiality: cert-manager + KeyFactor for X.509, Okta OAuth for OAUTHBEARER, MDS for token validation.
10. **NetApp S3 + Artifactory** — durable persistence: S3 for checkpoints/savepoints, Artifactory for JARs.

Each layer serves the layer *above* it and depends on the layer *below*. That's the mental model that turns a Flink incident into a directed search.

## 2. Output stopped 10 min ago, everything else looks green — where do you look FIRST?

**Flink UI → Checkpoints tab.**

Reasoning:

- Kafka-side (broker, lag) is "green" — data is being *offered* to the job
- Sinks would show errors if writes failed — assume they'd show
- Pod/K8s green means JM+TM are up

If checkpoints are **failing** or **haven't completed for 10 min**: something in the DAG has stalled (backpressure at a sink, state alignment issue, S3 write failure). The 10-min output stall matches a checkpoint stall.

If checkpoints are **succeeding but no output**: the DAG is processing but the sink isn't emitting. Check the sink operator's `numRecordsOut` and the source's `numRecordsIn` — one of them has stalled.

Secondary sweeps after the checkpoints tab:

- Source connector metrics — is Kafka offset advancing?
- Backpressure indicator on the operators — is any operator saturated?
- JM logs — any recent operator failure or restart-strategy delay?

Anti-pattern: jumping straight to Kafka broker logs. That's the "seen it before, muscle memory" trap. Flink's checkpoints tab is the fastest signal for "is the DAG healthy right now."

## 3. Difference between the operational surface an SRE handles vs a Flink developer handles?

**SRE surface (cluster / infrastructure):**

- Pod lifecycle, restarts, OOMKilled, node evictions
- Cert renewals, TLS handshake failures, PKI expiry
- RBAC, NetworkPolicy, ResourceQuota
- Operator upgrades (Flink Operator, CFK)
- S3 / storage availability

**Flink developer surface (job / application):**

- DAG shape, operator selection, chain boundaries
- State schema, TTL policy, backend choice (HashMap vs RocksDB)
- Watermarks, window semantics, allowed lateness
- Restart strategy config, upgrade mode choice, exactly-once semantics
- Business logic correctness

**Overlap** — the *symptom is a stuck job* zone:

- Pod dies mid-checkpoint → SRE looks at Pod eviction reason, developer looks at checkpoint-declined semantics
- State grows unbounded → developer implements TTL, SRE monitors disk usage + adjusts quotas
- OAuth token subject not in rolebindings → SRE fixes the rolebinding, developer verifies the source connects

The whole point of the capstone diagram is to make this handoff explicit. When a job is stuck, walk the diagram: identify which layer, hand to the right owner.

## 4. Given six common failures, which surfaces fastest as an alert, which is silent longest?

**Fastest** — Pod crash / OOMKilled. Kubernetes emits Events immediately, Prometheus `up == 0` fires within ~30s on the standard scrape interval, PagerDuty within a minute.

**Silent longest** — **keyed state growing unboundedly** (missing TTL). No metric fires until:
- Disk fills (TM OOMKilled — but by that time it's already too late), or
- Checkpoint size crosses a threshold (only alerts if you configured one), or
- Checkpoint duration exceeds interval (Backpressure alert)

State growth can silently run for weeks before it surfaces. Instrument state size trend and alert on absolute size or growth rate. It's the least-taught, highest-impact watchpoint in production Flink.

Ranking between them (fast → slow):

1. Pod crash — seconds
2. Job FAILED state — under a minute
3. Checkpoint declines — minutes (rate depends on interval)
4. Kafka source lag — depends on lag alert threshold
5. Watermark stall — minutes to hours depending on alert
6. State size growth — days to weeks (if not instrumented)

## 5. If you had to pick ONE thing from this bootcamp to teach the next cohort first, what would it be and why?

**State.**

Everything derives from state:

- Understand state → understand why checkpointing matters (it's how state survives)
- Understand checkpointing → understand fault tolerance (it's how the job recovers)
- Understand fault tolerance → understand restart strategies + upgrade modes (they're all state-preserving vs state-discarding choices)
- Understand upgrade modes → understand the operator's job (savepoint choreography)
- Understand the operator → understand the platform (CRDs, reconcile loops, Kubernetes RBAC)

Without state, Flink is just another stream mapper. The load-bearing concept is that operators *remember* things between events, and everything above (checkpointing, HA, exactly-once, savepoints) is machinery to make that remembering reliable in the presence of failure and change.

Start with state, and every downstream concept has a hook to hang on. Start with anything else, and state comes at you as a special-purpose add-on rather than the thing that makes streaming actually work.

---

**Congratulations — you've finished the 6-week Flink-on-Kubernetes bootcamp.** Your Personal Master Runbook (see [`06-Review/week06-runbook-deliverable.md`](../06-Review/week06-runbook-deliverable.md)) is the artifact that carries this forward into on-call.
