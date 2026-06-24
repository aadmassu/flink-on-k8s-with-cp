# Lab Cluster — Minimal CFK-managed Kafka on kind

A bare-minimum Kafka cluster running on kind, managed by **Confluent for Kubernetes (CFK)**. Used to demonstrate Service concepts during training; extended with features (TLS, auth, Connect, etc.) as the weeks progress.

## Composition

- **3 KRaft controllers** — declared as a `KRaftController` CR; CFK creates the StatefulSet, headless Service, ConfigMap
- **3 brokers** — declared as a `Kafka` CR; CFK creates the StatefulSet, per-broker Services, bootstrap Service, ConfigMap
- **2 Schema Registry instances** — declared as a `SchemaRegistry` CR; CFK creates the StatefulSet and ClusterIP Services
- **1 Control Center (C3)** — declared as a `ControlCenter` CR; CFK creates the StatefulSet and ClusterIP Services
- **Anti-affinity** in `podTemplate` keeps controllers and brokers spread one-per-node across the 3 kind worker nodes
- **Storage class `ssd`** — symbolic on kind (mapped to local-path); on a real cluster this would be a CSI-backed SSD class
- **Namespace**: `kafka-dev` (Confluent CRs) and `confluent` (operator)
- **CP version pin**: `7.9.8` for every component. Control Center hasn't shipped past 7.9.x (Confluent is replacing it with newer mgmt products), so 7.9.8 is the highest CP line where all four components — Kafka, KRaftController, Schema Registry, ControlCenter — coexist on the same train. `cp-server` and `cp-schema-registry` have 8.x tags; `cp-enterprise-control-center` does not.
- **No TLS, no SASL, no external listeners** — added per week as the training builds up

## Prerequisites

1. A kind cluster with 1 control-plane + 3 worker nodes (see [`00-kind-cluster-config.yaml`](00-kind-cluster-config.yaml))
2. The Confluent operator installed cluster-wide — see [`03-operator-install.md`](03-operator-install.md)
3. `kubectl` configured to the kind cluster: `kubectl config use-context kind-training`
4. ~4 GB free RAM for the cluster pods (operator + broker images are heavier than the OSS equivalents)

If the kind cluster doesn't exist:

```bash
kind create cluster --name training --config 00-kind-cluster-config.yaml
```

## Apply

Numeric prefixes apply in order. Simplest path after the operator is up:

```bash
kubectl apply -f 01-namespace.yaml
kubectl apply -f 02-storageclass-ssd.yaml
kubectl apply -f 10-kraftcontroller.yaml
kubectl -n kafka-dev wait --for=condition=Ready pod -l app=kraftcontroller --timeout=300s

kubectl apply -f 20-kafka.yaml
kubectl -n kafka-dev wait --for=condition=Ready pod -l app=kafka --timeout=300s

kubectl apply -f 30-schemaregistry.yaml
kubectl -n kafka-dev wait --for=condition=Ready pod -l app=schemaregistry --timeout=300s

kubectl apply -f 40-controlcenter.yaml
kubectl -n kafka-dev wait --for=condition=Ready pod -l app=controlcenter --timeout=600s
```

Apply order matters: the broker references the controller via `dependencies.kRaftController.clusterRef`; Schema Registry references the broker via `dependencies.kafka.bootstrapEndpoint`; Control Center references Schema Registry via `dependencies.schemaRegistry.url` and discovers Kafka from the same namespace. The operator pauses reconciliation until each dependency is Ready.

## Opening the Control Center UI

```bash
kubectl -n kafka-dev port-forward svc/controlcenter 9021:9021
# then open http://localhost:9021 in a browser
# default credentials: admin / Developer1
```

## Verify

```bash
# Confluent CRs and their status:
kubectl -n kafka-dev get kraftcontroller,kafka,schemaregistry

# What the operator generated from each CR:
kubectl -n kafka-dev get sts,deploy,svc,cm,pvc

# Pod layout (anti-affinity should spread brokers and controllers across worker nodes):
kubectl -n kafka-dev get pods -o wide

# EndpointSlices — which pods each Service routes to:
kubectl -n kafka-dev get endpointslice
```

Functional check — list internal topics from inside a broker:

```bash
kubectl -n kafka-dev exec kafka-0 -- \
  kafka-topics --bootstrap-server kafka.kafka-dev.svc.cluster.local:9071 --list
```

Functional check — register and read back a schema via Schema Registry:

```bash
# Register
kubectl -n kafka-dev exec deploy/schemaregistry -- \
  curl -s -X POST -H 'Content-Type: application/vnd.schemaregistry.v1+json' \
  --data '{"schema":"{\"type\":\"string\"}"}' \
  http://schemaregistry.kafka-dev.svc.cluster.local:8081/subjects/test-value/versions

# List
kubectl -n kafka-dev exec deploy/schemaregistry -- \
  curl -s http://schemaregistry.kafka-dev.svc.cluster.local:8081/subjects
```

## Recreate from scratch (tear down + re-apply)

Use this when you want a clean cluster — e.g. when the operator has been upgraded, when a CR's
schema has drifted, or when PVCs from a previous run are holding state you no longer want. The
sequence below deletes everything the cluster contains in dependency order, waits for finalizers
to release, then walks the Apply flow from scratch.

### 1) Tear down — delete CRs in reverse dependency order

ControlCenter depends on SchemaRegistry depends on Kafka depends on KRaftController, so delete
in that exact reverse order. Each `delete` blocks until the operator removes its child resources
(StatefulSet, Services, ConfigMap) and the finalizer releases — typically 10-30s per CR.

```bash
# oc
oc delete -f 40-controlcenter.yaml --ignore-not-found
oc delete -f 30-schemaregistry.yaml --ignore-not-found
oc delete -f 20-kafka.yaml --ignore-not-found
oc delete -f 10-kraftcontroller.yaml --ignore-not-found

# kubectl
kubectl delete -f 40-controlcenter.yaml --ignore-not-found
kubectl delete -f 30-schemaregistry.yaml --ignore-not-found
kubectl delete -f 20-kafka.yaml --ignore-not-found
kubectl delete -f 10-kraftcontroller.yaml --ignore-not-found
```

If a CR is stuck `Terminating` for more than ~60s, check operator logs — usually the operator is
unable to reach Jolokia/MDS on a pod that's already gone. The operator clears the finalizer once
it gives up; check for it and re-run delete if needed.

### 2) Clean up child PVCs (StatefulSets do NOT garbage-collect them)

Each CR's StatefulSet leaves its PVCs behind by design (data preservation). For a true reset
those have to go too — otherwise the next install reuses the old volumes and you see "stale"
broker IDs / log directories.

```bash
# oc
oc -n kafka-dev get pvc
oc -n kafka-dev delete pvc --all

# kubectl
kubectl -n kafka-dev get pvc
kubectl -n kafka-dev delete pvc --all
```

### 3) Delete the namespace and the symbolic StorageClass

```bash
# oc
oc delete -f 01-namespace.yaml --ignore-not-found
oc delete -f 02-storageclass-ssd.yaml --ignore-not-found

# kubectl
kubectl delete -f 01-namespace.yaml --ignore-not-found
kubectl delete -f 02-storageclass-ssd.yaml --ignore-not-found
```

Namespace deletion may hang briefly while finalizers on contained objects release; it's normal
to see the namespace in `Terminating` state for ~30s.

### 4) (Optional) Reinstall the operator

The operator survives a CR-only teardown — unless you're testing an operator upgrade or hit an
operator-side issue, **skip this step**. To fully reinstall, follow [`03-operator-install.md`](03-operator-install.md)
end-to-end, including the `helm uninstall` step it walks through.

### 5) Re-apply in dependency order

This is the same flow as the top-of-README "Apply" section — re-listed here so the recreate
workflow stands on its own.

```bash
# oc
oc apply -f 01-namespace.yaml
oc apply -f 02-storageclass-ssd.yaml
oc apply -f 10-kraftcontroller.yaml
oc -n kafka-dev wait --for=condition=Ready pod -l app=kraftcontroller --timeout=300s

oc apply -f 20-kafka.yaml
oc -n kafka-dev wait --for=condition=Ready pod -l app=kafka --timeout=300s

oc apply -f 30-schemaregistry.yaml
oc -n kafka-dev wait --for=condition=Ready pod -l app=schemaregistry --timeout=300s

oc apply -f 40-controlcenter.yaml
oc -n kafka-dev wait --for=condition=Ready pod -l app=controlcenter --timeout=600s

# kubectl
kubectl apply -f 01-namespace.yaml
kubectl apply -f 02-storageclass-ssd.yaml
kubectl apply -f 10-kraftcontroller.yaml
kubectl -n kafka-dev wait --for=condition=Ready pod -l app=kraftcontroller --timeout=300s

kubectl apply -f 20-kafka.yaml
kubectl -n kafka-dev wait --for=condition=Ready pod -l app=kafka --timeout=300s

kubectl apply -f 30-schemaregistry.yaml
kubectl -n kafka-dev wait --for=condition=Ready pod -l app=schemaregistry --timeout=300s

kubectl apply -f 40-controlcenter.yaml
kubectl -n kafka-dev wait --for=condition=Ready pod -l app=controlcenter --timeout=600s
```

### Verify the recreated cluster

```bash
# oc
oc -n kafka-dev get kraftcontroller,kafka,schemaregistry,controlcenter
oc -n kafka-dev get pods -o wide
oc -n kafka-dev get pvc

# kubectl
kubectl -n kafka-dev get kraftcontroller,kafka,schemaregistry,controlcenter
kubectl -n kafka-dev get pods -o wide
kubectl -n kafka-dev get pvc
```

Every CR should show its READY count equal to its REPLICAS count. PVCs should all be `Bound`,
and the names should be the per-replica pattern `data-<sts>-<ordinal>` (`data-kraftcontroller-0`,
`data-kafka-0`, etc. — fresh UUIDs, distinct from the previous run's PVs).

### Nuclear option — delete the entire kind cluster

If you only run the lab on kind and don't need to preserve the operator install:

```bash
kind delete cluster --name training
kind create cluster --name training --config 00-kind-cluster-config.yaml
# then re-install the operator per 03-operator-install.md, then step 5 above.
```

This is the fastest path to a known-clean state. The Apply flow takes ~6 minutes after the
operator finishes installing.

---

## Tear down (CRs only — keep the namespace and operator)

For a partial cleanup that leaves the namespace and operator in place (useful if you'll iterate
on the CRs):

```bash
# oc
oc delete -f 40-controlcenter.yaml --ignore-not-found
oc delete -f 30-schemaregistry.yaml --ignore-not-found
oc delete -f 20-kafka.yaml --ignore-not-found
oc delete -f 10-kraftcontroller.yaml --ignore-not-found
oc -n kafka-dev delete pvc --all          # PVCs are NOT garbage-collected by StatefulSets

# kubectl
kubectl delete -f 40-controlcenter.yaml --ignore-not-found
kubectl delete -f 30-schemaregistry.yaml --ignore-not-found
kubectl delete -f 20-kafka.yaml --ignore-not-found
kubectl delete -f 10-kraftcontroller.yaml --ignore-not-found
kubectl -n kafka-dev delete pvc --all
```

To also drop the namespace and storage class, append the steps from "Recreate from scratch" §3.
For a full operator uninstall see [`03-operator-install.md`](03-operator-install.md).

## What's intentionally NOT here yet

- No TLS / mTLS
- No SASL
- No external listeners (no NodePort, no Ingress, no Route)
- No authorization (no ACLs)
- No monitoring / metrics stack
- No Connect, ksqlDB, REST Proxy
- No RBAC for Confluent

Each week of training adds one or more of these as an additive overlay (or a tweak to the existing CRs — CFK keeps all of it in-place via the CR `spec`).

## Files

| File | Purpose |
|---|---|
| `00-kind-cluster-config.yaml` | kind cluster shape (1 control-plane + 3 workers) — used by `kind create cluster --config` |
| `01-namespace.yaml` | `kafka-dev` namespace |
| `02-storageclass-ssd.yaml` | Symbolic `ssd` StorageClass over local-path |
| `03-operator-install.md` | Helm commands to install the Confluent operator |
| `10-kraftcontroller.yaml` | `KRaftController` CR — 3 controllers, anti-affinity, 1 Gi PVCs |
| `20-kafka.yaml` | `Kafka` CR — 3 brokers, anti-affinity, 1 Gi PVCs, depends on the controller above |
| `30-schemaregistry.yaml` | `SchemaRegistry` CR — 2 replicas, depends on the broker above |
| `40-controlcenter.yaml` | `ControlCenter` CR — 1 replica, 2 Gi PVC, depends on the Schema Registry above |
