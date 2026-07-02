# Thursday — VPC, Subnets, Security Groups, NAT

**Time**: ~90 min
**Diagram**: [`images/VPC Network.png`](images/VPC%20Network.png) — Pod egress paths + how external clients reach the cluster (VPC 10.0.0.0/16 → public/private subnets → NAT GW / IGW / VPC endpoints / VGW; CFK Pods on CNI overlay reaching Okta, AWS S3/STS/ECR, and on-prem)

## Learning objective

> **Why can a Pod in `dah-flink-uat` reach `okta.example.com` but not `s3.us-east-1.amazonaws.com`?** Because of VPC routing + security groups + which VPC endpoints Platform has attached. Understanding this is the difference between "filing a firewall ticket every week" and "knowing exactly what to ask for."

## Architecture Discussion (~45 min)

ROSA workloads sit inside a VPC. The `VPC Network.png` diagram overlays five distinct traffic flows onto one topology. Walk them in order.

### The topology (top-left of the diagram)

- **VPC** `10.0.0.0/16` — regional, isolated virtual network
- **Public subnet** `10.0.1.0/24` (AZ-a) — has a route to the Internet Gateway; holds the NLB/ALB and the NAT Gateway
- **Private subnets** `10.0.2.0/24`, `10.0.3.0/24`, `10.0.4.0/24` (multi-AZ) — no route to IGW; hold worker nodes, VPC endpoint ENIs, and the on-prem VGW attachment
- **Worker node (EC2)** — sits in a private subnet, runs CFK/app Pods
- **Pod** — lives on the CNI overlay (e.g. `10.128.x.x`), **not** directly on the VPC CIDR; egress leaves through the worker node's ENI and is then SNAT'd

### Flow 1 — Client Access (Inbound), green arrows

External clients (User Zone / VM CP hosts) hit an HTTPS URL like `controlcenter.apps.<env>.ocp.example.com`. The path is:

```
External client
   │  HTTPS 443
   ▼
Internet Gateway (attached to VPC)
   ▼
NLB / ALB in public subnet 10.0.1.0/24 (Elastic IP, listens :443)
   ▼
Kubernetes Service / OpenShift Route
   ▼
HAProxy router Pod → backing Pod via CNI overlay
```

Two things to notice on the diagram:
- The NLB/ALB is the **only** thing in the public subnet that terminates client traffic
- The Pod itself has no public IP — the diagram calls this out explicitly ("No direct internet access" under the Pod box)

### Flow 2 — Pod Egress to Internet, black arrow

Pods that need generic internet egress (package pulls, non-AWS SaaS, etc.):

```
Pod (10.128.x.x)
   ▼  worker node ENI in private subnet
   ▼  Route Table (Private):  0.0.0.0/0 → NAT GW
NAT Gateway (Elastic IP, in public subnet 10.0.1.0/24)
   ▼  Route Table (Public):   0.0.0.0/0 → IGW
Internet Gateway → Internet
```

The `0.0.0.0/0 → NAT GW` entry in the private route table is what makes this work. Remove it and Pods lose internet.

### Flow 3 — External Service Access, orange arrows

Two orange flows in the diagram, both dispatched by the private route table but taking different paths:

- **Okta** (`okta.example.com` — OIDC authorization + JWT issuance) → follows Flow 2 (Pod → NAT GW → IGW) because Okta is a public SaaS endpoint
- **AWS Services** (`S3` / `STS` / `ECR`) → **preferred** path is VPC Endpoints, not NAT:
  - **S3 Gateway Endpoint** — free, wired via a `pl-xxxx → vpce-xxxx` prefix-list route in the private route table
  - **STS Interface Endpoint** — PrivateLink ENI in the private subnet; required for IRSA if you don't want STS traffic egressing via NAT
  - **ECR Interface Endpoint** — same pattern; image pulls stay inside the VPC
  - **KMS Interface Endpoint** — optional, add if any workload calls KMS

Engineers don't create these (Platform does), but must recognize them. That's how `aws s3 ls` can work even if the NAT GW is broken.

### Flow 4 — On-prem Access, purple arrows

Anything hosted in the data center — Artifactory (Docker repo), VM CP brokers, NetApp S3 (Flink checkpoints), DNS/SQL — is reached through the **Virtual Gateway (VGW)** or **AWS Direct Connect**:

```
Pod
   ▼  Route Table (Private):  10.x.x.x/N → VGW
Virtual Gateway (IPsec tunnel or Direct Connect private link)
   ▼
On-prem data center
```

Two things to notice:
- The purple flow is bidirectional — for cluster-link, on-prem VM CP brokers dial into the cluster over the same path (in reverse) via a Route/LB
- The route is by **on-prem CIDR**, not by hostname; DNS still has to resolve, which is why on-prem DNS servers are part of the tracker list

### Flow 5 — Security Model (blue-dashed control plane)

Two enforcement points, layered:

- **Security Groups** — stateful, instance-level, allow-only. On the diagram:
  - Worker SG: `Egress 6443 to masters` (kubelet ↔ control plane), `Ingress 9092/9094 from VPN CIDR` (cluster-link source brokers dialing in — tracker 2.10), `Egress: ALL` (outbound via NAT / VPCE)
  - NLB/ALB SG: `Ingress 443 from trusted client CIDRs` only
- **Route Tables** — separate from SGs but often confused with them. The private route table is where the 4 route classes coexist:
  - `0.0.0.0/0 → NAT GW`
  - `10.x.x.x/N → VGW` (on-prem)
  - `local routes → local` (intra-VPC)
  - `<vpc-endpoint-prefix> → VPCE`

**NACLs** (subnet-level, stateless, allow+deny) are on the diagram implicitly — Platform usually leaves them at defaults; they're rarely the cause of an issue but should be checked before escalating.

### What CFK needs from networking (which flow maps to which)

| Destination | Flow on the diagram | Route class |
|---|---|---|
| Inbound HTTPS to OCP Routes (`controlcenter.apps.<env>...`) | 1 (green) | IGW → NLB/ALB SG → Route |
| Inbound TCP/9094 for cluster-link source brokers | 1 (green, extended) | IGW → NLB → worker SG ingress from VPN CIDR (tracker 2.10) |
| Okta `okta.example.com:443` | 3 (orange, via NAT) | private `0.0.0.0/0 → NAT GW` |
| AWS STS for IRSA | 3 (orange, via VPCE preferred) | private `<sts-prefix> → vpce-id` |
| ECR image pulls | 3 (orange, via VPCE preferred) | private `<ecr-prefix> → vpce-id` |
| S3 (any AWS-side buckets) | 3 (orange, via Gateway Endpoint) | private `<s3-pl> → vpce-id` |
| Artifactory `artifactory.example.com` | 4 (purple) | private `<onprem-CIDR> → VGW` |
| VM CP brokers `kafka.<env>.dah.example.com:9092/9094` | 4 (purple) | private `<onprem-CIDR> → VGW` |
| NetApp S3 (Flink checkpoints) | 4 (purple) | private `<onprem-CIDR> → VGW` |

Every entry in `OUTBOUND-FIREWALL-REQUESTS.md` maps to one of these five flows.

## Diagram Walkthrough (~25 min)

Trace three journeys on the diagram in order. For each, name the exact route-table entry and SG rule that permits it:

1. **Outbound — Pod → Okta.** Expect: private RT `0.0.0.0/0 → NAT GW` → public RT `0.0.0.0/0 → IGW` → orange arrow to `okta.example.com`. Worker SG egress `ALL`.
2. **Outbound — Pod → S3.** Expect: private RT `<s3-prefix-list> → vpce-id` → S3 Gateway Endpoint. **No NAT hop.** If Platform hasn't attached the S3 gateway endpoint, this silently falls back to Flow 2 (NAT) — and the workload works but the traffic is unnecessarily on the public internet.
3. **Inbound — External client → Control Center Route.** Expect: black arrow to IGW → green arrow to NLB/ALB (SG allows 443 from client CIDR) → Route → Pod.

Then invert each: "where on the diagram would a firewall break this?" That's the vocabulary they need for firewall tickets.

## Failure Scenarios

| Symptom | What to check on the diagram |
|---|---|
| Pod can't reach `0.0.0.0/0` | NAT GW unhealthy, or private route table missing `0.0.0.0/0 → NAT GW` (Flow 2) |
| Pod can reach NAT but not Okta | Enterprise perimeter/DNS — tracker 2.9. The Flow 3 orange arrow is being dropped past the IGW |
| STS calls fail for IRSA but S3 works | STS Interface Endpoint not attached — SDK falls back to NAT and enterprise egress may block it |
| Pod can reach Okta but not an S3 bucket | Not a network issue — bucket policy or IRSA. Flow 3 to S3 is up; the auth layer is denying |
| External user can't reach a Route | NLB/ALB SG doesn't allow 443 from User Zone CIDR (Flow 1 / tracker 2.10) |
| Cluster-link source broker can't reach cluster | Worker SG ingress `9092/9094 from VPN CIDR` missing (Flow 1 extended / tracker 2.10) |
| VM CP broker unreachable from Pod | Private route table missing `<onprem-CIDR> → VGW`, or VGW/DX tunnel down (Flow 4) |
| TLS handshake fails post-connect | Trust chain — `corporate-trust-bundle` ConfigMap (tracker 2.8), unrelated to the diagram |

## Key takeaway (from the diagram)

Internet traffic from Pods leaves via **NAT Gateway** (generic egress) or **VPC Endpoints** (AWS services, preferred). External clients reach the cluster via **NLB/ALB** in the public subnet. On-prem connectivity rides **VPN (IPsec) or AWS Direct Connect** through the VGW. **Security Groups + Route Tables** are the two enforcement dials.

Operational preferences the diagram hints at:
- Prefer **VPC Endpoints** for AWS services — no NAT cost, no exit to the public internet
- Use **PrivateLink / Private Endpoints for SaaS** where the vendor supports it (Okta does; if enabled, Flow 3 for Okta becomes orange-via-VPCE instead of orange-via-NAT)
- Treat on-prem CIDRs as the source of truth in the private route table; a missing entry is the single most common cause of "Pod can reach the internet but not <VM CP host>"

## Q&A

1. What's the difference between the Internet Gateway (top of the diagram) and the NAT Gateway (public subnet)? Why do you need both?
2. Why does the diagram show Pods on `10.128.x.x` while the VPC is `10.0.0.0/16`? Where does the SNAT happen?
3. On Flow 3, why is the AWS-services arrow drawn to VPC Endpoints even though it would also work via NAT GW?
4. At $0.045/hr per NAT GW × 3 AZs, what's the monthly NAT bill? Which of the 5 flows would VPC endpoints eliminate from that bill?
5. Trace the exact path (route-table entry + SG rule) from a Pod in `dah-flink-uat` to a VM CP broker on `kafka.uat.dah.example.com:9094`.
6. A colleague says "the S3 endpoint is broken, workloads are still working though." What does the diagram tell you is actually happening, and why is it a cost/security problem even though nothing is failing?
7. For cluster-link source brokers dialing into the ROSA cluster on TCP/9094, which two arrows on the diagram carry that traffic, and which SGs must permit it?

## Added Enhancement — Cluster Upgrades & Day-2 Operations

Topics (not on the VPC diagram, but adjacent):
- Worker node replacement — what happens to Pod IPs on the CNI overlay when a node is cordoned/drained
- Pod disruption impacts — PDBs, and how the LB (Flow 1) reacts when a Route's backing Pod moves
- Stateful workload considerations — PVs stay behind, Pods move; how this interacts with Kafka/Flink
- Kafka/Flink maintenance planning — draining brokers vs. controllers, checkpoint impact on Flink
