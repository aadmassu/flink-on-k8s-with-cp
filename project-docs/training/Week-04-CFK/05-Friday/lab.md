# Week 4 Friday — Lab: Break the Upgrade

**Time**: ~4 hours
**SAFETY**: confirm with the instructor before running these. Only do this in the training project, never against `dah-flink-*`.

## Hands-on Lab — four scenarios, four recoveries

Each scenario:
1. Cause the failure
2. Observe it via `oc get` / `oc describe` / logs
3. Recover
4. Capture the exact diagnostic command that named the cause

### Scenario 1 — bad image tag

```bash
# Cause
oc patch kafka kafka --type=merge -p \
  '{"spec":{"image":{"application":"confluentinc/cp-server:9.9.9-does-not-exist"}}}'

# Observe — should hit ImagePullBackOff within 30s
oc get pods -l app=kafka
oc describe pod kafka-2 | grep -A 5 'Events:'

# Recover
oc patch kafka kafka --type=merge -p \
  '{"spec":{"image":{"application":"confluentinc/cp-server:7.7.0"}}}'
```

### Scenario 2 — tight PDB + worker drain

```bash
# Confirm there's a PDB
oc get pdb -l app=kafka

# Try draining the node hosting kafka-1
NODE=$(oc get pod kafka-1 -o jsonpath='{.spec.nodeName}')
oc adm drain $NODE --delete-emptydir-data --ignore-daemonsets

# Should hang on the broker Pod — read the message
# Recover: ctrl-C the drain. The cluster is fine.
oc uncordon $NODE
```

In your runbook capture: **what's the error message when PDB blocks drain?**

### Scenario 3 — cert mismatch

```bash
SECRET=$(oc get kafka kafka -o jsonpath='{.spec.tls.secretRef.name}')

# Backup
oc get secret $SECRET -o yaml > /tmp/secret-backup.yaml

# Replace tls.key with garbage
oc patch secret $SECRET -p '{"data":{"tls.key":"Z2FyYmFnZQ=="}}'

# Force a rollout
oc rollout restart statefulset/kafka

# Observe — CrashLoopBackOff with TLS error
oc get pods -l app=kafka -w
oc logs kafka-2 -c kafka --tail=50 | grep -i -E 'tls|ssl|keystore'

# Recover
oc apply -f /tmp/secret-backup.yaml
oc rollout restart statefulset/kafka
```

### Scenario 4 — PVC re-attach

```bash
# Identify a broker PVC
oc get pvc -l app=kafka

# Delete kafka-2's Pod
oc delete pod kafka-2

# While the new Pod is Pending, delete the PVC (PV will detach)
oc delete pvc data-kafka-2 --wait=false

# Observe — new Pod stuck Pending
oc get pods -l app=kafka
oc describe pod kafka-2 | grep -A 5 'Events:'

# Recover: re-create the PVC by deleting the Pod again (StatefulSet recreates PVC)
oc delete pod kafka-2
```

This one is risky — kafka-2's broker.id loses its data and resyncs from the other replicas. Make sure your topic has replication-factor 3 BEFORE running this.

## Troubleshooting Exercise — instructor injects ONE failure secretly

The instructor will pick one of the four scenarios (or a variation) and run it without telling you which. Your job:

1. From a clean state, find the symptom
2. Diagnose without running every command — start at status conditions, then narrow
3. Recover
4. Write down the exact path your eyes took to get to the cause

Time yourself.

## Deliverable — `deliverables/<you>/week04/friday.md`

1. **Four scenarios documented** — symptom + diagnostic command + recovery command for each
2. **The instructor's blind scenario** — what was broken, how long it took you to find, the diagnostic path
3. **Your personal "CFK broker won't come up" checklist** — top-of-funnel ordered list
4. **One non-obvious gotcha** — something you didn't know before this week
