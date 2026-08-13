# Week 1 Tuesday — Lab: StatefulSet + Anti-Affinity + PDB + Drain (on kind)

**Time**: ~4 hours (30 min setup + ~3.5 hours lab)
**Prerequisite**: Lesson 1-5 from morning discussion

## Why kind for this lab

The Tuesday lab needs **multiple nodes** to demonstrate anti-affinity spread and drain behavior. OpenShift Local (CRC) is single-node, so the drain step doesn't make pedagogical sense. `kind` ("Kubernetes IN Docker") spins up a real multi-node K8s cluster locally in about 60 seconds — perfect for this material.

**Plan for the bootcamp**: use kind for **Week 1 and Week 2**. Starting **Week 3 onwards** (ROSA, CFK, Kafka, Flink), switch to a real ROSA cluster — you need real AWS IAM / STS / OIDC / VPC and real OpenShift primitives (Routes, SCC, OLM) for those days.

`kubectl` against kind behaves identically to `oc` against OpenShift for everything in this Week-1 lab.

---

## Environment Setup — kind on macOS (one-time, ~10 min)

### Step 1 — install Docker Desktop (or Colima as a lighter alternative)

kind runs each "node" as a container, so you need a container runtime.

**Option A — Docker Desktop** (easiest, GUI)

1. Download from https://www.docker.com/products/docker-desktop/
2. Install + launch. Sign in (free account works).
3. In Docker Desktop → Settings → Resources, bump CPU to **6** and memory to **8 GB minimum** (kind nodes are CPU-light but K8s itself is memory-hungry).
4. Verify:
   ```bash
   docker version
   docker run --rm hello-world
   ```

**Option B — Colima** (lighter, CLI-only, no Docker login required)

```bash
brew install colima docker
colima start --cpu 6 --memory 8
docker version    # should connect to colima's daemon
```

### Step 2 — install kind + kubectl

```bash
brew install kind kubectl

kind version       # should print v0.20+ at time of writing
kubectl version --client
```

### Step 3 — create a 3-node training cluster

```bash
cat <<EOF | kind create cluster --name training --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
  - role: worker
  - role: worker
  - role: worker
EOF
```

Takes ~60 seconds. The CLI prints `Set kubectl context to "kind-training"` when done.

### Step 4 — verify the cluster

```bash
kubectl cluster-info --context kind-training

kubectl get nodes
# Expected: 4 nodes (1 control-plane + 3 workers), all Ready

kubectl get pods -n kube-system
# Expected: CoreDNS + kindnet + kube-proxy on every node
```

If something is wrong: `kind delete cluster --name training` and recreate.

### Step 5 — set the context (so you don't have to specify it each time)

```bash
kubectl config use-context kind-training
kubectl config current-context        # confirms kind-training
```

### Step 6 — create a working namespace

```bash
kubectl create namespace training
kubectl config set-context --current --namespace=training
kubectl config view --minify | grep namespace:
# Expected: namespace: training
```

You're ready.

---

## Hands-on Lab

All YAML manifests for this lab live in [`lab-manifests/`](lab-manifests/). Run the commands below from this `02-Tuesday/` directory so relative paths resolve.

Reference examples — generic Deployment + StatefulSet templates with inline comments — are under [`lab-manifests/examples/`](lab-manifests/examples/) for engineers to read alongside Lesson 1. They're standalone and runnable but NOT applied by the lab.

### Step 1 — Deploy a 3-replica StatefulSet (no extras yet)

```bash
kubectl apply -f lab-manifests/statefulset.yaml

kubectl get pods -l app=demo -o wide -w &
sleep 30 ; jobs %1 && kill %1 2>/dev/null
kubectl get pods -l app=demo -o wide
```

**Capture**: which node hosts each of demo-0 / demo-1 / demo-2. Without anti-affinity, they MAY share a node depending on the scheduler.

### Step 2 — Apply pod anti-affinity (Lesson 3)

```bash
kubectl patch statefulset demo --type=merge --patch-file=lab-manifests/anti-affinity-patch.yaml

# Force a rolling update so existing Pods re-spread
kubectl rollout restart statefulset/demo
kubectl rollout status statefulset/demo --timeout=300s

kubectl get pods -l app=demo -o wide
```

**Capture**: each Pod should now be on a DIFFERENT worker. With 3 workers + 3 replicas, all three should land — one per node.

To prove the constraint works, scale to 4 (more replicas than workers):

```bash
kubectl scale statefulset/demo --replicas=4
sleep 15
kubectl get pods -l app=demo -o wide
# Expected: demo-3 stuck Pending
kubectl describe pod demo-3 | grep -A 5 Events:
# Look for "didn't match Pod anti-affinity rules"

kubectl scale statefulset/demo --replicas=3
```

### Step 3 — Apply a PDB (Lesson 5)

```bash
kubectl apply -f lab-manifests/pdb.yaml

kubectl get pdb demo-pdb
```

**Capture**: `ALLOWED DISRUPTIONS` should be `1` (3 ready - 2 minAvailable = 1).

### Step 4 — Drain a node and observe (the safe case)

```bash
NODE=$(kubectl get pod demo-1 -o jsonpath='{.spec.nodeName}')
echo "Will drain $NODE"

# In a second terminal, watch:
#   kubectl get pods -l app=demo -o wide -w
#   kubectl get pdb demo-pdb -w

kubectl drain $NODE \
  --delete-emptydir-data \
  --ignore-daemonsets \
  --force \
  --grace-period=30 \
  --timeout=120s
```

**Expected behavior**:
- PDB allows the eviction (allowed disruptions = 1 ≥ 1 needed).
- demo-1 evicts cleanly.
- StatefulSet re-creates demo-1 on a different worker (anti-affinity ensures it doesn't land on a node already hosting demo-0 or demo-2).
- Drain completes successfully.

```bash
# Uncordon the node so it's schedulable again
kubectl uncordon $NODE

# Confirm all 3 Pods are Running
kubectl get pods -l app=demo -o wide
```

### Step 5 — Break the PDB on purpose (the blocked case)

Tighten the PDB so a drain is impossible:

```bash
kubectl patch pdb demo-pdb --type=merge --patch-file=lab-manifests/pdb-strict-patch.yaml

kubectl get pdb demo-pdb
# ALLOWED DISRUPTIONS should now be 0

NODE=$(kubectl get pod demo-1 -o jsonpath='{.spec.nodeName}')

# This drain should HANG / FAIL — PDB blocks the eviction
timeout 60 kubectl drain $NODE \
  --delete-emptydir-data \
  --ignore-daemonsets \
  --force \
  --grace-period=30 \
  --timeout=30s
echo "drain exit code: $?"
```

**Capture** the exact error message. It should name `demo-pdb` blocking the eviction with text like `Cannot evict pod as it would violate the pod's disruption budget`.

```bash
kubectl uncordon $NODE
kubectl apply -f lab-manifests/pdb.yaml        # revert to minAvailable: 2
```

### Step 6 — Why was the eviction allowed (or rejected)?

| Scenario | minAvailable | Ready Pods | Allowed disruptions | Result |
|---|---|---|---|---|
| Step 4 | 2 | 3 | 3 - 2 = 1 | Drain allowed |
| Step 5 | 3 | 3 | 3 - 3 = 0 | Drain blocked |

This is the EXACT same logic that protects Kafka brokers during a CFK rolling upgrade in Week 4.

## Troubleshooting Exercise

For each, predict the behavior before running, then run and confirm:

1. PDB `minAvailable: 2` on a 2-replica StatefulSet — can you drain a node hosting one Pod?
2. PDB `maxUnavailable: 1` on a 3-replica StatefulSet — equivalent to `minAvailable: 2`? Verify by comparing `ALLOWED DISRUPTIONS`.
3. Anti-affinity on a 2-worker cluster with `replicas: 3` — to test this, recreate kind with 2 workers (`kind delete cluster --name training` then re-create with 2 worker entries) — confirm demo-2 stays Pending. What event names the cause?
4. Add a taint `dedicated=demo:NoSchedule` to one worker + no toleration on the StatefulSet — what happens to existing demo-N Pods on that node? (Hint: nothing — taints don't evict existing Pods unless `NoExecute`.)
   ```bash
   kubectl taint nodes training-worker dedicated=demo:NoSchedule
   # ... observe ...
   kubectl taint nodes training-worker dedicated=demo:NoSchedule-   # remove (note trailing -)
   ```

## Deliverable — `deliverables/<you>/week01/tuesday.md`

1. **kind setup confirmation** — `kubectl get nodes` output showing 4-node cluster
2. **Initial Pod placement** — before anti-affinity (Pod → Node table)
3. **Placement after anti-affinity** — Pod → Node table again, plus the `Pending` result from scaling to 4 replicas
4. **PDB state** before and after each scenario (`kubectl get pdb`)
5. **Drain output** for both Step 4 (allowed) and Step 5 (blocked) — paste verbatim
6. **Your explanation** of why each drain was allowed or rejected, in your own words (1 paragraph)
7. **The CFK Connection** — 2-3 sentences about how this lab translates to Kafka broker survival during an OpenShift upgrade in Week 4

## Cleanup

Two options:

**Keep the cluster for later this week** (recommended — Week 1 Thursday's storage lab and Week 2 labs can reuse it):

```bash
kubectl delete statefulset demo
kubectl delete svc demo-headless
kubectl delete pdb demo-pdb
# Cluster stays running
```

**Tear down completely**:

```bash
kind delete cluster --name training
```

## Bootcamp environment plan

| Week | Topic | Environment |
|---|---|---|
| 1 | OpenShift Foundations | **kind** (this week) — `kubectl` instead of `oc`; Ingress in place of Route on Wed |
| 2 | OpenShift Operations | **kind** — install OLM / ArgoCD / Prometheus Operator manually via Helm |
| 3 | ROSA + AWS | **ROSA** — real AWS IAM / STS / OIDC / VPC are the day's subject matter |
| 4 | CFK | **ROSA** — Routes, SCC, OLM-managed CFK Operator, cert-manager + Keyfactor integration |
| 5 | Kafka Operations | **ROSA** — runs on the CFK installed in Week 4 |
| 6 | Flink + Multi-Region | **ROSA** — plus a second cluster (or DR region) for Wed-Fri cluster-link + MRC + DR drill |

Before Week 3 Monday, make sure your ROSA cluster is provisioned, `oc` is logged in, and you can `oc new-project <you>-training`.
