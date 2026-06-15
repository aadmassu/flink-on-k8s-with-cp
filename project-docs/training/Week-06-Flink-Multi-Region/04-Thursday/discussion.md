# Thursday — Multi-Region Clusters (MRC)

**Time**: ~90 min
**Diagram**: [`63-mrc-topology.drawio`](63-mrc-topology.drawio)

## Learning objective

> **What is a Multi-Region Cluster, when does  the platform need one, and what are the operational tradeoffs vs cluster linking?**

## Architecture Discussion (~45 min)

A **Multi-Region Cluster (MRC)** is a single Kafka cluster whose brokers are distributed across multiple regions/datacenters. From clients' perspective it's one cluster; from operations' it's spread across geography.

### Two patterns

**Pattern A — Single MRC across regions**
- One Kafka cluster, brokers in region-A + region-B + region-C
- Partition replicas span regions
- Synchronous replication across regions (acks=all + min.insync.replicas)
- Survives full region failure
- High latency for producers (because of cross-region acks)

**Pattern B — Two clusters with cluster linking**
- Cluster in region-A, cluster in region-B
- Bidirectional or unidirectional cluster link
- Asynchronous replication
- Survives full region failure with manual cutover
- Low latency in each region; eventual consistency across

the platform's current architecture is closer to Pattern B (separate dev/qa/uat/prd plus DR), with cluster linking between them. MRC is a future option for tighter coupling.

### When MRC makes sense

- Application MUST survive a full region failure with < 1 minute RTO
- Strong consistency required (single source of truth)
- Network between regions is fast + reliable enough for sync replication (< 50 ms RTT typical)
- Operational complexity is acceptable

### When cluster linking makes sense

- Region failure tolerance with manual/automated cutover acceptable
- Lower operational burden
- Independent scaling per region
- Per-region governance

### the platform's DR architecture

the platform has dr-1 and dr-2 clusters (in addition to prd-1, prd-2). The DR pattern is:

- prd-1 (primary)
- prd-2 (secondary, also active for split-region traffic)
- dr-1 + dr-2 (in a DR site, cluster-linked from prd)

In a regional failure scenario:
- Traffic fails over to dr-1/dr-2
- Cluster link directionality must flip (or be replaced)
- Application reconfigures bootstrap

### Observer replicas

Cluster-linked replicas can be "observers" — they receive data but don't count toward ISR. Used for:

- Read-only replicas in distant regions
- Lower-cost DR (no ack overhead)
- Migration patterns

### KRaft + regions

KRaftController is the source of truth for cluster metadata. In an MRC, KRaftController quorum (3 or 5 nodes) needs to span regions for region-failure-tolerance. Otherwise the cluster loses its controller when its KRaft region dies.

This is a key MRC design decision: where do controllers live, how many, and which region survives an outage?

### What CFK supports today

CFK can deploy:
- Single-cluster Kafka (default)
- Multi-region via rack-awareness annotations
- Cluster links to other clusters

CFK does NOT natively orchestrate two CFK clusters as one logical "MRC." That's a manual operational pattern using both cluster linking and rack-aware partition placement.

## Diagram Walkthrough (~30 min)

Open `63-mrc-topology.drawio`. Walk:
- Two regions
- Single MRC option: replicas spanning
- Two-cluster + cluster-link option: link directionality
- Where KRaftController quorum sits
- Network paths + cross-region latency

## Failure Scenarios

| Scenario | MRC | Cluster Link |
|---|---|---|
| Region A loses power | replicas in A unavailable; B+C continue | A cluster gone; B cluster keeps serving |
| Cross-region network down | ISR shrinks; min.insync.replicas may block writes | clusters keep working independently; lag accumulates |
| Loss of KRaftController quorum | Cluster unavailable until quorum restored | Independent KRaft per cluster — local impact only |

## Q&A

1. Why is `min.insync.replicas` more dangerous in an MRC than in a single-region cluster?
2. If the platform chose MRC over its current architecture, what would change about cluster linking?
3. What would the OpenShift network and storage prerequisites be for MRC in production?
4. Could Flink jobs span multiple Kafka clusters?


## Added Enhancement — Cluster Linking Operations

Topics:
- Topic replication validation
- Consumer group migration
- Replication lag analysis

Exercise:
Validate mirrored topics and identify replication issues.

Students build a migration validation checklist.
