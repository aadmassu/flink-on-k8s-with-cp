# Week 5 — Knowledge Check

## Kafka operations + security + observability (10 concept questions)

1. KafkaTopic CR vs runtime-created topic — when is each acceptable in production?
2. With `replicas=3`, `min.insync.replicas=2`, `acks=all` — explain what happens when one broker dies.
3. Consumer group rebalance: who triggers it, what pauses, and how long?
4. Cooperative vs eager rebalance protocol — what changes for the consumer?
5. Walk the Kafka OAuth flow: from client startup through producer.send() to broker accepting.
6. JWT validation steps at the broker — list all 5.
7. ACLs vs Confluent RBAC — what each covers, and when the platform uses each.
8. Name the 5 broker metrics that catch ~80% of incidents.
9. mTLS for Kafka — when do you use it vs OAuth in production? (cluster-link case + others)
10. Walk the 6-failure-mode catalog from Friday — each by symptom + first diagnostic.

## Self-scoring

- 8-10: ready to support Kafka on call solo
- 5-7: re-read OAuth + observability (Wed + Thu); these are where Week 5 differs most from previous Kafka knowledge
- < 5: revisit Week 5 fully
