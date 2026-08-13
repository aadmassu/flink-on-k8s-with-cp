# Tuesday — Workload Controllers, Scaling, HA, Scheduling, Resilience

**Time**: ~90 min discussion + ~3-4 hours lab
**Diagram**: [`02-k8s-components.drawio`](02-k8s-components.drawio) — 5 tabs, one per lesson

## Learning objective

> **Why can Kafka not run as a Deployment, and what does it take to keep a Kafka cluster healthy through node failures, maintenance windows, and upgrades?**

If the engineer can answer that on a whiteboard at the end of the day, they understand the difference between a stateless workload and a stateful one — and they're ready to think about CFK in Week 4.

The day is broken into 5 short lessons. Each has its own diagram tab in the `.drawio` file.

---

## Lesson 1 — Workload Controllers (~15 min)

**Diagram tab**: `L1 — Workload Controllers`

The shape of Kubernetes workloads:

```
Deployment
 └── ReplicaSet
      └── Pod, Pod, Pod    (interchangeable, random suffixes)

StatefulSet
 └── pod-0, pod-1, pod-2   (stable identity + per-Pod PVC)
```

- **Pod** — smallest deployable unit. One or more containers sharing a network namespace and (optionally) volumes. **Pods are cattle**: ephemeral, fungible, no stable identity. If the node dies, the Pod dies. K8s doesn't bring it back unless something else (a controller) wants it back.

- **Deployment** — wraps a **ReplicaSet** that maintains N identical Pods. Pods are **interchangeable**: any Pod is as good as any other. Perfect for stateless workloads (REST APIs, stateless stream processors, CMF, Connect workers, Schema Registry).

- **StatefulSet** — wraps a different set of guarantees:
  - **Stable network identity**: `pod-0`, `pod-1`, `pod-2` (not random suffixes). DNS resolves predictably.
  - **Stable storage identity**: each Pod gets its OWN PersistentVolumeClaim that follows it through restarts.
  - **Ordered lifecycle**: Pods created and terminated in order — `0 → 1 → 2` (creation), `2 → 1 → 0` (deletion).
  - **No interchangeability**: if pod-0 dies, K8s recreates pod-0 specifically.

### Why Kafka uses StatefulSets

Each broker has a `broker.id`, unique log data on disk, and other brokers + KRaftController need to know which broker is which by DNS. Deployment-managed Pods would shuffle IDs and lose disk identity on restart. The cluster would never form quorum.

### Why Flink uses StatefulSets

Two reasons:
- **JobManager HA** — leader election requires stable identity so standby JMs can find the leader's metadata path.
- **TaskManager state** — RocksDB state backend writes to local disk; per-TM PVC means state survives Pod restart.

### Tie-in to Week 4

CFK never creates Pods directly. It creates a Kafka CR → which the operator translates into a StatefulSet → which K8s expands into Pods. Today's StatefulSet knowledge is the layer underneath every CFK CR.

---

## Lesson 2 — Scaling (~15 min)

**Diagram tab**: `L2 — Scaling`

Three flavors of scale at the K8s layer:

- **Horizontal Pod Autoscaler (HPA)** — adds/removes replicas based on a metric (CPU, memory, custom). Works on Deployments out of the box. Adds replicas → more Pods → ReplicaSet target count goes up → kubelet starts more Pods.
- **Vertical Pod Autoscaler (VPA)** — adjusts the requests/limits of EACH Pod (bigger Pod, not more of them). Less common in production because it requires a Pod restart.
- **Cluster Autoscaler** — adds/removes NODES when Pods can't be scheduled or nodes are underutilized. Runs at the cloud/infrastructure layer.

### Why Kafka doesn't scale like a web application

- **Scaling brokers ≠ scaling throughput automatically.** New brokers have no partitions until you rebalance. Partition rebalance moves data over the network and takes hours for large logs.
- **Partition count is decided at topic creation.** A 6-partition topic can be consumed in parallel by at most 6 consumers in a group. Adding brokers doesn't change that.
- **HPA on a StatefulSet is dangerous.** Scaling down would terminate brokers; partitions whose replicas only lived on those brokers would lose ISR. Most teams don't HPA brokers at all — they scale capacity manually with planning.

### Why Flink scales differently

- **Parallelism is a job-level property**, decided when the job is submitted.
- **To rescale a running job**: stop with savepoint → submit a new job with new parallelism → restore from savepoint. State gets repartitioned during restore.
- **Reactive mode** (Flink 1.13+) auto-scales when TMs are added/removed, but FCB doesn't use this today.

The takeaway: scaling stateful systems is a planned operation, not an auto-scaler decision.

---

## Lesson 3 — High Availability via Affinity / Anti-Affinity (~15 min)

**Diagram tab**: `L3 — HA Affinity & Anti-Affinity`

K8s places Pods on Nodes via the scheduler. Affinity rules influence that placement:

- **Affinity** — schedule Pod A near (or on) something else. Examples: "place this Pod on a node with the SSD label," or "place this Pod near another Pod that produces its input."
- **Anti-Affinity** — schedule Pod A AWAY from things. The Kafka pattern: "no two broker Pods on the same node."

### The Kafka anti-affinity pattern

```
StatefulSet: kafka  (replicas: 3)
podAntiAffinity:
  requiredDuringSchedulingIgnoredDuringExecution:
    - labelSelector: { app: kafka }
      topologyKey: kubernetes.io/hostname
```

Result: broker-0 on node-1, broker-1 on node-2, broker-2 on node-3 — guaranteed.

### What happens if Node-2 dies?

- **Without anti-affinity** — schedulable replicas might end up clustered (say broker-0 and broker-1 on node-1). When node-1 dies, you lose 2 brokers at once. For a 3-broker cluster, ISR drops below `min.insync.replicas=2` → producer writes fail.
- **With anti-affinity + topologyKey=hostname** — at most ONE broker dies when ONE node dies. Other brokers continue, ISR=2, cluster keeps serving.

Stronger spread: `topologyKey=topology.kubernetes.io/zone` distributes across AZs.

### Topology spread constraints (modern alternative)

K8s 1.19+ has `topologySpreadConstraints` which are easier to reason about than `podAntiAffinity`. CFK still emits classic anti-affinity by default — recognize both patterns.

---

## Lesson 4 — Scheduling via Taints + Tolerations (~15 min)

**Diagram tab**: `L4 — Scheduling Taints & Tolerations`

Affinity tells the scheduler **where Pods want to go**. Taints + tolerations are the inverse — **which Pods nodes will accept**.

- **Taint** on a node — "this node repels Pods unless they tolerate this taint." Syntax: `key=value:Effect` where Effect is `NoSchedule` / `PreferNoSchedule` / `NoExecute`.
- **Toleration** on a Pod — "this Pod is okay being on a node with that taint." Matches key + value + effect.

### Real-world use cases

| Node taint | Use case |
|---|---|
| `dedicated=kafka:NoSchedule` | Reserve specific nodes for Kafka brokers only — other workloads get rejected |
| `dedicated=flink:NoSchedule` | Reserve nodes for Flink TaskManagers (CPU + RAM intensive) |
| `nvidia.com/gpu=true:NoSchedule` | GPU nodes — only GPU workloads tolerate this |
| `node-role.kubernetes.io/master:NoSchedule` | Control-plane nodes — kube-system pods tolerate, user workloads don't |

### Combining with affinity

To pin Kafka brokers to dedicated nodes:
1. Taint the nodes: `dedicated=kafka:NoSchedule`
2. Add a toleration to the broker Pods so they pass the taint
3. Add a node-selector or node-affinity so they ONLY land on those nodes

Without both pieces, brokers would tolerate the taint but might still land elsewhere if other nodes are cheaper.

### The three Effects

- **NoSchedule** — new Pods can't land unless they tolerate. Existing Pods stay.
- **PreferNoSchedule** — soft version. Scheduler avoids if possible.
- **NoExecute** — new Pods can't land AND existing Pods get evicted (unless they tolerate). Used for emergency node isolation.

---

## Lesson 5 — Resilience via Pod Disruption Budgets (~15 min)

**Diagram tab**: `L5 — Resilience PDB`

A **PodDisruptionBudget (PDB)** tells K8s how many Pods of a workload can be unavailable at the same time during VOLUNTARY disruption.

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: kafka-pdb
spec:
  minAvailable: 2        # or use maxUnavailable: 1
  selector:
    matchLabels:
      app: kafka
```

### What PDB DOES protect

- `oc adm drain <node>` — controlled evictions during maintenance, upgrades, autoscale-down
- Cluster autoscaler scale-down
- Operator-driven rolling updates

### What PDB does NOT protect

- Node crashes (involuntary disruption) — Pods just die
- Hardware failure
- Network partition

### Without PDB — what goes wrong

```
3 brokers → 3 nodes
   |
oc adm drain node-2
   |
all evictable Pods on node-2 evicted at once
   |
if drain happens to evict broker-1 AND a partition leader migration is in flight on broker-2,
the cluster can lose quorum / dip below min.insync.replicas
```

### With PDB minAvailable=2 on 3 brokers

```
oc adm drain node-2
   |
PDB: "you can evict broker-1 only if at least 2 of 3 stay available"
   |
broker-1 evicted → broker-0 + broker-2 still up → eviction allowed
   |
broker-1 rejoins on a different node → PDB recalculates
   |
drain proceeds to other Pods on node-2
```

### Directly relevant to

- **Kafka upgrades** — CFK rolling updates respect the PDB
- **OpenShift upgrades** — MachineConfigOperator's per-node drain respects PDBs
- **Worker replacement** — drains for replacement respect PDBs
- **ROSA maintenance** — Red Hat-orchestrated node replacement respects PDBs

---

## The CFK Connection — tying it all together

Everything in today's lessons exists because a Kafka cluster must survive node failures, maintenance windows, and upgrades.

```
Kafka Broker
   |
StatefulSet              (Lesson 1: identity + per-Pod PVC)
   |
Pod Anti-Affinity        (Lesson 3: never two brokers on one node)
   |
PodDisruptionBudget      (Lesson 5: drain only evicts 1 at a time)
   |
PersistentVolumeClaim    (Lesson 1: data survives Pod restart)
```

Scaling (Lesson 2) and dedicated-node scheduling (Lesson 4) are the "advanced operator" tools you reach for when basic SS + anti-affinity + PDB aren't enough.

When Week 4 shows you a Kafka CR with `spec.podTemplate.affinity`, `spec.replicas`, and an emitted PDB — you'll already know what each one is doing.

---

## Failure Scenarios — preview troubleshooting

| Symptom | Likely cause |
|---|---|
| StatefulSet Pod stuck `Pending` | PVC can't bind (no PV available; storage class wrong; quota exhausted) |
| Deployment Pod `CrashLoopBackOff` | App-side error, OOMKilled, bad config |
| Multiple Kafka Pods on one node | Anti-affinity missing or `preferredDuringScheduling` (soft) instead of `required` |
| `oc adm drain` hangs forever | PDB blocking eviction — `minAvailable` too tight relative to current Ready replicas |
| Broker rejoins cluster with wrong `broker.id` | Pod treated as fungible — Deployment used instead of StatefulSet, or PVC was deleted |
| StatefulSet rolling update stuck at pod-1 | pod-1 unhealthy / not Ready; pod-2 won't start (ordered lifecycle) |

---

## Q&A — by lesson

**Lesson 1**
1. What happens if you delete a StatefulSet's PVC but not the StatefulSet itself?
2. Can a Deployment Pod mount a PVC? If yes, what happens with replicas > 1?

**Lesson 2**
3. Why is HPA dangerous to apply to a Kafka broker StatefulSet?
4. Walk through what it takes to scale a 3-broker Kafka cluster to 6 brokers (planning steps).

**Lesson 3**
5. What's the difference between `requiredDuringScheduling` and `preferredDuringScheduling` anti-affinity, and which one would CFK emit by default?
6. With 3 brokers + anti-affinity on hostname + a 2-node cluster, what happens to broker-2?

**Lesson 4**
7. If a node has `dedicated=kafka:NoSchedule` and a Pod has `tolerations: [key: dedicated, value: kafka, effect: NoSchedule]` — will the Pod ALWAYS land on that node? Why or why not?
8. When would you use `NoExecute` vs `NoSchedule`?

**Lesson 5**
9. PDB `minAvailable: 3` on a 3-broker StatefulSet — what happens when you drain a node?
10. Does PDB protect against a node crash?

---

## Common misconceptions

- **"A Pod equals a container"** — no, a Pod can have multiple containers (sidecars, init containers).
- **"Deployments are 'newer' StatefulSets"** — no, they solve different problems.
- **"StatefulSet means high availability"** — no, it means identity preservation. HA = replication + anti-affinity + PDB combined.
- **"HPA scales everything"** — HPA works well on stateless Deployments. Don't use it on StatefulSets without thinking hard.
- **"Taints repel; tolerations attract"** — half right. Tolerations don't ATTRACT, they just ALLOW. Use nodeSelector / nodeAffinity to attract.
