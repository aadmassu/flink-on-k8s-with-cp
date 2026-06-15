# Wednesday — Cluster Linking (VM CP → CFK migration)

**Time**: ~90 min
**Diagram**: [`62-cluster-link.drawio`](62-cluster-link.drawio)

## Learning objective

> **What is a Confluent cluster link, how does  the platform use it for the VM-CP → CFK migration, and what are the per-topic + per-env cutover steps?**

## Architecture Discussion (~45 min)

Cluster linking is Confluent Platform's official "replicate topics between clusters" mechanism. It's NOT MirrorMaker — it's a broker-level feature where the destination cluster's brokers pull from the source cluster's brokers.

### How it works

- A **cluster link** is a configuration object on the destination cluster
- It points at the source cluster's bootstrap + auth
- For each linked topic, the destination cluster creates a "mirror topic"
- Mirror topic is read-only on the destination
- Offset positions are preserved (consumer can switch source → dest without offset translation)

### The Migration architecture

Currently:
- VM Confluent Platform clusters in dev/uat/stg/prd-1/prd-2 carry all live traffic
- New CFK clusters in dah-flink-dev (and corresponding envs) are being stood up
- The goal: cutover each env, env-for-env

Per-env cutover steps:
1. Stand up CFK cluster (Weeks 4-5 work)
2. Configure cluster link from CFK → VM (source: VM, destination: CFK)
3. Cluster link replicates all topics + offsets to CFK
4. Verify CFK has caught up
5. Pause producers on VM; wait for consumers to drain
6. Repoint producers to CFK
7. Repoint consumers to CFK
8. Decommission VM cluster (later, after stabilization period)

### The 9094 port + mTLS

Cluster linking from VM → CFK requires:
- A broker port on CFK that VM brokers can connect to
- VM brokers use mTLS (not OAuth)
- This is the **9094 listener** (Week 4 Wednesday, tracker 2.10)
- A firewall rule from VM CP estate → CFK 9094

If the firewall isn't open, the cluster link configuration succeeds but no data flows.

### The cluster-link CR (CFK-managed)

```yaml
apiVersion: platform.confluent.io/v1beta1
kind: ClusterLink
metadata:
  name: vm-to-cfk-dev
spec:
  destinationKafkaRest:
    endpoint: https://kafka-rest.dah-flink-dev.svc.cluster.local:8082
  sourceKafkaCluster:
    bootstrapEndpoint: vm-kafka-dev.example.com:9094
    authentication:
      type: mtls
    tls:
      enabled: true
      secretRef: vm-link-mtls
  mirrorTopics:
    - name: orders
    - name: payments
```

CFK operator creates and manages the link on the destination cluster.

### What can go wrong

- Source unreachable (firewall, tracker 2.10)
- mTLS cert mismatch (truststores)
- Topic auto-creation policies different (mirror tops require explicit config)
- Schema Registry not federated — consumers may break if SR endpoints differ
- Offset divergence — if mirror lags behind, consumers cutting over see "future" data they hadn't seen yet (unlikely but possible)

### After cutover — Flink

Once a Kafka cluster is migrated:
- Flink catalogs need to be repointed (CMF API)
- Existing Flink jobs need savepoint + restart against new bootstrap
- Schema Registry references must be updated if SR is also moving

This is why Flink migration usually follows, not parallels, Kafka migration in an environment.

## Diagram Walkthrough (~30 min)

Open `62-cluster-link.drawio`. Walk:
- Source cluster (VM CP)
- Network path: VM brokers → firewall → 9094 LB → CFK brokers
- Cluster link config on CFK
- Mirror topic on CFK
- Consumers cutting over

## Failure Scenarios

| Symptom | Where to look |
|---|---|
| Cluster link "CONNECTED" but no topics | mirrorTopics empty; topic filter mismatch |
| Cluster link "ERROR — Authentication failed" | mTLS cert chain or truststore |
| Cluster link "ERROR — Connection refused" | firewall rule (tracker 2.10) |
| Mirror topic lag growing | source partition rate > network/destination capacity |

## Q&A

1. Why does the platform use cluster linking instead of MirrorMaker 2?
2. What is "offset preservation" and why does it matter for consumer cutover?
3. If a Flink job is reading from a mirror topic, can it cut over to the source without a savepoint?
4. Walk through the order of operations for cutting over one production environment. Where can you fail safely?


## Added Enhancement — Watermark and Event Time Failures

Topics:
- Event time processing
- Watermarks
- Late arriving events

Scenario:
Pipeline produces incorrect aggregations.

Students determine whether watermark configuration is the cause.
