# Week 3 — Q&A (20 reinforcement questions)

---

## Monday — ROSA Architecture

**Q1. ROSA HCP vs ROSA Classic — what's the architectural difference?**
A. Classic = control plane (apiserver, etcd, scheduler, c-m) runs on EC2 instances inside YOUR AWS account. HCP = control plane runs in Red Hat's AWS account as a hosted service; you only pay for worker nodes. HCP is faster to provision, has lower control-plane cost, and outsources etcd management to Red Hat.

**Q2. Why does the platform pick one ROSA flavor over the other?**
A. Depends on cost vs. control tradeoffs. HCP is cheaper and lower-overhead but the etcd boundary moves to Red Hat. Classic gives full ownership and easier compliance answer ("our cluster, our etcd"). the platform's choice should be in the runbook; if not, ask the architecture team.

**Q3. ROSA's "MachineSet" — what is it K8s-side?**
A. A CR provided by the Machine API Operator (part of OpenShift). Each MachineSet manages N Machines = N EC2 instances of a specific type in a specific AZ. Scaling = changing `spec.replicas`. The Machine API talks to AWS via STS-assumed roles to provision the EC2s.

---

## Tuesday — OIDC

**Q4. Walk the OIDC dance for `oc login --web`.**
A. (1) Browser hits the cluster apiserver OAuth URL; (2) apiserver redirects to OpenShift's OAuth server; (3) OAuth server redirects to Okta with state + nonce; (4) Engineer authenticates with Okta; (5) Okta redirects back with an OAuth code; (6) OAuth server exchanges code for Okta token + user identity; (7) OAuth server issues OpenShift bearer token + redirects browser back to apiserver; (8) `oc` extracts the bearer token from the browser flow; (9) Subsequent `oc` calls use that bearer token in the Authorization header.

**Q5. What's the difference between the Okta JWT and the OpenShift bearer token?**
A. Okta JWT proves the engineer's identity at Okta + carries group claims. OpenShift bearer token is opaque, issued by OpenShift's OAuth server, used as the credential for all subsequent apiserver calls. The OAuth server can revoke OpenShift bearer tokens independently of Okta sessions.

**Q6. How does an Okta group become an OpenShift role binding?**
A. OpenShift OAuth maps Okta groups to OpenShift Groups via the IdP config. OpenShift Groups are then bound via RoleBindings / ClusterRoleBindings. Adding a user to the Okta group is sufficient — no OpenShift-side change needed. Removing the Okta group propagates on the next login or token refresh.

---

## Wednesday — STS / IRSA

**Q7. What does STS solve that long-lived IAM access keys don't?**
A. Long-lived keys leak (in git, logs, dumps) and stay valid forever. STS issues short-lived (15min - 12hr) credentials that can be scoped to a specific role. Even if leaked, the blast window is small. Engineers + workloads never get long-lived keys; they always assume a role via STS.

**Q8. Walk the IRSA flow for a Pod that wants to read from S3.**
A. (1) ServiceAccount is annotated with `eks.amazonaws.com/role-arn: arn:aws:iam::ACCT:role/foo`; (2) Pod uses that SA; (3) Kubelet injects a projected SA token at `/var/run/secrets/eks.amazonaws.com/serviceaccount/token`; (4) AWS SDK in the Pod sees the env vars `AWS_ROLE_ARN` + `AWS_WEB_IDENTITY_TOKEN_FILE`, calls STS `AssumeRoleWithWebIdentity` passing the SA token; (5) STS validates the token against the OIDC provider (the cluster's IDP); (6) STS issues short-lived AWS credentials; (7) SDK uses them to call S3.

**Q9. What three things must an engineer set up for IRSA to work?**
A. (1) An OIDC provider registered with IAM for the cluster (one-time, cluster-level); (2) An IAM Role with a Trust Policy that allows the cluster's OIDC provider + a specific ServiceAccount subject claim; (3) The SA annotation on the K8s side. Mismatch on any of three = `AccessDenied`.

**Q10. In production, what's the most likely IRSA use case in the medium term?**
A. Moving Flink checkpoint storage from NetApp S3 to AWS S3 (if that migration ever happens). Today the platform uses NetApp S3 with static access keys; IRSA matters more if/when workloads need to call AWS-native services. Cluster autoscaler at the platform layer already uses IRSA.

---

## Thursday — VPC

**Q11. Name the four layers of AWS networking a Pod traverses to reach the internet.**
A. (1) Pod CIDR (managed by CNI); (2) Node ENI (the EC2's primary network interface, in a subnet); (3) Subnet (public or private) — routing table determines next hop; (4) NAT GW (if private) or IGW (if public) to reach the internet. Plus SGs at the ENI level; NACLs at the subnet level.

**Q12. VPC endpoint vs NAT GW — when do you use which?**
A. VPC endpoint = direct private path from your VPC to an AWS service (S3, ECR, STS, etc.) without going through the internet. NAT GW = generic egress for any internet destination. VPC endpoints are cheaper (no NAT data charge), more secure (traffic doesn't leave AWS backbone), and required for some enterprise compliance asks. Use endpoints for S3 + STS + ECR; NAT for anything else.

**Q13. A Pod can't reach Okta. What three layers do you check?**
A. (1) NetworkPolicy in the namespace — does it allow egress to Okta CIDR + port 443? (2) Worker node SG egress — does it allow outbound 443 to Okta? (3) Subnet routing — is there a NAT GW for the private subnet the node is in? Plus DNS — `nslookup okta...` from the Pod. Tracker 2.9 captures the firewall exception that opens this.

**Q14. What does `topology.kubernetes.io/zone` give you?**
A. Per-node label naming the AZ. Used by scheduler for spread (anti-affinity across AZs), by topology-aware routing (prefer same-AZ Service endpoints to save cross-AZ data charges), and by StatefulSets for AZ-distributed broker placement.

---

## Friday — Cluster Upgrade + Scaling

**Q15. ROSA upgrade has two waves — describe each.**
A. Wave 1 (Control Plane): Red Hat upgrades apiserver + etcd + scheduler + controller-manager. For HCP it's near-invisible (hosted swap in RH's account); for Classic it's a rolling restart of master EC2s. Workloads keep running. Wave 2 (Worker Nodes): MachineConfigOperator renders new MachineConfig; per MachineConfigPool's `maxUnavailable`, K8s cordons + drains + replaces nodes one at a time.

**Q16. Why is a Kafka broker StatefulSet PDB critical during ROSA upgrade?**
A. Without it, the drain in Wave 2 could evict multiple broker Pods simultaneously — taking partitions below `min.insync.replicas`. PDB with `maxUnavailable: 1` on the broker SS forces drain to wait between brokers, preserving ISR. CFK's operator emits this PDB by default; verify it exists.

**Q17. What scales — control plane or worker pools — and how?**
A. Worker pools scale via MachineSet replica counts (or ClusterAutoscaler picking it up). Control plane scaling is handled by Red Hat (HCP) or fixed at install time (Classic — 3 masters). Worker scaling can be horizontal (more nodes) or vertical (bigger instance types via creating a new MachineSet and migrating).

---

## Cross-day integration

**Q18. The 9094 broker port in production — what's its role + what tracker?**
A. Tracker 2.10. CFK brokers expose a mTLS listener on 9094 (in addition to 9092 SASL_OAUTHBEARER and 9091 internal). VM CP brokers connect to 9094 as cluster-link source brokers during the VM→CFK migration. Needs a firewall exception (the 9094 port isn't in the default policy) — that's the policy-exception ticket.

**Q19. A new engineer can't log into the dev cluster via `oc login --web`. Walk the diagnostic order.**
A. (1) Is the user in the right Okta group? (Maha / IAM team check); (2) Is Okta itself up? (Okta status); (3) Does the cluster's OAuth IdP config point at the right Okta URL? (`oc get oauth cluster -o yaml`); (4) Network path — can a browser reach the apiserver URL? (cert + DNS + reachability); (5) For the OAuth code flow, is the browser blocked by a corporate proxy?

**Q20. The biggest mental shift Week 3 wanted you to make.**
A. ROSA isn't "OpenShift on AWS" — it's OpenShift + a bunch of AWS-specific identity/networking/scaling primitives that have to be configured correctly for the OpenShift bits to even function. STS, OIDC, VPC routing, SGs, MachineConfigPools — when these are wrong, OpenShift fails in confusing ways. Always check the AWS layer first when "OpenShift is broken."

---

## After completing Q&A

The 4-tracker reference (Q3, Q6, Q11, Q13, Q15, Q17, Q18) is the  the platform lookup map — keep it handy for incidents.
