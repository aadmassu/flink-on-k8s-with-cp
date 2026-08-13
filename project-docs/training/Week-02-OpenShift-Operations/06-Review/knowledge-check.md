# Week 2 — Knowledge Check

Answer from memory. If you struggle, return to that day's discussion.

## Platform operations (10 concept questions)

1. RBAC has four objects: Subject, Role/ClusterRole, RoleBinding/ClusterRoleBinding. Explain each and the rule "verbs × resources × scope."
2. Why does CFK need namespace-scoped Roles (not ClusterRoles) in production? Reference the tracker.
3. What is a ServiceAccount, and how does its token end up inside a Pod?
4. What does a Security Context Constraint (SCC) gate that an RBAC Role cannot? Name two SCC fields engineers commonly care about.
5. Define the Operator pattern in 3 sentences (Custom Resource → controller → reconcile → status).
6. What does "level-triggered" mean for an Operator, and why is it more robust than "edge-triggered"?
7. Walk the metrics path from broker Pod to Grafana panel — every hop.
8. What's the difference between a Prometheus rule and a Prometheus alert?
9. ArgoCD has a Sync state and a Health state. What's the difference and which one tells you "the cluster matches git"?
10. ResourceQuota vs LimitRange — which blocks at admission, which sets defaults, and which is more dangerous to misconfigure?

## Self-scoring

- 8-10: ready for Week 3
- 5-7: re-read RBAC, Operators, and Quotas before Week 3 starts
- < 5: revisit Week 2 fully
