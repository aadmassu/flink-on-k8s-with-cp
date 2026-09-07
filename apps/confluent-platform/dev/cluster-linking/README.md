# Cluster Linking + Schema Linking — dev

Configuration for the one-way link **VM DEV Confluent Platform (cp-confluent/dev) → CFK `dah-flink-dev`**. Everything here is
consumed by `.azure-pipelines/cluster-linking.yaml` (environment dropdown = `dev`).
No credential values live in this folder.

| File | Purpose |
|---|---|
| `link.env` | Endpoints, names, scope. `@vargroup` / `@discover` / `@live` markers are resolved at run time. |
| `clusterlink.yaml` | `ClusterLink` CR template. The pipeline renders `mirrorTopics`, `consumerGroupFilters`, `aclFilters` and the source cluster ID into it. |
| `topics.txt` | Topics to mirror (one per line, optional `source=mirror` rename). |
| `promote-topics.txt` | Mirror topics to promote on the next `promote` run. Keep entries after promotion. |
| `consumer-groups.txt` | Groups whose offsets sync (`name\|patternType\|filterType`). Empty file disables offset sync. |
| `acls.txt` | ACLs to sync (7 pipe-separated fields). Empty file disables ACL sync. |
| `schemaexporter.yaml` | `SchemaExporter` CR template. The pipeline renders `subjects`. |
| `subjects.txt` | Subjects to export (`*` = whole default context). |
| `rbac/clusterlink-rolebindings.yaml` | Destination-side `ConfluentRolebinding`s for the linking principal. |
| `source-rolebindings.sh` | Source-side grants for the Kafka Admin (`discover-source` prints it fully rendered). |

## Identity and secrets

One Okta client (the *linking principal*) is used for the cluster link and the schema
link. The pipeline's `linkPrincipal` dropdown picks which existing pair in variable group
`kafka-openshift-credentials-dev` supplies it (default `oauth-broker`, the VM broker/MDS
client that is already a super.user on the VM side):

| `linkPrincipal` | Variables read |
|---|---|
| `oauth-broker` (default) | `dev-oauth-broker-client-id` / `-client-secret` |
| `oauth-mds-rest` | `dev-oauth-mds-rest-client-id` / `-client-secret` |
| `oauth-schemaregistry` | `dev-oauth-schemaregistry-client-id` / `-client-secret` |
| `clusterlink` | `dev-clusterlink-oauth-client-id` / `-client-secret` (dedicated client, once issued) |

Whichever pair is chosen lands in Secret `oauth-clusterlink` (same five-key layout as the
other `oauth-*` Secrets) and is rendered over `__ENV_CLUSTERLINK_CLIENT_ID__` in `rbac/`.

Source endpoints come from the same variable group when `link.env` says `@vargroup`:
`dev-kafka-broker-hosts` (port rewritten to `SOURCE_BOOTSTRAP_PORT`),
`dev-schema-registry-hosts` (first host, `SOURCE_SR_PORT`), and
`kafka-oauthbearer-token-endpoint-url`. `SOURCE_HOST_PREFIX` fails the run if the hosts
belong to another environment's VM cluster.

`create-link-prereqs` also builds Secret `clusterlink-source-ca` from
`apps/confluent-platform/common/ca-certificates/*.pem` plus the `ca.crt` of `kafka-tls`,
so the destination brokers and the operator trust the source endpoints.

## Pipeline actions (in order)

1. `discover-source` — prints source cluster ID, topics, groups, subjects, and the rendered `source-rolebindings.sh` for the Kafka Admin. Read-only.
2. `create-link-prereqs` — creates the two Secrets and applies `rbac/`.
3. `validate` — static checks on this folder plus live checks (Kafka cluster-ready, KafkaRestClass, Secrets, source reachability from a broker pod, SchemaExporter extension on both SRs, dry-run of the rendered CRs).
4. `provision-cluster-link` — renders and applies `clusterlink.yaml`, waits for the link and every mirror topic to report ACTIVE.
5. `provision-schema-link` — renders and applies `schemaexporter.yaml`, waits for RUNNING.
6. `mirror-status` — status table for every mirror topic (state, lag per partition, last fetch) plus link and exporter diagnostics. Published as a pipeline artifact.
7. `promote` — promotes the topics in `promote-topics.txt` (refuses when lag > 0), verifies STOPPED.
8. `failover` — emergency only; takes a comma-separated topic list and a confirm checkbox.
9. `delete-link` — removes the exporter and the link (all remaining mirrors fail over). Confirm checkbox required.

## Prerequisites outside this repo

- Source Schema Registry must load `io.confluent.schema.exporter.SchemaExporterResourceExtension`,
  `kafkastore.update.handlers=...SchemaExporterUpdateHandler`, and set `password.encoder.secret`.
  `validate` probes `/exporters` on the source SR and fails if the extension is missing.
- Source-side role bindings from `source-rolebindings.sh` (Kafka Admin).
- Network: CFK broker pods → source brokers on 9092; CFK operator → source SR on 8081;
  source SR → `DEST_SR_PUBLIC_URL` on 443. Use `connectivity-test.yaml` for the first two.
