# Week 1 Monday — Lab: Cluster Inventory + First Deploy

**Time**: ~3 hours self-paced
**Prerequisites**: `oc` CLI installed, dev OpenShift cluster credentials, you've logged in once before today

## Hands-on Lab — see every component from `oc apply` to `Pod Ready`

Work in your own personal project. Substitute `<you>` with your username throughout.

```bash
# 1. log in to the dev cluster
oc login <dev-cluster-url> --username=<you>

# 2. create your training project (= namespace + RBAC + quota defaults)
oc new-project <you>-training

# 3. cluster inventory — see what you've got
oc get nodes -o wide
oc get pods -A -l app.kubernetes.io/component=apiserver       # the apiserver Pods running on master nodes
oc get pods -A -l app.kubernetes.io/component=etcd            # etcd Pods
oc get pods -A -l app.kubernetes.io/component=scheduler       # scheduler Pods
oc get pods -A -l app.kubernetes.io/component=controller-manager

# 4. deploy a single nginx Pod the old-school way
cat <<EOF | oc apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: nginx-pod-direct
  labels:
    app: nginx-pod-direct
spec:
  containers:
    - name: nginx
      image: nginx:1.27
      ports:
        - containerPort: 80
EOF

# 5. watch every step of the trace happen in real time (in another terminal)
oc get pods -w
oc get events --sort-by=.lastTimestamp
oc describe pod nginx-pod-direct
```

Now repeat — but via a Deployment. Watch how many more objects spring into existence:

```bash
oc create deployment nginx-via-deployment --image=nginx:1.27 --replicas=3
oc get deployment,replicaset,pod -l app=nginx-via-deployment
```

Question to answer in your runbook: **how many K8s objects does `oc create deployment` ACTUALLY create on your behalf?**

## Troubleshooting Exercise — break image pull

Make a Pod that can't pull its image:

```bash
cat <<EOF | oc apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: broken-image-pull
spec:
  containers:
    - name: c
      image: registry.example.com/this-image-does-not-exist:v999
EOF
```

Use the trace from this morning's diagram to investigate, in order:

1. Did the apiserver accept the Pod? (`oc get pod broken-image-pull`)
2. Did the scheduler bind it to a node? (`oc get pod broken-image-pull -o jsonpath='{.spec.nodeName}'`)
3. Did kubelet try to start it? (`oc describe pod broken-image-pull` → Events)
4. Where exactly did the chain break? (the `Failed` event will name it)
5. What's the Pod's `status.containerStatuses[0].state.waiting.reason`?

Then fix it: change the image to something pullable from the platform's Artifactory (`artifactory.example.com/...`) and re-apply.

Cleanup:

```bash
oc delete pod nginx-pod-direct broken-image-pull
oc delete deployment nginx-via-deployment
```

## Deliverable — submit before EOD

Create `deliverables/<you>/week01/monday.md` in this repo with:

1. **Cluster inventory section** — output of `oc get nodes -o wide` and the four `oc get pods -A -l ...` commands above
2. **The `oc create deployment` chain** — your answer to "how many K8s objects did `oc create deployment` create?" (list every Kind + name)
3. **Troubleshooting walk-through** — the exact step in the morning's diagram where `broken-image-pull` broke + the `oc describe` output that confirmed it
4. **Two real questions** that came up while doing the lab (no question is too basic — these become Tuesday's discussion seed)

Commit + push to your personal training branch before EOD.
