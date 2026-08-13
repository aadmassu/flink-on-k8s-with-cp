# Week 1 Friday — Lab: ConfigMaps, Secrets, ServiceAccounts, RBAC (break-then-fix)

## Goal

Land Friday's discussion in your hands:

1. Create each of the five primitives (ConfigMap, Secret, ServiceAccount, Role, RoleBinding) directly — no operator, no CFK — so you see exactly what each object is.
2. Wire a Pod up to consume them.
3. **Break each one on purpose** and watch the failure surface at the matching layer (admission, scheduling, container start, runtime API call).
4. Map the symptoms back to a future CFK install — every breakage you see today corresponds to a real failure mode CFK engineers hit later in the bootcamp.

## Pick your local cluster

Either works. Pick whichever you already have running.

### Option A — kind (laptop, no OpenShift)

```bash
kind create cluster --name training --config ../../lab-cluster/00-kind-cluster-config.yaml
kubectl config use-context kind-training
```

### Option B — OpenShift Local (CRC) or any `oc`-connected cluster

```bash
crc start                          # or: oc login <your-cluster>
oc new-project cfg-rbac-lab
```

> Every step below is shown in **both `oc` and `kubectl`** forms. Run only the one that matches your cluster. `oc` is a superset of `kubectl` — the `kubectl` form also works on OpenShift if you prefer.

If you're on kind, create the namespace:

```bash
kubectl create namespace cfg-rbac-lab --dry-run=client -o yaml | kubectl apply -f -
kubectl config set-context --current --namespace=cfg-rbac-lab
```

---

## Part 1 — ConfigMaps

### 1.1 Create a ConfigMap two ways

Way one: imperative, from literal values.

```bash
# oc
oc create configmap app-config \
  --from-literal=app.name=lab-app \
  --from-literal=log.level=INFO

# kubectl
kubectl create configmap app-config \
  --from-literal=app.name=lab-app \
  --from-literal=log.level=INFO
```

Way two: declarative YAML — the form CFK reconciles into.

```bash
# oc
oc apply -f - <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-properties
data:
  application.properties: |
    server.port=8080
    feature.flag=true
    db.connections.max=20
EOF

# kubectl
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-properties
data:
  application.properties: |
    server.port=8080
    feature.flag=true
    db.connections.max=20
EOF
```

Inspect what's stored:

```bash
# oc
oc get cm app-config -o yaml
oc get cm app-properties -o jsonpath='{.data.application\.properties}'

# kubectl
kubectl get cm app-config -o yaml
kubectl get cm app-properties -o jsonpath='{.data.application\.properties}'
```

### 1.2 Consume a ConfigMap as env vars AND as a mounted file

```bash
# oc
oc apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: cm-consumer
spec:
  containers:
    - name: reader
      image: busybox:1.36
      command: ["sh","-c","echo 'env vars:'; env | grep -E '^(APP_NAME|LOG_LEVEL)='; echo 'mounted file:'; cat /etc/app/application.properties; sleep 3600"]
      env:
        - name: APP_NAME
          valueFrom:
            configMapKeyRef: {name: app-config, key: app.name}
        - name: LOG_LEVEL
          valueFrom:
            configMapKeyRef: {name: app-config, key: log.level}
      volumeMounts:
        - {name: props, mountPath: /etc/app}
  volumes:
    - name: props
      configMap: {name: app-properties}
EOF

# kubectl
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: cm-consumer
spec:
  containers:
    - name: reader
      image: busybox:1.36
      command: ["sh","-c","echo 'env vars:'; env | grep -E '^(APP_NAME|LOG_LEVEL)='; echo 'mounted file:'; cat /etc/app/application.properties; sleep 3600"]
      env:
        - name: APP_NAME
          valueFrom:
            configMapKeyRef: {name: app-config, key: app.name}
        - name: LOG_LEVEL
          valueFrom:
            configMapKeyRef: {name: app-config, key: log.level}
      volumeMounts:
        - {name: props, mountPath: /etc/app}
  volumes:
    - name: props
      configMap: {name: app-properties}
EOF
```

Read what landed inside the Pod:

```bash
# oc
oc wait --for=condition=Ready pod/cm-consumer --timeout=60s
oc logs cm-consumer

# kubectl
kubectl wait --for=condition=Ready pod/cm-consumer --timeout=60s
kubectl logs cm-consumer
```

### 1.3 Break it — ConfigMap name typo

Reference a ConfigMap that doesn't exist. Predict the symptom first.

```bash
# oc
oc apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: cm-typo
spec:
  containers:
    - name: c
      image: busybox:1.36
      command: ["sleep","3600"]
      env:
        - name: APP_NAME
          valueFrom:
            configMapKeyRef: {name: app-config-DOES-NOT-EXIST, key: app.name}
EOF
oc get pod cm-typo
oc describe pod cm-typo | sed -n '/^Events:/,$p'

# kubectl
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: cm-typo
spec:
  containers:
    - name: c
      image: busybox:1.36
      command: ["sleep","3600"]
      env:
        - name: APP_NAME
          valueFrom:
            configMapKeyRef: {name: app-config-DOES-NOT-EXIST, key: app.name}
EOF
kubectl get pod cm-typo
kubectl describe pod cm-typo | sed -n '/^Events:/,$p'
```

Symptom: Pod stuck in `CreateContainerConfigError`. The Event message names the missing ConfigMap. **This is the same failure shape you'd see if CFK's operator-generated ConfigMap was somehow deleted underneath a running CFK component.**

### 1.4 Break it — ConfigMap edited, env-var consumer doesn't refresh

Change a value and watch which consumer sees it.

```bash
# oc
oc create configmap app-config --from-literal=app.name=lab-app-v2 --from-literal=log.level=DEBUG \
  --dry-run=client -o yaml | oc apply -f -
oc apply -f - <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-properties
data:
  application.properties: |
    server.port=8080
    feature.flag=true
    db.connections.max=99
EOF

# kubectl
kubectl create configmap app-config --from-literal=app.name=lab-app-v2 --from-literal=log.level=DEBUG \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-properties
data:
  application.properties: |
    server.port=8080
    feature.flag=true
    db.connections.max=99
EOF
```

Wait ~60 seconds, then re-check the consumer:

```bash
# oc
oc exec cm-consumer -- env | grep -E '^(APP_NAME|LOG_LEVEL)='
oc exec cm-consumer -- cat /etc/app/application.properties

# kubectl
kubectl exec cm-consumer -- env | grep -E '^(APP_NAME|LOG_LEVEL)='
kubectl exec cm-consumer -- cat /etc/app/application.properties
```

**Env vars still show the OLD values** (`APP_NAME=lab-app`, `LOG_LEVEL=INFO`) — env vars are baked in at Pod start. **The mounted file shows the NEW value** (`db.connections.max=99`) — kubelet projects updated content into the volume. This is exactly why CFK rolls Pods when you change `configOverrides:` instead of expecting a hot reload.

Clean up Part 1's broken Pod:

```bash
# oc
oc delete pod cm-typo --ignore-not-found

# kubectl
kubectl delete pod cm-typo --ignore-not-found
```

---

## Part 2 — Secrets

### 2.1 Create an Opaque Secret and a TLS Secret

```bash
# oc
oc create secret generic db-credentials \
  --from-literal=username=app-user \
  --from-literal=password=very-secret-123

# kubectl
kubectl create secret generic db-credentials \
  --from-literal=username=app-user \
  --from-literal=password=very-secret-123
```

Inspect — note that values come back **base64-encoded** in `data:`, not encrypted:

```bash
# oc
oc get secret db-credentials -o yaml
oc get secret db-credentials -o jsonpath='{.data.password}' | base64 -d ; echo
oc get secret db-credentials -o jsonpath='{.data}' | python3 -c "import json,sys; print(sorted(json.load(sys.stdin).keys()))"

# kubectl
kubectl get secret db-credentials -o yaml
kubectl get secret db-credentials -o jsonpath='{.data.password}' | base64 -d ; echo
kubectl get secret db-credentials -o jsonpath='{.data}' | python3 -c "import json,sys; print(sorted(json.load(sys.stdin).keys()))"
```

Generate a self-signed cert + key, then store them in a typed TLS Secret (same shape as CFK's `<cr>-tls` Secrets):

```bash
openssl req -x509 -newkey rsa:2048 -days 1 -nodes \
  -subj "/CN=lab.example.com" \
  -keyout /tmp/tls.key -out /tmp/tls.crt 2>/dev/null

# oc
oc create secret tls lab-tls --cert=/tmp/tls.crt --key=/tmp/tls.key

# kubectl
kubectl create secret tls lab-tls --cert=/tmp/tls.crt --key=/tmp/tls.key
```

Confirm the typed shape (kubernetes.io/tls requires both `tls.crt` and `tls.key` keys):

```bash
# oc
oc get secret lab-tls -o jsonpath='{.type}' ; echo
oc get secret lab-tls -o jsonpath='{.data}' | python3 -c "import json,sys; print(sorted(json.load(sys.stdin).keys()))"

# kubectl
kubectl get secret lab-tls -o jsonpath='{.type}' ; echo
kubectl get secret lab-tls -o jsonpath='{.data}' | python3 -c "import json,sys; print(sorted(json.load(sys.stdin).keys()))"
```

### 2.2 Consume a Secret as env vars AND a mounted directory

```bash
# oc
oc apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: sec-consumer
spec:
  containers:
    - name: reader
      image: busybox:1.36
      command: ["sh","-c","echo 'env DB_USER:'; echo \"$DB_USER\"; echo 'mounted tls files:'; ls -la /mnt/tls; sleep 3600"]
      env:
        - name: DB_USER
          valueFrom:
            secretKeyRef: {name: db-credentials, key: username}
      volumeMounts:
        - {name: tls, mountPath: /mnt/tls, readOnly: true}
  volumes:
    - name: tls
      secret: {secretName: lab-tls}
EOF
oc wait --for=condition=Ready pod/sec-consumer --timeout=60s
oc logs sec-consumer

# kubectl
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: sec-consumer
spec:
  containers:
    - name: reader
      image: busybox:1.36
      command: ["sh","-c","echo 'env DB_USER:'; echo \"$DB_USER\"; echo 'mounted tls files:'; ls -la /mnt/tls; sleep 3600"]
      env:
        - name: DB_USER
          valueFrom:
            secretKeyRef: {name: db-credentials, key: username}
      volumeMounts:
        - {name: tls, mountPath: /mnt/tls, readOnly: true}
  volumes:
    - name: tls
      secret: {secretName: lab-tls}
EOF
kubectl wait --for=condition=Ready pod/sec-consumer --timeout=60s
kubectl logs sec-consumer
```

The Pod prints the decoded `username` env var **and** lists `tls.crt` + `tls.key` from the mount.

### 2.3 Break it — Secret references a key that doesn't exist

```bash
# oc
oc apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: sec-missing-key
spec:
  containers:
    - name: c
      image: busybox:1.36
      command: ["sleep","3600"]
      env:
        - name: API_TOKEN
          valueFrom:
            secretKeyRef: {name: db-credentials, key: token-that-isnt-in-the-secret}
EOF
oc get pod sec-missing-key
oc describe pod sec-missing-key | sed -n '/^Events:/,$p'

# kubectl
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: sec-missing-key
spec:
  containers:
    - name: c
      image: busybox:1.36
      command: ["sleep","3600"]
      env:
        - name: API_TOKEN
          valueFrom:
            secretKeyRef: {name: db-credentials, key: token-that-isnt-in-the-secret}
EOF
kubectl get pod sec-missing-key
kubectl describe pod sec-missing-key | sed -n '/^Events:/,$p'
```

Same `CreateContainerConfigError` shape as the missing-ConfigMap case — Event names the missing key by exact name. This is the failure shape you'd see if CFK's `cmf-encryption-key` Secret existed but had the wrong key name.

### 2.4 Break it — TLS Secret with the wrong content

Recreate `lab-tls` as a generic Secret with bogus content, observe what changes:

```bash
# oc
oc delete secret lab-tls
oc create secret generic lab-tls --from-literal=cert=not-a-cert --from-literal=key=not-a-key
oc get secret lab-tls -o jsonpath='{.type}' ; echo
oc delete pod sec-consumer
oc apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: sec-consumer
spec:
  containers:
    - name: reader
      image: busybox:1.36
      command: ["sh","-c","ls -la /mnt/tls; cat /mnt/tls/tls.crt; sleep 3600"]
      volumeMounts:
        - {name: tls, mountPath: /mnt/tls}
  volumes:
    - name: tls
      secret: {secretName: lab-tls}
EOF
oc wait --for=condition=Ready pod/sec-consumer --timeout=60s
oc logs sec-consumer

# kubectl
kubectl delete secret lab-tls
kubectl create secret generic lab-tls --from-literal=cert=not-a-cert --from-literal=key=not-a-key
kubectl get secret lab-tls -o jsonpath='{.type}' ; echo
kubectl delete pod sec-consumer
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: sec-consumer
spec:
  containers:
    - name: reader
      image: busybox:1.36
      command: ["sh","-c","ls -la /mnt/tls; cat /mnt/tls/tls.crt; sleep 3600"]
      volumeMounts:
        - {name: tls, mountPath: /mnt/tls}
  volumes:
    - name: tls
      secret: {secretName: lab-tls}
EOF
kubectl wait --for=condition=Ready pod/sec-consumer --timeout=60s
kubectl logs sec-consumer
```

Notice: the Pod still starts (Kubernetes doesn't validate the *content* of an Opaque Secret), but the file at `/mnt/tls/tls.crt` is now empty — there's no `tls.crt` key in the Secret. **A real CFK component would crashloop here at init time**, because its config-rendering script tries to read `tls.crt` and finds nothing. The Pod starts; the application fails. This is why CFK validates Secret content at the init-container layer.

Restore the proper TLS Secret:

```bash
# oc
oc delete secret lab-tls
oc create secret tls lab-tls --cert=/tmp/tls.crt --key=/tmp/tls.key

# kubectl
kubectl delete secret lab-tls
kubectl create secret tls lab-tls --cert=/tmp/tls.crt --key=/tmp/tls.key
```

Cleanup Part 2:

```bash
# oc
oc delete pod sec-missing-key --ignore-not-found

# kubectl
kubectl delete pod sec-missing-key --ignore-not-found
```

---

## Part 3 — ServiceAccounts, Roles, RoleBindings

### 3.1 Create a ServiceAccount and use it

```bash
# oc
oc create serviceaccount lab-sa
oc get sa lab-sa -o yaml

# kubectl
kubectl create serviceaccount lab-sa
kubectl get sa lab-sa -o yaml
```

Run a Pod **as that SA**, then try to list Pods from inside (using the SA's mounted token):

```bash
# oc
oc apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: sa-probe
spec:
  serviceAccountName: lab-sa
  containers:
    - name: c
      image: bitnami/kubectl:1.30
      command: ["sh","-c","echo 'whoami via token:'; kubectl auth whoami 2>&1 || true; echo 'list pods in this namespace:'; kubectl get pods 2>&1; sleep 3600"]
EOF
oc wait --for=condition=Ready pod/sa-probe --timeout=60s
oc logs sa-probe

# kubectl
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: sa-probe
spec:
  serviceAccountName: lab-sa
  containers:
    - name: c
      image: bitnami/kubectl:1.30
      command: ["sh","-c","echo 'whoami via token:'; kubectl auth whoami 2>&1 || true; echo 'list pods in this namespace:'; kubectl get pods 2>&1; sleep 3600"]
EOF
kubectl wait --for=condition=Ready pod/sa-probe --timeout=60s
kubectl logs sa-probe
```

Expected output: `kubectl auth whoami` reports `system:serviceaccount:cfg-rbac-lab:lab-sa`, then `kubectl get pods` fails with **"forbidden"**. The SA has an identity but no permissions yet.

### 3.2 Add a Role + RoleBinding so the SA can list pods

```bash
# oc
oc apply -f - <<'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: pod-reader
rules:
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: lab-sa-pod-reader
subjects:
  - kind: ServiceAccount
    name: lab-sa
    namespace: cfg-rbac-lab
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: pod-reader
EOF

# kubectl
kubectl apply -f - <<'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: pod-reader
rules:
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: lab-sa-pod-reader
subjects:
  - kind: ServiceAccount
    name: lab-sa
    namespace: cfg-rbac-lab
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: pod-reader
EOF
```

The probe Pod's `kubectl` calls cache the failure, so trigger a fresh attempt:

```bash
# oc
oc exec sa-probe -- kubectl get pods

# kubectl
kubectl exec sa-probe -- kubectl get pods
```

Now it lists pods. The flow: **SA mounts a token → token authenticates as `system:serviceaccount:cfg-rbac-lab:lab-sa` → RoleBinding names that SA as a subject → Role authorizes `get/list/watch pods`**.

### 3.3 Break it — delete the RoleBinding

```bash
# oc
oc delete rolebinding lab-sa-pod-reader
oc exec sa-probe -- kubectl get pods 2>&1 | head -3

# kubectl
kubectl delete rolebinding lab-sa-pod-reader
kubectl exec sa-probe -- kubectl get pods 2>&1 | head -3
```

Forbidden again — the **Role still exists** (you can `get role pod-reader`), but a Role with nothing subjected to it grants nothing. This is exactly the situation CFK operators land in when a namespace-scoped install is missing the per-workload-namespace RoleBinding.

### 3.4 Break it — RoleBinding subjects the wrong namespace

Recreate the binding with the wrong namespace on the subject:

```bash
# oc
oc apply -f - <<'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: lab-sa-pod-reader
subjects:
  - kind: ServiceAccount
    name: lab-sa
    namespace: some-other-namespace      # WRONG — SA actually lives in cfg-rbac-lab
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: pod-reader
EOF
oc exec sa-probe -- kubectl get pods 2>&1 | head -3

# kubectl
kubectl apply -f - <<'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: lab-sa-pod-reader
subjects:
  - kind: ServiceAccount
    name: lab-sa
    namespace: some-other-namespace      # WRONG — SA actually lives in cfg-rbac-lab
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: pod-reader
EOF
kubectl exec sa-probe -- kubectl get pods 2>&1 | head -3
```

Still forbidden. The RoleBinding *exists*, but its subject is "the SA `lab-sa` in `some-other-namespace`" — a different identity from the one your Pod is actually running as. Diagnosing this on a real cluster requires reading the subject block carefully; the symptom looks identical to "no RoleBinding at all".

Fix the subject:

```bash
# oc
oc apply -f - <<'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: lab-sa-pod-reader
subjects:
  - kind: ServiceAccount
    name: lab-sa
    namespace: cfg-rbac-lab
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: pod-reader
EOF
oc exec sa-probe -- kubectl get pods

# kubectl
kubectl apply -f - <<'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: lab-sa-pod-reader
subjects:
  - kind: ServiceAccount
    name: lab-sa
    namespace: cfg-rbac-lab
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: pod-reader
EOF
kubectl exec sa-probe -- kubectl get pods
```

### 3.5 Break it — ServiceAccount referenced by the Pod doesn't exist

```bash
# oc
oc apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: sa-missing
spec:
  serviceAccountName: this-sa-does-not-exist
  containers:
    - name: c
      image: busybox:1.36
      command: ["sleep","3600"]
EOF
oc get pod sa-missing
oc describe pod sa-missing | sed -n '/^Events:/,$p'

# kubectl
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: sa-missing
spec:
  serviceAccountName: this-sa-does-not-exist
  containers:
    - name: c
      image: busybox:1.36
      command: ["sleep","3600"]
EOF
kubectl get pod sa-missing
kubectl describe pod sa-missing | sed -n '/^Events:/,$p'
```

Pod fails to schedule with `error looking up service account ... : serviceaccount "this-sa-does-not-exist" not found`. This is the failure shape you'd see if a CFK CR's `podTemplate.serviceAccountName:` named a pre-existing SA that wasn't actually created.

Cleanup Part 3's broken Pod:

```bash
# oc
oc delete pod sa-missing --ignore-not-found

# kubectl
kubectl delete pod sa-missing --ignore-not-found
```

---

## Part 4 — Bring it together: a Pod that consumes all five primitives

This is the smallest possible mirror of what a CFK component actually looks like at runtime — one Pod that runs as a custom SA, reads a ConfigMap as a file, mounts a TLS Secret, makes an in-cluster API call, and depends on a Role/RoleBinding to do that call.

### 4.1 Apply the full set

```bash
# oc
oc apply -f - <<'EOF'
apiVersion: v1
kind: ServiceAccount
metadata:
  name: app-sa
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: app-reads-own-config
rules:
  - apiGroups: [""]
    resources: ["configmaps", "secrets"]
    verbs: ["get", "list", "watch"]
    resourceNames: ["app-properties", "lab-tls"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: app-sa-reads-own-config
subjects:
  - kind: ServiceAccount
    name: app-sa
    namespace: cfg-rbac-lab
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: app-reads-own-config
---
apiVersion: v1
kind: Pod
metadata:
  name: full-stack
spec:
  serviceAccountName: app-sa
  containers:
    - name: app
      image: bitnami/kubectl:1.30
      command:
        - sh
        - -c
        - |
          echo "[1] application.properties:"
          cat /etc/app/application.properties
          echo ""
          echo "[2] TLS files:"
          ls -la /mnt/tls
          echo ""
          echo "[3] SA identity:"
          kubectl auth whoami 2>&1 | head -2
          echo ""
          echo "[4] Can I list MY ConfigMap (RBAC-allowed)?"
          kubectl get cm app-properties 2>&1
          echo ""
          echo "[5] Can I list ALL ConfigMaps (should fail — Role restricts to resourceNames)?"
          kubectl get cm 2>&1 | head -3
          sleep 3600
      volumeMounts:
        - {name: cfg, mountPath: /etc/app}
        - {name: tls, mountPath: /mnt/tls, readOnly: true}
  volumes:
    - name: cfg
      configMap: {name: app-properties}
    - name: tls
      secret: {secretName: lab-tls}
EOF
oc wait --for=condition=Ready pod/full-stack --timeout=60s
oc logs full-stack

# kubectl
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: ServiceAccount
metadata:
  name: app-sa
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: app-reads-own-config
rules:
  - apiGroups: [""]
    resources: ["configmaps", "secrets"]
    verbs: ["get", "list", "watch"]
    resourceNames: ["app-properties", "lab-tls"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: app-sa-reads-own-config
subjects:
  - kind: ServiceAccount
    name: app-sa
    namespace: cfg-rbac-lab
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: app-reads-own-config
---
apiVersion: v1
kind: Pod
metadata:
  name: full-stack
spec:
  serviceAccountName: app-sa
  containers:
    - name: app
      image: bitnami/kubectl:1.30
      command:
        - sh
        - -c
        - |
          echo "[1] application.properties:"
          cat /etc/app/application.properties
          echo ""
          echo "[2] TLS files:"
          ls -la /mnt/tls
          echo ""
          echo "[3] SA identity:"
          kubectl auth whoami 2>&1 | head -2
          echo ""
          echo "[4] Can I list MY ConfigMap (RBAC-allowed)?"
          kubectl get cm app-properties 2>&1
          echo ""
          echo "[5] Can I list ALL ConfigMaps (should fail — Role restricts to resourceNames)?"
          kubectl get cm 2>&1 | head -3
          sleep 3600
      volumeMounts:
        - {name: cfg, mountPath: /etc/app}
        - {name: tls, mountPath: /mnt/tls, readOnly: true}
  volumes:
    - name: cfg
      configMap: {name: app-properties}
    - name: tls
      secret: {secretName: lab-tls}
EOF
kubectl wait --for=condition=Ready pod/full-stack --timeout=60s
kubectl logs full-stack
```

You should see (1) the file contents from the ConfigMap, (2) the `tls.crt`/`tls.key` listing from the Secret, (3) `kubectl auth whoami` printing `system:serviceaccount:cfg-rbac-lab:app-sa`, (4) `get cm app-properties` succeeds, (5) `get cm` (all) fails with **forbidden** — the Role's `resourceNames` restricts it to one specific ConfigMap, the same tight scoping CFK's per-component Role uses.

### 4.2 Now break **one** thing — walk the troubleshooting tree

Pick one of the four breakages below. Predict the failure layer before you apply.

#### Break 4a — Pod references a ConfigMap that doesn't exist (cosmetic typo)

```bash
# oc
oc patch pod full-stack --type=json -p='[{"op":"replace","path":"/spec/volumes/0/configMap/name","value":"app-properties-typo"}]' 2>&1 | head -3

# kubectl
kubectl patch pod full-stack --type=json -p='[{"op":"replace","path":"/spec/volumes/0/configMap/name","value":"app-properties-typo"}]' 2>&1 | head -3
```

Patch is **rejected** — running Pods can't change immutable spec fields. Realistic flow: delete and re-create with the typo:

```bash
# oc
oc delete pod full-stack
# … re-apply with name app-properties-typo in spec.volumes[0].configMap.name …
# Result: CreateContainerConfigError, Event names the missing ConfigMap.

# kubectl
kubectl delete pod full-stack
# … re-apply with name app-properties-typo in spec.volumes[0].configMap.name …
# Result: CreateContainerConfigError, Event names the missing ConfigMap.
```

(Restoring the Pod is left as step (6) of the deliverable — re-apply the original manifest.)

#### Break 4b — Delete the RoleBinding

```bash
# oc
oc delete rolebinding app-sa-reads-own-config
oc exec full-stack -- kubectl get cm app-properties 2>&1 | head -3

# kubectl
kubectl delete rolebinding app-sa-reads-own-config
kubectl exec full-stack -- kubectl get cm app-properties 2>&1 | head -3
```

Pod stays Ready (it doesn't crash — the API call just fails). `kubectl get cm app-properties` → **forbidden**. Container looks healthy; *application functionality* is broken. This is the most insidious CFK failure mode — Pod metrics green, application broken.

Restore:

```bash
# oc
oc apply -f - <<'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: app-sa-reads-own-config
subjects:
  - kind: ServiceAccount
    name: app-sa
    namespace: cfg-rbac-lab
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: app-reads-own-config
EOF

# kubectl
kubectl apply -f - <<'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: app-sa-reads-own-config
subjects:
  - kind: ServiceAccount
    name: app-sa
    namespace: cfg-rbac-lab
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: app-reads-own-config
EOF
```

#### Break 4c — Edit the Role to drop the `secrets` resource

```bash
# oc
oc apply -f - <<'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: app-reads-own-config
rules:
  - apiGroups: [""]
    resources: ["configmaps"]            # secrets removed
    verbs: ["get", "list", "watch"]
    resourceNames: ["app-properties"]
EOF
oc exec full-stack -- kubectl get secret lab-tls 2>&1 | head -3

# kubectl
kubectl apply -f - <<'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: app-reads-own-config
rules:
  - apiGroups: [""]
    resources: ["configmaps"]            # secrets removed
    verbs: ["get", "list", "watch"]
    resourceNames: ["app-properties"]
EOF
kubectl exec full-stack -- kubectl get secret lab-tls 2>&1 | head -3
```

API call for `secret/lab-tls` is now forbidden. But the **mounted TLS files at `/mnt/tls` still work** — kubelet projected them at scheduling time and doesn't consult the SA's RBAC. Application code that reads `/mnt/tls/tls.crt` still works; application code that does in-process `kubectl get secret` fails. This is the difference the discussion called out — kubelet projection vs SA RBAC.

Restore by re-adding `secrets` to the Role's resources list.

#### Break 4d — Swap the Pod's SA to one without the binding

```bash
# oc
oc create serviceaccount unprivileged-sa
# Pod spec.serviceAccountName is immutable — recreate the Pod with the swap to see the failure
oc delete pod full-stack

# kubectl
kubectl create serviceaccount unprivileged-sa
kubectl delete pod full-stack
```

Re-apply the Pod from 4.1 with `serviceAccountName: unprivileged-sa` (and the ConfigMap + Secret volumes intact). Result: identity check shows `system:serviceaccount:cfg-rbac-lab:unprivileged-sa`; ConfigMap mount still resolves (kubelet); API calls fail (no RoleBinding for this SA).

Restore by re-applying the original Pod manifest with `serviceAccountName: app-sa`.

---

## Deliverable — `deliverables/<your-name>/week01/friday-cfg-rbac.md`

1. **The five primitives in your own words** — one sentence each for ConfigMap, Secret, ServiceAccount, Role, RoleBinding. No copy-paste from the discussion.
2. **Part 1 evidence** — your `oc/kubectl logs cm-consumer` showing the env vars + mounted file values BEFORE and AFTER the 1.4 edit. Three sentences explaining why env vars are stale but the file isn't.
3. **Part 2 evidence** — the Event message from the missing-Secret-key Pod (Break 2.3), and a one-line note describing what changed visually in the wrong-content TLS Secret case (Break 2.4).
4. **Part 3 evidence** — the `kubectl auth whoami` line from `sa-probe`, the **forbidden** error from before you added the RoleBinding, and the successful `get pods` after. State the four-link chain (Pod → SA → RoleBinding → Role) in your own words.
5. **Part 4 troubleshooting trace** — for the one breakage you picked (4a, 4b, 4c, or 4d):
   - The exact symptom you observed
   - Which layer it surfaced at (admission / scheduling / container start / runtime API call)
   - How you'd recognize the same shape on a future CFK install (which CFK Secret, ConfigMap, SA, Role, or RoleBinding would map to the broken object)
6. **Bridge to next week** — three sentences predicting what each of the five primitives looks like in a real CFK Kafka install. Reference the discussion's "operator generates X / external Y" matrix.

## Cleanup

```bash
# oc
oc delete pod cm-consumer sec-consumer sa-probe full-stack --ignore-not-found
oc delete configmap app-config app-properties --ignore-not-found
oc delete secret db-credentials lab-tls --ignore-not-found
oc delete role pod-reader app-reads-own-config --ignore-not-found
oc delete rolebinding lab-sa-pod-reader app-sa-reads-own-config --ignore-not-found
oc delete sa lab-sa app-sa unprivileged-sa --ignore-not-found
oc delete project cfg-rbac-lab          # or: oc delete namespace cfg-rbac-lab

# kubectl
kubectl delete pod cm-consumer sec-consumer sa-probe full-stack --ignore-not-found
kubectl delete configmap app-config app-properties --ignore-not-found
kubectl delete secret db-credentials lab-tls --ignore-not-found
kubectl delete role pod-reader app-reads-own-config --ignore-not-found
kubectl delete rolebinding lab-sa-pod-reader app-sa-reads-own-config --ignore-not-found
kubectl delete sa lab-sa app-sa unprivileged-sa --ignore-not-found
kubectl delete namespace cfg-rbac-lab
```

If you spun up a kind cluster only for this lab, the cheapest cleanup is:

```bash
kind delete cluster --name training
```

Removes every namespace, RBAC object, Pod, and PVC in one shot.

---

## Take-aways the bootcamp will lean on next week

- **CFK's per-component ConfigMap** = exactly what Part 1.4 showed: kubelet projects updated content, but the application doesn't hot-reload — that's why a `configOverrides:` edit rolls the StatefulSet.
- **CFK's `<cr>-tls` and `oauth-<role>` Secrets** = exactly what Part 2.3/2.4 showed: name match is the easy part; **key-name and content shape** is what causes the silent boot failures.
- **CFK's per-component SA + Role + RoleBinding** = exactly what Part 3 + Part 4 showed: each layer can be present and *still* grant nothing. When a CFK pod reports forbidden errors talking to the API, the SA → RoleBinding → Role chain is what to walk.
- **The operator's own SA + RB/CRB** is the same pattern at a different scale — Week 4 will show you the operator's permissions and how to verify a namespace-scoped install has the right RoleBinding in every workload namespace.
