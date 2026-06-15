# Week 4 — Knowledge Check

The most important week's review. Get this material cold before going on call.

## CFK on OpenShift (10 concept questions)

1. Name the 5 Confluent components CFK manages, and explain CFK's role for each.
2. What does the CFK operator produce when you `oc apply` a Kafka CR? List every K8s object.
3. Walk the reconciliation loop step-by-step (5 steps).
4. Where do you read CR health first — `status.conditions` or `oc describe pod`? Why?
5. Internal vs external vs custom listener — which protocol/auth on which port in production, and what tracker covers the custom one?
6. The broker JVM serves three listeners simultaneously. How can it speak different auth protocols on different ports?
7. Walk the TLS chain from cert-manager Certificate CR to a Kafka client's successful handshake.
8. What's the "trust bundle" problem (tracker 2.8), and how do you fix it?
9. PodDisruptionBudget during a rolling upgrade — what value, why, and what breaks without it?
10. What are the four most common rolling-upgrade failure modes? Which has the worst recovery cost?

## Self-scoring

- 8-10: confident on-call shadow for Kafka workloads
- 5-7: re-read Tue (CR→Pod) + Thu (TLS); these are the deepest concepts
- < 5: revisit Week 4 fully — this material gets exercised every week post-bootcamp
