# Lab Cluster — Minimal Kafka on kind

A bare-minimum Kafka cluster used to demonstrate Service concepts during training. Will be extended with features (TLS, auth, Connect, etc.) as the weeks progress — keep this folder evolving.

## Composition

- **3 KRaft controllers** (StatefulSet)
- **3 brokers** (StatefulSet)
- **2 Schema Registry instances** (Deployment)
- **Anti-affinity** ensures controllers spread across the 3 kind worker nodes; same for brokers
- **Storage class `ssd`** — symbolic on kind (mapped to local-path on the host); on a real cluster this would be a CSI-backed SSD class
- **Namespace**: `kafka-dev`
- **No TLS, no SASL, no external listeners** — keep it minimal; features added per training week

## Prerequisites

- A kind cluster with 1 control-plane + 3 worker nodes (see `00-kind-cluster-config.yaml`).
- `kubectl` configured to that cluster: `kubectl config use-context kind-training`.
- Docker (kind needs it).
- ~3 GB free RAM for the cluster pods.

If the kind cluster doesn't exist or has the wrong shape, create it:

```bash
kind create cluster --name training --config 00-kind-cluster-config.yaml
```

## Apply

The numeric prefixes apply in order. The simplest path:

```bash
kubectl apply -f .
```

Or step by step (better for the first run so you can see each piece settle):

```bash
kubectl apply -f 01-namespace.yaml
kubectl apply -f 02-storageclass-ssd.yaml
kubectl apply -f 10-controller-service.yaml
kubectl apply -f 11-controller-statefulset.yaml
kubectl -n kafka-dev wait --for=condition=Ready pod -l app.kubernetes.io/component=controller --timeout=180s

kubectl apply -f 20-broker-service.yaml
kubectl apply -f 21-broker-statefulset.yaml
kubectl -n kafka-dev wait --for=condition=Ready pod -l app.kubernetes.io/component=broker --timeout=180s

kubectl apply -f 30-schema-registry-service.yaml
kubectl apply -f 31-schema-registry-deployment.yaml
kubectl -n kafka-dev wait --for=condition=Available deployment/schema-registry --timeout=180s
```

## Verify

```bash
kubectl -n kafka-dev get pods -o wide          # 3 controllers + 3 brokers + 2 SR, spread across nodes
kubectl -n kafka-dev get svc                   # headless + ClusterIP services
kubectl -n kafka-dev get pvc                   # 6 PVCs (3 controller, 3 broker) on the ssd StorageClass
kubectl -n kafka-dev get endpointslice          # which pods each Service is routing to
```

A quick functional check — list internal Kafka metadata topics from inside a broker:

```bash
kubectl -n kafka-dev exec broker-0 -- \
  kafka-topics --bootstrap-server localhost:9092 --list
```

A quick check on Schema Registry:

```bash
kubectl -n kafka-dev exec deploy/schema-registry -- \
  curl -s http://localhost:8081/subjects
```

## Tear down

```bash
kubectl delete namespace kafka-dev
kubectl delete storageclass ssd
```

PVCs go with the namespace; the underlying local-path data on the host nodes is cleaned by the local-path provisioner.

## What's intentionally NOT here yet

- No TLS / mTLS
- No SASL
- No external listeners (no NodePort, no Ingress, no Route)
- No authorization (no ACLs)
- No monitoring / metrics stack
- No Connect, ksqlDB, or REST Proxy
- No CFK or Strimzi operator — raw StatefulSets / Deployments so learners can see the K8s primitives directly

Each week of training introduces one or more of these as additive overlays.
