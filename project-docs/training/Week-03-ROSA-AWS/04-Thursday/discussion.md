# Thursday — VPC, Subnets, Security Groups, NAT

**Time**: ~90 min
**Diagram**: [`33-vpc-network.drawio`](33-vpc-network.drawio) — VPC → public/private subnets → NAT GW → IGW → endpoints; where CFK Pods sit + what they reach

## Learning objective

> **Why can a Pod in `dah-flink-uat` reach `okta.example.com` (Okta) but not `s3.us-east-1.amazonaws.com`?** Because of VPC routing + security groups. Understanding this is the difference between "filing a firewall ticket every week" and "knowing exactly what to ask for."

## Architecture Discussion (~45 min)

ROSA workloads sit inside a VPC. AWS networking has 4 layers; engineers must know each:

### Layer 1 — VPC

The VPC is a regional, isolated virtual network. It has:
- **CIDR block(s)** — the IP address space (e.g. `10.0.0.0/16`)
- A default route table + main NACL — usually overridden

### Layer 2 — Subnets

Subnets carve the VPC CIDR into AZ-pinned slices. ROSA needs 2 flavors:

- **Public subnets** — have a route to the Internet Gateway (IGW); hold the NAT Gateway + LoadBalancers
- **Private subnets** — no route to IGW; hold worker nodes + Pods; egress only via NAT GW

Worker nodes sit in private subnets. **Pods inherit the worker node's network identity** (they're not directly on the VPC; they're on the CNI overlay, but their egress goes through the worker's interface).

### Layer 3 — Routing

Each subnet has an associated route table. Engineers must know:

- `0.0.0.0/0 → NAT-GW-id` in private subnets → general internet egress via NAT
- `0.0.0.0/0 → IGW-id` in public subnets → direct internet
- `10.x.x.x/N → vgw-id` for VPN/Direct Connect — onprem reach
- `<vpc-endpoint-cidr> → vpce-id` — bypasses the public internet for AWS APIs

The presence/absence of a specific route determines whether traffic can leave/arrive.

### Layer 4 — Security Groups + NACLs

- **Security Groups** — stateful, instance-level. Allow rules only (no deny). Engineers care about the worker node SG (for inbound from inside-cluster) and the LoadBalancer SG (for inbound from outside-cluster).
- **NACLs** — stateless, subnet-level. Allow + deny. Usually left at defaults; rarely the cause of an issue.

### VPC endpoints — the "private" AWS API path

For AWS APIs (S3, KMS, ECR), traffic typically goes through the NAT GW + public internet. To keep it inside the VPC,  the platform can use **VPC endpoints**:

- **Gateway endpoints** — S3 + DynamoDB only; free; configured via route table entry
- **Interface endpoints** — most other AWS services; PrivateLink-backed; have an ENI in your subnets; cost per hour

Engineers won't usually create these (Platform does) but must recognize them — they're why `oc exec aws-pod -- aws s3 ls` might work even when the cluster has no NAT GW.

### What CFK needs from networking (preview)

| Destination | How CFK reaches it |
|---|---|
| Okta `okta.example.com:443` | NAT GW → public internet (tracker 2.9) |
| Artifactory `artifactory.example.com:443` | VPN/Direct Connect to on-prem |
| NetApp S3 (Flink checkpoints) | VPN/Direct Connect to on-prem |
| VM CP brokers `kafka.<env>.dah.example.com:9092` | VPN/Direct Connect to on-prem |
| AWS STS for IRSA | NAT GW OR VPC endpoint |
| Inbound user traffic to OCP Routes | Internet Gateway → LB → router pods |
| Inbound TCP/9094 for cluster-link source brokers | Internet Gateway → LB → broker pods (per tracker 2.10 exception) |

Every entry in `OUTBOUND-FIREWALL-REQUESTS.md` maps to a routing decision in this diagram.

## Diagram Walkthrough (~25 min)

Walk the diagram region → VPC → subnets → worker → Pod. At each layer ask:

- *what's the traffic flow leaving the Pod heading to (a) Okta, (b) S3, (c) VM CP brokers?*
- *where would a firewall block this traffic if we wanted to deny it?*

Then trace traffic in the other direction — an external client opening `https://controlcenter.apps.<env>.ocp.example.com`:

```
External client (the User Zone)
   │
   ▼
Internet Gateway
   │
   ▼
NLB / ALB attached to a public subnet
   │
   ▼
HAProxy router pod (Week 1 Wed)
   │
   ▼
Service → backing Pod via CNI overlay
```

## Failure Scenarios

| Symptom | Likely cause |
|---|---|
| Pod can't reach `0.0.0.0/0` | NAT GW unhealthy, or the route table missing `0.0.0.0/0 → nat-gw` |
| Pod can reach NAT but not Okta | DNS or perimeter firewall (enterprise layer) — tracker 2.9 |
| Pod can reach Okta but not S3 | Bucket policy or IRSA — not a network issue |
| External user can't reach a Route | Security Group on LB doesn't allow port 443 from User Zone CIDR — tracker 2.10 |
| Pod can connect but TLS fails | Trust chain — cluster doesn't have  the platform Root CA — `corporate-trust-bundle` ConfigMap (tracker 2.8) |

## Q&A

1. Difference between an Internet Gateway and a NAT Gateway?
2. Why do worker nodes sit in private subnets?
3. If a NAT GW costs $0.045/hr × N AZs, what's the cluster's monthly NAT bill at 3 AZs?
4. When would VPC endpoints save cost vs NAT GW?
5. In production, what's the path from a Pod in `dah-flink-uat` to a VM CP broker on `kafka.uat.dah.example.com:9094`?


## Added Enhancement — Cluster Upgrades & Day-2 Operations

Topics:
- Worker node replacement
- Pod disruption impacts
- Stateful workload considerations
- Kafka/Flink maintenance planning
