# CFK Confluent Platform — stg

CFK Custom Resources for the STG cluster in `dah-flink-stg`. STG **does** have a VM CP analog at FCB (per `project_cfk_migration.md`), but [`../cp-confluent/stg/`](../cp-confluent/stg/) is not yet populated in this repo. Until those VM `.properties` files are added, this folder is modelled on the [UAT CFK build](../uat/) and uses UAT OAuth values verbatim — see the OAuth section below.

Structurally identical to [`../uat/`](../uat/); see the [dev README](../dev/README.md) for the full design rationale (worker-node sizing, anti-affinity, MDS keypair handling, storage class choice, etc.). This README only calls out **what's different in stg**.

## Target

- **Confluent Platform**: 8.1.x
- **CFK operator**: same operator instance that watches `dah-flink-dev`, `dah-flink-qa`, and `dah-flink-uat`; it also watches `dah-flink-stg`.
- **Namespace**: `dah-flink-stg`
- **Mode**: KRaft (3 controllers, 3 brokers)

## Topology

Mirrors the UAT CFK topology:

| Component | Replicas | CR file |
|---|---|---|
| KRaft Controller | 3 | [`kraftcontroller.yaml`](kraftcontroller.yaml) |
| Kafka Broker | 3 | [`kafka.yaml`](kafka.yaml) |
| Schema Registry | **2** | [`schemaregistry.yaml`](schemaregistry.yaml) |
| Connect | 2 | [`connect.yaml`](connect.yaml) |
| Kafka REST Proxy | **2** | [`kafkarest.yaml`](kafkarest.yaml) |
| Control Center | 1 | [`controlcenter.yaml`](controlcenter.yaml) |

When the VM STG `.properties` files land in [`../cp-confluent/stg/`](../cp-confluent/stg/), revisit replica counts and any per-host config that should be carried over (advertised listeners, telemetry exporter endpoints, OIDC client IDs, etc.) — same drill as we did for UAT.

## What's STG-specific in every CR

| Field | STG value | UAT value (for contrast) |
|---|---|---|
| Namespace | `dah-flink-stg` | `dah-flink-uat` |
| OAuth scope | `11547.DAH(UAT)` *(reused — see TODO below)* | `11547.DAH(UAT)` |
| Groups claim | `dahUAT_groups` *(reused — see TODO below)* | `dahUAT_groups` |
| Keyfactor `Environment` annotation | `Non-Prod-STG` | `Non-Prod-UAT` |
| External Kafka LB domain | `kafka.stg.dah.fcbint.net` (tentative) | `kafka.uat.dah.fcbint.net` (tentative) |
| Schema Registry replicas | 2 | 2 |
| Kafka REST Proxy replicas | 2 | 2 |

## ⚠️ OAuth values — reused from UAT pending Okta admin decision (STG is pre-prod — DO NOT skip this step before staging traffic moves over)

Every CFK CR in this folder reuses UAT's OAuth `scope` (`11547.DAH(UAT)`) and `groupsClaimName` (`dahUAT_groups`) verbatim. STG is the **last non-prod stage before prd-1 / prd-2**, so the decision to keep or replace these values has higher stakes than the equivalent decision for QA:

1. **Keep reusing UAT's Okta tenant for STG** — fine only if STG truly mirrors UAT's identity domain (same users, same group memberships). Rare in practice for a staging environment.
2. **Provision dedicated STG Okta clients** — required for any STG that needs its own RBAC posture distinct from UAT. Sweep every `11547.DAH(UAT)` → `11547.DAH(STG)` and `dahUAT_groups` → `dahSTG_groups`. The `TODO:` comments in every CR mark each line that needs updating — grep for `TODO: switch to STG` to find them all.

Once the VM STG `.properties` files are added to [`../cp-confluent/stg/`](../cp-confluent/stg/), the actual STG OAuth client IDs / secrets / scope / groups claim should be lifted from them — same pattern we used when authoring UAT from `cp-confluent/uat/`.

## Apply order

```
confluent-platform.yaml  environment=stg  action=create-prereqs
confluent-platform.yaml  environment=stg  action=install
```

CR apply order inside the `install` action:

1. `kafkarestclass.yaml`
2. `kraftcontroller.yaml`
3. `kafka.yaml`
4. `schemaregistry.yaml`
5. `connect.yaml`
6. `kafkarest.yaml`
7. `controlcenter.yaml`

Run after `prereqs/` Certificate CRs land their `*-tls` Secrets (the pipeline handles this — applies Certificates then waits up to 10 min per cert for Keyfactor).

## Sizing

Sizing matches dev/qa/uat — driven by the 16 vCPU / 32 GiB FCB worker-node fit. PVC sizing is held at dev's TEMP values until the `dah-flink-stg` namespace `ResourceQuota` is confirmed with Tom. STG is pre-prod, so PVCs **must** be bumped to VM-equivalent sizes (1 TiB broker / 64 GiB controller / 300 GiB C3) before any staging traffic moves over.

## Cross-reference

- UAT CRs (template): [`../uat/`](../uat/)
- QA CRs (sibling pre-prod env): [`../qa/`](../qa/)
- Dev CRs (reference): [`../dev/`](../dev/)
- VM STG properties (to be populated): [`../cp-confluent/stg/`](../cp-confluent/stg/) *(not yet in repo)*
- Project memory on the migration plan: `project_cfk_migration.md`
