# Week 1 Tuesday — Lab: StatefulSet + Anti-Affinity + PDB + Drain

**Time**: ~4 hours
**Prerequisite**: Lesson 1-5 from morning discussion

## Goal

Build a 3-replica StatefulSet that survives a node drain — then break it by tightening the PDB and watching the drain block. The exercise sticks because you can see the rules cause + reject the eviction in real time.

## Hands-on Lab

### Step 1 — Deploy a 3-replica StatefulSet (no extras yet)

```bash
oc project <you>-training

cat <<EOF | oc apply -f -
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: demo
spec:
  serviceName: demo-headless
  replicas: 3
  selector:
    matchLabels:
      app: demo
  template:
    metadata:
      labels:
        app: demo
    spec:
      containers:
        - name: app
          image: registry.access.redhat.com/ubi9/ubi-minimal
          command: ["sh", "-c", "while true; do sleep 30; done"]
          resources:
            requests: { cpu: 100m, memory: 64Mi }
            limits:   { cpu: 200m, memory: 128Mi }
---
apiVersion: v1
kind: Service
metadata:
  name: demo-headless
spec:
  clusterIP: None
  selector: { app: demo }
  ports:
    - port: 80
EOF

oc get pods -l app=demo -o wide -w &
sleep 30 ; jobs %1 && kill %1 2>/dev/null
```

**Capture**: which node hosts each of demo-0 / demo-1 / demo-2. Right now there's no anti-affinity — they MAY end up on the same node depending on the scheduler.

### Step 2 — Apply pod anti-affinity (Lesson 3)

```bash
oc patch statefulset demo --type=merge -p '
spec:
  template:
    spec:
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            - labelSelector:
                matchLabels:
                  app: demo
              topologyKey: kubernetes.io/hostname
'

# Force rolling update so existing Pods re-spread
oc rollout restart statefulset/demo
oc rollout status statefulset/demo --timeout=300s

oc get pods -l app=demo -o wide
```

**Capture**: NOW each Pod should be on a DIFFERENT node. If your training cluster has only 2 nodes, demo-2 will be stuck Pending — that's expected; describe the Pod to see the "didn't match Pod anti-affinity" event.

### Step 3 — Apply a PDB (Lesson 5)

```bash
cat <<EOF | oc apply -f -
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: demo-pdb
spec:
  minAvailable: 2
  selector:
    matchLabels:
      app: demo
EOF

oc get pdb demo-pdb
```

**Capture**: `ALLOWED DISRUPTIONS` should be `1` (out of 3, keeping minAvailable=2).

### Step 4 — Drain a node and observe

Pick the node hosting demo-1:

```bash
NODE=$(oc get pod demo-1 -o jsonpath='{.spec.nodeName}')
echo "Will drain $NODE"

# In a second terminal, watch:
#   oc get pods -l app=demo -o wide -w
#   oc get pdb demo-pdb -w

oc adm drain $NODE \
  --delete-emptydir-data \
  --ignore-daemonsets \
  --force \
  --grace-period=30 \
  --timeout=120s
```

**Expected behavior**:
- PDB allows the eviction (1 ≤ allowed disruptions).
- demo-1 evicts.
- demo-1's PVC follows it to the new node (rebound to whatever node K8s picks under the anti-affinity constraint).
- Drain completes.

```bash
# Cleanup — uncordon the node so it's schedulable again
oc adm uncordon $NODE

# Confirm all 3 Pods are Running
oc get pods -l app=demo -o wide
```

### Step 5 — Break the PDB on purpose

Tighten the PDB so a drain is impossible:

```bash
oc patch pdb demo-pdb --type=merge -p '{"spec":{"minAvailable":3}}'

oc get pdb demo-pdb
# ALLOWED DISRUPTIONS should now be 0

NODE=$(oc get pod demo-1 -o jsonpath='{.spec.nodeName}')

# This drain should HANG / FAIL — PDB blocks the eviction
timeout 60 oc adm drain $NODE \
  --delete-emptydir-data \
  --ignore-daemonsets \
  --force \
  --grace-period=30 \
  --timeout=30s
echo "drain exit code: $?"
```

**Capture** the exact error message. It should explicitly name the PDB blocking the eviction.

```bash
oc adm uncordon $NODE
oc patch pdb demo-pdb --type=merge -p '{"spec":{"minAvailable":2}}'
```

### Step 6 — Why was the eviction allowed (or rejected)?

Walk through the logic for both cases:

| Scenario | minAvailable | Ready pods | Allowed disruptions | Result |
|---|---|---|---|---|
| Step 4 | 2 | 3 | 3 - 2 = 1 | Drain allowed |
| Step 5 | 3 | 3 | 3 - 3 = 0 | Drain blocked |

This is the EXACT same logic that protects Kafka brokers during a CFK rolling upgrade in Week 4.

## Troubleshooting Exercise

For each, predict the behavior before running, then run and confirm:

1. PDB `minAvailable: 2` on a 2-replica StatefulSet — can you drain a node hosting one Pod?
2. PDB `maxUnavailable: 1` on a 3-replica StatefulSet — equivalent to `minAvailable: 2`? Verify.
3. Anti-affinity on a 2-node cluster with `replicas: 3` — what's demo-2's status? What event names the cause?
4. Add a taint `dedicated=demo:NoSchedule` to one node + no toleration on the StatefulSet — what happens to existing demo-N Pods on that node? (Hint: nothing — taints don't evict existing Pods unless NoExecute.)

## Deliverable — `deliverables/<you>/week01/tuesday.md`

1. **Initial Pod placement** — before anti-affinity (Pod → Node table)
2. **Placement after anti-affinity** — Pod → Node table again, plus what happens to demo-2 if your cluster has < 3 nodes
3. **PDB state** before and after each scenario (`oc get pdb -o wide`)
4. **Drain output** for both Step 4 (allowed) and Step 5 (blocked) — paste verbatim
5. **Your explanation** of why each drain was allowed or rejected, in your own words (1 paragraph)
6. **The CFK Connection** — write 2-3 sentences about how this lab translates to Kafka broker survival during an OpenShift upgrade

Cleanup:

```bash
oc delete statefulset demo
oc delete svc demo-headless
oc delete pdb demo-pdb
```
