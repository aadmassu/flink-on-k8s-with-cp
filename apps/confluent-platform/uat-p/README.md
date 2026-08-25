# CFK Confluent Platform — qa

CFK Custom Resources that reproduce the existing qa VM Confluent Platform cluster on OpenShift. Every CR in this folder is authored against the corresponding `.properties` file under [`../cp-confluent/qa/`](../cp-confluent/qa/) — that's the source of truth for parity.

> **UAT migration sizing (2026-08-15):** ResourceQuota now permits
> 1,272 Gi of requested storage. This package assigns 1,175 Gi to CFK and
> leaves 97 Gi free: Kafka 3 x 300 Gi, KRaft 3 x 25 Gi, Control Center
> 100 Gi, and bundled Prometheus 100 Gi. See
> [`UAT_RESOURCE_BUDGET.md`](UAT_RESOURCE_BUDGET.md) for the complete CPU,
> memory, storage, and reserved-capacity calculation.

## Target

- **Confluent Platform**: 8.1.x
- **CFK operator**: latest version that supports CP 8.1.x. Operator install is owned by FCB's Container Platforms team; FCB will upgrade if a newer version is required.
- **Namespace**: `dah-flink-uat` (CFK operator lives in its own namespace and watches `dah-flink-<env>`)
- **Mode**: KRaft (3 controllers, 3 brokers) — matching the qa VM cluster

## Topology mirrored from VM qa

| Component | Replicas | VM hosts | CR file |
|---|---|---|---|
| KRaft Controller | 3 | `d11547varc-jxvh`, `pnvg`, `d2kd` | [`kraftcontroller.yaml`](kraftcontroller.yaml) |
| Kafka Broker | 3 | `d11547varc-pgm8`, `g719`, `81mb` | [`kafka.yaml`](kafka.yaml) |
| Schema Registry | 2 | `d11547varc-4559` | [`schemaregistry.yaml`](schemaregistry.yaml) |
| Connect | 2 | `d11547varc-y0lb`, `rigt` | [`connect.yaml`](connect.yaml) |
| Kafka REST Proxy | 1 | `d11547varc-hsu5` | [`kafkarest.yaml`](kafkarest.yaml) |
| Control Center | 1 | `d11547varc-g5w0` | [`controlcenter.yaml`](controlcenter.yaml) |

## Folder layout

```
qa/
├── README.md                  (this file)
├── kafkarestclass.yaml        \
├── kraftcontroller.yaml        |
├── kafka.yaml                  |  ── CFK Custom Resources (root)
├── schemaregistry.yaml         |
├── connect.yaml                |
├── kafkarest.yaml              |
├── controlcenter.yaml         /
├── controlcenter-prometheus-pvc.yaml ── explicit kafka-SC PVC
├── UAT_RESOURCE_BUDGET.md     ── quota and headroom calculation
└── prereqs/                   ── supporting prerequisites (TLS Certificates + prereqs README)
    ├── README.md
    └── *-tls-certificate.yaml
```

CFK CRs live at the root for clear grouping. The `prereqs/` subfolder holds the cert-manager `Certificate` CRs that land the six `*-tls` Secrets, plus its own [README](prereqs/README.md) documenting the 11 non-TLS Opaque Secrets the pipeline creates from variable-group values.

## Infrastructure ownership — NetworkPolicy

**NetworkPolicy is owned and managed exclusively by the Container Platforms team** in UAT and all upper environments (uat-p, uat-s, prd, dr). The application pipeline:

- **Never creates, modifies, or deletes** NetworkPolicy in non-DEV environments
- **Skips NetworkPolicy validation and ingress-router port checking** for non-DEV
- **Prints an informational message** during install/uninstall to remind operators that network rules are managed by FCB Container Platforms
- **Fails hard** (exit 1) if a `network-policy/` directory is found in a non-DEV environment's manifest tree

**DEV is the exception.** The application pipeline manages NetworkPolicy in dev only; the Container Platforms team owns the function in all other environments and will apply equivalent rules as part of their upper-environment provisioning.

Contact Rick Mulder (Principal Infrastructure Engineer, Container Platforms) or submit a SNOW request if you need network access changes in UAT or higher.

## Apply order

Run the pipeline twice — `create-prereqs` first, then `install-or-update`.
For a destructive migration rebuild, run `uninstall` with `wipePVCs=true`
first. The pipeline applies in this sequence so failures attribute correctly:

1. **`create-prereqs` action** — pipeline creates the non-TLS Opaque Secrets from `kafka-openshift-credentials-<env>` variable group entries. See [`prereqs/README.md`](prereqs/README.md) for the variable mapping.
2. **`install-or-update` action**:
   1. Apply the TLS `Certificate` CRs under `cert-manager/`. Pipeline waits for Keyfactor to materialize each `*-tls` Secret.
   2. `kafkarestclass.yaml` — connection profile referenced by Connect + ControlCenter.
   3. `kraftcontroller.yaml` — KRaft quorum must be up before brokers register.
   4. `kafka.yaml` — brokers join the quorum.
   5. `schemaregistry.yaml` — uses Kafka as its kafkastore.
   6. `connect.yaml` — needs Kafka + SR.
   7. `kafkarest.yaml` — needs Kafka + SR.
   8. `controlcenter-prometheus-pvc.yaml` — creates the nested Prometheus claim with `storageClassName: kafka`.
   9. `controlcenter.yaml` — depends on all of the above.

## Application onboarding RBAC

Application/user access is intentionally separate from cluster installation.
Run `.azure-pipelines/application-rbac.yaml` after the UAT cluster is ready.
The UAT variable group must contain the verified token identities below:

| Variable | Required value |
|---|---|
| `uat-rbac-onboarding-user-sub` | UAT user's exact OIDC `sub` claim |
| `uat-rbac-onboarding-developer-group` | Exact UAT developer group claim emitted in the token |

The pipeline renders these only into temporary files. In
`direct-mds-bootstrap` mode, `@live` in the JSON input is replaced with the
new Kafka CR's live `status.clusterID`; a destructive reinstall therefore
does not leave a stale hard-coded Kafka cluster ID.

## Capacity (CFK CR settings vs. VM source)

| Component | CR `requests` | CR `limits` | Disk | VM allocation / utilization |
|---|---|---|---|---|
| Broker (×3) | 1 vCPU / 3 Gi | 2 vCPU / 6 Gi | **300 Gi each** | Migration priority |
| Controller (×3) | 0.75 vCPU / 2 Gi | 1.5 vCPU / 3 Gi | **25 Gi each** | Quorum headroom |
| Schema Registry (×2) | 0.15 vCPU / 768 Mi | 0.5 vCPU / 1.5 Gi | — | Stateless |
| REST Proxy | 0.125 vCPU / 512 Mi | 0.375 vCPU / 1 Gi | — | Stateless |
| Connect (×2) | 0.25 vCPU / 1 Gi | 0.5 vCPU / 2 Gi | — | Stateless; state in Kafka |
| Control Center | 0.5 vCPU / 3 Gi | 1.5 vCPU / 6 Gi | **100 Gi** | Working/RocksDB state |
| C3 Prometheus | 0.375 vCPU / 1 Gi | 1.25 vCPU / 3 Gi | **100 Gi** | Pre-created PVC |
| C3 Alertmanager | 0.1 vCPU / 512 Mi | 0.5 vCPU / 1 Gi | — | No PVC |

The pipeline performs a live quota projection before mutation. It subtracts
the currently deployed CFK footprint, adds this desired footprint, and reserves
capacity for Flink and operations. It fails rather than consuming the reserve.

## What's preserved vs adapted from the VM config

**Preserved as-is** (cluster contract — don't change without coordinating with VM clients):
- All inter-component topic replication factors = 3 (`offsets`, `transaction`, `__confluent-command`, `_schemas`, `_confluent-monitoring`, `_confluent-secrets`, `connect-cluster-*`)
- Log retention 168h (7d), 1 GiB segments
- Min ISR for transaction-state log = 2
- KRaft quorum size = 3
- OAuth issuer (Okta: `myapps.firstcitizens.com/oauth2/default`), JWKS endpoint, and UAT scope `11547.DAH(UAT)`
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
- Container images use the same Artifactory pattern as Flink: `artifactory.fcbint.net/camdepositsharedservices-docker-dev/confluentinc/cp-*:8.1.3` (UAT pulls from DEV repo) and `-docker-prod` for prd
- External Kafka access: `loadBalancer` type — CFK creates per-broker LBs plus a bootstrap LB

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
- **Service account**: `flink-operator` — same SA the CMF and Flink Operator pods run under. RBAC is owned by FCB's `fcb-security` ArgoCD chart in `dah-flink-uat`.
- **External Kafka LB** (tentative — confirm with Tom; needs hostname under `*.ocp.fcbint.net` per Keyfactor approver-policy):
  - bootstrap: `bootstrap.kafka.qa.dah.fcbint.net`
  - brokers: `b0/b1/b2.kafka.qa.dah.fcbint.net`
  - **Note**: these SANs are *not* in the cert today — Keyfactor rejected the request as a policy violation (allowed suffixes are `*.svc`, `*.svc.cluster.local`, `*.ocp.fcbint.net`; `*.dah.fcbint.net` is not allowed). Internal cluster bringup is unaffected (CMF, Flink jobs use the internal `*.svc.cluster.local` listener). Re-add the SANs once a real LB hostname is allocated under `*.ocp.fcbint.net`.
- **External C3 UI** (tentative): same situation — SAN removed from the cert until a real Route hostname under `*.apps.<cluster>.ocp.fcbint.net` is allocated.

**MDS token keypair** (`mds-token-keypair` Secret — *manual one-time setup, not pipeline-managed*):

CFK's MDS uses a **raw RSA keypair PEM**, not an X.509 cert, so **cert-manager is the wrong tool** — its `tls.crt` + `tls.key` shape doesn't match what MDS expects in the Secret. Two options:

1. **Reuse the VM keypair (recommended for migration)** — the VM brokers' `/var/ssl/private/tokenKeypair.pem` is the keypair MDS currently signs tokens with. Copy that file into a K8s Secret in `dah-flink-uat`:
   ```
   oc create secret generic mds-token-keypair \
     --from-file=mdsTokenKeyPair.pem=tokenKeypair.pem \
     -n dah-flink-uat
   ```
   This keeps VM-issued tokens valid in the CFK cluster during the cluster-link migration window.

2. **Generate fresh** — `openssl genrsa -out mds.pem 4096` and push as above. Cleaner cutover but invalidates every VM-issued token, forcing all clients to re-auth.

The keypair should not rotate (rotation invalidates outstanding tokens), so this is one-time setup — *not* pipeline-managed and not driven by cert-manager.

**Still open** (search for `REPLACE_WITH_` if any remain):
- LB / C3 hostnames are tentative until Tom confirms — if they change, update `kafka.yaml`, `kafka-tls-certificate.yaml`, and `controlcenter-tls-certificate.yaml` together.

## Cross-reference

- VM reference properties: [`../cp-confluent/qa/`](../cp-confluent/qa/)
- Project memory on the migration plan: `project_cfk_migration.md`
- Flink stays pointed at the VM cluster until migration completes: `project_flink_targets_vm_cp.md`
