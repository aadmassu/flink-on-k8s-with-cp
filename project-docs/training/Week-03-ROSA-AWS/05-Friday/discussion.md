# Friday — Cluster Upgrades + Scaling (controlled, not break-things)

**Time**: ~60 min discussion + the rest is the lab
**Diagram**: [`34-rosa-upgrade.drawio`](34-rosa-upgrade.drawio) — ROSA control plane → MachineConfigPool → MachineSet → worker rolling replacement

## Learning objective

> **The only thing scarier than not upgrading is upgrading wrong.** Understanding the upgrade machinery — what runs, in what order, with what blast radius — turns the upgrade from a panic event into a routine.

This Friday is intentionally NOT break-things because ROSA upgrades on a real cluster are slow + somewhat irreversible. Engineers practice the dry-run + observe a real upgrade if one is scheduled.

## Architecture Discussion (~40 min)

ROSA upgrades happen in two waves:

### Wave 1 — control plane upgrade

- **ROSA HCP**: Red Hat upgrades the hosted control plane in their account. From the engineer's view, the kube-apiserver / etcd / scheduler / controllers swap in place. Brief API blips during the upgrade. Worker nodes are untouched.
- **ROSA Classic**: Red Hat upgrades the control plane EC2 instances rolling one at a time. Slightly longer.

Either way: workloads don't restart. Engineer-side: no impact unless they're using a deprecated API.

### Wave 2 — worker node upgrade

This is where engineers feel it. Driven by the **MachineConfigOperator** (MCO) + **MachineConfigPool** (MCP) abstractions:

- A **MachineConfigPool** groups worker nodes (default: one pool for all workers + one for masters). Has a `maxUnavailable` setting (typically 1).
- The MCO renders a new MachineConfig with the new OS image + kubelet version
- MCO cordons + drains one node at a time, replaces it (with a new EC2 instance), waits for it to rejoin Ready, moves to the next
- Pods on the drained node are evicted; their controllers reschedule them elsewhere

Workloads survive the upgrade IF:
- They have `replicas > 1` and a PodDisruptionBudget allows eviction
- They tolerate Pod replacement (no local-disk state) OR have PVCs that move with the Pod
- StatefulSet Pods: each replaced one at a time per the StatefulSet's own update strategy

CFK specifically: brokers WILL be evicted during worker upgrades. Each broker's StatefulSet handles the orderly restart. **Cluster-link / replication must catch up before the next broker is touched** — otherwise data loss.

### The dry-run

```bash
oc adm upgrade --to=4.16.10                 # would-upgrade message but no action
oc adm upgrade                              # shows current channel + available versions
oc get clusterversion -o yaml | sed -n '/^status:/,/conditionalUpdates/p'
```

The `availableUpdates` section lists upgrade candidates. The `desiredUpdate` field is what's been requested; `history` shows past upgrades.

### Scaling

Worker pool scaling is via MachineSet:

```bash
oc get machinesets -A
oc scale machineset -n openshift-machine-api <name> --replicas=4
```

ROSA may have **cluster-autoscaler** enabled — if so, the MachineSet's `replicas` field is managed by the autoscaler, not by you. Look for `cluster-autoscaler-operator` Pods.

## Diagram Walkthrough (~20 min)

Walk the diagram: upgrade kicks off → control plane done → MCO computes the new rendered config → for each MCP, drain one node + replace → eventually all nodes match the desired config.

Stop at each step and ask: *what workload behavior would be disrupted here? What can the engineer do beforehand to harden against it?*

## Failure Scenarios

| Symptom | Likely cause |
|---|---|
| Upgrade stuck after control plane done; no worker progress | MCO can't proceed — usually a PDB blocking eviction OR a Pod not Ready after rescheduling |
| Single Pod stuck terminating during drain | Finalizer holding (Week 4 will cover this for CFK Secrets) OR the workload's terminationGracePeriod is too long |
| Cluster operator goes Degraded during upgrade | New version's CO didn't come up — usually self-resolves; if not, RH ticket |
| Workload Pod CrashLoopBackOff after upgrade | API deprecation — workload using an API that was removed in the new K8s minor. `oc adm upgrade --pre-upgrade-checks` warned about this BEFORE upgrade |
| CFK broker Pod replaced but `cluster-ready=False` | The PV didn't follow; StatefulSet identity broken — STOP the upgrade, investigate |

## Q&A

1. What's a MachineConfigPool vs a MachineSet vs a MachineConfig?
2. If `maxUnavailable=1` in the worker MCP, how long does a 30-worker cluster's upgrade take?
3. What's a PodDisruptionBudget and why does it matter for upgrades?
4. Why is CFK's StatefulSet update strategy `OnDelete` (manual) instead of `RollingUpdate`?
5. Who initiates a ROSA upgrade — the engineer, platform, or Red Hat?


## Added Enhancement — Real Incident Workshop

Scenario:
- Okta endpoint unreachable
- Security group change blocks traffic
- OAuth authentication failures

Students must identify root cause and remediation path.
