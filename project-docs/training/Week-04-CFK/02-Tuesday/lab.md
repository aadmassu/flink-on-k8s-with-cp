# Week 4 Tuesday — Lab: Modify a CR + Watch Reconciliation

**Time**: ~4 hours

## Hands-on Lab — three CR modifications, three traces

Continue from Monday's lab — `kafka` + `kraftcontroller` + `schemaregistry` + `connect` already running.

### Change 1 — scale brokers (3 → 4)

```bash
oc patch kafka kafka --type=merge -p '{"spec":{"replicas":4}}'

# In parallel terminals:
oc logs -n confluent-operator deploy/confluent-operator -f | grep -i kafka  # operator's view
oc get pods -l app=kafka -w                                                   # K8s's view
oc get kafka kafka -o jsonpath='{.status}' | python3 -m json.tool             # status
```

Notes for your runbook:
- Time between `oc patch` and operator-logs first reaction
- Time between StatefulSet replica count change and new Pod's `Ready=True`
- What changed in `status.conditions` while the new Pod came up

### Change 2 — image tag update

```bash
# Note the current image
oc get kafka kafka -o jsonpath='{.spec.image.application}'

# Patch to an older tag (no real upgrade — just observe the rolling restart)
oc patch kafka kafka --type=merge -p '{"spec":{"image":{"application":"confluentinc/cp-server:7.7.0"}}}'

# Observe ONE Pod restart at a time — that's the StatefulSet rolling update
oc get pods -l app=kafka -w
```

Verify: brokers restart **one at a time** (StatefulSet default), NOT all together (Deployment behavior).

### Change 3 — break it on purpose

```bash
# Reference a non-existent KRaftController
oc patch kafka kafka --type=merge -p '{"spec":{"dependencies":{"kRaftController":{"clusterRef":{"name":"does-not-exist"}}}}}'

# Status should flip to False with a useful message within ~30s
oc get kafka kafka -o jsonpath='{.status.conditions}' | python3 -m json.tool

# Revert
oc patch kafka kafka --type=merge -p '{"spec":{"dependencies":{"kRaftController":{"clusterRef":{"name":"kraftcontroller"}}}}}'
```

Verify the operator picked up the revert without restarting the broker Pods (no spec change → no rollout).

## Troubleshooting Exercise — read the conditions, then the logs

A teammate says "my Kafka cluster isn't healthy." You have nothing else.

Order of investigation:
1. `oc get kafka kafka -o jsonpath='{.status.conditions}' | python3 -m json.tool` — read `cluster-ready` message
2. `oc get pods -l app=kafka` — any Pending / CrashLoopBackOff / Init?
3. If 2 = yes → `oc describe pod <name>` and `oc logs <name>`
4. If 2 = no but 1 = False → check operator logs in `confluent-operator`
5. If everything looks healthy → ask which broker.id has the symptom; that's StatefulSet ordinal info

Document the order in your runbook.

## Deliverable — `deliverables/<you>/week04/tuesday.md`

1. **Three reconcile traces** — for Change 1, 2, 3, with timestamps and operator-log excerpts
2. **status.conditions before + after** Change 3 — both states
3. **The investigation order** — your top-down checklist for "CFK Kafka unhealthy"
4. **Cleanup** — `kafka` back to 3 brokers, original image, original dependency

Keep the CRs for Wednesday's networking lab.
