# Week 2 Thursday — Lab: Manage One App via ArgoCD

**Time**: ~4 hours

## Prerequisites

ArgoCD is already installed on the dev cluster (the OpenShift GitOps Operator does this). If not, ask the platform team.

```bash
# Confirm ArgoCD is available
oc -n openshift-gitops get pods | head -5
oc -n openshift-gitops get route openshift-gitops-server
```

## Hands-on Lab — your first Application

```bash
# 1. Fork or create a small public Git repo with one manifest
#    Easiest: use a fork of a public sample, or use this in-repo example path:
#    https://github.com/argoproj/argocd-example-apps/tree/master/guestbook
#
# (If you can't push to GitHub from here, paste your training repo URL.)

# 2. Create the Application CR
cat <<EOF | oc apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: guestbook-<you>
  namespace: openshift-gitops
spec:
  project: default
  source:
    repoURL: https://github.com/argoproj/argocd-example-apps.git
    path: guestbook
    targetRevision: HEAD
  destination:
    server: https://kubernetes.default.svc
    namespace: <you>-training
  syncPolicy:
    automated:
      prune: true        # delete cluster objects when Git removes them
      selfHeal: true     # revert manual oc-apply changes
EOF

# 3. Watch the sync happen
oc -n openshift-gitops get application guestbook-<you> -o jsonpath='{.status.sync.status} {.status.health.status}{"\n"}'
sleep 30
oc -n openshift-gitops get application guestbook-<you> -o jsonpath='{.status.sync.status} {.status.health.status}{"\n"}'
# Expect: "Synced Healthy"

# 4. Confirm objects landed in your training project
oc get all -n <you>-training -l app=guestbook-ui
```

Open the OpenShift Console → search for ArgoCD route → log in via the OAuth flow → view your Application as a graph. Click around — every K8s object that ArgoCD created shows up.

## Hands-on Lab Part 2 — observe the "selfHeal" reconcile

```bash
# Manually scale the Deployment that ArgoCD owns — break what's in Git
oc -n <you>-training scale deployment/guestbook-ui --replicas=5

# Watch what happens — ArgoCD should revert within a minute or two
oc -n <you>-training get deployment guestbook-ui -w
```

You should see replicas drop back to whatever Git says. That's `selfHeal: true` doing its job. **In production this prevents drift but ALSO prevents emergency manual fixes** — engineers need to know the trade-off.

## Troubleshooting Exercise

**Break 1 — invalid path in the Application**

```bash
oc -n openshift-gitops patch application guestbook-<you> --type='merge' \
  -p='{"spec":{"source":{"path":"does-not-exist"}}}'

# What does the Application's status say? `oc get application` → STATUS column
# Read the full status:
oc -n openshift-gitops get application guestbook-<you> -o jsonpath='{.status.conditions}' | python3 -m json.tool

# Fix:
oc -n openshift-gitops patch application guestbook-<you> --type='merge' \
  -p='{"spec":{"source":{"path":"guestbook"}}}'
```

**Break 2 — Sync + Health disagree**

```bash
# Patch the Deployment's image to something that can't pull
oc -n <you>-training set image deployment/guestbook-ui guestbook-ui=nginx:does-not-exist

# selfHeal will revert this in ~1 min if you wait. Race it — quickly check before then:
oc -n openshift-gitops get application guestbook-<you> -o jsonpath='{.status.sync.status} {.status.health.status}{"\n"}'

# What did Sync say? What did Health say? Why was that the answer? (Both)
```

## Deliverable — `deliverables/<you>/week02/thursday.md`

1. **Your Application YAML** — the working version, ServiceAccount + Project + sync policy
2. **A screenshot or text dump of the ArgoCD UI's resource graph** for your app (`oc -n openshift-gitops get application guestbook-<you> -o yaml | tail -50` is acceptable as text)
3. **The drift-and-heal trace** — `oc get deployment ... -w` output showing the scale-to-5 then ArgoCD reverting
4. **The two break scenarios** — for each, what condition message did ArgoCD show, and what was the resolution
5. **The production split** — in 3 sentences, explain why CFK CRs in production are deployed via Azure DevOps instead of ArgoCD. Reference the per-env variable group + the `apps/confluent-platform/<env>/` folder structure. (Hint: ArgoCD owns OPERATORS; Azure DevOps owns WORKLOADS. Why?)
6. Two questions

Cleanup:

```bash
oc -n openshift-gitops delete application guestbook-<you>
# ArgoCD will cascade-delete the workload since prune=true
```
