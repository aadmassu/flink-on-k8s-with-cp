# Week 4 — Confluent for Kubernetes (CFK)

**The most important week.** Everything Weeks 1–3 was building toward this.

**Goal**: every engineer can deploy a full CFK cluster (Kafka + SR + Connect + Control Center), expose it correctly, configure TLS end-to-end, perform a rolling upgrade, and triage failures.

## Daily plan

| Day | Topic | Diagram anchor |
|---|---|---|
| **Monday** | CFK Architecture (CFK Operator → Kafka, Connect, SR, C3, FlinkApplication CRs) | `40-cfk-network.drawio` (existing) |
| **Tuesday** | Custom Resources (Kafka CR → Operator → StatefulSets → Pods — extend Wk 2 Tue's operator pattern) | TBD: `41-cfk-cr-to-pod.drawio` |
| **Wednesday** | **CFK Networking** (internal vs external listeners; Client → Route → Broker Listener → Kafka Broker) — where most customer issues occur | TBD: `42-cfk-listeners.drawio` (or reuse `40-cfk-network.drawio`) |
| **Thursday** | TLS Architecture (Client cert → broker cert → cert rotation) | TBD: `43-cfk-tls.drawio` |
| **Friday** | **Rolling Upgrade — break-things day** (perform actual CFK upgrade on the lab cluster; observe `cluster-ready` flips) | TBD: `44-cfk-rolling-upgrade.drawio` |

## End-of-week deliverable

1. **A working CFK cluster** in your training project: KRaftController + Kafka + SR + Connect + Control Center, all healthy
2. **External listener configured** for the Kafka broker — produce + consume from a client OUTSIDE the cluster
3. **TLS cert rotation walkthrough** — rotate one of the `*-tls` Secrets via cert-manager and confirm no downtime
4. **Rolling upgrade evidence** — `oc get pods -l app=kafka -w` capture across the upgrade
5. **Updated personal troubleshooting checklist v3** — append the CFK-specific failure modes you saw

📝 Day-level discussion + lab content **to be written** before Week 4 Monday. Plan to spend the most prep time on this week.

> **The CFK Network diagram already lives in this repo at `training/diagrams/drawio/40-cfk-network.drawio` (originally drafted for the Rick walk).** Use it as the anchor for Monday + Wednesday's discussions.
