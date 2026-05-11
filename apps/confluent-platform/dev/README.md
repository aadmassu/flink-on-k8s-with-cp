# CFK Confluent Platform — dev

CFK Custom Resources that reproduce the existing dev VM Confluent Platform cluster on OpenShift. Every CR in this folder is authored against the corresponding `.properties` file under [`../cp-confluent/dev/`](../cp-confluent/dev/) — that's the source of truth for parity.

## Target

- **Confluent Platform**: 8.1.x
- **CFK operator**: latest version that supports CP 8.1.x. Operator install is owned by FCB's Container Platforms team; FCB will upgrade if a newer version is required.
- **Namespace**: `dah-flink-dev` (CFK operator lives in its own namespace and watches `dah-flink-<env>`)
- **Mode**: KRaft (3 controllers, 3 brokers) — matching the dev VM cluster

## Topology mirrored from VM dev

| Component | Replicas | VM hosts | CR file |
|---|---|---|---|
| KRaft Controller | 3 | `d11547varc-jxvh`, `pnvg`, `d2kd` | [`kraftcontroller.yaml`](kraftcontroller.yaml) |
| Kafka Broker | 3 | `d11547varc-pgm8`, `g719`, `81mb` | [`kafka.yaml`](kafka.yaml) |
| Schema Registry | 1 | `d11547varc-4559` | [`schemaregistry.yaml`](schemaregistry.yaml) |
| Connect | 2 | `d11547varc-y0lb`, `rigt` | [`connect.yaml`](connect.yaml) |
| Kafka REST Proxy | 1 | `d11547varc-hsu5` | [`kafkarest.yaml`](kafkarest.yaml) |
| Control Center | 1 | `d11547varc-g5w0` | [`controlcenter.yaml`](controlcenter.yaml) |

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

1. **`create-prereqs` action** — pipeline creates the 11 non-TLS Opaque Secrets from `<env>-openshift-credentials` variable group entries. See [`prereqs/README.md`](prereqs/README.md) for the variable mapping.
2. **`install` action**:
   1. Apply the six TLS `Certificate` CRs under `prereqs/`. Pipeline waits up to 10 min per cert for Keyfactor to materialize each `*-tls` Secret.
   2. `kafkarestclass.yaml` — connection profile referenced by Connect + ControlCenter.
   3. `kraftcontroller.yaml` — KRaft quorum must be up before brokers register.
   4. `kafka.yaml` — brokers join the quorum.
   5. `schemaregistry.yaml` — uses Kafka as its kafkastore.
   6. `connect.yaml` — needs Kafka + SR.
   7. `kafkarest.yaml` — needs Kafka + SR.
   8. `controlcenter.yaml` — depends on all of the above.

## Capacity (from `docs/server capacity and utlization.png`)

| Component | Cores | RAM | Disk | Notes |
|---|---|---|---|---|
| Broker (×3) | 16 (→ 26 planned) | 16 GB | 1 TB (→ 4 TB planned) | 2% utilization today |
| Controller (×3) | 4 | 4 GB | 64 GB | 9% |
| Schema Registry | 4 | 4 GB | 64 GB | stable, moderate |
| REST Proxy | 4 | 4 GB | 64 GB | — |
| Connect (×2) | 4 | 4 GB | 64 GB | moderate |
| Control Center | 12 | 16 GB | 300 GB | stable |

The CR `resources.requests` track these values; raise `limits` if the planned core/disk bump goes through.

## What's preserved vs adapted from the VM config

**Preserved as-is** (cluster contract — don't change without coordinating with VM clients):
- All inter-component topic replication factors = 3 (`offsets`, `transaction`, `__confluent-command`, `_schemas`, `_confluent-monitoring`, `_confluent-secrets`, `connect-cluster-*`)
- Log retention 168h (7d), 1 GiB segments
- Min ISR for transaction-state log = 2
- KRaft quorum size = 3
- OAuth issuer (Okta: `myapps.firstcitizens.com/oauth2/default`), JWKS endpoint, scope `11547.DAH(Dev)`
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

**Storage** (resolved from [`docs/OpenShift Persistent Storage.pdf`](../../../docs/OpenShift%20Persistent%20Storage.pdf)):

FCB OpenShift uses **OpenShift Data Foundation (ODF / Ceph)** with two storage classes. We use **`ocs-storagecluster-ceph-rbd`** (raw block device) for every PV in this stack — Kafka log dirs, KRaft quorum log, and Control Center RocksDB state. The alternative (`ocs-storagecluster-ceph-filesystem`) is CephFS RWX and would add an FS layer overhead that's not needed for these single-writer workloads.

**Backup caveat** (from [`docs/OpenShift Backup and Restore.pdf`](../../../docs/OpenShift%20Backup%20and%20Restore.pdf)):

OADP / Velero is the platform backup mechanism, but the PDF explicitly notes it is **not intended for volumes ≥ 500 GB**. Our broker volumes are 1 TB today (4 TB planned), well above that threshold. We will **not** rely on OADP for Kafka data protection. Instead, DR sits at the Kafka layer:

- **Intra-cluster**: RF=3 across the 3 brokers in each env.
- **Cross-env**: cluster-link between the CFK CP envs (and to the existing VM CP during migration) — same pattern the VM PRD-1 ↔ PRD-2 already uses.

KRaft controller (64 GB) and C3 (300 GB) volumes are under the 500 GB threshold so they're eligible for OADP if needed; we can ask Container Platforms to add a Schedule for the namespace if they want one.

**Versions, accounts, and hostnames (set in this commit)**:

- **CFK / init container**: `0.1351.59` (matches the vendored chart `charts/confluent-for-kubernetes/` `appVersion: 3.1.1`, operator image `confluentinc/confluent-operator:0.1351.59`). The same tag is used for `confluentinc/confluent-init-container`. If FCB's Container Platforms upgrades the operator, bump these in lockstep.
- **Service account**: `flink-operator` — same SA the CMF and Flink Operator pods run under. RBAC is owned by FCB's `fcb-security` ArgoCD chart in `dah-flink-dev`.
- **External Kafka LB** (tentative — confirm with Tom 2026-05-12):
  - bootstrap: `bootstrap.kafka.dev.dah.fcbint.net`
  - brokers: `b0/b1/b2.kafka.dev.dah.fcbint.net`
- **External C3 UI** (tentative): `c3.dev.dah.fcbint.net`

**MDS token keypair** (`mds-token-keypair` Secret — *manual one-time setup, not pipeline-managed*):

CFK's MDS uses a **raw RSA keypair PEM**, not an X.509 cert, so **cert-manager is the wrong tool** — its `tls.crt` + `tls.key` shape doesn't match what MDS expects in the Secret. Two options:

1. **Reuse the VM keypair (recommended for migration)** — the VM brokers' `/var/ssl/private/tokenKeypair.pem` is the keypair MDS currently signs tokens with. Copy that file into a K8s Secret in `dah-flink-dev`:
   ```
   oc create secret generic mds-token-keypair \
     --from-file=mdsTokenKeyPair.pem=tokenKeypair.pem \
     -n dah-flink-dev
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
