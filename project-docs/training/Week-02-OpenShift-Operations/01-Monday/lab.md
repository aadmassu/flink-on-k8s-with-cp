# Week 2 Monday — Lab: Build a Working RBAC Sandbox

**Time**: ~3 hours

## Hands-on Lab — create a read-only "viewer" Role for your training project

```bash
oc project <you>-training

# 1. Create a ServiceAccount that will act as a "viewer" identity
oc create sa viewer

# 2. Create a Role: viewer can GET/LIST/WATCH pods, services, deployments — but NOT secrets, NOT create anything
cat <<EOF | oc apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: viewer-role
rules:
  - apiGroups: [""]
    resources: ["pods", "services", "configmaps"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["apps"]
    resources: ["deployments", "replicasets", "statefulsets"]
    verbs: ["get", "list", "watch"]
EOF

# 3. Bind the SA to the Role
cat <<EOF | oc apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: viewer-binding
subjects:
  - kind: ServiceAccount
    name: viewer
    namespace: <you>-training
roleRef:
  kind: Role
  name: viewer-role
  apiGroup: rbac.authorization.k8s.io
EOF

# 4. Verify with the diagnostic command
SA="system:serviceaccount:<you>-training:viewer"
oc auth can-i list pods --as=$SA -n <you>-training            # yes
oc auth can-i create pods --as=$SA -n <you>-training          # no
oc auth can-i get secrets --as=$SA -n <you>-training          # no
oc auth can-i list deployments --as=$SA -n <you>-training     # yes
oc auth can-i delete deployments --as=$SA -n <you>-training   # no
```

Each `oc auth can-i` should answer `yes` or `no` matching the Role you wrote. If it gets the answer wrong, fix the Role and re-test.

## Hands-on Lab Part 2 — run a Pod AS the viewer SA

```bash
# Deploy a Pod that uses the viewer SA + a busybox image with kubectl pre-installed
cat <<EOF | oc apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: viewer-pod
spec:
  serviceAccountName: viewer
  containers:
    - name: c
      image: bitnami/kubectl:1.30
      command: ["sleep","3600"]
EOF

oc wait --for=condition=Ready pod/viewer-pod --timeout=60s

# Exec in and try things — Pod uses its SA token automatically
oc exec viewer-pod -- kubectl get pods            # works
oc exec viewer-pod -- kubectl get secrets         # FORBIDDEN
oc exec viewer-pod -- kubectl delete pod viewer-pod   # FORBIDDEN
```

This is the EXACT same model the CFK / Flink Operator Pods use. Their SA + Role pair determines what they can do.

## Troubleshooting Exercise — three intentional misconfigurations

**Break 1 — the verb is wrong**

```bash
oc patch role viewer-role --type='json' -p='[{"op":"replace","path":"/rules/0/verbs","value":["create"]}]'

# Predict: which `oc auth can-i` answers flip? Verify.
oc auth can-i list pods --as=$SA -n <you>-training            # ?
oc auth can-i create pods --as=$SA -n <you>-training          # ?

# Restore:
oc patch role viewer-role --type='json' -p='[{"op":"replace","path":"/rules/0/verbs","value":["get","list","watch"]}]'
```

**Break 2 — the apiGroup is wrong**

```bash
# Try to grant access to "deployments" but in the wrong apiGroup
oc patch role viewer-role --type='json' -p='[{"op":"replace","path":"/rules/1/apiGroups","value":[""]}]'

oc auth can-i list deployments --as=$SA -n <you>-training     # ?
# Why does this fail? (Deployments are in 'apps', not '')

# Restore:
oc patch role viewer-role --type='json' -p='[{"op":"replace","path":"/rules/1/apiGroups","value":["apps"]}]'
```

**Break 3 — the RoleBinding references the wrong subject namespace**

```bash
# Patch the binding to point at an SA in a non-existent namespace
oc patch rolebinding viewer-binding --type='json' -p='[{"op":"replace","path":"/subjects/0/namespace","value":"WRONG"}]'

oc auth can-i list pods --as=$SA -n <you>-training            # what now?

# Restore:
oc patch rolebinding viewer-binding --type='json' -p='[{"op":"replace","path":"/subjects/0/namespace","value":"<you>-training"}]'
```

## Deliverable — `deliverables/<you>/week02/monday.md`

1. **Your viewer Role + RoleBinding YAML** (the working versions)
2. **The full `oc auth can-i` matrix** — 8 rows, one per (verb, resource) combination you tested, with the actual `yes` / `no` output
3. **For each of the 3 breakages**: which `oc auth can-i` answer flipped, and why (reference apiGroups / verbs / namespace match)
4. **The CFK connection** — in 3 sentences, explain how the platform-side `flink-operator` SA pre-creation gate (tracker 3.2) is the EXACT same model you just built. Reference the namespace name, the Role's verbs, the RoleBinding's subject.
5. Two questions

Cleanup:

```bash
oc delete pod viewer-pod
oc delete sa viewer
oc delete role viewer-role
oc delete rolebinding viewer-binding
```
