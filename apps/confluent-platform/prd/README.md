# CFK Confluent Platform — prd

> 🛑 **PLACEHOLDER STATE — DO NOT DEPLOY WITHOUT FILLING IN THE VALUES BELOW.**
> This tree was cloned from `../uat/` on 2026-07-08 with mechanical env-token
> substitutions (namespace → dah-flink-prod, DNS → apps.pd, ESO → 11547-p-key-fp,
> AZDO var prefix → prd-, OAuth scope → DAH(PD), groups claim → dahPD_groups).
> The following values are best-guess / unverified and MUST be confirmed before
> any pipeline run against the PRD cluster:
>
> - **OAuth scope `11547.DAH(PD)`** — CONFIRMED against the VM PRD broker
>   properties in `../cp-confluent/prd/`
> - **Groups claim `dahPD_groups`** — CONFIRMED against the same VM properties
> - **ESO SecretStore `11547-p-key-fp`** — confirm with Container Platforms; the PRD
>   CyberArk safe follows the d/q/u pattern but the exact name is not in this repo yet
> - **OpenShift API URL `api.pd.ocp.fcbint.net`** — confirm with Container
>   Platforms; may be `api.pd-p.ocp.fcbint.net` for the primary cluster explicitly
> - **VM CP hostnames** — the mapping table below carries `<REPLACE_WITH_PRD_...>`
>   placeholders. Populate from `apps/confluent-platform/cp-confluent/prd/` when
>   Ayu extracts the PRD VM .properties files from the FCB laptop (that folder
>   is not in the repo yet as of this commit).
> - **StorageClass `kafka`** — Rick's dedicated vSphere CSI SC was provisioned in
>   dev; unclear whether the same SC exists in the PRD cluster. PVCs will stay
>   Pending if it does not.
> - **AZDO variable group `kafka-openshift-credentials-prd`** — 37 `prd-*` variables
>   need to be populated (mirror the QA / UAT screenshots but with PRD-specific
>   OAuth client IDs + secrets from the PRD Okta app).
>
> Also flag: **PRD has a primary AND secondary cluster** (`pd-p` / `pd-s` per
> OpenShift Ingress.pdf). This folder deploys to the primary. The DR/secondary
> deployment lives in `../dr/`.

CFK Custom Resources that reproduce the existing prd VM Confluent Platform cluster on OpenShift. Every CR in this folder is authored against the corresponding `.properties` file under [`../cp-confluent/prd/`](../cp-confluent/prd/) — that's the source of truth for parity (folder does not exist in the repo yet; extract from a PRD VM broker before deploy).

> ⚠️ **Heads-up — broker/controller CPU+memory AND all PVC sizes have been scaled down from the VM allocation.** Two separate constraints drove this:
>
> **1. Worker-node fit (2026-05-12)**: FCB worker nodes are **16 vCPU / 32 GiB**. VM brokers got 16 vCPU / 16 GiB and controllers 4 vCPU / 4 GiB at 2%/9% utilization — but carrying those request sizes into K8s leaves the broker pods stuck `Pending` (kubelet reserves ~1–2 vCPU, leaving ~14 allocatable).
>
> **2. Namespace ResourceQuota (2026-05-13)**: `dah-flink-prod` has a 10 GiB total `requests.storage` cap. Original VM-sized PVCs (3 × 1 TiB brokers + 3 × 64 GiB controllers + 300 GiB C3 = ~3.5 TiB) exceeded the cap 350×. Until Tom raises the quota, dev PVCs are tightly sized to fit exactly 10 GiB.
>
> | Component | Old (VM) | **CFK `request` / `limit`** | **PVC (TEMP, until quota raised)** |
> |---|---|---|---|
> | Broker (×3) | 16 vCPU / 16 GiB / 1 TiB | **2 / 4 vCPU**, **4 / 8 GiB** | **2 GiB** (was 1 TiB) |
> | KRaft ctrlr (×3) | 4 vCPU / 4 GiB / 64 GiB | **1 / 2 vCPU**, **2 / 2 GiB** | **1 GiB** (was 64 GiB) |
> | C3 | 12 vCPU / 16 GiB / 300 GiB | unchanged | **1 GiB** (was 300 GiB) |
>
> Total dev PVC ask: 6 + 3 + 1 = 10 GiB, fits the namespace quota exactly. Bump back to VM-sized PVCs (1 TiB brokers, 64 GiB controllers, 300 GiB C3) the day Tom raises the namespace `requests.storage` quota. CPU/memory limits stay where they are — those are about the 16/32 worker fit, separate from the quota.
>
> Full table + per-node co-tenancy math in the [Capacity](#capacity-cfk-cr-settings-vs-vm-source) section below. SR / Connect / REST / C3 CPU+memory unchanged — those VM sizes already fit a 16/32 worker.

## Target

- **Confluent Platform**: 8.1.x
- **CFK operator**: latest version that supports CP 8.1.x. Operator install is owned by FCB's Container Platforms team; FCB will upgrade if a newer version is required.
- **Namespace**: `dah-flink-prod` (CFK operator lives in its own namespace and watches `dah-flink-<env>`)
- **Mode**: KRaft (3 controllers, 3 brokers) — matching the dev VM cluster

## Topology mirrored from VM prd

> ⚠️ Placeholders below — replace with the PRD VM CP hostnames from
> `apps/confluent-platform/cp-confluent/prd/` once extracted.

| Component | Replicas | VM hosts | CR file |
|---|---|---|---|
| KRaft Controller | 3 | `<REPLACE_WITH_PRD_KRAFT_1>`, `<REPLACE_WITH_PRD_KRAFT_2>`, `<REPLACE_WITH_PRD_KRAFT_3>` | [`kraftcontroller.yaml`](kraftcontroller.yaml) |
| Kafka Broker | 3 | `<REPLACE_WITH_PRD_BROKER_1>`, `<REPLACE_WITH_PRD_BROKER_2>`, `<REPLACE_WITH_PRD_BROKER_3>` | [`kafka.yaml`](kafka.yaml) |
| Schema Registry | 1 | `<REPLACE_WITH_PRD_SR_1>` (+ `<REPLACE_WITH_PRD_SR_2>` if 2 in prod) | [`schemaregistry.yaml`](schemaregistry.yaml) |
| Connect | 2 | `<REPLACE_WITH_PRD_CONNECT_1>`, `<REPLACE_WITH_PRD_CONNECT_2>` | [`connect.yaml`](connect.yaml) |
| Kafka REST Proxy | 1 | `<REPLACE_WITH_PRD_REST_1>` (+ `<REPLACE_WITH_PRD_REST_2>` if 2 in prod) | [`kafkarest.yaml`](kafkarest.yaml) |
| Control Center | 1 | `<REPLACE_WITH_PRD_C3_1>` | [`controlcenter.yaml`](controlcenter.yaml) |

## Folder layout

```
dev/
├── README.md                  (this file)
├── kafkarestclass.yaml        \
├── kraftcontroller.yaml        |
├── kafka.yaml                  |  ── CFK Custom Resources (root)
├── schemaregistry.yaml         |
├── connect.yaml                |
├── kafkarest.yaml              |
├── controlcenter.yaml         /
└── prereqs/                   ── supporting prerequisites (TLS Certificates + prereqs README)
    ├── README.md
    └── *-tls-certificate.yaml
```

CFK CRs live at the root for clear grouping. The `prereqs/` subfolder holds the cert-manager `Certificate` CRs that land the six `*-tls` Secrets, plus its own [README](prereqs/README.md) documenting the 11 non-TLS Opaque Secrets the pipeline creates from variable-group values.

## Apply order

Run the pipeline twice — `create-prereqs` first, then `install`. CFK reconciles in dependency order itself, but the pipeline applies in this sequence so any failure attributes to the right component:

1. **`create-prereqs` action** — pipeline creates the 11 non-TLS Opaque Secrets from `kafka-openshift-credentials-<env>` variable group entries. See [`prereqs/README.md`](prereqs/README.md) for the variable mapping.
2. **`install` action**:
   1. Apply the six TLS `Certificate` CRs under `prereqs/`. Pipeline waits up to 10 min per cert for Keyfactor to materialize each `*-tls` Secret.
   2. `kafkarestclass.yaml` — connection profile referenced by Connect + ControlCenter.
   3. `kraftcontroller.yaml` — KRaft quorum must be up before brokers register.
   4. `kafka.yaml` — brokers join the quorum.
   5. `schemaregistry.yaml` — uses Kafka as its kafkastore.
   6. `connect.yaml` — needs Kafka + SR.
   7. `kafkarest.yaml` — needs Kafka + SR.
   8. `controlcenter.yaml` — depends on all of the above.

## Capacity (CFK CR settings vs. VM source)

| Component | CR `requests` | CR `limits` | Disk | VM allocation / utilization |
|---|---|---|---|---|
| Broker (×3) | 2 vCPU / 4 Gi | 4 vCPU / 8 Gi | **2 GiB** (TEMP) | VM 16 vCPU / 16 GiB; actual usage 2% CPU / 20% mem |
| Controller (×3) | 1 vCPU / 2 Gi | 2 vCPU / 2 Gi | **1 GiB** (TEMP) | VM 4 vCPU / 4 GiB; 9% utilization (actual ~0.36 vCPU / 0.36 GiB) |
| Schema Registry | 4 vCPU / 4 Gi | 4 vCPU / 4 Gi | — | VM 4 vCPU / 4 GiB; stable moderate |
| REST Proxy | 4 vCPU / 4 Gi | 4 vCPU / 4 Gi | — | VM 4 vCPU / 4 GiB |
| Connect (×2) | 4 vCPU / 4 Gi | 4 vCPU / 4 Gi | — | VM 4 vCPU / 4 GiB; moderate |
| Control Center | 12 vCPU / 16 Gi | 12 vCPU / 16 Gi | **1 GiB** (TEMP) | VM 12 vCPU / 16 GiB; stable |

**Broker sizing rationale**: FCB worker nodes are **16 vCPU / 32 GiB** (per Tom). The VM had 100% of a 16-vCPU box, but only used 2% CPU and 20% memory. On a K8s node, requesting that full VM allocation makes the broker un-schedulable (kubelet + OpenShift system daemons reserve ~1–2 vCPU). The CR `requests` are sized at ~6× actual dev usage — comfortable headroom — and the `limits` allow the broker to burst when needed without monopolizing a worker.

**Controller sizing rationale**: KRaft controllers handle metadata-log writes only (topic creates, partition reassignments, leader elections), no data-path traffic. VM was 4 vCPU / 4 GiB at 9% utilization — actual usage ~0.36 vCPU and ~0.36 GiB. Shrunk to `request: 1 vCPU / 2 Gi`, `limit: 2 vCPU / 2 Gi` — still ~3× CPU and ~5× memory over actual.

**Co-tenancy on a 16 vCPU / 32 GiB worker** with one broker + one controller co-located (per the anti-affinity rules):

```
broker     limit  4 vCPU / 8 GiB
controller limit  2 vCPU / 2 GiB
system            ~2 vCPU / ~4 GiB   (kubelet, OpenShift node-exporter, ovs-cni, etc.)
─────────────────────────────────────
total used        ~8 vCPU / ~14 GiB
free on worker    ~8 vCPU / ~18 GiB  (for CMF, monitoring, other CFK pods)
```

**SR / REST / Connect / C3** match VM allocation 1:1 — those VMs were 4 vCPU / 4 GiB (12 / 16 for C3), and there's no scheduling issue at those sizes on a 16/32 worker.

If broker traffic grows enough to bottleneck on CPU or hit the heap ceiling, raise `limits` first (JVM heap auto-tunes to ~75% of memory limit); request increases only if average load consistently exceeds requests.

## What's preserved vs adapted from the VM config

**Preserved as-is** (cluster contract — don't change without coordinating with VM clients):
- All inter-component topic replication factors = 3 (`offsets`, `transaction`, `__confluent-command`, `_schemas`, `_confluent-monitoring`, `_confluent-secrets`, `connect-cluster-*`)
- Log retention 168h (7d), 1 GiB segments
- Min ISR for transaction-state log = 2
- KRaft quorum size = 3
- OAuth issuer (Okta: `myapps.firstcitizens.com/oauth2/default`), JWKS endpoint, scope `11547.DAH(PD)`
- Authorizer: `ConfluentServerAuthorizer` with `CONFLUENT,KRAFT_ACL` rule providers
- Embedded MDS on broker port 8090 (HTTPS, BEARER)
- Self-Balancing Cluster (SBC) enabled
- Telemetry export to C3 enabled

**Adapted** (Kubernetes-native equivalents):
- Hostnames become Service DNS (`<component>.<ns>.svc.cluster.local`)
- Listener ports follow CFK conventions (internal + external) — VM `INTERNAL:9092 / BROKER:9091 / CERTONLY:9094` collapses to CFK `internal` + `external` (LoadBalancer) + a `custom` mTLS-only listener
- TLS cert/key/truststore JKS paths → cert-manager `Certificate` CRs issuing through FCB Keyfactor; each lands a `*-tls` Secret consumed by the matching CR via `tls.secretRef` (same pattern as `cmf-tls`)
- All OAuth client IDs and secrets → K8s Secrets (see [`00-prereq-secrets.md`](00-prereq-secrets.md)); will move to CyberArk via ESO
- Confluent license → `confluent-license` Secret (already used by CMF)
- Kafka admin REST (VM `kafka.rest.*` on broker) → CFK `KafkaRestClass` CR (`kafkarestclass.yaml`) referenced by Connect + ControlCenter
- `log.dirs=/data/kafka` → CFK PV with the storage class FCB approves; mount path is operator-managed
- Container images use the same Artifactory pattern as Flink: `artifactory.fcbint.net/camdepositsharedservices-docker-dev/confluentinc/cp-*:8.1.0` for dev / qa / uat, `-docker-prod` for prd
- External Kafka access: `loadBalancer` type — CFK creates per-broker LBs plus a bootstrap LB

> **Temporary approved exception**: PRD pulls Confluent images from
> `camdepositsharedservices-docker-dev` until the production Artifactory
> repository is available. Image names and immutable version tags remain
> controlled. Migrate to `camdepositsharedservices-docker-prod` after
> repository readiness is confirmed.

**Storage** (resolved from [`docs/OpenShift Persistent Storage.pdf`](../../../docs/OpenShift%20Persistent%20Storage.pdf)):

FCB provisioned a dedicated **`kafka`** StorageClass on vSphere CSI (`csi.vsphere.vmware.com`) for this workload, with `reclaimPolicy: Retain` (PVs are preserved if a PVC gets deleted — data-safety for the log dirs / quorum log / RocksDB state) and `allowVolumeExpansion: true`. Owned by Container Platforms (`ContainerPlatforms@firstcitizens.com`), backed by a dedicated vSphere datastore. We use it for every PV in this stack — Kafka log dirs, KRaft quorum log, and Control Center RocksDB state. CFK workloads are single-writer per PV, so block-mode is the right shape (no need for RWX / filesystem SCs on the cluster). Previously used `ocs-storagecluster-ceph-rbd`; switched on 2026-07-06 to the dedicated `kafka` SC.

**PV determinism — broker/controller/C3 always rebind to their own PV.** CFK turns `spec.dataVolumeCapacity` + `spec.storageClass.name` into a StatefulSet `volumeClaimTemplate`. Each pod gets a deterministically-named PVC tied to its ordinal:

| StatefulSet | PVC names |
|---|---|
| `kafka` | `data-kafka-0`, `data-kafka-1`, `data-kafka-2` |
| `kraftcontroller` | `data-kraftcontroller-0`, `data-kraftcontroller-1`, `data-kraftcontroller-2` |
| `controlcenter` | `data-controlcenter-0` |

When a pod restarts — same node, evicted to another node, or after a `helm`-style replace — Kubernetes reuses the **same PVC**, which is bound to the **same PV**. Since the underlying volume is Ceph RBD (network-attached), the PV is re-attachable from any worker, so a broker can drift to a different node and still come back up with its log dir intact. The deterministic name also means the broker's `node.id` ↔ PVC ↔ log dir mapping is stable across the entire cluster lifetime — `kafka-1` always reads from the same `data-kafka-1` PV.

**Pod anti-affinity — brokers spread, controllers spread, mixed colocation allowed.** The Kafka and KRaftController CRs each define a hard `podAntiAffinity` on `kubernetes.io/hostname` keyed by a custom `cfk-role` pod label. The result:

- No two brokers on the same node (`cfk-role: kafka-broker`)
- No two controllers on the same node (`cfk-role: kraft-controller`)
- A broker and a controller MAY colocate on the same node — they carry different `cfk-role` values, so neither anti-affinity rule matches across components

In a 3+ worker cluster this means brokers and controllers each fully spread, and you can have at most one broker + one controller per worker. With Ceph RBD storage, an evicted broker rescheduled to a different worker still picks up its own PV — see "PV determinism" above.

**Backup caveat** (from [`docs/OpenShift Backup and Restore.pdf`](../../../docs/OpenShift%20Backup%20and%20Restore.pdf)):

OADP / Velero is the platform backup mechanism, but the PDF explicitly notes it is **not intended for volumes ≥ 500 GB**. Our broker volumes are 1 TB today (4 TB planned), well above that threshold. We will **not** rely on OADP for Kafka data protection. Instead, DR sits at the Kafka layer:

- **Intra-cluster**: RF=3 across the 3 brokers in each env.
- **Cross-env**: cluster-link between the CFK CP envs (and to the existing VM CP during migration) — same pattern the VM PRD-1 ↔ PRD-2 already uses.

KRaft controller (64 GB) and C3 (300 GB) volumes are under the 500 GB threshold so they're eligible for OADP if needed; we can ask Container Platforms to add a Schedule for the namespace if they want one.

**Versions, accounts, and hostnames (set in this commit)**:

- **CFK / init container**: `0.1351.59` (matches the vendored chart `charts/confluent-for-kubernetes/` `appVersion: 3.1.1`, operator image `confluentinc/confluent-operator:0.1351.59`). The same tag is used for `confluentinc/confluent-init-container`. If FCB's Container Platforms upgrades the operator, bump these in lockstep.
- **Service account**: `flink-operator` — same SA the CMF and Flink Operator pods run under. RBAC is owned by FCB's `fcb-security` ArgoCD chart in `dah-flink-prod`.
- **External Kafka LB** (tentative — confirm with Tom; needs hostname under `*.ocp.fcbint.net` per Keyfactor approver-policy):
  - bootstrap: `bootstrap.kafka.dev.dah.fcbint.net`
  - brokers: `b0/b1/b2.kafka.dev.dah.fcbint.net`
  - **Note**: these SANs are *not* in the cert today — Keyfactor rejected the request as a policy violation (allowed suffixes are `*.svc`, `*.svc.cluster.local`, `*.ocp.fcbint.net`; `*.dah.fcbint.net` is not allowed). Internal cluster bringup is unaffected (CMF, Flink jobs use the internal `*.svc.cluster.local` listener). Re-add the SANs once a real LB hostname is allocated under `*.ocp.fcbint.net`.
- **External C3 UI** (tentative): same situation — SAN removed from the cert until a real Route hostname under `*.apps.<cluster>.ocp.fcbint.net` is allocated.

**MDS token keypair** (`mds-token-keypair` Secret — *manual one-time setup, not pipeline-managed*):

CFK's MDS uses a **raw RSA keypair PEM**, not an X.509 cert, so **cert-manager is the wrong tool** — its `tls.crt` + `tls.key` shape doesn't match what MDS expects in the Secret. Two options:

1. **Reuse the VM keypair (recommended for migration)** — the VM brokers' `/var/ssl/private/tokenKeypair.pem` is the keypair MDS currently signs tokens with. Copy that file into a K8s Secret in `dah-flink-prod`:
   ```
   oc create secret generic mds-token-keypair \
     --from-file=mdsTokenKeyPair.pem=tokenKeypair.pem \
     -n dah-flink-prod
   ```
   This keeps VM-issued tokens valid in the CFK cluster during the cluster-link migration window.

2. **Generate fresh** — `openssl genrsa -out mds.pem 4096` and push as above. Cleaner cutover but invalidates every VM-issued token, forcing all clients to re-auth.

The keypair should not rotate (rotation invalidates outstanding tokens), so this is one-time setup — *not* pipeline-managed and not driven by cert-manager.

**Still open** (search for `REPLACE_WITH_` if any remain):
- LB / C3 hostnames are tentative until Tom confirms — if they change, update `kafka.yaml`, `kafka-tls-certificate.yaml`, and `controlcenter-tls-certificate.yaml` together.

## Cross-reference

- VM reference properties: [`../cp-confluent/dev/`](../cp-confluent/dev/)
- Project memory on the migration plan: `project_cfk_migration.md`
- Flink stays pointed at the VM cluster until migration completes: `project_flink_targets_vm_cp.md`

## Cluster Linking + Schema Linking

Link configuration for this environment lives in [`cluster-linking/`](cluster-linking/) (endpoints, topic / consumer-group / ACL / subject lists, `ClusterLink` and `SchemaExporter` CR templates, destination role bindings). It is driven by `.azure-pipelines/cluster-linking.yaml`; see the folder README for the action order.
