# CFK StatefulSet vct evidence bundle

**Date captured:** 2026-05-14

**CFK versions tested:**
- `confluent-for-kubernetes-0.1351.59` (appVersion 3.1.1) — the version
  currently running at FCB. Operator image
  `confluentinc/confluent-operator:0.1351.103`.
- `confluent-for-kubernetes-0.1514.40` (appVersion 3.2.2) — the latest
  GA release at the time of capture. Operator image
  `confluentinc/confluent-operator:0.1514.40`.

**Cluster:** a clean Kubernetes test cluster outside the FCB
environment, with no Gatekeeper / OPA admission policies installed.
This is intentional — it lets the StatefulSets CFK generates show up in
plain view so the offending field can be inspected directly. Both CFK
versions were installed in turn against the same cluster topology.

**Cluster state during capture:** fully operational. Kafka 3/3 Ready,
KRaftController 3/3 Ready, SR / Connect / REST / C3 either Running or
in expected post-init recovery. The capture is from steady-state CFK
behavior, not a transient or error condition.

## The finding in one line

**Both CFK 3.1.x and CFK 3.2.2 emit `storageClassName: dummy` on every
StatefulSet `volumeClaimTemplate`, regardless of what
`spec.storageClass.name` is set to on the CR. Upgrading does not fix
it.**

| | CFK 3.1.1 (chart 0.1351.59) | CFK 3.2.2 (chart 0.1514.40) |
|---|---|---|
| `oc explain X.spec.volumeClaimTemplates` for kafka / kraftcontroller / controlcenter | `field does not exist` | `field does not exist` |
| `sts/kafka.vct.storageClassName` | `dummy` | `dummy` |
| `sts/kraftcontroller.vct.storageClassName` | `dummy` | `dummy` |
| `sts/controlcenter.vct.storageClassName` | `dummy` | `dummy` |

## Evidence

### 1. The CRD does not expose `spec.volumeClaimTemplates`

```
$ oc explain kraftcontroller.spec.volumeClaimTemplates
error: field "volumeClaimTemplates" does not exist

$ oc explain kafka.spec.volumeClaimTemplates
error: field "volumeClaimTemplates" does not exist

$ oc explain controlcenter.spec.volumeClaimTemplates
error: field "volumeClaimTemplates" does not exist
```

Same output for both CFK 3.1.1 and CFK 3.2.2 installed in turn against
the same cluster. Operators have no CR-level mechanism to override the
`dummy` value.

### 2. The vct field on every stateful sts says `dummy`

```
sts/kafka              vct[data0].spec.storageClassName: dummy
sts/kraftcontroller    vct[data0].spec.storageClassName: dummy
sts/controlcenter      vct[data0].spec.storageClassName: dummy
```

(`sts/schemaregistry`, `sts/connect`, `sts/kafkarest` are stateless —
no vct at all, as expected.)

Full live YAMLs are bundled under `cfk-3.1.1/` and `cfk-3.2.2/` for
side-by-side comparison.

### 3. The actual PVCs have the correct storage class — CFK creates them out-of-band using `spec.storageClass.name` from the CR

```
$ oc get pvc -n dah-flink-dev
NAME                      STATUS   STORAGECLASS
data0-kafka-0             Bound    <CR's storageClass.name>
data0-kafka-1             Bound    <CR's storageClass.name>
data0-kafka-2             Bound    <CR's storageClass.name>
data0-kraftcontroller-0   Bound    <CR's storageClass.name>
data0-kraftcontroller-1   Bound    <CR's storageClass.name>
data0-kraftcontroller-2   Bound    <CR's storageClass.name>
data0-controlcenter-0     Bound    <CR's storageClass.name>
```

PVCs are bound to the exact class the CR requested. The vct, however,
says `dummy`. K8s' StatefulSet controller matches the PVCs by
deterministic name and never falls back to vct-based provisioning, so
the `dummy` value is functionally inert — until an admission policy
inspects it.

### 4. The cluster is operational

End-to-end Kafka + KRaft + downstream components run cleanly with
`storageClassName: dummy` on the vct. This isn't a CFK error condition
— it's CFK's steady-state design pattern.

## Why this is a problem at FCB

FCB's OpenShift cluster runs a Gatekeeper constraint named
`ceph-storage` that validates
`StatefulSet.spec.volumeClaimTemplates[*].spec.storageClassName`
against an allow-list of storage classes. Because CFK emits `dummy` on
that field, every CFK-managed stateful StatefulSet is rejected:

```
admission webhook "validation.gatekeeper.sh" denied the request:
[ceph-storage] statefulset did not specify an allowed and valid storage
class name <dummy>. Must be one of [ocs-storagecluster-ceph-rbd,
ocs-storagecluster-cephfs]
```

The angle brackets around `dummy` are the policy's quoting — `dummy`
is the literal value found on the StatefulSet's vct.

The actual storage layer is policy-compliant (PVCs are on
`ocs-storagecluster-ceph-rbd`); only the field the admission policy
inspects is a placeholder.

## What we are asking Confluent for

Either of the following would unblock FCB without weakening their
admission posture:

1. **Propagate `spec.storageClass.name` to the StatefulSet's vct** —
   simplest fix, makes the vct field meaningful and policy-compliant.

2. **Expose `spec.volumeClaimTemplates` as a CRD field** so operators
   can explicitly set `vct.storageClassName` when needed.

We've confirmed neither is in place as of CFK 3.2.2 (the latest GA).

## Files in this bundle

```
sts-vct-reproduction/
├── README.md                     ← this document
├── cfk-3.1.1/                    ← live StatefulSet YAMLs under CFK 3.1.1
│   ├── sts-kafka.yaml
│   ├── sts-kraftcontroller.yaml
│   ├── sts-controlcenter.yaml
│   ├── sts-schemaregistry.yaml
│   ├── sts-connect.yaml
│   └── sts-kafkarest.yaml
└── cfk-3.2.2/                    ← same StatefulSets re-captured under CFK 3.2.2
    ├── sts-kafka.yaml
    ├── sts-kraftcontroller.yaml
    ├── sts-controlcenter.yaml
    ├── sts-schemaregistry.yaml
    ├── sts-connect.yaml
    └── sts-kafkarest.yaml
```

Within each YAML, the `spec.volumeClaimTemplates` block (where present)
is the key evidence — search for `storageClassName: dummy`.
