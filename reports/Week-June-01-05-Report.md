# Week-June-01-05 Progress Report

**Project Progress: RED**

Report period: June 1 – June 5, 2026.

## Blockers

- **CFK operator missing `update` + `patch` on cluster-scoped `persistentvolumes`** (RITM1093307, Container team) — kraft and any PVC-backed CR report `cluster-ready=False` even when pods are healthy, so Kafka never reconciles. See `ISSUE-TRACKER.md` 2.3 / runbook A10.
- **`fcb-security` ArgoCD chart hasn't applied the per-env SA/Role/RoleBinding to `dah-flink-uat`** (RITM1050600, Container team) — UAT CMF install will admit cleanly but the pod will fail to schedule with `serviceaccount "flink-operator" not found` until this lands. Tracker 3.2.
- **DEV namespace ResourceQuota too tight at 2 CPU / 8 Gi** (RITM1079670, Container team) — only fits ~4 of the 6 CFK pods because every pod claims ~500m via the operator-injected init container; Connect + ControlCenter parked at `replicas: 0`. Tracker 2.5 / runbook A3.
- **Flink Operator label-propagation issue** (RITM1080156, Container team) — FCB Gatekeeper `[required-workload-labels]` denies the Deployment because the operator doesn't expose a Deployment-level label override. **Blocking Asmerom's job-development work.** Tracker 3.1 / runbook G1.
- **CyberArk safes don't yet hold the per-env CMF secrets for QA / UAT / PRD** (QA: RITM1085071, UAT: RITM1085692, PRD: RITM1085693, Tushar) — blocks all three upper-env CMF deploys until fulfillment. Tracker 1.4.

## Accomplishments

- **Closed the KRaftController authorizer chicken-and-egg** — dropped the `CONFLUENT` provider from the controller's `authorizer.access.rule.providers` (controllers don't host MDS, so centralized RBAC can't bootstrap on them); brokers retain `CONFLUENT,KRAFT_ACL`. Runbook A8.
- **Closed the ConfluentMetricsReporter chicken-and-egg on the controller** — removed `ConfluentMetricsReporter` from `metric.reporters` (publishes to a Kafka topic that doesn't exist until the broker is up); kept `TelemetryReporter`. Runbook A9.
- **Diagnosed the operator PV RBAC gap and got the Ceph CSI driver issue resolved** — Rick's MR registered the CSI driver on the previously-broken node, and the operator RBAC gap was identified, captured as runbook A10, and submitted to Container team as RITM1093307. KRaftController is now `Ready 1/1`.
- **Confirmed `storageClassName: dummy` is intentional CFK behavior** — Confluent product engineers verified, FCB Gatekeeper `[ceph-storage]` policy relaxed (RITM1076878 closed). Removed the side-by-side reproduction folder (`apps/confluent-platform/sts-vct-reproduction/`); captured as runbook A11.
- **Added CMF chart-suppression overrides to UAT + PRD `values.yaml`** — `rbac: false`, `serviceAccount.create: false`, `persistence.create: false`, `additionalLabels`. Without these, the upper-env Helm install hits 5 admission errors at once. Documented in LESSONS-LEARNED.md B4.
- **Refactored env stack from `dev/qa/uat/stg/prd-1/prd-2` to `dev/qa/uat/prd/dr`** — Azure DevOps variable groups renamed to `kafka-openshift-credentials-<env>`, variable refs made generic (`openshift-api`, `openshift-namespace`), `stg/` removed, `prd-1`/`prd-2` collapsed into separate `prd/` and `dr/` (now distinct clusters, not active+passive halves). Touched 7 pipelines + READMEs + runbook + cmf and openshift-prereqs folder layout.
- **Created `runbook/` (`LESSONS_LEARNED.md`, `CHECKLIST.md`) and `ISSUE-TRACKER.md`** — living root-cause documentation (sections A–H, 11+ entries) plus a 3-track cross-team action-item tracker (Secret management, CFK on OpenShift, Flink on OpenShift) with RITM column and clear owner conventions.
- **Added `forceFinalizerRemoval` opt-in to the `confluent-platform` pipeline** — recovers stuck Connect CR after a broken-cluster uninstall; runbook E3.
- **Documented the `fcb-security` pre-creation gate** — README.md + LESSONS-LEARNED.md now carry a pre-flight `oc get sa flink-operator cmf-env-sa-dah-flink-<env>` check before the `cmf` pipeline runs in any upper env, so this trap doesn't repeat for QA/PRD/DR.

## Next Week Action Items

- **Wait for RITM1093307** (operator PV RBAC ClusterRole patch) to land in DEV; once Container team applies it, kraft's `cluster-ready` flips to True and the broker should provision automatically.
- **Wait for RITM1050600** (`fcb-security` applies SA/Role/RoleBinding to `dah-flink-uat`); once landed, re-run the UAT CMF install pipeline.
- **Wait for RITM1079670** (DEV ResourceQuota raise to ≥6 CPU / ≥24 Gi); once landed, revert the `replicas: 0` on Connect + ControlCenter in dev values and re-run install.
- **Track fulfillment of the three CyberArk RITMs** (1085071 / 1085692 / 1085693); once the per-env CMF secrets land in CyberArk, QA + UAT + PRD CMF deploys are unblocked.
- **Submit the still-to-be-created RITMs**: upper-env mirror items 2.2 (admission policy), 2.4 (operator PV RBAC), 2.6 (ResourceQuota), 3.3 (`fcb-security` for PRD); plus housekeeping 1.5 / 1.6 (stale CyberArk key cleanup).
- **Resume Flink Operator label-propagation debugging** (tracker 3.1) once RITM1080156 lands and Rick has the cluster-level admission-mutation policy in place.
- **Once DEV is fully green** (all 6 CFK pods up, CMF connected, Flink job-deploy unblocked), formally start the UAT promotion using `runbook/CHECKLIST.md`.

---

*Generated 2026-06-05 from the daily conversation log, `ISSUE-TRACKER.md` state, and the week's git history. Week range per the "Revised Gantt" tab in `docs/Flink_K8s_CP_Gantt_Chart`.*
