# Week 5 Tuesday — Q&A Answers

Answers to the discussion Q&A in [`discussion.md`](discussion.md#qa).

---

## 1. FlinkDeployment application cluster vs FlinkSessionJob against a session cluster — when do you choose each?

- **Application cluster** (`FlinkDeployment` with `spec.job` set) — dedicated JM+TMs, one cluster per job. Job lifecycle == cluster lifecycle. Best isolation (no noisy-neighbor across jobs), best blast-radius control. Use for production long-running jobs.
- **FlinkSessionJob** — submits a job into a pre-existing `FlinkDeployment` running as a session cluster (no `spec.job`). Many jobs share one JM+TMs, one slot pool. Cheapest to iterate; jobs interfere with each other. Use for dev, CMF SQL Gateway workflows, or ad-hoc / low-isolation workloads.

FCB pattern: prod Flink jobs → application clusters; CMF-driven SQL Gateway workloads → session cluster + FlinkSessionJobs.

## 2. Why does the Flink operator use Deployments, and CFK uses StatefulSets for Kafka brokers?

- **JMs are stateless from K8s' perspective.** Durability lives in S3 (checkpoints/savepoints) and the K8s HA lease (ConfigMap/Lease). Any JM Pod can be replaced by any other JM Pod as long as it can pick up the lease and read S3. Deployment is the correct primitive.
- **Kafka brokers own local disk with persistent identity** — `broker.id`, log directory, ordered pod names. A broker's storage cannot be swapped between Pods without breaking replication invariants. StatefulSet gives stable identity + ordered rollout + PVC-per-replica.

Different durability models, different primitives.

## 3. If you edit `spec.job.parallelism` from 4 to 8, does the operator restart the job immediately, at the next checkpoint, or wait for the next savepoint?

Depends on `spec.job.upgradeMode`:

- `stateless` — immediate stop + redeploy, no state carried over
- `savepoint` (default for stateful) — operator triggers a savepoint, stops the job, redeploys, restarts *from* the savepoint
- `last-state` — uses the most recent successful checkpoint (skips the explicit savepoint step)

It is **not** an immediate hot-rescale. Flink's operator instance rescheduling requires state redistribution, which needs a snapshot boundary (checkpoint or savepoint). During the operation the CR moves through `RECONCILING → SUSPENDED → RUNNING`.

## 4. Name three fields the operator writes into `status`.

Any three of:

- `status.jobStatus.state` — `CREATED` / `RUNNING` / `RESTARTING` / `FAILED` / `RECONCILING`
- `status.jobManagerDeploymentStatus` — `READY` / `MISSING` / `DEPLOYING`
- `status.reconciliationStatus.state` — `DEPLOYED` / `UPGRADING` / `ROLLED_BACK`
- `status.clusterInfo.flink-version` — the running Flink version
- `status.jobStatus.savepointInfo.lastSavepoint.path` — S3 URI of the last savepoint

Use these to answer "is this CR in the state I expect" without shelling into Pods.

## 5. In FCB HA setup, what happens if the K8s API server is briefly unreachable — does the JobManager fail over?

**Not immediately.** The JM doesn't need the API server in its hot path once the Pod is running — Kafka source reads and S3 checkpoint writes are direct.

Failover trigger is **HA lease expiry**. The JM holds a K8s Lease (or ConfigMap in older versions). Renewal is on a timer (default ~2s renewal, ~15s lease duration in Flink K8s HA). If the API server is unreachable long enough that the lease can't be renewed within its duration, the leader is considered lost and any standby JM becomes leader. If API server recovers before lease expiry, no failover.

Practical granularity: sub-minute for real failover, seconds if configured aggressively.
