# Week 1 Tuesday — Lab: Stateless vs Stateful Workloads

**Time**: ~3 hours

## Hands-on Lab — Deployment vs StatefulSet, side by side

Work in `<you>-training`.

```bash
# 1. Deploy nginx as a Deployment (stateless)
cat <<EOF | oc apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx
spec:
  replicas: 3
  selector:
    matchLabels: {app: nginx}
  template:
    metadata:
      labels: {app: nginx}
    spec:
      containers:
        - name: nginx
          image: nginx:1.27
EOF

# 2. Deploy redis as a StatefulSet (with PVC template)
# You need a headless Service first (for stable DNS)
cat <<EOF | oc apply -f -
apiVersion: v1
kind: Service
metadata:
  name: redis-headless
spec:
  clusterIP: None
  selector: {app: redis}
  ports:
    - port: 6379
      name: redis
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: redis
spec:
  serviceName: redis-headless
  replicas: 3
  selector:
    matchLabels: {app: redis}
  template:
    metadata:
      labels: {app: redis}
    spec:
      containers:
        - name: redis
          image: redis:7
          ports:
            - containerPort: 6379
          volumeMounts:
            - name: data
              mountPath: /data
  volumeClaimTemplates:
    - metadata:
        name: data
      spec:
        accessModes: ["ReadWriteOnce"]
        resources:
          requests:
            storage: 1Gi
EOF

# 3. Observe pod names + IPs
oc get pods -l app=nginx -o wide
oc get pods -l app=redis -o wide
oc get pvc

# 4. Delete one of each and watch what happens
oc delete pod nginx-<some-hash>
oc delete pod redis-0
# Watch:
oc get pods -w
```

Answer in your runbook: **what's different about the replacement Pod's name in each case? Why?**

## Troubleshooting Exercise — break the StatefulSet ordering

```bash
# Force redis-1 into CrashLoopBackOff by giving it a bad image
oc set image statefulset/redis redis=redis:doesnotexist
oc get pods -l app=redis
```

Observe: even though redis-0 is healthy, redis-2 is stopped during the rolling update because redis-1 won't reach Ready.

Investigate using the morning's diagram trace:
1. What's the StatefulSet's `updateStrategy`? (`oc get statefulset redis -o yaml | grep -A3 updateStrategy`)
2. Why doesn't K8s skip redis-1 and update redis-2?
3. Roll back: `oc set image statefulset/redis redis=redis:7` and watch the recovery

## Deliverable — `deliverables/<you>/week01/tuesday.md`

1. **Side-by-side observation table** — for nginx Deployment and redis StatefulSet, list: Pod names, IPs after delete-and-recreate, whether each Pod has a PVC, what survives a Pod delete
2. **Why Kafka uses StatefulSet** — explain in your own words, in 3 sentences max. (Reference: broker.id stability, log data, DNS-based broker discovery)
3. **The blocked update** — what was the failure mode of the redis-1 update? What command did you use to unblock?
4. Two questions that came up

Cleanup before EOD:

```bash
oc delete statefulset redis
oc delete pvc -l app=redis     # critical — StatefulSet does NOT garbage-collect its PVCs
oc delete svc redis-headless
oc delete deployment nginx
```

That `oc delete pvc -l app=redis` step is itself a Week-1 lesson: **deleting a StatefulSet does NOT delete its PVCs by default.** A real CFK uninstall in prod follows the same rule — be careful.
