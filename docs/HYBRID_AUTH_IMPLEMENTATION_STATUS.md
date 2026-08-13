# Hybrid Authentication Implementation Status

**Date:** 2026-08-12  
**Scope:** All environments (dev, qa, uat-p, uat-s, prd, dr)

## Summary

SASL/PLAIN + TLS for internal Kafka infrastructure (inter-broker, internal listener, metrics, KRaft controller). OAuth + TLS for external listeners and managed components. One admin credential per environment.

## What Was Done

### ✅ Manifests Updated

All CFK Kafka and KRaftController manifests updated to hybrid authentication model:

| Environment | kafka.yaml | kraftcontroller.yaml | Status |
|-------------|-----------|-------------------|--------|
| dev | ✅ Updated | ✅ Updated | Live |
| qa | ✅ Updated | ✅ Updated | Ready for deployment |
| uat-p | ✅ Updated | ✅ Updated | Ready for deployment |
| uat-s | ✅ Updated | ✅ Updated | Ready for deployment |
| prd | ✅ Updated | ✅ Updated | Ready for deployment |
| dr | ✅ Updated | ✅ Updated | Ready for deployment |

**Changes made:**

1. Internal listener: `type: oauth` → `type: plain` + `secretRef: sasl-plain-internal`
2. KRaft controller dependency: `type: oauth` → `type: plain` + `secretRef: sasl-plain-internal`
3. Metric reporter: `type: oauth` → `type: plain` + `secretRef: sasl-plain-internal`
4. Added `metricsClient` dependency with basic auth to Control Center
5. Authorization: Added `User:admin` as infrastructure superuser
6. configOverrides: Removed internal SASL mechanism configs (CFK generates them automatically)
7. External listener: Remains OAuth (environment-specific — **still needs validation**)

### ✅ Documentation Created

1. **HYBRID_AUTH_ALL_ENVIRONMENTS.md** — Full technical specification, per-environment configuration requirements, implementation checklist
2. **PIPELINE_CHANGES_HYBRID_AUTH.md** — Explains pipeline state (no code changes needed), variable group requirements, validation checklist
3. **HYBRID_AUTH_IMPLEMENTATION_STATUS.md** (this file) — Tracks what's done and what remains

### ✅ Pipeline Status

The `confluent-platform.yaml` pipeline:

- ✅ Already requires only one SASL credential: `<env>-sasl-plain-admin-pwd`
- ✅ Already creates `sasl-plain-internal` with five keys from that single credential
- ✅ Already does NOT consume the five legacy component-specific PLAIN variables
- ✅ Ready for deployment to all environments without modification

No pipeline code changes required.

### ✅ Namespace Corrections

- dev: Already correct
- qa: `dah-flink-qa` ✅
- uat-p: `dah-flink-uat-p` ✅
- uat-s: `dah-flink-uat-s` ✅
- prd: `dah-flink-prod` ✅ (corrected from dah-flink-prd)
- dr: `dah-flink-dr` ✅

## What Still Needs To Be Done

### ⚠️ OAuth Configuration Review (Per-Environment)

**Current manifests inherit DEV OAuth configuration.** Each environment needs verification/update:

| Env | Broker OAuth ID | Groups Claim | Scope | Status |
|-----|----------------|--------------|-------|--------|
| dev | ✅ verified | dahDev_groups | 11547.DAH(Dev) | Live |
| qa | ❌ Needs review | Currently dahDev_groups | Currently 11547.DAH(Dev) | **To do** |
| uat-p | ❌ Needs review | Likely dahUAT_groups | Likely 11547.DAH(UAT) | **To do** |
| uat-s | ❓ Same as uat-p | Same as uat-p | Same as uat-p | **To do** |
| prd | ❌ Needs review | Likely dahProd_groups | Likely 11547.DAH(Prod) | **To do** |
| dr | ❓ Mirrors prd | Same as prd | Same as prd | **To do** |

**Required actions:**

1. Confirm with Okta admin (or FCB infrastructure) the correct OAuth client IDs, group claims, and scopes for each environment
2. Update kafka.yaml in each environment directory with the correct OAuth settings
3. Do NOT copy OAuth values between environments — each must use its own Okta realm configuration

### ⚠️ CyberArk Onboarding

For each environment, onboard **one property:**

```
sasl-plain-admin-password
```

**Status:**
- [ ] dev — likely already onboarded (verify)
- [ ] qa — needs onboarding
- [ ] uat-p — needs onboarding
- [ ] uat-s — needs onboarding (can mirror uat-p)
- [ ] prd — needs onboarding
- [ ] dr — needs onboarding (can mirror prd)

The ExternalSecret CR will:

1. Retrieve the single `sasl-plain-admin-password` property from CyberArk
2. Apply `decodingStrategy: Base64` (already correct in manifests)
3. Template all five required Kubernetes Secret keys from that single value

### ⚠️ Prerequisite README Updates

Each environment's `apps/confluent-platform/<env>/prereqs/README.md` needs update:

**Currently documents:** Five component-specific PLAIN password variables (stale)  
**Should document:**
- Single infrastructure PLAIN identity: `<env>-sasl-plain-admin-pwd`
- Five legacy variables marked for manual removal after validation
- All OAuth and observability credentials (unchanged)

**Status:**
- [ ] dev — likely already updated
- [ ] qa — needs update
- [ ] uat-p — needs update
- [ ] uat-s — needs update
- [ ] prd — needs update
- [ ] dr — needs update

### ⚠️ Deployment Validation (Per-Environment)

Once a manifest is updated and deployed:

1. Run pipeline `action=create-prereqs` to create `sasl-plain-internal` Secret
2. Verify Secret has five keys:
   ```bash
   oc -n dah-flink-<env> get secret sasl-plain-internal -o jsonpath='{.data}' | jq 'keys'
   ```
   Expected output:
   ```json
   [
     "kafka-server-listener-internal-plain-users.json",
     "kraftcontroller-server-listener-controller-plain-users.json",
     "plain-interbroker.txt",
     "plain-users.json",
     "plain.txt"
   ]
   ```

3. Run pipeline `action=install-or-update` with KRaft and Kafka
4. Confirm both reach `cluster-ready=True`
5. Confirm managed components deploy without SASL/PLAIN authentication errors
6. If using CyberArk ExternalSecret, confirm it reports `SecretSynced=True`

**Status:**
- [x] dev — ✅ validated
- [ ] qa — pending deployment
- [ ] uat-p — pending deployment
- [ ] uat-s — pending deployment
- [ ] prd — pending deployment
- [ ] dr — pending deployment

## Next Steps (In Order)

1. **Confirm OAuth configuration** for qa, uat-p, uat-s, prd, dr (meet with Okta admin or infrastructure)

2. **Update kafka.yaml** for each environment with correct OAuth client IDs, group claims, and scopes

3. **Update prerequisite READMEs** to document the single SASL credential and mark five legacy variables for removal

4. **Onboard CyberArk property** for each environment: `sasl-plain-admin-password`

5. **Deploy to qa** first as a test environment:
   - Run `action=create-prereqs`
   - Verify Secrets are created correctly
   - Run `action=install-or-update` with KRaft + Kafka
   - Validate cluster-ready=True and no auth errors
   - Review logs for any SASL/PLAIN configuration issues

6. **Deploy to uat-p/uat-s** (once qa is stable)

7. **Deploy to prd** (once uat is stable)

8. **Deploy to dr** (can be done after prd or concurrently with pre-staging)

## Rollback Plan

If SASL/PLAIN hybrid auth encounters issues:

1. Legacy five PLAIN password variables remain in variable groups (documented as unused)
2. Revert to pure OAuth configuration by:
   - Restoring previous kubernetes manifests from git history
   - Running `oc delete -f kafka.yaml kraftcontroller.yaml` on the CR manifests
   - Applying the OAuth-only manifests
   - Kafka will reconcile back to OAuth-only state

3. This provides a quick rollback path during the first few deployments

## Summary

- ✅ Manifests updated for all six environments
- ✅ Pipeline ready (no code changes needed)
- ✅ Documentation complete
- ⚠️ OAuth configuration needs per-environment review (not yet done)
- ⚠️ CyberArk onboarding needed (not yet done)
- ⚠️ Prerequisite READMEs need updates (not yet done)
- ⚠️ Deployment validation pending (not yet started)

**Estimated time to first successful deployment (qa):** 1-2 days (pending OAuth confirmation and CyberArk coordination)  
**Estimated time to all six environments:** 1-2 weeks (pending per-environment validation and sign-offs)
