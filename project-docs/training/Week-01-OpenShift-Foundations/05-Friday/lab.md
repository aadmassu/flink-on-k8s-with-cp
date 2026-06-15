# Week 1 Friday — Lab: Break Things, Then Fix Them

**Time**: ~4 hours
**Theme**: every Friday for the next 5 weeks looks like this. Lean in.

## Setup

```bash
oc project <you>-training
```

You'll deploy a known-good baseline app, then a teammate (or this script) will break it. You apply the troubleshooting tree from this morning, find the layer that broke, fix it, and document everything.

## Baseline — a known-good app you'll break later

```bash
cat <<'EOF' | oc apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: troubleshoot-target
  labels: {app: tt}
spec:
  replicas: 2
  selector:
    matchLabels: {app: tt}
  template:
    metadata:
      labels: {app: tt}
    spec:
      containers:
        - name: nginx
          image: nginx:1.27
          ports: [{containerPort: 80}]
          readinessProbe:
            httpGet: {path: /, port: 80}
            periodSeconds: 5
          resources:
            requests: {cpu: 50m, memory: 64Mi}
            limits:   {cpu: 200m, memory: 128Mi}
---
apiVersion: v1
kind: Service
metadata:
  name: troubleshoot-target
spec:
  selector: {app: tt}
  ports: [{port: 80, targetPort: 80}]
---
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: troubleshoot-target
spec:
  host: tt-<you>.apps.<env>.ocp.example.com
  to: {kind: Service, name: troubleshoot-target}
  port: {targetPort: 80}
  tls: {termination: edge}
EOF

oc wait --for=condition=Available deployment/troubleshoot-target --timeout=60s
curl -sk https://tt-<you>.apps.<env>.ocp.example.com/ | head -3
```

Now work through the 5 break-fix exercises. **For each, predict the symptom BEFORE you break it, then verify.**

---

## Break 1 — bad image

```bash
oc set image deployment/troubleshoot-target nginx=nginx:totally-not-a-real-tag
```

- Predict: where will this fail in the decision tree?
- Verify: `oc get pod`, `oc describe pod`, `oc get events`
- Fix: revert with `oc set image deployment/troubleshoot-target nginx=nginx:1.27`
- Document: which Event message most directly named the failure?

---

## Break 2 — resource request bigger than any node

```bash
oc patch deployment/troubleshoot-target --type='strategic' -p='{"spec":{"template":{"spec":{"containers":[{"name":"nginx","resources":{"requests":{"memory":"500Gi"}}}]}}}}'
```

- Predict: what `oc get pod` STATUS will you see?
- Verify: `oc describe pod` — what does the scheduler Events say?
- Fix: revert with `oc patch deployment/troubleshoot-target --type='strategic' -p='{"spec":{"template":{"spec":{"containers":[{"name":"nginx","resources":{"requests":{"memory":"64Mi"}}}]}}}}'`
- Document: which layer of the tree caught it?

---

## Break 3 — readiness probe fails

```bash
oc set probe deployment/troubleshoot-target --readiness --get-url=http://:80/this-path-does-not-exist
```

- Predict: will the Pod show `Ready` or not? What happens to the Route?
- Verify: `oc get pod`, then `curl -sk` the Route
- Document: `oc get endpoints` — is the failed Pod still in the endpoints list?
- Fix: revert with `oc set probe deployment/troubleshoot-target --readiness --remove`

---

## Break 4 — Route to a Service with no endpoints

```bash
oc patch svc troubleshoot-target -p '{"spec":{"selector":{"app":"WRONG"}}}'
```

- Predict: what does the user see when they hit the Route?
- Verify: `curl -sk https://tt-<you>.apps.<env>.ocp.example.com/`
- Document: HAProxy's response status code; explain to a teammate why
- Fix: `oc patch svc troubleshoot-target -p '{"spec":{"selector":{"app":"tt"}}}'`

---

## Break 5 — PVC stuck Pending (use yesterday's Pod template)

```bash
cat <<EOF | oc apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: friday-broken-pvc
spec:
  storageClassName: nonexistent-storage-class
  accessModes: ["ReadWriteOnce"]
  resources: {requests: {storage: 1Gi}}
---
apiVersion: v1
kind: Pod
metadata:
  name: friday-stuck-pod
spec:
  containers:
    - name: c
      image: nginx:1.27
      volumeMounts: [{name: d, mountPath: /data}]
  volumes:
    - name: d
      persistentVolumeClaim: {claimName: friday-broken-pvc}
EOF
```

- Predict: what does `oc get pod friday-stuck-pod` show as STATUS?
- Verify: walk the decision tree top-down — start with `get pod`, work down
- Document: which `oc describe` output named the actual failure (PVC, not Pod, not container)?
- Fix: delete the broken PVC + Pod

```bash
oc delete pod friday-stuck-pod
oc delete pvc friday-broken-pvc
```

---

## Deliverable — your personal troubleshooting checklist

This is the most important deliverable of Week 1. Create `deliverables/<you>/week01/friday-troubleshooting-checklist.md`:

**Section 1 — the checklist**

Write down — in YOUR words, not mine — the first 3–5 commands you'll run when someone says "my app isn't working on OpenShift." Each command has a specific question it answers. Order matters; this is your decision tree from this morning, but personalized.

Example shape (replace with your own):

```
1. oc get pod <name>                  →   does the Pod exist? what's its STATUS?
2. oc describe pod <name>             →   most recent Events; explains 80% of failures
3. oc logs <name>                     →   what did the app say?
4. oc logs <name> --previous          →   what did the app say BEFORE it crashed?
5. oc get events --sort-by=...        →   anything cluster-wide that's relevant?
```

**Section 2 — the 5 break-fix exercises** — for each, document: the symptom you saw, which step in the checklist identified the layer, the fix you applied, and the Event/log message that was the smoking gun.

**Section 3 — three new commands** you discovered today that weren't in the morning discussion. (Engineers always find one or two.)

**Section 4 — three blockers / questions** you still have. (Becomes Week 2 Monday's discussion.)

## Cleanup

```bash
oc delete deployment troubleshoot-target
oc delete svc troubleshoot-target
oc delete route troubleshoot-target
```

**Submit your week-01-runbook.md by EOD per the Week 1 README. The Friday checklist is its centerpiece.**
