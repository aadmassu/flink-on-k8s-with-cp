# Tuesday — CFK Custom Resources: CR → Pod

**Time**: ~90 min
**Diagram**: [`41-cfk-cr-to-pod.drawio`](41-cfk-cr-to-pod.drawio)

## Learning objective

> **What does the CFK operator do, step by step, when you `oc apply` a Kafka CR?** Trace one CR through reconciliation into a running broker Pod.

## Architecture Discussion (~45 min)

A CFK Custom Resource is a declarative spec for one Confluent component. The operator's job is to make K8s reality match the spec.

### The CR is divided into three sections

- **`spec.replicas` + `spec.image`** — what to deploy
- **`spec.dataVolumeCapacity` + `spec.storageClass`** — where data lives
- **`spec.dependencies` + `spec.listeners` + `spec.authorization`** — how it connects to other components

Plus a `status` block the operator writes back: conditions, current replica count, restart progress.

### Reconciliation step-by-step

When you apply a `Kafka` CR, the operator runs this loop (this is the Week 2 Tuesday pattern in detail):

1. **Watch** sees a new/changed Kafka object
2. **Validate** the spec — required fields, valid image, valid storage class
3. **Read dependencies** — find the KRaftController CR named in `spec.dependencies.kRaftController.clusterRef.name`. If it's not Ready, requeue and try later.
4. **Render child objects** — produce YAML for StatefulSet + Services + ConfigMaps + PVCs + ServiceAccount + RoleBindings
5. **Apply** each child object (server-side apply with the operator as field manager)
6. **Watch** child objects — wait until StatefulSet has `replicas == readyReplicas`
7. **Update status** — set `cluster-ready=True` (or False with a reason)
8. **Requeue** in 30s or on any child-object change

A few subtleties:

- **The operator does NOT mutate Pods directly**. It writes StatefulSets, and K8s spins up the Pods. This separation is why Pods can be deleted (e.g. by drain during upgrade) and re-created without operator involvement.
- **PVCs are NOT deleted when the StatefulSet shrinks** — that's a K8s safety policy. To remove broker storage you delete the PVCs explicitly.
- **Image upgrades roll the StatefulSet** — bump `spec.image.application`, operator updates StatefulSet, K8s does the rolling-update one Pod at a time, respecting PDBs.

### Status conditions — read these every time

Engineers' #1 mistake is `oc describe pod` first. The CFK answer lives in **CR status conditions**:

```bash
oc get kafka kafka -o jsonpath='{.status.conditions}' | python3 -m json.tool
```

Common conditions:
- `cluster-ready` — overall — True/False
- `image-pull-status` — last image pull
- `cluster-update` — the operator's current understanding of in-flight changes

If `cluster-ready=False`, the `message` field names the reason. **Read that first.**

### site-specific CR contents

CFK CRs in production carry site-specific blocks:

- **`spec.image`** — must be `confluentinc/cp-server:7.7.0` paired with `confluentinc/confluent-init-container:2.9.0` (project memory `project_cmf_image_tag` and CFK build-number mapping)
- **`spec.podTemplate.envVars`** — KRaft + TelemetryReporter disable (project memory `project_telemetry_audit_reenable_later`)
- **`spec.tls.secretRef`** — points at a Secret created by ESO/CyberArk (`project_eso_cyberark`)
- **`spec.metricReporter.bootstrapEndpoint`** — broker self-reference for the JMX metric reporter

## Diagram Walkthrough (~30 min)

Open `41-cfk-cr-to-pod.drawio` and trace one apply:

1. User → kube-apiserver → `Kafka` CR stored in etcd
2. Operator (in `confluent-operator` namespace) watches and gets the change
3. Operator renders StatefulSet + Service + ConfigMap + PVCs + Secret
4. Operator applies them; K8s scheduler places Pods
5. Each Pod has its init container fetch certs + config, then the broker starts
6. Operator polls Pod readiness → writes `status.conditions` back

## Failure Scenarios

| Symptom | Where to look first |
|---|---|
| `Kafka` CR applied but no Pods | operator logs in `confluent-operator` namespace |
| Pods stuck Pending | quota (tracker 2.5) or PVC not bound |
| Pods CrashLoopBackOff with TLS error | Secret missing or trust bundle wrong (tracker 2.8) |
| `cluster-ready=False, message: ".. dependency ..."` | KRaftController CR is not Ready yet |

## Q&A

1. If you `oc edit kafka kafka` and change `replicas: 3` to `replicas: 5`, list the chain of events.
2. If the operator Pod dies mid-reconcile, what happens to the in-flight change?
3. Why does `spec.image` cause a rolling restart but `spec.podTemplate.envVars` may or may not, depending on the env var?
4. Where does the operator's own RBAC come from, and which verb did  the platform have to add (runbook + tracker 2.3)?


## Added Enhancement — CRD and Status Troubleshooting

Topics:
- Spec vs Status
- Conditions
- Events
- Reconciliation errors

Exercise:
Identify deployment issues using only:
- CR status
- Events
- Operator logs
