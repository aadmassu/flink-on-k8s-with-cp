# Friday — Kafka Failure Day (break-things)

**Time**: ~90 min
**Diagram**: [`54-kafka-failure-modes.drawio`](54-kafka-failure-modes.drawio)

## Learning objective

> **Recognize the 6 most common Kafka failure modes by symptom alone, in under 2 minutes each.**

## Architecture Discussion (~30 min)

Six failure modes that cover ~85% of Kafka production incidents in production.

### 1. Broker disk full

- **Symptom**: producer gets `NotEnoughReplicasException`; broker logs `No space left on device`
- **Root cause**: retention.ms set too high, or topic growth wasn't anticipated
- **Recovery**: temporarily reduce retention OR add disk OR delete topic (last resort)

### 2. Single broker unresponsive (alive but slow)

- **Symptom**: ISR shrinks; some partitions go below min.insync; some clients hang
- **Root cause**: GC pause, disk I/O saturation, JVM heap pressure
- **Recovery**: identify via metrics, restart broker, address underlying cause (heap, disk)

### 3. Network partition (broker can reach K8s API but not other brokers)

- **Symptom**: brokers each think they're isolated; ISR collapses on all topics
- **Root cause**: NetworkPolicy regression, security group change, pod CIDR routing issue
- **Recovery**: fix the network; brokers re-sync once reachability returns

### 4. Authorization regression

- **Symptom**: clients that worked yesterday get `TOPIC_AUTHORIZATION_FAILED`
- **Root cause**: ACL change, Okta group rename, RBAC binding deleted
- **Recovery**: diff RBAC state vs git; restore the ACL

### 5. Schema-registry unavailable

- **Symptom**: producers using Avro/Protobuf serializer hang or fail; broker is fine
- **Root cause**: SR Pod down, SR backing-store (`_schemas` topic) issue, SR DNS lookup
- **Recovery**: bring SR back; producers retry automatically once SR resolves

### 6. Cluster-link source down

- **Symptom**: destination topic lag growing on linked topics
- **Root cause**: source broker unreachable from destination, mTLS cert expired (9094)
- **Recovery**: check tracker 2.10 (9094 firewall), check cert chain; restart link if needed

## Break-Things Lab Preview (~15 min)

The afternoon lab walks through each failure mode in turn. For each:

1. Engineer triggers the failure
2. Capture the FIRST symptom — what would a customer report?
3. Identify the metric / log line that confirms diagnosis
4. Apply the recovery
5. Confirm metric returns to normal

The Friday deliverable is a one-page "Kafka failure cheat sheet" for the engineer's personal use.

## Q&A

1. Which of the six failure modes is hardest to diagnose without metrics? Why?
2. Which of the six is  the platform MOST likely to encounter in the first month after migration cutover?
3. Which two failure modes look identical from the producer's perspective but require different recovery?
4. If you had time to add ONE alert to the Kafka dashboard in production tomorrow, what would it be and at what threshold?


## Added Enhancement — Incident Response Day

Simulated Incidents:

1. Broker Failure
2. Disk Full Condition
3. Consumer Lag Spike
4. Replication Lag
5. Authentication Failure

Students follow a structured troubleshooting workflow and present findings.
