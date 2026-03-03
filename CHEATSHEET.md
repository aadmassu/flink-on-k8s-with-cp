# Command Cheatsheet

Quick reference for all kubectl, helm, and oc commands used in this project.

---

## Cluster Connectivity

```bash
# Verify current context
kubectl config get-contexts

# Check cluster info
kubectl cluster-info

# OpenShift: verify login
oc whoami
oc cluster-info
oc version
```

---

## Helm Repositories

```bash
# Add all required repos
helm repo add argo-cd https://argoproj.github.io/argo-helm
helm repo add confluent https://packages.confluent.io/helm
helm repo add jetstack https://charts.jetstack.io
helm repo update
```

---

## ArgoCD

### Install

```bash
helm install argocd argo-cd/argo-cd \
  --namespace argocd \
  --create-namespace \
  -f apps/argocd/<env>/values.yaml \
  --wait --timeout 5m
```

### Upgrade

```bash
helm upgrade argocd argo-cd/argo-cd \
  --namespace argocd \
  -f apps/argocd/<env>/values.yaml \
  --wait --timeout 5m
```

### Uninstall

```bash
helm uninstall argocd --namespace argocd
```

### Verify

```bash
kubectl get pods -n argocd
kubectl get svc argocd-server -n argocd
```

### Get URL (LoadBalancer)

```bash
kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

### Get Admin Password

```bash
# Standard ArgoCD
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# OpenShift GitOps
oc -n openshift-gitops get secret openshift-gitops-cluster -o jsonpath='{.data.admin\.password}' | base64 -d
```

### OpenShift Route

```bash
# Create Route
oc create route passthrough argocd-server \
  --service=argocd-server \
  --port=https \
  --namespace=argocd

# Get Route URL
oc get route argocd-server -n argocd -o jsonpath='{.spec.host}'

# OpenShift GitOps Route
oc get route openshift-gitops-server -n openshift-gitops -o jsonpath='{.spec.host}'
```

---

## Deploy Applications

### cert-manager

```bash
kubectl apply -f gitops-config/aws-us-east-2/<env>/cert-manager-application-set.yaml

kubectl wait --for=jsonpath='{.status.health.status}'=Healthy \
  application/cert-manager-<env> -n argocd --timeout=180s

kubectl get pods -n cert-manager
```

### Confluent Operator

```bash
kubectl apply -f gitops-config/aws-us-east-2/<env>/confluent-operator-application-set.yaml

kubectl wait --for=jsonpath='{.status.health.status}'=Healthy \
  application/confluent-operator-<env> -n argocd --timeout=180s

kubectl get pods -n confluent-<env> -l app=confluent-operator
```

### Flink Operator

```bash
kubectl apply -f gitops-config/aws-us-east-2/<env>/confluent-flink-operator-application-set.yaml

kubectl wait --for=jsonpath='{.status.health.status}'=Healthy \
  application/confluent-flink-operator-<env> -n argocd --timeout=180s

kubectl get pods -n confluent-<env>
```

---

## ArgoCD Application Status

```bash
# List all applications
kubectl get applications -n argocd

# Detailed status table
kubectl get applications -n argocd -o custom-columns=\
NAME:.metadata.name,\
HEALTH:.status.health.status,\
SYNC:.status.sync.status,\
NAMESPACE:.spec.destination.namespace

# Describe a specific application
kubectl describe application <app-name> -n argocd

# Get sync status
kubectl get application <app-name> -n argocd -o jsonpath='{.status.sync.status}'

# Get health status
kubectl get application <app-name> -n argocd -o jsonpath='{.status.health.status}'
```

---

## Verify CRDs

```bash
# ArgoCD Application CRD
kubectl get crd applications.argoproj.io

# cert-manager CRDs
kubectl get crd certificates.cert-manager.io

# Confluent Platform CRDs
kubectl get crd kafkas.platform.confluent.io
```

---

## Troubleshooting

```bash
# Find ArgoCD namespace
kubectl get pods --all-namespaces | grep argocd

# ArgoCD controller logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller --tail=50

# cert-manager webhook status
kubectl get pods -n cert-manager -l app.kubernetes.io/component=webhook

# List registered clusters in ArgoCD
kubectl get secrets -n argocd -l argocd.argoproj.io/secret-type=cluster

# Check pod events (for debugging failures)
kubectl describe pod <pod-name> -n <namespace>

# Check operator logs
kubectl logs -n confluent-<env> -l app=confluent-operator --tail=50
kubectl logs -n confluent-<env> -l app.kubernetes.io/name=flink-kubernetes-operator --tail=50
```

---

## OpenShift SCC Permissions

```bash
# Confluent operator
oc adm policy add-scc-to-user anyuid -z default -n confluent-<env>
oc adm policy add-scc-to-user anyuid -z confluent-operator -n confluent-<env>

# Flink operator
oc adm policy add-scc-to-user anyuid -z flink-kubernetes-operator -n confluent-<env>

# cert-manager
oc adm policy add-scc-to-user anyuid -z cert-manager -n cert-manager
oc adm policy add-scc-to-user anyuid -z cert-manager-webhook -n cert-manager
oc adm policy add-scc-to-user anyuid -z cert-manager-cainjector -n cert-manager

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

```bash
# Delete all ArgoCD-managed applications
kubectl delete applications --all -n argocd

# Uninstall ArgoCD
helm uninstall argocd --namespace argocd

# Delete namespaces
kubectl delete ns argocd confluent-<env> cert-manager --wait --timeout=120s
```

---

## Quick Reference - Environment Variable Pattern

Most commands in this project follow this pattern. Set `ENV` once and reuse:

```bash
ENV=dev   # Change to: qa, stg, prd

kubectl apply -f gitops-config/aws-us-east-2/${ENV}/cert-manager-application-set.yaml
kubectl apply -f gitops-config/aws-us-east-2/${ENV}/confluent-operator-application-set.yaml
kubectl apply -f gitops-config/aws-us-east-2/${ENV}/confluent-flink-operator-application-set.yaml

kubectl get pods -n confluent-${ENV}
kubectl get applications -n argocd
```
