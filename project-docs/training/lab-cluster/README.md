# Lab Cluster — Minimal CFK-managed Kafka on kind

A bare-minimum Kafka cluster running on kind, managed by **Confluent for Kubernetes (CFK)**. Used to demonstrate Service concepts during training; extended with features (TLS, auth, Connect, etc.) as the weeks progress.

## Composition

- **3 KRaft controllers** — declared as a `KRaftController` CR; CFK creates the StatefulSet, headless Service, ConfigMap
- **3 brokers** — declared as a `Kafka` CR; CFK creates the StatefulSet, per-broker Services, bootstrap Service, ConfigMap
- **2 Schema Registry instances** — declared as a `SchemaRegistry` CR; CFK creates the Deployment and ClusterIP Service
- **Anti-affinity** in `podTemplate` keeps controllers and brokers spread one-per-node across the 3 kind worker nodes
- **Storage class `ssd`** — symbolic on kind (mapped to local-path); on a real cluster this would be a CSI-backed SSD class
- **Namespace**: `kafka-dev`
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
```

Apply order matters: the broker references the controller via `dependencies.kRaftController.clusterRef`, and Schema Registry references the broker via `dependencies.kafka.bootstrapEndpoint`. The operator will pause reconciliation until each dependency is Ready.

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

## Tear down

```bash
kubectl delete -f 30-schemaregistry.yaml
kubectl delete -f 20-kafka.yaml
kubectl delete -f 10-kraftcontroller.yaml
kubectl delete namespace kafka-dev
kubectl delete storageclass ssd
# Keep the operator if you'll iterate; otherwise see 03-operator-install.md for full uninstall.
```

## What's intentionally NOT here yet

- No TLS / mTLS
- No SASL
- No external listeners (no NodePort, no Ingress, no Route)
- No authorization (no ACLs)
- No monitoring / metrics stack
- No Connect, ksqlDB, REST Proxy, or Control Center
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
