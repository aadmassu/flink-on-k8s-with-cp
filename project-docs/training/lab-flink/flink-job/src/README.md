# src — Custom Flink job source

Maven project for the `event-counter` job — a per-user running count that keys `events-in` by user ID and writes `userId=count` records to `counts-out`.

## Build → image → cluster

Flink's application mode (what `FlinkDeployment.spec.job` uses) only supports `local://` JAR URIs — the JAR must be baked into the container image. So the flow is: `mvn package` → build a Flink image with the JAR inside → `kind load` the image into the cluster.

### 1. Build the JAR

```
cd src/
mvn package
# produces target/event-counter.jar (~20 MB shaded)
```

### 2. Build the Docker image

```
cp target/event-counter.jar .
docker build -t event-counter:local .
```

The `Dockerfile` is a two-line derivative of `flink:1.18` that copies the JAR to `/opt/flink/usrlib/event-counter.jar` — the standard usrlib location Flink searches for application-mode JARs.

### 3. Load the image into kind (or minikube)

```
kind load docker-image event-counter:local --name flink-lab
```

For minikube: `minikube image load event-counter:local`. For a real cluster: push to a registry the cluster can pull from and update the CR's `image:` accordingly.

### 4. Apply the FlinkDeployment CR

```
oc      apply -f ../flinkdeployment-custom.yaml
kubectl apply -f ../flinkdeployment-custom.yaml
```

The CR sets `imagePullPolicy: Never` so kubelet uses the kind-loaded image rather than trying to pull from a registry.

## Verify

```
kubectl get flinkdeployment event-counter -n flink-lab
# JOB STATUS should progress: CREATED -> RECONCILING -> RUNNING (STABLE)

kubectl get pods -n flink-lab -l app=event-counter
# Expect: 1 JobManager Pod + 2 TaskManager Pods

kubectl exec -n flink-lab kafka-0 -- kafka-console-consumer \
  --bootstrap-server localhost:9092 --topic counts-out --max-messages 20
# expect: user-3=1, user-7=1, user-3=2, user-3=3, user-1=1, ...
```

## Code layout

```
src/
├── pom.xml                 (Java 11 target -- flink:1.18 runs Java 11)
├── Dockerfile              (bakes event-counter.jar into flink:1.18)
├── README.md               (this file)
└── src/main/java/dev/lab/
    └── EventCounter.java
```

## Why Java 11 (not 17)

The `flink:1.18` image ships Java 11. Compiling against Java 17 produces class-file version 61.0, which the JobManager's classloader rejects with `UnsupportedClassVersionError` at startup. `pom.xml` pins `maven.compiler.source/target` to 11 to prevent this.

## What the code demonstrates (bootcamp week mapping)

| Concept | Where in EventCounter.java | Week / Day |
|---|---|---|
| Kafka source | `KafkaSource.builder()` | W5 Mon (sources) |
| keyBy partitioning | `.keyBy(userId -> userId)` | W5 Mon, W6 Mon |
| Keyed `ValueState` | `PerKeyCounter.countState` | W5 Mon (state), W6 Wed |
| Kafka sink + delivery guarantee | `KafkaSink.setDeliveryGuarantee(AT_LEAST_ONCE)` | W6 Thu |
| Operator naming | `.name("extract-userId")` etc. | W5 Wed (chains/tasks in the UI) |

## Extending

Layered exercises for later bootcamp weeks:

- Swap `AT_LEAST_ONCE` for `EXACTLY_ONCE` and re-observe sink latency (Week 6 Thu)
- Add a 1-minute tumbling window between `keyBy` and the counter (Week 6 Mon)
- Add state TTL to `PerKeyCounter` and observe cleanup (Week 6 Wed)
- Install MinIO into `flink-lab` and enable durable RocksDB checkpoints (see the commented-out `flinkConfiguration` block in `flinkdeployment-custom.yaml`)

## Iteration tips

Rebuilding the JAR after a source change requires:

```
mvn package && cp target/event-counter.jar . && \
  docker build -t event-counter:local . && \
  kind load docker-image event-counter:local --name flink-lab && \
  kubectl delete flinkdeployment event-counter -n flink-lab && \
  kubectl apply -f ../flinkdeployment-custom.yaml
```

The `delete + apply` forces the operator to pull the updated image (since the tag is stable at `:local`, without the delete kubelet would keep the cached layer).
