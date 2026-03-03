# Confluent Flink Manager (CMF) -- Phase 2

This directory will contain **ArgoCD `Application` resources** for deploying [Confluent Manager for Apache Flink (CMF)](https://docs.confluent.io/confluent-manager-for-apache-flink/current/overview.html) in a future phase.

## Current Status

CMF manifests have been removed as part of the Phase 1 scope, which focuses on deploying operators only (cert-manager, Confluent Operator, Flink Operator). Confluent Platform runs on VMs, not Kubernetes.

## Phase 2 Plan

In Phase 2, this directory will be populated with:

- Per-environment CMF `Application` manifests under `openshift/{dev,qa,stg,prd}/manifests/`
- A corresponding `confluent-flink-application-set.yaml` per environment in `gitops-config/openshift/`
- CMF configured to connect to the external Confluent Platform running on VMs

## Dependencies

- **Flink Kubernetes Operator** must be running in the target cluster (see `../confluent-flink-operator/`)
- **Confluent Platform** must be accessible from the OpenShift cluster (running on VMs)
