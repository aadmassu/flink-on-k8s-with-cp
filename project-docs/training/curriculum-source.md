# Curriculum Source — 6-Week Roadmap

OpenShift, ROSA, Confluent Platform, CFK, Apache Flink, and Multi-Region Streaming.

This is the **roadmap document** — the source-of-truth plan that the bootcamp was built against. Day-by-day content lives in `Week-NN-<Topic>/0N-<Day>/` folders; this file gives the bird's-eye view.

---

## Executive Summary

This 6-week learning plan develops practical operational proficiency in OpenShift, ROSA, Confluent Platform, Confluent for Kubernetes (CFK), Apache Flink, and Multi-Region Kafka architectures. The curriculum emphasizes hands-on deployment, troubleshooting, security, observability, and disaster recovery scenarios commonly encountered in enterprise production environments.

The primary objective is not merely to deploy platforms, but to build the skills necessary to **operate, support, troubleshoot, and recover** a production-grade streaming platform running on ROSA / OpenShift.

---

## 6-Week Learning Plan

| Week | Focus Area | Topics | Hands-On Activities | Deliverables |
|---|---|---|---|---|
| **1** | OpenShift Fundamentals | Kubernetes architecture · OpenShift architecture · Pods, Deployments, StatefulSets · Services and Routes · ConfigMaps and Secrets · Persistent Volumes and PVCs · OpenShift Console · `oc` CLI | Deploy sample applications · Create services and routes · Configure persistent storage · Troubleshoot failed pods · Perform rolling updates | Application deployment walkthrough · OpenShift object lifecycle doc · Basic troubleshooting guide |
| **2** | OpenShift Administration & Platform Operations | RBAC · Service Accounts · Security Context Constraints (SCC) · Operators · Prometheus & Grafana · Logging · OpenShift GitOps (ArgoCD) · Resource Quotas and Limits | Install Operators · Configure RBAC · Deploy applications via GitOps · Create monitoring dashboards · Configure alerts | GitOps deployment pipeline · RBAC implementation · Monitoring dashboard · Operational checklist |
| **3** | ROSA Administration & AWS Integration | ROSA architecture · AWS Networking · IAM · STS · OIDC · VPC Design · Security Groups · Cluster Upgrades · Cluster Scaling · Logging and Monitoring | Deploy ROSA Cluster · Configure AWS IAM Integration · Perform Cluster Upgrade · Configure OIDC Authentication · Review Security Controls | ROSA deployment guide · IAM/OIDC documentation · Operations runbook · Upgrade procedure |
| **4** | Confluent Platform & CFK | Confluent Platform architecture · KRaft architecture · Confluent for Kubernetes (CFK) · CFK Custom Resources · Kafka Cluster Deployment · Schema Registry · Connect · Control Center · REST Proxy · Component Networking · TLS Architecture | Deploy Kafka with CFK · Deploy Schema Registry · Deploy Connect · Configure TLS · Configure External Access · Perform Rolling Upgrade | CFK deployment guide · Platform architecture diagram · External access design · Component lifecycle doc |
| **5** | Kafka Operations, Security & Observability | Kafka Administration · Topics · Partitions · Replication · Consumer Groups · Broker Operations · Capacity Planning · Security (OAuth/OIDC, mTLS, ACLs) · Confluent RBAC · Service Accounts · Observability (JMX, Prometheus, Grafana) · Alerting · Log Analysis · Troubleshooting (broker failures, ISR, replication lag, consumer lag, storage) | Create RBAC Roles · Configure OAuth · Deploy Monitoring · Investigate Failure Scenarios · Build Grafana Dashboards | Security configuration guide · Monitoring dashboard package · Kafka operational runbook · Troubleshooting guide |
| **6** | Flink & Multi-Region Streaming Platform | Apache Flink · Flink architecture · Flink SQL · Stateful Processing · Checkpoints · Savepoints · Watermarks · High Availability · Flink on Kubernetes · Multi-Region Architecture · Cluster Linking · MirrorMaker 2 overview · Consumer Group Migration · Active-Active vs Active-Passive · DR Strategy · RTO/RPO · Regional Failover | Deploy Flink Jobs · Build Streaming Pipelines · Configure Cluster Linking · Validate Replication · Execute Failover Testing · Recover Flink Jobs | Multi-region architecture diagram · Flink deployment guide · DR runbook · End-to-end demonstration · Lessons learned doc |

---

## Weekly Breakdown — Daily Topic Matrix

| Day | Week 1 — Foundations | Week 2 — Operations | Week 3 — ROSA + AWS | Week 4 — CFK | Week 5 — Kafka Ops | Week 6 — Flink + MRC |
|---|---|---|---|---|---|---|
| **Mon** | K8s Architecture · OpenShift Architecture | RBAC · ServiceAccounts | ROSA Architecture · AWS Networking | Confluent Platform Architecture · KRaft Architecture | Kafka Administration · Topics & Partitions | Apache Flink · Flink Architecture |
| **Tue** | Pods, Deployments, StatefulSets | SCC · Operators | IAM · STS · OIDC | CFK · CFK Custom Resources | Replication · Consumer Groups · Broker Operations | Flink SQL · Stateful Processing |
| **Wed** | Services and Routes · ConfigMaps and Secrets | Prometheus & Grafana · Logging | VPC Design · Security Groups | Kafka Cluster Deployment · Schema Registry | OAuth/OIDC · mTLS · ACLs · Confluent RBAC | Checkpoints · Savepoints · Watermarks |
| **Thu** | Persistent Volumes and PVCs · OpenShift Console · `oc` CLI | OpenShift GitOps (ArgoCD) · Resource Quotas and Limits | Cluster Upgrades · Cluster Scaling | Connect · Control Center · REST Proxy · TLS Architecture | Observability · JMX Metrics · Prometheus Exporters · Grafana Dashboards | Multi-Region Architecture · Cluster Linking · MirrorMaker 2 Overview |
| **Fri** | Deploy sample apps · Troubleshoot failed pods · Perform rolling updates | Deploy via GitOps · Configure alerts | Deploy ROSA Cluster · Configure OIDC Authentication | Deploy Kafka with CFK · Configure External Access · Perform Rolling Upgrade | Investigate Failure Scenarios · Build Grafana Dashboards | Validate Replication · Execute Failover Testing · Recover Flink Jobs |

Every Friday is a **break-things / failure-investigation** day. Engineers spend the morning on the planned discussion topic and the afternoon investigating intentionally-broken systems.

---

## Study Allocation

| Technology Area | Allocation |
|---|---|
| OpenShift Administration & Operations | **30%** |
| ROSA on AWS | 15% |
| Confluent Platform & CFK | **20%** |
| Kafka Operations & Security | **20%** |
| Flink & Multi-Region Architecture | 15% |

---

## Expected Outcomes — After 6 Weeks

| Skill Area | Outcome |
|---|---|
| OpenShift | Deploy, troubleshoot, secure, and operate applications |
| ROSA | Provision and manage production-grade OpenShift clusters on AWS |
| CFK | Deploy and manage Confluent Platform components on Kubernetes |
| Kafka Operations | Operate, secure, monitor, and troubleshoot Kafka clusters |
| Flink | Deploy and support production Flink applications |
| Multi-Region Streaming | Design and support resilient multi-region Kafka architectures |
| Platform Engineering | Operate a production-grade ROSA / OpenShift streaming platform |

---

## Final Deliverables (end of Week 6)

Each engineer submits the following, signed off by the instructor:

1. **OpenShift Operations Runbook**
2. **ROSA Administration Guide**
3. **CFK Deployment Guide**
4. **Kafka Security & Monitoring Guide**
5. **Flink Operations Runbook**
6. **Multi-Region Architecture & DR Runbook**
7. **End-to-End Streaming Platform Demonstration** (a live failure-and-recovery scenario)

See [`deliverables/README.md`](deliverables/README.md) for the submission convention and naming rules.

---

## Where the day-by-day content lives

This roadmap maps 1:1 to the bootcamp folder structure:

| Week | Folder |
|---|---|
| Week 1 — OpenShift Fundamentals | [`Week-01-OpenShift-Foundations/`](Week-01-OpenShift-Foundations/) |
| Week 2 — OpenShift Operations | [`Week-02-OpenShift-Operations/`](Week-02-OpenShift-Operations/) |
| Week 3 — ROSA + AWS | [`Week-03-ROSA-AWS/`](Week-03-ROSA-AWS/) |
| Week 4 — CFK | [`Week-04-CFK/`](Week-04-CFK/) |
| Week 5 — Kafka Operations | [`Week-05-Kafka-Operations/`](Week-05-Kafka-Operations/) |
| Week 6 — Flink + Multi-Region | [`Week-06-Flink-Multi-Region/`](Week-06-Flink-Multi-Region/) |

Inside each week, day folders follow the convention `0N-<Day>/` (Monday through Friday), plus `06-Review/` with knowledge check, skill check, and 20 Q&A. Each day folder contains:

- `discussion.md` — morning architecture + diagram walkthrough (~90 min)
- `lab.md` — afternoon hands-on lab (~3-4 hours)
- One or more `.drawio` files — the day's diagrams

Bigger-picture documents at the training root:

- [`README.md`](README.md) — bootcamp orientation, daily rhythm, gap analysis vs this roadmap
- [`PROGRAM-OVERVIEW.txt`](PROGRAM-OVERVIEW.txt) — Training Program v2.0 philosophy summary
