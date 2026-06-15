# Week 1 — Knowledge Check

Self-quiz. Try to answer from memory before looking back at discussion notes. If you can't answer in 1-2 sentences, re-read that day's `discussion.md`.

## Foundations (10 concept questions)

1. Name the four control-plane components of a Kubernetes cluster and what each does in one sentence.
2. What does the kubelet do, and how does it differ from the controller-manager?
3. Why does a StatefulSet exist when a Deployment already manages Pods?
4. What does OpenShift add on top of stock Kubernetes? List the four most important additions.
5. A Pod has three containers. When the Pod is "scheduled," what does that mean precisely?
6. Walk the chain: client → broker. List every K8s object the traffic touches when the broker is exposed via a Route.
7. What's the difference between a ClusterIP Service and a Headless Service, and when do you use each for Kafka?
8. PVC, PV, StorageClass — explain each and how the three connect when a Pod requests storage.
9. ConfigMap vs Secret — when would you use each, and how does OpenShift handle base64 encoding for Secrets?
10. Walk the troubleshooting decision tree for "Pod is in CrashLoopBackOff" — what are the first 3 commands you run?

## Self-scoring

- 8-10 confident: ready for Week 2
- 5-7: re-read the days you missed before Week 2 starts
- < 5: revisit the entire week before moving forward; ask the instructor for office hours
