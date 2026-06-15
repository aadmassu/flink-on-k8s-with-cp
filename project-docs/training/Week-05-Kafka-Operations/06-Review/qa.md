# Week 5 — Q&A (20 reinforcement questions)

---

## Monday — Topic Lifecycle

**Q1. Partitions, replicas, ISR — define each in one sentence.**
A. Partition = one ordered log (the unit of parallelism). Replica = N copies of each partition's log (the unit of durability). ISR (in-sync replicas) = subset of replicas currently caught up to the leader within `replica.lag.time.max.ms` — the only replicas eligible to be elected leader.

**Q2. With acks=all and min.insync.replicas=2 in a 3-broker cluster, what happens when one broker dies?**
A. The dead broker's replicas are removed from ISR for partitions where it was a replica. Remaining ISR for those partitions = 2, which meets `min.insync.replicas=2`. Producers keep working. If a SECOND broker dies for the same partition (ISR=1 < min), producers see `NotEnoughReplicasException` until ISR recovers.

**Q3. Who tells the producer where the leader of a partition lives?**
A. Metadata responses from any bootstrap broker. The producer connects to a bootstrap, asks for topic metadata, gets the partition→leader mapping back. It caches this and refreshes when it gets `NOT_LEADER_FOR_PARTITION` errors (after a leader election). Clients don't talk to KRaftController directly.

**Q4. CR-managed vs runtime-created topics in production — what's policy?**
A. Production topics MUST be CR-managed (KafkaTopic CR in git, applied via Azure DevOps). Reason: auditable, reviewable, GitOps-able. Runtime-created topics (by Connect, Flink, applications with CREATE permission) are easier but harder to govern. Lower envs (dev/qa) can use either; UAT/PRD requires CR.

---

## Tuesday — Consumer Groups

**Q5. Why does Kafka have consumer groups at all?**
A. To share work across multiple consumer instances. Group of N consumers cooperatively reads all partitions of a topic. Each partition assigned to exactly one consumer; partitions distributed evenly across consumers. Lets you scale consumption horizontally and provides automatic failover when a consumer dies.

**Q6. Rebalance — who triggers it, who orchestrates it?**
A. Trigger: consumer joins/leaves the group (heartbeat timeout or graceful leave) OR topic partition count changes. Orchestration: the **group coordinator** = one broker, elected by hashing the group ID. Coordinator runs the JoinGroup → SyncGroup → assignment dance.

**Q7. Cooperative vs eager rebalance — what changes for the user?**
A. Eager: ALL consumers revoke ALL partitions, then receive new assignments → big consumption pause. Cooperative (incremental): only partitions that NEED to move revoke (e.g. when 1 consumer leaves, 1 partition reassigns; others keep their existing assignment) → much smaller pause. Modern clients should use cooperative for production.

**Q8. Why does a slow consumer cause continuous rebalance?**
A. Consumer exceeds `max.poll.interval.ms` between poll() calls; coordinator decides it's dead; rebalance; new (slow) consumer assigned, same problem next loop. Symptom: group oscillates, lag grows monotonically. Fix: increase max.poll.interval.ms, OR reduce per-poll batch size, OR scale consumers.

---

## Wednesday — OAuth (+ mTLS, ACLs gap-fill)

**Q9. SASL_OAUTHBEARER — what does the client send + what does the broker do?**
A. Client fetches a JWT from Okta (client_credentials grant), sends it during SASL handshake. Broker validates: (1) JWT signature against Okta's JWKS public keys; (2) issuer (`iss`) matches expected; (3) audience (`aud`) matches expected; (4) expiry not past; (5) extracts principal from configured claim (e.g. `preferred_username`).

**Q10. The two trust pieces a broker needs to validate Okta tokens.**
A. (1) JWKS reachable + cached — broker fetches Okta's public keys to verify signatures. Requires Okta egress (tracker 2.9). (2) Audience + issuer config exact match — broker config has `aud=kafka-cluster` (or similar); Okta config must mint tokens with that exact `aud`. Mismatch = `invalid_token`.

**Q11. mTLS in production — where is it used?**
A. The 9094 listener (tracker 2.10) for cluster-link source brokers from VM CP. mTLS = mutual TLS: client presents a cert, broker validates against truststore. Used because VM brokers don't speak OAuth; mTLS is their existing protocol. After full migration, mTLS could be phased out — until then it's a long-term  the platform pattern.

**Q12. ACLs vs Confluent RBAC — the the picture.**
A. ACLs = Kafka-native, stored in KRaft, on (principal × resource × operation). RBAC = Confluent commercial feature, stored in MDS (Metadata Service), supports roles + group memberships, easier to manage at scale.  the platform starts with ACLs (simpler); RBAC is on the roadmap when MDS is provisioned. Confluent RBAC isn't fully wired yet — the bootcamp covers it conceptually.

---

## Thursday — Observability

**Q13. The five broker metrics that catch ~80% of incidents.**
A. (1) `under_replicated_partitions == 0`; (2) `under_min_isr_partition_count == 0`; (3) `request_handler_avg_idle_percent > 50%`; (4) `request_throttle_time_avg` per client (non-zero = quota throttling); (5) `log_log_size` growth tracking. If any are off, descend into specific topic + broker views.

**Q14. The metrics journey — broker JVM to your eyes.**
A. (1) Kafka MBeans in JVM; (2) `cp-kafka-prometheus-jmx-exporter` sidecar scrapes JMX, exposes HTTP /metrics on 7203; (3) Prometheus (per OCP cluster) discovers Pod via ServiceMonitor + scrapes; (4) Prometheus stores time series; (5) Grafana queries via PromQL; (6) browser renders. Plus: broker stdout logs → OCP log forwarder → Splunk.

**Q15. Where does the platform put audit logs, and why are they currently disabled?**
A. Project memory `project_telemetry_audit_reenable_later`. Audit log produces to a destination Kafka cluster's audit topic. Currently disabled across dev/qa/uat because broker bootstrap servers for the destination don't exist at controller startup. Re-enable when the destination cluster is provisioned.

**Q16. Dynatrace's role in production?**
A. Org-wide APM + node-level monitoring via OneAgent (DaemonSet). Complements Prometheus (which is cluster-local + Kafka-specific) with broader visibility (HTTP traces, JVM detail, infra). Kafka admins primarily use Prometheus/Grafana; SREs use Dynatrace for cross-stack views. Both feed the same incident-response workflow.

---

## Friday — Failure Modes

**Q17. Six common Kafka failure modes — name them.**
A. (1) Broker disk full; (2) Slow broker (CPU/IO saturation); (3) Network partition (broker isolated); (4) Authorization regression (ACL change); (5) Schema Registry down; (6) Cluster-link source unreachable. Each maps to a specific diagnostic + recovery in the cheat sheet.

**Q18. Customer reports "Kafka is broken." First three diagnostic commands.**
A. (1) `oc get kafka -o jsonpath='{.status.conditions}'` — is CFK healthy? (2) `oc get pods -l app=kafka` — are all brokers Running + Ready? (3) `kafka-topics --bootstrap-server ... --describe --topic <hot_topic>` — ISR state per partition. If all 3 healthy, the problem is application-side OR client-config side.

**Q19. Which failure mode has the worst recovery cost, and why?**
A. Broker disk full when retention isn't easy to reduce. Adding disk requires PVC expand + StorageClass support; reducing retention rolls out via CR change + per-topic config. If you have to delete data to recover, you've lost real customer data. PREVENTION (disk-usage alerts) is the only good strategy.

---

## Cross-day integration

**Q20. The most important on-call mental model from Week 5.**
A. Kafka problems often look like *operations* problems but are usually one of: a config drift (ACL, OAuth audience, broker.properties), a resource-saturation (disk, CPU, ISR), or a dependency outage (Okta, SR, NetApp S3). Order your triage: (1) is CFK healthy? (2) are brokers healthy? (3) are clients configured correctly? (4) are dependencies up? Most incidents end in step 3 or 4.

---

## After completing Q&A

The 5-metric checklist (Q13), the 6-failure catalog (Q17), and the diagnostic order (Q18) are the Week 5 takeaway artifacts. Keep them in your on-call cheat sheet.
