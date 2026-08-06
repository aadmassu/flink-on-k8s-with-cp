# Kafka Discovery Automation

Automates the collection of Kafka cluster discovery evidence, enabling programmatic discovery of:
- Cluster topology and broker configuration
- Topic inventory with partitioning details
- Consumer groups and lag monitoring
- ACL and security configuration
- Schema Registry information
- Performance metrics (Prometheus/Datadog)

---

## Installation

### Prerequisites
- Python 3.8+
- `pip install kafka-python pyyaml requests`

### Setup

```bash
cd tools/
pip install -r requirements.txt
cp discovery-config.example.yaml discovery-config.yaml
```

---

## Configuration

Edit `discovery-config.yaml` to match your environment:

```yaml
environment: "uat-p"

clusters:
  - name: "uat-p-kafka-primary"
    bootstrap_servers: "kafka-broker-0:9092,kafka-broker-1:9092,kafka-broker-2:9092"
    security_protocol: "PLAINTEXT"
    
    # Optional: SASL authentication
    # security_protocol: "SASL_SSL"
    # sasl_mechanism: "PLAIN"
    # sasl_username: "${KAFKA_SASL_USER}"
    # sasl_password: "${KAFKA_SASL_PASSWORD}"
    
    # Optional: Schema Registry
    schema_registry_url: "http://schema-registry:8081"
    
    # Optional: Metrics collection
    metrics:
      enabled: true
      type: "prometheus"
      prometheus_url: "http://prometheus:9090"
```

### Environment Variables

For security, use environment variables instead of hardcoding credentials:

```bash
export KAFKA_SASL_USER="your-user"
export KAFKA_SASL_PASSWORD="your-password"
export DATADOG_API_KEY="your-api-key"
export DATADOG_APP_KEY="your-app-key"
```

---

## Usage

### Basic Discovery (all clusters, all discovery items)

```bash
python3 kafka-discovery-automation.py \
  --config discovery-config.yaml \
  --output kafka-discovery-report.json
```

### Override Environment

```bash
python3 kafka-discovery-automation.py \
  --config discovery-config.yaml \
  --environment uat-p \
  --output discovery-report-uat-p.json
```

### View Report

```bash
# Pretty-print JSON report
cat kafka-discovery-report.json | jq '.'

# Extract specific section
cat kafka-discovery-report.json | jq '.clusters."uat-p-kafka-primary".topics'

# Count topics
cat kafka-discovery-report.json | jq '.clusters."uat-p-kafka-primary".topics.count'
```

---

## Report Structure

### Example Report Output

```json
{
  "discovery_timestamp": "2026-08-03T12:00:00Z",
  "environment": "uat-p",
  "clusters": {
    "uat-p-kafka-primary": {
      "bootstrap_servers": "kafka-broker-0:9092,...",
      "brokers": {
        "count": 3,
        "brokers": {
          "0": {
            "id": 0,
            "host": "kafka-broker-0",
            "port": 9092,
            "rack": "us-east-1a"
          }
          // ...
        },
        "controller_id": 0
      },
      "topics": {
        "count": 45,
        "topics": {
          "customer-events": {
            "partition_count": 12,
            "partitions": {
              "0": {
                "leader": 0,
                "replicas": [0, 1, 2],
                "isr": [0, 1, 2]
              }
              // ...
            }
          }
          // ...
        }
      },
      "consumer_groups": {
        "count": 28,
        "consumer_groups": {
          "data-warehouse-sync": {
            "type": "consumer",
            "lag": {
              "total_lag": 1234,
              "lag_by_topic": {
                "customer-events": {
                  "0": {
                    "current_offset": 50000,
                    "end_offset": 51234,
                    "lag": 1234
                  }
                  // ...
                }
              }
            }
          }
          // ...
        }
      },
      "schema_registry": {
        "subjects_count": 62,
        "subjects": {
          "customer-events-value": {
            "versions": [1, 2, 3]
          }
          // ...
        }
      },
      "configs": {
        "broker_configs": {
          "broker_0": {
            "log.retention.hours": {
              "value": "168",
              "read_only": false,
              "is_default": false
            }
            // ...
          }
        }
      }
    }
  }
}
```

---

## Automation Mapping

| Discovery Item | Method | Automation Script | Output |
|---|---|---|---|
| Cluster count & locations | Kafka admin API | `_get_brokers()` | Broker topology, controller ID |
| Topic inventory | Kafka admin API | `_get_topics()` | Topic count, partitions, replication |
| Consumer groups & lag | Kafka admin API | `_get_consumer_groups()` | Group count, lag by topic/partition |
| ACL configuration | Kafka admin API | `_get_acls()` | ACL rules, principals, operations |
| Broker configs | Kafka admin API | `_get_broker_configs()` | Per-broker configuration |
| Schema Registry | HTTP API | `_get_schema_registry_info()` | Subject inventory, versions |
| Throughput metrics | Prometheus/Datadog | `PrometheusMetrics` / `DatadogMetrics` | Bytes in/out per second |
| Consumer lag | Prometheus/Datadog | Metrics queries | High-level lag trends |
| Broker resources | Prometheus/Datadog | Metrics queries | CPU, memory, disk utilization |

---

## Troubleshooting

### Connection Failures

```bash
# Test Kafka connectivity
kafka-broker-api-versions.sh --bootstrap-server localhost:9092

# Check Prometheus availability
curl http://prometheus:9090/api/v1/targets
```

### SASL Authentication

```bash
# Test SASL authentication
kafkacat -b kafka-broker-0:9092 \
  -X security.protocol=SASL_SSL \
  -X sasl.mechanism=PLAIN \
  -X sasl.username=$KAFKA_SASL_USER \
  -X sasl.password=$KAFKA_SASL_PASSWORD \
  -L
```

### High Lag Messages

Ignore consumer groups with extremely high lag (likely dead consumers):

```bash
cat kafka-discovery-report.json | \
  jq '.clusters[].consumer_groups.consumer_groups | 
      to_entries[] | 
      select(.value.lag.total_lag > 10000000) | 
      .key'
```

---

## Integration with Discovery Workflow

Use this automation script to populate the **Artifact/Output** column in the discovery plan:

1. **Before discovery sessions**: Review the discovery plan to identify automation-capable items
2. **During discovery**: Run this script to collect programmatic evidence
3. **After collection**: Compare automated discoveries with manual findings (interviews, docs)
4. **For gaps**: Identify items requiring manual investigation (governance, SLAs, pain points)

---

## Advanced Usage

### Parallel Discovery of Multiple Clusters

```bash
# Create cluster-specific configs
cp discovery-config.yaml discovery-config-uat-p.yaml
cp discovery-config.yaml discovery-config-uat-s.yaml

# Edit each config file with cluster details, then run in parallel
parallel python3 kafka-discovery-automation.py --config {} \
  ::: discovery-config-uat-p.yaml discovery-config-uat-s.yaml

# Merge reports
jq -s '.[0].clusters += .[1].clusters | .[0]' \
  kafka-discovery-report-uat-p.json \
  kafka-discovery-report-uat-s.json > \
  kafka-discovery-report-combined.json
```

### Export to CSV for Spreadsheet

```bash
# Extract topic inventory to CSV
cat kafka-discovery-report.json | \
  jq -r '.clusters[].topics.topics | 
          to_entries[] | 
          [.key, .value.partition_count] | 
          @csv' > topics-inventory.csv
```

### Compare Clusters

```bash
# Compare topic counts between environments
diff <(cat report-uat-p.json | jq '.clusters."uat-p".topics.count') \
     <(cat report-uat-s.json | jq '.clusters."uat-s".topics.count')
```

---

## Performance Notes

- **Admin API calls**: ~10-20 seconds per cluster (depending on topic/partition count)
- **Metrics queries**: ~5-10 seconds per cluster (Prometheus/Datadog)
- **Total time**: 15-30 seconds per cluster for full discovery

For large clusters (1000+ topics), consider:
- Filtering topics by prefix in config
- Running metrics collection separately
- Scheduling discovery during off-peak hours

---

## Output Files

- `kafka-discovery-report.json` — Raw discovery data (JSON)
- `kafka-discovery.log` — Detailed execution log

---

## Next Steps

After automation discovery:

1. **Manual review**: Validate automated findings against:
   - Stakeholder interviews (ownership, SLAs)
   - Architecture documentation (governance, isolation)
   - Operational runbooks (incident response, capacity planning)

2. **Gap analysis**: Identify items requiring manual investigation:
   - Items with `error` status in report
   - Missing schema subjects or consumer groups
   - Lag outliers requiring investigation

3. **Discovery plan update**: Update the Excel discovery plan with:
   - Automated artifact links (JSON report sections)
   - Manual interview findings
   - Status indicators (complete, gaps, escalations)
