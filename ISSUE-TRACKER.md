# Issue Tracker

Cross-team action items for the CFK + CMF + Flink rollout on FCB OpenShift. Each entry names the **scope** (which env/component), the **owner**, and the **current state**.

This is the action-item view. For technical root-cause writeups on closed issues, see [`runbook/LESSONS_LEARNED.md`](runbook/LESSONS_LEARNED.md). For per-env deploy gates, see [`runbook/CHECKLIST.md`](runbook/CHECKLIST.md). For the original DEV-rollout retrospective, see [`LESSONS-LEARNED.md`](LESSONS-LEARNED.md).

**Status legend:**
- `OPEN` — work outstanding
- `BLOCKER` — currently blocking forward progress on a named workstream
- `CLOSED` — resolved; kept for reference

*Last updated: 2026-06-05.*

---

## TRACK 1: Secret management — ESO + CyberArk Integration

**Scope:** All envs. **Owner:** FCB Security (CyberArk safe admins), Tushar (safe contents), Container team (cluster-side ESO).

DEV is fully integrated and CMF is running against CyberArk-sourced secrets — no longer a FLINK+CFK blocker. Remaining items are housekeeping plus the corresponding request for upper envs.

| ID | Status | Owner | Issue | Notes | RITM |
|---|---|---|---|---|---|
| 1.1 | CLOSED | Ayu | `dev-confluent-license` secret wasn't syncing to OpenShift | Resolved. Root cause was format mismatch — CMF wants the raw JWT, CFK wants `license=<JWT>` properties shape (`runbook/LESSONS_LEARNED.md` C1) | — |
| 1.2 | CLOSED | FCB Security | `dev-artifactory-svc-user-password` and `dev-db-user-password` missing from CyberArk Key safe | Added | — |
| 1.3 | CLOSED | Tushar | Cleanup — remove duplicate keys from the Linux safe | Duplicates removed | — |
| 1.4 | OPEN | Tushar | Add per-env CMF secrets to CyberArk for QA + UAT + PRD (DR to follow as we promote). Three secrets per env:<br>• `qa-cmf-encryption-key`, `qa-cmf-sql-server-user-password`, `qa-confluent-license`<br>• `uat-cmf-encryption-key`, `uat-cmf-sql-server-user-password`, `uat-confluent-license`<br>• `prd-cmf-encryption-key`, `prd-cmf-sql-server-user-password`, `prd-confluent-license` | **Blocks QA + UAT + PRD enablement.** Awaiting CyberArk fulfillment of the RITMs | QA: RITM1085071<br>UAT: RITM1085692<br>PRD: RITM1085693 |
| 1.5 | OPEN | Tushar | Delete stale `dev_confluent_key` from the `11547_D_KEY_FP` safe | Specific stale key to remove (not a duplicate — an obsolete entry from earlier iterations) | Yet to be created |
| 1.6 | OPEN | Tushar | Delete stale `artifactory-svc-user-password` from the `11547_D_UNIX_FP` safe | Specific stale key to remove from the Unix safe | Yet to be created |

## TRACK 2: CFK on OpenShift

**Scope:** All envs. **Owner:** Container team.

DEV has been unblocked through Gatekeeper policy relaxations and operator-side ClusterRole adjustments. The same fixes need to be applied to QA / UAT / PRD / DR clusters as we promote.

| ID | Status | Owner | Issue | Notes | RITM |
|---|---|---|---|---|---|
| 2.1 | CLOSED (DEV) | Container team | Gatekeeper `[ceph-storage]` constraint denying CFK StatefulSets that emit `storageClassName: dummy` on the volumeClaimTemplate | Rick updated DEV Cluster Admission Policy. See `runbook/LESSONS_LEARNED.md` A11 for root cause | RITM1076878 |
| 2.2 | OPEN | Container team | Apply the same admission policy update from 2.1 to the QA, UAT, and PRD clusters | Repeats Rick's DEV change on the upper-env clusters. DR scope to be discussed separately | Yet to be created |
| 2.3 | OPEN | Container team | CFK operator ServiceAccount (`confluent-operator/confluent`) lacks `update` + `patch` on cluster-scoped `persistentvolumes`. **Requested ClusterRole rule:**<br>`- apiGroups: [""]`<br>`  resources: ["persistentvolumes"]`<br>`  verbs: ["get", "list", "watch", "update", "patch"]` | Without this, kraft and any PVC-backed CR report `cluster-ready=False` even when the pod is healthy — and Kafka never reconciles because it waits on kraft. `get`/`list`/`watch` are typically already present; `update` and `patch` are the new verbs the CFK 3.1.2 operator needs. See `runbook/LESSONS_LEARNED.md` A10 | RITM1093307 |
| 2.4 | OPEN | Container team | Apply the same `confluent-operator` service account PV role update from 2.3 into QA, UAT, and PRD clusters | Repeats 2.3's ClusterRole patch on the upper-env clusters. Without it in place ahead of CFK install, the `cluster-ready=False` symptom from DEV will repeat verbatim. DR scope to be discussed separately | Yet to be created |
| 2.5 | OPEN | Container team | DEV namespace ResourceQuota increase | Current 2 CPU / 8 Gi only fits ~4 of the 6 CFK pods. Every pod claims ~500m via the operator-injected init container (`runbook/LESSONS_LEARNED.md` A3). Container team to raise to ≥6 CPU / ≥24 Gi so we can bring Connect + ControlCenter back from `replicas: 0`. Per-env quota + capacity estimates are documented in the [FCB Kafka Application Infrastructure Workbook](https://firstcitizens.sharepoint.com/:x:/r/sites/PlatformIntegrationprojectassistance-11547-DAH-FCBKafka/_layouts/15/Doc.aspx?sourcedoc=%7B71805FFD-E8D3-42A2-8A12-1546EEC055CD%7D&file=11547_DAH_FCB_Kafka-Application_Infrastructure_Workbook.xlsx&action=default&mobileredirect=true) (FCB SharePoint — `11547_DAH_FCB_Kafka-Application_Infrastructure_Workbook.xlsx`) | — |
| 2.6 | CLOSED | Container team | CFK Custom Resources weren't visible on the OpenShift console for the upper-env cluster | Fixed by Container team. Historical reference; was specific to the cluster's console view, not a CFK or manifest issue | — |

## TRACK 3: Flink on OpenShift

**Scope:** All Flink-stack rollout issues — Flink Kubernetes Operator behavior, CMF Helm install, Flink job deployment. **Owner:** Asmerom (engineering side), Ayu (manifests / chart values), Container team (operator / RBAC / Kyverno side).

Covers both the DEV operator label-propagation blocker and the upper-env CMF rollout (chart-suppression overrides + the `fcb-security` RBAC pre-creation gate).

| ID | Status | Owner | Issue | Notes | RITM |
|---|---|---|---|---|---|
| 3.1 | BLOCKER | Container team | Enable debug logging on the Flink Kubernetes Operator to diagnose why FCB common-metadata labels aren't propagating to the Deployment that the operator creates | **Blocking Asmerom's job-development work.** FCB Gatekeeper `[required-workload-labels]` denies the Deployment because the operator doesn't expose a Deployment-level label override — Pod labels propagate fine, Deployment labels don't. Likely needs a Kyverno mutation policy added at the cluster level (or an upstream operator fix). See `runbook/LESSONS_LEARNED.md` G1 | — |
| 3.2 | OPEN | Ayu | UAT CMF Helm install hit 5 admission errors at once (`serviceaccounts/roles/rolebindings is forbidden`, `[ceph-storage]` PVC denial, `[required-workload-labels]`) | Chart-suppression overrides added to `apps/confluent-cmf/uat/values.yaml` + `apps/confluent-cmf/prd/values.yaml` to match the dev/qa pattern. See `LESSONS-LEARNED.md` B4 | — |
| 3.3 | OPEN | Container team | `fcb-security` ArgoCD chart hasn't yet applied the per-env SA / Role / RoleBinding to `dah-flink-uat` | Pending Container team change-management approval. Required before the next CMF install attempt can succeed — the chart-suppression overrides in 3.2 mean the install will admit cleanly, but the CMF pod will fail to schedule with `serviceaccount "flink-operator" not found` until this lands. Pre-flight check: `oc -n dah-flink-uat get sa flink-operator cmf-env-sa-dah-flink-uat` | — |

---

## How to update this file

When you open a new cross-team item, add it to the appropriate track with a fresh ID (next sequential under that track's prefix). When an item closes, **don't delete it** — flip its status to `CLOSED` and leave the notes column intact so future readers can see what was resolved and how. Keep the "Last updated" line at the top of the file in step with reality.

If you find yourself reaching for a `runbook/LESSONS_LEARNED.md` entry to explain an item here, link to it by section letter (e.g. "see A10"). This file is the *action* view; the runbook is the *root-cause* view. Keep them complementary, not duplicative.
