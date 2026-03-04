# Flink Infrastructure CRs -- Phase-II

Kustomize manifests for Flink infrastructure custom resources:

- **CMFRestClass** — Points to the CMF REST API (`cmf-service.<ns>.svc.cluster.local:80`)
- **FlinkEnvironment** — Scopes Flink defaults (namespace, task slots) and references the CMFRestClass
- **PVC** — 10Gi ReadWriteMany volume for Flink checkpoints and savepoints

## Structure

```
base/              # Base CRs (namespace-agnostic)
dev/               # Kustomize overlay — namespace: confluent-dev
qa/                # Kustomize overlay — namespace: confluent-qa
stg/               # Kustomize overlay — namespace: confluent-stg
prd/               # Kustomize overlay — namespace: confluent-prd
```

## Dependencies

- **CMF** must be deployed and healthy (`cmf-service` endpoint reachable)
- **CFK** must be running (provides the CMFRestClass / FlinkEnvironment CRDs)
- **Flink Kubernetes Operator** must be running (reconciles FlinkDeployment CRs created by CMF)
