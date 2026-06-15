# Thursday — Kafka Observability: Metrics + Logs + Tracing

**Time**: ~90 min
**Diagram**: [`53-kafka-observability.drawio`](53-kafka-observability.drawio)

## Learning objective

> **What does  the platform look at when a Kafka customer says "it's slow"?** Map metrics, logs, and audit data to specific failure modes.

## Architecture Discussion (~45 min)

You can't operate Kafka without telemetry. the platform's stack:

- **Metrics** — Prometheus (cluster-side) + Grafana, plus Dynatrace (org-wide)
- **Logs** — Splunk (org standard); broker stdout via STDOUT sidecar or OpenShift log forwarder
- **Audit** — Kafka audit log (currently disabled — project memory `project_telemetry_audit_reenable_later`)

### Metrics — the four golden signals for Kafka

For each broker / topic / consumer group:

1. **Throughput** — bytes-in-per-sec, bytes-out-per-sec, messages-per-sec
2. **Latency** — produce latency p50/p99, fetch latency p50/p99, request queue time
3. **Errors** — failed produces, failed fetches, leader-not-available, network exceptions
4. **Saturation** — request handler avg idle %, network processor avg idle %, ISR shrink/expand rate

### Where the metrics come from

Kafka brokers expose JMX. CFK adds the `cp-kafka-prometheus-jmx-exporter` sidecar that scrapes JMX and serves Prometheus-format HTTP.

Prometheus scrape config has a job targeting `kafka-*` Pods on port 7203 (or whatever the platform uses). Grafana dashboards pull from Prometheus.

### The five broker metrics that catch 80% of issues

- `kafka_server_replica_manager_under_replicated_partitions` — should be 0
- `kafka_server_replica_manager_under_min_isr_partition_count` — should be 0
- `kafka_network_request_metrics_request_handler_avg_idle_percent` — should be > 50%
- `kafka_server_request_throttle_time_avg` (per client) — non-zero = client being throttled by quota
- `kafka_log_log_size` (per partition) — for growth tracking

### Topic-level: lag + skew

- **Consumer lag** = log-end-offset − committed offset, per partition per consumer group
- **Partition skew** — total bytes per partition. Unbalanced producers (poorly chosen keys) create hot partitions

Both are visible via `kafka-consumer-groups` and `kafka-log-dirs`.

### Logs

Broker logs to `/var/log/kafka/`, forwarded to Splunk. The lines that matter in production:

- `OFFLINE_LOG_DIR` — log directory failure (disk dead)
- `OFFLINE_PARTITION` — partition unavailable
- `ISR shrink` — replica fell behind
- `SASL authentication failed` — client config error or token issue
- `client connection from .. terminated abruptly` — network issue, client crash

Splunk searches commonly used by Kafka admin (in your runbook, capture the index + base query the  the platform team uses).

### Audit — what's NOT enabled in production

The Confluent audit log is disabled across all envs (project memory). When you re-enable:
- Adds ~10-20% broker load
- Produces to a topic on a destination cluster
- Requires bootstrap config that didn't exist at controller startup (the disable reason)

When re-enabling, plan for the broker bootstrap servers to be defined; this happens after first migration.

### CFK-specific telemetry — operator + CRs

- **CFK operator metrics** — exposed at `/metrics` on the operator Pod, scraped by Prometheus
- **CR.status conditions** — read these first when "something is wrong"
- **Events** — `oc get events -n dah-flink-dev --sort-by=.lastTimestamp` for the K8s side

## Diagram Walkthrough (~30 min)

Open `53-kafka-observability.drawio`. Walk:
- Broker → JMX exporter sidecar → Prometheus → Grafana
- Broker stdout → OpenShift log forwarder → Splunk
- (Future) Broker audit → destination Kafka cluster
- CFK Operator → /metrics → Prometheus → Grafana

## Failure Scenarios

| Symptom | First metric to check |
|---|---|
| Consumer reports "Kafka is slow" | request_handler_avg_idle_percent on brokers |
| Producer sends timing out | NetworkProcessor avg idle + ISR shrink rate |
| Disk filling up | log_log_size per partition; retention policy |
| Client gets `THROTTLE_QUOTA_VIOLATION` | request_throttle_time_avg per client |
| All clients fail at once | broker availability — `up{job="kafka"}` |

## Q&A

1. Why doesn't  the platform use Confluent Control Center as the primary monitoring tool?
2. Where does Dynatrace fit into the Kafka observability story in production?
3. If `under_replicated_partitions > 0`, what are the three most likely causes?
4. What's the difference between consumer lag and partition skew, and which is the customer's problem vs. ours?


## Added Enhancement — Operational Dashboards

Required Dashboards:

1. Broker Health
2. Consumer Lag
3. Storage Utilization
4. ISR Health
5. Controller Health

Students explain how each dashboard would be used during an incident.
