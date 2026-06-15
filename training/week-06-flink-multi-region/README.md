# Week 6 — Apache Flink + Multi-Region Architecture

**Goal**: deploy a Flink job on the Week-4 CFK cluster, configure checkpointing to S3, design a multi-region cluster-link topology, and run a disaster-recovery exercise where the primary region is lost.

This week mirrors the actual FCB architecture (cluster-link from VM CP → CFK in dah-flink-prd; future MRC topology with prd / dr).

## Daily plan

| Day | Topic | Diagram anchor |
|---|---|---|
| **Monday** | Flink Architecture (JobManager + TaskManagers + state) | `60-flink-network.drawio` (existing) |
| **Tuesday** | Checkpointing (State → Checkpoint → Object Storage) | TBD: `61-flink-checkpoints.drawio` |
| **Wednesday** | Cluster Linking (Cluster A → Cluster Link → Cluster B) | TBD: `62-cluster-link.drawio` |
| **Thursday** | **MRC Architecture** — probably the most valuable diagram of the entire course | TBD: `63-mrc-topology.drawio` |
| **Friday** | **DR Exercise — "Region A lost"** | TBD: `64-dr-failover.drawio` |

## End-of-week deliverable

1. **A working Flink job** on the Week-4 CFK cluster, with checkpoints persisting to NetApp S3 (or similar)
2. **A cluster-link** configured between two CFK clusters (or simulated — one cluster + topic mirror to a different namespace)
3. **MRC architecture diagram** annotated for FCB's actual prd ↔ dr topology
4. **DR runbook** — step-by-step what an engineer does when "Region A is lost":
   1. Validate cluster link health
   2. Validate mirrored topics are caught up
   3. Validate consumer groups offsets are mirrored
   4. Recover Flink jobs (savepoint → start in Region B)
   5. Restore traffic to Region B
5. **Final personal troubleshooting checklist v5** — append Flink + multi-region failure modes
6. **End-to-end demonstration** — record a 10-min screencast (or live demo) of the full pipeline: producer in Region A → CFK Kafka → Flink job → consumer; then fail over to Region B and show the same pipeline keeps working

📝 Day-level discussion + lab content **to be written** before Week 6 Monday.

> **The MRC topology diagram (Thursday) is THE deliverable from this entire bootcamp.** It should be the artifact engineers reference when they're paged about a regional outage at FCB. Spend the most prep time on it.

> **The Flink Network diagram already lives at `training/diagrams/drawio/60-flink-network.drawio`** (originally drafted for the Rick walk). Use it as the anchor for Monday.
