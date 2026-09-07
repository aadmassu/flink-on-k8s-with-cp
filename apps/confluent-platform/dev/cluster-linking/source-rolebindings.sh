#!/usr/bin/env bash
# Source-side RBAC for the dev linking principal. Run by the Kafka Admin on a host
# with the Confluent CLI logged in to the SOURCE MDS (https://d11547varc-pgm8.fcpd.fcbint.net:8090).
# The pipeline's discover-source action prints this file with every token resolved.
#
# Tokens: __ENV_CLUSTERLINK_CLIENT_ID__  Okta client id of the linking principal
#         __SOURCE_CLUSTER_ID__          source Kafka cluster id
#         __SOURCE_SR_CLUSTER_ID__       source Schema Registry cluster id (schema-registry)
#         __TOPIC_LINES__ / __GROUP_LINES__  one grant per entry in topics.txt / consumer-groups.txt
set -euo pipefail
P="User:__ENV_CLUSTERLINK_CLIENT_ID__"
K="__SOURCE_CLUSTER_ID__"
SR="__SOURCE_SR_CLUSTER_ID__"

# Cluster link on the source: describe the cluster and read topic data + configs.
confluent iam rbac role-binding create --principal "$P" --role ClusterAdmin --kafka-cluster "$K"
__TOPIC_LINES__

# Consumer offset sync: read committed offsets of the listed groups.
__GROUP_LINES__

# Schema link: the exporter is created on and runs inside the SOURCE SR.
confluent iam rbac role-binding create --principal "$P" --role ClusterAdmin --kafka-cluster "$K" --schema-registry-cluster "$SR"
confluent iam rbac role-binding create --principal "$P" --role DeveloperRead --resource 'Subject:*' --kafka-cluster "$K" --schema-registry-cluster "$SR"

echo "Source-side role bindings applied for $P"
