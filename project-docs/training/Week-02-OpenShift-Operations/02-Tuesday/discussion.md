# Tuesday — Operators (the reconciliation loop)

**Time**: ~90 min — **the most important day before Week 4 (CFK)**
**Diagram**: [`21-operator-reconciliation.drawio`](21-operator-reconciliation.drawio) — Custom Resource → Operator → Owned Objects → Reconciliation

## Learning objective

> **CFK, the Flink Operator, and the cert-manager Operator are all the same pattern.** If you understand how ONE operator reconciles, you understand all of them. What is the reconciliation loop, what triggers it, and what does the operator do INSIDE that loop?

## Architecture Discussion (~50 min)

An Operator is just a Pod (often a Deployment) that runs a control loop. The control loop is identical in shape to the built-in K8s controllers from Week 1 Monday (Deployment controller, ReplicaSet controller, Node controller, ...). What's different is what it manages.

### The two halves of an Operator

**Half 1 — the Custom Resource Definition (CRD)**

A CRD teaches the K8s API server about a new resource kind. After applying a CRD for `Kafka` (apiGroup `platform.confluent.io`), the apiserver accepts:

```yaml
apiVersion: platform.confluent.io/v1beta1
kind: Kafka
metadata: {name: my-kafka}
spec: { ... }
```

The apiserver doesn't know what to DO with that — it just stores it in etcd like any other resource. The operator does the doing.

**Half 2 — the operator Pod (the reconciler)**

The operator Pod watches the apiserver for CRs of a specific kind. When it sees one (create, update, delete), it runs a **reconcile loop**:

1. Read the CR's desired `spec`
2. Read what currently exists in the cluster (StatefulSets, Services, Pods owned by this CR)
3. Compute the delta — what's missing, what's wrong, what's extra
4. Make the delta zero — create / update / delete child objects to match desired state
5. Write the result back to the CR's `status` field

The loop runs:
- When the CR changes (CRUD event from the apiserver watch)
- When any owned child object changes (Pod restart, StatefulSet status update)
- On a periodic resync (typically every 10 min) to handle missed events

This is the SAME pattern as the built-in Deployment controller. The difference: a Deployment controller creates ReplicaSets; the CFK Kafka operator creates StatefulSets + Services + ConfigMaps + Secrets + a bunch of related child objects.

### Owner references — how children stick to their parent

When the operator creates a child object (a StatefulSet on behalf of a Kafka CR), it sets the StatefulSet's `metadata.ownerReferences` to point at the parent CR. Two consequences:

- If the parent CR is deleted, the K8s garbage collector cascades and deletes all children
- `oc get all -o name | grep <parent-uid>` finds the whole tree

`oc tree` (a krew plugin) walks the ownerReferences chain visually — every engineer should install it.

### The status field is the source of truth for "is it ready?"

A Kafka CR's `status.conditions` shows `cluster-ready: True/False/Unknown`. The operator updates this based on its reconcile result. **In production**, the tracker 2.3 RITM was about exactly this: the CFK operator couldn't `update`/`patch` PVs, so it couldn't complete reconciliation, so it kept setting `cluster-ready=False`. The CR existed; the Pods came up; but `status` truthfully reported the operator's frustration.

Reading the status conditions is the FIRST step in troubleshooting any operator-managed workload.

## Diagram Walkthrough (~25 min) — apply the loop to a real example

Open the diagram and trace a CFK Kafka CR end-to-end:

```
Engineer:  oc apply -f kafka.yaml
            │
            ▼
   apiserver stores Kafka CR in etcd
            │
            ▼
   CFK Operator's watch fires
            │
            ▼
   Reconcile loop:
      Step 1 — read spec.replicas = 3, spec.dataVolumeCapacity = 1Ti
      Step 2 — read existing StatefulSet ? → none
      Step 3 — delta: create StatefulSet + Services + ConfigMaps + Secrets
      Step 4 — apiserver POSTs into etcd; built-in controllers see new StatefulSet,
               StatefulSet controller creates Pods, scheduler binds, kubelet starts ...
      Step 5 — operator polls Pod status → updates Kafka.status.conditions:
               cluster-ready=True when all pods Ready and Kafka quorum formed
            │
            ▼
   Watch fires again (Pod status change) → loop re-runs idempotently
            │
            ▼
   Engineer: oc get kafka my-kafka -o jsonpath='{.status.conditions[?(@.type=="cluster-ready")].status}'
              → "True" — the operator agrees we're done
```

Stop at each step: *if the operator can't perform that step (RBAC, missing config, API timeout), what does the engineer see in the CR's status?*

## Failure Scenarios

| Symptom | Likely cause | First check |
|---|---|---|
| `Kafka` CR applied but nothing happens | Operator Pod isn't running, or operator isn't watching this namespace | `oc -n confluent-operator get pods` + operator logs |
| CR applied; operator Pod logs say `Forbidden` | Operator SA missing a verb on some resource (the tracker 2.3 case) | `oc auth can-i ... --as=system:serviceaccount:confluent-operator:confluent` |
| Operator reconciles, child objects created, but Pod CrashLoopBackOff | Not an operator problem — Week 1 troubleshooting tree (image, config, app) | `oc describe pod` |
| `status.conditions: cluster-ready=False`, reason: `ApplyFailed` | Operator can't apply something (RBAC, validation) | Read the message field on the condition |
| Operator stuck reconciling — no error, no progress | Operator missing `watch` verb on some child resource | Operator logs at DEBUG; check Role |
| CR deleted but children remain | Owner references missing or finalizer holding | `oc describe <child>` → `ownerReferences` block |

## Q&A

1. What's the difference between a CRD and a CR?
2. If you `oc delete crd kafkas.platform.confluent.io`, what happens to existing Kafka CRs and their child StatefulSets?
3. Why is reconciliation idempotent? What does "idempotent" mean operationally here?
4. How does the operator decide WHICH namespace's CRs to reconcile? (Hint: chart values + RBAC scope)
5. If two operator Pods are running by accident, what happens? (Hint: leader election via Lease objects in `coordination.k8s.io`)

## Common misconceptions

- **"Operators replace Helm"** — no, they solve different problems. Helm renders templates and applies them once. Operators continuously reconcile.
- **"The operator runs the workload"** — no, the operator creates the workload objects; the workload runs on its own. (CFK operator doesn't BE Kafka; it CREATES Kafka.)
- **"If `oc apply` succeeded, the workload is ready"** — `oc apply` only tells you the CR was stored in etcd. The operator hasn't necessarily reconciled yet. Check `status.conditions`.
- **"Operators are CFK-specific"** — the pattern is universal. cert-manager, ArgoCD, Prometheus Operator, Strimzi, every database operator — all use the same loop.


## Added Enhancement — Operator Failure Analysis

Common CFK troubleshooting pattern:
CR -> Operator Logs -> Events -> Child Objects -> Status Conditions

Required commands:
```bash
oc logs deployment/<operator>
oc get events -A
oc describe <cr>
```
