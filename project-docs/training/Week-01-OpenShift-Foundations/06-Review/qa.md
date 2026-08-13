# Week 1 — Q&A (20 reinforcement questions)

Short Q&A organized by day. Read the question, formulate an answer in your head, then check.

---

## Monday — Kubernetes + OpenShift Architecture

**Q1. Why does Kubernetes separate the control plane from worker nodes?**
A. The control plane (apiserver, etcd, scheduler, controller-manager) is the cluster's brain — it's CPU-intensive, security-sensitive, and benefits from running on dedicated hardware that workers don't see. Worker nodes run user workloads in containers under kubelet + CRI-O. Separating them lets you scale workers without touching the control plane, and protects etcd from noisy-neighbor effects.

**Q2. What is etcd and why is it the single most important component?**
A. etcd is the consistent key-value store that holds ALL cluster state — every object, every config. If etcd corrupts, the cluster is gone. It uses Raft consensus; a quorum (3 or 5 nodes) must survive. ROSA HCP outsources etcd management to Red Hat's AWS account so you don't manage it.

**Q3. What does OpenShift add on top of Kubernetes?**
A. Four major additions: (1) Routes — a layer-7 reverse proxy in front of Services; (2) SCCs — Security Context Constraints that gate what Pods can do (privileged, hostPath, etc.); (3) integrated OAuth + Console; (4) the Operator Lifecycle Manager and the OperatorHub. Plus minor: ImageStreams, BuildConfigs, Projects (namespaces with extra metadata).

**Q4. How is a Project different from a Namespace?**
A. A Project is a Namespace with OpenShift-added metadata (annotations for display name, requester, description) plus default ResourceQuota + LimitRange + RBAC bindings. Underneath the hood it's still a Namespace — kubectl sees it as such. `oc new-project` creates the Project + applies the standard templates.

---

## Tuesday — Pods, Deployments, StatefulSets

**Q5. Why does Kafka run as a StatefulSet, not a Deployment?**
A. Brokers need stable identity (broker.id tied to a hostname like kafka-0) and stable storage (PVC follows the Pod). Deployments give you fungible Pods with random suffixes; killing kafka-0 and getting kafka-asdfg back would break the broker's identity and the partition assignments. StatefulSet preserves both name and PVC binding across Pod restarts.

**Q6. What does `podManagementPolicy: OrderedReady` mean and when should you NOT use it?**
A. OrderedReady is the StatefulSet default — Pod N waits for Pod N-1 to be Ready before starting. For initial bring-up of an N-broker Kafka cluster, this means each broker waits for the previous; total startup is N × per-broker-time. For faster bring-up use `Parallel`, but ONLY during initial creation. For upgrades, leave it OrderedReady — you want one-at-a-time replacement.

**Q7. When a Pod has a sidecar container, can the sidecar outlive the main container?**
A. No, the Pod is a unit. When the Pod terminates, ALL containers terminate. Sidecars share the Pod's network namespace and (optionally) volumes. A new sidecar pattern in K8s 1.28+ adds "initContainers with restartPolicy: Always" for true sidecars; CFK doesn't use that yet.

---

## Wednesday — Services + Routes + Config

**Q8. Trace a client request from outside the cluster to a Kafka broker Pod (port 9092). Name every K8s object touched.**
A. Client → DNS → HAProxy Ingress Pod (OpenShift) → Route (TLS termination or passthrough) → Service (ClusterIP or Headless) → Endpoints (the live broker IPs) → kube-proxy iptables rule → broker Pod IP:9092 → broker container. The Route + Service rules are managed by OpenShift; the iptables update is managed by kube-proxy.

**Q9. What's the difference between a ClusterIP Service and a Headless Service?**
A. ClusterIP gets a virtual IP that load-balances to backend Pods. Headless (`clusterIP: None`) gets NO virtual IP — DNS returns A records for each backing Pod. Kafka uses Headless for the broker-discovery service so each broker can directly address kafka-0, kafka-1, kafka-2 by DNS.

**Q10. How does a Secret protect a value compared to a ConfigMap?**
A. It doesn't — much. Secrets are base64-encoded (not encrypted) in etcd by default. The real protection is RBAC + admission: most engineers don't have GET on Secrets in production namespaces, and OpenShift can encrypt etcd at rest. For real secret material (CyberArk-managed in production) the value never lives in etcd — it's pulled at Pod start via ESO and rotated on a schedule.

**Q11. What's the difference between TLS edge-termination and passthrough on a Route?**
A. Edge: TLS terminates at HAProxy; clear-text from HAProxy → Pod. Re-encrypt: TLS terminates at HAProxy, then NEW TLS to the Pod. Passthrough: HAProxy doesn't inspect; the encrypted bytes flow straight to the Pod. Kafka brokers use passthrough on 9092 because the broker handles its own SASL/TLS (HAProxy can't decrypt + re-sign Kafka frames).

---

## Thursday — Storage

**Q12. Walk the chain: Pod requests storage. What objects come into play?**
A. Pod template references PVC by name → PVC says "I need 10Gi of `gp3-csi` storage class, RWO" → Provisioner (CSI driver bound to the storage class) creates a backing volume (EBS in ROSA) and binds a PV that references it → kubelet attaches the PV to the node → mounts into the Pod. Pod sees `/var/lib/data` (or whatever it mounted as). PVC + PV bind 1:1.

**Q13. What does a StorageClass's `reclaimPolicy` control?**
A. What happens to the PV when its PVC is deleted. `Delete` — PV and backing storage are removed. `Retain` — PV stays as `Released`, backing storage stays, you can manually re-bind it. Production Kafka brokers typically use `Retain` so accidental PVC deletion doesn't lose log data.

**Q14. If a PV is "Bound" but the Pod referencing it is Pending, what could be wrong?**
A. Several possibilities: node selector / affinity rules mean no node can run the Pod; the node where the PV is attached has resource pressure; the PV is a `nodeAffinity` PV (zonal) and no schedulable node is in that zone; or the Pod's resource requests exceed all nodes. `oc describe pod` Events section names which.

---

## Friday — Troubleshooting Workflow

**Q15. What are the first 3 commands when a Pod is in CrashLoopBackOff?**
A. (1) `oc get pod <name>` — confirm state + restart count; (2) `oc describe pod <name>` — read Events for K8s-level reason; (3) `oc logs <name> --previous` — read the actual container exit cause from the prior crash. If `--previous` is empty, the container failed before it logged anything (image entrypoint issue).

**Q16. ImagePullBackOff — what are the typical causes and which one is most common in production?**
A. Causes: (1) image tag doesn't exist; (2) registry auth failed; (3) registry unreachable from worker network. In production the most common is #2 — Artifactory pull secret missing or expired, often because a project was created without the standard pull-secret template applied. Fix: apply the standard pull-secret to the namespace.

**Q17. A Pod is OOMKilled. What was wrong, and how do you confirm?**
A. The container exceeded its memory limit. Confirm: `oc describe pod` shows `Reason: OOMKilled` in the container status; `LastState.Terminated.Reason` is OOMKilled. Fix: raise the memory limit, OR find the leak/inefficiency in the workload. For Kafka, OOMKilled usually means the JVM heap is too small (or too large with no headroom for off-heap).

**Q18. A Pod is Pending. What's the first thing to check?**
A. `oc describe pod <name>` Events section — the scheduler will tell you why it can't schedule. Common reasons: insufficient CPU/memory across nodes, taints + tolerations mismatch, PVC unbound, node selector with no matches. NEVER assume it's a "K8s bug" — the scheduler is always explicit about why.

**Q19. Define the four-layer troubleshooting model from Week 1.**
A. Layer 1 — infra: nodes Ready, network reachable, storage attached. Layer 2 — K8s control plane: apiserver responsive, etcd healthy. Layer 3 — workload primitives: Pods scheduled, Services routing, Endpoints populated. Layer 4 — application: container logs, app-level errors. Most customer-reported issues live in Layer 4 symptomatically but a layer below causally. Triage descends.

**Q20. What's the one habit Week 1 wanted you to build for the rest of the bootcamp?**
A. Read `status.conditions` and `Events:` BEFORE reading container logs. K8s tells you why something failed in structured fields most of the time. Logs are forensic — useful but late in the funnel. Engineers who jump to `oc logs` first miss the "why didn't it schedule" / "why won't it pull" answers entirely.

---

## After completing Q&A

- Flag any question you couldn't answer confidently — re-read that day before Week 2
- Keep this file for your runbook; the answers are condensed mental models you'll use on call
