# Week-June-08-12 Progress Report

**Project Progress: RED**

Report period: June 8 – June 12, 2026.

## Blockers

- **DEV namespace storage quota still capped** — CPU + memory portion of the DEV ResourceQuota raise landed, but storage was not granted in the same SNOW pass. PVC-backed StatefulSets (Kafka, KRaftController, ControlCenter, future Flink-state-bearing jobs) are constrained until the storage piece lands. Tracker 2.5 (status downgraded from OPEN / BLOCKER to OPEN now that the urgent CPU/RAM pressure is gone).
- **CFK operator missing `update` + `patch` on cluster-scoped `persistentvolumes`** (RITM1093307, Container team) — kraft and any PVC-backed CR still report `cluster-ready=False` until this lands. Tracker 2.3 / runbook A10. Gabry's justification email (sent last week) is the gating dependency for FCB Container Platforms to approve the exception.
- **`fcb-security` ArgoCD chart hasn't applied the per-env SA/Role/RoleBinding to `dah-flink-uat`** (RITM1050600, Container team) — UAT CMF install will admit cleanly but the pod won't schedule until this lands. Tracker 3.2.
- **CyberArk safes don't yet hold the per-env CMF secrets for QA / UAT / PRD** (QA: RITM1085071, UAT: RITM1085692, PRD: RITM1085693, Tushar) — blocks all three upper-env CMF deploys until fulfillment. Tracker 1.4.

## Accomplishments

- **`aep-rate-limit-job` Flink job successfully deployed in `dah-flink-dev`**. This is the first end-to-end Flink-on-CFK job running in the new dev stack. Required diagnosing and working around three distinct Apache Flink Operator behaviors at FCB:
  - Deployment-level label propagation gap — the operator carries `fcbint.net/*` labels to the Deployment but filters `app.kubernetes.io/*`; FCB Gatekeeper `[required-workload-labels]` denied the POST. Worked around by adding the full FCB common-metadata set to the FlinkDeployment CR's top-level `metadata.labels` (which the operator copies to the Deployment), rather than relying solely on the pod-template labels. Runbook G1 hypothesis is now confirmed by debug-log evidence.
  - Missing `livenessProbe` / `readinessProbe` on the operator-generated pod — Flink Operator only emits a `startupProbe` (with `failureThreshold: 2147483647`, effectively disabled, by design). FCB Gatekeeper `[readiness-liveness]` denied. Worked around by adding explicit probes via `spec.podTemplate.spec.containers[].livenessProbe` / `readinessProbe` pointing at `/config` on the `rest` port. Same shape as the CFK `[startup]` constraint gap.
  - Compute footprint — the dev environment defaults (1 CPU / 4000m JM + 1 CPU / 4000m TM, 2 task slots) would have demanded 2 CPU / 8 GiB just for one Flink job, leaving no room for CFK pods. Reduced to 0.5 CPU / 1024m per JM/TM with 1 slot for `dah-flink-dev` only.
- **DEV ResourceQuota CPU + memory portion raised** by Container team — sufficient headroom for the full CFK stack plus Flink jobs. Connect + ControlCenter can be brought back from `replicas: 0` when re-prioritized. Tracker 2.5 status downgraded from OPEN / BLOCKER → OPEN; storage portion still outstanding.
- **Shrunk `apps/confluent-flink/dev/environment.json` FlinkApplication + compute-pool defaults** — JM/TM CPU `1 → 0.5`, memory `4000m → 1024m`, `taskmanager.numberOfTaskSlots: "2" → "1"`. Any future Flink job in dev that doesn't override now defaults to ~1 CPU / 2 GiB total. QA / UAT / PRD intentionally left at the older defaults — those should be sized per the Application Infrastructure Workbook before per-env promotion.
- **Diagnosed two distinct admission denials** from the same Flink job via the DEBUG logs enabled in last week's RITM1080156 (tracker 3.1 close) — without DEBUG, both failures would have surfaced as opaque "Deployment rejected" events. Validated that the DEBUG investment was load-bearing for this week's progress.
- **Confirmed FCB's Flink Operator install runs with `defaultConfiguration.append: false`** and DEBUG logging still flows correctly (counter to the upstream chart's documented `append: true` requirement). Saved as a project memory so the upstream chart behavior isn't relitigated.

## Next Week Action Items

- **Wait for the DEV storage quota raise** (tracker 2.5 remainder) so PVC-backed CRs aren't constrained on disk; brings Connect + ControlCenter fully back into the dev stack.
- **Wait for RITM1093307** (operator PV RBAC ClusterRole patch) to land in DEV; once Container team applies it, kraft's `cluster-ready` flips to True and Kafka should provision automatically. Gabry's justification writeup, when it arrives, is the artifact Container team needs to approve.
- **Wait for RITM1050600** (`fcb-security` applies SA/Role/RoleBinding to `dah-flink-uat`); once landed, re-run the UAT CMF install pipeline.
- **Track fulfillment of the three CyberArk RITMs** (1085071 / 1085692 / 1085693); once the per-env CMF secrets land in CyberArk, QA + UAT + PRD CMF deploys are unblocked.
- **Submit the still-to-be-created RITMs**: upper-env mirror items 2.2 (admission policy), 2.4 (operator PV RBAC), 2.6 (ResourceQuota), 3.3 (`fcb-security` for PRD).
- **Asmerom continues `aep-rate-limit-job` validation** against the dev CFK + VM Kafka data path now that the job is running; raise any new admission / runtime issues as they surface.
- **Apply the same env.json sizing review to QA / UAT / PRD** before each env's promotion — current files mirror the old dev sizing, which won't match the Application Infrastructure Workbook targets for each env.
- **Once DEV is fully green** (storage quota raised + all 6 CFK pods up + RITM1093307 landed), formally start the UAT promotion using `runbook/CHECKLIST.md`.
