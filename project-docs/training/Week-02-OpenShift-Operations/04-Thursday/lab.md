# Week 2 Thursday — Lab: GitOps Strategies hands-on (Push vs Pull, and the Boundary)

## Goal

Land the discussion in your terminal:

1. **Part 1** — *Read-through* of Strategy A's pipeline shape in this repo (the Azure DevOps push pattern).
2. **Part 2** — *Hands-on* simulation of Strategy A's drift-blind behavior. Apply once, change manually, observe no reconcile.
3. **Part 3** — *Hands-on* with Strategy B: install ArgoCD on your kind cluster, create an Application, observe `selfHeal` reverting drift.
4. **Part 4** — *Hands-on* simulation of the **cross-boundary dependency**: a workload that needs a ServiceAccount the other "lane" is supposed to provide. You'll feel the failure shape and the triage rule.
5. **Part 5** — *Read-through* of Strategy B in the sister `openshift-cfk-gitops` repo: walk the actual `Application` + `AppProject` CRs you'll see in real customer environments.

Every command is given in both `oc` and `kubectl` forms. Run only the one that matches your cluster.

## Pick your local cluster

The kind training cluster you rebuilt last Friday — `lab-cluster/` — is the right target. ArgoCD will be installed *on top* of it; the existing `kafka-dev` namespace with the CFK install stays untouched.

```bash
# kind
kind get clusters                          # expect: training
kubectl config use-context kind-training
kubectl get nodes

# oc / OpenShift Local (CRC) / any oc-connected cluster
oc whoami --show-server
oc get nodes
```

> The lab uses a fresh namespace `gitops-lab` for Parts 2 + 4 to keep the existing `kafka-dev` CFK install isolated. ArgoCD installs to its own `argocd` namespace.

```bash
# kubectl
kubectl create namespace gitops-lab --dry-run=client -o yaml | kubectl apply -f -

# oc
oc new-project gitops-lab || oc project gitops-lab
```

---

## Part 1 — Read-through: Strategy A (Azure DevOps push) in this repo

You can't run Azure DevOps locally, but you have the *real* pipeline files in front of you. The point of this section is to **identify the deploy contract elements** so when an engineer hands you a pipeline YAML on a customer engagement you can read it cold.

Open each of these files and find the elements listed in the table below:

```
.azure-pipelines/
├── confluent-platform.yaml    → deploys CFK CRs (Kafka, KRaftController, SR, Connect, C3)
├── cmf.yaml                   → installs CMF via Helm
├── cmf-tls.yaml               → renders the cert-manager Certificate for CMF
├── flink-environments.yaml    → creates Flink env + Kafka catalog + database via CMF REST API
├── connectivity-test.yaml     → probes outbound dependencies
├── diagnostics.yaml           → read-only cluster-state dump
└── templates/
    ├── install-tools.yaml     → installs oc + helm on the agent
    └── diagnostics-step.yaml  → reusable diagnostics body
```

| Deploy contract element | Where to look | What you should find |
|---|---|---|
| **Trigger** | `trigger:` block at the top of each pipeline | `trigger: none` — pipelines run manually or on `parameters` change. No commit-driven auto-run. |
| **Parameters / per-env knob** | `parameters:` block | A `environment` enum across `dev, qa, uat, prd, dr` — the same pipeline body, env-selected at trigger time. |
| **Variable group binding** | `variables:` block, conditional on parameter | One `group: kafka-openshift-credentials-<env>` per env — that's where secrets/URLs/SA tokens come from. |
| **Cluster auth** | First `Bash@3` task in the steps | `oc login` with `$OC_USER` + `$OC_PWD` (the SA token from the variable group). |
| **Apply step** | A middle `Bash@3` task | Either `helm upgrade --install ... -f apps/.../values.yaml` (for `cmf.yaml`) or `oc apply -f apps/confluent-platform/<env>/` (for `confluent-platform.yaml`). |
| **Side effects** | Other tasks beyond apply | `flink-environments.yaml` calls the CMF REST API after the apply. `connectivity-test.yaml` runs outbound TCP probes. These are *not* possible with a pure GitOps controller. |
| **Idempotency** | Look for `--ignore-not-found`, `if [ ... ]; then ... fi`, `oc get ... 2>/dev/null` | The pipeline scripts handle "already exists" cases manually, with shell guards. No automatic reconcile. |
| **Exit behavior** | Bottom of each pipeline | Pipeline runs to completion, reports success/failure, and **exits**. There's no controller watching afterward. |

### Exercise — write up in your deliverable

Pick **one** pipeline (suggested: `cmf.yaml`) and trace it line-by-line. In your deliverable, answer:

1. What does the pipeline do BEFORE the actual `helm install`? (Hint: `install-tools`, `oc login`, secret existence checks.)
2. What does it do AFTER `helm install` succeeds? (Hint: `helm status`, `oc get pods`.)
3. If step N fails halfway through, what state is the cluster in?
4. How would you know if someone `oc edit`-ed the CMF Deployment after this pipeline finished?
5. If you needed to write the same deploy as an ArgoCD Application, what would you LOSE in the translation?

---

## Part 2 — Hands-on: simulate Strategy A's drift-blind behavior locally

Strategy A applies once and exits. There's no continuous reconcile. To feel that on your kind cluster, you'll write the simplest possible "push deploy script" — apply a manifest, then walk away. Then you'll change the cluster manually and observe nothing reverts.

### 2.1 The "push deploy" — apply once

Apply a simple Deployment with a known replica count and image:

```bash
# kubectl
kubectl -n gitops-lab apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: push-app
  labels: {app: push-app, deployed-by: push-strategy}
spec:
  replicas: 2
  selector:
    matchLabels: {app: push-app}
  template:
    metadata:
      labels: {app: push-app}
    spec:
      containers:
        - name: app
          image: hashicorp/http-echo:1.0
          args: ["-text=push-strategy version 1"]
          ports: [{containerPort: 5678}]
EOF

# oc
oc -n gitops-lab apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: push-app
  labels: {app: push-app, deployed-by: push-strategy}
spec:
  replicas: 2
  selector:
    matchLabels: {app: push-app}
  template:
    metadata:
      labels: {app: push-app}
    spec:
      containers:
        - name: app
          image: hashicorp/http-echo:1.0
          args: ["-text=push-strategy version 1"]
          ports: [{containerPort: 5678}]
EOF
```

That `apply` is your "pipeline" — it ran once and exited. Verify it landed:

```bash
# kubectl
kubectl -n gitops-lab get deployment push-app

# oc
oc -n gitops-lab get deployment push-app
```

Two replicas Ready.

### 2.2 Manual change — simulate "engineer edited the cluster"

Now act like a tired on-call engineer who scaled up by hand to deal with a spike:

```bash
# kubectl
kubectl -n gitops-lab scale deployment/push-app --replicas=5

# oc
oc -n gitops-lab scale deployment/push-app --replicas=5
```

Wait 30 seconds. Did anything revert?

```bash
# kubectl
sleep 30
kubectl -n gitops-lab get deployment push-app

# oc
sleep 30
oc -n gitops-lab get deployment push-app
```

**Five replicas.** Nothing reverted. There's no controller watching. The cluster has drifted from what you originally applied, and Strategy A has no way to know.

This is the **drift-blind** behavior the discussion calls out. In real Azure DevOps deploys, the drift stays invisible until the next pipeline run — at which point it's overwritten (or the pipeline fails if the engineer also changed something irreversible).

### 2.3 Document the moment

Capture for your deliverable:

```bash
# kubectl
kubectl -n gitops-lab get deployment push-app -o jsonpath='{.spec.replicas}' ; echo "  (live)"

# oc
oc -n gitops-lab get deployment push-app -o jsonpath='{.spec.replicas}' ; echo "  (live)"
```

The "live" replica count differs from what your `apply` declared. Note this gap — Part 3 closes it.

---

## Part 3 — Hands-on: Strategy B (ArgoCD pull) with `selfHeal`

Now install ArgoCD on the kind cluster, point it at a public Git repo, watch it reconcile.

### 3.1 Install ArgoCD

```bash
# kubectl — works on kind directly
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl -n argocd wait --for=condition=Available deployment --all --timeout=180s

# oc — same install on OCP / CRC (skip if your cluster already has OpenShift GitOps Operator)
oc new-project argocd || oc project argocd
oc apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
oc -n argocd wait --for=condition=Available deployment --all --timeout=180s
```

Confirm pods are Ready:

```bash
# kubectl
kubectl -n argocd get pods

# oc
oc -n argocd get pods
```

You should see `argocd-server`, `argocd-application-controller`, `argocd-repo-server`, `argocd-redis`, `argocd-applicationset-controller`, `argocd-dex-server`, `argocd-notifications-controller` — those are the moving parts the discussion described.

### 3.2 Open the ArgoCD Web UI (optional but worth a look)

```bash
# kubectl — port-forward
kubectl -n argocd port-forward svc/argocd-server 8080:443 &
sleep 3

# oc — same
oc -n argocd port-forward svc/argocd-server 8080:443 &
sleep 3
```

Now grab the initial admin password and open the UI:

```bash
# kubectl
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d ; echo
echo "Open https://localhost:8080 — accept the self-signed cert, login as admin with the password above"

# oc
oc -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d ; echo
echo "Open https://localhost:8080 — accept the self-signed cert, login as admin with the password above"
```

Leave the port-forward running in the background for now; you'll use it again.

### 3.3 Create your first Application

Point ArgoCD at the public `argoproj/argocd-example-apps` repo, deploying the `guestbook` sample into your `gitops-lab` namespace.

```bash
# kubectl
kubectl apply -f - <<'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: guestbook
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/argoproj/argocd-example-apps.git
    path: guestbook
    targetRevision: HEAD
  destination:
    server: https://kubernetes.default.svc
    namespace: gitops-lab
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF

# oc
oc apply -f - <<'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: guestbook
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/argoproj/argocd-example-apps.git
    path: guestbook
    targetRevision: HEAD
  destination:
    server: https://kubernetes.default.svc
    namespace: gitops-lab
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF
```

Watch the sync happen:

```bash
# kubectl
sleep 15
kubectl -n argocd get application guestbook -o jsonpath='Sync={.status.sync.status} Health={.status.health.status}{"\n"}'
kubectl -n gitops-lab get all -l app=guestbook-ui

# oc
sleep 15
oc -n argocd get application guestbook -o jsonpath='Sync={.status.sync.status} Health={.status.health.status}{"\n"}'
oc -n gitops-lab get all -l app=guestbook-ui
```

Expect `Sync=Synced Health=Healthy` once the Pod is Ready.

### 3.4 Observe `selfHeal` — manual change gets reverted

Just like Part 2, scale up by hand. Unlike Part 2, ArgoCD is watching now.

```bash
# kubectl
kubectl -n gitops-lab scale deployment/guestbook-ui --replicas=5
kubectl -n gitops-lab get deployment guestbook-ui -w &
sleep 90
kill %1 2>/dev/null

# oc
oc -n gitops-lab scale deployment/guestbook-ui --replicas=5
oc -n gitops-lab get deployment guestbook-ui -w &
sleep 90
kill %1 2>/dev/null
```

Within ~3 minutes you should see replicas drop back to whatever the Git manifest specified (the example uses 1). That's `selfHeal: true` reverting drift. **This is the property Strategy A doesn't have.**

### 3.5 Read both signals — Sync and Health

```bash
# kubectl
kubectl -n argocd get application guestbook -o jsonpath='Sync={.status.sync.status} Health={.status.health.status}{"\n"}'

# oc
oc -n argocd get application guestbook -o jsonpath='Sync={.status.sync.status} Health={.status.health.status}{"\n"}'
```

Now break the workload (not Git) — set a non-existent image:

```bash
# kubectl
kubectl -n gitops-lab set image deployment/guestbook-ui guestbook-ui=nginx:does-not-exist
sleep 30
kubectl -n argocd get application guestbook -o jsonpath='Sync={.status.sync.status} Health={.status.health.status}{"\n"}'
kubectl -n gitops-lab get pods -l app=guestbook-ui

# oc
oc -n gitops-lab set image deployment/guestbook-ui guestbook-ui=nginx:does-not-exist
sleep 30
oc -n argocd get application guestbook -o jsonpath='Sync={.status.sync.status} Health={.status.health.status}{"\n"}'
oc -n gitops-lab get pods -l app=guestbook-ui
```

**Expected**: very briefly `Sync=OutOfSync Health=Degraded` while ArgoCD reverts, then `Sync=Synced` once the image is reverted from Git but with `Health=Progressing` or `Health=Degraded` if the bad image lingers in old ReplicaSets. The point: these are **two independent signals**. Read both.

---

## Part 4 — Hands-on: simulate the cross-boundary dependency

This is the discussion's image 3 in action. You'll create a workload that depends on a ServiceAccount the *other lane* is supposed to provide. The failure is the most common cross-team incident on customer engagements.

### 4.1 "Azure DevOps push" attempts to deploy a workload that needs a SA

This is the imitation of the failing Azure DevOps pipeline:

```bash
# kubectl
kubectl -n gitops-lab apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: needs-platform-sa
  labels: {app: needs-platform-sa}
spec:
  replicas: 1
  selector:
    matchLabels: {app: needs-platform-sa}
  template:
    metadata:
      labels: {app: needs-platform-sa}
    spec:
      serviceAccountName: platform-sa            # <-- this SA does NOT exist yet
      containers:
        - name: app
          image: busybox:1.36
          command: ["sh", "-c", "echo platform-sa workload starting; sleep 3600"]
EOF

# oc
oc -n gitops-lab apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: needs-platform-sa
  labels: {app: needs-platform-sa}
spec:
  replicas: 1
  selector:
    matchLabels: {app: needs-platform-sa}
  template:
    metadata:
      labels: {app: needs-platform-sa}
    spec:
      serviceAccountName: platform-sa
      containers:
        - name: app
          image: busybox:1.36
          command: ["sh", "-c", "echo platform-sa workload starting; sleep 3600"]
EOF
```

Watch what happens to the Pod:

```bash
# kubectl
sleep 10
kubectl -n gitops-lab get deployment needs-platform-sa
kubectl -n gitops-lab get pods -l app=needs-platform-sa
kubectl -n gitops-lab describe deployment needs-platform-sa | grep -A2 "Conditions:\|Events:" | head -20

# oc
sleep 10
oc -n gitops-lab get deployment needs-platform-sa
oc -n gitops-lab get pods -l app=needs-platform-sa
oc -n gitops-lab describe deployment needs-platform-sa | grep -A2 "Conditions:\|Events:" | head -20
```

**Expected outcome**: the Deployment exists, but the ReplicaSet can't create Pods. The condition message will say something like `pods "needs-platform-sa-..." is forbidden: error looking up service account gitops-lab/platform-sa: serviceaccount "platform-sa" not found`.

This is **exactly** what an Azure DevOps pipeline log would show when the SA it depends on hasn't been applied yet by the upstream ArgoCD chart. The pipeline log makes it look like an Azure DevOps issue. The actual fix lives in the other lane.

### 4.2 "ArgoCD reconciles the SA from Git" — the fix on the other side of the boundary

Now imagine the platform team's ArgoCD just synced and applied the missing SA. Since this is a simulation, you'll apply the SA via ArgoCD by creating a second Application that points at a minimal manifest. But for laboratory speed, the simplest representation is a direct apply — the educational point is *which lane the fix lives in*:

```bash
# kubectl
kubectl -n gitops-lab apply -f - <<'EOF'
apiVersion: v1
kind: ServiceAccount
metadata:
  name: platform-sa
  labels: {provided-by: argocd-lane, app.kubernetes.io/component: cluster-scaffolding}
EOF

# oc
oc -n gitops-lab apply -f - <<'EOF'
apiVersion: v1
kind: ServiceAccount
metadata:
  name: platform-sa
  labels: {provided-by: argocd-lane, app.kubernetes.io/component: cluster-scaffolding}
EOF
```

Wait a moment for the Deployment controller to retry pod creation:

```bash
# kubectl
sleep 15
kubectl -n gitops-lab get deployment needs-platform-sa
kubectl -n gitops-lab get pods -l app=needs-platform-sa

# oc
sleep 15
oc -n gitops-lab get deployment needs-platform-sa
oc -n gitops-lab get pods -l app=needs-platform-sa
```

**Expected outcome**: the Pod is now Running. The fix didn't change anything in the "Azure DevOps lane" (the Deployment manifest) — it only changed the "ArgoCD lane" (the SA). That's the cross-boundary triage rule made concrete.

### 4.3 The triage rule, written down

From the discussion's Part 3:

> When an Azure DevOps deploy fails with `ServiceAccount not found`, `CRD not found`, `ClusterRole not found`, or `Operator not ready` — the fix is almost always in the ArgoCD lane. Don't debug the pipeline; check whether the upstream ArgoCD Application is `Synced + Healthy` and whether the resources it owns are present in the target namespace.

You just walked it.

---

## Part 5 — Read-through: Strategy B in `openshift-cfk-gitops`

To see what production Strategy B looks like, browse the sister repo. (Clone it locally if you don't have it yet.)

```bash
# Clone the sister repo if you haven't already (in a folder OUTSIDE this repo)
cd /tmp
git clone git@github.com:Psyncopate-Technologies/openshift-cfk-gitops.git 2>/dev/null || true
cd openshift-cfk-gitops/env/dev/argocd
ls
```

Read the three files:

```bash
cat appproject.yaml
cat cfk-operator-app.yaml
cat confluent-platform-app.yaml
```

Match what you see against the discussion's Part 2 — find:

| Element | Where in the files |
|---|---|
| **AppProject scope** | `appproject.yaml` — `sourceRepos`, `destinations`, `clusterResourceWhitelist`, `namespaceResourceWhitelist` |
| **Helm-chart-based source** | `cfk-operator-app.yaml` — `spec.source.repoURL: https://packages.confluent.io/helm` + `chart: confluent-for-kubernetes` + `targetRevision: 0.1351.59` |
| **Git-path-based source** | `confluent-platform-app.yaml` — `spec.source.repoURL: git@github.com:...` + `path: env/dev/confluent-platform` |
| **Continuous reconcile config** | Both Applications — `syncPolicy.automated.prune: true` + `selfHeal: true` |
| **Drift handling for operator-mutated fields** | `cfk-operator-app.yaml` — `ignoreDifferences:` block excluding `imagePullSecrets` and `secrets` on the ServiceAccount |
| **Retry policy** | Both Applications — `retry.limit: 5` + `backoff.duration: 5s` |

### Exercise

Now answer in your deliverable:

1. Why does `cfk-operator-app.yaml` have an `ignoreDifferences` block but `confluent-platform-app.yaml` doesn't?
2. The AppProject's `namespaceResourceWhitelist` includes `platform.confluent.io: '*'`. What would break if it were missing?
3. If you applied both `cfk-operator-app.yaml` and `confluent-platform-app.yaml` to a fresh cluster simultaneously, which one syncs first and why?
4. The two Applications have different `source.repoURL` shapes (HTTPS Helm chart vs Git SSH). What does each tell you about the credentials ArgoCD needs?
5. Now compare this layout to your `.azure-pipelines/cmf.yaml` — for each of the 8 deploy-contract elements in Part 1, which strategy expresses it more explicitly?

---

## Deliverable — `deliverables/<your-name>/week02/thursday.md`

1. **Part 1 write-up** — the line-by-line trace of one Azure DevOps pipeline (any one) covering all 5 questions from §1.
2. **Part 2 evidence** — your `get deployment push-app` output showing replicas drifted from 2 to 5 with no auto-revert. One sentence on why this is acceptable in Strategy A.
3. **Part 3 evidence** — the `Sync=Synced Health=Healthy` output for your guestbook Application, plus the `get deployment guestbook-ui -w` output showing ArgoCD reverting the scale change. One sentence on the cost of `selfHeal: true` in production.
4. **Part 3 — Sync vs Health** — paste your `get application` Sync/Health output before AND after the bad-image push from §3.5. Explain in one sentence why they can disagree.
5. **Part 4 — cross-boundary trace** — paste:
   - the failed Pod creation event from §4.1 (the "ServiceAccount not found" condition)
   - the running Pod after §4.2 applied the SA
   - one paragraph applying the triage rule: a customer engineer brings you a failing Azure DevOps pipeline log showing "ClusterRole `cfk-operator-role` not found." Where do you start, and what's the wrong first instinct?
6. **Part 5 read-through** — your answers to the 5 questions on the openshift-cfk-gitops Application CRs.
7. **The decision question** — given an asset (operator install, ConfigMap with per-env values, KafkaTopic, OAuth client Secret, cluster-wide NetworkPolicy), which strategy do you pick and why? Cover at least three of the five examples.
8. Two questions you still have.

---

## Cleanup

```bash
# kubectl
kubectl -n argocd delete application guestbook
kubectl -n gitops-lab delete deployment push-app needs-platform-sa --ignore-not-found
kubectl -n gitops-lab delete serviceaccount platform-sa --ignore-not-found
kubectl delete namespace gitops-lab
# Keep argocd namespace if you'll iterate; otherwise:
# kubectl delete -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
# kubectl delete namespace argocd

# oc
oc -n argocd delete application guestbook
oc -n gitops-lab delete deployment push-app needs-platform-sa --ignore-not-found
oc -n gitops-lab delete serviceaccount platform-sa --ignore-not-found
oc delete project gitops-lab
# Keep argocd project if you'll iterate; otherwise:
# oc delete -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
# oc delete project argocd
```

Stop the port-forward if it's still running:

```bash
# either shell variant
jobs -l
kill %1 2>/dev/null
```

The `lab-cluster/` CFK install in `kafka-dev` is left intact — keep it for tomorrow.

If you spun up the kind cluster only for this lab and don't need it tomorrow:

```bash
kind delete cluster --name training
```

---

## What you'll carry forward

By the end of this lab you've personally driven both strategies and the boundary between them:

- **Strategy A felt drift-blind by design** — Part 2's `oc scale` stayed at 5 forever.
- **Strategy B reverted drift within seconds** — Part 3's `oc scale` snapped back to the Git replica count.
- **The cross-boundary dependency is the highest-leverage failure shape** — Part 4's "Pod can't schedule because the OTHER lane hasn't synced its SA yet" is the most common incident on hybrid customer engagements, and you triaged it via the lane rule.

Next time someone says "the Azure DevOps pipeline failed with ServiceAccount not found," you'll have a one-question diagnostic instead of a one-hour debugging session.
