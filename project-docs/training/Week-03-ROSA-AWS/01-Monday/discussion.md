# Monday — ROSA Architecture

**Time**: ~90 min
**Diagram**: [`30-rosa-architecture.drawio`](30-rosa-architecture.drawio) — AWS → VPC → ROSA → OpenShift → CFK

## Learning objective

> **What is ROSA actually?** It's not a fork of OpenShift; it's not "OpenShift on EC2." It's a Red Hat–managed OpenShift cluster running on AWS-owned VPC infrastructure, jointly supported by RH + AWS, with a specific control-plane / worker split that differs from self-managed OCP.

## Architecture Discussion (~40 min)

ROSA = "Red Hat OpenShift Service on AWS". Two architecture flavors:

- **ROSA Classic** — control plane runs on dedicated EC2 instances in your VPC; you pay for them. Older shape; DEV/QA were likely this until ROSA HCP rolled out.
- **ROSA HCP (Hosted Control Plane)** — control plane runs in Red Hat's account (`hostedcontrolplanes` AWS infrastructure); you pay only for worker nodes. Faster cluster creation, cheaper, and where most new deployments go.

Either way, from the engineer's perspective the OpenShift API + UI feels identical. The difference matters when:
- **Troubleshooting control plane** — on HCP you can't `ssh` to the masters; tickets go to Red Hat support
- **Networking** — HCP control plane traffic crosses the AWS account boundary via PrivateLink; understanding this is essential for firewall design
- **Cost model** — HCP separates control-plane subscription from worker EC2 spend

### The layered stack — what runs where

Walking the diagram top-down:

1. **AWS account + region** — outermost boundary. ROSA cluster pinned to one region; multi-region needs a second ROSA cluster + replication (Week 6).
2. **VPC** — private network for the cluster. Has public + private subnets across multiple AZs.
3. **ROSA control plane** — kube-apiserver, etcd, scheduler, controllers (Week 1 Monday's heptagons). On HCP, hosted in RH's AWS account, reachable via PrivateLink endpoint in your VPC.
4. **ROSA worker nodes** — EC2 instances in your private subnets; run kubelet + CRI-O + kube-proxy + your Pods (Week 1 Monday's bottom half).
5. **OpenShift on top** — Routes, Projects, SCC, the Operator framework, the integrated registry (Friday Week 1's diagram).
6. **Your workloads** — CFK, Flink, your apps.

### The three AWS-specific integration points engineers must understand

These are what makes ROSA "ROSA" vs vanilla OCP, and they're the topics of Tue/Wed/Thu:

- **OIDC** (Tuesday) — how users sign in. ROSA federates with an external identity provider (Okta in production). The control plane trusts tokens issued by that IdP.
- **STS / IRSA** (Wednesday) — how Pods authenticate to AWS APIs. Pod's ServiceAccount → annotated with an IAM Role ARN → AWS STS exchanges the SA token for AWS credentials. No long-lived secrets stored anywhere.
- **VPC + security groups** (Thursday) — what the cluster can reach + what can reach it. NAT gateways, security groups, route tables.

### Read-only ROSA inventory commands (run these in the lab)

```bash
# Check the cluster's ROSA shape — there's a per-cluster ConfigMap describing it
oc get clusterversion
oc get nodes -o wide
oc get machineconfigpools
oc get clusteroperators                                 # 30+ operators; this is the cluster itself
oc adm top nodes                                        # what's running where
```

For the control plane on ROSA HCP, you won't see master Pods listed because the control plane is in RH's account. That's a clear signal you're on HCP vs Classic.

## Diagram Walkthrough (~30 min)

Walk the layered diagram top-down. At each layer, ask the team:

- *"If this layer fails, what does the engineer see?"*
- *"Who owns this layer — engineer, platform team, RH support, or AWS?"*

Example responses to walk through:

- VPC subnets full → new worker nodes can't get IPs → cluster scale-up fails — **platform team**
- ROSA control plane upgrades to next minor → some APIs deprecated → workloads break — **RH-initiated, platform-orchestrated, engineer-impacted**
- kube-apiserver returns 5xx → cluster-wide outage → all ops paused — **RH support**
- Worker node EC2 fails health check → kubelet stops reporting → pods on that node go NotReady → reschedule — **platform team / autoscaler**

## Failure Scenarios

| Symptom | Likely cause | Who fixes |
|---|---|---|
| `oc login` returns `connection refused` | VPC routing broken; PrivateLink endpoint unhealthy |  the platform Platform |
| New Pods stuck Pending: `0/X nodes available: Insufficient cpu` | Workers full; need scale-up | Platform / autoscaler |
| Worker node disappears from `oc get nodes` | EC2 instance terminated; autoscaler replacing | Platform |
| Cluster operator `Degraded` in `oc get co` | Internal RH-managed component issue | RH support ticket |
| Pod can't pull from ECR | IRSA misconfigured (Wednesday's topic) | Engineer |

## Q&A

1. What's the difference between ROSA Classic and ROSA HCP?
2. Where does the etcd cluster live in ROSA HCP? Can you `ssh` to it?
3. If RH does a control-plane upgrade, who orchestrates the worker upgrade?
4. Why does ROSA need a NAT gateway in the VPC?
5. In production, who would you contact for: (a) a worker-side networking issue, (b) etcd disk pressure, (c) an SCC misconfiguration?


## Added Enhancement — ROSA vs Self-Managed OpenShift

Focus on operational differences:
- AWS managed control plane
- Shared responsibility model
- Cluster upgrades
- Support boundaries (Red Hat, AWS, Customer)

Whiteboard: Who owns what during an outage?
