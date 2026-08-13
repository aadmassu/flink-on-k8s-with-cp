# Week 2 Tuesday — Lab: Watch a Real Operator Reconcile

**Time**: ~4 hours

The point of this lab is NOT to learn one specific operator's syntax. It's to watch the reconcile loop happen in real time, so when CFK behaves the same way in Week 4 it's familiar.

## Hands-on Lab — install cert-manager Operator + watch it reconcile

cert-manager is the canonical "good citizen" operator and is the perfect first one because  the platform already uses it (see `apps/confluent-platform/<env>/cert-manager/` — the production CFK Certificate CRs are reconciled by the cert-manager Operator).

```bash
# 1. If cert-manager isn't already installed on this cluster, install it from OperatorHub:
#    Console: Operators → OperatorHub → search "cert-manager" → Install (cluster-wide).
#    CLI alternative (skip if your dev cluster already has it):
oc apply -f https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.yaml

# 2. Confirm the operator Pod is running and watching the API
oc -n cert-manager get pods
oc -n cert-manager logs deployment/cert-manager -f &
LOGTAIL=$!

# 3. Create a self-signed Issuer (the "config" CR) — a small CR to start
oc project <you>-training
cat <<EOF | oc apply -f -
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: selfsigned
spec:
  selfSigned: {}
EOF

# 4. Now create a Certificate CR — the operator should reconcile and produce a Secret holding a TLS cert + key
cat <<EOF | oc apply -f -
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: my-first-cert
spec:
  secretName: my-first-cert-tls    # where the operator will write the result
  duration: 2160h                   # 90 days
  commonName: my-first-cert.<you>-training.svc
  issuerRef:
    name: selfsigned
    kind: Issuer
EOF

# 5. Watch the reconcile happen in real time
oc get certificate -w &
sleep 15
oc get certificate my-first-cert -o yaml | sed -n '/^status:/,$p'

# 6. The operator should have CREATED the Secret as a child object
oc get secret my-first-cert-tls
oc get secret my-first-cert-tls -o yaml | head -30

# 7. Inspect the owner references — the Secret points at the Certificate CR
oc get secret my-first-cert-tls -o jsonpath='{.metadata.ownerReferences}' | python3 -m json.tool

# 8. Kill the LogTail
kill $LOGTAIL
```

In your runbook, note: **how long did it take from `oc apply` to `Ready=True`?** Compare to a manual workflow (generate a cert, create a Secret) — what would have been faster manually? When does the operator's value really show up? (Hint: cert rotation.)

## Hands-on Lab Part 2 — observe the rotation loop

```bash
# Force an early renewal — change the Certificate's spec to a shorter duration
oc patch certificate my-first-cert --type='merge' -p='{"spec":{"duration":"1h","renewBefore":"30m"}}'

# Watch the operator log + the Secret get rotated
oc get certificate my-first-cert -w &
# In another terminal:
watch -n 5 'oc get secret my-first-cert-tls -o jsonpath="{.metadata.creationTimestamp} cert={.data.tls\.crt}" | cut -c-100'
```

Eventually the Secret's `tls.crt` changes — that's the operator detecting `renewBefore` is satisfied and reissuing.

## Troubleshooting Exercise — break the operator's RBAC

This is the operator-side equivalent of yesterday's RBAC lab. Bring down the operator's permission to write Secrets, observe what happens.

```bash
# Identify the operator's ServiceAccount + its ClusterRole
oc -n cert-manager get sa
oc -n cert-manager get clusterrolebindings | grep cert-manager-controller
oc get clusterrole cert-manager-controller-certificates -o yaml | head -40

# Remove `update` and `patch` on Secrets from the ClusterRole
# (do this on a dev cluster ONLY — cluster-wide RBAC change)
oc get clusterrole cert-manager-controller-certificates -o yaml > /tmp/cm-role-backup.yaml
oc patch clusterrole cert-manager-controller-certificates --type='json' \
  -p='[{"op":"replace","path":"/rules/2/verbs","value":["get","list","watch","create","delete"]}]'

# Now try to renew a cert; what happens?
oc delete certificate my-first-cert
sleep 2
oc apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: Certificate
metadata: {name: my-first-cert}
spec:
  secretName: my-first-cert-tls
  duration: 720h
  commonName: my-first-cert.<you>-training.svc
  issuerRef: {name: selfsigned, kind: Issuer}
EOF

# Watch operator logs + Certificate status
oc -n cert-manager logs deployment/cert-manager --tail=50 | grep -i error
oc get certificate my-first-cert -o jsonpath='{.status.conditions}' | python3 -m json.tool

# This is the tracker 2.3 pattern in miniature:
#   operator CAN create the child object but CANNOT update/patch existing ones
#   → status condition reports the failure
#   → engineer reads the condition, identifies the verb, escalates to platform team

# Restore the ClusterRole
oc apply -f /tmp/cm-role-backup.yaml
```

## Deliverable — `deliverables/<you>/week02/tuesday.md`

1. **The reconcile timing** — how long did `oc apply` → `Ready=True` take for the Certificate?
2. **Owner-references trace** — paste the `ownerReferences` block of the Secret, explain in 2 sentences what would happen if you `oc delete certificate my-first-cert` now (the Secret should cascade-delete)
3. **The rotation evidence** — two timestamps showing the Secret was rotated by the operator
4. **The RBAC break** — what specific condition message did the operator log? Tie it back to the tracker 2.3 (CFK operator missing `update`/`patch` on `persistentvolumes`) in 2 sentences — same pattern, different resource.
5. **Two questions** — these become Week 4 Monday's seed, where we see the SAME loop running CFK.

Cleanup:

```bash
oc delete certificate my-first-cert
oc delete issuer selfsigned
oc delete secret my-first-cert-tls --ignore-not-found
# Leave cert-manager Operator installed — Week 4 will use it again.
```
