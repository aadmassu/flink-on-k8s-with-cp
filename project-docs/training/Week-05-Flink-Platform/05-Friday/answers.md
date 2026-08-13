# Week 5 Friday — Q&A Answers

Answers to the discussion Q&A in [`discussion.md`](discussion.md#qa).

---

## 1. Order these closest-to-developer → closest-to-JVM, and categorize (user-facing / cluster-side / library-embedded):

**Ordering:**
1. **Artifactory** — user-facing artifact repository (developer pushes JARs)
2. **CMF** — user-facing statement / catalog surface (developer authors SQL)
3. **kube-apiserver** — cluster-side control plane (CI applies CRs here)
4. **Flink Operator** — cluster-side controller (reconciles CRs → K8s resources)
5. **JobManager** — cluster-side runtime (accepts job submissions, schedules)
6. **Kafka** — data-plane dependency (accessed by TMs, not embedded)

**Categorization:**

- User-facing: Artifactory, CMF
- Cluster-side: kube-apiserver, Flink Operator, JobManager
- Data-plane dependency: Kafka (from Flink's POV, it's a source/sink dependency — not embedded in the JVM, accessed via client library)

## 2. If the JAR download fails at Pod startup, does the CR stay in `RECONCILING` or move to `FAILED`? Where's the HTTP status code?

**Stays `RECONCILING`** — the operator retries reconciles on backoff. `FAILED` is reserved for terminal errors that reconciliation can't repair (schema errors, unrecoverable operator failures on the running job graph).

Where the HTTP status code shows:

- `oc describe pod <jm-pod>` → Events section (init container failure event)
- Init container logs (`oc logs <jm-pod> -c artifact-fetcher` — actual container name depends on the Flink Operator version)
- If the JAR is fetched by JM main container itself: JM Pod stdout has the artifact-fetch stack trace with URL + HTTP code

## 3. Where in the flow does OAuth first come into play?

**At Kafka source connection.** That's when the TM opens a Kafka producer/consumer and hits the OAUTHBEARER SASL handshake, which reaches MDS for the token.

Not at:
- **CR apply** — K8s API server auth (service account token, not OAuth)
- **Pod startup** — image pull uses image-pull secret; JAR fetch uses Artifactory token (basic auth or API key, not OAuth)
- **Checkpoint write** — S3 uses static IAM-style credentials or IRSA, not OAuth

## 4. In FCB's flow, who owns each step (Developer / Release / Platform / SRE)?

| Step | Owner |
|---|---|
| Author code, unit tests, PR | Developer |
| Push JAR to Artifactory | Developer (via CI) |
| Author `FlinkDeployment` CR YAML | Developer |
| Approve prod deploy | Release management |
| OpenShift cluster, cert-manager, CFK operator install | Platform (Container Platforms) |
| Flink Operator install, CRD upgrades | Platform |
| CyberArk safes + ExternalSecrets | Platform (Container Platforms) + FCB Security |
| Kafka cluster health, MDS, cluster-links | SRE (Kafka Admin team) |
| Flink S3 checkpoint storage | SRE (NetApp storage team) |
| On-call rotation for job health | SRE (Kafka Admin org) |

FCB-specific: Kafka Admin org covers the Flink SRE role given the tight Kafka↔Flink coupling.

## 5. What's the single change that would make an end-to-end deploy fastest to iterate — where's the current bottleneck?

**Skip Artifactory during dev iteration.** Two options:

- **Use CMF SQL Gateway for the inner loop** — SQL statements don't need a JAR at all. Edit statement in CMF UI → submit → job runs. Iteration cycle drops from ~10 min (build + push + CI + CR apply) to seconds.
- **Local dev cluster with an in-cluster JAR** — mount the JAR via a ConfigMap or serve it from an nginx sidecar (like [Week 5 Friday's lab](../05-Friday/lab.md#prerequisite-setup) baseline). Skips the JAR-push step.

Current bottleneck: **Artifactory push + CI stage** for the JAR-based path. In production, the pipeline stages themselves (approval gates, build) also add minutes. For prod deploy iteration those gates are worth it; for dev iteration they're not.
