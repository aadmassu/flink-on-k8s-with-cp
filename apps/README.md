# Apps — Helm Values & Kubernetes Manifests

This directory contains all Helm values and Kubernetes manifests for deploying Confluent Platform and Flink on OpenShift, deployed via Azure DevOps pipelines in [`.azure-pipelines/`](../.azure-pipelines/).

---

## Directory Overview

| Directory | Type | Pipeline | Description |
|-----------|------|----------|-------------|
| [`cert-manager/`](cert-manager/) | Helm values | 2-cert-manager | cert-manager for operator webhook TLS |
| [`confluent-operator/`](confluent-operator/) | Helm values | 3-cfk-operator | Confluent for Kubernetes (CFK) operator |
| [`confluent-flink-operator/`](confluent-flink-operator/) | Helm values | 4-flink-operator | Confluent Flink Kubernetes Operator |
| [`confluent-cmf/`](confluent-cmf/) | Helm values | 5-cmf | Confluent Manager for Apache Flink (CMF) |
| [`confluent-flink/`](confluent-flink/) | Plain YAML | 6-flink-crs | Flink CRs (CMFRestClass, FlinkEnvironment, session cluster, PVC) |
| [`confluent-platform/`](confluent-platform/) | Plain YAML | — | Confluent Platform CRs (KRaft, Kafka, SR, Connect, C3) |

---

## Structure

### Helm-based apps (cert-manager, operators, CMF)

```
apps/<component>/
├── dev/values.yaml            # Per-environment Helm overrides
├── qa/values.yaml
├── uat/values.yaml
├── prd/values.yaml
└── openshift-overlay.yaml     # Nullifies security contexts for OpenShift SCC
```

Pipelines install with both value files layered:

```bash
helm upgrade --install <release> <chart> \
  -f apps/<component>/<env>/values.yaml \
  -f apps/<component>/openshift-overlay.yaml
```

### Plain YAML apps (Confluent Platform, Flink CRs)

```
apps/<component>/
├── dev/*.yaml     # Flat manifests with namespace baked in
├── qa/*.yaml
├── uat/*.yaml
└── prd/*.yaml
```

Pipelines apply directly:

```bash
oc apply -f apps/<component>/<env>/
```

---

## Environments

| Environment | Namespace |
|---|---|
| dev | `dah-kafka-dev` |
| qa | `dah-kafka-qa` |
| uat | `dah-kafka-uat` |
| prd | `dah-kafka-prd` |
