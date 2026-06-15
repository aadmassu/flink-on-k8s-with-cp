# Friday — Troubleshooting Workflow (break-things day)

**Time**: ~60 min discussion in the morning, then the rest of the day is the lab
**Diagram**: [`12-troubleshooting-tree.drawio`](12-troubleshooting-tree.drawio) — the decision tree the team will memorize

## Learning objective

> **When an app on OpenShift is broken, where do you look first, second, third?** Build a personal troubleshooting checklist that becomes muscle memory by the end of the bootcamp.

This Friday is the most important day of Week 1. Every Friday for the next 5 weeks is a break-things day. The skill compounds.

## Architecture Discussion (~30 min) — the decision tree

Walk through the diagram. The tree has four levels, in the order an engineer should check:

### Level 1: Is the Pod even there?

- `oc get pod <name>` — does it exist?
- `oc get pods -l <label>` — if a controller (Deployment/StatefulSet) should have created Pods, did it?
- `oc describe deployment <name>` — Events at the bottom show why the controller couldn't create Pods (quota, admission policy, ServiceAccount missing)

### Level 2: Is the Pod scheduled to a node?

- `oc get pod <name> -o wide` — has the `NODE` column? If empty, scheduler hasn't bound it
- `oc describe pod <name>` — Events: `0/N nodes are available` means scheduler tried and gave up
- Common causes: no node has the requested resources, taint mismatch, PVC unbound (Pod sits Pending until storage is ready)

### Level 3: Is the container running on that node?

- `oc describe pod <name>` — Events from kubelet: image pull, container start, probe failures
- `oc get pod <name> -o jsonpath='{.status.containerStatuses[*].state}'` — what state is the container in?
- Common states: `ImagePullBackOff`, `CrashLoopBackOff`, `OOMKilled`, `Error`

### Level 4: Is the application inside the container actually working?

- `oc logs <name>` — application logs
- `oc logs <name> --previous` — the previous container's logs (after a crash)
- `oc exec <name> -- <cmd>` — get inside the container, check connectivity, files, etc.
- `oc port-forward <name> <local-port>:<container-port>` — connect from your laptop to a single Pod, bypassing Services + Routes
- Common causes: bad config, missing env var, can't reach a dependency, application bug

### Auxiliary checks at every level

- `oc get events --sort-by=.lastTimestamp | tail -50` — cluster-wide recent events
- `oc get pod <name> -o yaml | grep -A5 conditions` — Pod's own self-reported conditions
- `oc top pod <name>` — current CPU + memory usage
- `oc get all -l <label>` — everything related to one app at once

## The "where did I start" rule

Most engineers waste hours by:
- Starting at Level 4 (reading logs) before checking Level 1 (does the Pod exist)
- Reading the wrong logs (current vs previous; the right container in a multi-container Pod)
- Believing `oc describe` shows them everything (it shows recent Events; old events expire after ~1h)
- Confusing Pod conditions with container conditions (a Pod can be `Ready=True` while its container restarted 50 times)

The decision tree forces top-down: do `get` first, then `describe`, then `logs`, then `exec`.

## Diagram Walkthrough (~30 min) — apply the tree to four common failures

Walk one trace per failure:

**Failure A: image pull**
1. `oc get pod` → Pod exists, status: `ImagePullBackOff`
2. `oc describe pod` → Events: `Failed to pull image "...": Forbidden 401`
3. Cause: pull secret missing or wrong; image name typo
4. Fix: `oc set image ...` with the right name, OR `oc create secret docker-registry`

**Failure B: schedule failure**
1. `oc get pod` → Pod exists, status: `Pending`, NODE: empty
2. `oc describe pod` → Events: `0/3 nodes are available: 3 Insufficient memory`
3. Cause: requested memory > what any node has free
4. Fix: lower the request, or scale the cluster

**Failure C: app crash**
1. `oc get pod` → Pod exists, status: `CrashLoopBackOff`, RESTARTS: 5
2. `oc logs <name>` → empty or only startup
3. `oc logs <name> --previous` → reveals the actual error
4. Cause: app-side
5. Fix: depends on the log

**Failure D: route returns 503**
1. User reports 503 from `curl https://myapp.apps...`
2. `oc get pod` → Pod exists, Ready
3. `oc get endpoints <svc>` → empty!
4. Cause: Service selector doesn't match Pod labels (Wednesday's lesson)
5. Fix: `oc patch svc ...`

## Common misconceptions

- **"`oc logs` always shows the error"** — no. If the container died, use `--previous`. If multi-container, specify `-c <container>`.
- **"I should restart the Pod"** — almost never the fix. Investigate first.
- **"`oc describe` is the same as `kubectl describe`"** — basically yes, but `oc` adds Route/Project context.
- **"OpenShift Console is for users; CLI is for admins"** — Console is great for visualization; CLI is faster for triage. Use both.


## Added Enhancement — Network Policy Troubleshooting

Mini discussion:

```text
Pod A -> NetworkPolicy -> Pod B
```

Common future CFK symptoms:
- Connect cannot reach Kafka
- Flink cannot reach Schema Registry
- OAuth/OIDC endpoints unreachable

Validation commands:
```bash
oc get networkpolicy -A
oc describe networkpolicy <name>
```
