# Command Cheatsheet

Troubleshooting, break-glass fixes, and diagnostic commands for this project on OpenShift. For deployment steps, see [PHASE-I.md](PHASE-I.md) and [PHASE-II.md](PHASE-II.md).

---

## Cluster Connectivity

```bash
# Verify OpenShift login
oc whoami
oc cluster-info
oc version

# Verify current context
oc config get-contexts

# Check current project
oc project

# Check node availability zones
oc get nodes -L topology.kubernetes.io/zone

# Check node resource allocation (CPU/memory requests vs capacity)
oc describe node <node-name> | grep -A8 'Allocated resources'

# Quick node resource utilization
oc adm top nodes
```

---

## Helm Repositories

```bash
# Add all required repos
helm repo add confluent https://packages.confluent.io/helm
helm repo add jetstack https://charts.jetstack.io
helm repo update
```

---

## OpenShift GitOps (ArgoCD)

The OpenShift GitOps Operator is installed via OperatorHub, not Helm. These
commands verify the operator-managed instance.

### Verify OpenShift GitOps

```bash
# Check the operator subscription
oc get subscription openshift-gitops-operator -n openshift-operators

# Check that the GitOps pods are running
oc get pods -n openshift-gitops

# Check the ArgoCD instance
oc get argocd -n openshift-gitops
```

### Get Route URL

```bash
oc get route openshift-gitops-server -n openshift-gitops -o jsonpath='{.spec.host}'
```

### Get Admin Password

```bash
oc -n openshift-gitops get secret openshift-gitops-cluster -o jsonpath='{.data.admin\.password}' | base64 -d
```

### Force sync a stuck application

```bash
# Hard refresh — force ArgoCD to re-read the git repo
oc annotate application <app-name> -n openshift-gitops argocd.argoproj.io/refresh=hard --overwrite

# Trigger manual sync
oc patch application <app-name> -n openshift-gitops --type merge \
  -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"revision":"HEAD"}}}'

# Force sync with replace (break glass — recreates resources)
oc patch application <app-name> -n openshift-gitops --type merge \
  -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"syncStrategy":{"apply":{"force":true}}}}}'
```

### Clear repo-server cache (stale manifests after git push)

```bash
# Restart repo-server to flush git/manifest cache
oc rollout restart deployment openshift-gitops-repo-server -n openshift-gitops
oc rollout status deployment openshift-gitops-repo-server -n openshift-gitops --timeout=60s
```

### Delete and recreate an Application (stuck operation / wrong spec)

```bash
# Delete the Application object; the ApplicationSet will recreate it
oc delete application <app-name> -n openshift-gitops
```

### Check repo credentials registered in ArgoCD

```bash
oc get secrets -n openshift-gitops -l argocd.argoproj.io/secret-type=repository
```

### Fix "namespace not managed" error

```bash
# Namespace "confluent-dev" for Application ... is not managed
oc label namespace confluent-${ENV} argocd.argoproj.io/managed-by=openshift-gitops --overwrite
oc label namespace cert-manager argocd.argoproj.io/managed-by=openshift-gitops --overwrite
```

---

## Deploy Applications

### cert-manager

```bash
oc apply -f gitops-config/openshift/<env>/cert-manager-application-set.yaml

oc wait --for=jsonpath='{.status.health.status}'=Healthy \
  application/cert-manager-<env> -n openshift-gitops --timeout=180s

oc get pods -n cert-manager
```

### Confluent Operator

```bash
oc apply -f gitops-config/openshift/<env>/confluent-operator-application-set.yaml

oc wait --for=jsonpath='{.status.health.status}'=Healthy \
  application/confluent-operator-<env> -n openshift-gitops --timeout=180s

oc get pods -n confluent-<env> -l app=confluent-operator
```

### Flink Operator

```bash
oc apply -f gitops-config/openshift/<env>/confluent-flink-operator-application-set.yaml

oc wait --for=jsonpath='{.status.health.status}'=Healthy \
  application/confluent-flink-operator-<env> -n openshift-gitops --timeout=180s

oc get pods -n confluent-<env>
```

### CMF (Phase-II)

```bash
oc apply -f gitops-config/openshift/<env>/confluent-cmf-application-set.yaml

oc wait --for=jsonpath='{.status.health.status}'=Healthy \
  application/confluent-cmf-<env> -n openshift-gitops --timeout=180s

oc get pods -n confluent-<env> -l app.kubernetes.io/name=confluent-manager-for-apache-flink
```

### Confluent Platform (Phase-II)

```bash
oc apply -f gitops-config/openshift/<env>/confluent-platform-application-set.yaml

oc wait --for=jsonpath='{.status.health.status}'=Healthy \
  application/confluent-platform-<env> -n openshift-gitops --timeout=300s

# Wait for Kafka to reach RUNNING state
oc get kafka kafka -n confluent-<env> -o jsonpath='{.status.phase}'
```

### Flink Infrastructure (Phase-II)

```bash
oc apply -f gitops-config/openshift/<env>/confluent-flink-application-set.yaml

oc wait --for=jsonpath='{.status.sync.status}'=Synced \
  application/confluent-flink-<env> -n openshift-gitops --timeout=180s

# Verify Flink session cluster is READY
oc get flinkdeployment flink-session -n confluent-<env> \
  -o jsonpath='{.status.jobManagerDeploymentStatus}'

# Access Flink UI
oc port-forward svc/flink-session-rest 8081:8081 -n confluent-<env>
```

---

## ArgoCD Application Status

```bash
# List all applications
oc get applications -n openshift-gitops

# Detailed status table
oc get applications -n openshift-gitops -o custom-columns=\
NAME:.metadata.name,\
HEALTH:.status.health.status,\
SYNC:.status.sync.status,\
NAMESPACE:.spec.destination.namespace

# Describe a specific application
oc describe application <app-name> -n openshift-gitops

# Get sync status
oc get application <app-name> -n openshift-gitops -o jsonpath='{.status.sync.status}'

# Get health status
oc get application <app-name> -n openshift-gitops -o jsonpath='{.status.health.status}'
```

---

## Verify CRDs

```bash
# ArgoCD Application CRD
oc get crd applications.argoproj.io

# cert-manager CRDs
oc get crd certificates.cert-manager.io
oc get crd issuers.cert-manager.io
oc wait --for=condition=Established crd/certificates.cert-manager.io --timeout=60s

# Confluent Operator CRDs (CFK)
oc get crd | grep confluent

# Flink CRDs
oc get crd flinkdeployments.flink.apache.org
oc get crd flinkapplications.cmf.confluent.io

# CMF CRDs (Phase-II)
oc get crd | grep cmf
```

---

## Operator Troubleshooting

### cert-manager

```bash
# Pod and webhook status
oc get pods -n cert-manager
oc get pods -n cert-manager -l app.kubernetes.io/component=webhook

# Logs
oc logs -n cert-manager -l app=cert-manager --tail=100
oc logs -n cert-manager -l app.kubernetes.io/component=webhook --tail=50

# Check certificate issuance
oc get certificates -A
oc describe certificate <name> -n <namespace>
```

### Confluent Operator (CFK)

```bash
# Pod status
oc get pods -n confluent-${ENV} -l app=confluent-operator

# Logs
oc logs -n confluent-${ENV} -l app=confluent-operator --tail=100

# Check CFK-managed resources
oc get confluent -n confluent-${ENV}
```

### Flink Operator

```bash
# Pod status
oc get pods -n confluent-${ENV} -l app.kubernetes.io/name=flink-kubernetes-operator

# Logs
oc logs -n confluent-${ENV} -l app.kubernetes.io/name=flink-kubernetes-operator --tail=100

# Check Flink deployments
oc get flinkdeployments -n confluent-${ENV}
```

### CMF

```bash
# Pod status
oc get pods -n confluent-${ENV} -l app.kubernetes.io/name=confluent-manager-for-apache-flink

# Logs
oc logs -n confluent-${ENV} -l app.kubernetes.io/name=confluent-manager-for-apache-flink --tail=100

# Check CMF service endpoint
oc get svc cmf-service -n confluent-${ENV}

# Check CMFRestClass and FlinkEnvironment status
oc get cmfrestclass -n confluent-${ENV}
oc get flinkenvironment -n confluent-${ENV}
```

### Confluent Platform (local Kafka)

```bash
# Overall status
oc get kafka kafka -n confluent-${ENV} -o jsonpath='{.status.phase}'
oc get pods -n confluent-${ENV}

# Individual component status
oc get kraftcontroller -n confluent-${ENV}
oc get kafka -n confluent-${ENV}
oc get schemaregistry -n confluent-${ENV}
oc get connect -n confluent-${ENV}
oc get controlcenter -n confluent-${ENV}

# Kafka logs
oc logs kafka-0 -n confluent-${ENV} --tail=100
```

---

## Storage / PVC Troubleshooting

```bash
# List StorageClasses available on the cluster
oc get sc

# Check PVC status (Pending = not yet bound)
oc get pvc -n confluent-${ENV}

# Check PV node affinity (volumes may be AZ-locked)
oc get pv <pv-name> -o jsonpath='{.spec.nodeAffinity}' | python3 -m json.tool

# Fix PVC stuck in wrong AZ: delete PVC so it rebinds in the correct AZ
# (pod must be deleted first or will be rescheduled automatically)
oc delete pvc <pvc-name> -n <namespace>

# WaitForFirstConsumer — PVC stays Pending until a pod references it (normal)
oc get pvc <pvc-name> -n <namespace> -o jsonpath='{.status.phase}'
```

---

## Pod Debugging

```bash
# Pod events and conditions
oc describe pod <pod-name> -n <namespace>

# Current logs
oc logs <pod-name> -n <namespace> --tail=100

# Previous container logs (after a crash)
oc logs <pod-name> -n <namespace> --previous

# Namespace events (sorted by time)
oc get events -n <namespace> --sort-by='.lastTimestamp'

# Resource pressure on nodes
oc describe nodes | grep -A5 "Conditions"
oc adm top nodes
oc adm top pods -n confluent-${ENV}
```

---

## Scheduling / Resource Issues

```bash
# Pod stuck in Pending — check why it can't be scheduled
oc describe pod <pod-name> -n <namespace> | tail -15

# Check per-node CPU/memory allocation (look for >90% requests)
oc describe node <node-name> | grep -A8 'Allocated resources'

# List pods sorted by CPU requests (find resource hogs)
oc get pods -n confluent-${ENV} -o custom-columns=\
'NAME:.metadata.name,CPU_REQ:.spec.containers[0].resources.requests.cpu,MEM_REQ:.spec.containers[0].resources.requests.memory'

# Check for taints preventing scheduling
oc get nodes -o custom-columns='NAME:.metadata.name,TAINTS:.spec.taints'
```

---

## OpenShift SCC Permissions

### Declarative (recommended)

Apply the pre-built SCC and ClusterRoleBinding manifests for each environment:

```bash
oc apply -f openshift-prereqs/<env>/manifests/
```

This applies `confluent-scc.yaml` and `scc-bindings.yaml` for the target
environment (dev, qa, stg, prd).

### Imperative (break-glass / quick PoC only)

> **Warning:** These commands bind the built-in `anyuid` SCC, which is broader than the custom `confluent-scc`. Use the declarative approach above for production deployments.

```bash
# Confluent operator
oc adm policy add-scc-to-user anyuid -z confluent-operator -n confluent-<env>

# Flink operator
oc adm policy add-scc-to-user anyuid -z flink-kubernetes-operator -n confluent-<env>

# cert-manager
oc adm policy add-scc-to-user anyuid -z cert-manager -n cert-manager
oc adm policy add-scc-to-user anyuid -z cert-manager-webhook -n cert-manager
oc adm policy add-scc-to-user anyuid -z cert-manager-cainjector -n cert-manager
```

### Inspect SCC assignments

```bash
# Check which SCC a pod is using
oc get pod <pod-name> -n <namespace> -o jsonpath='{.metadata.annotations.openshift\.io/scc}'

# Check service account for a pod
oc get pod <pod-name> -n <namespace> -o jsonpath='{.spec.serviceAccountName}'
```

---

## OpenShift GitOps Namespace Management

```bash
# Label namespaces for OpenShift GitOps access
oc label namespace confluent-<env> argocd.argoproj.io/managed-by=openshift-gitops
oc label namespace cert-manager argocd.argoproj.io/managed-by=openshift-gitops

# Grant cluster-admin (alternative, broader access)
oc adm policy add-cluster-role-to-user cluster-admin \
  system:serviceaccount:openshift-gitops:openshift-gitops-argocd-application-controller
```

---

## Git Multi-Remote

```bash
# List configured remotes
git remote -v

# Push to both remotes (origin=GitHub, azure=Azure DevOps)
git push origin <branch>
git push azure <branch>

# Check what branches exist on a remote
git ls-remote --heads <remote-name>
```

---

## Tear Down

### Automated

```bash
./scripts/destroy-openshift-dev.sh
```

This script deletes ApplicationSets (in reverse order), removes the SCC
prerequisites, and deletes the `confluent-dev` and `cert-manager` namespaces.
The OpenShift GitOps Operator and `openshift-gitops` namespace are **not**
removed -- they are managed by the OperatorHub subscription.

### Manual (reverse order)

```bash
ENV=dev

# Phase-II first
oc delete applicationset confluent-flink-${ENV} -n openshift-gitops --ignore-not-found
oc delete applicationset confluent-platform-${ENV} -n openshift-gitops --ignore-not-found
oc delete applicationset confluent-cmf-${ENV} -n openshift-gitops --ignore-not-found

# Then Phase-I
oc delete applicationset confluent-flink-operator-${ENV} -n openshift-gitops --ignore-not-found
oc delete applicationset confluent-operator-${ENV} -n openshift-gitops --ignore-not-found
oc delete applicationset cert-manager-${ENV} -n openshift-gitops --ignore-not-found

# Delete OpenShift prerequisites (SCC + bindings)
oc delete -f openshift-prereqs/${ENV}/manifests/ --ignore-not-found

# Wait for cleanup then delete namespaces
oc wait --for=delete application/confluent-flink-${ENV} -n openshift-gitops --timeout=120s 2>/dev/null || true
oc delete ns confluent-${ENV} cert-manager --wait --timeout=120s
```

---

## Break-Glass Fixes

### Clear stuck finalizers (CFK/Flink CRs)

If namespaces won't delete because CRs have finalizers and operators are gone:

```bash
for KIND in cmfrestclass flinkenvironment flinkdeployment kafka kraftcontroller connect \
            controlcenter schemaregistry; do
  for RESOURCE in $(oc get "$KIND" -n confluent-<env> -o name 2>/dev/null); do
    oc patch "$RESOURCE" -n confluent-<env> --type merge \
      -p '{"metadata":{"finalizers":null}}'
  done
done
```

### Clear stuck finalizers (ArgoCD Applications)

```bash
for APP in $(oc get applications -n openshift-gitops -o name 2>/dev/null); do
  oc patch "$APP" -n openshift-gitops --type merge \
    -p '{"metadata":{"finalizers":null}}'
done
```

### Restart a stuck operator

```bash
oc rollout restart deployment/<deployment-name> -n confluent-${ENV}
oc rollout status deployment/<deployment-name> -n confluent-${ENV} --timeout=120s
```

### Delete and let ArgoCD recreate a resource

```bash
# ArgoCD will recreate the resource on next sync (if selfHeal is on)
oc delete pod <pod-name> -n <namespace>

# Force ArgoCD to sync after manual deletion
oc annotate application <app-name> -n openshift-gitops argocd.argoproj.io/refresh=hard --overwrite
```

### Manually remove finalizers from a stuck resource

```bash
# Use when a resource is stuck in Terminating state
oc patch <resource-type> <name> -n <namespace> --type merge \
  -p '{"metadata":{"finalizers":null}}'
```

### Reset cert-manager if webhooks are broken

```bash
# Delete the webhook configs and let cert-manager recreate them
oc delete validatingwebhookconfiguration cert-manager-webhook --ignore-not-found
oc delete mutatingwebhookconfiguration cert-manager-webhook --ignore-not-found
oc rollout restart deployment/cert-manager-webhook -n cert-manager
```

---

## Verify Deployment

```bash
# Automated verification
./scripts/verify-openshift-dev.sh
```

---

## Quick Reference - Environment Variable Pattern

Most commands in this project follow this pattern. Set `ENV` once and reuse:

```bash
ENV=dev   # Change to: qa, stg, prd

# Apply SCC prerequisites
oc apply -f openshift-prereqs/${ENV}/manifests/

# Deploy ApplicationSets (Phase-I)
oc apply -f gitops-config/openshift/${ENV}/cert-manager-application-set.yaml
oc apply -f gitops-config/openshift/${ENV}/confluent-operator-application-set.yaml
oc apply -f gitops-config/openshift/${ENV}/confluent-flink-operator-application-set.yaml

# Deploy ApplicationSets (Phase-II)
oc apply -f gitops-config/openshift/${ENV}/confluent-cmf-application-set.yaml
oc apply -f gitops-config/openshift/${ENV}/confluent-platform-application-set.yaml
oc apply -f gitops-config/openshift/${ENV}/confluent-flink-application-set.yaml

# Verify
oc get pods -n confluent-${ENV}
oc get applications -n openshift-gitops
```
