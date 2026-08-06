#!/usr/bin/env python3
"""
Kafka Discovery Metrics Collection
Collects throughput, lag, and resource metrics from Prometheus or Datadog.
"""

import logging
from typing import Dict, Any, List
from datetime import datetime, timedelta

try:
    import requests
except ImportError:
    print("ERROR: requests not installed. Run: pip install requests")


class MetricsCollector:
    """Base class for metrics collection."""

    def __init__(self, config: Dict[str, Any], logger: logging.Logger):
        self.config = config
        self.logger = logger

    def collect(self) -> Dict[str, Any]:
        """Collect metrics. Implemented by subclasses."""
        raise NotImplementedError


class PrometheusMetrics(MetricsCollector):
    """Collect metrics from Prometheus."""

    def __init__(self, config: Dict[str, Any], logger: logging.Logger):
        super().__init__(config, logger)
        self.url = config.get("prometheus_url", "http://prometheus:9090")
        self.timeout = config.get("timeout", 30)

    def collect(self) -> Dict[str, Any]:
        """Collect Kafka metrics from Prometheus."""
        self.logger.info(f"Collecting metrics from Prometheus: {self.url}")

        metrics = {
            "timestamp": datetime.utcnow().isoformat(),
            "source": "prometheus",
            "throughput": self._get_throughput_metrics(),
            "lag": self._get_consumer_lag_metrics(),
            "broker_resources": self._get_broker_resource_metrics(),
            "replication": self._get_replication_metrics(),
        }

        return metrics

    def _query_prometheus(self, query: str) -> List[Dict[str, Any]]:
        """Execute a PromQL query."""
        try:
            response = requests.get(
                f"{self.url}/api/v1/query",
                params={"query": query},
                timeout=self.timeout,
            )
            response.raise_for_status()
            data = response.json()

            if data["status"] == "success":
                return data["data"]["result"]
            else:
                self.logger.warning(f"Query failed: {data.get('error', 'unknown')}")
                return []
        except requests.RequestException as e:
            self.logger.error(f"Prometheus query failed: {e}")
            return []

    def _get_throughput_metrics(self) -> Dict[str, Any]:
        """Get Kafka throughput metrics."""
        # Kafka bytes in/out per second
        bytes_in = self._query_prometheus(
            'rate(kafka_server_brokertopicmetrics_messagesin_total[5m])'
        )
        bytes_out = self._query_prometheus(
            'rate(kafka_server_brokertopicmetrics_messagesout_total[5m])'
        )

        return {
            "bytes_in_per_sec": self._parse_metric_results(bytes_in),
            "bytes_out_per_sec": self._parse_metric_results(bytes_out),
        }

    def _get_consumer_lag_metrics(self) -> Dict[str, Any]:
        """Get consumer lag metrics."""
        lag = self._query_prometheus(
            'kafka_consumergroup_lag{group=~".*"}'
        )

        return {
            "consumer_group_lag": self._parse_metric_results(lag),
        }

    def _get_broker_resource_metrics(self) -> Dict[str, Any]:
        """Get broker CPU and memory metrics."""
        cpu = self._query_prometheus(
            'process_cpu_usage{job="kafka"}'
        )
        memory = self._query_prometheus(
            'jvm_memory_used_bytes{job="kafka",area="heap"}'
        )
        disk = self._query_prometheus(
            'node_filesystem_avail_bytes{mountpoint="/var/kafka-logs"}'
        )

        return {
            "cpu_usage": self._parse_metric_results(cpu),
            "heap_memory_used_bytes": self._parse_metric_results(memory),
            "disk_available_bytes": self._parse_metric_results(disk),
        }

    def _get_replication_metrics(self) -> Dict[str, Any]:
        """Get replication lag metrics."""
        replication_lag = self._query_prometheus(
            'kafka_server_replicamanager_leadercount'
        )
        under_replicated = self._query_prometheus(
            'kafka_server_replicafetcher_lag_bytes'
        )

        return {
            "replication_lag_bytes": self._parse_metric_results(replication_lag),
            "under_replicated_partitions": self._parse_metric_results(under_replicated),
        }

    def _parse_metric_results(self, results: List[Dict[str, Any]]) -> Dict[str, float]:
        """Parse Prometheus query results."""
        parsed = {}
        for result in results:
            labels = result.get("metric", {})
            value = float(result.get("value", [0, 0])[1])

            # Create a key from labels
            label_str = ",".join([f"{k}={v}" for k, v in labels.items()])
            parsed[label_str] = value

        return parsed


class DatadogMetrics(MetricsCollector):
    """Collect metrics from Datadog."""

    def __init__(self, config: Dict[str, Any], logger: logging.Logger):
        super().__init__(config, logger)
        self.api_key = config.get("datadog_api_key")
        self.app_key = config.get("datadog_app_key")
        self.api_url = "https://api.datadoghq.com"
        self.timeout = config.get("timeout", 30)

    def collect(self) -> Dict[str, Any]:
        """Collect Kafka metrics from Datadog."""
        if not self.api_key or not self.app_key:
            self.logger.error("Datadog API key and app key required")
            return {"error": "Missing Datadog credentials"}

        self.logger.info("Collecting metrics from Datadog")

        metrics = {
            "timestamp": datetime.utcnow().isoformat(),
            "source": "datadog",
            "throughput": self._get_throughput_metrics(),
            "lag": self._get_consumer_lag_metrics(),
            "broker_resources": self._get_broker_resource_metrics(),
        }

        return metrics

    def _query_datadog(self, query: str) -> Dict[str, Any]:
        """Execute a Datadog metrics query."""
        try:
            headers = {
                "DD-API-KEY": self.api_key,
                "DD-APPLICATION-KEY": self.app_key,
            }

            # Get metrics from last 5 minutes
            from_time = int((datetime.utcnow() - timedelta(minutes=5)).timestamp())
            to_time = int(datetime.utcnow().timestamp())

            response = requests.get(
                f"{self.api_url}/api/v1/query",
                params={
                    "query": query,
                    "from": from_time,
                    "to": to_time,
                },
                headers=headers,
                timeout=self.timeout,
            )
            response.raise_for_status()
            return response.json()
        except requests.RequestException as e:
            self.logger.error(f"Datadog query failed: {e}")
            return {}

    def _get_throughput_metrics(self) -> Dict[str, Any]:
        """Get Kafka throughput metrics from Datadog."""
        bytes_in = self._query_datadog("avg:kafka.network.bytes_in{*}")
        bytes_out = self._query_datadog("avg:kafka.network.bytes_out{*}")

        return {
            "bytes_in_per_sec": bytes_in.get("series", []),
            "bytes_out_per_sec": bytes_out.get("series", []),
        }

    def _get_consumer_lag_metrics(self) -> Dict[str, Any]:
        """Get consumer lag metrics from Datadog."""
        lag = self._query_datadog("avg:kafka.consumer_lag{*}")

        return {
            "consumer_lag": lag.get("series", []),
        }

    def _get_broker_resource_metrics(self) -> Dict[str, Any]:
        """Get broker resource metrics from Datadog."""
        cpu = self._query_datadog("avg:system.cpu.user{service:kafka}")
        memory = self._query_datadog("avg:system.mem.pct_usable{service:kafka}")
        disk = self._query_datadog("avg:system.disk.free{service:kafka}")

        return {
            "cpu_usage_percent": cpu.get("series", []),
            "memory_usage_percent": memory.get("series", []),
            "disk_free_bytes": disk.get("series", []),
        }


def create_metrics_collector(
    config: Dict[str, Any], logger: logging.Logger
) -> MetricsCollector:
    """Factory function to create appropriate metrics collector."""
    metrics_type = config.get("type", "prometheus")

    if metrics_type == "prometheus":
        return PrometheusMetrics(config, logger)
    elif metrics_type == "datadog":
        return DatadogMetrics(config, logger)
    else:
        raise ValueError(f"Unknown metrics type: {metrics_type}")
