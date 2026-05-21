# CFK Confluent Platform — uat

CFK Custom Resources that reproduce the existing UAT VM Confluent Platform cluster on OpenShift. Every CR in this folder is authored against the corresponding `.properties` file under [`../cp-confluent/uat/`](../cp-confluent/uat/) — that's the source of truth for parity.

Structurally identical to [`../dev/`](../dev/); see the dev README for the full design rationale (worker-node sizing, anti-affinity, MDS keypair handling, storage class choice, etc.). This README only calls out **what's different in uat**.

## Target

- **Confluent Platform**: 8.1.x
- **CFK operator**: same operator instance that watches `dah-flink-dev`; it also watches `dah-flink-uat` (FCB Container Platforms owns the operator install).
- **Namespace**: `dah-flink-uat`
- **Mode**: KRaft (3 controllers, 3 brokers) — matching the UAT VM cluster

## Topology mirrored from VM uat

| Component | Replicas | VM hosts | CR file |
|---|---|---|---|
| KRaft Controller | 3 | `t11547varc-00c1`, `zg6u`, `kprg` | [`kraftcontroller.yaml`](kraftcontroller.yaml) |
| Kafka Broker | 3 | `t11547varc-9vdq`, `9tcm`, `mcae` | [`kafka.yaml`](kafka.yaml) |
| Schema Registry | **2** | `t11547varc-b9eb`, `lntz` | [`schemaregistry.yaml`](schemaregistry.yaml) |
| Connect | 2 | `t11547varc-4zxw`, `5cr4` | [`connect.yaml`](connect.yaml) |
| Kafka REST Proxy | **2** | `t11547varc-0wjc`, `amm5` | [`kafkarest.yaml`](kafkarest.yaml) |
| Control Center | 1 | `t11547varc-mdnp` | [`controlcenter.yaml`](controlcenter.yaml) |

**Differences from dev** (which has 1 SR + 1 REST + 1 Connect → 2):
- Schema Registry runs as **2 replicas** (HA pair backed by the same `_schemas` Kafka topic).
- Kafka REST Proxy runs as **2 replicas** (matches VM UAT's 2-host REST Proxy deployment).

## What's UAT-specific in every CR

| Field | UAT value | dev value (for contrast) |
|---|---|---|
| Namespace | `dah-flink-uat` | `dah-flink-dev` |
| OAuth scope | `11547.DAH(UAT)` | `11547.DAH(Dev)` |
| Groups claim | `dahUAT_groups` | `dahDev_groups` |
| Keyfactor `Environment` annotation | `Non-Prod-UAT` | `Non-Prod-DEV` |
| External Kafka LB domain | `kafka.uat.dah.fcbint.net` (tentative) | `kafka.dev.dah.fcbint.net` (tentative) |
| Schema Registry replicas | 2 | 1 |
| Kafka REST Proxy replicas | 2 | 1 |

Container image registry path is `camdepositsharedservices-docker-dev` for all non-prd envs (per the FCB Artifactory layout) — same as dev.

## Apply order

Run the pipeline twice — `create-prereqs` first, then `install`:

1. **`create-prereqs` action** — pipeline creates the 11 non-TLS Opaque Secrets from `uat-openshift-credentials` variable group entries. See [`prereqs/README.md`](prereqs/README.md) for the variable mapping.
2. **`install` action**:
   1. Apply the six TLS `Certificate` CRs under `prereqs/`. Pipeline waits up to 10 min per cert for Keyfactor to materialize each `*-tls` Secret.
   2. `kafkarestclass.yaml` — connection profile referenced by Connect + ControlCenter.
   3. `kraftcontroller.yaml` — KRaft quorum must be up before brokers register.
   4. `kafka.yaml` — brokers join the quorum.
   5. `schemaregistry.yaml` — uses Kafka as its kafkastore.
   6. `connect.yaml` — needs Kafka + SR.
   7. `kafkarest.yaml` — needs Kafka + SR.
   8. `controlcenter.yaml` — depends on all of the above.

Trigger the pipeline with:

```
confluent-platform.yaml  environment=uat  action=create-prereqs
confluent-platform.yaml  environment=uat  action=install
```

## Capacity / sizing

Sizing follows dev's CFK CR requests / limits — those are driven by the **16 vCPU / 32 GiB worker-node fit** (a property of the FCB OpenShift hardware, not the environment). PVC sizing is held at dev's TEMP values until the `dah-flink-uat` namespace `ResourceQuota` is confirmed with Tom; bump back to VM-equivalent disk sizes (1 TiB broker, 64 GiB controller, 300 GiB C3) once quota allows.

See the dev README's [Capacity](../dev/README.md#capacity-cfk-cr-settings-vs-vm-source) section for the full table and rationale.

## Cross-reference

- VM reference properties: [`../cp-confluent/uat/`](../cp-confluent/uat/)
- Dev CRs (template): [`../dev/`](../dev/)
- Project memory on the migration plan: `project_cfk_migration.md`
- Flink stays pointed at the VM cluster until migration completes: `project_flink_targets_vm_cp.md`
