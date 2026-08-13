# Thursday — VPC, Subnets, Security Groups, NAT

**Time**: ~90 min

![VPC Network — Pod egress paths + how external clients reach the cluster](images/VPC%20Network.png)

## Learning objective

> **Why can a Pod in `dah-flink-uat` reach `okta.example.com` but not `s3.us-east-1.amazonaws.com`?** Because of VPC routing + security groups + which VPC endpoints Platform has attached. Understanding this is the difference between "filing a firewall ticket every week" and "knowing exactly what to ask for."

## Architecture Discussion (~45 min)

ROSA workloads sit inside a VPC. AWS networking has 4 layers; engineers must know each. The diagram above overlays five color-coded traffic flows onto the same topology — refer back to it as each layer is walked.

### Layer 1 — VPC

The VPC is a regional, isolated virtual network. On the diagram: the outer green rectangle labeled `VPC (10.0.0.0/16)`. Engineers must know:

- **CIDR block(s)** — the IP address space (this cluster: `10.0.0.0/16`)
- **Internet Gateway (IGW)** — attached to the VPC (top of diagram); the only public-internet on-ramp
- A default route table + main NACL — usually overridden per-subnet

### Layer 2 — Subnets

Subnets carve the VPC CIDR into AZ-pinned slices. ROSA needs 2 flavors, both visible on the diagram:

- **Public subnet** `10.0.1.0/24` (AZ-a) — has a route to the IGW; holds the NLB/ALB and the NAT Gateway
- **Private subnets** `10.0.2.0/24`, `10.0.3.0/24`, `10.0.4.0/24` (multi-AZ) — no route to IGW; hold worker nodes, VPC endpoint ENIs, and the VGW attachment

Worker nodes sit in private subnets. **Pods live on the CNI overlay** (e.g. `10.128.x.x`, called out under the Pod box on the diagram) — they are not directly on the VPC CIDR. Egress leaves through the worker's ENI and is SNAT'd to the worker's private IP.

### Layer 3 — Routing

Each subnet has an associated route table. On the diagram, the private Route Table box lists all four entry classes engineers must know:

- `0.0.0.0/0 → NAT-GW-id` in private subnets → generic internet egress via NAT (used for Okta)
- `0.0.0.0/0 → IGW-id` in the public route table → direct internet (for NAT GW itself and the LB)
- `10.x.x.x/N → vgw-id` → on-prem reach via VPN / Direct Connect (used for Artifactory, VM CP brokers, NetApp S3)
- `<vpc-endpoint-prefix> → vpce-id` → bypasses the public internet for AWS APIs (S3, STS, ECR, KMS)

The presence/absence of a specific entry determines whether traffic can leave/arrive. Most "Pod can't reach X" tickets are one of these four rows being missing.

### Layer 4 — Security Groups + NACLs

- **Security Groups** — stateful, instance-level, allow-only. On the diagram, the worker SG shows the exact rules that matter: `Egress 6443 to masters` (kubelet), `Ingress 9092/9094 from VPN CIDR` (cluster-link source brokers dialing in — tracker 2.10), `Egress: ALL` (outbound via NAT / VPCE). The NLB/ALB SG allows only `443 from trusted client CIDRs`.
- **NACLs** — stateless, subnet-level, allow + deny. Usually left at defaults; rarely the cause of an issue but should be checked before escalating.

### VPC endpoints — the "private" AWS API path

For AWS APIs (S3, KMS, ECR, STS), traffic would otherwise go through the NAT GW + public internet. To keep it inside the VPC, Platform attaches **VPC endpoints** — shown as their own box on the diagram:

- **Gateway endpoints** — S3 + DynamoDB only; free; configured via route-table entry (`<s3-pl> → vpce-id`)
- **Interface endpoints** — most other AWS services; PrivateLink-backed; have an ENI in your private subnet; cost per hour. STS + ECR + optional KMS are the ones this cluster runs.

Engineers won't create these (Platform does) but must recognize them — they're why `aws s3 ls` might work even when the NAT GW is broken.

### What CFK needs from networking

Each CFK destination maps to exactly one colored flow on the diagram — the color tells you which route-table entry carries it.

| Destination | Flow (diagram color) | Route class |
|---|---|---|
| Inbound HTTPS to OCP Routes | green (Client access) | IGW → NLB/ALB (public subnet) |
| Inbound TCP/9094 for cluster-link source brokers | green | IGW → NLB → worker SG (ingress from VPN CIDR) — tracker 2.10 |
| Okta `okta.example.com:443` | orange via NAT | private `0.0.0.0/0 → NAT GW` |
| AWS STS for IRSA | orange via VPCE | private `<sts-prefix> → vpce-id` |
| ECR image pulls | orange via VPCE | private `<ecr-prefix> → vpce-id` |
| S3 (AWS-side buckets) | orange via Gateway Endpoint | private `<s3-pl> → vpce-id` |
| Artifactory `artifactory.example.com` | purple (on-prem) | private `<onprem-CIDR> → VGW` |
| VM CP brokers `kafka.<env>.dah.example.com:9092/9094` | purple | private `<onprem-CIDR> → VGW` |
| NetApp S3 (Flink checkpoints) | purple | private `<onprem-CIDR> → VGW` |

Every entry in `OUTBOUND-FIREWALL-REQUESTS.md` maps to one of these rows.

## Diagram Walkthrough (~25 min)

Walk the diagram region → VPC → subnet → worker → Pod. At each layer ask:

- *what's the traffic flow leaving the Pod heading to (a) Okta, (b) S3, (c) VM CP brokers?*
- *where would a firewall block this traffic if we wanted to deny it?*

Then trace an external client opening `https://controlcenter.apps.<env>.ocp.example.com`:

```
External client (User Zone / VM CP)
   │  HTTPS 443
   ▼
Internet Gateway
   │
   ▼
NLB / ALB in public subnet (Elastic IP, listens :443)
   │
   ▼
OpenShift Route → HAProxy router Pod (Week 1 Wed)
   │
   ▼
Service → backing Pod via CNI overlay
```

## Failure Scenarios

| Symptom | Likely cause |
|---|---|
| Pod can't reach `0.0.0.0/0` | NAT GW unhealthy, or private route table missing `0.0.0.0/0 → NAT GW` |
| Pod can reach NAT but not Okta | DNS or perimeter firewall (enterprise layer) — tracker 2.9 |
| STS calls fail for IRSA but S3 works | STS Interface Endpoint not attached; SDK fell back to NAT, enterprise egress may block it |
| Pod can reach Okta but not an S3 bucket | Bucket policy or IRSA — not a network issue |
| External user can't reach a Route | NLB/ALB SG doesn't allow 443 from User Zone CIDR — tracker 2.10 |
| Cluster-link source broker can't reach cluster | Worker SG ingress `9092/9094 from VPN CIDR` missing — tracker 2.10 |
| VM CP broker unreachable from Pod | Private route table missing `<onprem-CIDR> → VGW`, or VGW/DX tunnel down |
| Pod can connect but TLS fails | Trust chain — `corporate-trust-bundle` ConfigMap — tracker 2.8 |

## Q&A

1. Difference between an Internet Gateway (top of diagram) and a NAT Gateway (public subnet)?
2. Why do worker nodes sit in private subnets?
3. Why does the diagram show Pods on `10.128.x.x` while the VPC is `10.0.0.0/16`? Where does the SNAT happen?
4. If a NAT GW costs $0.045/hr × N AZs, what's the monthly NAT bill at 3 AZs? Which flows would VPC endpoints remove from that bill?
5. When would VPC endpoints save cost vs NAT GW?
6. In production, what's the path from a Pod in `dah-flink-uat` to a VM CP broker on `kafka.uat.dah.example.com:9094`?
7. For cluster-link source brokers dialing into the ROSA cluster on TCP/9094, which arrow on the diagram carries that traffic, and which SGs must permit it?


## Added Enhancement — Cluster Upgrades & Day-2 Operations

Topics:
- Worker node replacement
- Pod disruption impacts
- Stateful workload considerations
- Kafka/Flink maintenance planning
