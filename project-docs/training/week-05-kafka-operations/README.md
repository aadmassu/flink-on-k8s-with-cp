# Week 5 — Kafka Operations, Security & Observability

**Goal**: operate the Kafka cluster you built in Week 4 — manage topics, monitor consumer lag, configure OAuth + mTLS, build dashboards, and on Friday, recover from intentional broker/disk/ISR/auth failures.

## Daily plan

| Day | Topic | Diagram anchor |
|---|---|---|
| **Monday** | Topic Lifecycle (create, partition strategy, replication, retention, compaction) | TBD: `50-topic-lifecycle.drawio` |
| **Tuesday** | Consumer Groups (offset, lag, rebalancing, sticky vs cooperative assignors) | TBD: `51-consumer-group.drawio` |
| **Wednesday** | **OAuth / OIDC for Kafka clients** (Application → Okta → token → Kafka broker) — highly relevant to the FCB environment | TBD: `52-kafka-oauth.drawio` |
| **Thursday** | Observability (Kafka → JMX Exporter → Prometheus → Grafana; consumer lag dashboards) | TBD: `53-kafka-observability.drawio` |
| **Friday** | **Failure Day — break broker / disk / ISR / authentication; investigate and recover** | TBD: `54-kafka-failure-modes.drawio` |

## End-of-week deliverable

1. **Topic + consumer-group ops walkthrough** — create a topic, produce + consume, observe lag, rebalance a consumer group
2. **OAuth listener configured** on the Week-4 Kafka — produce + consume with an Okta-issued token
3. **Consumer lag Grafana dashboard** — JSON export committed
4. **The Failure Day debrief**: for each of the four intentional breaks (broker / disk / ISR / authentication), describe the symptom + root-cause investigation + recovery
5. **Updated personal troubleshooting checklist v4** — append Kafka-side failure modes

📝 Day-level discussion + lab content **to be written** before Week 5 Monday.

> **Friday's failure scenarios are the centerpiece of this week.** Plan ~6 hours for the lab — engineers should NOT all attempt the breaks at the same time on a shared cluster.
