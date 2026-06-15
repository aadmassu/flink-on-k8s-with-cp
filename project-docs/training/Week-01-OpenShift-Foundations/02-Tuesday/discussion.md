# Tuesday — Pods, Deployments, StatefulSets

**Time**: ~90 min
**Diagram**: [`02-k8s-components.drawio`](02-k8s-components.drawio) — workload controllers + their relationships

## Learning objective

> **Why can Kafka not run as a Deployment?**

If the engineer can answer that on a whiteboard, they understand the difference between a stateless workload and a stateful one — and they're ready to think about CFK.

## Architecture Discussion (~40 min)

- **Pod** — the smallest deployable unit. One or more containers sharing a network namespace and (optionally) volumes. **Pods are cattle**: ephemeral, fungible, no stable identity. If the node dies, the Pod dies. K8s doesn't bring it back unless something else (a controller) wants it back.

- **Deployment** — wraps a **ReplicaSet** that maintains N identical Pods. Pods are **interchangeable**: any Pod is as good as any other; if one dies, the controller creates a fresh one with a new name + IP. Perfect for stateless workloads (nginx, REST APIs, stateless processors).

- **StatefulSet** — wraps a different set of guarantees:
  - **Stable network identity**: `pod-0`, `pod-1`, `pod-2` (not random suffixes). DNS resolves predictably: `pod-0.headless-service.namespace.svc.cluster.local`.
  - **Stable storage identity**: each Pod gets its OWN PersistentVolumeClaim that follows it through restarts. Pod-0 always mounts PVC-pod-0.
  - **Ordered lifecycle**: Pods are created and terminated 0 → 1 → 2 (creation) and 2 → 1 → 0 (deletion). The next Pod only starts once the previous is Ready.
  - **No interchangeability**: if pod-0 dies, K8s recreates pod-0 specifically (same name, same PVC, same DNS), not a random new Pod.

- **Why Kafka needs StatefulSet**: each broker has an identity (`broker.id`), unique log data on disk, and other brokers + ZooKeeper/KRaft need to know which broker is which by DNS. Deployment-managed Pods would shuffle IDs + lose disk identity on restart. The cluster would never form quorum.

- **CFK builds on this**: a CFK `Kafka` Custom Resource doesn't directly create Pods. It creates a StatefulSet, which creates the broker Pods. Same for KRaftController.

## Diagram Walkthrough (~30 min)

On the K8s Components diagram, focus on the workload-controller row:

- Deployment → manages → Pod (interchangeable)
- StatefulSet → manages → Pod-0 + PVC-0; Pod-1 + PVC-1; Pod-2 + PVC-2 (each glued together)
- Custom Resource → managed by → Operator → which creates → Deployment OR StatefulSet

Then trace: when you delete `pod-0` of a StatefulSet, what does K8s do? (Recreates `pod-0` with the SAME PVC mounted — the data persists.)

## Failure Scenarios — preview troubleshooting

| Symptom | Likely cause |
|---|---|
| StatefulSet Pod stuck `Pending` | PVC can't bind (no PV available; storage class wrong; quota exhausted) |
| Deployment Pod `CrashLoopBackOff` | App-side error, OOMKilled, bad config |
| Broker rejoins cluster with wrong `broker.id` | Pod was treated as fungible somehow — Deployment was used instead of StatefulSet, or PVC was deleted |
| StatefulSet rolling update stuck at pod-1 | pod-1 is unhealthy and not reaching Ready; pod-2 won't even start (ordered lifecycle) |

## Q&A

1. What happens if you delete a StatefulSet's PVC but not the StatefulSet itself?
2. If a Deployment Pod dies and gets replaced, why does its IP address change?
3. Why does K8s deploy StatefulSet Pods one at a time instead of in parallel?
4. Can a Deployment Pod mount a PVC? If yes, what happens with replicas > 1?
5. When CFK creates 3 Kafka brokers, what controls the Pod start order — Deployment or StatefulSet?

## Common misconceptions

- **"A Pod equals a container"** — no, a Pod can have multiple containers (sidecars, init containers)
- **"Deployments are 'newer' StatefulSets"** — no, they solve different problems
- **"StatefulSet means high availability"** — no, it means identity preservation. HA is replication, separate concept.
