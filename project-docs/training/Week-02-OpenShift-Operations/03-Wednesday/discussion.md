# Wednesday — Monitoring (Prometheus + Grafana)

**Time**: ~90 min
**Diagram**: [`22-monitoring-flow.drawio`](22-monitoring-flow.drawio) — Pod → /metrics endpoint → Prometheus scrape → time-series DB → PromQL → Grafana panel → engineer's eyeball

## Learning objective

> **When CFK is misbehaving in production, what do you look at — and how do you build the dashboard that surfaces the symptom BEFORE the customer notices?**

## Architecture Discussion (~45 min)

OpenShift ships an integrated monitoring stack: Prometheus + Alertmanager + (optionally) Thanos for long-term storage + Grafana for dashboards. Cluster admins can opt-in user-workload monitoring, which is what lets engineers' apps + CFK be scraped.

### The four stages of the metrics pipeline

1. **The application exposes `/metrics`** — Prometheus expects an HTTP endpoint returning text in the Prometheus exposition format. Two ways apps speak this:
   - **Native instrumentation** — the app embeds a Prometheus client library (Go, Python, Java) and serves `/metrics` itself
   - **Exporter sidecar** — a separate process translates the app's own metrics (JMX, statsd, custom) into Prometheus format. CFK Kafka uses the **JMX Exporter** as a sidecar to translate broker JMX MBeans → Prometheus

2. **Prometheus scrapes** — Prometheus reads the cluster for `ServiceMonitor` and `PodMonitor` CRs that tell it WHICH endpoints to scrape, WHICH labels to attach, and HOW OFTEN (default 30s). Each scrape pulls a snapshot of current values. There's no push; Prometheus is pull-based.

3. **Time-series database** — every scraped sample becomes a point in the TSDB, tagged with labels (pod, namespace, container, etc.). Storage is local to the Prometheus Pod by default (lost if Pod dies; PVC retains across restarts).

4. **Query + visualize** — engineers write **PromQL** to compute aggregates over the TSDB ("p99 broker request latency over 5min"). Grafana panels are saved PromQL queries with a render style (graph, single stat, table). Alertmanager evaluates PromQL expressions against thresholds and routes alerts.

### CFK-specific monitoring shape

When you deploy CFK, each broker pod runs a JMX Exporter sidecar exposing `/metrics` on the broker pod. The CFK chart creates a `ServiceMonitor` (or `PodMonitor`) telling Prometheus to scrape it. Examples of what gets collected:

- `kafka_server_brokertopicmetrics_bytesinpersec` — broker-level produce throughput
- `kafka_server_replicamanager_underreplicatedpartitions` — count of partitions where the replica is behind the leader (the **single most important alert**)
- `kafka_controller_kafkacontroller_activecontrollercount` — should be exactly 1 cluster-wide; if 0, the cluster has no controller
- `kafka_consumer_consumer_fetch_manager_metrics_records_lag_max` — per-consumer-group lag

The Grafana dashboard that surfaces "is Kafka healthy?" combines these. Week 5 Thursday builds it out.

### The Prometheus query model (very brief)

PromQL is a small language. Three operations cover 80% of real dashboards:

- **Instant vector** — `kafka_server_replicamanager_underreplicatedpartitions` returns the latest value per series
- **Range vector** — `kafka_server_replicamanager_underreplicatedpartitions[5m]` returns the last 5 min of samples
- **Aggregation** — `sum by (namespace) (kafka_server_brokertopicmetrics_bytesinpersec)` collapses across labels

Functions matter: `rate()`, `irate()`, `sum_over_time()`, `histogram_quantile()`. Engineers will spend most of their time on `rate(metric_total[5m])` and `histogram_quantile(0.99, ...)`.

## Diagram Walkthrough (~25 min) — trace one metric end-to-end

Walk the diagram from the broker Pod to the engineer's screen:

```
Kafka broker Pod (kafka-0)
   │
   │  emits JVM MBean metrics on JMX port 9999
   ▼
JMX Exporter sidecar (in same Pod)
   │
   │  translates MBeans → Prometheus text format on :7071/metrics
   ▼
Prometheus (scrapes every 30s via ServiceMonitor)
   │
   │  stores samples in TSDB, tagged with labels {pod="kafka-0", namespace="dah-flink-uat"}
   ▼
Prometheus TSDB
   │
   │  PromQL query: sum by (pod) (kafka_server_replicamanager_underreplicatedpartitions)
   ▼
Grafana panel (or Alertmanager rule)
   │
   ▼
Engineer's eyeball / Slack alert
```

Stop at each step: *what could break that stops the metric from showing on Grafana?*

## Failure Scenarios

| Symptom | Likely cause |
|---|---|
| Dashboard shows "No data" for one specific broker | That broker's JMX Exporter sidecar isn't responding; pod might be restarting |
| Dashboard shows "No data" cluster-wide | Prometheus isn't scraping; check ServiceMonitor exists + selector matches + Prometheus has RBAC to read |
| Dashboard shows old data, hours behind | Prometheus scrape failing recently — check `up{job=...}` metric |
| Alert never fires despite obvious problem | Alert rule's PromQL expression is wrong, OR thresholds are too lenient, OR alert is silenced in Alertmanager |
| Alert fires constantly during normal operation | Flap — either threshold too tight, or rate window too short |

## Q&A

1. Why is Prometheus pull-based instead of push-based?
2. When would you use `rate()` vs `irate()` vs `increase()`?
3. What's the difference between a `ServiceMonitor` and a `PodMonitor`?
4. Where do CFK metrics actually live — in the Kafka container or the JMX Exporter sidecar? Why does this matter for troubleshooting?
5. In production, who runs the cluster's Prometheus + Grafana? (Hint: Container team; we consume it, we don't own it)

## Common misconceptions

- **"Grafana stores the metrics"** — no, Grafana is read-only against Prometheus (or Loki for logs). The TSDB is in Prometheus.
- **"If Prometheus is down for 1 hour, we lose 1 hour of metrics"** — yes, that's why long-term storage backends (Thanos, Cortex) exist for production environments.
- **"All metrics are equal"** — no. Some are gauges (current value, e.g. CPU usage); some are counters (monotonically increasing, e.g. total bytes); some are histograms (distribution, e.g. request latency buckets). Wrong PromQL for the type produces wrong answers.
- **"Alertmanager fires alerts"** — Alertmanager DELIVERS alerts (to Slack, email, PagerDuty). The alert FIRES inside Prometheus based on rules.


## Added Enhancement — Logging

Metrics tell you that a problem exists. Logs tell you why.

Exercise:
- Review pod logs
- Review previous container logs
- Correlate metrics spike with log events

Commands:
```bash
oc logs <pod>
oc logs <pod> --previous
```
