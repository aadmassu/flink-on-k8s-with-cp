# Week 1 Thursday — Lab: Persistent Storage Across Pod Restarts

## Goal

Prove to yourself, hands-on, that:

1. A PVC backed by a StorageClass survives a Pod delete-and-recreate.
2. A StatefulSet gives each replica its **own** PVC and that pairing is sticky across restarts.
3. The chain Pod → PVC → PV → StorageClass → backing storage is the same regardless of whether the backing store is EBS in a real cluster or a directory on your laptop.

## Pick your local cluster

Run the lab on **one** of the two below. Both work. Pick whichever you already have:

### Option A — kind (single laptop, no OpenShift)

```bash
kind create cluster --name training --config ../../lab-cluster/00-kind-cluster-config.yaml
kubectl config use-context kind-training
```

kind ships with the `rancher.io/local-path` provisioner enabled by default — every PVC's data lands in a directory on the host filesystem (inside the kind node container, mounted from `/var/lib/rancher/k3s/...`). Tear down the cluster and the data goes with it.

### Option B — OpenShift Local (CRC) or any `oc`-connected cluster

```bash
crc start                          # or: oc login <your-cluster>
oc new-project storage-lab
```

CRC ships with `crc-csi-hostpath-provisioner` as the default StorageClass. Same hostpath idea as kind — data lives on a directory inside the CRC VM.

> **Throughout this lab, every command is given in both `oc` and `kubectl` forms.** Run only the one that matches the cluster you started above. `oc` is a superset of `kubectl`, so the `kubectl` form will also work on OpenShift if you prefer.

## Step 0 — Carve out a StorageClass you control

The lab-cluster ships a symbolic StorageClass named **`ssd`** that wraps whatever local provisioner the cluster offers. You'll use the same one here so the manifests look identical to a real-cluster install.

Apply it:

```bash
# oc
oc apply -f ../../lab-cluster/02-storageclass-ssd.yaml

# kubectl
kubectl apply -f ../../lab-cluster/02-storageclass-ssd.yaml
```

The file is intentionally small:

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ssd
provisioner: rancher.io/local-path        # <-- swap to match your cluster
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: false
```

**Adapt the `provisioner` field to your environment:**

| Cluster you're on | Set `provisioner` to | Notes |
|---|---|---|
| kind (default) | `rancher.io/local-path` | Ships built in |
| OpenShift Local / CRC | `kubevirt.io.hostpath-provisioner` | Default in CRC |
| Minikube | `k8s.io/minikube-hostpath` | Default in Minikube |
| Docker Desktop k8s | `docker.io/hostpath` | Single-node hostpath |
| Real EKS | `ebs.csi.aws.com` | Pick a `type: gp3` parameter block |
| Real AKS | `disk.csi.azure.com` | Pick `skuname: Premium_LRS` |
| Real GKE | `pd.csi.storage.gke.io` | Pick `type: pd-ssd` |
| Real ROSA | `ebs.csi.aws.com` | Same EBS as EKS |

You can also skip applying `ssd` entirely and use whichever class is already marked default on your cluster — every PVC in this lab omits `storageClassName` for that reason, except the final break-it-on-purpose step. List what's available:

```bash
# oc
oc get storageclass

# kubectl
kubectl get storageclass
```

The class annotated `(default)` is what your PVCs will use if you don't ask for a specific one.

## Step 1 — Single Pod, single PVC, prove data survives restart

Work in a fresh namespace.

```bash
# oc
oc new-project storage-lab || oc project storage-lab

# kubectl
kubectl create namespace storage-lab --dry-run=client -o yaml | kubectl apply -f -
kubectl config set-context --current --namespace=storage-lab
```

### Create a PVC

```bash
# oc
oc apply -f - <<'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-data
spec:
  accessModes: ["ReadWriteOnce"]
  resources:
    requests:
      storage: 1Gi
  # storageClassName: ssd   # uncomment to force a specific class; otherwise default is used
EOF

# kubectl
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-data
spec:
  accessModes: ["ReadWriteOnce"]
  resources:
    requests:
      storage: 1Gi
EOF
```

### Confirm the PVC is `Pending` (it should be — `WaitForFirstConsumer`)

```bash
# oc
oc get pvc my-data

# kubectl
kubectl get pvc my-data
```

`STATUS=Pending` is expected. With `volumeBindingMode: WaitForFirstConsumer` the binder waits for a Pod before carving a PV. Tuesday's lesson said "the scheduler runs lazily" — this is the storage-layer version of the same idea.

### Create a writer Pod that mounts the PVC

```bash
# oc
oc apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: write-data
spec:
  containers:
    - name: writer
      image: busybox:1.36
      command: ["sh","-c","echo hello-from-write-data-at-$(date) >> /data/log.txt; sleep 3600"]
      volumeMounts:
        - {name: data, mountPath: /data}
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: my-data
EOF

# kubectl
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: write-data
spec:
  containers:
    - name: writer
      image: busybox:1.36
      command: ["sh","-c","echo hello-from-write-data-at-$(date) >> /data/log.txt; sleep 3600"]
      volumeMounts:
        - {name: data, mountPath: /data}
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: my-data
EOF
```

Wait for it and inspect both the PVC binding and what was written:

```bash
# oc
oc wait --for=condition=Ready pod/write-data --timeout=60s
oc get pvc my-data                                  # now Bound
oc get pv $(oc get pvc my-data -o jsonpath='{.spec.volumeName}')
oc exec write-data -- cat /data/log.txt

# kubectl
kubectl wait --for=condition=Ready pod/write-data --timeout=60s
kubectl get pvc my-data
kubectl get pv $(kubectl get pvc my-data -o jsonpath='{.spec.volumeName}')
kubectl exec write-data -- cat /data/log.txt
```

Capture the PV name. That's the cluster-scoped resource the CSI driver just provisioned for you. On kind, look inside the kind node container to see where the data lives on the host:

```bash
docker exec -it training-control-plane sh -c 'find /var/lib/rancher -name log.txt -print 2>/dev/null'
```

### Delete the writer Pod (NOT the PVC) and bring up a reader

```bash
# oc
oc delete pod write-data
oc apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: read-data
spec:
  containers:
    - name: reader
      image: busybox:1.36
      command: ["sh","-c","echo READ:; cat /data/log.txt; sleep 3600"]
      volumeMounts:
        - {name: data, mountPath: /data}
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: my-data
EOF
oc wait --for=condition=Ready pod/read-data --timeout=60s
oc logs read-data

# kubectl
kubectl delete pod write-data
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: read-data
spec:
  containers:
    - name: reader
      image: busybox:1.36
      command: ["sh","-c","echo READ:; cat /data/log.txt; sleep 3600"]
      volumeMounts:
        - {name: data, mountPath: /data}
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: my-data
EOF
kubectl wait --for=condition=Ready pod/read-data --timeout=60s
kubectl logs read-data
```

`READ:` followed by the writer's `hello-from-write-data-at-...` line. That's the entire point of a PVC — **data survives Pod death**. The Pod was destroyed, the PVC was not, the PV was not, the directory on the host was not, the new Pod re-mounted the same chain.

## Step 2 — StatefulSet PVCs across replicas

Now prove that a StatefulSet hands each replica its own sticky PVC — the property CFK relies on to keep `broker.id`s aligned with their log directories.

```bash
# oc
oc apply -f - <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: writer-svc
spec:
  clusterIP: None
  selector: {app: writer}
  ports: [{port: 80}]
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: writer
spec:
  serviceName: writer-svc
  replicas: 3
  selector:
    matchLabels: {app: writer}
  template:
    metadata:
      labels: {app: writer}
    spec:
      containers:
        - name: c
          image: busybox:1.36
          command: ["sh","-c","echo $HOSTNAME-wrote-here > /data/who.txt; sleep 3600"]
          volumeMounts:
            - {name: data, mountPath: /data}
  volumeClaimTemplates:
    - metadata: {name: data}
      spec:
        accessModes: ["ReadWriteOnce"]
        resources:
          requests: {storage: 100Mi}
EOF

# kubectl
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: writer-svc
spec:
  clusterIP: None
  selector: {app: writer}
  ports: [{port: 80}]
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: writer
spec:
  serviceName: writer-svc
  replicas: 3
  selector:
    matchLabels: {app: writer}
  template:
    metadata:
      labels: {app: writer}
    spec:
      containers:
        - name: c
          image: busybox:1.36
          command: ["sh","-c","echo $HOSTNAME-wrote-here > /data/who.txt; sleep 3600"]
          volumeMounts:
            - {name: data, mountPath: /data}
  volumeClaimTemplates:
    - metadata: {name: data}
      spec:
        accessModes: ["ReadWriteOnce"]
        resources:
          requests: {storage: 100Mi}
EOF
```

Watch PVCs come up — one per replica, named `data-writer-0`, `data-writer-1`, `data-writer-2`:

```bash
# oc
oc get pvc

# kubectl
kubectl get pvc
```

Confirm each Pod sees ONLY its own data:

```bash
# oc
for i in 0 1 2; do
  echo "--- writer-$i ---"
  oc exec writer-$i -- cat /data/who.txt
done

# kubectl
for i in 0 1 2; do
  echo "--- writer-$i ---"
  kubectl exec writer-$i -- cat /data/who.txt
done
```

Each Pod reports its own hostname. That's the StatefulSet identity guarantee from Tuesday made concrete with storage.

### Prove the PVC is sticky across Pod delete

Kill `writer-1` and watch the StatefulSet recreate it. The replacement reads back the same `/data/who.txt` because the PVC was never deleted.

```bash
# oc
oc delete pod writer-1
oc wait --for=condition=Ready pod/writer-1 --timeout=120s
oc exec writer-1 -- cat /data/who.txt

# kubectl
kubectl delete pod writer-1
kubectl wait --for=condition=Ready pod/writer-1 --timeout=120s
kubectl exec writer-1 -- cat /data/who.txt
```

The file still says `writer-1-wrote-here`. The StatefulSet controller re-created `writer-1` (same name), the Pod referenced `data-writer-1` (same PVC), the PVC was still bound to the same PV (same backing directory). **This is exactly the chain CFK relies on for Kafka brokers to keep their `broker.id` ↔ log-dir mapping intact across pod restarts.**

## Step 3 — Troubleshooting: break the storage chain on purpose

### Break 1 — PVC stuck `Pending` due to unknown StorageClass

```bash
# oc
oc apply -f - <<'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: broken-pvc
spec:
  storageClassName: this-class-does-not-exist
  accessModes: ["ReadWriteOnce"]
  resources:
    requests: {storage: 1Gi}
EOF
oc get pvc broken-pvc
oc describe pvc broken-pvc        # read the Events section

# kubectl
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: broken-pvc
spec:
  storageClassName: this-class-does-not-exist
  accessModes: ["ReadWriteOnce"]
  resources:
    requests: {storage: 1Gi}
EOF
kubectl get pvc broken-pvc
kubectl describe pvc broken-pvc
```

Capture the exact event message. It will say something like `storageclass.storage.k8s.io "this-class-does-not-exist" not found`.

### Break 2 — Pod stuck `Pending` because its PVC is unbound

```bash
# oc
oc apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: stuck-pod
spec:
  containers:
    - name: c
      image: busybox:1.36
      command: ["sleep","3600"]
      volumeMounts: [{name: d, mountPath: /data}]
  volumes:
    - name: d
      persistentVolumeClaim:
        claimName: broken-pvc
EOF
oc describe pod stuck-pod

# kubectl
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: stuck-pod
spec:
  containers:
    - name: c
      image: busybox:1.36
      command: ["sleep","3600"]
      volumeMounts: [{name: d, mountPath: /data}]
  volumes:
    - name: d
      persistentVolumeClaim:
        claimName: broken-pvc
EOF
kubectl describe pod stuck-pod
```

Read the FailedScheduling event. Walk the chain from the morning's diagram: which layer broke? (Bottom — StorageClass missing → PVC can't provision → PV doesn't exist → Pod can't schedule.)

### Break 3 — Access mode mismatch

```bash
# oc
oc apply -f - <<'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: rwx-pvc
spec:
  accessModes: ["ReadWriteMany"]
  resources:
    requests: {storage: 100Mi}
EOF
oc describe pvc rwx-pvc

# kubectl
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: rwx-pvc
spec:
  accessModes: ["ReadWriteMany"]
  resources:
    requests: {storage: 100Mi}
EOF
kubectl describe pvc rwx-pvc
```

Hostpath / local-path provisioners only support `ReadWriteOnce`. The PVC will stay Pending with a message about no matching PV — the same failure mode CFK would hit if you accidentally asked an EBS-only cluster for RWX.

## Deliverable — `deliverables/<you>/week01/thursday.md`

1. **The data-survives-Pod-restart trace** — the `oc exec` / `kubectl exec` output showing the second Pod read the first Pod's data
2. **The StatefulSet PVC-per-Pod evidence** — three different outputs from `kubectl exec writer-N -- cat /data/who.txt`
3. **The sticky-PVC-across-delete trace** — output showing `writer-1`'s recreated Pod still reads `writer-1-wrote-here`
4. **Why Kafka uses StatefulSet PVCs** — 2–3 sentences referencing your evidence above. Mention `broker.id` stability and what would break if you used a Deployment instead.
5. **The three broken-chain walks** — for each, the exact event message that explained the failure and which diagram layer broke
6. **One paragraph on local lab vs. real cluster** — what stayed the same in the chain, what would change if you ran this on EKS / AKS / GKE / ROSA. Mention the provisioner field and `volumeBindingMode`.
7. Two questions you still have

## Cleanup

```bash
# oc
oc delete pod read-data stuck-pod --ignore-not-found
oc delete pvc my-data broken-pvc rwx-pvc --ignore-not-found
oc delete statefulset writer
oc delete pvc -l app=writer            # PVCs are NOT GC'd by the StatefulSet
oc delete svc writer-svc
oc delete project storage-lab          # or: oc delete namespace storage-lab

# kubectl
kubectl delete pod read-data stuck-pod --ignore-not-found
kubectl delete pvc my-data broken-pvc rwx-pvc --ignore-not-found
kubectl delete statefulset writer
kubectl delete pvc -l app=writer
kubectl delete svc writer-svc
kubectl delete namespace storage-lab
```

If you applied the `ssd` StorageClass and you don't plan to use it again:

```bash
# oc
oc delete storageclass ssd

# kubectl
kubectl delete storageclass ssd
```

If you spun up a kind cluster just for this lab, the cheapest cleanup is:

```bash
kind delete cluster --name training
```

That deletes the cluster *and* every PVC's backing directory on the host in one shot. Useful when you want a clean slate before tomorrow.
