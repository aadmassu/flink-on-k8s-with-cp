# Thursday — GitOps with ArgoCD

**Time**: ~90 min
**Diagram**: [`23-gitops.drawio`](23-gitops.drawio) — Git → ArgoCD → OpenShift

## Learning objective

> **What does GitOps actually mean in practice?** And specifically: in production, ArgoCD owns *operators only* (cert-manager Operator, platform-security chart, CFK Operator); Azure DevOps owns *workloads* (CFK CRs, CMF, Flink jobs). Why that split — and what happens when you try to mix them?

## Architecture Discussion (~45 min)

### The core idea

**Git is the source of truth. Whatever is in Git, ArgoCD applies to the cluster, continuously.**

That's it. The rest is implementation detail.

Two implications:

1. **You can't make a "successful" change by `oc apply`-ing it manually.** ArgoCD will revert it on the next sync (or flag it as drift) because the Git version doesn't match.
2. **Rollback is just `git revert`.** No special tooling — same workflow as undoing any commit.

### ArgoCD's pieces

- **Application CR** — points at a Git repo + path + revision (branch / tag / commit). ArgoCD watches the cluster for state matching this Application's manifests.
- **Application Project** — group of Applications + RBAC scope (which clusters / namespaces / resource kinds it can touch).
- **ApplicationSet** — generator pattern: "for every cluster in this list, create one Application that points at this path".
- **ArgoCD Server** — the API + the Web UI; engineers use this to view sync status, click "Sync Now", see live diffs.
- **Application Controller** — the actual reconciler (operator pattern, Week 2 Tuesday); watches Application CRs, compares Git state → cluster state, applies diffs.
- **Repo Server** — clones Git repos, renders manifests (Helm, Kustomize, plain YAML).

### The sync wave

ArgoCD applies manifests in declared "sync wave" order. CRDs need to exist before their CRs. Annotations on each manifest:

```yaml
annotations:
  argocd.argoproj.io/sync-wave: "-1"   # earlier wave (applied first)
```

CFK requires the CFK operator + CRDs (wave -1 or earlier) before any Kafka CR (wave 0). In production this is why the operator lives in ArgoCD: the CRDs must exist BEFORE Tushar's Azure pipeline can apply the Kafka CR.

### The production split (read this before the lab)

| Owner | What lives there | Why |
|---|---|---|
| **ArgoCD** | Operators + chart-managed cluster services (cert-manager Operator, platform-security ArgoCD chart with the per-namespace SA/Role/RoleBinding, KRaft + Kafka CRDs from CFK operator chart) | Cluster-wide concerns; same shape across all envs; rare changes |
| **Azure DevOps** | Workloads + their per-env config (CFK CRs in apps/confluent-platform/<env>/, CMF Helm in apps/confluent-cmf/<env>/, Flink jobs) | Per-env params; frequent releases; pipelines need per-env variable groups |

Where it crosses lines:
- Tracker 3.2 (UAT) and 3.3 (PRD) are about the `platform-security` ArgoCD chart not yet applying the `flink-operator` SA in the right namespace. Until ArgoCD catches up, Azure DevOps' CMF install fails with "ServiceAccount not found." That's the cross-boundary dependency you live with.

### "Sync" vs "Healthy"

These are TWO DIFFERENT signals in ArgoCD:

- **Sync status** — does what's in the cluster MATCH what's in Git? `Synced` / `OutOfSync` / `Unknown`
- **Health status** — is the workload itself working? `Healthy` / `Degraded` / `Progressing` / `Missing`

You can be `Synced + Degraded` (the manifest applied, but the Pod is CrashLoopBackOff). Or `OutOfSync + Healthy` (someone manually `oc apply`-ed a fix; cluster is happy; Git doesn't know).

Engineers must read BOTH signals.

## Diagram Walkthrough (~25 min) — trace one ArgoCD sync

Walk the diagram:

```
Engineer commits a change to Git (manifest under apps/confluent-platform/dev/kafka.yaml)
   │
   │ Git push
   ▼
GitHub / Azure Repos / etc.
   │
   │ ArgoCD Repo Server polls (default 3 min)
   ▼
ArgoCD Application Controller notices "OutOfSync"
   │
   │ runs the reconcile loop (Week 2 Tuesday)
   │ compares desired (from Git) vs live (in cluster)
   │ computes the diff
   ▼
ArgoCD calls apiserver: kubectl apply (effectively)
   │
   ▼
apiserver writes to etcd → built-in controllers + operators take over
   │
   ▼
ArgoCD watches the resulting objects; updates the Application's Health status
   │
   ▼
Engineer's Slack: "kafka-uat is now Healthy"
```

At each step: *what does the engineer see in the ArgoCD UI? Where would they look if it failed?*

## Failure Scenarios

| Symptom | Likely cause |
|---|---|
| Application stuck `OutOfSync` after a Git push | ArgoCD hasn't polled yet (wait 3 min); or repo credentials wrong; or branch revision mismatch |
| Application `OutOfSync` even though Git == cluster | Resource has a field that the apiserver mutates after apply (e.g. `creationTimestamp`); add it to `ignoreDifferences` |
| Application `Synced + Degraded` | The manifest applied but the Pod is unhealthy → Week 1 troubleshooting tree |
| Cluster has resources NOT in Git ("stale") | Someone `oc apply`-ed manually; set `prune: true` to delete OR `oc delete` to clean up |
| Sync fails with `Forbidden` | ArgoCD's SA doesn't have RBAC for that resource type — same RBAC tree as yesterday |

## Q&A

1. If two engineers push conflicting changes to the same manifest, who wins?
2. Why does ArgoCD's pull model scale better than a push-based deploy tool would?
3. When would you ever NOT use GitOps for a cluster change?
4. In production, why are CFK CRs deployed via Azure DevOps instead of ArgoCD?
5. How would ArgoCD detect a `kubectl edit` someone made directly on the cluster?

## Common misconceptions

- **"GitOps means using Git for code"** — no. GitOps means Git is the *source of truth for cluster state*. Code is separate.
- **"ArgoCD pushes changes to the cluster"** — no, ArgoCD PULLS desired state from Git and reconciles. The cluster doesn't expose anything outbound.
- **"Manual `oc apply` is fine if I push to Git later"** — order matters. Manual apply → ArgoCD notices drift → engineer is confused.
- **"GitOps replaces CI/CD"** — no, it replaces deploy (CD). CI still builds + tests.


## Added Enhancement — Drift Detection Lab

Manually change a deployed object using oc edit.
Observe ArgoCD detect and reconcile the drift.

This demonstrates why Git remains the source of truth.
