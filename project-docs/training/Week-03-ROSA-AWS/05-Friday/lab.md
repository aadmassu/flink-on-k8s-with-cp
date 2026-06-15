# Week 3 Friday — Lab: Upgrade Dry-Run + PDB Hardening

**Time**: ~3 hours

## Hands-on Lab — read the cluster's upgrade state

```bash
# 1. Current version + available updates
oc adm upgrade

# 2. The full ClusterVersion CR — channels, history, conditional updates
oc get clusterversion version -o yaml | sed -n '/^spec:/,/^status:/p'
oc get clusterversion version -o yaml | sed -n '/^status:/,/conditionalUpdates/p'

# 3. MachineConfigPools — these drive the worker rollout
oc get mcp
oc get mcp worker -o jsonpath='{.spec.maxUnavailable}{"\n"}'
oc get mcp worker -o jsonpath='{.status.readyMachineCount} / {.status.machineCount}{"\n"}'

# 4. Recent upgrades
oc get clusterversion version -o jsonpath='{range .status.history[*]}{.completionTime} {.state} {.version}{"\n"}{end}' | head -10
```

## Hands-on Lab Part 2 — add a PodDisruptionBudget to your training workload

PDB tells the cluster "you may evict at most N of these Pods at a time." Without one, drain can be aggressive and break replication-sensitive workloads.

```bash
# Deploy a 3-replica nginx
oc create deployment nginx --image=nginx:1.27 --replicas=3

# Add a PDB so at MOST 1 Pod can be unavailable
cat <<EOF | oc apply -f -
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: nginx-pdb
spec:
  maxUnavailable: 1
  selector:
    matchLabels: {app: nginx}
EOF

# Simulate a drain — pick a node where nginx Pods live
NODE=$(oc get pod -l app=nginx -o jsonpath='{.items[0].spec.nodeName}')
oc adm drain $NODE --ignore-daemonsets --delete-emptydir-data --dry-run=client

# Watch what eviction looks like (dry-run only — don't actually drain a production node)
oc get pdb nginx-pdb -o yaml | grep -A5 status
```

In your runbook, note: **what would happen if the PDB was `maxUnavailable: 0`?** (Hint: cluster admin can't drain ANY node holding an nginx Pod — upgrade gets blocked.)

## Troubleshooting Exercise — predict the blast radius

Without running anything destructive, for each of the following, predict what happens during a routine worker-node upgrade:

1. A Deployment with replicas=1 (no PDB)
2. A StatefulSet with replicas=3 and `updateStrategy: RollingUpdate`
3. A CFK Kafka cluster with replicas=3 brokers + a cluster-link mirror flowing in
4. A Flink job with checkpointing to S3
5. A `cert-manager` Operator Pod

Your answer for each: which Pod(s) move, what's the customer-visible impact, what would have prevented downtime.

## Deliverable — `deliverables/<you>/week03/friday.md`

1. **Cluster upgrade state** — current version, available updates, last 3 history entries
2. **PDB inventory** — what PDBs already exist on the cluster (`oc get pdb -A`)
3. **Your nginx-pdb evidence** — the dry-run drain output showing the PDB blocking eviction
4. **The 5 blast-radius predictions** — your answers for each workload type
5. **Updated personal troubleshooting checklist v3** — append the upgrade-side patterns from today
6. Two questions

**End-of-week deliverable reminder**: `week-03-runbook.md` per the Week 3 README — your one-page ROSA inventory + IRSA evidence + connectivity ladder + this upgrade plan.

Cleanup:

```bash
oc delete pdb nginx-pdb
oc delete deployment nginx
```
