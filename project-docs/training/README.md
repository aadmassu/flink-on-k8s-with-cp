# CFK on OpenShift — 6-Week Engineer Bootcamp

Practical curriculum that takes an engineer from "what's a Pod?" to "I can implement, support, and troubleshoot CFK + Flink on OpenShift / ROSA in production."

The source curriculum overview is preserved in [`curriculum-source.md`](curriculum-source.md). This folder breaks that plan into per-day morning + afternoon sessions, with diagrams + labs + troubleshooting exercises.

## Curriculum philosophy

**Teach by operational layer, not by product.** Most CFK deployment failures aren't Kafka problems — they're K8s, networking, storage, RBAC, or operator-pattern problems that surface as Kafka symptoms. The curriculum follows the layers in the order they fail:

1. **Week 1** — Kubernetes / OpenShift foundations
2. **Week 2** — OpenShift platform operations
3. **Week 3** — ROSA / AWS integration
4. **Week 4** — Confluent for Kubernetes (CFK)
5. **Week 5** — Kafka operations + security
6. **Week 6** — Apache Flink + multi-region

**CFK support is 80% troubleshooting and 20% deployment.** Every day ends with a break-things exercise so engineers see failure modes before they see them in production.

## Daily rhythm

Each day folder is self-contained — morning discussion, afternoon lab, and the day's diagram all live together:

```
Morning  (~90 min)              Afternoon (~3–4 hours, self-paced)
─────────────────────           ──────────────────────────────────
discussion.md                   lab.md
├── Architecture                ├── Hands-on Lab
├── Diagram Walkthrough         ├── Troubleshooting Exercise
├── Failure Scenarios           └── Deliverable Submission
└── Q&A
```

The diagram referenced in `discussion.md` lives in the same day folder as a `.drawio` file (numbered to match the rough course order — `40-cfk-network.drawio`, `41-cfk-cr-to-pod.drawio`, etc.).

## Folder layout

```
training/
├── README.md                                       ← you are here
├── curriculum-source.md                            ← extracted from the original 6-week plan .docx
├── Week-01-OpenShift-Foundations/
│   ├── README.md                                   ← week intro + outcomes + daily index
│   ├── 01-Monday/
│   │   ├── discussion.md                           ← morning content
│   │   ├── lab.md                                  ← afternoon lab
│   │   └── 01-k8s-architecture.drawio              ← the day's diagram (one or more)
│   ├── 02-Tuesday/    (same shape)
│   ├── 03-Wednesday/  (same shape)
│   ├── 04-Thursday/   (same shape)
│   └── 05-Friday/     (same shape — Friday = break-things day)
├── Week-02-OpenShift-Operations/  (same shape)
├── Week-03-ROSA-AWS/              (same shape)
├── Week-04-CFK/                   (same shape — the most important week)
├── Week-05-Kafka-Operations/      (same shape)
├── Week-06-Flink-Multi-Region/    (same shape)
│
└── deliverables/                                   ← engineers submit week-by-week outputs here
    └── README.md                                   ← what to submit, naming convention
```

## Daily curriculum index (Mon–Fri × 6 weeks)

| Day | Wk 1 — Foundations | Wk 2 — Operations | Wk 3 — ROSA + AWS | Wk 4 — CFK | Wk 5 — Kafka Ops | Wk 6 — Flink + MRC |
|---|---|---|---|---|---|---|
| **Mon** | K8s Architecture | RBAC | ROSA Architecture | CFK Architecture | Topic Lifecycle | Flink Architecture |
| **Tue** | Pods · Deployments · StatefulSets | Operators | OIDC Flow | Custom Resources (Kafka, SR, Connect, C3, FlinkApplication) | Consumer Groups | Checkpointing |
| **Wed** | Services + Routes | Monitoring (Prometheus + Grafana) | STS / IRSA | CFK Networking (internal vs external listeners) | OAuth / OIDC for Kafka clients | Cluster Linking |
| **Thu** | Storage (PVC + PV + StorageClass) | GitOps (ArgoCD) | VPC + Security Groups | TLS architecture | Observability (JMX + Prometheus + Grafana) | MRC architecture |
| **Fri** | **Troubleshooting Workflow — break things** | **Quotas + Limits — break via exhaustion** | Cluster upgrades + scaling | **Rolling Upgrade — break-things** | **Failure Day — broker/disk/ISR/auth** | **Disaster Recovery — Region A lost** |

Every Friday = break-things day. Engineers spend the morning on a planned discussion topic and the afternoon investigating intentionally-broken systems.

## Deliverables at the end of the bootcamp

By Friday of Week 6, each engineer submits (under `deliverables/<engineer-name>/`):

1. OpenShift Troubleshooting Runbook
2. CFK Deployment Guide
3. Kafka Operations Guide
4. OAuth/OIDC Troubleshooting Guide
5. Monitoring Dashboard Package (JSON exports + how to import)
6. Multi-Region DR Runbook
7. Final Architecture Diagram Set (drawio originals + PNG exports)

See `deliverables/README.md` for the submission convention.

## Prerequisites — engineer setup before Week 1 Monday

- `oc` CLI installed; able to log into the dev OpenShift cluster
- VS Code with the drawio plugin (or drawio.io in a browser)
- Git Bash or WSL (for the lab shell commands)
- Read access to this repo + the matching `runbook/LESSONS_LEARNED.md` for site-specific context

## Status of the curriculum

- **Week 1** — fully written; ready to run from Monday
- **Week 2** — fully written; ready to run
- **Week 3** — fully written; ready to run
- **Week 4** — fully written; ready to run (the most important week)
- **Week 5** — fully written; ready to run
- **Week 6** — fully written; ready to run (DR drill as final exercise)

Each week ends with a `06-Review/` folder containing a knowledge check, a skill check, and 20 Q&A.

## Alignment with the original 6-week plan

The bootcamp matches the original plan (`6_Week_Learning plan_OpenShift_ROSA_MRC_CP_Flink.docx`) at the day-level topic grain. A few intentional emphasis shifts vs. the original — each gap is surfaced in the corresponding week's `06-Review/qa.md` so engineers still master the missing material:

| Week | Original-plan topic | What this curriculum did | Where the gap is filled |
|---|---|---|---|
| 1 | ConfigMaps and Secrets (Wed alongside Services) | Touched lightly across days | Wk 1 Q&A Q10 + Q11; skill-check Task 3 |
| 2 | Security Context Constraints (Tue alongside Operators) | Dropped from dedicated treatment | Wk 2 Q&A Q4; skill-check Task 2 |
| 5 | mTLS + ACLs + Confluent RBAC (Wed alongside OAuth) | Centered on OAuth | Wk 5 Q&A Q11 + Q12 |
| 6 | Flink SQL + Watermarks (Tue) | Centered on checkpoints/savepoints | Wk 6 Q&A Q7 + Q8 |
| 6 | MirrorMaker 2 (Thu) | Centered on cluster linking | Wk 6 Q&A Q10 + Q11 |

If any of these gaps need a full day's treatment instead of Q&A coverage, that's an instructor judgment call for the cohort.
