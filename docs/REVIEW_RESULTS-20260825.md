# QA-to-UAT Promotion Review

Decision: **GO for repository promotion and UAT-P/UAT-S deployment**, subject to the external prerequisites listed below.

## Corrections made

- Rebuilt UAT-P and UAT-S deployable manifests from the working QA baseline.
- Preserved the shared UAT namespace (`dah-flink-uat`) and floating DNS (`*.apps.ut.ocp.fcbint.net`).
- Assigned physical-cluster certificate SANs to `*.apps.ut-p.ocp.fcbint.net` and `*.apps.ut-s.ocp.fcbint.net` respectively.
- Promoted QA storage and resources, including 300 Gi per Kafka broker, 25 Gi per KRaft controller, 100 Gi for Control Center, and the 100 Gi Control Center Prometheus PVC.
- Promoted QA TLS, PKCS12 truststore, OAuth/MDS, operator-mTLS, C3 Prometheus/Alertmanager, image, probe, and dependency configuration.
- Added the missing `cfk-operator-mds-client-certificate.yaml` and Control Center Prometheus PVC to both UAT environments.
- Moved bootstrap role bindings to the pipeline-required `rbac/rolebindings.yaml` path.
- Corrected UAT OAuth scope/group-claim values and removed DEV/QA identity leakage.
- Configured onboarding RBAC for the UAT user group `ut_app_okta_digital_analytics_hub_users`.
- Generalized component-client-ID rendering to use the selected environment's Azure DevOps variable group.
- Restored both application-RBAC deployment modes: `cfk-cr` and `direct-mds-bootstrap`. Both consume `rbac/onboarding-rolebindings.yaml`; no second RBAC JSON manifest is used.
- Extended the QA mTLS, trust-bundle, certificate, existing-cluster bootstrap, and C3 PVC pipeline gates to UAT-P and UAT-S.
- Confirmed no application-owned NetworkPolicy exists or is applied for QA/UAT.

## Validation performed

- Parsed 98 YAML files containing 131 YAML documents.
- Syntax-checked 6 shell script files and 52 inline Azure Pipeline shell blocks.
- Checked 4 Python scripts against Python 3.6 grammar.
- Verified UAT-P/UAT-S parity; only the approved `ut-p`/`ut-s` physical certificate SANs differ.
- Verified QA-equivalent images, replicas, storage, CPU, memory, TLS, truststore, and component topology.
- Verified six onboarding and eight component/bootstrap role bindings per UAT environment.
- Verified the UAT SecretStore/license mapping is `11547-u-key-fp` / `uat-confluent-license`.
- Verified no DEV/QA namespace, OAuth scope, group claim, group principal, or DNS leakage remains in deployable UAT YAML.

## External pre-deployment prerequisites

These cannot be proven from repository files and must be true in each target cluster/variable group:

1. `kafka-openshift-credentials-uat-p` and `kafka-openshift-credentials-uat-s` point to their respective OpenShift API endpoints but contain the same approved UAT component/OIDC credentials.
2. Both namespaces contain the platform-managed `fcb-trust-bundle` ConfigMap with `bundle.p12` (and `bundle.jks` for the KRaft configuration inherited from QA).
3. SecretStore `11547-u-key-fp`, remote key `uat-confluent-license`, StorageClass `kafka`, cert-manager issuer, upper-environment NetworkPolicy, floating DNS, and Okta redirect URIs/group assignment are provisioned by their owning teams.
4. The asserted UAT group name `ut_app_okta_digital_analytics_hub_users` matches the exact value emitted in the UAT token's `dahUAT_groups` claim.

Install UAT-P and UAT-S separately. Do not run both installs concurrently against the same physical cluster or variable group.
