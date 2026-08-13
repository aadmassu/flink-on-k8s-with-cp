# ROSA-specific CR overrides — temporary

The CRs in `apps/confluent-platform/rosa/` are a simplified copy of the
FCB CRs in `apps/confluent-platform/dev/`, modified to run on a clean
ROSA cluster for the **CFK StatefulSet admission reproduction** (see
`docs/ROSA-STS-REPRO-NOTES.md`).

The originals at `apps/confluent-platform/dev/` are unchanged — when we
go back to FCB work, nothing needs to be reverted there. This directory
+ its README are the entirety of the temporary divergence.

## What's different from the FCB CRs

| Concern | FCB value (untouched) | ROSA override (temporary) | Why |
|---|---|---|---|
| Application image | `artifactory.fcbint.net/camdepositsharedservices-docker-dev/confluentinc/cp-*` | `docker.io/confluentinc/cp-*` | ROSA has no creds for FCB Artifactory |
| Init container | `artifactory.fcbint.net/.../confluent-init-container:0.1351.103` | `docker.io/confluentinc/confluent-init-container:0.1351.103` | Same — same tag |
| OAuth (Okta) on Kafka external listener | `oauth` type + `myapps.firstcitizens.com` URLs | External listener removed entirely | FCB Okta unreachable from ROSA |
| `services.mds` on Kafka CR | OAuth-backed MDS | Entire `services.mds` block removed | Same — depends on Okta |
| OAuth on SR/Connect/REST/C3 dependencies + spec.authentication | nested `oauth.{secretRef, configuration}` blocks pointing to Okta | Replaced with plain SASL where required; component auth blocks removed | Same |
| `injectLabels` / `podTemplate.labels` | FCB common-metadata (`fcbint.net/app-id: "11547"`, etc.) | Stripped — no Gatekeeper enforcing labels on ROSA | Not needed; ROSA has no FCB policies |
| `storageClass.name` | `ocs-storagecluster-ceph-rbd` | `gp3-csi` | ROSA's default AWS EBS storage class |
| Resources (CPU/memory) | FCB worker sizing (broker 2-4 CPU + 4-8 GiB, C3 12 CPU + 16 GiB) | Minimum-viable (100-500m CPU + 256-1024 Mi memory) | ROSA cluster is 4× m5.xlarge worker = 16 vCPU + 64 GiB total |
| `dataVolumeCapacity` | 1 GiB (already shrunk for FCB ResourceQuota) | 1 GiB | Kept |
| License `secretRef: cfk-license` | Present | Commented out → CFK falls back to evaluation license | We don't have a license for the Psyncopate cluster |
| `podSecurity` on operator chart | Whatever FCB applies | `enabled: false` (helm install flag) | ROSA `restricted-v2` SCC requires no fixed UID |
| `flink-operator` SA + `anyuid` SCC | FCB platform team sets these via fcb-security ArgoCD chart | Created manually here | Reproduce permissions |

## Things we did NOT change from FCB

- `replicas` per component (3 brokers, 3 controllers, etc.)
- `listeners.internal` plain SASL config (uses our placeholder `sasl-plain-internal` secret)
- `configOverrides.server` blocks (RF=3, balancer, telemetry, etc.)
- `pdb` enabled with `maxUnavailable: 1`
- `podSecurityContext: {}` (let OpenShift fill in UID)
- Anti-affinity for kafka and kraftcontroller

## Revert path

1. Delete CRs from ROSA: `oc -n dah-flink-dev delete kafka,kraftcontroller,schemaregistry,connect,kafkarestproxy,controlcenter,kafkarestclass --all`
2. (Optional) `rm -rf apps/confluent-platform/rosa/` and this doc.
3. Tear down the ROSA cluster: `gh workflow run 01-provision-rosa.yaml --ref main -f environment=dev -f action=destroy`.

Nothing in `apps/confluent-platform/dev/` was touched.
