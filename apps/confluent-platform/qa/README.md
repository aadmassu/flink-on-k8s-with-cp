# CFK Confluent Platform — qa

CFK Custom Resources for a fresh CP cluster in `dah-flink-qa`. QA has **no VM CP analog** — FCB never built a VM QA Confluent Platform (per `project_cfk_migration.md`). This folder is therefore modelled on the [UAT CFK build](../uat/) rather than carried over from a VM cluster.

Structurally identical to [`../uat/`](../uat/); see the [dev README](../dev/README.md) for the full design rationale (worker-node sizing, anti-affinity, MDS keypair handling, storage class choice, etc.). This README only calls out **what's different in qa**.

## Target

- **Confluent Platform**: 8.1.x
- **CFK operator**: same operator instance that watches `dah-flink-dev` and `dah-flink-uat`; it also watches `dah-flink-qa`.
- **Namespace**: `dah-flink-qa`
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

## What's QA-specific in every CR

| Field | QA value | UAT value (for contrast) |
|---|---|---|
| Namespace | `dah-flink-qa` | `dah-flink-uat` |
| OAuth scope | `11547.DAH(UAT)` *(reused — see TODO below)* | `11547.DAH(UAT)` |
| Groups claim | `dahUAT_groups` *(reused — see TODO below)* | `dahUAT_groups` |
| Keyfactor `Environment` annotation | `Non-Prod-QA` | `Non-Prod-UAT` |
| External Kafka LB domain | `kafka.qa.dah.fcbint.net` (tentative) | `kafka.uat.dah.fcbint.net` (tentative) |
| Schema Registry replicas | 2 | 2 |
| Kafka REST Proxy replicas | 2 | 2 |

## ⚠️ OAuth values — reused from UAT pending Okta admin decision

Every CFK CR in this folder reuses UAT's OAuth `scope` (`11547.DAH(UAT)`) and `groupsClaimName` (`dahUAT_groups`) verbatim. This is **deliberate** — it lets the QA cluster authenticate against the existing UAT Okta application during bring-up, before FCB Okta admins decide whether to:

1. **Keep reusing UAT's Okta tenant for QA** — no manifest changes needed. Acceptable if QA is a transient test environment whose users and groups overlap with UAT.
2. **Provision dedicated QA Okta clients** — requires sweeping every `11547.DAH(UAT)` → `11547.DAH(QA)` and `dahUAT_groups` → `dahQA_groups` here. Cleaner separation but requires Okta admin work.

The `TODO:` comments throughout the CRs flag every line that needs updating if option 2 is chosen. Search for `TODO: switch to QA` to find them all.

## Apply order

```
confluent-platform.yaml  environment=qa  action=create-prereqs
confluent-platform.yaml  environment=qa  action=install
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

Sizing matches dev/uat — driven by the 16 vCPU / 32 GiB FCB worker-node fit. PVC sizing is held at dev's TEMP values until the `dah-flink-qa` namespace `ResourceQuota` is confirmed with Tom.

## Cross-reference

- UAT CRs (template): [`../uat/`](../uat/)
- Dev CRs (reference): [`../dev/`](../dev/)
- Project memory on the migration plan: `project_cfk_migration.md` — notes that QA has no VM CP analog
