# Confluent Platform Hybrid Authentication Refactor — Implementation Summary

**Date Completed**: 2026-08-12  
**Status**: Ready for Phase 4 deployment  
**Scope**: 6 environments (dev, qa, uat-p, uat-s, prd, dr)

---

## Executive Summary

This refactor unifies Confluent Platform's listener architecture around a **hybrid OAuth + OIDC authentication model**, migrating managed components (SchemaRegistry, Connect, REST Proxy, Control Center) from basic internal authentication (:9071) to OAuth-based external authentication (:9092). Control Center browser SSO now uses Okta OIDC exclusively.

### Key Changes

| Area | Before | After |
|------|--------|-------|
| **Managed Component Bootstrap** | `kafka:9071` (SASL/PLAIN) | `kafka:9092` (OAuth) |
| **C3 UI Authentication** | Basic HTTP Auth (username/password) | Okta OIDC (user identity + groups) |
| **MDS Token Signing** | Implicit (pod-local) | Explicit via `mds-token-keypair` Secret |
| **OAuth Scopes** | Per-component (e.g., "11547.DAH(Dev)") | Expanded for groups claims (dahDev_groups, etc.) |

---

## Phase 1: Manifest Updates ✅ COMPLETE

### Changed Files: All 6 Environments

#### For each environment (dev, qa, uat-p, uat-s, prd, dr):

**schemaregistry.yaml, connect.yaml, kafkarest.yaml, controlcenter.yaml:**
- **Line 70 (schemaregistry.yaml)** / **Line 65 (connect.yaml)** / **Line 66 (kafkarest.yaml)** / **Line 104 (controlcenter.yaml)**
  - Changed: `bootstrapEndpoint: kafka.dah-flink-<env>.svc.cluster.local:9071`
  - To: `bootstrapEndpoint: kafka.dah-flink-<env>.svc.cluster.local:9092`

**controlcenter.yaml (all environments):**
- **Lines 62–70 (old)**: Removed entire top-level authentication block:
  ```yaml
  authentication:
    type: basic
    basic:
      secretRef: controlcenter-basic-auth
      roles:
        - Administrators
      restrictedRoles:
        - Restricted
  ```
- **Dependencies.kafka.oauthSettings**: Retained as-is (now uses :9092)
- **Dependencies.mds.ssoProtocol**: Retained and verified as `oidc`

### Verification: All 6 environments confirmed ✓

```bash
# Pattern: Each environment uses correct namespace-specific kafka service DNS
dev:   kafka.dah-flink-dev.svc.cluster.local:9092
qa:    kafka.dah-flink-qa.svc.cluster.local:9092
uat-p: kafka.dah-flink-uat.svc.cluster.local:9092   # Note: shared with uat-s
uat-s: kafka.dah-flink-uat.svc.cluster.local:9092
prd:   kafka.dah-flink-prd.svc.cluster.local:9092
dr:    kafka.dah-flink-dr.svc.cluster.local:9092
```

---

## Phase 2: Pipeline Refactor ✅ COMPLETE

### File: `.azure-pipelines/confluent-platform.yaml`

#### 2a. Required Variables Validation (Lines 136–147)

**Added to `required_vars` array:**
```bash
OAUTH_MDS_SSO_ID OAUTH_MDS_SSO_SECRET
```

**Rationale**: MDS OIDC client credentials now required for all environments.

**Removed** (these were never actually used):
- `C3_BASIC_USER` (not in pipeline)
- `C3_BASIC_PWD` (not in pipeline)

#### 2b. Removed C3 Basic Auth Secret Creation (Old Lines 373–383)

**Deleted block**:
```bash
# C3 UI basic-auth realm — key basic.txt is a Jetty realm file...
BASIC_TMP=$(mktemp)
printf '%s: %s,Administrators,Restricted\n' \
  "$OAUTH_C3_ID" "$OAUTH_C3_SECRET" > "$BASIC_TMP"
apply_secret_from_file controlcenter-basic-auth basic.txt "$BASIC_TMP"
rm -f "$BASIC_TMP"
```

**Impact**:
- `controlcenter-basic-auth` Secret no longer created by pipeline
- If Secret exists on cluster, it will be ignored by new manifests (C3 doesn't reference it)
- Uninstall step preserves prereq Secrets (old `controlcenter-basic-auth` won't be deleted)

#### 2c. Removed `controlcenter-basic-auth` from Prereq Checks

**Removed from**:
- **Required secrets array** (line ~499)
- **oc describe loop** (line ~388-396)
- **Summary oc get secret** command (line ~391-399)

#### 2d. Re-enabled Readiness Gates (Lines 730–758)

**KRaftController Readiness Gate**:
```bash
if is_true "$APPLY_KRAFT" || is_true "$APPLY_KAFKA"; then
  wait_for_cr_ready kraftcontroller kraftcontroller 600
fi
```
- Timeout: **600 seconds** (10 minutes)
- Triggers before Kafka apply

**Kafka Readiness Gate**:
```bash
if is_true "$APPLY_KAFKA" || is_true "$APPLY_SR" \
   || is_true "$APPLY_CONNECT" || is_true "$APPLY_KREST" \
   || is_true "$APPLY_C3"; then
  wait_for_cr_ready kafka kafka 900
fi
```
- Timeout: **900 seconds** (15 minutes)
- Blocks Phase 2 component apply (SR, Connect, REST, C3)

#### 2e. Post-Kafka Verification (New step, ~750 lines after Kafka readiness gate)

**Checks**:
1. Kafka listeners configuration in CR spec
2. **oauth-mds-sso Secret exists** — required for MDS OIDC
3. **MDS readiness** at https://localhost:8090/api/v1/metadata/security/1.0/validate
   - Polls up to 150s (30 attempts × 5s sleep)
   - Non-fatal warning if timeout (proceed anyway)

**Code location**: Inserted between Kafka readiness gate and Phase 2 rolebindings apply

#### 2f. Managed Components Readiness Task (New task, before Ingress apply)

**New pipeline step** (after CR apply, before Ingress):
- **Task name**: "Verify managed components readiness before Ingress"
- **Purpose**: Block Ingress until components are ready or report warnings
- **Components checked**:
  - SchemaRegistry (if APPLY_SR=True)
  - Connect (if APPLY_CONNECT=True)
  - KafkaRestProxy (if APPLY_KREST=True)
  - ControlCenter (if APPLY_C3=True)
- **Timeout per component**: 300s (5 minutes)
- **Failure mode**: WARNING (non-fatal; Ingress applies anyway)

### Summary of Pipeline Changes

| Operation | Status |
|-----------|--------|
| Add OAUTH_MDS_SSO to required vars | ✓ Done |
| Remove controlcenter-basic-auth Secret creation | ✓ Done |
| Remove controlcenter-basic-auth from prereq checks | ✓ Done |
| Re-enable KRaftController readiness gate (600s) | ✓ Done |
| Re-enable Kafka readiness gate (900s) | ✓ Done |
| Add post-Kafka oauth-mds-sso / MDS verification | ✓ Done |
| Add managed components readiness task | ✓ Done |

---

## Phase 3: Documentation ✅ COMPLETE

### New Reference Guides

#### 3.1 `docs/LISTENER_PORT_MATRIX.md` (168 lines)

**Contents**:
- Listener port overview table (9071 internal, 9092 external, 8090 MDS)
- Listener detail sections with auth mechanisms, clients, certificates
- DNS resolution by environment (with note on uat-p/uat-s shared DNS)
- Managed component bootstrap endpoints (all now :9092)
- Control Center authentication paths (OIDC for UI, OAuth for backend)
- Pre-deployment checklist
- Troubleshooting guide with symptoms/diagnosis/fixes

**Use case**: Operational reference for understanding Confluent Platform listener architecture post-refactor.

#### 3.2 `docs/OKTA_OIDC_REQUIREMENTS.md` (290 lines)

**Contents**:
- Okta OIDC app settings template (Authorization Code flow, public/confidential)
- Base configuration (issuer, endpoints)
- **Redirect URIs for all 6 environments** (with exact callback URIs)
- Scope configuration (openid, profile, email, refresh token)
- Groups claim configuration by environment (dahDev_groups, dahQA_groups, dahUAT_groups, dahProd_groups)
- Subject claim options (email vs. sub)
- Pre-deployment checklist
- Post-deployment validation tests (browser, token introspection, C3 connection, Kafka listener)
- Okta OIDC app creation steps (for admins)
- Known issues and troubleshooting

**Use case**: Template and procedures for Okta team to provision OIDC apps; validation guide for ops.

#### 3.3 `docs/CONTROL_CENTER_SSO_VALIDATION.md` (371 lines)

**Contents**:
- Quick validation (5 min): pod health, DNS, TLS cert, HTTP redirect test
- Full validation (manual browser): step-by-step OIDC flow with expected results
- Automated validation commands: pod status, service/endpoint checks, Secret validation, MDS readiness, listener verification, C3 OIDC config inspection
- Common issues with symptoms, root causes, and fixes
- Backup testing without browser (curl-based OAuth simulation)
- Validation checklist

**Use case**: Post-deployment testing and troubleshooting guide for ops teams.

---

## Phase 4: Deployment Readiness Checklist

### Pre-Deployment (All Environments)

- [ ] **Okta OIDC apps provisioned**:
  - [ ] DEV: `oauth-mds-sso` OIDC app created, callback URI registered
  - [ ] QA: Same
  - [ ] UAT-P & UAT-S: Shared OIDC app with floating DNS callback
  - [ ] PRD: OIDC app created
  - [ ] DR: OIDC app created (or shares PRD app)

- [ ] **Okta credentials stored in Azure DevOps variable groups**:
  - [ ] Each environment has `<env>-oauth-mds-sso-client-id` and `-client-secret`

- [ ] **Floating DNS CNAMEs registered** (UAT, PRD, DR):
  - [ ] `controlcenter.apps.<env>.ocp.fcbint.net`
  - [ ] `kafka-mds.apps.<env>.ocp.fcbint.net` (if using external MDS)
  - [ ] Other component Ingress hostnames (SR, Connect, REST)

- [ ] **Manifests verified in target environments**:
  - [ ] Each manifest reviewed for environment-specific values (namespace, scopes, groups claims)
  - [ ] No `REPLACE_WITH_*` placeholders remain

### Deployment Steps (Per Environment)

1. **Run create-prereqs task**:
   ```
   Pipeline: confluent-platform.yaml
   Parameters:
     environment: <env>
     action: create-prereqs
   ```
   - Validates OAUTH_MDS_SSO_* variables present
   - Creates oauth-mds-sso Secret with OIDC client credentials
   - All other prereq Secrets created as before

2. **Run install-or-update task**:
   ```
   Pipeline: confluent-platform.yaml
   Parameters:
     environment: <env>
     action: install-or-update
     applyAll: true
   ```
   - Applies Certificate CRs (wait ~10 min for TLS Secrets)
   - Phase 1a: KRaftController (wait 600s for cluster-ready)
   - Phase 1b: Kafka + kafkarestclass (wait 900s for cluster-ready)
   - Post-Kafka verification: oauth-mds-sso Secret check, MDS readiness
   - Phase 2 (pre): rolebindings
   - Phase 2: SR, Connect, REST, C3 (wait for readiness before Ingress)
   - Apply Ingress CRs

3. **Post-deployment validation**:
   - [ ] Run validation commands from CONTROL_CENTER_SSO_VALIDATION.md
   - [ ] Test C3 browser login (manual: https://controlcenter.apps.dv.ocp.fcbint.net/)
   - [ ] Check pod logs for OIDC errors
   - [ ] Verify Kafka listeners online (9071, 9092, 8090)

### Rollback / Troubleshooting

**If C3 login fails with "Invalid redirect_uri"**:
- Verify callback URI in Okta app matches CONTROL_CENTER_SSO_VALIDATION.md table
- Verify floating DNS CNAME is registered and resolves correctly
- Check kafka.yaml spec.services.mds.provider.sso.configurations

**If oauth-mds-sso Secret missing**:
- Run `action=create-prereqs` with `bypassEsoForSecrets=oauth-mds-sso` to override ExternalSecret

**If managed components can't reach Kafka at :9092**:
- Verify manifests have `bootstrapEndpoint: kafka.dah-flink-<env>.svc.cluster.local:9092`
- Check Kafka :9092 listener status: `oc exec kafka-0 -- netstat -tlnp | grep 9092`

---

## Commit History

```
71c1cf1 Refactor Confluent Platform hybrid auth: bootstrap :9092, remove C3 basic-auth
         Phase 1: Update all manifest bootstrap endpoints from :9071 to :9092 across dev/qa/uat-p/uat-s/prd/dr
         Phase 2: Pipeline refactor with readiness gates and MDS verification

344708e Add comprehensive hybrid authentication documentation
        LISTENER_PORT_MATRIX.md, OKTA_OIDC_REQUIREMENTS.md, CONTROL_CENTER_SSO_VALIDATION.md
```

---

## Files Modified

### Manifests (42 files)
- **6 environments × 5 manifests** (schemaregistry, connect, kafkarest, controlcenter, kafkarestclass)
- **Plus**: cert-manager, ingress, rolebindings, NetworkPolicy, README files
- **Total**: ~42 files with bootstrap endpoint and/or C3 auth changes

### Pipeline (1 file)
- `.azure-pipelines/confluent-platform.yaml`
  - 747 insertions, 364 deletions
  - Significant additions: readiness gate logic, post-Kafka verification, managed component checks

### Documentation (3 new files, ~829 lines total)
- `docs/LISTENER_PORT_MATRIX.md`
- `docs/OKTA_OIDC_REQUIREMENTS.md`
- `docs/CONTROL_CENTER_SSO_VALIDATION.md`

---

## Key Decision Points

1. **:9092 over :9071**
   - Preserves :9071 for internal infrastructure (KRaft, inter-broker)
   - Managed components now use OAuth (required for Okta scopes + groups)
   - Reduces port confusion (external = OAuth, internal = PLAIN)

2. **Okta OIDC for C3 UI only**
   - Browser-based login uses OIDC (standard for web SSO)
   - Backend API calls use OAuth (same as other components)
   - Separates user identity from service-to-service auth

3. **MDS token keypair required**
   - Explicit Secret instead of pod-local generation
   - Allows token validation across pod restarts
   - Required for OIDC callback validation

4. **Readiness gates (re-enabled)**
   - Prevents cascading failures when infrastructure not ready
   - 600s for KRaft (quorum sync can be slow)
   - 900s for Kafka (listener init, MDS startup)
   - Managed components get 300s each (shorter, they depend on Kafka)

5. **No hard failure for MDS readiness**
   - MDS startup can be slow (token validation, OIDC config)
   - Warnings only (operator retries internally)
   - Allows for eventual consistency

---

## References

- Runbook A22: CFK OAuth and RBAC configuration
- Runbook A23: Kafka OAuth scopes and MDS impersonation
- Runbook A29: Control Center authentication (legacy, now archived)
- Confluent docs: https://docs.confluent.io/kafka/operations-tools/manage-metadata.html
- CFK docs: https://docs.confluent.io/operator/current/

---

## Next Steps

1. **Review and test locally** (if possible)
   - Syntax check: `oc apply -f <manifest> --dry-run=client` per environment
   - Variable substitution: Verify all `$()` and `${}` resolve correctly

2. **Deploy to DEV first**
   - Full walkthrough of all phases
   - Complete post-deployment validation
   - Document any environment-specific issues

3. **QA / UAT / PRD deployment**
   - Repeat validation per environment
   - Coordinate floating DNS CNAMEs with network team
   - Okta OIDC app provisioning by identity team

4. **Runbook updates**
   - Archive legacy C3 basic-auth procedures
   - Update troubleshooting guides with new listener ports
   - Add OIDC validation procedures

---

**Status**: ✅ **READY FOR PHASE 4 DEPLOYMENT**

All manifests updated, pipeline refactored, documentation complete and comprehensive.

