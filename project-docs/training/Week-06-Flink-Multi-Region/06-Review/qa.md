# Week 6 — Q&A (20 reinforcement questions)

The capstone week. Q&A includes gap-fills for Flink SQL + watermarks + MirrorMaker 2 that the original plan emphasized.

---

## Monday — Flink Architecture

**Q1. CMF vs Flink Operator — what does each do?**
A. **CMF (Confluent Manager for Flink)** — API gateway + multi-tenant control. Holds catalogs (Kafka cluster pointers), environments, statements (SQL jobs). Translates SQL/Table API to Flink jobs. **Flink Operator** — K8s primitive that watches FlinkApplication CRs and renders Deployments/Services/ConfigMaps to spin up JobManager + TaskManager Pods. CMF calls Flink Operator by creating CRs.

**Q2. JobManager + TaskManager — roles and scaling axes.**
A. **JobManager (JM)** — coordinator. Accepts submissions, schedules tasks, drives checkpointing, handles recovery. One per Flink cluster (with HA standbys). Scale = HA setup. **TaskManager (TM)** — workers. Each has N task slots; each slot runs one parallel subtask. Scale TMs to scale throughput.

**Q3.  the platform checkpoint store — where + how authenticated?**
A. NetApp S3 (NOT AWS S3). Configured via `state.checkpoints.dir: s3://netapp-bucket/checkpoints/<job>/`. Endpoint override: `s3.endpoint: https://netapp-s3.example.com`. Credentials = K8s Secret created by ESO from CyberArk. Access keys not stored long-term in the Flink job config.

---

## Tuesday — Checkpoints + Savepoints (+ Flink SQL + Watermarks gap-fill)

**Q4. Checkpoint vs savepoint — what's the difference?**
A. Checkpoint = recurring, automatic, optimized for fast recovery (Flink's choice of format). Savepoint = explicit, durable, forward-compatible format (you can upgrade Flink and resume). Both are state snapshots; both go to NetApp S3 in production. You take savepoints for planned upgrades + migrations; checkpoints run continuously.

**Q5. Walk the checkpoint barrier flow.**
A. JM injects a numbered "barrier" record into every source. Barriers flow through the job graph alongside data. When an operator sees barrier N on ALL its input streams, it snapshots its state to S3 + forwards the barrier downstream. When all operators have snapshotted barrier N, the checkpoint is complete — JM records this as the new "latest complete checkpoint." Aligned (default) = wait for all input barriers; Unaligned = snapshot immediately, capture in-flight records.

**Q6. Exactly-once with Kafka source + Kafka sink — walk it.**
A. Source: committed offset is stored in the Flink CHECKPOINT, not in Kafka. Sink: uses Kafka transactions — phase 1 (pre-commit): write to Kafka in transaction, don't commit yet; phase 2 (commit): once checkpoint completes, commit the transaction. On crash: revert to last checkpoint, source rewinds to checkpointed offset, sink aborts uncommitted transaction. Result: each input record reaches sink exactly once.

**Q7. Flink SQL — what is it, and where does  the platform use it?**
A. (Gap-fill — the original plan emphasized this.) Flink SQL = ANSI SQL syntax for stream processing. CMF exposes it via "statements" — `SELECT ... FROM kafka_orders WHERE ...`. CMF compiles SQL to a Flink job graph + submits as FlinkApplication. Reduces the JVM/Scala/Java barrier to entry. In production it's the primary way analysts + non-Java teams interact with Flink.

**Q8. Watermarks — what are they and why are they critical?**
A. (Gap-fill.) Watermarks are how Flink tracks "event time" progress. A watermark of timestamp T means "no more events with timestamp < T will arrive." Used by window operators to know when to close a window + emit results. Without watermarks, windows never close (you'd be waiting forever for late data). Tuning watermarks = balancing latency (close windows fast) vs accuracy (capture late events).

**Q9. RocksDB state backend vs in-memory — when does  the platform use which?**
A. **In-memory** (HashMap state backend) — small state, low latency, fits in JVM heap. **RocksDB** — large state on local disk (TM Pod's PVC), can be much larger than heap.  the platform defaults to RocksDB for production jobs because state can grow large (joins, aggregations over windows); incremental checkpoints are cheaper. In-memory is for prototypes + small windowed counts.

---

## Wednesday — Cluster Linking (+ MirrorMaker 2 gap-fill)

**Q10. Cluster linking vs MirrorMaker 2 — what's the difference?**
A. **MirrorMaker 2 (MM2)** — runs as Kafka Connect connectors that consume from source, produce to destination. External process; requires offset translation; doesn't preserve cluster-side ACLs/configs. **Cluster Linking** — broker-native feature; destination cluster's brokers pull from source cluster's brokers. Preserves offset positions, replicates topic configs, simpler operationally. Confluent commercial feature.

**Q11. Why does the platform use cluster linking instead of MM2?**
A. (Gap-fill — original plan named MM2 explicitly.) Cluster linking preserves OFFSET POSITIONS — meaning a consumer that read up to offset 12345 on the source can switch to the destination and continue from 12345 without offset translation. MM2 requires explicit offset-translation logic. In production, the VM→CFK migration needs offset preservation for the consumer cutover step; cluster linking makes this trivial.

**Q12. The 9094 mTLS path — recap from Week 4 in cluster-link context.**
A. Tracker 2.10. VM CP brokers (source) connect to CFK brokers (destination) over port 9094, mTLS authenticated. Need firewall exception because 9094 isn't in default policy. Once link is up, mirror topics appear on CFK side, read-only, with VM-side offsets preserved.

**Q13. Cluster-link cutover — the 7 ordered steps.**
A. (1) Stand up CFK cluster; (2) Configure cluster link CFK→VM (CFK destination, VM source); (3) Cluster link replicates topics + offsets; (4) Verify CFK caught up (lag = 0); (5) Pause VM producers; wait VM consumers to drain; (6) Repoint producers + consumers to CFK; (7) Decommission VM (later, after stabilization).

---

## Thursday — MRC

**Q14. MRC (Multi-Region Cluster) vs cluster-linked dual cluster — when does each make sense?**
A. **MRC** — single cluster, brokers across regions, sync replication, survives full region loss with no manual action, but cross-region latency on every produce. Worth it when: <1min RTO required, strong consistency mandatory, network between regions reliable + <50ms. **Cluster-linked** — two independent clusters, async replication, low per-region latency, but manual failover. Worth it when: lower latency matters more than zero-RTO. the platform's current architecture is closer to cluster-linked.

**Q15. KRaftController quorum + regions — what's the constraint?**
A. KRaftController quorum (3 or 5 nodes) needs to survive region failure for the cluster to keep functioning. In MRC: must span regions but cross-region election latency hurts. In dual-cluster (the platform's current architecture): each cluster has its own quorum, independent of the other.

**Q16. Rack awareness — what does CFK do with `broker.rack`?**
A. The KRaftController uses `broker.rack` when assigning partition replicas — it tries to spread replicas of each partition across different racks. In production this means broker replicas land in different AWS AZs, so one AZ failure doesn't lose all replicas of a partition. CFK reads node label `topology.kubernetes.io/zone` and sets broker.rack automatically.

---

## Friday — DR Drill

**Q17. RTO vs RPO — define and give production targets.**
A. **RTO** (Recovery Time Objective) — how long can you be down? **RPO** (Recovery Point Objective) — how much data can you lose? production targets are environment-specific (PROD usually <15min RTO, <5min RPO for streaming data). Cluster-linked async replication has RPO = link lag (typically seconds). MRC with sync replication has RPO = 0 but higher operational overhead.

**Q18. Layer 1 — Layer 4 mental model — walk it.**
A. (1) Workloads — Flink jobs, app producers/consumers; (2) Kafka data plane — topics, ISR, consumer groups, cluster links; (3) CFK control plane — Operator, CRs, CMF, Flink Operator; (4) OCP/AWS infra — Pods, nodes, network, storage, IAM, NetApp S3, Okta. Customer reports at Layer 4 (top); triage descends layer-by-layer to find the cause.

**Q19. If Okta goes down for 10 minutes — what works, what doesn't?**
A. Existing connected clients continue to produce/consume — their broker connections are already authenticated; SASL state persists. New client connections fail (can't fetch new JWT). Token refreshes on existing clients may fail if Okta-down spans the refresh window. Broker-to-broker traffic (internal listener, no auth) is unaffected. Recovery: wait for Okta; clients auto-reconnect.

**Q20. The single most important habit Week 6 wants you to leave with.**
A. **Always pre-capture state before triggering recovery.** When a customer says "Kafka is broken" and you're tempted to restart something — first capture the failing state. CR conditions, Pod statuses, current ISR, current consumer-group offsets. The restart may resolve the symptom but the captured state is what you'll learn from. Without it, you've fixed one incident and lost the postmortem.

---

## After completing Q&A

This is the final week. Your **Personal Master Runbook v5** should aggregate the per-week Q&A answers into a single document organized by failure pattern, not by week. The bootcamp gave you the building blocks; the runbook is the artifact you carry into the role.
