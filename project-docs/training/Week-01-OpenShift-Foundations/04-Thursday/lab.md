# Week 1 Thursday — Lab: Persistent Storage Across Pod Restarts

**Time**: ~3 hours

## Hands-on Lab — survive a Pod restart with data intact

```bash
oc project <you>-training

# 1. List the available StorageClasses on the cluster
oc get storageclass

# 2. Create a PVC explicitly
cat <<EOF | oc apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-data
spec:
  accessModes: ["ReadWriteOnce"]
  resources:
    requests:
      storage: 1Gi
  # storageClassName: <your-cluster's-default-storage-class>  # leave commented to use default
EOF

# 3. Watch the binding happen
oc get pvc my-data -w &
sleep 5 ; jobs %1 && kill %1 2>/dev/null

# 4. Confirm a PV got created and bound to your PVC
oc get pvc my-data
oc get pv | grep $(oc get pvc my-data -o jsonpath='{.spec.volumeName}')

# 5. Create a Pod that mounts the PVC and writes data
cat <<EOF | oc apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: write-data
spec:
  containers:
    - name: c
      image: busybox:1.36
      command: ["sh","-c","echo 'hello from $HOSTNAME at $(date)' >> /data/log.txt; sleep 3600"]
      volumeMounts:
        - name: data
          mountPath: /data
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: my-data
EOF

# Wait for it, then read what was written
oc wait --for=condition=Ready pod/write-data --timeout=60s
oc exec write-data -- cat /data/log.txt

# 6. Kill the Pod (NOT the PVC), and create a new Pod that mounts the SAME PVC
oc delete pod write-data
cat <<EOF | oc apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: read-data
spec:
  containers:
    - name: c
      image: busybox:1.36
      command: ["sh","-c","echo 'I am $HOSTNAME; previous data:'; cat /data/log.txt; sleep 3600"]
      volumeMounts:
        - name: data
          mountPath: /data
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: my-data
EOF

oc wait --for=condition=Ready pod/read-data --timeout=60s
oc logs read-data
```

The second Pod should print the first Pod's `hello from write-data` log line. That's the whole point of a PVC — data survives Pod death.

## Hands-on Lab Part 2 — StatefulSet PVCs across replicas

```bash
# Deploy a 3-replica StatefulSet, each replica gets its own PVC
cat <<EOF | oc apply -f -
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
          command: ["sh","-c","echo \"\$HOSTNAME wrote here\" > /data/who.txt; sleep 3600"]
          volumeMounts:
            - {name: data, mountPath: /data}
  volumeClaimTemplates:
    - metadata: {name: data}
      spec:
        accessModes: ["ReadWriteOnce"]
        resources:
          requests: {storage: 100Mi}
EOF

# Watch it create PVCs and bind them
oc get pvc
# data-writer-0, data-writer-1, data-writer-2 — one per Pod

# Confirm each Pod has its OWN data
for i in 0 1 2; do
  echo "--- writer-$i ---"
  oc exec writer-$i -- cat /data/who.txt
done
```

Each Pod should report its own hostname. **That's the StatefulSet identity guarantee from Tuesday made concrete.**

## Troubleshooting Exercise — break the storage chain

**Break 1 — PVC stuck Pending due to unknown StorageClass**

```bash
cat <<EOF | oc apply -f -
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
oc describe pvc broken-pvc        # what does Events say?
```

**Break 2 — Pod stuck Pending due to unbound PVC**

```bash
cat <<EOF | oc apply -f -
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

oc describe pod stuck-pod     # what's the scheduling event?
```

Walk through the morning's diagram: which layer broke? (Hint: the bottom — StorageClass missing → PVC can't provision → PV doesn't exist → Pod can't schedule.)

## Deliverable — `deliverables/<you>/week01/thursday.md`

1. **The data-survives-Pod-restart trace** — the `oc exec` output showing the second Pod read the first Pod's data
2. **The StatefulSet PVC-per-Pod evidence** — 3 different outputs from `oc exec writer-N -- cat /data/who.txt`
3. **Why Kafka uses StatefulSet PVCs** — explain in 2–3 sentences referencing your evidence above. Mention `broker.id` stability.
4. **The two broken PVC walks** — for each, the exact event message that explained the failure
5. Two questions

Cleanup:

```bash
oc delete pod read-data stuck-pod --ignore-not-found
oc delete pvc my-data broken-pvc --ignore-not-found
oc delete statefulset writer
oc delete pvc -l app=writer       # AGAIN — StatefulSet doesn't garbage-collect its PVCs
oc delete svc writer-svc
```
