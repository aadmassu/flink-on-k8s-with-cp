# Storage Architecture — CFK and Flink on OpenShift

How persistent storage works for Confluent Platform (CFK-managed) and Flink workloads, including the Kubernetes storage stack, access modes, and per-component requirements.

---

## Kubernetes Storage Stack

```mermaid
flowchart TD
    subgraph pod["Pod"]
        container["Container"]
        volmount["volumeMount<br>/var/lib/kafka/data"]
    end

    subgraph k8s["Kubernetes Storage"]
        pvc["PersistentVolumeClaim (PVC)<br>Access mode · Size · StorageClass"]
        pv["PersistentVolume (PV)<br>(dynamically provisioned)"]
        sc["StorageClass<br>gp3 (default) · gp2"]
    end

    subgraph infra["Infrastructure"]
        ebs["AWS EBS Volume<br>(block storage)"]
        efs["AWS EFS Volume<br>(NFS file storage)"]
    end

    container --> volmount
    volmount --> pvc
    pvc -->|"binds to"| pv
    sc -->|"provisions"| pv
    pv -->|"RWO (block)"| ebs
    pv -->|"RWX (NFS)"| efs
```

**How it works:**

1. A **Pod** declares a `volumeMount` pointing to a path inside the container
2. The volume references a **PVC** that requests storage with a specific access mode and size
3. The **StorageClass** dynamically provisions a **PV** backed by cloud storage
4. The PV binds to the PVC, and the pod mounts it

---

## Access Modes: RWO vs RWX

```mermaid
flowchart LR
    subgraph rwo["ReadWriteOnce (RWO)"]
        rwo_pvc["PVC<br>RWO · gp3"]
        rwo_pv["EBS Volume"]
        rwo_pod1["Pod (single node)"]
        rwo_pod1 --> rwo_pvc --> rwo_pv
    end

    subgraph rwx["ReadWriteMany (RWX)"]
        rwx_pvc["PVC<br>RWX · EFS"]
        rwx_pv["EFS Volume"]
        rwx_pod1["Pod A (node 1)"]
        rwx_pod2["Pod B (node 2)"]
        rwx_pod3["Pod C (node 3)"]
        rwx_pod1 --> rwx_pvc
        rwx_pod2 --> rwx_pvc
        rwx_pod3 --> rwx_pvc
        rwx_pvc --> rwx_pv
    end
```

| Access Mode | Abbreviation | Backed By | Use Case |
|-------------|-------------|-----------|----------|
| **ReadWriteOnce** | RWO | AWS EBS (gp3/gp2) | Single pod reads/writes — block storage attached to one node |
| **ReadWriteMany** | RWX | AWS EFS (NFS) | Multiple pods on different nodes read/write simultaneously |

**Key rule:** EBS volumes (gp3/gp2) only support RWO — they physically attach to a single EC2 instance. For multi-pod shared storage, you need EFS (NFS-based), which supports RWX.

---

## Who Needs What

### CFK-Managed Components (Confluent Platform)

CFK uses **StatefulSets** for stateful components. Each pod gets its own dedicated PVC via `volumeClaimTemplates`. These are always **RWO** because each pod (broker, controller) has its own exclusive data.

```mermaid
flowchart TD
    subgraph cfk["CFK StatefulSet Storage"]
        subgraph kraft["KRaftController StatefulSet"]
            kraft0["kraftcontroller-0"]
            kraft_pvc0["PVC: data0-kraftcontroller-0<br>RWO · 1TB"]
            kraft0 --> kraft_pvc0
        end

        subgraph kafka["Kafka StatefulSet"]
            kafka0["kafka-0"]
            kafka_pvc0["PVC: data0-kafka-0<br>RWO · 1TB"]
            kafka0 --> kafka_pvc0
        end

        subgraph c3["ControlCenter StatefulSet"]
            c30["controlcenter-0"]
            c3_pvc0["PVC: data0-controlcenter-0<br>RWO · 1TBi"]
            c30 --> c3_pvc0
        end
    end

    subgraph stateless["Stateless (no PVC)"]
        sr["SchemaRegistry<br>state in Kafka topics"]
        connect["Connect<br>state in Kafka topics"]
        cmf["CMF<br>stateless REST service"]
    end
```

| Component | Storage | Access Mode | Size | Why |
|-----------|---------|-------------|------|-----|
| **KRaftController** | PVC per pod | RWO | 1TB | KRaft consensus log, quorum state — exclusive to each controller |
| **Kafka** | PVC per pod | RWO | 1TB | Message logs, commit offsets — exclusive to each broker |
| **ControlCenter** | PVC per pod | RWO | 10Gi | Monitoring metrics, internal topics — single pod |
| **SchemaRegistry** | None | — | — | Stateless — schemas stored in Kafka `_schemas` topic |
| **Connect** | None | — | — | Stateless — configs/offsets/status stored in Kafka topics |
| **CMF** | None | — | — | Stateless REST service — state in Flink/Kafka/PostgreSQL |

**Why RWO for CFK?** Each Kafka broker and KRaft controller owns its data exclusively. No two pods ever need to read/write the same volume. CFK creates one PVC per pod replica via StatefulSet `volumeClaimTemplates`. This maps naturally to EBS block storage.

---

### Flink Components

Flink uses a **shared PVC** for checkpoints and savepoints — state snapshots that enable job recovery and exactly-once processing.

```mermaid
flowchart TD
    subgraph flink["Flink Session Cluster"]
        jm["JobManager"]
        tm1["TaskManager 1"]
        tm2["TaskManager 2"]
    end

    subgraph storage["Shared Checkpoint Storage"]
        pvc["flink-pvc<br>10Gi"]
        pv["PersistentVolume"]
    end

    jm -->|"trigger checkpoint"| pvc
    tm1 -->|"write state snapshot"| pvc
    tm2 -->|"write state snapshot"| pvc
    pvc --> pv

    subgraph modes["Access Mode Decision"]
        rwx_mode["RWX (ReadWriteMany)<br>EFS / NFS<br>Multi-node clusters"]
        rwo_mode["RWO (ReadWriteOnce)<br>EBS gp3<br>Single-node / dev"]
    end

    pv -.->|"production"| rwx_mode
    pv -.->|"dev/PoC"| rwo_mode
```

| Scenario | Access Mode | Storage | Why |
|----------|-------------|---------|-----|
| **Production** (multi-node) | **RWX** | AWS EFS | JM and TMs run on different nodes — all must read/write checkpoints |
| **Dev/PoC** (single-node) | **RWO** | AWS EBS (gp3) | Single replica, everything on one node — EBS is simpler and cheaper |

**Why Flink needs shared storage:**

1. **Checkpointing:** TaskManagers periodically snapshot their state to a shared location. The JobManager coordinates these snapshots. If a TaskManager fails, the replacement reads the checkpoint to resume processing.
2. **Savepoints:** Manual snapshots for job upgrades, scaling, or migration. Both JM and TMs need access.
3. **Multi-pod access:** In production, JM and TMs run on different nodes. All pods must read/write the same checkpoint directory — this requires RWX (EFS/NFS).

---

## Current Configuration

### Base manifests

| File | Access Mode | Size |
|------|-------------|------|
| `apps/confluent-flink/base/flink-pvc.yaml` | ReadWriteMany | 10Gi |

### Per-environment overlays

All environments currently patch to **RWO** for single-replica dev/PoC:

| Environment | Overlay | Access Mode | Why |
|-------------|---------|-------------|-----|
| dev | `apps/confluent-flink/dev/kustomization.yaml` | ReadWriteOnce | Single replica, one node |
| qa | `apps/confluent-flink/qa/kustomization.yaml` | ReadWriteOnce | Single replica |
| stg | `apps/confluent-flink/stg/kustomization.yaml` | ReadWriteOnce | Single replica |
| prd | `apps/confluent-flink/prd/kustomization.yaml` | ReadWriteOnce | Single replica |

> **Production note:** When scaling to multi-node Flink clusters, change the prd overlay back to `ReadWriteMany` and provision an EFS StorageClass. The base manifest already defaults to RWX.

---

## Storage Classes on OpenShift (ROSA)

| StorageClass | Provisioner | Binding Mode | Access Modes | Use Case |
|-------------|------------|-------------|-------------|----------|
| **gp3** (default) | `ebs.csi.aws.com` | WaitForFirstConsumer | RWO | Kafka, KRaft, C3, Flink (dev) |
| **gp2** | `kubernetes.io/aws-ebs` | WaitForFirstConsumer | RWO | Legacy EBS |
| **efs** (if provisioned) | `efs.csi.aws.com` | Immediate | RWO, RWX | Flink checkpoints (production) |

> **WaitForFirstConsumer:** PVC stays `Pending` until a pod actually mounts it. This ensures the EBS volume is created in the same availability zone as the pod's node.

---

## OpenShift SCC Volume Constraints

The custom `confluent-scc` allows these volume types:

```yaml
volumes:
  - configMap
  - downwardAPI
  - emptyDir
  - persistentVolumeClaim    # PVCs allowed
  - projected
  - secret
```

`hostPath` volumes are **not allowed** — all persistent data must go through PVCs.
