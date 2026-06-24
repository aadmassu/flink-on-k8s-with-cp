# Thursday — GitOps Strategies: Azure DevOps Push vs ArgoCD Pull (and the Hybrid Reality)

## Learning objective

> **"GitOps" is a slogan; the implementation is a choice.** Two real strategies for deploying Confluent Platform on OpenShift exist in front of you today — an Azure DevOps push pipeline (this repo) and an ArgoCD pull-based GitOps deployment (the sister repo). Each solves a different problem. In real customer engagements, you almost always end up using **both** — and the boundary between them is where most cross-team incidents happen. Today is about understanding when to use which, and how to debug the boundary.

By the end of the day an engineer should be able to:

- Explain what "GitOps" actually requires (Git as source of truth + automated reconcile against it) and why two valid implementations exist.
- Walk an engineer through deploying CFK with Strategy A (Azure DevOps push) — including how the pipeline reads env-specific variable groups, what `oc login` it performs, and where drift goes invisible.
- Walk an engineer through deploying CFK with Strategy B (ArgoCD pull) — including where ArgoCD lives, the Application + AppProject CRs, sync waves, and the difference between `Sync` and `Health` status.
- Pick the right strategy for a given asset (operator vs CR vs Helm release) and defend the choice to a platform team.
- Diagnose a failure that crosses the ownership boundary (e.g. Azure DevOps deploy fails because ArgoCD hasn't applied the prerequisite ServiceAccount yet).

## Diagrams referenced

| # | File | Purpose |
|---|---|---|
| 1 | `Azure DevOps Push Pipeline.png` | Strategy A — Azure DevOps push pipeline, the approach used in this repo |
| 2 | `ArgoCD Pull-Based GitOps.png` | Strategy B — ArgoCD pull-based GitOps, used in the sister `openshift-cfk-gitops` repo |
| 3 | `Hybrid Production Split.png` | The real customer reality — both strategies on the same cluster, with the ownership boundary and the cross-boundary dependency callouts |

---

## Part 0 — What "GitOps" actually requires

Strip the marketing language out and GitOps reduces to two non-negotiables:

1. **Git is the source of truth for cluster state.** Whatever is in Git is what's "supposed to be" in the cluster. Manual `oc apply` doesn't count as a real change — it's a temporary patch on top of a Git-derived state.
2. **Something reconciles the cluster against Git automatically.** A controller, a pipeline, a webhook, a cron — *something* converts a Git change into a cluster change without a human pressing buttons in the cluster.

That's the whole rule. The argument is over the *implementation*.

There are two valid implementations, and **you have one of each running today**:

- **Push (CI/CD style)** — a pipeline outside the cluster reads Git, then *pushes* changes into the cluster on a schedule or commit trigger. Drift detection requires an extra step.
- **Pull (operator style)** — a controller *inside* the cluster watches Git and reconciles continuously. Drift is detected on every tick by design.

The next two sections look at one of each, in detail.

---

## Part 1 — Strategy A: Azure DevOps Push Pipeline

![1 — Azure DevOps Push Pipeline](<images/Azure DevOps Push Pipeline.png>)

This is the pattern used in **this repo** (`flink-on-k8s-with-cp`). Every pipeline under `.azure-pipelines/` follows the same shape.

### What's actually in the repo

```
flink-on-k8s-with-cp/
├── .azure-pipelines/
│   ├── confluent-platform.yaml      → deploys CFK CRs (Kafka, KRaftController, SR, Connect, C3)
│   ├── cmf.yaml                     → installs CMF via Helm
│   ├── cmf-tls.yaml                 → renders the cert-manager Certificate for CMF's REST endpoint
│   ├── flink-environments.yaml      → creates Flink environment + Kafka catalog + database via CMF REST
│   ├── connectivity-test.yaml       → probes outbound dependencies (Okta, CyberArk, Artifactory, SQL Server)
│   ├── diagnostics.yaml             → read-only dump of cluster state for triage
│   └── templates/
│       ├── install-tools.yaml       → installs oc / helm on the agent
│       └── diagnostics-step.yaml    → reusable diagnostics body
├── apps/confluent-platform/<env>/   → CFK CR manifests per env (dev, qa, uat, stg, prd, dr)
├── apps/confluent-cmf/<env>/        → CMF Helm values per env
└── apps/confluent-flink/<env>/      → Flink environment / catalog / database JSONs per env
```

### How it works (trace one deploy)

1. **Engineer commits** manifests + values to `flink-on-k8s-with-cp` on the deployment branch.
2. **Pipeline triggered** — either manually from the Azure DevOps UI, on commit via branch policy, or scheduled.
3. **Agent runs** on the `DevOpsLinux` pool. The pipeline reads the env-specific **variable group** (e.g. `kafka-openshift-credentials-uat`), runs `oc login` with a service-account token, and applies the manifests via `helm install/upgrade` or `oc apply`.
4. **Cluster changes**, pipeline reports success or failure, and **exits**.
5. **No further reconcile.** Any manual `oc edit` on the cluster goes undetected until the next pipeline run.

### Strengths

- **Per-env parameterization** is first-class. Each env has its own variable group; secrets, hostnames, replicas, image tags can all differ without manifest duplication.
- **Explicit deploys** — engineers know exactly when a change goes out, and rollback is "rerun the previous pipeline" or "revert the commit + rerun."
- **Integrates with enterprise change management** — approvals, release gates, audit trails all live in Azure DevOps and ServiceNow.
- **Pipeline can do non-Kubernetes work** — file SNOW tickets, post Slack messages, run smoke tests, hit the CMF REST API (which is what `flink-environments.yaml` does).

### Weaknesses

- **Drift-blind by design.** If someone `oc edit`s a Kafka CR on the cluster, no one notices until the next pipeline run.
- **Pipeline state is procedural.** `confluent-platform.yaml` is a bash script that does steps in order — if step 3 of 7 fails, the cluster is in a half-deployed state until you debug and rerun.
- **Per-env config drift between envs is easy.** dev and uat values.yaml diverge silently unless you have a discipline (or a tool) that compares them.
- **Continuous-state guarantees require extra work.** You'd have to write a separate "drift detector" pipeline that runs on a schedule and compares cluster → Git.

### When to use Strategy A

- The deploy is **per-env** and has **per-env secrets** that aren't well-modeled by ArgoCD.
- You need to do **non-Kubernetes side effects** as part of the deploy (REST API calls, smoke tests, downstream notifications).
- The team is already in an **Azure DevOps-shop** and reusing existing variable-group + approval infrastructure is more important than continuous reconcile.
- You want **explicit deploy windows** rather than a controller that applies as soon as Git changes.

This is exactly the customer case for **workloads** (CFK CRs, CMF, Flink jobs) — env-specific values, multi-stage approvals, downstream side effects, all justify Strategy A.

---

## Part 2 — Strategy B: ArgoCD Pull-Based GitOps

![2 — ArgoCD Pull-Based GitOps](<images/ArgoCD Pull-Based GitOps.png>)

This is the pattern used in the **sister repo** `openshift-cfk-gitops`. ArgoCD lives **inside** the OCP cluster and continuously reconciles Git → cluster.

### What's actually in the repo

```
openshift-cfk-gitops/
├── env/dev/argocd/
│   ├── appproject.yaml              → AppProject "confluent" — scopes source repos + destinations + allowed resource kinds
│   ├── cfk-operator-app.yaml        → Application — installs CFK Operator from packages.confluent.io Helm chart
│   └── confluent-platform-app.yaml  → Application — applies env/dev/confluent-platform/ manifests
├── env/dev/confluent-platform/
│   ├── kafka.yaml, kraftcontroller.yaml, schemaregistry.yaml, connect.yaml, ...
│   ├── kustomization.yaml
│   ├── secrets/                     → TLS + OAuth + MDS Secret manifests
│   ├── rbac/                        → kafkarestclass + sysAdmins
│   └── topics/                      → KafkaTopic CRs
├── env/dev/cluster-config/          → namespace + SCC + kustomization
└── terraform/                       → ROSA cluster provisioning (separate concern)
```

The two `Application` CRs are short and worth reading carefully — they're the *entire* deployment contract:

```yaml
# cfk-operator-app.yaml (excerpt)
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata: { name: cfk-operator, namespace: argocd }
spec:
  source:
    repoURL: https://packages.confluent.io/helm
    chart: confluent-for-kubernetes
    targetRevision: 0.1351.59
    helm:
      values: |
        namespaced: false
        namespaceList: [confluent]
  destination:
    server: https://kubernetes.default.svc
    namespace: confluent-operator
  syncPolicy:
    automated: { prune: true, selfHeal: true }
```

```yaml
# confluent-platform-app.yaml (excerpt)
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata: { name: confluent-platform, namespace: argocd }
spec:
  source:
    repoURL: git@github.com:Psyncopate-Technologies/openshift-cfk-gitops.git
    targetRevision: main
    path: env/dev/confluent-platform
  destination:
    server: https://kubernetes.default.svc
    namespace: confluent
  syncPolicy:
    automated: { prune: true, selfHeal: true, allowEmpty: false }
```

Two things to notice:

1. **`automated.selfHeal: true`** — any manual `oc edit` on the cluster gets reverted on the next reconcile tick.
2. **`automated.prune: true`** — anything in the cluster that's *not* in Git gets deleted.

That's strong contract enforcement. The cluster *will* match Git, every few minutes, with no human in the loop.

### ArgoCD's moving parts

- **Application CR** — points at a Git repo + path + revision. ArgoCD owns reconcile for that path.
- **AppProject** — RBAC scope; restricts which repos / namespaces / resource kinds an Application can touch. The `confluent` AppProject in this repo whitelists `Namespace`, `CustomResourceDefinition`, and everything under `platform.confluent.io` / `route.openshift.io`.
- **ApplicationSet** — generator pattern: "for every cluster in this list, create one Application that points at this path." Useful for multi-env / multi-cluster rollouts.
- **Repo Server** — clones Git repos, renders manifests (Helm, Kustomize, plain YAML).
- **Application Controller** — the reconciler. Watches Application CRs, computes diff between desired (Git) and live (cluster), applies the diff via kube-apiserver.
- **ArgoCD Server (API + Web UI)** — engineers use this to view sync status, click "Sync Now", see live diffs, roll back.

### Sync waves

ArgoCD applies manifests in declared "sync wave" order. CRDs must exist before CRs. Annotations on each manifest:

```yaml
annotations:
  argocd.argoproj.io/sync-wave: "-1"   # earlier wave (applied first)
```

The CFK operator chart (wave `-1` or earlier) installs the `Kafka` CRD; the `Kafka` CR (wave `0`) gets applied next; topics + Routes (later waves) come after. Get the ordering wrong and you'll see `no matches for kind "Kafka"` errors that retry until the wave catches up.

### Sync vs Health (the most common misread)

These are **two different signals** in ArgoCD, and engineers confuse them constantly:

| Signal | Question it answers | Possible values |
|---|---|---|
| **Sync** | Does the cluster match Git? | `Synced`, `OutOfSync`, `Unknown` |
| **Health** | Is the workload itself working? | `Healthy`, `Progressing`, `Degraded`, `Missing`, `Suspended` |

You can be:

- **`Synced + Healthy`** — happy path. Cluster matches Git; workloads are running.
- **`Synced + Degraded`** — the manifest applied, but the Pod is CrashLoopBackOff. ArgoCD's job is done; the *application* is broken.
- **`OutOfSync + Healthy`** — someone manually `oc apply`-ed a fix. Cluster is happy; Git doesn't know about it. Will be reverted on next sync.
- **`OutOfSync + Degraded`** — change in Git hasn't been applied yet, AND the current state is broken. Common during recovery from a bad deploy.

Always read both signals.

### Strengths

- **Drift is impossible** (with `selfHeal + prune`). The cluster *will* match Git.
- **Rollback is `git revert`**. No special tooling.
- **Continuous reconciliation** — operators that should always-be-running, RBAC that should always-be-applied, can never silently drift.
- **The Application CR is the contract.** New engineers reading the repo know exactly what's deployed; the Application points at the path and the path holds the truth.
- **Multi-cluster scales naturally** via ApplicationSet generators.

### Weaknesses

- **Per-env parameterization is harder.** Helm values + Kustomize overlays work, but they require more discipline than "use a different variable group."
- **Side effects don't fit.** ArgoCD can apply manifests, period. If your deploy needs to hit the CMF REST API, file a SNOW ticket, or run a smoke test, you need a separate pipeline.
- **Selfheal can fight with operators.** If CFK mutates a generated Service annotation on every reconcile and Git doesn't have the mutation, ArgoCD will flap between `OutOfSync` and `Synced`. Mitigated by `ignoreDifferences` blocks (see `cfk-operator-app.yaml` for examples).
- **Secrets are tricky.** Plain Kubernetes Secrets in Git are insecure. Production ArgoCD installs need ExternalSecrets Operator, SealedSecrets, sops, or vault integration.

### When to use Strategy B

- The deploy is **cluster-wide** and **identical across envs** (operators, CRDs, RBAC scaffolding, cert-manager Operator, network policies).
- You want **continuous drift detection** — anything that should always be in a known state.
- The team owns the cluster, owns the Git repo, and can give ArgoCD permission to reconcile aggressively.
- Multi-cluster fleets where ApplicationSet's generator pattern is useful.

This is exactly the customer case for **operators and cluster scaffolding** — CFK operator install, the `platform-security` RBAC chart, cert-manager Operator. Identical across envs, should always be running, drift would be a security incident.

---

## Part 3 — The Hybrid Production Reality

![3 — Hybrid Production Split](<images/Hybrid Production Split.png>)

In real customer engagements you almost always end up using **both** strategies. The question isn't which one wins — it's **which assets each owns**.

### The ownership boundary

| Owner | What lives there | Why |
|---|---|---|
| **ArgoCD** (`openshift-cfk-gitops`) | CFK Operator, cert-manager Operator, network policies, cluster-wide CRDs, the `platform-security` RBAC chart (per-namespace SA + Role + RoleBinding), AppProjects | Cluster-wide, identical across envs, must-always-be-running, drift is a security incident |
| **Azure DevOps** (`flink-on-k8s-with-cp`) | CFK CRs per env (Kafka, KRaftController, SR, Connect, C3), CMF Helm release per env, Flink jobs, env-specific TLS Secrets, env-specific variable values | Per-env config, frequent releases, multi-stage approval, downstream side effects (REST API calls, SNOW, smoke tests) |

The line isn't arbitrary. Walk through any asset and ask:

- *Does this differ per env?* → Azure DevOps.
- *Should this drift be impossible?* → ArgoCD.
- *Does deploying this need to hit an external REST API, file a ticket, or run a test?* → Azure DevOps.
- *Is this an operator or a cluster-wide piece of scaffolding?* → ArgoCD.

### Cross-boundary dependencies — where incidents actually happen

The ownership split is clean on paper. In practice, **workloads depend on scaffolding that lives in the other lane.** Two concrete examples that show up in real customer engagements:

#### Cross-boundary dependency #1 — CRDs must exist before CRs

- **ArgoCD lane** installs the CFK Operator → operator reconciles its CRDs (`Kafka`, `KRaftController`, `SchemaRegistry`, ...) into the cluster.
- **Azure DevOps lane** applies a `Kafka` CR.
- **If ArgoCD hasn't synced yet**, the Azure DevOps `oc apply` fails with `no matches for kind "Kafka"`. The pipeline log makes it look like an Azure DevOps bug. The actual fix lives in the ArgoCD lane.

#### Cross-boundary dependency #2 — Operator-applied SA referenced by Helm-installed workload

- **ArgoCD lane** owns a `platform-security` Helm chart that applies per-namespace SA + Role + RoleBinding (e.g. a `flink-operator` SA in each workload namespace).
- **Azure DevOps lane** installs CMF via Helm — and the CMF Deployment spec references that SA via `spec.template.spec.serviceAccountName`.
- **If ArgoCD hasn't applied the SA yet**, the Azure DevOps Helm install creates the Deployment, but the Pod fails to schedule with `error looking up service account <ns>/flink-operator: serviceaccount "flink-operator" not found`. The error surfaces in the Azure DevOps log. The fix is upstream in the ArgoCD chart.

These are the failures the discussion's image 3 marks with the red dashed arrows. They're not edge cases — they're the **default** of running a hybrid setup.

### The triage rule that follows from this

**When an Azure DevOps deploy fails with "ServiceAccount not found", "CRD not found", "ClusterRole not found", "Operator not ready" — the fix is almost always in the ArgoCD lane.** Don't debug the pipeline; check whether the upstream ArgoCD Application is `Synced + Healthy` and whether the resources it owns are present in the target namespace.

The inverse is also true: when ArgoCD shows everything `Synced + Healthy` but engineers report workloads broken, the fix is almost always in the Azure DevOps lane.

---

## Side-by-side comparison

| Dimension | Strategy A — Azure DevOps Push | Strategy B — ArgoCD Pull |
|---|---|---|
| **Trigger** | Manual click / commit webhook / scheduled | Continuous polling (~3 min) or commit webhook |
| **Where it runs** | DevOpsLinux agent pool (outside cluster) | ArgoCD controller (inside cluster) |
| **Auth to cluster** | `oc login` with SA token from variable group | ArgoCD SA + RBAC inside the cluster |
| **Reconcile** | One-shot per pipeline run | Continuous, every few minutes |
| **Drift detection** | None by default; requires separate diff pipeline | Built-in; `selfHeal: true` auto-reverts |
| **Rollback** | Revert commit + rerun pipeline | `git revert` (controller picks it up automatically) |
| **Per-env config** | First-class via variable groups | Helm values + Kustomize overlays + ApplicationSet |
| **Secrets** | Variable group values + ESO references | ESO / SealedSecrets / sops (cannot put plain Secrets in Git) |
| **Side effects** | Yes — pipeline can hit REST APIs, file tickets, run tests | No — manifests only |
| **Best for** | Per-env workload releases, multi-stage approval, downstream side effects | Operators, CRDs, cluster RBAC, anything must-always-be-running |
| **In your repos** | `flink-on-k8s-with-cp/.azure-pipelines/*.yaml` | `openshift-cfk-gitops/env/dev/argocd/*.yaml` |

---

## Failure scenarios — split by strategy

| Symptom | Likely cause | Which lane |
|---|---|---|
| Pipeline failed with `no matches for kind "Kafka"` | CFK Operator CRDs not installed yet | ArgoCD (operator app `OutOfSync` or `Progressing`) |
| Pipeline failed with `serviceaccount not found` | `platform-security` chart hasn't applied SA in target namespace | ArgoCD (operator-applied SA missing) |
| Pipeline succeeded but Pod is `CrashLoopBackOff` | Application-level error | Azure DevOps lane (workload manifest / image / config) |
| Engineer `oc edit`-ed a CR; change was reverted minutes later | ArgoCD `selfHeal: true` reverted to Git state | ArgoCD (expected behavior — edit Git instead) |
| ArgoCD App shows `OutOfSync` after commit but nothing happens | Repo Server hasn't polled yet (wait ~3 min), or repo creds wrong, or revision mismatch | ArgoCD |
| ArgoCD App shows `Synced + Degraded` | Manifest applied; Pod is unhealthy | Azure DevOps lane (workload issue) — same triage tree as Week 1 Friday |
| Cluster has resources not in Git | Someone `oc apply`-ed manually OR `prune: false` left stale objects | Either — check both lanes |
| `Application` apply fails with `Forbidden` | ArgoCD SA doesn't have RBAC for that resource kind | ArgoCD (extend AppProject namespaceResourceWhitelist) |
| Helm install fails reading CyberArk-backed values | Secret hasn't been synced by ESO yet | Could be either — check ExternalSecret status |

---

## Q&A

1. Two engineers push conflicting changes to the same manifest. Who wins on each strategy?
2. Why does ArgoCD pull from Git instead of having a webhook push to it?
3. When would you *not* use GitOps for a cluster change?
4. The Azure DevOps pipeline does `helm install` for CMF. Why isn't that an ArgoCD Application instead?
5. Trace what happens when an engineer does `oc edit kafka kafka -n dah-flink-uat` on (a) the Azure DevOps-owned dev cluster and (b) the ArgoCD-owned gitops cluster. Where do the two paths diverge?
6. The ArgoCD Application is `Synced + Degraded` for `cfk-operator`. The operator Deployment is in `CrashLoopBackOff`. Whose problem is this — the operator image, the chart values, the cluster's resource quota, or the ArgoCD reconcile?
7. You need to add a new env (qa) for CFK workloads. Walk through what changes in the Azure DevOps lane and what changes in the ArgoCD lane.
8. The platform-security ArgoCD chart hasn't applied the `flink-operator` SA in the target namespace. The Azure DevOps CMF pipeline fails with "serviceaccount not found." A junior engineer wants to add an `oc create sa flink-operator` step to the pipeline as a fix. Why is that the wrong fix?
9. ArgoCD has `prune: true` set. An engineer accidentally deletes a manifest from Git, pushes, and walks away. What happens to the cluster?
10. The Azure DevOps pipeline `confluent-platform.yaml` has a "no-op" run (no diff between Git and cluster). Does the pipeline detect that and skip the deploy, or does it apply anyway?
11. ArgoCD Application targets `targetRevision: main`. A platform engineer wants to test a manifest change without affecting `main`. What ArgoCD-native pattern would you use?
12. The discussion image 3 shows two cross-boundary dependency arrows (CRD → CR, SA → Helm release). Name two more cross-boundary dependencies you'd expect to see in this kind of hybrid setup.

---

## Common misconceptions

- **"GitOps means using Git for code"** — no. GitOps means Git is the *source of truth for cluster state*. Application code lives in different repos with their own CI; GitOps is about *deployment*, not *build*.
- **"ArgoCD pushes changes to the cluster"** — no. ArgoCD *pulls* from Git and reconciles inside the cluster. The cluster doesn't expose anything outbound to a CI system.
- **"Push pipelines aren't GitOps"** — they can be, if Git is the source of truth and the pipeline reconciles automatically on commit. The Azure DevOps approach is GitOps; it just lacks continuous reconcile.
- **"You should always use ArgoCD"** — not for workloads that need per-env secrets, downstream side effects, or multi-stage approval. Use the strategy that fits the asset.
- **"Manual `oc apply` is fine if I push to Git later"** — order matters. Manual apply → ArgoCD notices drift → engineer is confused. Commit first, then `oc apply` if you must — but really, just commit and let the controller reconcile.
- **"Sync == Healthy"** — different signals. `Synced + Degraded` is a routine state during recovery from a bad deploy.
- **"ArgoCD replaces CI/CD"** — no. It replaces CD (deploy). CI (build + test) still runs separately.
- **"If the pipeline log says X, the problem is in the pipeline"** — when the failure involves prerequisite cluster state (CRDs, SAs, RBAC), the fix is usually in the ArgoCD lane. Read the boundary, not just the pipeline log.

---

## Reference

- ArgoCD docs — Applications and AppProjects: <https://argo-cd.readthedocs.io/en/stable/user-guide/application-specification/>
- ArgoCD sync waves and hooks: <https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/>
- Azure DevOps pipelines: <https://learn.microsoft.com/en-us/azure/devops/pipelines/>
- The two repos referenced today:
  - `flink-on-k8s-with-cp` (this repo, Strategy A) — `.azure-pipelines/*.yaml` + `apps/confluent-*/<env>/`
  - `openshift-cfk-gitops` (sister repo, Strategy B) — `env/dev/argocd/*.yaml` + `env/dev/confluent-platform/`
