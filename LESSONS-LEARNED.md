# Lessons Learned — DEV Deployment

A retrospective on the dev rollout of the Flink-on-OpenShift stack at FCB. Captures every issue we hit, how it was resolved, and what's still open for cross-team follow-up.

The intent of this doc is twofold:

1. **Audit defense** — every chart deviation, RBAC tweak, and policy interaction is documented so the QA/UAT/PRD rollouts can reference an authoritative root cause for every change.
2. **Cross-team conversations** — there are several items that need closure with Container Platforms (Tom Philipps / Rick Mulder) and the Kafka team (Tushar / Preeti) before we widen the rollout. Those items are pulled out into a dedicated section.

---

## Where dev landed

What's running, healthy, and has been verified end-to-end in `dah-flink-dev`:

| Component | State | Notes |
|---|---|---|
| `confluent-manager-for-apache-flink` Deployment | 1/1 Running, `restartCount: 0`, started in 49s | image `cp-cmf:2.3.0-fcb-preview-2` from FCB Artifactory |
| `cmf-service` Service | port 443 → targetPort 8080, `cmf-https` named port | TLS terminated by Spring Boot inside the pod |
| `cmf-tls` cert-manager Certificate | `Ready=True`, signed by `keyfactor` ClusterIssuer | per-service SANs (no wildcards), 1-year duration, auto-renew at -15d |
| External SQL Server (`DAHFLINK` on `db-dahbronze-d`) | Connected, Flyway schema at v30.1.0 | persistent across helm uninstall/reinstall |
| Flink Environment / Kafka Catalog / Kafka Database in CMF | Registered, retrievable via REST | applied via `flink-environments` pipeline |
| Pod admission stack | passes SCC `restricted-v2`, PSA `restricted`, Gatekeeper required-labels | OpenShift assigns UID `1001320000` from namespace range |
| Variable group `dev-openshift-credentials` | All entries populated, encryption key locked | secret entries marked temp pending CyberArk migration |

What's **not** yet verified end-to-end and tracked in the open-items section: ESO+CyberArk integration, the Flink Operator's presence in `dah-flink-dev`, OAuth on the CMF REST endpoint, HA/DR posture.

---

## Cross-cutting themes (what to internalize before QA/UAT/PRD)

### 1. The cluster has a stack of admission controllers, not just one

Every pod we tried to schedule had to satisfy **all** of:

- **OpenShift SCC** (`restricted-v2`) — mutates UIDs/GIDs to a namespace-assigned range, validates `runAsUser` / `fsGroup`. *Mutates and validates.*
- **Kubernetes PodSecurity admission** (`restricted` profile) — validates container-level `allowPrivilegeEscalation: false`, `capabilities.drop: [ALL]`, `seccompProfile`, `runAsNonRoot`. *Validates only — does not mutate.*
- **Gatekeeper Common Metadata policies** — validates required labels (`app.kubernetes.io/{name,instance,component}`, `fcbint.net/app-id`) on Services, Secrets, Deployments, etc. Some are warn-only today, will graduate to deny.
- **cert-manager approver-policy** + **Keyfactor server-side template validation** for any `Certificate` resource.

Each layer is independent and can fail independently. Two of our deepest debug rabbit-holes were caused by misreading "the SCC is rejecting my pod" when the actual block was PSA, and vice versa. **Read the rejection text carefully** — the layer is named in the error.

### 2. Vendor charts are not OpenShift-aware out of the box

The Confluent CMF Helm chart we vendored shipped with three OpenShift-incompatible defaults:

- `podSecurity.enabled: true` with hardcoded `runAsUser: 1001` / `fsGroup: 1001`
- No container-level `securityContext` block (PSA `restricted` rejects)
- No labels on the rendered Service (Gatekeeper `required-network-labels` warns)

Any future Confluent (or third-party) chart will need the same audit. The pattern: render with `helm template`, grep for `securityContext`, `runAsUser`, `fsGroup`; check every emitted object's `metadata.labels` block; check for `ClusterRole` / `ClusterRoleBinding` (FCB pipeline SA can't create those).

### 3. Helm `--wait` failures cascade

A single `helm upgrade --wait --timeout 10m` that times out leaves the release in a "failed" state with the `deployed` pointer still on the previous successful revision. **Subsequent `helm upgrade`s revert to that older revision's manifests** because helm's idea of "current" is the last successful one. Three failed waits and a chart full of stale ReplicaSets put us in a state where any iteration was overwritten on the next run. Recovery required `helm uninstall` + clean reinstall.

For QA/UAT/PRD: when an install fails, `helm history <release> -n <ns>` and `helm get values <release>` are mandatory diagnostic steps. Don't assume the cluster is running what's in the latest pipeline run.

### 4. Documentation as audit defense

Rick's review style demands every chart deviation, RBAC tweak, and policy interaction be defensible. We absorbed this by:

- Inline comments on every non-obvious values.yaml field (the *why*, not the *what*).
- Per-pipeline header blocks listing variable group dependencies.
- README files at every directory level cross-referencing the others.
- This `LESSONS-LEARNED.md` itself as part of the audit trail.

### 5. Pipeline-managed secrets are an interim state

Today's secrets (`cmf-db-credentials`, `cmf-encryption-key`, `confluent-license`, plus the openshift-service-account-pwd and artifactory-svc-user-password) are created by the pipeline from Azure DevOps variable groups. **This is temporary by FCB policy.** Target state: ESO-managed, CyberArk-sourced. The variable group README marks every secret entry as `temp — pipeline-managed; moves to CyberArk via ESO` so reviewers know the migration is planned, not an oversight.

---

## Issue catalog — what we hit, what we did, where the fix lives

### A. CMF Helm chart customizations

| # | Symptom | Root cause | Resolution | Reference |
|---|---|---|---|---|
| A1 | `helm install` failed: `clusterrolebindings forbidden: User cannot create resource` | Upstream CMF chart unconditionally renders `ClusterRole` and `ClusterRoleBinding`; FCB pipeline SA lacks cluster-scoped RBAC. | Confluent published a custom build (`cp-cmf:2.3.0-fcb-preview-2`) with a `namespaced: true` flag that emits `Role` + `RoleBinding` instead. We set `namespaced: true` in every env's values.yaml. | `apps/confluent-cmf/<env>/values.yaml`, image tag pinned per env |
| A2 | Chart attempted to create its own ServiceAccount | FCB Container Platforms team owns SA creation via the `fcb-security` ArgoCD chart; pipeline SA can't create SAs. | `rbac: false`, `serviceAccount.create: false`, `serviceAccount.name: flink-operator` — chart consumes the existing SA. | `apps/confluent-cmf/<env>/values.yaml` |
| A3 | Pod-admission rejected: `fsGroup: 1001` / `runAsUser: 1001` not in allowed SCC range | Chart's default `podSecurity.enabled: true` injects hardcoded UIDs that conflict with `restricted-v2` SCC's namespace-range mutation. | Set `podSecurity.enabled: false` in every env's values.yaml — chart skips rendering pod-level securityContext, OpenShift assigns UID from the allowed range (`1001320000+`). | `apps/confluent-cmf/<env>/values.yaml` |
| A4 | Pod-admission rejected by PSA `restricted`: missing container-level `allowPrivilegeEscalation`, `capabilities.drop`, `seccompProfile` | Chart's `templates/deployment.yaml` had no container-level `securityContext` block at all. PSA validates this independently of SCC. | Modified the vendored chart's `deployment.yaml` to hardcode the four PSA-required fields at container scope. Aligned with upstream Kubernetes best-practice anyway. | `charts/confluent-manager-for-apache-flink/templates/deployment.yaml` |
| A5 | `cmf-service` triggered `[required-network-labels]` Gatekeeper warning | Chart's `service.yaml` had no `metadata.labels` block. | Modified the vendored chart's `service.yaml` to include the existing `cmf.labels` helper, which combines `app.kubernetes.io/{name,instance,component,managed-by,version}` + `helm.sh/chart` + `additionalLabels.fcbint.net/app-id`. | `charts/confluent-manager-for-apache-flink/templates/service.yaml` |

The two **chart fork commitments** (A4 and A5) are fields on a chart we vendored. Upgrading the chart in future requires re-applying both modifications. Watch for this on every chart bump — track via [`charts/confluent-manager-for-apache-flink/`](charts/confluent-manager-for-apache-flink/) header comments.

### B. RBAC and ServiceAccounts

| # | Symptom | Root cause | Resolution | Reference |
|---|---|---|---|---|
| B1 | CMF pod started but couldn't `list deployments` in its own namespace; threw `KubernetesClientException` at boot | The `flink-operator` SA's Role (deployed by `fcb-security` chart) didn't include `apps/deployments` get/list/watch in `dah-flink-dev`. | Tom's team updated the Role in the `fcb-security` chart to include the required verbs on `pods`, `services`, `events`, `configmaps`, `secrets`, `apps/deployments`, `flink.apache.org/*`, etc. | `openshift-prereqs/<env>/manifests/flink-sa-role-rolebinding.yaml` documents the expected shape |
| B2 | CMF environment creation failed because per-environment SA didn't exist | CMF expects a `cmf-env-sa-<env>` ServiceAccount per registered Environment (used by Flink job pods at runtime); not created automatically. | Pre-created by Tom on a per-environment-namespace basis. Manifests in `openshift-prereqs/<env>/manifests/flink-sa-role-rolebinding.yaml` for reference. | Open item: confirm the `cmf-env-sa-dah-flink-qa` exists before we activate QA. |
| B3 | Initial chart variants tried to bind a Role to the wrong SA name | Earlier iterations had a `flink` SA + Role that wasn't aligned to what CMF was configured to use (`flink-operator`). | Removed the inconsistency; now everything points at `flink-operator` SA. RBAC cleanup in the FCB-managed `fcb-security` chart still pending — orphan `flink` SA + Role may still exist in dev namespace from earlier iterations and could be tidied up. | Tom |

### C. Cert-manager / Keyfactor / TLS to CMF REST endpoint

| # | Symptom | Root cause | Resolution | Reference |
|---|---|---|---|---|
| C1 | `oc wait --for=condition=Ready=True certificate/cmf-tls` timed out at 10 min | We initially requested wildcard SANs (`*.svc`, `*.svc.cluster.local`, `*.ocp.fcbint.net`). The `keyfactor` `ClusterIssuer` is bound to an Entity Keyfactor template, which mandates concrete (non-wildcard) SANs. | Switched to per-service specific SANs: `cmf-service.dah-flink-<env>.svc.cluster.local` + `cmf-service.dah-flink-<env>.svc`. CN matches `*.cluster.local` (allowed by approver-policy). | `apps/confluent-cmf/<env>/cmf-tls-certificate.yaml` |
| C2 | Initial cert manifests rejected at admission | Six Keyfactor metadata annotations are mandatory: `Certificate-Support-Group-Contact`, `Environment` (`Non-Prod-DEV`/`-QA`/`-UAT`/`Prod-Corp`), `Description`, `Organization` (`FCB`), `Application-ID` (CMDB), `Platform` (`OPENSHIFT`). Missing any → Keyfactor rejects. | All six populated on every Certificate manifest. | `apps/confluent-cmf/<env>/cmf-tls-certificate.yaml` annotation block |
| C3 | Resulting `cmf-tls` Secret would have failed `[required-secret-labels]` admission | cert-manager doesn't propagate Common Metadata labels to the Secret it issues. | Added `spec.secretTemplate.labels` block to every Certificate manifest — cert-manager copies these onto the resulting Secret. | `apps/confluent-cmf/<env>/cmf-tls-certificate.yaml` |
| C4 | CMF pod started but Spring Boot wasn't serving HTTPS | Chart had `cmf.ssl` knobs wired to a configmap entry but no PEM cert/key pointed at them by default. | Added `cmf.ssl.enabled: true`, `cmf.ssl.certificate: file:/etc/cmf/tls/tls.crt`, `cmf.ssl.certificate-private-key: file:/etc/cmf/tls/tls.key` plus a `mountedVolumes` block to mount the `cmf-tls` Secret read-only at `/etc/cmf/tls`. Spring Boot 3.1+ accepts PEM directly. | `apps/confluent-cmf/<env>/values.yaml` |
| C5 | Pipelines that hit CMF via apiserver service-proxy returned plaintext-style errors after the TLS cutover | Default service-proxy URL `services/cmf-service:80/proxy` only does plain HTTP. | Updated `flink-environments.yaml` (and the verify pipeline) to use `services/https:cmf-service:443/proxy` — the `https:` prefix tells the apiserver proxy to dial the backend over TLS. | `.azure-pipelines/flink-environments.yaml`, `.azure-pipelines/verify-flink-setup.yaml` |
| C6 | Service port renamed from 80 to 443 | Naming previously misleading (port 80 named `cmf-service-https`). | Renamed to `cmf-https` and changed port to 443; targetPort stays 8080 (CMF Spring Boot listens there). | `charts/confluent-manager-for-apache-flink/templates/service.yaml` |

### D. SQL Server / CMF database

| # | Symptom | Root cause | Resolution | Reference |
|---|---|---|---|---|
| D1 | CMF couldn't connect to dev SQL Server: `PKIX path building failed` (TLS) | SQL Server cert in dev is self-signed; JDBC default rejects. | Added `trustServerCertificate=true` to the JDBC options string. **Must be flipped to `false` for prod** when CA-signed cert is in place. | `apps/confluent-cmf/dev/values.yaml` `cmf.database.jdbc.options` |
| D2 | CMF DB schema persisted across the helm uninstall + clean reinstall | DB is external (SQL Server is managed by FCB DBA team, not by Helm). | Working as designed — Flyway found schema at v30.1.0 on reinstall and skipped migrations. The Environment / Catalog / Database records registered on April 21 were still there after April 30's reinstall. | Operational note for the rollback playbook |
| D3 | DB name briefly used underscores (`DAH_FLINK`); CMF rejected | CMF disallows underscores in database name. | Renamed to `DAHFLINK` (no underscores). | `apps/confluent-cmf/<env>/values.yaml` `cmf.database.jdbc.database` |
| D4 | `cmf.sql.production: true` in early dev attempts caused boot failure | Production mode requires an `encryption.key` Secret, which we hadn't yet created. | Set `cmf.sql.production: false` for dev/qa; flip to `true` only after the `cmf-encryption-key` Secret is in place and validated. | `apps/confluent-cmf/<env>/values.yaml` |

### E. Helm release management

| # | Symptom | Root cause | Resolution | Reference |
|---|---|---|---|---|
| E1 | After three `helm upgrade --wait` timeouts, `helm history` showed release pointer stuck on revision 24 (April 21) with revisions 25/26/27 marked `failed`. 14 stale ReplicaSets accumulated. | Helm's "current deployed" pointer only advances on a successful `--wait`. Failed waits don't advance the pointer; the cluster keeps reverting to whatever the last `deployed` revision shipped. | `helm uninstall confluent-cmf -n dah-flink-dev` to wipe the release, then `cmf` pipeline re-run as revision 1 of a fresh release. Cluster state cleaned up via cascade-delete of the Deployment. | One-time recovery; documented in this file as a runbook step |
| E2 | The 10-minute `--wait` was burning iteration time during debug | Default helm behavior. | During acute debugging, temporarily replaced the `helm upgrade` block in `cmf.yaml` with a battery of diagnostic `helm history` / `helm get values` / `helm get manifest` / `oc get` commands. Reverted once the issue was found. | Pattern available in commit history if needed again |
| E3 | Pre-flight check in `cmf.yaml` aborted the install when `cmf-tls` Secret was missing | Intentional. | Pre-flight added during the TLS work to fail fast (sub-second) instead of letting the install crash 5 minutes in with a Spring Boot keystore error. | `.azure-pipelines/cmf.yaml` "Verifying cmf-tls Secret exists" block |

### F. CMF REST API integration

| # | Symptom | Root cause | Resolution | Reference |
|---|---|---|---|---|
| F1 | Initial environment-name attempts rejected (`fcb-flink-dev`, etc.) | CMF normalizes environment name to match the kubernetesNamespace; we were inconsistent. | Standardized on env name == namespace == `dah-flink-<env>`. | `apps/confluent-flink/<env>/environment.yaml` |
| F2 | Kafka Database name briefly used underscores (`dah_kafka_dev`); CMF rejected | Same DNS-1123-style rule. | Renamed to `dah-kafka-<env>` (hyphens only). | `apps/confluent-flink/<env>/kafka-database.yaml` |
| F3 | Pipeline initially POSTed JSON files; we wanted YAML for readability | CMF accepts JSON over the wire only. | Authored manifests as YAML in Git, added in-flight YAML→JSON conversion via PyYAML in the pipeline. PyYAML is lazy-installed if not on the build agent. | `.azure-pipelines/flink-environments.yaml` `yaml_to_json` helper |
| F4 | Tried to split `flink-environments.yaml` into three resource-specific pipelines (`flink-environment`, `kafka-catalog`, `kafka-database`) | New pipelines need ADO definition registration, which the user can't do alone. The existing `flink-environments` definition expected the original combined file. | Reverted; back to a single combined pipeline that POSTs all three resources sequentially in one run. | `.azure-pipelines/flink-environments.yaml` |

### G. FCB Common Metadata enforcement

| # | Symptom | Root cause | Resolution | Reference |
|---|---|---|---|---|
| G1 | Pipeline-created Secrets triggered `[required-secret-labels]` warning | `oc create secret generic` produces no labels. | Added an `oc label --local` step in the pipeline to inject the four required labels onto each Secret before applying. | `.azure-pipelines/cmf.yaml` `create_labeled_secret` function |
| G2 | Service triggered `[required-network-labels]` warning | (See A5.) | Chart modification to render `cmf.labels` on the Service. | (See A5.) |
| G3 | `replica-range` Gatekeeper policy fires warning on the CMF Deployment | Policy mandates 2-15 replicas; CMF chart hardcodes `replicas: 1` because CMF is single-instance by design (single SQL connection, no leader election). | Currently warn-only — non-blocking. **Requires exception from Container Platforms** if/when Gatekeeper flips to `deny`. Bumping to 2 replicas would break CMF, not satisfy the policy. | Open item — see "Items for Container Platforms" |

### H. Pipeline architecture and variable groups

| # | Symptom | Root cause | Resolution | Reference |
|---|---|---|---|---|
| H1 | Pipelines hardcoded `dev-cmf-*` variable references regardless of selected environment | Initial copy/paste from a dev-only template. | Made all secret references env-aware: `$(${{ parameters.environment }}-cmf-*)`. | `.azure-pipelines/cmf.yaml`, `.azure-pipelines/flink-environments.yaml`, etc. |
| H2 | Variable name typo `dev-cmf-sql-server-user-passwored` (should be `password`) caused secret lookup to return literal `$(name)` | Typo on the variable group entry. | Renamed in the variable group; aligned to `password`. | dev / qa variable groups (in the FCB Library) |
| H3 | QA Kafka REST proxy + Schema Registry are multi-host (comma-separated); pipeline initially treated each as a single hostname | Original connectivity test loop only iterated `kafka-broker-hosts` (already comma-separated) but treated REST proxy / SR as scalar values. | Added comma-split iteration for `<env>-kafka-rest-proxy-hosts` and `<env>-schema-registry-hosts`. | `.azure-pipelines/connectivity-test.yaml` |
| H4 | Encryption key `<env>-cmf-encryption-key` is one-time, non-rotatable | AES-GCM key encrypts secrets at rest in the CMF DB; rotating it makes the existing rows unreadable. | Variable group entry marked **never rotate**. Generated fresh per env. Will move to CyberArk via ESO with the same one-time semantics. | `.azure-pipelines/README.md` |
| H5 | Confluent license JWT initially stored unlocked in the QA variable group | Plaintext JWT visible in screenshots. | Locked in the variable group; treat as credential going forward. License rotation policy still TBD. | Variable group hygiene |

### I. Connectivity to FCB ecosystem

| # | Symptom | Root cause | Resolution | Reference |
|---|---|---|---|---|
| I1 | Cluster has no Docker Hub egress — busybox pull failed | Standard FCB egress lockdown. | All images mirrored through `artifactory.fcbint.net/camdepositsharedservices-docker-dev/`. Connectivity-test pipeline pushes busybox into Artifactory if absent before deploying it for probes. | `.azure-pipelines/connectivity-test.yaml` |
| I2 | Kafka brokers on port 9094 with `security.protocol: PLAINTEXT` (despite 9094 being conventionally TLS in Confluent ecosystem) | Cross-checked with Tushar — FCB's VM Kafka has a dedicated PLAINTEXT listener on 9094. | Configured `kafkaCluster.connectionConfig.security.protocol: PLAINTEXT`. Documented in the Kafka Database manifest with a why-comment so future readers don't "fix" it. | `apps/confluent-flink/dev/kafka-database.yaml` |
| I3 | NetApp S3 URL `qa-net-app-s3-url` initially pointed at `velocity-flink-app-dev` (wrong env's bucket) | Copy-paste from dev's variable group. | Repointed to QA-specific bucket. **Same care needed for UAT/PRD.** | qa variable group |
| I4 | Schema Registry URL is `http://...` (plaintext) | Existing FCB VM cluster doesn't expose SR over HTTPS today. | Configured as HTTP for now; flagged for follow-up with Kafka team. | `apps/confluent-flink/dev/kafka-catalog.yaml` |

---

## Items for follow-up with Container Platforms (Tom Philipps / Rick Mulder)

These are blocked or deferred on cluster-policy / platform-team-managed config that we don't control. Worth a single conversation that walks through the list.

| # | Item | Why it matters |
|---|---|---|
| 1 | **Wildcard Keyfactor template binding** — bind `keyfactor` `ClusterIssuer` to the Wildcard Keyfactor template per `CHG4236061`, or stand up a separate `keyfactor-wildcard` `ClusterIssuer`. | Per-service certs are fine for now (CMF only). When future services land in `dah-flink-<env>` (Schema Registry proxy, Connect proxy, Flink Job UIs), wildcards would let one cert cover them. Otherwise we're issuing N certs for N services. |
| 2 | **`replica-range` exception for `confluent-manager-for-apache-flink`** — currently warn-only Gatekeeper constraint requires 2-15 replicas. CMF is single-instance by Confluent design (single SQL connection, no leader election today). | If/when Gatekeeper flips to `deny`, deployment breaks. Pre-emptive exception needed. Confluent's HA roadmap for CMF is uncertain. |
| 3 | **`flink-operator` SA permissions** — confirm the Role bound by `fcb-security` chart includes `serviceaccounts` (CRUD), `rbac.authorization.k8s.io/{roles,rolebindings}` (CRUD). | CMF creates per-application SAs and Roles when launching Flink jobs. Without these, runtime job submission will fail even though CMF itself is healthy. |
| 4 | **Per-environment SA pre-creation** — confirm `cmf-env-sa-dah-flink-qa` (and uat/prd) will be pre-created by Tom in advance of those rollouts. | CMF expects this SA to exist; it's used by Flink job pods at runtime. Without pre-creation, Environment registration fails. |
| 5 | **Apiserver service-proxy trust of Keyfactor CA** — verify the apiserver's trust bundle includes the Keyfactor CA. | If it doesn't, our `services/https:cmf-service:443/proxy` calls fail with TLS verification errors and the `flink-environments` pipeline can't reach CMF. So far we've only validated the data path informally. |
| 6 | **Flink Operator presence in `dah-flink-<env>`** — log warning at CMF startup: `"FlinkDeployment CRD is registered but no operator deployment was found"`. | CMF is healthy without it, but the moment we submit a `FlinkApplication` via the REST API, the CR has nothing to reconcile it. Need the Operator deployed in the namespace (or a system namespace watching `dah-flink-<env>`). |
| 7 | **CyberArk SecretStore URL correction** — the existing `ClusterSecretStore` was created with the wrong URL, blocking ESO integration. | Until corrected, we can't migrate the five secret-type variable group entries (cmf-db-password, cmf-encryption-key, confluent-license, openshift-service-account-pwd, artifactory-svc-user-password) out of pipeline-managed mode. SNOW form "Container Platforms: Onboard Namespace to CyberArk" is the trigger. |
| 8 | **PSA profile baseline confirmation** — does `dah-flink-<env>` have `pod-security.kubernetes.io/enforce: restricted` (deny) or `warn: restricted`? | Affects whether the container `securityContext` we hardcoded into the chart is *required* or *recommended*. Documented as required defensively, but worth confirming. |
| 9 | **`fcb-security` chart RBAC drift** — orphan `flink` SA + Role + RoleBinding may exist in `dah-flink-dev` from earlier iterations of CMF deployment. | Not breaking, but tidies up the audit picture. If the FCB-managed chart only deploys `flink-operator`-scoped resources today, the leftovers can be removed. |
| 10 | **Encryption key recovery procedure** — `<env>-cmf-encryption-key` is a one-time, non-rotatable AES-GCM key. Variable group is the current store; if wiped, all encrypted CMF DB rows become unreadable. | When ESO+CyberArk lands, the same constraint applies. Document the recovery path (vault path, escrow procedure) in DR runbook. |

---

## Items for follow-up with Kafka team (Tushar Sridhar / Preeti)

The CMF/Flink stack consumes the existing FCB VM Kafka cluster as a black box. These items will affect how the integration evolves.

| # | Item | Why it matters |
|---|---|---|
| 1 | **Confirm `PLAINTEXT` on port 9094 is the long-term plan** — vs. eventual SASL_SSL migration. | Today's Kafka Database manifest hardcodes `security.protocol: PLAINTEXT`. If the Kafka team is planning a TLS-listener rollout, we'll need to add `connectionSecretId` referencing a SASL JAAS config Secret and possibly a CA bundle for in-cluster trust. |
| 2 | **Schema Registry HTTPS** — currently HTTP, configured at `http://d11547varc-4559.fcpd.fcbint.net:8081`. | Same as above. Kafka Catalog manifest will need TLS config + trust bundle. The current CMF cert is for `cmf-service` only; SR consumers in CMF would need separate trust. |
| 3 | **Kafka brokers / SR / REST Proxy per environment** — are dev/qa pointed at the same VM cluster, or distinct clusters? | Variable groups suggest distinct broker hostnames per env (`d11547varc-*` for dev, `t11547varc-*` for qa). Confirm this is intentional and what UAT/PRD will use. |
| 4 | **OAuth Bearer / MDS** — CMF supports `cmf.authentication.type: oauth` referencing Confluent's MDS for RBAC enforcement. Today disabled. | When we want fine-grained access control on the CMF REST endpoint (instead of "anyone with cluster RBAC can call it"), we'll need MDS endpoints, an Okta tenant, and OAuth client credentials per env. Also affects how Flink jobs authenticate to Kafka brokers. |
| 5 | **Topic naming conventions** — for Flink CDC sources / sinks the team will eventually run. | Catalog management gets cleaner if there's a documented prefix convention that aligns with the Kafka team's existing topic governance. |
| 6 | **Confluent license refresh** — current `<env>-confluent-license` JWT expires `2028-04-30`. | 730 days from now, but worth knowing whether the Kafka team or Container Platforms will source the renewal. Same license used for CMF + the broader Confluent Platform on VMs? Or distinct? |
| 7 | **Kafka REST Proxy multi-host configuration** — qa has multiple REST Proxy hosts; CMF Kafka Database manifest only references brokers, not REST Proxy. | If REST Proxy is needed for some CMF/Flink features, we'll need to add it to the connection config and confirm load-balancing semantics. |

---

## Deferred items (our follow-up, not blocked on a team)

| # | Item | Status |
|---|---|---|
| 1 | **OAuth on CMF REST endpoint** — currently `Authentication is disabled` in CMF startup logs. | Wired in chart values for uat/prd templates, just commented as `<TODO>`. Activate once Okta tenant + audience + client-id is provided. |
| 2 | **HA / DR plan for CMF** — single-instance, no leader election, external DB. Pod restart = ~30-60s outage. | Acceptable for non-prod. PRD needs a documented plan: scheduled maintenance window for cert renewals and pod restarts; SQL Server failover behavior; runbook for Confluent license rotation. |
| 3 | **Flink Operator deployment audit** — confirm operator is running in (or watching) `dah-flink-<env>`. CMF reports the warning at boot. | Possibly already managed by Container Platforms via a separate ArgoCD app; need to confirm before submitting FlinkApplications. |
| 4 | **NetApp S3 bucket per-env enforcement** — caught dev URL leaking into qa once. | Add a verify-pipeline step that asserts `<env>-net-app-s3-url` matches the expected per-env naming convention. |
| 5 | **Verify-pipeline build-pool approval** — `verify-flink-setup.yaml` requires pool approval the user doesn't have. Diagnostics that need to fire on every install run had to be moved into the install pipeline's failure path instead. | Either get approval, or accept that the verify pipeline is rarely runnable and concentrate diagnostics in the install pipelines. Currently the latter. |
| 6 | **Replica-range exception, in writing** — file the request now while it's a warning, so the exception is in place before Gatekeeper graduates the policy. | One ticket / SNOW form to Container Platforms. |

---

## What I'd do differently next time (process notes)

1. **Run `helm template` against the vendored chart on day one**, before writing any pipeline. Inspect every emitted manifest for OpenShift compatibility — `securityContext`, RBAC scope, label completeness, port assumptions. We discovered most of A1-A5 piecemeal across runs that each took 5-15 minutes; a single `helm template ... | grep -E "securityContext|ClusterRole|labels:"` would have surfaced them in 30 seconds.

2. **Establish the admission-stack mental model first**, then debug. Specifically: SCC mutates and validates; PSA validates only; Gatekeeper validates with severity (`warn` vs `deny`); cert-manager has its own approver-policy. Knowing which layer threw a given error saves hours.

3. **`helm history` is a first-class debug tool, not a last resort.** When the cluster behaves like it's stuck in the past, it almost certainly is — check the release pointer.

4. **Pipeline cycle time matters more than YAML elegance.** A pipeline that takes 12 minutes to fail is a learning rate of 5 cycles per hour. Adding a sub-second pre-flight check (like the `cmf-tls` Secret existence test) for every dependency dropped our median failure time from 12 min → 30s. Same logic should apply to chart values validation: render and grep before applying.

5. **Document the *why*, not the *what*.** Comments like `# trustServerCertificate=true because dev SQL is self-signed` survive a re-read in three months. Comments like `# set trustServerCertificate to true` rot. The values.yaml files now have why-comments throughout; carry that pattern into qa/uat/prd.

6. **For chart forks, mark every modification.** The two chart-modification points (container `securityContext`, Service labels) are not in upstream Confluent's chart. Header comments in those files document what was changed and why so a future bump doesn't silently lose the changes.

---

## Recommended sequence for QA / UAT / PRD rollout

Based on all of the above, the per-env playbook:

1. **Pre-reqs in place by Container Platforms (Tom)**: namespace `dah-flink-<env>`, `flink-operator` SA + Role + RoleBinding via `fcb-security` chart, `cmf-env-sa-dah-flink-<env>` pre-created, `restricted-v2` SCC bindings.
2. **Variable group on FCB Azure DevOps**: `kafka-openshift-credentials-<env>` populated, secret entries marked. Confluent license JWT locked.
3. **DBA team (SNOW)**: SQL Server database for CMF, env-specific service principal, JDBC URL. (For environments not yet on jdbc, fallback to `database.type: local` is documented in QA values as a stopgap.)
4. **Storage team (SNOW)**: NetApp S3 bucket per env (`velocity-flink-app-<env>`) + per-env S3 URL.
5. **Apply `apps/confluent-cmf/<env>/cmf-tls-certificate.yaml`** via `cmf-tls` pipeline. Verify Certificate `Ready=True`, Secret has `tls.crt` + `tls.key` + `ca.crt`.
6. **Run `cmf` pipeline.** Pre-flight passes (Secret exists), helm install succeeds, pod schedules, CMF starts.
7. **Run `flink-environments` pipeline.** Registers Environment + Kafka Catalog + Kafka Database via REST.
8. **Functional smoke test**: a `curl -k https://cmf-service.dah-flink-<env>.svc.cluster.local:443/cmf/api/v1/environments` from inside the namespace returns 200 + the registered env.
9. **Commit and close** the env-specific cutover ticket.

Each step is bounded — under 15 minutes individually if everything aligns. If a step fails, the diagnostics in `cmf-tls.yaml`'s failure path (for cert) and `cmf.yaml`'s log output (for install) point at a specific layer.

---

*Last updated: end of dev rollout, pre-QA enablement.*
