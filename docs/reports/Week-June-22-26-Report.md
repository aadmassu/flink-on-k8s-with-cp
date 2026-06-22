# Week-June-22-26 Progress Report

**Project Progress: TBD (color to be set)**

Report period: June 22 – June 26, 2026.

## Priority shift

- **Flink on OpenShift goes to production** — UAT CMF must land first, then promotion path through stg → prd.
- **Confluent Platform QA environment** — to be added to the existing VM infrastructure (parallel to the OpenShift effort).
  - **Ayu** leads and executes the implementation.
  - **Afsaral** files the RITMs to provision: VMs, Service Accounts (both infra and `kafka` service), networking (firewall, load balancer, DNS, KeyFactor certs).
- **Asmerom** delivers the AEP Rate Limit job.
- **New SOW must be signed** to extend Ayu's and Asmerom's hours — gating both the QA-on-VM build-out and AEP delivery.

## Blockers

- **UAT CMF deploy** — encryption-key double-base64 bug isolated and fixed pipeline-side (commit `343a93f`); waiting on: (a) `uat-cmf-encryption-key` variable-group value set to the base64 string in `project-docs/pump.txt`, (b) corrupted Secret deleted, (c) pipeline re-run. Tracker 3.4 (DBA-side CREATE DATABASE permission on `ut_db_DAH_kafka-svc`) still open in parallel.
- **Tracker 3.2 (RITM1050600)** — `fcb-security` ArgoCD chart still hasn't applied per-env SA/Role/RoleBinding to `dah-flink-uat`. Container team.
- **Tracker 1.4** — CyberArk safes don't yet hold the per-env CMF secrets for QA/UAT/PRD (RITM1085071/692/693). Variable-group fallback in place.
- **Tracker 3.5** — prd CMF RBAC scaffolding (8 objects + flink-operator Role update) not yet applied. Tushar to file SNOW; namespace name to confirm.
- **Tracker 2.9** — Okta egress per-namespace allowlist (`myapps.firstcitizens.com:443`) still blocked at perimeter.
- **Tracker 2.10** — CFK broker custom-TCP-port exposure (9092 + 9094) pending non-standard request form, per env.
- **SOW signature** — blocks Ayu's hours extension and the QA-on-VM commitment; blocks Asmerom's AEP job delivery.

## Accomplishments (week ending June 19)

- **CMF encryption-key double-base64 bug — root-caused and fixed pipeline-side** (commit `343a93f`). `create_labeled_secret` re-routed off the encryption-key path; new branch validates the variable is non-empty, valid base64, and decodes to exactly 16 or 32 bytes before `oc apply`-ing the Secret with the value verbatim in `data.key`. Runbook updated (`LESSONS_LEARNED.md` C5, `CHECKLIST.md` pre-flight).
- **Diagnostics pipeline extended with a CMF validation block (CMF.1–CMF.12)** (commit `236dd39`) — Helm release state, prereq-Secret matrix, encryption-key byte-length validator that mirrors CMF's `encryptionConfigInitializer` check, Deployment + Pod state + image-tag drift vs `2.3.0-fcb-preview-2`, namespace-scoped RBAC sanity, rendered `cmf-config` ConfigMap, Service/Endpoints, DB reachability probe from inside the pod (DNS + TCP), filtered pod log tail, REST API health probe, CMF-scoped events. Read-only.
- **UAT + PRD `values.yaml` OAuth blocks commented out** (commit `8886eb4`) — every Okta endpoint and OAuth client credential in the block is still a placeholder; UAT now matches dev/qa posture so the chart can be exercised end-to-end while the real Okta authorization server and CyberArk credentials are wired up. PRD carries a stronger "MUST re-enable before production rollout" warning.
- **Operator + init-container minor alignment in `apps/confluent-platform/dev`** (commit `c33b49d`) — bumped `spec.image.init` from `3.1.2` → `3.2.0` to match the deployed operator chart (`0.1514.40`, CFK 3.2.x). Addresses the kafka `ApplyFailed`/`status.replicas: 0` parked state per `LESSONS_LEARNED.md` D1.
- **Training Week 1 Thursday (Storage) — discussion.md + lab.md rewritten** (commits `b537a23`, `4771f34`) — three CFK PV provisioning options per `docs.confluent.io/operator/current/co-storage.html`, access-mode table, block-vs-NFS section, mermaid + YAML for the full StatefulSet → PVC → PV → StorageClass → backing chain, PVC-reattachment-on-restart walkthrough, per-platform StorageClass table (EKS/AKS/GKE/ROSA/on-prem ODF). Lab runs on kind and `oc`/CRC with every command in both `oc` and `kubectl` variants.
- **Training Week 1 Friday (ConfigMaps/Secrets/SA/RBAC) — discussion.md + lab.md rewritten** (commits `e5b78a5`, `333ac18`) — five primitives in plain K8s, what CFK CRs generate vs. consume, namespace-scoped vs cluster-scoped operator posture, who-creates-what matrix, ESO section covering AWS Secrets Manager (primary), Azure Key Vault, Vault, CyberArk CCP. Lab covers each primitive with break-then-fix exercises and a final Pod-consumes-all-five scenario.
- **kind training lab cluster — full rebuild** (today) — `kind delete cluster --name training` → fresh cluster → CFK operator `0.1514.40` (CFK 3.2.2) → KRaftController (3/3) → Kafka (3/3) → SchemaRegistry (2/2) → ControlCenter (1/1). All Pods Running, anti-affinity spread one-per-node on KRaft + Kafka. Ready for next week's training delivery.
- **Diagnostics pipeline operator-vs-init-container cross-check** (commit `2e9c880`) — explicit pull of `.status.operatorVersion` from a CR plus every CR's `spec.image.init`, so the LESSONS_LEARNED D1 mismatch is the first thing visible after the secrets block.

## Plan for this week (June 22–26)

- **Unblock UAT CMF**: set `uat-cmf-encryption-key` variable-group value, delete the corrupted Secret, re-run the `cmf` pipeline. Verify CMF.3 in the diagnostics dump prints `OK — 32 raw bytes (256-bit AES)`. Then confirm CMF clears `encryptionConfigInitializer` and surfaces the next failure (if any).
- **Ayu — lead the QA-on-VM Confluent Platform implementation**: write the per-component install plan (Controller, Broker, SR, Connect, REST Proxy, C3) for the VM stack mirroring the existing UAT/STG/PRD VM CP install. Sequence the work so it can begin the day the SOW is signed.
- **Afsaral — file RITMs**: VMs (sized per current UAT VM CP), Service Accounts (infra + `kafka` service), Networking (firewall east-west to consumers/producers, load balancer in front of brokers + SR + KRP, internal DNS, KeyFactor cert RITMs per FQDN).
- **Asmerom — deliver AEP Rate Limit job**: drive to completion per the existing aep-rate-limit-job/ folder; coordinate with Walter / Tushar for the deployment review.
- **Get the SOW signed** — blocks the above two work streams. Confirm scope and hours before commitments.
- **File the FCB non-standard TCP port request for the Kafka brokers** (per env, starting DEV) — TCP/9092 (SASL_SSL OAuth) + TCP/9094 (mTLS). Justification drafted in `project-docs/pump.txt`. Tushar files.
- **Verify RITM1093307 implementation lands** — Rick's commit at the 2026-06-12 Friday walk; expect DEV kraft `cluster-ready` flipped to True and Kafka provisioned automatically.
- **Tushar files tracker 3.5 SNOW** — confirm `dah-flink-prd` vs `dah-flink-prod` namespace name with Container team; reference repo template `openshift-prereqs/prd/manifests/flink-sa-role-rolebinding.yaml`.
- **DBA-team follow-through on tracker 3.4** — grant `CREATE DATABASE` to `ut_db_DAH_kafka-svc` (or pre-create `DAHFLINK` with the Flyway-required rows). Once landed, re-attempt UAT CMF deploy.
- **Revert UAT cmf values.yaml DEBUG + stackTraceLogging** (commits `e327716` + `137cae6`) once UAT CMF startup is clean — not safe to leave verbose JDBC + driver-level logs on in upper envs.
- **Continue waiting on**: RITM1050600, RITM1085071/692/693, tracker 2.9 (Okta egress).
