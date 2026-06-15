# Week 5 — Skill Check

## Task 1 — Topic lifecycle (Mon)

1. Create a KafkaTopic CR for `review-week5-orders` (RF=3, partitions=6, min.insync.replicas=2)
2. Produce 1000 messages with `acks=all`
3. Kill the leader of partition 0; capture the leader election timeline
4. Reset back to 3-broker steady state

**Verifies**: Topic + replication + leadership (Mon)

## Task 2 — Consumer group operations (Tue)

1. Start a 3-consumer group; produce 10000 messages
2. Capture `kafka-consumer-groups --describe` — partition assignment + lag
3. Kill one consumer; capture rebalance timeline
4. Reset the group's offset to `earliest`; observe re-consumption

**Verifies**: Consumer groups + rebalance + offset reset (Tue)

## Task 3 — OAuth client (Wed)

Using the corporate Okta credentials provided by the instructor:

1. Fetch an Okta JWT manually via curl
2. Decode + inspect claims (`iss`, `aud`, `sub`, `groups`, `exp`)
3. Configure a Kafka producer with the OAuth client config
4. Produce one successful message + capture the broker log line showing the principal extraction

**Verifies**: OAuth end-to-end (Wed)

## Task 4 — Add Prometheus + Grafana panel (Thu)

1. Identify the JMX exporter port on a broker Pod
2. Curl + grep for `kafka_server_replica_manager_under_replicated_partitions`
3. Build a 5-panel ad-hoc dashboard: under-replicated, request handler idle %, bytes-in/sec, consumer lag, disk usage
4. Export the JSON

**Verifies**: Observability (Thu)

## Task 5 — Three induced failures (Fri)

Run 3 of the 6 failure modes from Wk 5 Fri lab. For each: cause + symptom + diagnostic + recovery + time-to-recovery.

**Verifies**: Failure-mode pattern recognition (Fri)

## Submission

`deliverables/<you>/week05/` — together these become your **Kafka Security & Monitoring Guide** + **Kafka Operations Runbook** (final-deliverable items 3 + 4).
