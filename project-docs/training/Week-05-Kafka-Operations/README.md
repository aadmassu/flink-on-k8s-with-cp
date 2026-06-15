# Week 5 — Kafka Operations

**Goal**: every engineer can manage Kafka topics + consumer groups, authenticate clients via OAuth, read the observability stack, and recognize the six most common failure modes by symptom.

## Daily plan

| Day | Topic | Diagram | Lab |
|---|---|---|---|
| **[Monday](01-Monday/discussion.md)** | KafkaTopic CR + partition/replication/ISR | `50-topic-lifecycle.drawio` | [`lab.md`](01-Monday/lab.md) |
| **[Tuesday](02-Tuesday/discussion.md)** | Consumer Groups + Rebalance | `51-consumer-group.drawio` | [`lab.md`](02-Tuesday/lab.md) |
| **[Wednesday](03-Wednesday/discussion.md)** | OAuth / OIDC end-to-end (Okta → JWT → broker) | `52-kafka-oauth.drawio` | [`lab.md`](03-Wednesday/lab.md) |
| **[Thursday](04-Thursday/discussion.md)** | Observability (Prometheus + Grafana + Splunk + Dynatrace) | `53-kafka-observability.drawio` | [`lab.md`](04-Thursday/lab.md) |
| **[Friday](05-Friday/discussion.md)** | **Break-things day** — 6 failure modes | `54-kafka-failure-modes.drawio` | [`lab.md`](05-Friday/lab.md) |

## End-of-week deliverable — `week-05-runbook.md`

1. **Topic-management cheat sheet** — create / modify / delete via CR + via admin client
2. **Consumer-group toolkit** — describe / lag / reset-offsets / list
3. **OAuth client config snippet** — works against the corporate Okta
4. **5-panel Grafana board** — sketched with PromQL queries
5. **6-failure-modes cheat sheet** — symptom → diagnostic → recovery
6. **Personal troubleshooting checklist v4** — append Kafka data-plane patterns

✅ Fully written — ready to run.

> Week 6 brings Flink, cluster linking, and MRC — the workloads that depend on everything Weeks 1-5 covered.

## End-of-week review

After Friday, before moving on:

- [`06-Review/knowledge-check.md`](06-Review/knowledge-check.md) — 10 self-quiz concept questions
- [`06-Review/skill-check.md`](06-Review/skill-check.md) — hands-on tasks that produce runbook artifacts
- [`06-Review/qa.md`](06-Review/qa.md) — 20 Q&A reinforcing the week's key concepts
