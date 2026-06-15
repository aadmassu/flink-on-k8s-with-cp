# Monday — RBAC (Role-Based Access Control)

**Time**: ~90 min
**Diagram**: [`20-rbac-binding.drawio`](20-rbac-binding.drawio) — User / ServiceAccount → RoleBinding → Role → Resources

## Learning objective

> **Why does CFK fail to install in upper envs with `serviceaccount "flink-operator" not found`?** And why is RBAC the most common reason an OpenShift admission decision goes the "wrong" way?

If the engineer can trace why a particular `oc <verb> <resource>` either succeeds or returns `Forbidden`, the rest of OpenShift admin becomes legible.

## Architecture Discussion (~40 min)

K8s RBAC has four objects and one rule. Master the rule and you can read any RBAC configuration.

**The rule**: *"can `<subject>` perform `<verb>` on `<resource>` in `<scope>`?"*

The four objects together answer that question:

- **Subject** — a User (human identity, usually from OAuth — Okta in production), a Group (collection of users), or a **ServiceAccount** (the identity used by Pods). ServiceAccounts are namespace-scoped objects. Every Pod runs AS some ServiceAccount, default is `default` if you don't specify.

- **Role** — a list of `(verbs, resources, apiGroups)` permission tuples. Namespace-scoped. Example: "get + list + watch on pods, configmaps, secrets in apiGroup `''`".

- **ClusterRole** — same shape as Role but **cluster-scoped**. Two uses:
  - Grants permissions on cluster-scoped resources (Nodes, PersistentVolumes, ClusterRoles themselves, CRDs)
  - Defines a *template* of permissions that can be bound at the namespace level via RoleBinding (reusable across namespaces)

- **RoleBinding** — binds one or more Subjects to one Role (or one ClusterRole used as a template). Namespace-scoped — only grants permissions IN this namespace.

- **ClusterRoleBinding** — binds Subjects to a ClusterRole, cluster-wide. Use with care — this grants permissions across ALL namespaces.

### The CFK case that broke us

In production the `flink-operator` ServiceAccount must exist in `dah-flink-<env>` BEFORE CMF or the Flink Operator can be installed. It's pre-created by the `platform-security` ArgoCD chart in a specific shape:

```
ServiceAccount: flink-operator (in dah-flink-uat)
   └── bound by RoleBinding: flink-operator-dah-flink
              ↓
         Role: flink-operator (in dah-flink-uat)
              ↓
   verbs: get, list, watch, create, update, patch, delete on
   resources: pods, services, configmaps, secrets, deployments, ingresses, ...
   resources: flinkdeployments / flinksessionjobs / flinkstatesnapshots (flink.apache.org)
   resources: leases (coordination.k8s.io)
   resources: serviceaccounts (get only — Wk 4 will explain why)
   resources: roles, rolebindings (get, list, watch)
```

The CMF Pod runs AS this ServiceAccount and uses those verbs to provision the Flink Operator's per-env workload. If the chart hasn't applied the RoleBinding, the CMF Pod schedules but its API calls fail with `Forbidden`.

## Diagram Walkthrough (~30 min)

Walk the diagram from bottom (the resource) to top (the subject):

1. Resource — `pods` in apiGroup `""` in namespace `dah-flink-uat`
2. Role — names `pods` in its `rules`, with verbs `[get, list, watch]`
3. RoleBinding — names that Role + a ServiceAccount Subject
4. ServiceAccount — `flink-operator`
5. Pod — declares `serviceAccountName: flink-operator` in its spec

When the Pod calls the K8s API, the apiserver walks this chain in reverse: identity → token → SA → look up bindings → resolve to Role → check verb/resource → allow or deny.

Stop at each step and ask: *"if this object didn't exist, what error would the Pod get?"*

## Failure Scenarios

| Symptom | Likely cause |
|---|---|
| Pod fails to schedule: `serviceaccount "X" not found` | ServiceAccount missing (the CFK UAT story, tracker 3.2) |
| Pod runs but API calls return 403 `Forbidden` | RoleBinding missing OR Role doesn't grant the right verb |
| Pod can't list ConfigMaps it expects | Role lists `secrets` but not `configmaps` (off-by-one resource type) |
| Operator stuck reconciling — no error | ClusterRole binding missing a `watch` verb (operator can `get` but can't subscribe to changes) |
| `oc auth can-i` returns no but the Role looks right | `apiGroups` mismatch — `pods` is in `""`, but `deployments` is in `apps` |

## The diagnostic command engineers must memorize

```bash
oc auth can-i <verb> <resource> --as=system:serviceaccount:<namespace>:<sa-name> -n <namespace>
```

This is the single most useful RBAC debug command. It impersonates the ServiceAccount and asks the apiserver "would this be allowed?" — without running anything that mutates state.

## Q&A

1. What's the difference between Role and ClusterRole? When would you ever bind a ClusterRole at the namespace level via RoleBinding?
2. If a Pod has no `serviceAccountName` in its spec, what identity does it run as?
3. Can a single RoleBinding bind multiple subjects to one Role?
4. Why does the platform pre-create the `flink-operator` SA via a chart instead of letting the CMF Helm install create it?
5. What's the security implication of `ClusterRoleBinding` to `cluster-admin`? Why is it usually wrong?

## Common misconceptions

- **"Roles grant permission to USERS"** — Roles + ClusterRoles only DESCRIBE permissions. RoleBindings + ClusterRoleBindings GRANT them.
- **"ClusterRole means the role applies cluster-wide"** — Only when bound via ClusterRoleBinding. ClusterRole + RoleBinding = the role applies within ONE namespace.
- **"`oc create rolebinding ...` is enough"** — Not if your SA is in a different namespace from the RoleBinding. Check the subject's namespace.
- **"You can grant permissions you don't have"** — No. K8s rejects RoleBindings that escalate beyond what the creator has.


## Added Enhancement — SCC (Security Context Constraints)

Before Week 4 CFK, engineers must understand why OpenShift may admit or deny a pod even when Kubernetes RBAC is correct.

Topics:
- restricted-v2 SCC
- anyuid SCC
- service account to SCC binding
- Why operators sometimes fail due to SCC violations

Troubleshooting commands:
```bash
oc describe pod <pod>
oc get scc
oc adm policy who-can use scc restricted-v2
```
