# Training Lab — Local CFK + Flink Sandbox

Self-contained lab bundle for Week 5 Monday (Flink Architecture) and Week 5 Tuesday (Flink Operator) hands-on exercises.

Runs against any local Kubernetes (kind, minikube, k3d) with ~6 GB free memory. Not a production template.

## What you'll get

- **Confluent for Kubernetes (CFK) operator** — reconciles Kafka/SR/etc. Custom Resources
- **Flink Kubernetes Operator** — reconciles `FlinkDeployment` / `FlinkSessionJob` CRs
- **CMF (Confluent Manager for Flink)** — SQL Gateway + Catalog (Week 5 Thursday preview)
- **1-broker Kafka cluster** — smallest working KRaft-mode CP
- **A load-generator Job** — produces `user_id|action|timestamp` events into `events-in`
- **A Flink job** — reads `events-in`, keys by user, counts events, writes to `counts-out`

Total: ~10 Pods, ~4 GB memory, boots in about 5 minutes on a laptop.

## Layout

```
lab/
├── platform-chart/         # Item 1: umbrella Helm chart (CFK + Flink operator + CMF)
├── cluster/                # Item 2: light CP cluster (Kafka + topic + producer)
├── flink-job/              # Item 3: Flink job (example JAR + custom Java source)
└── teardown.md             # Cleanup instructions
```

## Prerequisites

- Docker Desktop / Colima / Rancher Desktop
- `kind` v0.20+ (or `minikube` / `k3d`)
- `kubectl` v1.28+ (or `oc` v4.12+ — both are shown in every command)
- `helm` v3.12+
- **Optional** for the custom Flink job: Maven 3.9+ and JDK 17

## Quick start (10 minutes end-to-end)

### 1. Create a local cluster

```
kind create cluster --name flink-lab --config - <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
- role: worker
- role: worker
EOF
```

### 2. Install cert-manager (prerequisite for both operators)

```
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.0/cert-manager.yaml
kubectl wait --for=condition=Available deployment --all -n cert-manager --timeout=180s
```

### 3. Install the operators + CMF (via the umbrella Helm chart)

See [`platform-chart/README.md`](platform-chart/README.md). In short:

```
oc      apply -f platform-chart/templates/namespace.yaml
kubectl apply -f platform-chart/templates/namespace.yaml

cd platform-chart
helm dependency update
helm install lab-platform . -n flink-lab -f values.yaml
```

### 4. Deploy the light Kafka cluster + topic + producer

See [`cluster/README.md`](cluster/README.md). In short:

```
oc      apply -f cluster/kafka.yaml -n flink-lab
oc      apply -f cluster/topic.yaml -n flink-lab
oc      apply -f cluster/producer.yaml -n flink-lab

kubectl apply -f cluster/kafka.yaml -n flink-lab
kubectl apply -f cluster/topic.yaml -n flink-lab
kubectl apply -f cluster/producer.yaml -n flink-lab
```

Wait for the Kafka Pods to be Ready (~3 min), then the producer Job to start streaming.

### 5. Deploy the Flink job

See [`flink-job/README.md`](flink-job/README.md). Two variants:

- **Example-JAR variant** (zero code — uses the `StateMachineExample.jar` bundled in `flink:1.18`):
  ```
  oc      apply -f flink-job/flinkdeployment-example.yaml -n flink-lab
  kubectl apply -f flink-job/flinkdeployment-example.yaml -n flink-lab
  ```

- **Custom EventCounter variant** (reads `events-in`, does keyed counting, writes `counts-out`):
  ```
  cd flink-job/src && mvn package
  # deploy the built JAR via jar-server, then apply the CR
  oc      apply -f flink-job/jar-server.yaml -n flink-lab
  oc      apply -f flink-job/flinkdeployment-custom.yaml -n flink-lab
  ```

### 6. Observe

```
oc      get flinkdeployment -n flink-lab
oc      get pods -n flink-lab
kubectl get flinkdeployment -n flink-lab
kubectl get pods -n flink-lab

# Flink UI (JobManager REST) via port-forward
kubectl port-forward -n flink-lab svc/event-counter-rest 8081:8081
# open http://localhost:8081
```

## What this demonstrates

### Week 5 Monday — Flink Architecture

Walk `kubectl get pods -n flink-lab`:

- JobManager Pod = the master (schedules operators, coordinates checkpoints)
- TaskManager Pods = the workers (run operator DAG in slots)
- MinIO Pod = the checkpoint store (S3-compatible)
- Kafka Pods = source + sink

Open the Flink UI (step 6): see the running job's DAG, its slots (utilized vs free), its checkpoint history.

### Week 5 Tuesday — Flink Operator

Inspect the CR-to-resources reconciliation:

```
oc      get flinkdeployment event-counter -n flink-lab -o yaml
kubectl get flinkdeployment event-counter -n flink-lab -o yaml
```

Note `status.jobManagerDeploymentStatus`, `status.jobStatus.state`, `status.reconciliationStatus.state`.

Then trace what the operator built:

```
kubectl get deployment -n flink-lab -l app=event-counter
kubectl get service -n flink-lab -l app=event-counter
kubectl get configmap -n flink-lab -l app=event-counter
```

Every K8s resource on the right came from the CR on the left.

## Teardown

See [`teardown.md`](teardown.md).
