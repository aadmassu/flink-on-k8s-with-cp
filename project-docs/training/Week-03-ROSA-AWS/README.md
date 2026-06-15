# Week 3 — ROSA + AWS Integration

**Goal**: understand the ROSA architecture, the IAM/STS/OIDC chain that lets pods talk to AWS APIs, the VPC + security group layer that CFK depends on, and the upgrade machinery.

## Daily plan

| Day | Topic | Diagram | Lab |
|---|---|---|---|
| **[Monday](01-Monday/discussion.md)** | ROSA Architecture (AWS → VPC → ROSA → OpenShift → CFK) | `30-rosa-architecture.drawio` | [`lab.md`](01-Monday/lab.md) |
| **[Tuesday](02-Tuesday/discussion.md)** | **OIDC flow** (User → Okta → OAuth → OpenShift bearer token) | `31-oidc-flow.drawio` | [`lab.md`](02-Tuesday/lab.md) |
| **[Wednesday](03-Wednesday/discussion.md)** | **STS / IRSA flow** (Pod → SA → IAM Role → AWS API; no long-lived creds) | `32-sts-irsa-flow.drawio` | [`lab.md`](03-Wednesday/lab.md) |
| **[Thursday](04-Thursday/discussion.md)** | VPC + Subnets + Security Groups + NAT + VPC Endpoints | `33-vpc-network.drawio` | [`lab.md`](04-Thursday/lab.md) |
| **[Friday](05-Friday/discussion.md)** | Cluster upgrades + scaling (NOT break-things this week — controlled dry-run) | `34-rosa-upgrade.drawio` | [`lab.md`](05-Friday/lab.md) |

## End-of-week deliverable — `week-03-runbook.md`

1. **ROSA cluster summary** — control-plane version, worker count, machine pool config, networking (VPC, subnets, SGs), STS roles attached
2. **OIDC sign-in trace** — browser network log of one `oc login --web`
3. **One STS / IRSA pod** — your Pod successfully calling an AWS API via SA-attached IAM Role
4. **VPC connectivity ladder** — `nc -zv` outputs for Okta, Artifactory, S3, VM CP brokers, the OCP Routes' inbound LB
5. **An upgrade dry-run plan** — copy-paste commands for upgrading dev ROSA to the next minor (don't run)
6. **Personal troubleshooting checklist v3** — append AWS-side patterns from this week

✅ Fully written — ready to run.

> The three diagrams ROSA Architecture / OIDC Flow / STS Flow explain ~80% of future AWS-side authentication issues. They are the centerpieces of the week.

## End-of-week review

After Friday, before moving on:

- [`06-Review/knowledge-check.md`](06-Review/knowledge-check.md) — 10 self-quiz concept questions
- [`06-Review/skill-check.md`](06-Review/skill-check.md) — hands-on tasks that produce runbook artifacts
- [`06-Review/qa.md`](06-Review/qa.md) — 20 Q&A reinforcing the week's key concepts
