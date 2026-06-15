# Friday — CFK Rolling Upgrade (break-things day)

**Time**: ~90 min
**Diagram**: [`44-cfk-rolling-upgrade.drawio`](44-cfk-rolling-upgrade.drawio)

## Learning objective

> **What goes wrong during a CFK rolling upgrade**, and how do PDBs, partition leadership, and the operator combine to keep the cluster available?

## Architecture Discussion (~30 min)

A CFK upgrade is "just" a StatefulSet image bump. The interesting part is what happens during the rollout.

### The default sequence

1. You patch `spec.image.application: confluentinc/cp-server:NEW`
2. Operator updates StatefulSet
3. K8s starts rolling broker-N → broker-N-1 → ... → broker-0
4. Each broker: terminated → new Pod with new image → rejoins cluster → next one starts

### What can go wrong

- **No PDB → all brokers restart at once if drain pushes them** — partition leaderships have no home
- **PDB too permissive (`maxUnavailable: 2` of 3)** — same result, just slower
- **Cluster-link replication lag** — if a broker holds active link partitions and gets killed while still catching up, that link is stuck until ISR rebuilds
- **PV stuck Terminating** — Pod can't rejoin because new Pod can't bind PVC
- **TLS / OAuth init container fails on new image** — new image requires a config the old Secret didn't have
- **Image pull from Artifactory fails** — version typo, registry pull-secret expired

### How the operator coordinates

The CFK operator's `cluster-update` status condition tells you the current upgrade state:
- `restart-required` — operator knows a restart is needed
- `in-progress` — Pods are being replaced
- `completed` — all replicas on the new image

But the operator doesn't actively gate the rollout — K8s does that via the PodDisruptionBudget. The operator just observes.

### PDB in production

For Kafka brokers the platform uses:

```yaml
spec:
  podManagementPolicy: Parallel  # NOT for upgrades; for initial bring-up
  # Operator emits a PDB:
  # apiVersion: policy/v1
  # kind: PodDisruptionBudget
  # spec:
  #   maxUnavailable: 1
  #   selector: matchLabels: { app: kafka }
```

`maxUnavailable: 1` means K8s won't evict broker-N until broker-N+1 is back. This is the safety net.

### Failure recovery

If the rollout stalls:

```bash
oc get statefulset kafka -o jsonpath='{.status}' | python3 -m json.tool
oc get pods -l app=kafka
oc get events --sort-by=.lastTimestamp | tail -20
```

The action depends on the symptom — see the lab.

## Break-Things Lab Preview (~15 min)

Today's lab DELIBERATELY breaks the cluster mid-upgrade. Confirm with the instructor before starting. The four scenarios:

1. **Bad image tag** — operator updates StatefulSet to a tag that doesn't exist
2. **PDB too tight + planned worker drain** — drain blocks because PDB is violated
3. **Cert mismatch on new image** — new image expects a key the old Secret doesn't have
4. **PVC reattach failure** — kill a PVC mid-rotation

For each you'll observe the symptom, diagnose, and recover.

## Failure Scenarios — what each looks like

| Scenario | First symptom | Recovery |
|---|---|---|
| Bad image tag | New broker Pod stuck `ImagePullBackOff` | Patch CR back to the previous tag |
| Tight PDB during drain | drain command hangs | bump PDB or unblock drain |
| Cert mismatch | new broker Pod CrashLoopBackOff with TLS error | revert image OR update Secret |
| PVC reattach | new Pod stuck Pending — `pod has unbound immediate PersistentVolumeClaims` | restore PVC or re-bind PV |

## Q&A

1. If `maxUnavailable: 1` and a worker node fails (taking 1 broker with it) WHILE the operator is mid-upgrade restarting a different broker, what happens?
2. Why is `podManagementPolicy: Parallel` safe for initial creation but dangerous for upgrade?
3. What's the operator's role during a rollout — observer or coordinator?
4. How would you recover if all 3 brokers ended up on a broken image at once?


## Added Enhancement — Production Readiness Review

Checklist:

- Storage validated
- TLS validated
- External access validated
- Monitoring validated
- Backup strategy reviewed

Capstone Exercise:

Deploy Kafka using CFK and perform a rolling upgrade while maintaining service availability.
