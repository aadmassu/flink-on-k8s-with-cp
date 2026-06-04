# Confluent Platform — CFK on OpenShift

CFK-based Confluent Platform deployment for FCB's OpenShift cluster — the **target** platform that will eventually replace the existing RPM-on-VM CP via cluster-link migration. The CFK operator is installed in its own namespace and watches the `dah-flink-<env>` namespaces where these CRs land.

## Layout

```
apps/confluent-platform/
├── README.md                    (this file)
├── cp-confluent/                # Reference: existing VM CP .properties files
│   ├── dev/                     # populated
│   ├── uat/                     # to follow
│   ├── stg/                     # to follow
│   ├── prd-1/                   # to follow (active prod)
│   └── prd-2/                   # to follow (passive prod, cluster-linked to prd-1)
├── dev/                         # CFK CRs (placeholders today)
├── qa/                          # CFK CRs (placeholders today)
├── uat/                         # CFK CRs (placeholders today)
├── stg/                         # CFK CRs (placeholders today)
├── prd-1/                       # CFK CRs (placeholders today)
└── prd-2/                       # CFK CRs (placeholders today)
```

## Two halves explained

### `cp-confluent/<env>/` — VM reference (read-only source of truth)

Holds the **actual `.properties` files copied verbatim from the running VM CP brokers, controllers, Schema Registry, Connect workers, REST Proxy, and Control Center**. These are the contract against which the CFK CRs are authored. Don't edit them to "improve" things — they reflect what the VM components are running today, and the goal is parity.

VM envs that have a reference folder today: **dev**. Others (uat, stg, prd-1, prd-2) will be added as the team collects the files.

There is no `cp-confluent/qa/` — VM CP has no QA environment.

### `<env>/` — CFK CRs (the deployment target)

Each env folder is where the **CFK Custom Resources** live: `Kafka`, `KafkaController` (KRaft mode — dev VM is KRaft, so CFK matches), `SchemaRegistry`, `Connect`, `KafkaRestProxy`, `ControlCenter`. These get applied by the pipeline into the `dah-flink-<env>` namespace, where the CFK operator reconciles them.

Both halves use **lowercase** folder names. PRD splits into `prd-1` (active) and `prd-2` (passive) because the VM PRD is already a cluster-linked active+passive pair.

## Env mapping

| Env folder | OpenShift namespace | VM CP counterpart | Status |
|---|---|---|---|
| `dev` | `dah-flink-dev` | dev VM CP cluster | reference populated; CFK CRs TBD |
| `qa` | `dah-flink-qa` | *(no VM QA)* | CFK-only env; CFK CRs TBD |
| `uat` | `dah-flink-uat` | uat VM CP cluster | reference TBD; CFK CRs TBD |
| `prd` | `dah-flink-prd` | prd VM CP cluster | reference TBD; CFK CRs TBD |
| `dr` | `dah-flink-dr` | DR VM CP cluster | reference TBD; CFK CRs TBD |

`prd` and `dr` live on separate OpenShift clusters (active site and disaster-recovery site respectively); they each have their own variable group (`kafka-openshift-credentials-prd` and `kafka-openshift-credentials-dr`).

## Migration plan reminder

Flink (CMF + Flink Operator) **does not** point at the CFK CP yet. It continues to consume the **VM CP** via `apps/confluent-flink/<env>/{kafka-catalog,kafka-database}.json` throughout the migration. The CFK CP being built here will be cluster-linked to its VM counterpart, and connectors/consumers/producers migrate one by one over the link before Flink is repointed.
