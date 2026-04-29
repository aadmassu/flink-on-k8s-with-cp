# Flink Infrastructure CRs -- Phase-II

Kustomize manifests for Flink infrastructure custom resources:

- **CMFRestClass** — Points to the CMF REST API (`cmf-service.<ns>.svc.cluster.local:80`)
- **FlinkEnvironment** — Scopes Flink defaults (namespace, task slots) and references the CMFRestClass
- **FlinkDeployment (session cluster)** — Long-running Flink session cluster (`flink-session`) for interactive SQL
- **KafkaCatalog** — Connects Flink SQL to Kafka and Schema Registry for topic/schema discovery *(commented out — requires `cmf.confluent.io` CRD)*
- **PVC** — 10Gi ReadWriteMany volume for Flink checkpoints and savepoints

## Structure

```
base/
  cmf-rest-class.yaml           # CMFRestClass CR
  flink-environment.yaml        # FlinkEnvironment CR
  flink-pvc.yaml                # PVC for checkpoints/savepoints
  flink-session-cluster.yaml    # FlinkDeployment — Flink session cluster
  kafka-catalog.yaml            # KafkaCatalog CR (commented out in kustomization)
  kustomization.yaml            # Base kustomization
dev/                            # Kustomize overlay — namespace: confluent-dev
qa/                             # Kustomize overlay — namespace: confluent-qa
uat/                            # Kustomize overlay — namespace: confluent-uat
prd/                            # Kustomize overlay — namespace: confluent-prd
```

## Dependencies

- **CMF** must be deployed and healthy (`cmf-service` endpoint reachable)
- **CFK** must be running (provides the CMFRestClass / FlinkEnvironment CRDs)
- **Flink Kubernetes Operator** must be running (reconciles FlinkDeployment CRs created by CMF)
