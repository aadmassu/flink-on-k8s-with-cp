# Week 3 — Knowledge Check

## ROSA + AWS integration (10 concept questions)

1. What's the difference between ROSA Classic and ROSA HCP? Which does  the platform use, and why?
2. Walk the OIDC sign-in flow when an engineer types `oc login --web`. Name every player.
3. What is STS, and why does it eliminate long-lived AWS credentials?
4. IRSA: what's the projected SA token, and how does AWS verify it?
5. Name the 4 layers of AWS networking that a CFK Pod traverses to reach the internet.
6. What does a VPC endpoint do, and when would you use one instead of NAT GW egress?
7. Why does the platform need an Okta egress firewall exception (tracker 2.9)?
8. During a ROSA upgrade, what happens to running workloads? Walk both waves (control plane + worker).
9. A MachineConfigPool with `maxUnavailable: 1` is upgrading. A worker node dies separately. What does K8s do?
10. Cluster-link source brokers connect from VM CP to CFK on which port, and why does that port need a firewall exception (tracker 2.10)?

## Self-scoring

- 8-10: ready for Week 4 (CFK)
- 5-7: re-read OIDC + STS + tracker 2.9/2.10 before Week 4
- < 5: revisit Week 3 fully — Week 4's auth depends on this
