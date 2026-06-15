# Week 5 Thursday — Lab: Build a Kafka Health Dashboard

**Time**: ~4 hours

## Hands-on Lab — find the metrics, build the dashboard

### Step 1 — find the JMX exporter endpoint

```bash
# CFK adds a sidecar / scrape-port; find it
oc get pod kafka-0 -o jsonpath='{.spec.containers[*].name}' ; echo
oc get pod kafka-0 -o jsonpath='{.spec.containers[?(@.name=="kafka")].ports}' | python3 -m json.tool
# Or look at the service
oc get svc kafka -o yaml | grep -A 3 -- '- port'
```

Identify which port serves Prometheus metrics. Common default: 7203 or 7777.

### Step 2 — scrape one metric manually

```bash
# Port-forward and curl
oc port-forward kafka-0 7203:7203 &
sleep 2
curl -s http://localhost:7203/metrics | grep kafka_server_replica_manager | head -5
kill %1
```

You should see the under-replicated and under-min-isr counts.

### Step 3 — locate the platform's existing Grafana dashboard (or skeleton one)

```bash
# Find the Prometheus + Grafana namespace
oc get project | grep -i -E 'monitor|prometheus|grafana'
```

Note the URL to the platform's Kafka dashboard. If there isn't one, the lab continues with a self-built one.

### Step 4 — identify the 5 panels you want

For your runbook, write down which queries you'd add as panels:

| Panel | PromQL |
|---|---|
| Under-replicated partitions | `sum(kafka_server_replica_manager_under_replicated_partitions{job="kafka"})` |
| Request handler idle % | `avg(kafka_network_request_metrics_request_handler_avg_idle_percent{job="kafka"})` |
| Bytes-in per broker | `rate(kafka_server_brokertopicmetrics_messages_in_total[1m])` |
| Lag for a consumer group | (need lag exporter or `kafka_consumergroup_lag`) |
| Disk usage % | (need node-exporter) |

### Step 5 — run a load test; watch the metrics move

```bash
# Producer load test
oc exec -i kafka-0 -c kafka -- kafka-producer-perf-test \
  --topic orders \
  --num-records 100000 --record-size 1024 --throughput 5000 \
  --producer-props bootstrap.servers=kafka.<you>-training.svc.cluster.local:9092 acks=all

# In another terminal, watch the metric move
oc port-forward kafka-0 7203:7203 &
while true; do
  curl -s http://localhost:7203/metrics | grep -E '^kafka_server_brokertopicmetrics_messages_in_total{topic="orders"}'
  sleep 2
done
```

## Troubleshooting Exercise — induce three patterns; recognize them

### Pattern A — slow producer

Producer with `acks=all` and `min.insync.replicas=3` while only 2 brokers up.
**Metric signature**: producer-side `record-send-rate` low; broker `request-handle-time-ms-p99` not high.

### Pattern B — hot partition

Producer with a fixed key (e.g. `--message-key fixed`) so all messages go to one partition.
**Metric signature**: bytes-in skewed to one partition; one broker's CPU spikes.

### Pattern C — slow consumer

Single consumer with intentional `sleep` between polls.
**Metric signature**: `kafka_consumergroup_lag` growing.

For each pattern, capture the metric output that identified it.

## Deliverable — `deliverables/<you>/week05/thursday.md`

1. **JMX exporter port + sample metric output** — proof you can scrape
2. **Five-panel dashboard sketch** — table with panel name + PromQL + threshold
3. **Splunk queries** — the platform team baseline + one you wrote for "find SASL auth failures"
4. **Three induced patterns** — metric signature for each, captured from your runs
5. **One question** — about anything in the observability stack you couldn't answer
