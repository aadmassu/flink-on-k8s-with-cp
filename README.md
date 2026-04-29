# Confluent Platform & Flink on OpenShift

Helm values, manifests, and Azure DevOps pipelines for deploying Confluent Platform and Apache Flink on OpenShift.

## Structure

```
apps/
├── cert-manager/          # TLS certificate management (operator webhooks)
├── confluent-operator/    # Confluent for Kubernetes (CFK) operator
├── confluent-flink-operator/  # Confluent Flink Kubernetes Operator
├── confluent-cmf/         # Confluent Manager for Apache Flink
├── confluent-flink/       # Flink CRs (FlinkDeployment, FlinkEnvironment, CMFRestClass)
└── confluent-platform/    # Confluent Platform CRs (Kafka, SR, Connect, C3, KRaft)

.azure-pipelines/
├── 1-prereqs.yaml         # Namespaces, SCC, license secret
├── 2-cert-manager.yaml    # cert-manager via Helm
├── 3-cfk-operator.yaml    # CFK Operator via Helm + webhook TLS
├── 4-flink-operator.yaml  # Flink Operator via Helm
├── 5-cmf.yaml             # CMF via Helm (local chart)
└── 6-flink-crs.yaml       # Flink CRs via oc apply

charts/                    # Local Helm charts (vendored)
```

## Environments

Each app has per-environment values with namespace baked in:

| Environment | Namespace |
|---|---|
| dev | `dah-kafka-dev` |
| qa | `dah-kafka-qa` |
| uat | `dah-kafka-uat` |
| prd | `dah-kafka-prd` |

## Deployment

Pipelines are run in order 1-6 via Azure DevOps. Each pipeline requires the `Openshift-ROSA-VAR-Groups` variable group with:

- `OPENSHIFT_SERVER` — OpenShift API URL
- `OPENSHIFT_TOKEN` — login token (secret)
- `CONFLUENT_LICENSE` — Confluent license JWT (secret)
