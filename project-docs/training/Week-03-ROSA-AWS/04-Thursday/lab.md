# Week 3 Thursday — Lab: Trace VPC Routing from a Pod

**Time**: ~3 hours

## Hands-on Lab — connectivity ladder from a Pod

```bash
oc project <you>-training

# 1. Deploy a busybox Pod (Week 1 Friday's trick — busybox in a known-good image)
cat <<EOF | oc apply -f -
apiVersion: v1
kind: Pod
metadata: {name: net-debug}
spec:
  containers:
    - name: c
      image: nicolaka/netshoot:v0.13
      command: ["sleep","3600"]
EOF

oc wait --for=condition=Ready pod/net-debug --timeout=60s

# 2. Test each layer of the connectivity ladder
oc exec net-debug -- nslookup okta.example.com           # DNS resolves?
oc exec net-debug -- nc -zv okta.example.com 443         # TCP/443 reachable? (might fail — tracker 2.9)
oc exec net-debug -- nc -zv artifactory.example.com 443           # via VPN/Direct Connect
oc exec net-debug -- nc -zv s3.amazonaws.com 443                 # via NAT or endpoint
oc exec net-debug -- nc -zv kafka.dev.dah.example.com 9092        # VM CP — should reach
oc exec net-debug -- traceroute -n -m 5 8.8.8.8                  # external internet path (NAT GW)
```

For each destination, document: **DNS resolved?** + **TCP connected?** + **what path the traceroute showed?** (you'll see the NAT GW or VPC endpoint as a hop)

## Hands-on Lab Part 2 — read the VPC config (requires AWS access)

If you have AWS CLI access to the the production account:

```bash
# Identify the VPC the cluster is in
CLUSTER_VPC=$(aws ec2 describe-vpcs --filters "Name=tag:kubernetes.io/cluster/<cluster-name>,Values=owned" --query 'Vpcs[0].VpcId' --output text)
echo "VPC: $CLUSTER_VPC"

# List its subnets
aws ec2 describe-subnets --filters "Name=vpc-id,Values=$CLUSTER_VPC" \
  --query 'Subnets[*].[SubnetId,CidrBlock,AvailabilityZone,Tags[?Key==`Name`].Value|[0]]' --output table

# Route tables
aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$CLUSTER_VPC" \
  --query 'RouteTables[*].[RouteTableId,Routes[].DestinationCidrBlock]' --output table

# Security groups on worker nodes
aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$CLUSTER_VPC" "Name=tag:kubernetes.io/cluster/<cluster-name>,Values=owned" \
  --query 'SecurityGroups[*].[GroupId,GroupName,Description]' --output table
```

(If you don't have AWS CLI access, capture screenshots of the AWS Console VPC view and paste into your deliverable.)

## Troubleshooting Exercise — predict + confirm what's blocking each known production destination

Using the discussion's "what CFK needs from networking" table, walk through each  the platform destination + predict which AWS-side mechanism allows it:

| Destination | NAT? VPC endpoint? VPN? IGW? |
|---|---|
| `okta.example.com:443` | NAT GW — pending firewall (tracker 2.9) |
| `artifactory.example.com:443` | VPN to on-prem |
| `s3.us-east-1.amazonaws.com` | NAT GW OR Gateway endpoint |
| `kafka.<env>.dah.example.com:9094` | VPN to on-prem |
| `controlcenter.apps.<env>.ocp.example.com` (inbound) | IGW → LB |

For each, your prediction + the `nc -zv` or `traceroute` evidence.

## Deliverable — `deliverables/<you>/week03/thursday.md`

1. **Connectivity ladder output** — the 5–6 `nc -zv` and 1 `traceroute` results
2. **VPC inventory** — subnets, route tables, SGs (CLI output or Console screenshot)
3. **The mechanism table** — your predictions + evidence for each  the platform destination
4. **Two questions** to bring to Friday — could be about specific tracker items (2.9 Okta egress, 2.10 broker port exception) given today's understanding

Cleanup:

```bash
oc delete pod net-debug
```
