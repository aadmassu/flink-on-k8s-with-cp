# Week 4 Monday — Lab: Install CFK + Apply the First Kafka CR

**Time**: ~4 hours

## Prerequisites — already in place in production

Before today, the platform team has set up:
- CFK Operator installed in `confluent-operator` namespace (verify with `oc get pods -n confluent-operator`)
- CRDs registered (`oc get crd | grep platform.confluent.io`)
- Your training project has the necessary RBAC and quota

Verify these are good before continuing:

```bash
oc get pods -n confluent-operator
oc get crd | grep platform.confluent.io
oc auth can-i create kafkas.platform.confluent.io -n <you>-training
```

## Hands-on Lab — apply a minimal Kafka CR (no TLS, no auth — keep it simple)

```bash
oc project <you>-training

# 1. KRaftController CR — the metadata layer
cat <<EOF | oc apply -f -
apiVersion: platform.confluent.io/v1beta1
kind: KRaftController
metadata:
  name: kraftcontroller
spec:
  replicas: 1
  image:
    application: confluentinc/cp-server:7.7.0
    init: confluentinc/confluent-init-container:2.9.0
  dataVolumeCapacity: 10Gi
EOF

# 2. Wait for kraftcontroller to be Ready
oc wait --for=jsonpath='{.status.conditions[?(@.type=="cluster-ready")].status}'=True \
        kraftcontroller/kraftcontroller --timeout=600s

# 3. Kafka CR — depends on KRaftController being Ready first
cat <<EOF | oc apply -f -
apiVersion: platform.confluent.io/v1beta1
kind: Kafka
metadata:
  name: kafka
spec:
  replicas: 3
  image:
    application: confluentinc/cp-server:7.7.0
    init: confluentinc/confluent-init-container:2.9.0
  dataVolumeCapacity: 10Gi
  dependencies:
    kRaftController:
      clusterRef:
        name: kraftcontroller
EOF

# 4. Watch the reconcile happen (Week 2 Tuesday's loop)
oc get kafka kafka -w &
sleep 30 ; jobs %1 && kill %1 2>/dev/null
oc get pods -l app=kafka -o wide

# 5. Check the status conditions
oc get kafka kafka -o jsonpath='{.status.conditions}' | python3 -m json.tool
```

If `cluster-ready=True`, congratulations — you have a CFK Kafka cluster running. If `False`, the message will name what's blocking.

## Hands-on Lab Part 2 — add Schema Registry + Connect

```bash
cat <<EOF | oc apply -f -
apiVersion: platform.confluent.io/v1beta1
kind: SchemaRegistry
metadata:
  name: schemaregistry
spec:
  replicas: 1
  image:
    application: confluentinc/cp-schema-registry:7.7.0
    init: confluentinc/confluent-init-container:2.9.0
  dependencies:
    kafka:
      bootstrapEndpoint: kafka.<you>-training.svc.cluster.local:9092
EOF

cat <<EOF | oc apply -f -
apiVersion: platform.confluent.io/v1beta1
kind: Connect
metadata:
  name: connect
spec:
  replicas: 1
  image:
    application: confluentinc/cp-server-connect:7.7.0
    init: confluentinc/confluent-init-container:2.9.0
  dependencies:
    kafka:
      bootstrapEndpoint: kafka.<you>-training.svc.cluster.local:9092
    schemaRegistry:
      url: http://schemaregistry.<you>-training.svc.cluster.local:8081
EOF

oc get pods -l 'app in (schemaregistry,connect)' -w &
sleep 60 ; jobs %1 && kill %1 2>/dev/null
```

## Troubleshooting Exercise — read CR.status.conditions

```bash
# Inspect EVERY CR's conditions
for cr in kraftcontroller/kraftcontroller kafka/kafka schemaregistry/schemaregistry connect/connect; do
  echo "=== $cr ==="
  oc get $cr -o jsonpath='{.status.conditions}' | python3 -m json.tool
  echo ""
done
```

In your runbook, note: **which condition type is the actionable one?** (Hint: `cluster-ready` for the broker; component-specific for the others.)

## Deliverable — `deliverables/<you>/week04/monday.md`

1. **The full CR set you applied** — KRaftController + Kafka + SR + Connect YAMLs
2. **`oc get pods` final state** — should be 1 + 3 + 1 + 1 = 6 Pods all Ready
3. **The `cluster-ready` condition** from each CR — paste verbatim
4. **One inter-component connection** — exec into `connect` and curl `http://schemaregistry:8081/subjects` to prove the chain works
5. **Why CFK uses StatefulSet for Kafka** — your one-paragraph answer (cross-ref Week 1 Tuesday)
6. Two questions

Cleanup — **DON'T DELETE** today's CRs unless instructed; Tuesday's lab continues with them.
