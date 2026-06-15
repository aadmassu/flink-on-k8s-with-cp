# Monday — Topic Lifecycle: KafkaTopic CR + Replication

**Time**: ~90 min
**Diagram**: [`50-topic-lifecycle.drawio`](50-topic-lifecycle.drawio)

## Learning objective

> **What happens between `oc apply -f topic.yaml` and the producer's first successful publish?** Trace topic creation, partition placement, leader election, ISR, replication.

## Architecture Discussion (~45 min)

A topic is the unit of organization in Kafka. CFK exposes it as a `KafkaTopic` Custom Resource so it can be managed declaratively.

### KafkaTopic CR shape

```yaml
apiVersion: platform.confluent.io/v1beta1
kind: KafkaTopic
metadata:
  name: orders
spec:
  replicas: 3
  partitionCount: 6
  configs:
    cleanup.policy: delete
    retention.ms: "604800000"  # 7 days
    min.insync.replicas: "2"
  kafkaClusterRef:
    name: kafka
```

The CFK operator translates this into an admin client call to the Kafka cluster's `CreateTopics` API. The cluster — specifically the KRaftController — assigns partitions to brokers and elects leaders.

### Partitions, replicas, ISR — the three concepts

- **Partition** — one ordered log. Producer hashes the key to pick a partition. Consumers see partition order.
- **Replica** — N copies of each partition. One is leader, the others are followers.
- **ISR (in-sync replicas)** — subset of replicas that are currently caught up (within `replica.lag.time.max.ms`).

When `min.insync.replicas=2` and `acks=all`, a producer's write is acknowledged only after 2 replicas have it in their log. This is the durability guarantee.

### Leader election

KRaftController is the single source of truth for partition leadership. When a broker dies:

1. The controller detects via heartbeat timeout
2. Picks a new leader from the surviving ISR
3. Notifies all brokers
4. Producers refetch metadata, redirect writes to the new leader

The duration of this gap (~1-5s typically) is the partition's unavailability window during a broker death.

### How replication works on the wire

- Each follower has a fetcher thread that pulls from the leader's log
- Follower keeps a high-water-mark = the offset all ISR have acked
- Consumer can only read up to the high-water-mark — no dirty reads

### site-specific topic patterns

- **Flink checkpoint state topics** — names like `flink-checkpoints-<jobname>`, retention forever, log compaction
- **Connect internal topics** — `connect-offsets`, `connect-status`, `connect-configs`. Compaction enabled.
- **Cluster-link replicated topics** — created via cluster-link config rather than KafkaTopic CR; CFK doesn't manage them directly
- **Topics created by Flink jobs at runtime** — Flink uses Kafka admin client; if the producer's principal has `CREATE` on the cluster, they appear without a KafkaTopic CR. Engineers + audit teams need to know this.

### Two ways topics exist in production

1. **CR-managed** — KafkaTopic CR in git, applied via ArgoCD or Azure DevOps
2. **Application-created** — runtime by Connect / Flink / app code

CR-managed is auditable. Application-created is faster but harder to govern. enterprise policy is "production must be CR-managed."

## Diagram Walkthrough (~30 min)

Open `50-topic-lifecycle.drawio`. Trace `oc apply -f orders.yaml`:
- KafkaTopic CR stored in etcd
- Operator reads, calls `CreateTopics` against Kafka
- KRaftController assigns partitions, elects leaders
- Followers begin fetching from leaders
- Operator polls `DescribeTopics`, writes `status.partitionCount` etc.

## Failure Scenarios

| Symptom | Where to look |
|---|---|
| `KafkaTopic` CR applied, no topic in Kafka | operator logs; Kafka admin auth |
| `min.insync.replicas=2` but topic shows ISR=1 | broker down or replication lag |
| Topic shows `Leader: -1` | no in-sync replica; partition unavailable |
| Producer sees `NOT_LEADER_FOR_PARTITION` repeatedly | client metadata stale, force refresh |

## Q&A

1. If `replicas=3` and you set `min.insync.replicas=3`, what happens when one broker is down?
2. Who tells the producer where the leader of a partition is?
3. If you delete a KafkaTopic CR, does Kafka delete the topic? (Hint: depends on `delete.topic.enable` and finalizers)
4. How would you migrate a 200-topic estate from "runtime-created" to "CR-managed" without downtime?


## Added Enhancement — Topic Lifecycle Management

Topics:
- Topic creation
- Partition expansion
- Replication factor considerations
- Retention policies

Failure Scenario:
A topic reaches retention limits and consumers cannot replay historical data.

Students determine root cause and recovery options.
