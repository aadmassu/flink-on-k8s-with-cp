# Week 4 — CFK on OpenShift

**Goal**: understand how the CFK operator turns Custom Resources into running Confluent Platform components, where the listener / TLS / upgrade pitfalls are, and how to diagnose a sick CFK cluster from `status.conditions` first.

## Daily plan

| Day | Topic | Diagram | Lab |
|---|---|---|---|
| **[Monday](01-Monday/discussion.md)** | CFK Architecture (the 5 Confluent components + how CFK glues them) | `40-cfk-network.drawio` | [`lab.md`](01-Monday/lab.md) |
| **[Tuesday](02-Tuesday/discussion.md)** | CR → Pod: reconcile step-by-step | `41-cfk-cr-to-pod.drawio` | [`lab.md`](02-Tuesday/lab.md) |
| **[Wednesday](03-Wednesday/discussion.md)** | Listeners: internal vs external; bilingual broker | `42-cfk-listeners.drawio` | [`lab.md`](03-Wednesday/lab.md) |
| **[Thursday](04-Thursday/discussion.md)** | TLS architecture (cert-manager + Keyfactor + CFK consumption) | `43-cfk-tls.drawio` | [`lab.md`](04-Thursday/lab.md) |
| **[Friday](05-Friday/discussion.md)** | **Break-things day** — rolling upgrade failures | `44-cfk-rolling-upgrade.drawio` | [`lab.md`](05-Friday/lab.md) |

## End-of-week deliverable — `week-04-runbook.md`

1. **CR inventory** — every CFK CR in your training project + its purpose
2. **Listener map** — which port has which auth, with the site-specific rationale (trackers 2.9, 2.10)
3. **Cert chain trace** — from broker on the wire → Secret → Certificate → ClusterIssuer → Keyfactor
4. **Four broken-upgrade scenarios** with diagnostic + recovery
5. **Personal "CFK won't start" checklist** — ordered top-down

✅ Fully written — ready to run.

> Week 5 begins Kafka-specific operations (topics, consumer groups, OAuth, observability). Week 4's habits — read `status.conditions` first — carry forward.

## End-of-week review

After Friday, before moving on:

- [`06-Review/knowledge-check.md`](06-Review/knowledge-check.md) — 10 self-quiz concept questions
- [`06-Review/skill-check.md`](06-Review/skill-check.md) — hands-on tasks that produce runbook artifacts
- [`06-Review/qa.md`](06-Review/qa.md) — 20 Q&A reinforcing the week's key concepts
