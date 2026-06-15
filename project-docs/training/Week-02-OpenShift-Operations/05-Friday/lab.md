# Week 2 Friday — Lab: Break Everything with Quota Exhaustion

**Time**: ~4 hours
**Theme**: this is THE DEV CFK install story from 2026-04 made into a hands-on exercise. By EOD engineers should never confuse a quota failure for any other admission failure again.

## Setup — give yourself a very tight quota first

```bash
oc project <you>-training

# Set a deliberately tight ResourceQuota so admission failures are easy to trigger
cat <<EOF | oc apply -f -
apiVersion: v1
kind: ResourceQuota
metadata:
  name: training-quota
spec:
  hard:
    requests.cpu:    2
    requests.memory: 2Gi
    limits.cpu:      4
    limits.memory:   4Gi
    requests.storage: 4Gi
    persistentvolumeclaims: 3
    pods: 6
EOF

# Plus a LimitRange that supplies sensible defaults so quota accounting works
cat <<EOF | oc apply -f -
apiVersion: v1
kind: LimitRange
metadata:
  name: training-limits
spec:
  limits:
    - type: Container
      default:
        cpu:    200m
        memory: 256Mi
      defaultRequest:
        cpu:    100m
        memory: 128Mi
      max:
        cpu:    2
        memory: 2Gi
EOF

# Inspect what you just set
oc describe quota training-quota
oc describe limitrange training-limits
```

## Hands-on Lab — fit the right number of Pods, fail the next one

```bash
# 1. Deploy nginx with 5 replicas — quota allows 6 pods, each gets default 100m cpu
oc create deployment nginx --image=nginx:1.27 --replicas=5

oc get pods -l app=nginx              # all 5 should land
oc describe quota training-quota      # used.pods = 5, used.requests.cpu = 500m (5 × 100m default)

# 2. Scale to 6 — should still fit (cap is 6 pods, 1 left = used 6/6)
oc scale deployment nginx --replicas=6
oc get pods -l app=nginx              # all 6 should land
oc describe quota training-quota      # used.pods = 6

# 3. Scale to 7 — FIRST failure (pod cap)
oc scale deployment nginx --replicas=7
oc describe replicaset -l app=nginx | tail -10   # what's the Events message?
oc describe quota training-quota                 # used.pods still 6 — 7th was rejected at admission
```

In your runbook: paste the exact error message. It should mention `exceeded quota: training-quota, requested: pods=1, used: pods=6, limited: pods=6`.

## Hands-on Lab Part 2 — exhaust CPU (the DEV story)

```bash
# Reset to 0
oc scale deployment nginx --replicas=0

# Create a Pod that asks for MORE CPU than the quota's CPU cap
cat <<EOF | oc apply -f -
apiVersion: v1
kind: Pod
metadata: {name: hungry}
spec:
  containers:
    - name: c
      image: nginx:1.27
      resources:
        requests:
          cpu:    "3"    # 3 CPU; quota cap is 2
          memory: 1Gi
EOF

oc describe pod hungry           # admitted? rejected? (rejected — won't even reach the kubelet)
oc get events --sort-by=.lastTimestamp | tail -10
```

This is the CFK init-container ~500m × 6 pods = 3 CPU pattern (runbook A3). With a 2-CPU quota, the 6th pod's admission would fail this way — only 4 fit.

## Hands-on Lab Part 3 — exhaust PVC storage (the OTHER DEV story)

```bash
# Create three PVCs, 1Gi each — total 3Gi, under the 4Gi quota
for i in 0 1 2; do
  cat <<EOF | oc apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata: {name: data-$i}
spec:
  accessModes: ["ReadWriteOnce"]
  resources:
    requests:
      storage: 1Gi
EOF
done

oc get pvc
oc describe quota training-quota   # used.persistentvolumeclaims=3, used.requests.storage=3Gi

# Now create a 4th PVC requesting 2Gi → both PVC count cap (3) AND storage cap (4Gi) fail
cat <<EOF | oc apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata: {name: data-overflow}
spec:
  accessModes: ["ReadWriteOnce"]
  resources:
    requests:
      storage: 2Gi
EOF
```

In your runbook: paste the error message. Note which quota dimension the apiserver reports (it'll be the first one that fails — pvc count OR storage size).

## Hands-on Lab Part 4 — diagnose by reading status

```bash
# A StatefulSet hitting quota — controllers retry, error lives at the ReplicaSet/StatefulSet level
cat <<EOF | oc apply -f -
apiVersion: apps/v1
kind: StatefulSet
metadata: {name: hitwall}
spec:
  serviceName: hitwall
  replicas: 4
  selector: {matchLabels: {app: hitwall}}
  template:
    metadata: {labels: {app: hitwall}}
    spec:
      containers:
        - name: c
          image: nginx:1.27
          resources:
            requests: {cpu: 500m, memory: 256Mi}
EOF

oc get pods -l app=hitwall            # how many of the 4 came up?
oc describe statefulset hitwall | tail -20   # Events at the bottom — should show the quota miss
```

Read the Events output: what specifically did the StatefulSet controller report?

## Troubleshooting Exercise — fix WITHOUT raising the quota (simulate "platform team can't help today")

The point: real CFK quota issues in production took weeks to raise. While waiting, engineers had to fit the workload to the existing quota.

Two strategies:
1. **Lower per-Pod requests** — reduce CPU/memory requests so more fit (works for stateless workloads; not always for Kafka)
2. **Reduce replicas** — set Connect + ControlCenter to `replicas: 0` (the DEV mitigation while quota was being raised — see runbook A3)

Apply one of those to the StatefulSet above so 4 pods CAN fit under the existing quota.

## Deliverable — `deliverables/<you>/week02/friday.md`

1. **Four error messages** — one from each break (pod cap, cpu cap, PVC cap, storage cap). Pick the most informative phrasing.
2. **A diagnostic command sequence** — "show me, in 4 commands, that a quota is the bottleneck and exactly which dimension." (Hint: `oc describe quota`, `oc describe rs`, `oc get events`, `oc top pod` for the runtime side)
3. **The tracker 2.5 tie-in** — in 3 sentences, explain what DEV's ResourceQuota was set to before the raise, what CFK actually needed (use runbook A3 init-container floor as evidence), and why the symptom looked like "kafka pods stuck Pending" without `exceeded quota` being obvious
4. **Updated personal troubleshooting checklist v2** — append the quota-failure recognition pattern from today
5. Two questions

Cleanup:

```bash
oc delete deployment nginx --ignore-not-found
oc delete pod hungry --ignore-not-found
oc delete statefulset hitwall --ignore-not-found
oc delete pvc -l "kubernetes.io/created-for/pvc.name" --ignore-not-found
oc delete pvc data-0 data-1 data-2 --ignore-not-found
oc delete quota training-quota
oc delete limitrange training-limits
```

**End-of-week deliverable reminder**: per the Week 2 README, commit your full `week-02-runbook.md` covering all 5 days. The Friday troubleshooting checklist v2 is its centerpiece.
