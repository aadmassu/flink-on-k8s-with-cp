# Outbound Firewall Requests — CFK + Flink

Single source of truth for the **outbound** firewall-rule asks needed so pods
running in `dah-flink-<env>` can reach the FCB-internal and external endpoints
they depend on at runtime.

Companion: [INBOUND-FIREWALL-REQUESTS.md](INBOUND-FIREWALL-REQUESTS.md) covers
the reverse direction (external clients reaching CFK/CMF/Flink).

## How this list was built

Destinations and ports below come directly from
[`.azure-pipelines/connectivity-test.yaml`](../../.azure-pipelines/connectivity-test.yaml),
which probes them from a busybox pod in `dah-flink-<env>` before any CFK install.
Run that pipeline in any env to verify these rules are in place; a green run
is the pre-flight check before the next CFK or CMF deploy.

Two tracks: CFK (platform components) and Flink (CMF + JobManager + jobs).
The pods sit in the same namespace and share the same egress posture from the
perimeter's perspective, but the destinations they each need to reach are
distinct enough to warrant separate tables.

## CFK track

Outbound destinations needed by the CFK platform components (Kafka brokers,
Schema Registry, Connect, REST Proxy, Control Center, embedded MDS) running
in `dah-flink-<env>`.

| Destination | DNS / endpoint | Port | Purpose |
|---|---|---|---|
| Okta tenant (OAuth tokens) | `myapps.firstcitizens.com` | 443 | OAuth/OAUTHBEARER tokens used by every CFK component for SASL_SSL authentication. Currently **BLOCKED** in DEV — see [`../ISSUE-TRACKER.md`](../ISSUE-TRACKER.md) tracker 2.9 |
| CyberArk webhook (via ESO) | FCB CCP endpoint (per `apps/confluent-cmf/<env>/secretstores/*`) | 443 | External Secrets Operator pulls `confluent-license`, `cfk-license`, `cmf-encryption-key`, `cmf-db-credentials` from CyberArk; ESO pod issues the call but the egress is from the same namespace |
| Artifactory image registry | `artifactory.fcbint.net` | 443 | CFK component image pulls during pod (re)start |
| FCB internal DNS | resolver IPs supplied by Container team | 53 (UDP / TCP) | Hostname resolution for everything above; controlled by FCB DNS, not by this repo |
| VM CP brokers (cluster-link migration only) | `<env>-kafka-broker-hosts` (e.g. `d11547varc-pgm8.fcpd.fcbint.net:9094`) | 9092 / 9094 | One-time mirror source during cluster-link cutover from VM CP to CFK; the egress is needed only on the CFK destination side during migration |

## Flink track

Outbound destinations needed by CMF + Flink Operator + Flink Application pods
(JobManagers + TaskManagers + per-job containers).

| Destination | DNS / endpoint | Port | Purpose |
|---|---|---|---|
| CMF SQL Server | `<env>-cmf-sql-server-jdbc-url` (from `kafka-openshift-credentials-<env>`) | 3085 | CMF metadata database (FCB MSSQL custom port) |
| VM CP Kafka brokers | `<env>-kafka-broker-hosts` | 9092 / 9094 | Flink jobs source/sink Kafka traffic until per-env cluster-link migration completes |
| VM CP Schema Registry | `<env>-schema-registry-hosts` | 8081 | Avro / Protobuf / JSON-Schema lookups during job execution |
| VM CP Kafka REST Proxy | `<env>-kafka-rest-proxy-hosts` | 8082 | Reserved for HTTP-based Kafka clients; exercised by connectivity-test but not used by `aep-rate-limit-job` |
| NetApp S3 (Flink checkpoints + savepoints) | `<env>-net-app-s3-url` | 443 | Job state persistence — JobManager + TaskManager pods write checkpoints here on every interval |
| Okta tenant (OAuth tokens) | `myapps.firstcitizens.com` | 443 | Flink jobs that talk to Kafka via SASL_SSL also fetch OAuth tokens — same `Connection timed out` symptom as the CFK track. **BLOCKED** in DEV — tracker 2.9 |
| Artifactory image registry | `artifactory.fcbint.net` | 443 | CMF + Flink Operator + per-job image pulls |

Job-specific outbound destinations (e.g. AEP API endpoints for
`aep-rate-limit-job`) are added per job in that job's own manifests and
firewall request, not here. Today's `aep-rate-limit-job` global failover
(2026-06-10) was caused by exactly that kind of missing per-job egress —
keep job-specific destinations on the job's RUNBOOK, not in this platform
README.

## Source side (every rule above)

Source for every outbound rule is the pod-network CIDR of `dah-flink-<env>`
(OCP pod IP range allocated to that namespace's pods). Container team supplies
the exact pod-network CIDRs per env. The cluster's apps LB IPs and the
broker LB IPs are inbound endpoints — **not** the source for any egress rule.

## Known status

Snapshot from the 2026-06-10 DEV run of `connectivity-test.yaml`. Refresh by
re-running the pipeline against any env.

| Destination | DEV | QA / UAT / PRD / DR |
|---|---|---|
| Okta tenant — 443 | **BLOCKED** (`Connection timed out`) — tracker 2.9 | Same blocker expected per-env; Tushar files SNOW per-namespace |
| CyberArk webhook — 443 | OPEN (ESO syncing on DEV) | TBC per env (`Cyber*` SecretStore must land first) |
| Artifactory — 443 | OPEN (cluster pulls images today) | OPEN |
| FCB DNS — 53 | OPEN (in-cluster resolution works) | OPEN |
| CMF SQL Server — 3085 | OPEN | TBC per env |
| VM Kafka — 9092 / 9094 | OPEN | TBC per env |
| VM SR — 8081 | OPEN | TBC per env |
| VM KRP — 8082 | OPEN | TBC per env |
| NetApp S3 — 443 | OPEN | TBC per env |
| VM CP brokers (cluster-link) — 9092 / 9094 | N/A (no cutover yet) | N/A |

`connectivity-test.yaml` is the regression check for this list — run it per
env as part of the deploy gate (`runbook/CHECKLIST.md`) before any CFK or CMF
install.
