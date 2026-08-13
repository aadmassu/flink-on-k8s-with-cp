# Friday — ResourceQuota + Limits (break-things day)

**Time**: ~60 min discussion + the rest is the lab
**Diagram**: [`24-quota-failures.drawio`](24-quota-failures.drawio) — Pod → ResourceQuota → LimitRange → admission decision

## Learning objective

> **Why did DEV's CFK install fail for two weeks?** Because the namespace ResourceQuota was 10 GB storage when the CFK stack needed ~24 Gi minimum. Engineers need to recognize the exhaustion symptom in under 30 seconds.

This is the tracker 2.5 story made into a hands-on lab. Engineers WILL see this pattern in upper-env promotion.

## Architecture Discussion (~30 min)

OpenShift namespaces enforce TWO related-but-distinct admission policies:

### ResourceQuota — namespace-level CAPS

A `ResourceQuota` object caps the SUM of requests/limits across all Pods in the namespace. Example:

```yaml
spec:
  hard:
    requests.cpu:    4
    requests.memory: 8Gi
    limits.cpu:      8
    limits.memory:   16Gi
    requests.storage: 100Gi
    persistentvolumeclaims: 10
    pods: 50
```

This caps TOTAL consumption across the whole namespace. New Pods that would push the sum over the cap are rejected at admission with `exceeded quota: ...`.

The CFK 3.1.x story (runbook A3): the operator-injected init container has a ~500m CPU floor by default that becomes the pod-effective CPU request. With 6 CFK Pods needing ~500m each, that's 3 CPU minimum from CPU quota alone — and the broker's main container needs its OWN cpu request on top. A 2-CPU quota fits ~4 Pods. The DEV cluster was capped that way and CFK refused to install for weeks.

### LimitRange — per-object DEFAULTS + MIN/MAX

A `LimitRange` does two things:

1. **Defaults**: if a Pod doesn't specify `resources.requests.cpu`, the LimitRange supplies one. Critical because: without a Pod request, ResourceQuota can't enforce.
2. **Min/Max**: caps the per-Pod range. "No single Pod can request more than 4 CPU."

LimitRange + ResourceQuota work together. LimitRange ensures every Pod has a request set; ResourceQuota caps the SUM.

### Three admission outcomes

When a Pod is submitted:

1. **No quota issue** — accepted, scheduled
2. **Defaults supplied, quota OK** — LimitRange filled in the gap; ResourceQuota counted it; under cap; accepted
3. **Quota exceeded** — REJECTED at admission with `exceeded quota: <quota-name>, requested: cpu=500m, used: cpu=1800m, limited: cpu=2`

Outcome 3 is the symptom engineers must recognize instantly.

### Why this matters across the lifecycle

- **CFK install fails**: kraftcontroller Pod can't admit because PVC quota exceeded
- **Day-2 Pod restart loops**: a Pod terminates + recreates rapidly, each recreation counted; if quota fills, can't recreate
- **Upper-env promotion**: QA / UAT / PRD each need their OWN quota raise; the DEV story repeats (tracker 2.6)
- **Storage quota differs from CPU/memory**: a Pod can fit CPU but its PVC can't be provisioned because `requests.storage` is exhausted. Different error message, same root cause.

## Diagram Walkthrough (~30 min) — trace one Pod through admission

Walk the diagram top-down:

```
oc apply -f pod.yaml
   │
   ▼
apiserver receives the create request
   │
   ▼
Admission controller chain runs (in order):
   1. Defaults plugin — does this Pod set requests.cpu? If not, LimitRange supplies a default.
   2. ResourceQuota plugin — would this Pod push the namespace's sum over the cap?
      → If yes: REJECT with `exceeded quota` error
      → If no: pass, increment the quota's `used` counter
   3. Gatekeeper policies (label requirements, SCC, etc.)
   4. (Pod admitted; persisted to etcd; scheduler picks it up)
```

Stop at each step: *what does the engineer see if it fails HERE?*

## Failure Scenarios — the four flavors

| Symptom | Underlying quota dimension |
|---|---|
| `pods "xyz" is forbidden: exceeded quota: ..., requested: requests.cpu=500m, used: requests.cpu=1800m, limited: requests.cpu=2` | CPU |
| `persistentvolumeclaims "data-kafka-0" is forbidden: exceeded quota: ..., requested: persistentvolumeclaims=1, used: persistentvolumeclaims=10, limited: persistentvolumeclaims=10` | PVC count |
| `persistentvolumeclaims "data-kafka-0" is forbidden: exceeded quota: ..., requested: requests.storage=1Ti, used: requests.storage=99Gi, limited: requests.storage=100Gi` | PVC storage |
| StatefulSet stuck creating pod-1; pod-0 exists but pod-1 admission fails | (the StatefulSet controller surfaces only the count failure; check `oc describe statefulset` Events for the actual quota message) |

## Q&A

1. What's the difference between `resources.requests` and `resources.limits`? Which one does ResourceQuota cap?
2. If a Pod doesn't specify `resources.requests`, what value does ResourceQuota count?
3. Why does the platform enforce LimitRange alongside ResourceQuota? What breaks if only ResourceQuota is set?
4. Why does CFK's operator init container CPU floor matter to ResourceQuota? (Reference: runbook A3)
5. If a Pod is admitted and runs, can its actual usage exceed the quota? (Trick: yes, the quota is a request-side cap. Limits are the runtime ceiling.)

## Common misconceptions

- **"Quota is enforced at runtime"** — no, at ADMISSION. Once admitted, a Pod's burst usage isn't quota-counted.
- **"If I have 1Ti free disk, I can create a 1Ti PVC"** — only if the namespace's `requests.storage` quota allows it. The cluster might have terabytes free; quota is per-namespace.
- **"`oc get quota` shows what's REMAINING"** — partially. It shows `used / hard`. Subtract for remaining.
- **"Quota exhaustion only matters at install"** — wrong. Pod restarts, scale-up, Day-2 rotation all hit it.


## Added Enhancement — CFK Capacity Planning

Use actual Kafka/CFK resource requests and calculate:
- CPU consumption
- Memory consumption
- PVC requirements

This prepares engineers for namespace sizing discussions.
