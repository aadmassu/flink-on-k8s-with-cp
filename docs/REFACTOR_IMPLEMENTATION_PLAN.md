# Production Refactor Implementation Plan

**Date:** 2026-08-12  
**Status:** Assessment Complete, Ready for Execution  
**Scope:** All 6 environments, cross-platform consistency

## Critical Findings

### Finding 1: Control Center Basic Authentication Violation

**Current state:** controlcenter.yaml uses basic authentication
```yaml
authentication:
  type: basic
  basic:
    secretRef: controlcenter-basic-auth
```

**Problem:** Violates requirement #7 (SSO-only mandate). Also reuses `OAUTH_C3_ID` + `OAUTH_C3_SECRET` as username:password in the `controlcenter-basic-auth` Secret.

**Action:** Remove all basic-auth. Implement SSO-only via MDS OIDC.

---

### Finding 2: Managed Components Point to PLAIN Listener with OAuth Credentials

**Current state:** All managed components reference `kafka:9071` with OAuth authentication:
```
schemaregistry.yaml:70 — bootstrapEndpoint: kafka:9071, authentication: type=oauth
connect.yaml:65 — bootstrapEndpoint: kafka:9071, authentication: type=oauth
kafkarest.yaml:66 — bootstrapEndpoint: kafka:9071, authentication: type=oauth
controlcenter.yaml:104 — bootstrapEndpoint: kafka:9071, authentication: type=oauth
```

**Problem:** Port 9071 is the internal PLAIN listener (requires SASL/PLAIN auth). OAuth clients cannot use it.

**Evidence:** Kafka listener configuration shows:
- `listeners.internal` → SASL/PLAIN (expected port ~9071)
- `listeners.external` → OAuth (expected port ~9092 or 29092)

**Action:** 
1. Determine exact CFK-generated listener ports via pipeline verification step
2. Update all managed components to use the OAuth listener port
3. Add pipeline validation to catch listener port mismatches

---

### Finding 3: Missing Variable Validation for MDS SSO

**Current state:** Pipeline does not validate `OAUTH_MDS_SSO_ID` and `OAUTH_MDS_SSO_SECRET`

**Problem:** If these variables are missing or empty, the pipeline proceeds silently, creating a broken MDS SSO configuration.

**Action:** Add required variable validation.

---

### Finding 4: Readiness Gates Commented Out

**Current state:** KRaftController and Kafka readiness gates are disabled (commented out).

**Problem:** Deployment proceeds regardless of cluster state, masking failures.

**Action:** Re-enable gates with 10-minute KRaft and 15-minute Kafka timeouts.

---

### Finding 5: ESO Discovery Happens After Variable Validation

**Current state:** Pipeline requires Azure variables for ALL Secrets, even those already managed by ExternalSecret CRs.

**Problem:** Cannot migrate secrets from variables to CyberArk incrementally. Requires all Azure variables simultaneously.

**Action:** Reorder: discover ESO-managed Secrets first, then require only Azure variables for pipeline-managed Secrets.

---

## Implementation Checklist

### Phase 1: Listener Mapping (Foundation)

- [ ] Document expected CFK listener port mapping based on CRD
- [ ] Add pipeline step: collect actual listener ports from running cluster
- [ ] Add pipeline validation: fail if expected PLAIN and OAuth listeners missing
- [ ] Create listener/port/DNS matrix for each environment
- [ ] Determine managed component target port (OAuth listener)

### Phase 2: Control Center SSO Refactor

- [ ] Remove controlcenter.yaml `authentication.type: basic` block entirely
- [ ] Remove `controlcenter-basic-auth` Secret creation from pipeline
- [ ] Remove `C3_BASIC_USER` and `C3_BASIC_PWD` variables from pipeline
- [ ] Remove corresponding Azure Pipeline variables
- [ ] Configure Control Center to delegate to MDS OIDC SSO (if CFK 3.2 CRD supports it)
- [ ] Add pipeline validation: confirm MDS OIDC client configured
- [ ] Document callback URI requirement (no secret values)

### Phase 3: Managed Component Kafka Endpoints

- [ ] Update all managed components to use OAuth listener bootstrap endpoint
- [ ] Verify each component uses correct OAuth Secret
- [ ] Verify no component uses PLAIN credentials
- [ ] Add pipeline validation to cross-check listener types vs auth types

### Phase 4: Variable and ESO Refactor

- [ ] Reorder create-prereqs: ESO discovery → per-Secret validation
- [ ] Add `OAUTH_MDS_SSO_ID` and `OAUTH_MDS_SSO_SECRET` to required variables
- [ ] Add Secret key contract validation (per spec in requirements)
- [ ] Add per-Secret creation logic: if ESO-managed, verify it exists; else create from variables
- [ ] Remove requirement for Azure variables on ESO-managed Secrets

### Phase 5: Readiness Gates and Verification

- [ ] Uncomment and enable KRaftController readiness gate (10-min timeout)
- [ ] Uncomment and enable Kafka readiness gate (15-min timeout)
- [ ] Implement timeout logic: print conditions, pods, events, logs on failure
- [ ] Add MDS readiness verification after Kafka
- [ ] Add Listener Service/endpoint verification before managed components
- [ ] Add per-component readiness gate before its Ingress

### Phase 6: CyberArk Templates

- [ ] Create fully-commented templates for all 14 sensitive Secrets
- [ ] Include per-environment placeholders (namespace, SecretStore, CyberArk key)
- [ ] Include FCB labels in metadata
- [ ] Create CyberArk migration inventory per environment
- [ ] Document CyberArk property names and Kubernetes Secret keys

### Phase 7: Documentation and Matrices

- [ ] Create listener/port/DNS matrix per environment
- [ ] Create Secret contract matrix
- [ ] Create per-environment CyberArk migration inventory
- [ ] Create changelog identifying every modified file
- [ ] Create validation checklist

### Phase 8: Cross-Environment Consistency

- [ ] Apply Phase 1–7 to all 6 environments
- [ ] Verify environment-specific values (namespace, DNS, Okta IDs)
- [ ] Confirm no credentials copied between environments
- [ ] Validate all YAML

### Phase 9: Final Validation

- [ ] Parse every YAML file (check duplicate keys)
- [ ] Validate pipeline YAML structure
- [ ] Validate CRs against CFK 3.2 CRDs
- [ ] Confirm no `REPLACE_WITH_*` placeholders in deployable environments
- [ ] Confirm no QA identity in DEV
- [ ] Confirm no secrets in manifests/docs/code
- [ ] Confirm every Secret has exactly one producer
- [ ] Confirm every Secret producer creates all required keys
- [ ] Confirm OAuth clients point to OAuth listener (not PLAIN)
- [ ] Confirm PLAIN clients point to internal listener (not OAuth)
- [ ] Confirm external exposure uses ClusterIP + HAProxy (not LoadBalancer/NodePort/HTTP Ingress)
- [ ] Confirm Control Center has no basic auth
- [ ] Confirm MDS SSO is configured
- [ ] Confirm readiness gates enabled
- [ ] Confirm Control Center delegates to Okta OIDC

### Phase 10: Packaging

- [ ] Remove macOS metadata (.DS_Store, __MACOSX, ._*)
- [ ] Create clean ZIP with original directory structure
- [ ] Include all documentation and matrices
- [ ] Include changelog
- [ ] Include validation results

---

## Unresolved Infrastructure Dependencies

These require FCB team confirmation:

1. **Actual Kafka Listener Ports:** CFK generates ports based on spec. Exact mapping depends on cluster configuration.
   - Need: Live `oc exec kafka-0 -- grep '^listeners=' /mnt/config/server.properties`

2. **OAuth Listener Bootstrap DNS:** Whether OAuth listener uses floating DNS or per-broker names.
   - Need: Live `oc get kafka kafka -o yaml | grep -A10 externalAccess`

3. **HAProxy Route to OAuth Listener:** How external OAuth clients reach the broker.
   - Need: Rick (FCB infrastructure) confirmation on Route/Service setup

4. **Okta OIDC Callback URI:** Control Center must register exact callback URI with Okta.
   - Need: Current Control Center OIDC callback URI from Okta application config

5. **CFK 3.2 Control Center SSO Schema:** Exact YAML structure for `spec.authentication` when using SSO only.
   - Mitigation: Added `oc explain controlcenter.spec.authentication --recursive` to pipeline validation

---

## Risk Mitigation

| Risk | Mitigation |
|------|-----------|
| Listener port wrong | Pipeline verification step will catch mismatch; manifests document expected ports |
| Managed components can't reach Kafka | Listener/auth type validation in pipeline |
| Control Center OIDC not configured | Pre-validation of OIDC client and MDS readiness before C3 apply |
| ESO partially migrated | Pipeline accepts mix of ESO and variable-backed Secrets; per-Secret logic |
| Credentials leaked | Strict validation; no secret values in output; Secret key contracts |
| Downtime during migration | All changes backward-compatible; readiness gates prevent partial state |

---

## Execution Sequence

1. Start with DEV (validate and test everything)
2. Roll out to QA, UAT-P, UAT-S in parallel (same manifests, different credentials)
3. Roll out to PRD/DR (additional validation gates for production)

---

## Estimated Effort

- Listener mapping: 2 hours (requires cluster verification)
- Control Center SSO refactor: 3 hours
- Managed component updates: 2 hours
- Variable/ESO refactor: 4 hours
- Readiness gates: 3 hours
- CyberArk templates: 2 hours
- Documentation/matrices: 2 hours
- Cross-environment: 3 hours
- Validation: 2 hours
- Packaging: 1 hour

**Total: ~24 hours of focused work**

**Timeline: Ready for execution (awaiting cluster access for listener verification)**

---

## Next Steps

Confirm:

1. [ ] Proceed with full execution?
2. [ ] Have live cluster access for listener verification, or proceed with validation steps documented for post-deployment?
3. [ ] For DEV Okta OIDC: Is callback URI registered? What is it?
4. [ ] CFK 3.2 Control Center CRD — use OIDC SSO or fallback to different approach?

