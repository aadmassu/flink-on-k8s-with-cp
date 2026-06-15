# Week 3 — ROSA + AWS Integration

**Goal**: stand up and run a ROSA cluster on AWS; understand the IAM/STS/OIDC chain that makes pods talk to AWS APIs; design the VPC + security groups that CFK + Flink need.

## Daily plan

| Day | Topic | Diagram anchor |
|---|---|---|
| **Monday** | ROSA Architecture (AWS → VPC → ROSA cluster → OpenShift → CFK) | TBD: `30-rosa-architecture.drawio` |
| **Tuesday** | **OIDC flow** (User → Okta → OAuth token → OpenShift) | TBD: `31-oidc-flow.drawio` |
| **Wednesday** | **STS / IRSA flow** (Pod → ServiceAccount → IAM Role → AWS API) | TBD: `32-sts-irsa-flow.drawio` |
| **Thursday** | VPC + Security Groups (where CFK pods sit, what they reach) | TBD: `33-vpc-network.drawio` |
| **Friday** | Cluster upgrades + scaling (controlled, low-risk; not "break-things" this week) | TBD: `34-rosa-upgrade.drawio` |

## End-of-week deliverable

1. **ROSA cluster summary** — your existing dev ROSA cluster's: control-plane version, worker count, machine pool config, networking (VPC, subnets, security groups), STS roles attached
2. **One OIDC sign-in trace** — login to the OpenShift Console via Okta and document every redirect (use browser dev tools)
3. **One STS / IRSA pod** — a Pod in your training project that successfully calls an AWS API using its ServiceAccount-attached IAM Role (e.g. `aws s3 ls`)
4. **VPC diagram** — annotate the existing dev VPC diagram with: where CFK Pods sit, where their LB sits, what they need to reach (Artifactory, NetApp S3, Okta, SQL Server)
5. **An upgrade dry-run plan** — copy-paste-ready commands for upgrading dev ROSA to the next minor (don't actually run)

📝 Day-level discussion + lab content **to be written** before Week 3 Monday.

> **Note**: the three diagrams ROSA Architecture / OIDC Flow / STS Flow explain ~80% of future AWS-side authentication issues. Prioritize them.
