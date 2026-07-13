# Monday — DataStream API

**Time**: ~90 min

## Learning objective

> **Once the platform is running (Week 5), how do we actually write a Flink application?** By the end of the session you should be able to read a DataStream API job and name every operator, understand watermarks, and pick the right window type for a given latency/completeness requirement.

## Architecture Discussion (~45 min)

### The DataStream API — Flink's low-level Java/Scala interface

Two APIs to write Flink apps:

- **DataStream API** — imperative Java/Scala. You write operators explicitly. Full control. Used for anything with custom logic that SQL can't express.
- **Flink SQL** — declarative. You write SQL over Kafka tables. The runtime translates SQL to a DataStream DAG under the hood.

Both compile to the same operator DAG, run on the same JM+TM runtime. The difference is authoring ergonomics. FCB pattern: Flink SQL for most business logic (statement-driven via CMF); DataStream API where a specific transformation needs custom code.

### The four operator families

- **Source** — pulls events from an external system. In FCB, almost always `KafkaSource`. Runs continuously, converting external records into DataStream records.
- **Transformation** — the middle. Map, filter, flatMap, keyBy, window, aggregate, join, connect. Composed into an arbitrary DAG.
- **Sink** — pushes events out. `KafkaSink` for another Kafka topic; `JdbcSink` for a relational DB; `FileSink` for object storage.
- **Side-output** — a secondary output stream from an operator; used for dead-letter queues or diagnostic paths.

### Sources — the anatomy

```java
KafkaSource<String> source = KafkaSource.<String>builder()
    .setBootstrapServers("kafka.dah-flink-<env>.svc.cluster.local:9092")
    .setTopics("input-topic")
    .setGroupId("my-flink-job")
    .setStartingOffsets(OffsetsInitializer.committedOffsets(OffsetResetStrategy.EARLIEST))
    .setValueOnlyDeserializer(new SimpleStringSchema())
    .build();

DataStream<String> stream = env.fromSource(
    source,
    WatermarkStrategy.<String>forBoundedOutOfOrderness(Duration.ofSeconds(5)),
    "kafka-source"
);
```

Notes engineers must know:

- **OffsetsInitializer** — where do you start reading? `committedOffsets` (resume from Kafka), `earliest` (replay all), `latest` (only new).
- **WatermarkStrategy** — how Flink tracks "how far behind real time" the source is. See watermarks below.
- **Deserializer** — how bytes on the wire become a Java object. `SimpleStringSchema` for JSON strings, `KafkaAvroDeserializationSchema` for Avro with Schema Registry.

### Transformation operators — the ones you'll see most

- **map** — 1:1 transformation, no state
- **filter** — drop events matching a predicate
- **flatMap** — 1:many, emit zero-or-more outputs per input
- **keyBy** — partition the stream by key. Below this, operators can be *keyed* (each key handled by exactly one operator instance, state per key).
- **window** — group events by time (or count) before aggregation
- **reduce / aggregate / process** — actual computation over windowed groups
- **connect** — merge two streams into a *connected stream* where operators can access both

### Sinks — the anatomy

```java
KafkaSink<String> sink = KafkaSink.<String>builder()
    .setBootstrapServers("kafka.dah-flink-<env>.svc.cluster.local:9092")
    .setRecordSerializer(KafkaRecordSerializationSchema.<String>builder()
        .setTopic("output-topic")
        .setValueSerializationSchema(new SimpleStringSchema())
        .build())
    .setDeliveryGuarantee(DeliveryGuarantee.EXACTLY_ONCE)
    .setTransactionalIdPrefix("my-flink-job")
    .build();

stream.sinkTo(sink);
```

`DeliveryGuarantee.EXACTLY_ONCE` uses Kafka transactions — the sink writes are committed transactionally with the checkpoint. Requires the output topic ACLs to allow the transactional-id prefix.

### Watermarks — the concept that makes streaming honest

An event happens at real time `T_event`; it arrives at Flink at wall time `T_now > T_event`. **Watermark** = Flink's estimate of "we've seen all events with timestamp ≤ W." When a windowed operator receives a watermark past its window's end, it fires.

Strategies:

- `forBoundedOutOfOrderness(Duration.ofSeconds(5))` — "we're at most 5 sec late." Most common.
- `forMonotonousTimestamps()` — "events arrive in strict order." Rare in practice.
- `noWatermarks()` — batch-like; only makes sense with bounded input.

Set the watermark strategy wrong → windows either fire too early (missing late events) or too late (data sitting in memory unnecessarily).

### Windows — grouping events for aggregation

Three window shapes:

- **Tumbling** — fixed size, non-overlapping. E.g., "count per 5-min bucket."
- **Sliding** — fixed size, overlapping. E.g., "count over trailing 5 min, computed every 1 min."
- **Session** — dynamic size, closes after a gap of inactivity. E.g., "session per user, closes after 30 min of no events."

Combined with the watermark strategy, windows are the workhorse for real-time aggregations.

## Diagram Walkthrough (~30 min)

Draw the operator DAG for a job that:

1. Reads from `payments-raw` (Kafka)
2. Filters out failed payments
3. Keys by `user_id`
4. Windows into 5-minute tumbling buckets
5. Sums payment amounts per user per window
6. Writes to `payments-per-user-5min` (Kafka)

Label each operator, note where state lives, note the watermark boundary.

## Failure Scenarios

| Symptom | Where to look |
|---|---|
| Job runs but output topic is empty | Watermark strategy might be too strict; windows never fire. Check `numLateRecords` metric. |
| Deserialization exception in TM logs | Source deserializer doesn't match the message format. Common cause: JSON events + Avro deserializer. |
| Sink writes but only some events reach output | If `EXACTLY_ONCE`: check transaction-id ACL. If `AT_LEAST_ONCE`: check for downstream duplicates. |
| Job restarts loop with `Serialization` errors | Custom class changed between runs; savepoint restore fails to deserialize old state. |
| CPU 100% on one TM | Skew — a "hot" key dominates. Fix with `keyBy` distribution or pre-aggregation. |

## Q&A

1. Why is `keyBy` a partitioning operator, not a transformation — what physically happens between the upstream and downstream operators?
2. When would you choose a session window over a tumbling window? Give a concrete example.
3. If a source emits a message at `T=10s` but Flink's watermark is at `T=5s`, what happens to the message when it arrives?
4. Exactly-once delivery in the sink requires Kafka transactions. What's the tradeoff — why isn't every job using it?
5. Between DataStream API and Flink SQL, when do you write a job in Java rather than SQL?

## Added Enhancement

Take one FCB SQL statement from CMF and translate the top-level query mentally into a DataStream DAG. Then run `EXPLAIN` on the SQL statement to see the actual DAG Flink generates. Compare — is your mental translation the same shape? Any operators SQL added that you didn't think about?
