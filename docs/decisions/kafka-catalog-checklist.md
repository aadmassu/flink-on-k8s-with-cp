# KafkaCatalog Configuration Checklist

Decision checklist for configuring the CMF `KafkaCatalog` resource. Review each item before finalizing `apps/confluent-flink/base/kafka-catalog.yaml` and per-env overlays.

Reference: [Confluent docs — Configure catalogs](https://docs.confluent.io/platform/current/flink/configure/catalog.html)

---

## Authentication & Credentials

- [ ] **Schema Registry auth** — Is SR running unauthenticated (PoC) or does it need `basic.auth.user.info` / mTLS? If authenticated, you need a `connectionSecretId` + K8s Secret per environment.
- [ ] **Kafka auth** — Is the Kafka listener unauthenticated (PoC) or does it need SASL/mTLS? Same secret pattern applies.
- [ ] **Per-environment secrets** — If using auth, do you need an `EnvironmentSecretMapping` to map different credentials per env (dev/qa/stg/prd)?

## Database Configuration

- [ ] **Single or multiple databases?** — Currently we define one `default` database. Do you need separate databases (e.g., per team, per use case)?
- [ ] **`alterEnvironments`** — Which environments should be allowed to run `ALTER TABLE` on Flink tables? Probably only `dev`/`qa`, not `stg`/`prd`.

## Schema Registry

- [ ] **TopicNameStrategy only** — CMF assumes subjects are named `{topic}-key` and `{topic}-value`. Does your SR follow this convention? If not, Flink SQL won't discover schemas.
- [ ] **SR endpoint** — Using the local K8s SR (`schemaregistry:8081`) for PoC, but for production will this point to the external VM-based SR?

## Kafka Connectivity

- [ ] **Bootstrap port** — We're using `kafka:9071` (CFK internal listener). Is this the correct listener for Flink workloads, or should it use a different listener/port?
- [ ] **External vs local Kafka** — PoC uses local K8s Kafka. For production, will the KafkaCatalog point to the external VM-based Kafka? If so, the `bootstrap.servers` will need to change to external endpoints.

## Operational

- [ ] **Catalog naming** — We named it `kafka`. Is that the right name, or should it be more specific (e.g., `confluent-platform`, `prod-kafka`)?
- [ ] **Compacted topics** — CMF does not expose compacted topics as tables. Are any of your topics compacted? Those won't be queryable via Flink SQL.
- [ ] **Table lifecycle** — Tables are inferred from topics (can't be created/dropped via Flink SQL). Is that understood by the teams who will use this?

## Not Needed Now (Phase-III)

- [ ] **CP on K8s migration** — When Kafka moves to K8s (Phase-III), the catalog endpoints stay the same (already pointing to K8s services). No catalog changes needed.
