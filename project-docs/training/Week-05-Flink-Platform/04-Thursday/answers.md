# Week 5 Thursday — Q&A Answers

Answers to the discussion Q&A in [`discussion.md`](discussion.md#qa).

---

## 1. If CMF goes down, do already-running Flink jobs continue processing?

**Yes.** CMF is the SQL Gateway / statement management surface. Once a Flink job's JM and TMs are running, CMF is out of the hot path — the job reads Kafka, snapshots to S3, and writes to Kafka without CMF involvement.

What breaks while CMF is down:

- Submitting *new* SQL statements
- Listing running statements in the CMF UI
- Catalog / environment resolution for new job authoring
- Any `cmfctl` operations against the affected env

What keeps working:

- All currently-running jobs (application clusters and session-cluster-based)
- The Flink Kubernetes Operator (reconciles CRs directly, not via CMF)
- The Flink Web UI (served by each job's JM)

## 2. Checkpoint vs savepoint in *what they store* — are they different formats?

**Same file format underneath** — same state serializer, same on-disk layout. What differs is metadata + lifecycle:

- **Checkpoints** can be *incremental* on RocksDB (only changed SSTables uploaded). Savepoints are always full.
- **Checkpoints** are Flink-managed (auto-cleaned per `state.checkpoints.num-retained`). Savepoints never get cleaned by Flink — you manage them.
- **Savepoints** are portable across Flink versions and job graphs (with compatible state schemas). Checkpoints assume the same Flink version + job binary.
- **Convention**: separate S3 prefixes (`.../checkpoints/`, `.../savepoints/`) but the underlying files are the same shape.

A savepoint restored on the same job is functionally equivalent to restoring from a checkpoint — the difference is a management contract, not a file format.

## 3. Why does FCB use SQL Server for CMF's backend instead of in-cluster PostgreSQL?

Organizational, not technical. FCB's DBA team runs SQL Server as the enterprise-standard managed RDBMS:

- HA + backup + DR are on the DBA team's playbook, not the Flink team's
- Compliance / auditing / access review flow through DBA's existing controls
- Ops burden of an in-cluster Postgres (StatefulSet, PVC lifecycle, backup automation, upgrade drills) would fall on the Flink / Container Platforms teams

Aligns CMF's DB tier with FCB's centralized data-tier ownership model. Trade-off: SQL Server client, slightly more complex JDBC config in CMF, but a well-understood ops model.

## 4. If Artifactory is down when a job Pod starts — CR stays `CREATED`, fails, or retries?

**CR stays `RECONCILING` (or `DEPLOYING`) with a JAR-fetch error surfacing in status conditions.** The JM Pod (or init container) fails on the artifact download step. Kubernetes marks the Pod `CrashLoopBackOff` or the init container `Error`; the Flink Operator's next reconcile loop sees the missing JM Deployment and retries.

Not `FAILED` — that's for terminal, non-recoverable errors. Not `CREATED` — the operator has moved past initial creation.

Recovery is automatic once Artifactory is reachable — next reconcile succeeds, JM starts, TMs claim slots, job transitions to `RUNNING`.

Where to look:

- `oc describe pod <jm-pod>` → Events section
- Init container logs (`oc logs <jm-pod> -c <init-container-name>`)
- CR status conditions (`oc get flinkdeployment <name> -o yaml`)

## 5. Where is the HA leader lease physically stored, and what's failover granularity?

Kubernetes **Lease** resource in the same namespace as the FlinkDeployment (older Flink versions used ConfigMap with annotations). Access controlled by the Flink service account's Role.

Granularity is **seconds** — bound by:

- `high-availability.kubernetes.leader-election.lease-duration` (default 15s)
- `high-availability.kubernetes.leader-election.renew-deadline` (default 10s)
- `high-availability.kubernetes.leader-election.retry-period` (default 2s)

So a lost leader is detected within 10–15s and the standby JM becomes leader on the next election cycle. Faster than the ZK-based Flink HA of pre-1.13 days.
