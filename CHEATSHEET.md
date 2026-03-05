# Command Cheatsheet

Quick reference for `oc` and `helm` commands used in this project on OpenShift.

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

# Confluent Operator CRDs (CFK)
oc get crd kafkas.platform.confluent.io

# Flink CRDs
oc get crd flinkdeployments.flink.apache.org

# CMF CRDs (Phase-II)
oc get crd cmfrestclasses.platform.confluent.io
oc get crd flinkenvironments.platform.confluent.io
```

---

## Troubleshooting

```bash
# Check OpenShift GitOps pods
oc get pods -n openshift-gitops

# ArgoCD controller logs
oc logs -n openshift-gitops -l app.kubernetes.io/name=openshift-gitops-application-controller --tail=50

# cert-manager webhook status
oc get pods -n cert-manager -l app.kubernetes.io/component=webhook

# List registered clusters in ArgoCD
oc get secrets -n openshift-gitops -l argocd.argoproj.io/secret-type=cluster

# Check pod events (for debugging failures)
oc describe pod <pod-name> -n <namespace>

# Check operator logs
oc logs -n confluent-<env> -l app=confluent-operator --tail=50
oc logs -n confluent-<env> -l app.kubernetes.io/name=flink-kubernetes-operator --tail=50
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

## Tear Down

### Automated

```bash
./scripts/destroy-openshift-dev.sh
```

This script deletes ApplicationSets (in reverse order), removes the SCC
prerequisites, and deletes the `confluent-dev` and `cert-manager` namespaces.
The OpenShift GitOps Operator and `openshift-gitops` namespace are **not**
removed -- they are managed by the OperatorHub subscription.

### Manual

```bash
# Delete all ArgoCD-managed applications
oc delete applications --all -n openshift-gitops

# Delete OpenShift prerequisites (SCC + bindings)
oc delete -f openshift-prereqs/<env>/manifests/ --ignore-not-found

# Delete namespaces
oc delete ns confluent-<env> cert-manager --wait --timeout=120s
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

### Restart operators

```bash
oc rollout restart deployment -n confluent-<env> -l app=confluent-operator
oc rollout restart deployment -n confluent-<env> -l app.kubernetes.io/name=flink-kubernetes-operator
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

# Deploy ApplicationSets
oc apply -f gitops-config/openshift/${ENV}/cert-manager-application-set.yaml
oc apply -f gitops-config/openshift/${ENV}/confluent-operator-application-set.yaml
oc apply -f gitops-config/openshift/${ENV}/confluent-flink-operator-application-set.yaml

# Verify
oc get pods -n confluent-${ENV}
oc get applications -n openshift-gitops
```
