# Thursday — Storage (PVC + PV + StorageClass)

**Time**: ~90 min
**Diagram**: [`11-storage-chain.drawio`](11-storage-chain.drawio) — Pod → PVC → PV → StorageClass → backing storage

## Learning objective

> **Why does Kafka depend on PVCs?** And what happens, step by step, when a Pod requests storage?

## Architecture Discussion (~40 min)

K8s storage has four layers. Engineers who don't understand the difference between PVC and PV will not be able to triage CFK PVC-stuck-Pending issues.

- **StorageClass** — describes a *type* of storage available on the cluster (e.g. `ceph-rbd-fast-ssd`, `gp3-encrypted`). Cluster admin defines them. Each has a `provisioner` (the CSI driver that creates volumes) and parameters (replication factor, encryption, IOPS tier).

- **PersistentVolume (PV)** — a *specific* volume that exists somewhere — a Ceph RBD image, an EBS volume, an NFS share. Has capacity, access modes, a storage class label, and a reclaim policy (`Retain` vs `Delete`). Cluster-scoped resource — Pods don't reference PVs directly.

- **PersistentVolumeClaim (PVC)** — a Pod's *request* for storage. "I need 100Gi, ReadWriteOnce, of storage class `ceph-rbd-fast-ssd`." Namespace-scoped. K8s + the storage provisioner find or create a matching PV and **bind** them.

- **Pod `volumes` + `volumeMounts`** — the Pod references the PVC by name; kubelet mounts the bound PV into the container at the requested path.

The **binding** between PVC and PV is the most-misunderstood step. Two flavors:

- **Static provisioning** — admin manually creates a PV; PVC matches it by storage class + capacity + access mode. Old-school; rarely used.
- **Dynamic provisioning** — PVC is created with a `storageClassName`; the CSI driver creates a fresh PV on demand. This is the default everywhere modern. **OpenShift uses dynamic provisioning by default with Ceph CSI** (rook / ODF).

For Kafka specifically:

- Every broker Pod needs its OWN persistent disk (its log directory). If broker.id=0's disk gets mounted into broker.id=1, the data is corrupted.
- A StatefulSet's `volumeClaimTemplates` block creates ONE PVC per Pod automatically — `data-kafka-0`, `data-kafka-1`, `data-kafka-2`. Each PVC binds to its own PV. Each Pod always mounts its own PVC across restarts. (Tied back to Tuesday's StatefulSet identity-preservation discussion.)
- If the PVC's PV is lost (storage corruption, accidental delete), the broker pod can never restart with the same identity — the broker is gone from Kafka's perspective. This is the disaster-recovery scenario covered in Week 5.

## Diagram Walkthrough (~30 min)

Walk the chain on the diagram:

```
StatefulSet (apps/v1 Kafka resource with replicas: 3)
   │
   │ creates per-Pod PVC via volumeClaimTemplates
   ▼
PVC: data-kafka-0  ──┐    PVC: data-kafka-1  ──┐    PVC: data-kafka-2  ──┐
                     │                          │                          │
                     │ binds to                 │                          │
                     ▼                          ▼                          ▼
PV: pvc-<uid-0>             PV: pvc-<uid-1>             PV: pvc-<uid-2>
   │  storageClassName: ceph-rbd-fast-ssd
   │
   ▼
StorageClass: ceph-rbd-fast-ssd
   │  provisioner: rook-ceph.rbd.csi.ceph.com
   │
   ▼
Ceph cluster (the actual backing storage — rados block devices)
   │
   ▼
Pod: kafka-0  →  mounts data-kafka-0  →  PV pvc-<uid-0>  →  on Ceph RBD image
Pod: kafka-1  →  mounts data-kafka-1  →  PV pvc-<uid-1>  →  on Ceph RBD image
Pod: kafka-2  →  mounts data-kafka-2  →  PV pvc-<uid-2>  →  on Ceph RBD image
```

Stop at each layer and ask: *what does each Pod actually see at `/var/lib/kafka`?* Answer: its OWN PV's content, totally independent from the other Pods.

## Failure Scenarios — preview troubleshooting

| Symptom | Likely cause |
|---|---|
| PVC stuck `Pending` | StorageClass doesn't exist; provisioner not running; cluster out of capacity |
| PVC bound but Pod can't start | PV's access mode wrong (`RWX` requested, `RWO` available); node can't mount (csi-node issue) |
| StatefulSet stuck creating pod-1 | pod-0's PVC didn't bind; ordered lifecycle blocks pod-1 |
| Pod ran fine, then disk full | PVC's storage size is a soft limit; Ceph fills up but Pod doesn't get killed — app handles it |
| Restored a Kafka cluster from snapshot, brokers don't form quorum | PV reclaim policy was `Delete`; old PVs were garbage-collected; new PVs have no broker data |

## Q&A

1. If you delete a StatefulSet, what happens to its PVCs? (Trick: nothing, unless retain policy is `Delete`)
2. If a node holding a PV's mount dies, can the Pod be rescheduled to a different node?
3. What's an `accessMode: ReadWriteOnce`? Why is it the default for Kafka?
4. Why does StatefulSet `volumeClaimTemplates` create separate PVCs instead of one shared PVC for all Pods?
5. In production, what's the storage backend behind the StorageClass that CFK uses? (Trick: depends per env — ask Container team)

## Common misconceptions

- **"PVCs and PVs are the same"** — no, PVC = request, PV = the actual volume
- **"All Pods of a StatefulSet share storage"** — NO. Each Pod has its OWN PVC and PV. Critical for Kafka.
- **"Deleting a PVC deletes the data"** — depends on reclaim policy. `Retain` keeps it; `Delete` reclaims it. Read the StorageClass.
- **"Cluster storage is unlimited"** — no, ResourceQuota.storage caps how much PVC space a project can claim. Tracker 2.5 was the DEV story.


## Added Enhancement — Dynamic Provisioning

Engineers should observe PVC creation before and after binding and understand that StorageClasses trigger dynamic PV creation through a CSI provisioner.

Required Commands:
```bash
oc get storageclass
oc get pvc
oc get pv
watch oc get pvc,pv
```
