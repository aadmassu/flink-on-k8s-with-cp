# Producer to Kafka — REST Proxy (HTTP) vs Native Client (Kafka Protocol)

How a producer reaches Kafka decides what features it can use, how fast it can go, and which constraints it carries. Two paths exist for any Confluent / Apache Kafka cluster:

1. **REST Proxy (HTTP)** — the producer is an HTTP client; the REST Proxy is the bridge to brokers.
2. **Native Kafka protocol** — the producer is a Kafka client (Java, librdkafka, .NET, Go, etc.) that speaks the binary Kafka protocol directly to brokers.

This doc is a side-by-side feature comparison plus pros/cons of each, so design conversations have a single reference.

## Quick mental model

```
Path 1: Producer ──HTTP──> REST Proxy ──Kafka protocol──> Brokers
Path 2: Producer ───────────Kafka protocol───────────────> Brokers
```

Path 1 adds a hop (extra latency + extra failure point) but enables anything that can speak HTTP. Path 2 is direct (lower latency, higher throughput) but requires a Kafka client library.

## Feature-by-feature comparison

| Capability | REST Proxy (HTTP) | Native Producer (Kafka Protocol) |
|---|---|---|
| **Transport** | HTTP/1.1 (HTTP/2 in newer REST Proxy versions) | TCP, Kafka binary protocol |
| **Connection model** | Stateless HTTP requests (with optional keep-alive) | Long-lived TCP connections to each broker; metadata cached client-side |
| **Required client library** | Any HTTP client (`curl`, `fetch`, `requests`, etc.) | Confluent / Apache Kafka client lib for the target language |
| **Browser / mobile support** | Yes | No (browsers can't open raw TCP) |
| **Polyglot support** | Universal (anything that does HTTP) | Limited to languages with maintained Kafka clients |
| **Network exposure** | One REST Proxy URL behind a service / ingress | Connectivity to *all* brokers required (bootstrap returns broker addresses) |
| **Batching control** | Multi-record HTTP request body; proxy's internal producer batches via `kafka-rest.properties` (proxy-wide) | Per-producer `linger.ms` + `batch.size` + `buffer.memory`; full client-side control |
| **Compression** | Set instance-wide via `compression.type` in `kafka-rest.properties`; no per-request override | Per-producer `compression.type` (`none`/`gzip`/`snappy`/`lz4`/`zstd`); can vary per producer |
| **Exactly-Once Semantics / Transactions** | **Not supported** — no `begin/commit/abort` API; each HTTP POST is a standalone produce | **Supported** — `enable.idempotence=true`, `transactional.id`, `beginTransaction()` / `commitTransaction()` |
| **Idempotent producer** | Internal proxy producer *can* enable it, but HTTP retries from the client can still duplicate (no end-to-end ack-correlation) | `enable.idempotence=true` gives per-producer-session deduplication end-to-end |
| **Async send** | v3 `/records` async produce endpoint; otherwise HTTP request-response | `producer.send(record, callback)` returns a `Future`; fully async |
| **Backpressure** | HTTP 5xx + client-side retry; no buffer-based throttling | `buffer.memory` cap + `max.block.ms`; producer blocks when full |
| **Schema validation** | Built-in via `application/vnd.kafka.avro.v2+json` (and JSON Schema / Protobuf variants); proxy validates payload against Schema Registry before producing | Schema Registry serializer (`KafkaAvroSerializer` / `KafkaProtobufSerializer`) on the client; same SR roundtrip |
| **Partition selection** | Key-based routing (proxy computes `hash(key)` against cached metadata); cannot explicitly target a partition number per record | Full control — set `partition` on `ProducerRecord`, or supply a custom `Partitioner` |
| **Per-record headers** | Yes (v2/v3 `records[].headers`) | Yes (`ProducerRecord.headers()`) |
| **Per-record ordering** | Per-key ordering holds **only if** the same client sends records sequentially to one REST Proxy instance and that proxy uses one underlying producer | Per-key ordering with idempotence enabled (or `max.in.flight.requests.per.connection=1` on legacy clients) |
| **Authentication (client → endpoint)** | HTTP: Basic auth, OAuth bearer, mTLS — easy for service-to-service over standard ingress | Kafka protocol: SASL/PLAIN, SASL/OAUTHBEARER, SASL/SCRAM, mTLS — needs Kafka-aware client config |
| **Authorization (broker enforcement)** | ACL/RBAC enforced both at REST Proxy (auth) and at the broker (via the proxy's identity, or the caller's identity if the proxy is configured to impersonate) | ACL/RBAC enforced at the broker against the client's authenticated principal |
| **Throughput** | Roughly an order of magnitude lower than native (HTTP framing + JSON parsing + proxy hop) | Highest — direct binary protocol, batched, compressed |
| **Latency** | Higher — HTTP round-trip + proxy serialize/deserialize + broker | Lowest — single Kafka roundtrip |
| **Operational footprint** | Adds REST Proxy as a service to deploy, monitor, scale, and harden | One fewer service in the path; brokers are the only thing to operate |
| **Failure surface** | Producer ↔ Proxy *and* Proxy ↔ Broker | Producer ↔ Broker only |
| **Telemetry** | HTTP-level metrics (response codes, latency); Kafka-level metrics on the proxy's internal producer | Rich Kafka client metrics (per-topic record-send-rate, batch-size-avg, request-latency, etc.) |
| **Schema Registry interceptor support** | No client-side serializer interceptors | Yes (interceptors, custom serializers, `ProducerInterceptor` chain) |
| **EOS Sink connectors compat** | N/A — connectors are native clients | Required for Sink connectors that consume `read_committed` |

## REST Proxy (HTTP) — Pros and Cons

### Pros

- **Language- and runtime-agnostic.** Anything that speaks HTTPS can produce — a browser, a Lambda, a legacy COBOL app behind a curl wrapper, a low-code platform.
- **Zero client-library footprint.** No Kafka SDK to package, version-manage, or worry about JVM compatibility.
- **Easy firewall / DMZ traversal.** A single HTTPS endpoint (typically behind a load balancer / ingress) is much simpler to expose than connectivity to every broker.
- **Browser / mobile reachable.** Native clients can't speak Kafka from a browser; REST Proxy can.
- **Schema validation built into the content type.** Sending `application/vnd.kafka.avro.v2+json` makes Schema Registry enforcement automatic at the proxy boundary.
- **Authentication uses standard web mechanisms.** OAuth bearer tokens, mTLS at the ingress, basic auth — all familiar to web/API teams.
- **Serverless-friendly.** Functions that wake up, fire one event, and die don't pay for Kafka producer initialization cost (no metadata fetch, no broker connection setup).
- **Centralized policy enforcement.** Egress controls, rate limits, audit logs, payload scanning can all live at the proxy layer.
- **Smaller blast radius for client misbehavior.** A misconfigured native client could spam brokers directly; REST Proxy can be metered / throttled at the HTTP layer.

### Cons

- **~10× lower throughput** than native, mostly from HTTP overhead and the extra proxy hop.
- **Higher per-message latency.** Two network hops (client → proxy → broker) plus HTTP/JSON parsing.
- **No EOS / transactions.** Hard stop for read-process-write patterns that need atomicity between offset commit and produce.
- **No per-request linger/batch control.** Client can pack many records into a POST body, but proxy-instance-wide `kafka-rest.properties` is the only knob for the internal producer.
- **Compression is server-side configured**, not per-producer or per-batch.
- **Cannot pick a partition explicitly** — key-based hashing only.
- **REST Proxy itself becomes a tier to operate.** SPOF unless HA'd; another set of dashboards, alerts, scaling decisions.
- **No producer interceptors.** Forget custom partitioners, lineage interceptors, side-channel metrics.
- **HTTP retries are not idempotent end-to-end.** A timed-out POST that succeeded server-side will get re-sent by a retrying client → duplicate. Mitigation requires application-level idempotency keys.
- **Per-key ordering is fragile across multiple REST Proxy replicas** unless the client pins to a specific replica or accepts reordering risk.
- **Slower to debug.** Failure can be at the HTTP layer (client), the proxy layer, or the broker layer — three places to look.

## Native Producer (Kafka Protocol) — Pros and Cons

### Pros

- **Highest throughput** the cluster can deliver. No HTTP framing, no JSON, no extra hop.
- **Lowest latency.** Single Kafka roundtrip.
- **Full feature set.** Exactly-once semantics, transactions, idempotence, custom partitioners, interceptors, async callbacks, header support, manual offsets — everything Kafka offers.
- **Fine-grained control** over `linger.ms`, `batch.size`, `buffer.memory`, `compression.type`, `max.in.flight.requests.per.connection`, `acks` — the producer can be tuned to the workload.
- **End-to-end idempotence** with `enable.idempotence=true` — retries are safe.
- **Rich client metrics.** Per-topic, per-partition send rates, batch sizes, request latencies — feeds straight into Prometheus / Dynatrace.
- **Direct broker connections** — no proxy hop, simpler failure picture.
- **Sink/source connectors and stream processors** use native clients; integrating with the same patterns means less impedance mismatch.
- **Schema Registry support is first-class** via `KafkaAvroSerializer` / `KafkaProtobufSerializer` with caching.
- **Ecosystem maturity.** Long-standing client libraries, well-trodden tuning guides, broad community support.

### Cons

- **Requires a maintained Kafka client library** in the producer's language; some languages have weaker support than others.
- **Not reachable from browsers / mobile WebViews** (TCP only).
- **Firewall / network complexity.** Producer must reach every broker, not just one endpoint. Bootstrap servers return broker addresses; if any are unreachable, partitions hosted there are unavailable to this producer.
- **Heavier client footprint.** The Java producer in particular drags in significant memory and CPU baseline; not ideal for ultra-light serverless functions.
- **Steeper learning curve.** New users have to internalize `acks`, `linger.ms`, `enable.idempotence`, `max.in.flight`, partition affinity, consumer groups, offset commits, etc. before they're productive.
- **Configuration sprawl.** Dozens of producer settings; getting them wrong (e.g. `acks=0`) silently weakens delivery guarantees.
- **Authentication via Kafka protocol.** SASL/OAUTHBEARER / mTLS work but are less familiar to teams used to HTTP-style auth and harder to debug end-to-end.
- **Cluster metadata exposure.** Clients learn broker hostnames from bootstrap; if those aren't routable from the client's network, the produce silently fails after the initial connect.
- **Less convenient for centrally enforcing policy.** No single HTTP-layer chokepoint to apply rate limits, payload scanning, or token introspection unless those run inside Kafka (broker plugins, custom authorizers).

## When to choose which

A rough decision rubric — refine for your specific workload:

| Situation | Lean toward |
|---|---|
| Browser / mobile / WebApp producing events | REST Proxy |
| Serverless / FaaS producer (fire-and-forget, low rate) | REST Proxy |
| Legacy app, no Kafka client available, can do HTTPS | REST Proxy |
| Light operational integration where a 50 ms-ish latency budget is fine | REST Proxy |
| High-volume streaming pipeline (≥ thousands of msg/sec from one producer) | Native |
| Read-process-write requiring exactly-once semantics | Native |
| Connect / Streams / Flink as the producer | Native (these *are* native clients) |
| Tight latency SLO (single-digit ms produce → ack) | Native |
| Heavy egress where compression tuning matters | Native (per-producer compression control) |
| Need partition-level control or custom partitioner | Native |
| Need rich Kafka-side metrics for SLO/SLI tracking | Native |

## Hybrid pattern

It's common in production to use both:

- **Native** for backbone services: stream processors, connectors, the high-throughput services that drive the bus.
- **REST Proxy** for edge integrations: webhooks, browser/mobile event posters, low-volume FaaS, ad-hoc test / smoke producers, third-party SaaS pushes.

The proxy is a *bridge*, not a *replacement*. Treating it that way keeps each path doing what it's good at and keeps the throughput-sensitive code on the protocol that can keep up.
