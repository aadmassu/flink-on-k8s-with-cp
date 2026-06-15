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

Each day has the same shape — same content lives in two places to keep the morning discussion focused and the afternoon lab independent:

```
Morning  (~90 min)              Afternoon (~3–4 hours, self-paced)
─────────────────────           ──────────────────────────────────
discussion.md                   labs/weekNN/<day>.md
├── Architecture                ├── Hands-on Lab
├── Diagram Walkthrough         ├── Troubleshooting Exercise
├── Failure Scenarios           └── Deliverable Submission
└── Q&A
```

The diagram referenced in `discussion.md` lives once in `diagrams/drawio/` (numbered to match the rough course order). The lab file in `labs/weekNN/<day>.md` is the engineer's afternoon work.

## Folder layout

```
training/
├── README.md                                       ← you are here
├── curriculum-source.md                            ← extracted from the original 6-week plan .docx
├── week-01-openshift-foundations/
│   ├── README.md                                   ← week intro + outcomes + daily index
│   ├── monday/    discussion.md                    ← morning content per day
│   ├── tuesday/   discussion.md
│   ├── wednesday/ discussion.md
│   ├── thursday/  discussion.md
│   └── friday/    discussion.md                    ← Friday = break-things day
├── week-02-openshift-operations/  (same shape)
├── week-03-rosa-aws/              (same shape)
├── week-04-cfk/                   (same shape — the most important week)
├── week-05-kafka-operations/      (same shape)
├── week-06-flink-multi-region/    (same shape)
│
├── diagrams/                                       ← central diagram library; one source per concept
│   ├── drawio/                                     ← canonical .drawio source files (numbered ~ course order)
│   ├── png/                                        ← engineers add PNG exports as they reference them
│   └── notes/                                      ← per-diagram explanation .md for self-study
│
├── labs/                                           ← afternoon labs, one per day per week
│   ├── week01/  monday.md  tuesday.md  ...
│   ├── week02/  ...
│   ├── week03/  ...
│   ├── week04/  ...
│   ├── week05/  ...
│   └── week06/  ...
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
- Read access to this repo + the matching `runbook/LESSONS_LEARNED.md` for FCB-specific context

## Status of the curriculum

- **Week 1** — fully written; ready to run from Monday
- **Week 2** — fully written; ready to run
- **Weeks 3–6** — week-level READMEs in place with the daily topics; per-day discussion + lab content fleshed out as each week approaches
