# Issue Tracker

Cross-team action items for the CFK + CMF + Flink rollout on FCB OpenShift. Each entry names the **scope** (which env/component), the **owner**, and the **current state**.

This is the action-item view. For technical root-cause writeups on closed issues, see [`runbook/LESSONS_LEARNED.md`](runbook/LESSONS_LEARNED.md). For per-env deploy gates, see [`runbook/CHECKLIST.md`](runbook/CHECKLIST.md). For the original DEV-rollout retrospective, see [`LESSONS-LEARNED.md`](LESSONS-LEARNED.md).

**Status legend:**
- `OPEN` — work outstanding
- `BLOCKER` — currently blocking forward progress on a named workstream
- `CLOSED` — resolved; kept for reference

*Last updated: 2026-06-05.*

---

## 1. Secret management — ESO + CyberArk integration

**Scope:** All envs. **Owner:** FCB Security (CyberArk safe admins), Tushar (safe contents), Container team (cluster-side ESO).

DEV is fully integrated and CMF is running against CyberArk-sourced secrets — no longer a FLINK+CFK blocker. Remaining items are housekeeping plus the corresponding request for upper envs.

| ID | Status | Issue | Notes |
|---|---|---|---|
| 1.1 | CLOSED | `dev-confluent-license` secret wasn't syncing to OpenShift | Resolved. Root cause was format mismatch — CMF wants the raw JWT, CFK wants `license=<JWT>` properties shape (`runbook/LESSONS_LEARNED.md` C1) |
| 1.2 | CLOSED | `dev-artifactory-svc-user-password` and `dev-db-user-password` missing from CyberArk Key safe | Added |
| 1.3 | OPEN | Cleanup — remove duplicate keys from the Linux safe | Housekeeping. Not a blocker. Tushar |
| 1.4 | OPEN | Submit CyberArk request for QA + UAT (PRD + DR to follow as we promote) | **Blocks QA + UAT enablement.** SNOW ticket pending submission |

## 2. CFK on OpenShift — admission policy + operator RBAC

**Scope:** All envs. **Owner:** Container team.

DEV has been unblocked through Gatekeeper policy relaxations and operator-side ClusterRole adjustments. The same fixes need to be applied to QA / UAT / PRD / DR clusters as we promote.

| ID | Status | Issue | Notes |
|---|---|---|---|
| 2.1 | CLOSED (DEV) | Gatekeeper `[ceph-storage]` constraint denying CFK StatefulSets that emit `storageClassName: dummy` on the volumeClaimTemplate | Policy relaxed in DEV. CFK 3.1.x/3.2.x both emit `dummy` intentionally as a sentinel; the real storage class is applied to PVCs through a separate operator code path. See `runbook/LESSONS_LEARNED.md` A11 |
| 2.2 | OPEN | CFK operator ServiceAccount (`confluent-operator/confluent`) lacks `update` + `patch` on cluster-scoped `persistentvolumes` | Without this, kraft and any PVC-backed CR report `cluster-ready=False` even when the pod is healthy — and Kafka never reconciles because it waits on kraft. Fix is a ClusterRole patch (one rule, two verbs). See `runbook/LESSONS_LEARNED.md` A10 |
| 2.3 | OPEN | Mirror 2.1 + 2.2 onto QA / UAT / PRD / DR clusters as part of each env's provisioning ticket | Tracker for the upper-env CFK rollout. Without these policy + RBAC changes in place ahead of CFK install, the symptoms in DEV will repeat verbatim |
| 2.4 | OPEN | DEV namespace ResourceQuota increase | Current 2 CPU / 8 Gi only fits ~4 of the 6 CFK pods. Every pod claims ~500m via the operator-injected init container (`runbook/LESSONS_LEARNED.md` A3). Container team to raise to ≥6 CPU / ≥24 Gi so we can bring Connect + ControlCenter back from `replicas: 0` |

## 3. Flink Kubernetes Operator — Deployment-level label propagation

**Scope:** DEV (Flink job deployment). **Owner:** Asmerom (engineering side), Container team (operator / Kyverno side).

| ID | Status | Issue | Notes |
|---|---|---|---|
| 3.1 | BLOCKER | Enable debug logging on the Flink Kubernetes Operator to diagnose why FCB common-metadata labels aren't propagating to the Deployment that the operator creates | **Blocking Asmerom's job-development work.** FCB Gatekeeper `[required-workload-labels]` denies the Deployment because the operator doesn't expose a Deployment-level label override — Pod labels propagate fine, Deployment labels don't. Likely needs a Kyverno mutation policy added at the cluster level (or an upstream operator fix). See `runbook/LESSONS_LEARNED.md` G1 |

## 4. Upper-environment rollout (UAT → PRD → DR)

**Scope:** UAT first, then PRD, then DR. **Owner:** Ayele (manifests), Container team (RBAC pre-creation), DBA team (SQL Server provisioning).

The env-stack refactor dropped `stg` and split the old `prd-1`/`prd-2` into separate `prd` / `dr` clusters. DEV is the reference for the per-env playbook in [`LESSONS-LEARNED.md` § Recommended sequence](LESSONS-LEARNED.md#recommended-sequence-for-qa--uat--prd-rollout).

| ID | Status | Issue | Notes |
|---|---|---|---|
| 4.1 | CLOSED | CFK Custom Resources weren't visible on the OpenShift console for the upper-env cluster | Fixed by Maha. Historical reference; was specific to the cluster's console view, not a CFK or manifest issue |
| 4.2 | OPEN | UAT CMF Helm install hit 5 admission errors at once (`serviceaccounts/roles/rolebindings is forbidden`, `[ceph-storage]` PVC denial, `[required-workload-labels]`) | Chart-suppression overrides added to `apps/confluent-cmf/uat/values.yaml` + `apps/confluent-cmf/prd/values.yaml` to match the dev/qa pattern. See `LESSONS-LEARNED.md` B4 |
| 4.3 | OPEN | `fcb-security` ArgoCD chart hasn't yet applied the per-env SA / Role / RoleBinding to `dah-flink-uat` | Pending Container team change-management approval. Required before the next CMF install attempt can succeed — the chart-suppression overrides in 4.2 mean the install will admit cleanly, but the CMF pod will fail to schedule with `serviceaccount "flink-operator" not found` until this lands. Pre-flight check: `oc -n dah-flink-uat get sa flink-operator cmf-env-sa-dah-flink-uat` |

---

## How to update this file

When you open a new cross-team item, add it to the appropriate section with a fresh ID (next sequential under that section's prefix — e.g. the next open item under section 2 is `2.5`). When an item closes, **don't delete it** — flip its status to `CLOSED` and leave the notes column intact so future readers can see what was resolved and how. Keep the "Last updated" line at the top of the file in step with reality.

If you find yourself reaching for a `runbook/LESSONS_LEARNED.md` entry to explain an item here, link to it by section letter (e.g. "see A10"). This file is the *action* view; the runbook is the *root-cause* view. Keep them complementary, not duplicative.
