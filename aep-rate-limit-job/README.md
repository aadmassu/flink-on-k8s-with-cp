# AEP Rate Limit Flink Job

Java Flink DataStream application for the POC pipeline:

```text
Debezium -> Kafka post-SMT topic(s) -> Flink -> rate-limited/batched HTTP POST -> AEP
```

The job does **not** transform records. It forwards the post-SMT Kafka value unchanged inside the configured AEP request body format.

## Main class

```text
com.company.flink.AepRateLimitJob
```

## JAR expected by deployment manifest

```text
/opt/flink/usrlib/aep-rate-limit-job.jar
```

## Build

```bash
mvn clean package
```

Output:

```text
target/aep-rate-limit-job.jar
```

## Build image

```bash
docker build -t artifactory.fcbint.net/camdepositsharedservices-docker-dev/<app-repo>/aep-rate-limit-job:1.0.0 .
docker push artifactory.fcbint.net/camdepositsharedservices-docker-dev/<app-repo>/aep-rate-limit-job:1.0.0
```

## Key environment variables

| Name | Required | Example |
|---|---:|---|
| `BOOTSTRAP_SERVERS` | yes | `broker1:9094,broker2:9094` |
| `SOURCE_TOPICS` | yes | `topic.credit,topic.debit` |
| `DLQ_TOPIC` | yes | `dlq.flink.aep` |
| `CONSUMER_GROUP_ID` | no | `aep-rate-limit-group` |
| `AUTO_OFFSET_RESET` | no | `earliest` |
| `SECURITY_PROTOCOL` | no | `PLAINTEXT` |
| `AEP_ENDPOINT_URL` | yes | `https://...` |
| `AEP_API_KEY` | no | secret value |
| `AEP_CLIENT_SECRET` | no | secret value |
| `AEP_HEADER_1_NAME` / `AEP_HEADER_1_VALUE` | no | header pair |
| `AEP_HEADER_2_NAME` / `AEP_HEADER_2_VALUE` | no | header pair |
| `AEP_HEADER_3_NAME` / `AEP_HEADER_3_VALUE` | no | header pair |
| `RATE_LIMIT_REQUESTS_PER_SECOND` | no | `200` |
| `TARGET_BATCH_SIZE_BYTES` | no | `10240` |
| `MAX_BATCH_SIZE_BYTES` | no | `51200` |
| `MAX_BATCH_RECORDS` | no | `166` |
| `BATCH_FLUSH_INTERVAL_MS` | no | `100` |
| `AEP_BATCH_MODE` | no | `JSON_ARRAY`, `NDJSON`, or `SINGLE_RECORD` |
| `HTTP_TIMEOUT_MS` | no | `10000` |
| `HTTP_MAX_RETRIES` | no | `6` |
| `HTTP_INITIAL_BACKOFF_MS` | no | `500` |
| `HTTP_MAX_BACKOFF_MS` | no | `30000` |
| `ENABLE_DYNAMIC_429_BACKOFF` | no | `true` |
| `ENABLE_DOWNSTREAM_COMPRESSION` | no | `false` |

## Batching modes

The final AEP body format must be confirmed with the AEP team.

* `JSON_ARRAY`: body is `[event1,event2,...]`
* `NDJSON`: body is newline-delimited JSON
* `SINGLE_RECORD`: each request contains exactly one record; batching size config is ignored

Default is `JSON_ARRAY`.

## Rate limiting note

`RATE_LIMIT_REQUESTS_PER_SECOND` is treated as a **job-wide target** and divided by the number of parallel subtasks in the HTTP operator. For example:

```text
200 RPS / 2 sink subtasks = 100 RPS per subtask
```

This is appropriate for a static POC. If production requires a strict global distributed rate limit during dynamic scaling, replace the local token bucket with a shared/distributed limiter.
