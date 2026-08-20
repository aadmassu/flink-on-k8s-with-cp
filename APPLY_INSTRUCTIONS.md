# QA Known-Good Promotion Packet

This packet promotes the tagged, working DEV architecture to QA while retaining QA-specific namespace, DNS, certificate subjects, OAuth group/scope, and variable-group identities.

## Apply byte for byte

Replace these repository paths with the packet contents:

- `.azure-pipelines/confluent-platform.yaml`
- `.azure-pipelines/validate-confluent-platform.yaml`
- `.azure-pipelines/scripts/`
- `apps/confluent-platform/qa/`

Delete the two retired QA root-level duplicates if they still exist:

- `apps/confluent-platform/qa/network-policy.yaml`
- `apps/confluent-platform/qa/rolebindings.yaml`

The canonical replacements are:

- `apps/confluent-platform/qa/network-policy/network-policy.yaml`
- `apps/confluent-platform/qa/rbac/rolebindings.yaml`

Also remove the retired file if it remains after replacing the QA directory:

- `apps/confluent-platform/qa/externalsecrets/externalsecrets-all-disabled.yaml`

Do not modify anything under `apps/confluent-platform/dev/`.

## Identity handling

QA manifests intentionally contain `__QA_OAUTH_*__` tokens. During an `install-or-update` QA run, `render-qa-identities.sh` replaces them in the ephemeral build workspace using the verified client IDs from `kafka-openshift-credentials-qa`. The pipeline fails if an ID is missing, malformed, or a token remains.

The pipeline separately enforces the verified QA Control Center accounts:

- Machine/API client: `0oa1z6d5wjgBLvoKz358`
- Browser SSO client: `0oa1z6cqhxwa1O0UK358`

No client secrets are included in this packet.

## Preserved known-good architecture

- Kafka storage: 300 Gi per broker
- MDS/operator mTLS using `cfk-operator-mds-client-tls`
- Platform `fcb-trust-bundle` mounted as `bundle.p12`
- MDS server truststore uses `bundle.p12`
- No `confluent.metadata.server.ssl.endpoint.identification.algorithm`
- Managed-component TLS enabled
- Control Center and Prometheus storage match DEV
- Canonical network policy and RBAC subdirectories
- QA namespace: `dah-flink-qa`
- QA group/scope: `dahQA_groups` / `11547.DAH(QA)`
- QA floating DNS: `*.apps.qa.ocp.fcbint.net`

## Recommended execution order

1. Commit and push these replacements on `fcb-flink-cp`.
2. Run `create-prereqs` for QA.
3. Confirm the pipeline validates both QA Control Center identities.
4. Run `install-or-update` for QA with all components selected.
5. Allow Kafka and managed-component rollouts to complete.
6. Run `validate-confluent-platform.yaml` with environment `qa`.

