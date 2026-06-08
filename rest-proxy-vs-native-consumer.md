# Consumer to Kafka — REST Proxy (HTTP) vs Native Client (Kafka Protocol)

Companion doc to [`rest-proxy-vs-native-producer.md`](rest-proxy-vs-native-producer.md), this time from the consumer side. Two ways a consumer reaches Kafka:

1. **REST Proxy (HTTP)** — the consumer is an HTTP client. REST Proxy maintains a server-side **consumer instance** (an ephemeral stateful object that participates in the consumer group on the HTTP client's behalf) that the HTTP client polls via repeated `GET` requests.
2. **Native Kafka protocol** — the consumer is a Kafka client (`KafkaConsumer`, librdkafka, Confluent.Kafka, etc.) that maintains its own group membership and prefetch buffer, fetching directly from brokers.

The shapes are more different on the consume side than on the produce side, because consuming is fundamentally stateful — partition assignments, offsets, heartbeats, rebalances all have to live somewhere.

## Quick mental model

```
Path 1 (REST Proxy):
  HTTP client ──POST /consumers/<group>──> REST Proxy
                                           │ (creates server-side instance,
                                           │  joins the consumer group)
                                           ▼
                                       Brokers
  HTTP client ──GET .../records────────> REST Proxy ──fetch──> Brokers
                                           │ (returns prefetched records,
                                           │  keeps heartbeating in background)
  ... (repeat poll on a cadence)
  HTTP client ──DELETE /consumers/...──> REST Proxy (tears down instance)

Path 2 (Native):
  KafkaConsumer ──join group + heartbeats──> Brokers
  KafkaConsumer ──poll() (continuous fetch)─> Brokers
```

REST Proxy is essentially "your consumer state lives at the proxy and you talk to it over HTTP" — the proxy is doing native consuming on your behalf, you just GET batches out of it.

## Feature-by-feature comparison

| Capability | REST Proxy Consumer (HTTP) | Native Consumer (Kafka Protocol) |
|---|---|---|
| **Transport** | HTTP/1.1 (HTTP/2 in newer REST Proxy versions) | TCP, Kafka binary protocol |
| **State location** | Server-side — REST Proxy holds the consumer instance, group membership, current offsets, prefetch buffer | Client-side — the `KafkaConsumer` object owns all state in-process |
| **Consumer lifecycle** | Explicit: `POST /consumers/<group>` creates an instance, `DELETE /consumers/.../instances/<id>` tears it down. Instance reaped on `consumer.request.timeout.ms` if not polled | Tied to the `KafkaConsumer` object's life — created, used, closed |
| **Poll model** | HTTP request-response pull: `GET .../records?timeout=...&max_bytes=...` returns whatever the proxy's prefetch buffer holds | Continuous in-process poll loop: `consumer.poll(Duration)` returns batched records the client already prefetched |
| **Heartbeats** | Handled by REST Proxy's internal consumer. Group membership stays alive only while the consumer instance remains active and continues to be polled within configured timeouts (`session.timeout.ms`, `consumer.request.timeout.ms`) | Handled by the native client's background thread (`heartbeat.interval.ms`) |
| **Group rebalancing** | Happens server-side. Client only sees the resulting partition reassignment reflected in subsequent record sets; no rebalance callback exposed | Client-visible via `ConsumerRebalanceListener` callbacks — `onPartitionsRevoked` / `onPartitionsAssigned` enable state cleanup, flushing, etc. |
| **Cooperative rebalancing** | Depends on REST Proxy version — older versions only support eager rebalancing; newer versions inherit the configured `partition.assignment.strategy` from REST Proxy's internal consumer configuration | Supported via `CooperativeStickyAssignor` |
| **Rebalance callbacks** | Not exposed to the HTTP client — no `onPartitionsRevoked` / `onPartitionsAssigned` hooks on the proxy side | First-class via `ConsumerRebalanceListener` (`onPartitionsRevoked` / `onPartitionsAssigned`) — enables state cleanup, flushing, partition-aware buffering |
| **Offset commits** | `POST .../offsets` for manual commits; `auto.commit.enable=true` for auto-commit. Granularity is per partition | `commitSync()` / `commitAsync()` with arbitrary per-partition `(topic, partition, offset)` tuples; `enable.auto.commit=true` for auto-commit |
| **Seek / position control** | `POST .../positions` (v3) supports seeking to specific offsets, beginning, or end. v2 has weaker support | `seek(partition, offset)`, `seekToBeginning(partitions)`, `seekToEnd(partitions)` |
| **Pause / resume** | Not exposed | `pause(partitions)` / `resume(partitions)` — partition-level flow control |
| **Subscribe vs assign** | Subscribe (`POST .../subscription`) for group-managed consumption; explicit assign (`POST .../assignments` in v3) for static partition assignment | `subscribe(topics)` for group consumption; `assign(partitions)` for manual partition assignment |
| **Read isolation (EOS)** | Set via `isolation.level=read_committed` on the consumer-instance create call — REST Proxy passes it through to its internal consumer | `isolation.level=read_committed` skips uncommitted records from transactional producers |
| **Deserialization / schema validation** | Built-in via `Accept: application/vnd.kafka.avro.v2+json` (or JSON Schema / Protobuf variants); REST Proxy deserializes against Schema Registry and returns JSON | Schema Registry deserializer (`KafkaAvroDeserializer` / `KafkaProtobufDeserializer`) on the client; SR roundtrip cached locally |
| **Throughput** | Typically several times lower than a native consumer — and can be an order-of-magnitude gap in high-volume workloads. Limited by HTTP poll cadence, JSON response framing, and the proxy hop. Actual ratio depends on record size, batching, and `fetch.max.bytes` | Highest — continuous prefetch, binary records, batched fetch |
| **Latency to first record** | Higher — HTTP setup, consumer-instance creation (when not already in place; typically an explicit `POST /consumers/<group>` rather than implicit on first poll), proxy fetch, and JSON serialization | Lower — client already has prefetched records when `poll()` is called |
| **Required client library** | Any HTTP client (`curl`, `fetch`, `requests`, etc.) | Confluent / Apache Kafka client lib for the target language |
| **Browser / mobile support** | Yes | No |
| **Polyglot support** | Universal | Limited to languages with maintained Kafka clients |
| **Concurrency model** | Each consumer instance is one logical group member. Concurrent consumption requires the application to orchestrate multiple instances itself | Standard thread-per-consumer or single-threaded poll-and-dispatch pattern; rich documentation |
| **Network exposure** | One REST Proxy URL behind a service / ingress | Consumer must reach the broker endpoints returned through metadata discovery — typically all brokers participating in the cluster |
| **Private networking requirements** | Only the REST Proxy endpoint must be reachable | Consumer must reach all broker endpoints advertised by cluster metadata (Private Link / Transit Gateway / DNS abstractions can hide topology but the underlying requirement remains) |
| **Authentication (client → endpoint)** | HTTP: Basic auth, OAuth bearer, mTLS | Kafka protocol: SASL/PLAIN, SASL/OAUTHBEARER, SASL/SCRAM, mTLS |
| **Authorization (broker enforcement)** | ACLs/RBAC enforced at the broker against either the REST Proxy's identity or the caller's identity (if impersonation is configured); also enforced at REST Proxy layer for HTTP-level controls | ACLs/RBAC enforced at the broker against the client's authenticated principal |
| **Interceptors** | Not supported | `ConsumerInterceptor` chain (e.g. monitoring interceptors, lineage tracking) |
| **Per-record headers** | Yes (v2/v3 responses include `headers`) | Yes (`ConsumerRecord.headers()`) |
| **Static group membership** | Configurable via `group.instance.id` on the consumer-instance create call (newer REST Proxy versions) | `group.instance.id` on the `KafkaConsumer` config |
| **Failure surface** | Client ↔ Proxy *and* Proxy ↔ Broker; **plus** the proxy holds state — proxy restart loses the consumer instance and the application has to recreate (offsets are durable in `__consumer_offsets`, so position is recovered, but partition reassignments may shift) | Client ↔ Broker; restart re-joins the group cleanly |
| **Operational footprint** | Adds REST Proxy as a stateful service to deploy, monitor, and scale — and to consider for session-affinity if running multiple replicas | One fewer service in the path |
| **Telemetry** | HTTP-level metrics (response codes, latency); Kafka consumer metrics on the proxy's internal consumer (not directly visible to the HTTP client) | Rich client metrics: per-partition lag, `records-consumed-rate`, `fetch-latency`, `commit-latency`, etc. |

## REST Proxy Consumer — Pros and Cons

### Pros

- **Language- and runtime-agnostic.** Any HTTP client can consume — browser, mobile, FaaS, low-code platform, anything.
- **Zero client-library footprint.** No Kafka SDK to package, version, or worry about runtime compatibility.
- **Easy firewall / DMZ traversal.** A single HTTPS endpoint vs connectivity to all brokers.
- **Browser / mobile reachable.** Browsers can poll the REST Proxy and stream records into a web UI; native clients can't speak Kafka from a browser.
- **HTTP-style authentication.** OAuth bearer, basic auth, mTLS at the ingress — familiar to API/web teams.
- **Webhook / batch-fetch friendly.** A serverless function can wake up, POST to create a consumer instance (or reuse one), GET a batch, process it, and either commit or let auto-commit handle it — no long-running consumer needed.
- **Schema-aware deserialization at the proxy.** Request `application/vnd.kafka.avro.v2+json` and get already-decoded JSON in the response; no SR client setup on the consumer side.
- **Centralized observability point.** Auth audit logs, payload scanning, rate limiting, and ingress metrics all live at one HTTP-layer chokepoint.
- **Simpler initial integration.** No `KafkaConsumer` configuration matrix to get right — fewer foot-guns for new users.

### Cons

- **Throughput typically several times lower than native**, with HTTP framing, JSON encoding, and the extra proxy hop as the main contributors. Can reach an order-of-magnitude gap in high-volume workloads; actual ratio depends on record size, batching, and prefetch behavior.
- **Higher latency to first record** because of HTTP setup, optional instance create on cold poll, and JSON serialization on the way out.
- **Stateful consumer instance is a footgun.** If the HTTP client pauses longer than `consumer.request.timeout.ms`, the proxy reaps the instance, the group sees a member drop, a rebalance happens, and the client has to recreate the instance on next poll.
- **No rebalance callbacks exposed.** The client can't run cleanup / flush logic when partitions are revoked. State that's local to the HTTP-client process needs out-of-band invalidation when assignments shift.
- **Limited flow control.** No `pause()` / `resume()` to selectively stop fetching from a partition while processing back-pressures.
- **Limited seek API in older REST Proxy versions.** v2 has weak seek support; v3 is better but still less flexible than `KafkaConsumer.seek()`.
- **No consumer interceptors.** Forget monitoring interceptors, lineage capture, custom deserializers, or anything that depends on the consumer's request/response pipeline.
- **Concurrency is the application's problem.** Want parallel consumption? You orchestrate multiple HTTP consumer instances yourself — there's no in-proxy fan-out.
- **Multi-replica REST Proxy adds session affinity concerns.** The consumer instance lives on one proxy replica. A load balancer that doesn't pin requests to the same backend will break the consumer. Some deployments mitigate this by routing clients directly to a specific proxy instance or by storing consumer state externally; sticky sessions or per-replica DNS are common workarounds.
- **Two hops, three places to debug.** Failure can be at the HTTP client, REST Proxy, or broker layer — harder to triage than a direct client-broker exchange.
- **Heartbeat semantics are different.** The proxy heartbeats on your behalf as long as you poll, but if your poll cadence is slower than `session.timeout.ms`, you'll be evicted from the group without the proxy doing anything wrong.
- **Cooperative rebalancing support varies by REST Proxy version.** Some older versions only do eager rebalancing, meaning every assignment change pauses all consumption.

## Native Consumer — Pros and Cons

### Pros

- **Highest throughput** the cluster can deliver. Continuous prefetch, binary protocol, no HTTP overhead, no proxy hop.
- **Lowest latency** to first record (data is often already in the local fetch buffer when `poll()` returns).
- **Full feature set.** Pause / resume per partition, seek / seekToBeginning / seekToEnd, manual `commitSync` / `commitAsync` with per-partition offset granularity, cooperative rebalancing, static membership, interceptors.
- **Rebalance listener** lets the application flush state, persist offsets, or otherwise react cleanly when partitions are revoked or assigned.
- **`read_committed` isolation is native** and feels like part of the API rather than a config flag bolted on.
- **Direct broker connection.** No proxy hop, fewer moving parts in the failure picture.
- **Mature client metrics.** Per-partition lag, fetch latency, commit latency — all feed naturally into Prometheus / Dynatrace and into autoscaling decisions.
- **Cooperative rebalancing** (via `CooperativeStickyAssignor`) avoids the full-stop rebalance pauses that plague long-running consumers.
- **Well-established threading patterns** (single-threaded poll loop with dispatch to worker threads, or one-consumer-per-thread) — documented and battle-tested across the ecosystem.
- **Schema Registry deserializers** are first-class — cached schema lookup, support for compatibility checks, soft-failure semantics, the whole story.

### Cons

- **Requires a maintained Kafka client library** in the consumer's language. Java and librdkafka-based clients are excellent; some languages have weaker support.
- **Not reachable from browsers / mobile WebViews.** TCP-only.
- **Firewall / network complexity.** Consumers must be able to reach the broker endpoints returned through metadata discovery — typically connectivity to all brokers participating in the cluster. If any are unreachable, partitions hosted there are unavailable to this consumer. Modern networking constructs (Private Link, Transit Gateway, DNS abstractions, Confluent networking) can hide topology but typically don't eliminate the underlying requirement.
- **Heavier client footprint.** The Java consumer pulls in significant JVM-side memory and CPU baseline — not ideal for ultra-light FaaS workloads.
- **Steeper learning curve.** `session.timeout.ms`, `heartbeat.interval.ms`, `max.poll.interval.ms`, `max.poll.records`, `fetch.min.bytes`, `auto.offset.reset`, group coordinator interactions — many knobs and many ways to misconfigure.
- **Long-running consumer pattern.** Either you keep the process alive and poll continuously, or you reconnect aggressively and pay the rejoin cost every time. Less natural for short-lived FaaS triggers.
- **Authentication via Kafka protocol** (SASL/OAUTHBEARER, SASL/SCRAM, mTLS) is less familiar to teams used to HTTP-style auth and harder to debug when it fails silently.
- **Less convenient for central policy enforcement.** No single HTTP-layer chokepoint to apply rate limits, payload scanning, or token introspection unless those run inside Kafka (broker plugins, custom authorizers).

## When to choose which

| Situation | Lean toward |
|---|---|
| Browser / mobile / WebApp consuming events | REST Proxy |
| Webhook-style consumer where the receiver wakes up on a schedule, fetches a batch, processes, then disappears | REST Proxy |
| FaaS / serverless consumer with low message rate, where polling is acceptable | REST Proxy (see practical caveat below) |
| Legacy / third-party app that can poll HTTP but has no Kafka client | REST Proxy |
| Cross-org consumer where you don't want to expose broker topology | REST Proxy |
| High-throughput streaming consumer (Connect, Streams, Flink, dedicated services) | Native |
| Read-process-write requiring transactional offset commits or end-to-end exactly-once semantics (`read_committed` alone is available through REST Proxy; what forces native is the transactional `sendOffsetsToTransaction` step) | Native |
| Consumer that needs `pause()`/`resume()` / explicit seek / rebalance listeners | Native |
| Tight end-to-end latency budget (single-digit ms) | Native |
| Workload requiring rebalance-aware state management | Native |
| Workload requiring rich consumer-side metrics (lag per partition, etc.) for SLO/SLI | Native |

## Practical caveats

A few things the decision matrix glosses over:

- **Browser / mobile access** is "yes" in the table, but production deployments still hit CORS, OAuth/JWT validation, long-poll behavior of intermediaries, and corporate proxy / WAF policies. Treat it as "possible when the REST Proxy is exposed appropriately and CORS / auth policies permit it" rather than free.
- **REST Proxy is convenient for FaaS, but Kafka isn't naturally pull-friendly for serverless.** A short-lived function that wakes up, polls, and dies pays the cost of consumer-instance creation / teardown (or sticks to a hot instance and inherits all the affinity concerns from Cons). For sporadic event-driven workloads, the more durable pattern is often **Kafka → Connect → SQS / PubSub / EventBridge → FaaS trigger** — push instead of poll, and the function reacts to records rather than chasing them.
- **REST Proxy state is ephemeral; committed offsets are not.** A REST Proxy restart loses the consumer instance, but `__consumer_offsets` survives — the application needs to recreate the instance and resume from the committed position, not start over from earliest.

## Hybrid pattern

Same shape as on the producer side, it's common to mix both:

- **Native** for the backbone services that turn events into derived data — stream processors, sink connectors, anything throughput- or latency-sensitive.
- **REST Proxy** for the edges — browser dashboards subscribing to a tail of events, third-party SaaS pollers, FaaS triggers that just want a recent batch, ad-hoc smoke tests.

The proxy is a *bridge* into the cluster, not a *replacement* for native consumers. Treat throughput-sensitive consumers as native and lifestyle consumers (FaaS, webhook poll, browser tail) as REST. The two patterns coexist cleanly because they're talking to the same brokers in the end.
