#!/usr/bin/env python3
"""
FCB Enterprise Kafka Discovery Automation
Collects Kafka cluster, topic, consumer, and configuration evidence programmatically.

Usage:
    python3 kafka-discovery-automation.py --config config.yaml --output discovery-report.json
"""

import json
import yaml
import logging
import argparse
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Any
import sys

try:
    from kafka.admin import KafkaAdminClient, ConfigResource, ConfigResourceType
    from kafka.errors import KafkaError
    from kafka import KafkaConsumer
except ImportError:
    print("ERROR: kafka-python not installed. Run: pip install kafka-python")
    sys.exit(1)

try:
    import requests
except ImportError:
    print("ERROR: requests not installed. Run: pip install requests")
    sys.exit(1)


class KafkaDiscovery:
    """Automates Kafka cluster discovery and evidence collection."""

    def __init__(self, config: Dict[str, Any]):
        self.config = config
        self.logger = self._setup_logging()
        self.discovery_data = {
            "discovery_timestamp": datetime.utcnow().isoformat(),
            "environment": config.get("environment", "unknown"),
            "clusters": {},
        }

    def _setup_logging(self) -> logging.Logger:
        """Configure logging."""
        logger = logging.getLogger("kafka-discovery")
        handler = logging.StreamHandler()
        formatter = logging.Formatter(
            "%(asctime)s - %(name)s - %(levelname)s - %(message)s"
        )
        handler.setFormatter(formatter)
        logger.addHandler(handler)
        logger.setLevel(logging.INFO)
        return logger

    def discover_all(self) -> Dict[str, Any]:
        """Run discovery against all configured clusters."""
        self.logger.info("Starting Kafka cluster discovery...")

        clusters = self.config.get("clusters", [])
        for cluster_config in clusters:
            cluster_name = cluster_config["name"]
            self.logger.info(f"Discovering cluster: {cluster_name}")

            try:
                cluster_data = self._discover_cluster(cluster_config)
                self.discovery_data["clusters"][cluster_name] = cluster_data
            except Exception as e:
                self.logger.error(f"Failed to discover cluster {cluster_name}: {e}")
                self.discovery_data["clusters"][cluster_name] = {
                    "error": str(e),
                    "status": "failed"
                }

        return self.discovery_data

    def _discover_cluster(self, cluster_config: Dict[str, Any]) -> Dict[str, Any]:
        """Discover a single Kafka cluster."""
        bootstrap_servers = cluster_config["bootstrap_servers"]

        admin_client = KafkaAdminClient(
            bootstrap_servers=bootstrap_servers,
            security_protocol=cluster_config.get("security_protocol", "PLAINTEXT"),
            sasl_mechanism=cluster_config.get("sasl_mechanism"),
            sasl_plain_username=cluster_config.get("sasl_username"),
            sasl_plain_password=cluster_config.get("sasl_password"),
        )

        cluster_data = {
            "bootstrap_servers": bootstrap_servers,
            "brokers": self._get_brokers(admin_client),
            "topics": self._get_topics(admin_client),
            "consumer_groups": self._get_consumer_groups(admin_client),
            "acls": self._get_acls(admin_client) if cluster_config.get("include_acls") else None,
            "configs": self._get_broker_configs(admin_client),
        }

        # Add Schema Registry info if configured
        if "schema_registry_url" in cluster_config:
            cluster_data["schema_registry"] = self._get_schema_registry_info(
                cluster_config["schema_registry_url"]
            )

        admin_client.close()
        return cluster_data

    def _get_brokers(self, admin_client: KafkaAdminClient) -> Dict[str, Any]:
        """Get broker inventory and details."""
        self.logger.info("  Collecting broker information...")

        try:
            cluster_metadata = admin_client.describe_cluster()
            brokers = {}

            for broker in cluster_metadata.brokers:
                broker_info = {
                    "id": broker.nodeId,
                    "host": broker.host,
                    "port": broker.port,
                    "rack": broker.rack,
                }
                brokers[str(broker.nodeId)] = broker_info

            return {
                "count": len(brokers),
                "brokers": brokers,
                "controller_id": cluster_metadata.controller,
            }
        except KafkaError as e:
            self.logger.error(f"Failed to get broker info: {e}")
            return {"error": str(e)}

    def _get_topics(self, admin_client: KafkaAdminClient) -> Dict[str, Any]:
        """Get topic inventory with partitioning details."""
        self.logger.info("  Collecting topic information...")

        try:
            metadata = admin_client.describe_topics(topics=[])
            topics = {}

            for topic_name, topic_metadata in metadata.items():
                if topic_metadata.error:
                    continue

                partitions = {}
                for partition in topic_metadata.partitions:
                    partitions[partition.partition] = {
                        "leader": partition.leader,
                        "replicas": partition.replicas,
                        "isr": partition.isr,
                    }

                topics[topic_name] = {
                    "partition_count": len(partitions),
                    "partitions": partitions,
                }

            return {
                "count": len(topics),
                "topics": topics,
            }
        except KafkaError as e:
            self.logger.error(f"Failed to get topic info: {e}")
            return {"error": str(e)}

    def _get_consumer_groups(self, admin_client: KafkaAdminClient) -> Dict[str, Any]:
        """Get consumer group inventory and lag."""
        self.logger.info("  Collecting consumer group information...")

        try:
            groups = admin_client.list_consumer_groups()
            consumer_groups = {}

            for group_tuple in groups.groups:
                group_id = group_tuple[0]
                group_type = group_tuple[1]

                try:
                    # Get group details
                    group_metadata = admin_client.describe_consumer_groups([group_id])

                    # Calculate lag
                    lag_info = self._calculate_consumer_lag(admin_client, group_id)

                    consumer_groups[group_id] = {
                        "type": group_type,
                        "lag": lag_info,
                    }
                except KafkaError as e:
                    self.logger.warning(f"Could not get details for group {group_id}: {e}")

            return {
                "count": len(consumer_groups),
                "consumer_groups": consumer_groups,
            }
        except KafkaError as e:
            self.logger.error(f"Failed to get consumer groups: {e}")
            return {"error": str(e)}

    def _calculate_consumer_lag(self, admin_client: KafkaAdminClient, group_id: str) -> Dict[str, Any]:
        """Calculate consumer lag for a group."""
        try:
            offsets = admin_client.list_consumer_group_offsets(group_id)
            lag_by_topic = {}
            total_lag = 0

            for (topic, partition), offset_metadata in offsets.items():
                current_offset = offset_metadata.offset

                # Get end offset
                consumer = KafkaConsumer(
                    bootstrap_servers=admin_client._client._bootstrap_servers,
                    group_id=None,
                )
                partitions = consumer.partitions_for_topic(topic)
                if partitions:
                    consumer.assign([
                        (topic, p) for p in partitions if p == partition
                    ])
                    consumer.seek_to_end(topic, partition)
                    end_offset = consumer.position(topic, partition)

                    lag = end_offset - current_offset
                    total_lag += lag

                    if topic not in lag_by_topic:
                        lag_by_topic[topic] = {}
                    lag_by_topic[topic][partition] = {
                        "current_offset": current_offset,
                        "end_offset": end_offset,
                        "lag": lag,
                    }

                consumer.close()

            return {
                "total_lag": total_lag,
                "lag_by_topic": lag_by_topic,
            }
        except Exception as e:
            self.logger.warning(f"Could not calculate lag for group {group_id}: {e}")
            return {"error": str(e)}

    def _get_acls(self, admin_client: KafkaAdminClient) -> Dict[str, Any]:
        """Get ACL configuration."""
        self.logger.info("  Collecting ACL information...")

        try:
            acls = admin_client.describe_acls()
            acl_list = []

            for resource_type, rules in acls.items():
                for rule in rules:
                    acl_list.append({
                        "resource_type": str(resource_type),
                        "resource_name": rule.resource_name,
                        "principal": rule.principal,
                        "host": rule.host,
                        "operation": rule.operation,
                        "permission_type": rule.permission_type,
                    })

            return {
                "count": len(acl_list),
                "acls": acl_list,
            }
        except KafkaError as e:
            self.logger.error(f"Failed to get ACLs: {e}")
            return {"error": str(e)}

    def _get_broker_configs(self, admin_client: KafkaAdminClient) -> Dict[str, Any]:
        """Get broker configurations."""
        self.logger.info("  Collecting broker configurations...")

        try:
            # Get cluster metadata to find brokers
            cluster_metadata = admin_client.describe_cluster()
            configs = {}

            for broker in cluster_metadata.brokers:
                broker_id = broker.nodeId
                resource = ConfigResource(ConfigResourceType.BROKER, str(broker_id))

                try:
                    broker_configs = admin_client.describe_configs([resource])
                    for resource_type, config_entries in broker_configs.items():
                        configs[f"broker_{broker_id}"] = {
                            entry.name: {
                                "value": entry.value,
                                "read_only": entry.read_only,
                                "is_default": entry.is_default,
                            }
                            for entry in config_entries
                        }
                except KafkaError as e:
                    self.logger.warning(f"Could not get config for broker {broker_id}: {e}")

            return {"broker_configs": configs}
        except KafkaError as e:
            self.logger.error(f"Failed to get broker configs: {e}")
            return {"error": str(e)}

    def _get_schema_registry_info(self, schema_registry_url: str) -> Dict[str, Any]:
        """Get Schema Registry information."""
        self.logger.info("  Collecting Schema Registry information...")

        try:
            # Get schema subjects
            response = requests.get(f"{schema_registry_url}/subjects", timeout=10)
            response.raise_for_status()
            subjects = response.json()

            schema_info = {
                "subjects_count": len(subjects),
                "subjects": {},
            }

            # Get version info for each subject
            for subject in subjects[:100]:  # Limit to first 100 to avoid timeout
                try:
                    versions_response = requests.get(
                        f"{schema_registry_url}/subjects/{subject}/versions",
                        timeout=10
                    )
                    versions_response.raise_for_status()
                    versions = versions_response.json()

                    schema_info["subjects"][subject] = {
                        "versions": versions,
                    }
                except requests.RequestException as e:
                    self.logger.warning(f"Could not get versions for subject {subject}: {e}")

            return schema_info
        except requests.RequestException as e:
            self.logger.error(f"Failed to get Schema Registry info: {e}")
            return {"error": str(e)}

    def save_report(self, output_path: str) -> None:
        """Save discovery report to file."""
        output_file = Path(output_path)
        output_file.parent.mkdir(parents=True, exist_ok=True)

        with open(output_file, "w") as f:
            json.dump(self.discovery_data, f, indent=2)

        self.logger.info(f"Discovery report saved to {output_path}")


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description="Automate Kafka cluster discovery and evidence collection"
    )
    parser.add_argument(
        "--config",
        required=True,
        help="Path to discovery configuration file (YAML)",
    )
    parser.add_argument(
        "--output",
        default="kafka-discovery-report.json",
        help="Output file path for discovery report (JSON)",
    )
    parser.add_argument(
        "--environment",
        help="Override environment name from config",
    )

    args = parser.parse_args()

    # Load configuration
    with open(args.config, "r") as f:
        config = yaml.safe_load(f)

    if args.environment:
        config["environment"] = args.environment

    # Run discovery
    discovery = KafkaDiscovery(config)
    discovery.discover_all()
    discovery.save_report(args.output)

    print(f"\n✓ Discovery complete. Report saved to {args.output}")


if __name__ == "__main__":
    main()
