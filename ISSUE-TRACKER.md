# Issue Tracker

Cross-team action items for the CFK + CMF + Flink rollout on FCB OpenShift. Each entry names the **scope** (which env/component), the **owner**, and the **current state**.

This is the action-item view. For technical root-cause writeups on closed issues, see [`runbook/LESSONS_LEARNED.md`](runbook/LESSONS_LEARNED.md). For per-env deploy gates, see [`runbook/CHECKLIST.md`](runbook/CHECKLIST.md). For the original DEV-rollout retrospective, see [`LESSONS-LEARNED.md`](LESSONS-LEARNED.md).

**Status legend:**
- `OPEN` — work outstanding (default for any item not yet resolved)
- `BLOCKER` — currently blocking forward progress on a named workstream. BLOCKER implies OPEN; rows show as `OPEN / BLOCKER` to make both states explicit
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
| 1.5 | OPEN | Tushar | Delete stale `dev_confluent_key` from the `11547_D_KEY_FP` safe | Specific stale key to remove (not a duplicate — an obsolete entry from earlier iterations) | RITM1097456 |
| 1.6 | OPEN | Tushar | Delete stale `artifactory-svc-user-password` from the `11547_D_UNIX_FP` safe | Specific stale key to remove from the Unix safe | RITM1097457 |

## TRACK 2: CFK on OpenShift

**Scope:** All envs. **Owner:** Container team.

DEV has been unblocked through Gatekeeper policy relaxations and operator-side ClusterRole adjustments. The same fixes need to be applied to QA / UAT / PRD / DR clusters as we promote.

| ID | Status | Owner | Issue | Notes | RITM |
|---|---|---|---|---|---|
| 2.1 | CLOSED (DEV) | Container team | Gatekeeper `[ceph-storage]` constraint denying CFK StatefulSets that emit `storageClassName: dummy` on the volumeClaimTemplate | Rick updated DEV Cluster Admission Policy. See `runbook/LESSONS_LEARNED.md` A11 for root cause | RITM1076878 |
| 2.2 | OPEN (PRD pending) | Container team | Apply the same admission policy update from 2.1 to the QA, UAT, and PRD clusters | Repeats Rick's DEV change on the upper-env clusters. QA + UAT tickets filed 2026-06-10; PRD ticket still to be created. DR scope to be discussed separately | RITM1101306 (QA), RITM1101307 (UAT), PRD yet to be created |
| 2.3 | OPEN / BLOCKER | Container team | CFK operator ServiceAccount (`confluent-operator/confluent`) lacks `update` + `patch` on cluster-scoped `persistentvolumes`. **Requested ClusterRole rule:**<br>`- apiGroups: [""]`<br>`  resources: ["persistentvolumes"]`<br>`  verbs: ["get", "list", "watch", "update", "patch"]` | Without this, kraft and any PVC-backed CR report `cluster-ready=False` even when the pod is healthy — and Kafka never reconciles because it waits on kraft. `get`/`list`/`watch` are typically already present; `update` and `patch` are the new verbs the CFK 3.1.2 operator needs. See `runbook/LESSONS_LEARNED.md` A10 | RITM1093307 |
| 2.4 | OPEN | Container team | Apply the same `confluent-operator` service account PV role update from 2.3 into QA, UAT, and PRD clusters | Repeats 2.3's ClusterRole patch on the upper-env clusters. Without it in place ahead of CFK install, the `cluster-ready=False` symptom from DEV will repeat verbatim. DR scope to be discussed separately | Yet to be created |
| 2.5 | OPEN | Container team | DEV namespace ResourceQuota increase — **CPU + memory fulfilled; storage raised 10 GB → 100 GB but target is ~1.272 TB (1,272 GB) per lower env** | Partial fulfillment: Container team raised CPU + memory to a level that comfortably fits the full CFK stack alongside the Flink jobs (Connect + ControlCenter can come back from `replicas: 0` when prioritized). Storage quota was raised from 10 GB to 100 GB in the same pass — enough for current smoke-test workloads but **~12× short of the ~1.272 TB target per lower env** documented in the Application Infrastructure Workbook. A follow-up storage-only quota raise is needed; likely a new SNOW request rather than a re-open of RITM1079670 since that ticket has been technically fulfilled. Per-env quota + capacity estimates: [FCB Kafka Application Infrastructure Workbook](https://firstcitizens.sharepoint.com/:x:/r/sites/PlatformIntegrationprojectassistance-11547-DAH-FCBKafka/_layouts/15/Doc.aspx?sourcedoc=%7B71805FFD-E8D3-42A2-8A12-1546EEC055CD%7D&file=11547_DAH_FCB_Kafka-Application_Infrastructure_Workbook.xlsx&action=default&mobileredirect=true) (FCB SharePoint — `11547_DAH_FCB_Kafka-Application_Infrastructure_Workbook.xlsx`). See `runbook/LESSONS_LEARNED.md` A3 for the init-container floor that drove the original CPU/RAM ask | RITM1079670 (fulfilled — follow-up RITM for ~1.272 TB storage still to be created) |
| 2.6 | OPEN | Container team | Apply the same ResourceQuota increase from 2.5 into QA, UAT, and PRD namespaces | Repeats 2.5's quota raise on the upper-env clusters. Per-env target sizes are in the Application Infrastructure Workbook linked from 2.5. DR scope to be discussed separately | Yet to be created |
| 2.7 | CLOSED | Container team | CFK Custom Resources weren't visible on the OpenShift console for the upper-env cluster | Fixed by Container team. Historical reference; was specific to the cluster's console view, not a CFK or manifest issue | — |

## TRACK 3: Flink on OpenShift

**Scope:** All Flink-stack rollout issues — Flink Kubernetes Operator behavior, CMF Helm install, Flink job deployment. **Owner:** Asmerom (engineering side), Ayu (manifests / chart values), Container team (operator / RBAC side).

Covers both the DEV operator label-propagation blocker and the upper-env CMF rollout (chart-suppression overrides + the `fcb-security` RBAC pre-creation gate).

| ID | Status | Owner | Issue | Notes | RITM |
|---|---|---|---|---|---|
| 3.1 | CLOSED | Container team | Enable debug logging on the Flink Kubernetes Operator to diagnose why FCB common-metadata labels aren't propagating to the Deployment that the operator creates | Resolved. Container team added `logger.operator.level = DEBUG` on the Flink Operator's `log4j-operator.properties` (with `append: true` on `defaultConfiguration`); operator pod restarted to pick up the new ConfigMap. Debug logs are now available for diagnosing the underlying label-propagation issue — root-cause analysis (and any follow-up admission-mutation policy or operator fix) remains separate work. See `runbook/LESSONS_LEARNED.md` G1 for the structural background | RITM1080156 |
| 3.2 | OPEN / BLOCKER | Container team | `fcb-security` ArgoCD chart hasn't yet applied the per-env SA / Role / RoleBinding to `dah-flink-uat` | Pending Container team change-management approval. The chart-suppression overrides already in `apps/confluent-cmf/{uat,prd}/values.yaml` (see `LESSONS-LEARNED.md` B4) mean the next install attempt will admit cleanly, but the CMF pod will fail to schedule with `serviceaccount "flink-operator" not found` until this lands. Pre-flight check: `oc -n dah-flink-uat get sa flink-operator cmf-env-sa-dah-flink-uat` | RITM1050600 |
| 3.3 | OPEN | Container team | `fcb-security` ArgoCD chart hasn't yet applied the per-env SA / Role / RoleBinding to `dah-flink-prd` | Repeats 3.2 on the PRD cluster. Pre-flight check before CMF install: `oc -n dah-flink-prd get sa flink-operator cmf-env-sa-dah-flink-prd` | Yet to be created |

---

## How to update this file

When you open a new cross-team item, add it to the appropriate track with a fresh ID (next sequential under that track's prefix). When an item closes, **don't delete it** — flip its status to `CLOSED` and leave the notes column intact so future readers can see what was resolved and how. Keep the "Last updated" line at the top of the file in step with reality.

If you find yourself reaching for a `runbook/LESSONS_LEARNED.md` entry to explain an item here, link to it by section letter (e.g. "see A10"). This file is the *action* view; the runbook is the *root-cause* view. Keep them complementary, not duplicative.
