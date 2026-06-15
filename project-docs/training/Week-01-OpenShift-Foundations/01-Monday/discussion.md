# Monday — Kubernetes Architecture

**Time**: ~90 min facilitated
**Diagram**: [`01-k8s-architecture.drawio`](01-k8s-architecture.drawio) — control plane + worker node + every native K8s component as a heptagon (modeled on kubernetes.io)

## Learning objective

> What happens, step by step, from `oc apply -f deployment.yaml` until a Pod is running on a node?

If the engineer can trace this walk-through, troubleshooting becomes much easier — every failure is a step in this chain that didn't happen.

## Architecture Discussion (~40 min)

Walk through the diagram one heptagon at a time:

- **`kube-apiserver`** — the front door. Everything talks to the apiserver; only the apiserver talks to etcd. Validates requests, runs admission policies (Gatekeeper, OpenShift SCC), persists state.
- **`etcd`** — Raft-replicated key-value store; the single source of truth for cluster state. Restoring etcd restores everything.
- **`kube-scheduler`** — watches for Pods with empty `nodeName`, picks a node based on resource fit / affinity / taints, writes the binding back. Decision-only; doesn't start anything.
- **`kube-controller-manager`** — hosts the built-in control loops (Deployment, ReplicaSet, Node, Endpoint, Job, ServiceAccount-token). Each loop watches a resource type and reconciles current → desired. **This is the pattern CFK and the Flink Operator extend.**
- **`kubelet`** — node-side agent, one per worker. Registers the node, watches for Pods assigned to its node, calls the container runtime via CRI gRPC, reports status back.
- **`kube-proxy`** — programs iptables/IPVS/eBPF rules so Service ClusterIPs are load-balanced to backing Pods. No traffic flows through kube-proxy itself.
- **Container Runtime (CRI-O on OpenShift)** — actually runs containers. Pulls images. Not a Kubernetes binary; swappable.

## Diagram Walkthrough (~30 min) — `oc apply -f deployment.yaml` step-by-step

Trace one arrow at a time on the diagram, using a marker or pointer:

1. `oc` POSTs the Deployment YAML to **`kube-apiserver`** over HTTPS (mTLS or bearer-token)
2. apiserver validates + runs admission policies + writes the Deployment to **`etcd`**
3. **Deployment controller** (in `kube-controller-manager`) sees the new Deployment, creates a ReplicaSet via the apiserver
4. **ReplicaSet controller** sees the new ReplicaSet, creates Pods (unscheduled — no `nodeName`) via the apiserver
5. **`kube-scheduler`** sees unscheduled Pods, picks a node, writes the binding back via the apiserver
6. **`kubelet`** on the chosen node sees a Pod assigned to it, calls **CRI-O** via CRI gRPC to start the container
7. CRI-O pulls the image, sets up cgroups + namespaces, runs the container, reports status to kubelet → apiserver → etcd
8. Once the Pod is Ready, **`kube-proxy`** sees the new endpoint (EndpointSlice) and updates the node's networking rules

Stop at each step and ask: *"if this step failed, what would the engineer see?"*

## Failure Scenarios — preview Friday's troubleshooting day

For each of the steps above, what's the most common real-world failure?

| Step | Common failure | What the engineer sees |
|---|---|---|
| 1 — `oc` to apiserver | Bad cluster URL, expired token | `error: dial tcp ...` / `401 Unauthorized` |
| 2 — admission policy | SCC denies the Pod, Gatekeeper constraint fails | `admission webhook denied the request` |
| 3 — Deployment controller | Almost never fails (controller bug) | `kubectl get deployment` shows no ReplicaSet |
| 4 — ReplicaSet controller | Quota exhausted, can't create Pod | Events: `exceeded quota` |
| 5 — scheduler | No node satisfies CPU/memory/taints | Events: `0/N nodes are available` |
| 6 — kubelet | Image pull fails (auth or DNS) | `ImagePullBackOff` |
| 7 — CRI-O | Container runtime bug, OOM-killed | `CrashLoopBackOff` |
| 8 — kube-proxy | Endpoints not propagating | Service has no endpoints; curl times out |

Keep this table in your back pocket — it becomes the troubleshooting tree on Friday.

## Q&A (~20 min)

Open-ended; use the diagram to anchor every answer:

1. If etcd were lost (no backup), what could you reconstruct from running workloads, and what couldn't?
2. Why does a Pod still appear "running" briefly after the kubelet on its node dies?
3. Which component would you check first if Pods are getting created but never reach Ready?
4. What's the security implication of the apiserver being the only thing that talks to etcd?
5. If you wanted to extend Kubernetes with a custom resource type (like `Kafka` for CFK), where in this picture does the operator slot in?

## Common misconceptions worth addressing

- **"kube-proxy proxies my traffic"** — no, it writes rules; the kernel routes traffic
- **"Pods talk to each other through the apiserver"** — no, Pods talk directly via the CNI overlay network
- **"Kubernetes runs containers"** — no, the container runtime (CRI-O / containerd) does
- **"OpenShift replaces all of K8s"** — no, OpenShift IS K8s plus added components (covered Friday)
