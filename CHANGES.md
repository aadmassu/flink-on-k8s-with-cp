# DEV Two-Account Control Center Identity — Final Corrected Implementation

## Overview

DEV Confluent Platform now enforces a two-account Control Center identity model, matching the working VM CP deployment. This implementation separates machine-to-machine service identity (oauth-controlcenter) from interactive user SSO (oauth-mds-sso), with executable validation at every stage.

**Scope:** DEV only. QA, UAT, PRD, and DR unchanged.

## Key Validation Approach

All validation is **machine-executable**, never relying on grep line-proximity or manual inspection:

1. **Pipeline Safeguards (confluent-platform.yaml)**
   - Client ID validation with exact jsonpath queries
   - Secret structure validation with dotted-key escaping
   - YAML-aware manifest validation (Python 3.6 + PyYAML)

2. **Manual Diagnostic Validation (ad-hoc-oc-scripts.sh)**
   - Complete JWT claim validation (not just token existence)
   - Broker-side correlation (pod IP + MDS 401 detection)
   - Fail-fast on missing required resources (not SKIP)

## Architecture: Two-Account Identity Model

### Account 1: Machine-to-Machine Service Identity (oauth-controlcenter)
- **ClientId:** 0oa1ov6h5mwmQTCKI358
- **Used by:** Control Center, Schema Registry, Connect, Kafka, MDS RBAC ops
- **Secret Keys:** clientId, clientSecret, bearer.txt

### Account 2: Interactive SSO Identity (oauth-mds-sso)
- **ClientId:** 0oa1o0ea1m26pITBQ358
- **Used by:** Kafka MDS for browser-based OIDC login (Control Center UI)
- **Secret Keys:** clientId, clientSecret, oidcClientSecret.txt

## Manifest Configuration

### kafka.yaml (spec.services.mds.provider.sso)
```yaml
clientCredentials:
  secretRef: oauth-mds-sso
configurations:
  issuer: https://myapps.firstcitizens.com/oauth2/default
  audience: "Confluent,account,api://default"
  authorizeBaseEndpointUri: https://myapps.firstcitizens.com/oauth2/default/v1/authorize
  tokenBaseEndpointUri: https://myapps.firstcitizens.com/oauth2/default/v1/token
  jwksEndpointUri: https://myapps.firstcitizens.com/oauth2/default/v1/keys
  groupsClaimName: dahDev_groups
  subClaimName: sub
  groupsClaimScope: 11547.DAH(Dev)
  refreshToken: true
```

### controlcenter.yaml
- All machine dependencies (Kafka, MDS, SR, Connect) use oauth-controlcenter
- No basic-auth on MDS/UI login
- ssoProtocol: oidc (browser-only, no fallback)

### rolebindings.yaml
- controlcenter-systemadmin principal: 0oa1ov6h5mwmQTCKI358 (machine identity, not SSO)
- Kafka MDS impersonation includes User:0oa1ov6h5mwmQTCKI358

## Pipeline Implementation

### confluent-platform.yaml Changes

**1. DEV Client ID Safeguards (create-prereqs)**
```bash
EXPECTED_C3_ID=0oa1ov6h5mwmQTCKI358
EXPECTED_SSO_ID=0oa1o0ea1m26pITBQ358
# Fail unless OAUTH_C3_ID == EXPECTED_C3_ID
# Fail unless OAUTH_MDS_SSO_ID == EXPECTED_SSO_ID
# Fail unless the two IDs differ
```

**2. oauth-mds-sso Secret Structure Validation (create-prereqs)**
```bash
# Validate each key explicitly with escaping:
oc get secret oauth-mds-sso -o jsonpath='{.data.clientId}'       # Must be nonempty
oc get secret oauth-mds-sso -o jsonpath='{.data.clientSecret}'   # Must be nonempty
oc get secret oauth-mds-sso -o jsonpath='{.data.oidcClientSecret\.txt}'  # Must be nonempty
```

**3. DEV Static Manifest Validation (pre-flight)**
```bash
python3 .azure-pipelines/scripts/validate_dev_two_account_manifest.py $ENV_DIR
```

This Python script validates:
- kafka.yaml: exact YAML paths (not grep)
- controlcenter.yaml: exact YAML paths (not grep)
- rolebindings.yaml: exact document + field validation

**4. Uninstall**
```bash
oc delete secret oauth-controlcenter oauth-mds-sso --ignore-not-found
```

### validate-confluent-platform.yaml (Preserved)

Manual execution: `executeAdHocScript=true` parameter

### ad-hoc-oc-scripts.sh Extensions

**Section A: Kubernetes Secrets**
- Both oauth secrets exist with correct Client IDs
- No secret values printed

**Section B: Live Kafka MDS SSO**
- provider.sso.clientCredentials.secretRef == oauth-mds-sso
- All SSO configurations live (groupsClaimName, subClaimName, groupsClaimScope, refreshToken)

**Section C: Live Control Center Dependencies**
- Kafka, MDS, Schema Registry, Connect all use oauth-controlcenter
- ssoProtocol == oidc
- No MDS basic-auth

**Section D: Rolebinding Status**
- spec.principal.name and status.principal match
- role == SystemAdmin
- app-ready condition == True

**Section E: Machine-Token Validation (COMPLETE)**
- Request fresh token from oauth-controlcenter
- Decode JWT using Python 3.6 stdlib
- **Validate all claims:**
  - sub == 0oa1ov6h5mwmQTCKI358
  - cid/client_id == 0oa1ov6h5mwmQTCKI358
  - iss == https://myapps.firstcitizens.com/oauth2/default
  - scp/scope contains 11547.DAH(Dev)
  - exp exists and is later than now
- **Fail if any claim invalid**
- Report dahDev_groups presence (not root-cause)

**Section F: Runtime Logs + Broker Correlation**
- Collect C3 pod IP
- Search C3 logs for auth errors (not SKIP on missing pod, FAIL)
- **Collect broker logs and correlate:**
  - For kafka-0, kafka-1, kafka-2: detect MDS 401 responses
  - If C3 pod IP found + GET /security/1.0/authenticate + 401: FAIL
  - Otherwise: PASS

## New Helper Scripts

### validate_dev_two_account_manifest.py

YAML-aware validation of DEV manifest structure. Validates exact paths:

```python
# Kafka SSO configurations
spec.services.mds.provider.sso.clientCredentials.secretRef == oauth-mds-sso
spec.services.mds.provider.sso.configurations.subClaimName == sub
spec.services.mds.provider.sso.configurations.groupsClaimName == dahDev_groups
spec.services.mds.provider.sso.configurations.groupsClaimScope == 11547.DAH(Dev)
spec.services.mds.provider.sso.configurations.refreshToken == true

# Control Center dependencies
spec.dependencies.kafka.authentication.jaasConfig.secretRef == oauth-controlcenter
spec.dependencies.mds.authentication.oauth.secretRef == oauth-controlcenter
spec.dependencies.schemaRegistry.authentication.oauth.secretRef == oauth-controlcenter
every spec.dependencies.connect[*].authentication.oauth.secretRef == oauth-controlcenter
spec.dependencies.mds.ssoProtocol == oidc
spec.dependencies.mds.authentication.basic is absent

# Rolebinding
Find ConfluentRolebinding where:
  metadata.name == controlcenter-systemadmin
  spec.principal.name == 0oa1ov6h5mwmQTCKI358
  spec.principal.type == user
  spec.role == SystemAdmin
```

## Deployment Sequence

### Clean Install
1. create-prereqs: Validate Client IDs (DEV)
2. create-prereqs: Create oauth-controlcenter and oauth-mds-sso
3. create-prereqs: Validate oauth-mds-sso structure (DEV)
4. pre-flight: Run Python YAML validation (DEV)
5. Phase 1a: KRaft Controller
6. Phase 1b: Kafka + KafkaRestClass
7. Phase 1c: RBAC rolebindings
8. Phase 2: Schema Registry, Connect, REST Proxy, Control Center

### Manual Post-Deployment Validation
```bash
./validate-confluent-platform.yaml with executeAdHocScript=true
```

The ad-hoc script validates all 6 sections (A-F) with fail-fast behavior.

## Testing Checklist

- [ ] **Clean install (DEV):** Pipeline validates Client IDs before creation
- [ ] **Create-prereqs:** oauth-mds-sso contains oidcClientSecret.txt
- [ ] **Pre-flight:** Python YAML validation passes all checks
- [ ] **Manual validation:** Run ad-hoc script with executeAdHocScript=true
- [ ] **Token validation:** JWT claims all validated (sub, cid, iss, scp, exp)
- [ ] **Broker correlation:** No 401 responses to current C3 pod IP
- [ ] **Control Center:** Web UI loads, OIDC login works
- [ ] **Uninstall:** Both oauth secrets deleted

## Key Implementation Decisions

1. **Deterministic validation only** — All checks use YAML parser, exact jsonpath, or Python stdlib. No grep line-proximity guessing.

2. **Fail-fast on missing resources** — If controlcenter-0 pod missing, validation FAILs (not SKIPs).

3. **Complete JWT validation** — All claims validated (not just token existence), including expiration.

4. **Broker-side correlation** — Detects if brokers are rejecting the current C3 pod IP with 401 responses.

5. **Pipeline separation preserved** — confluent-platform.yaml does not call ad-hoc script. Manual invocation only.

6. **No secret values exposed** — Client secrets, tokens, and bearer tokens never printed to logs.

## Files in This Deliverable

- `.azure-pipelines/confluent-platform.yaml` — With safeguards + static validation
- `.azure-pipelines/validate-confluent-platform.yaml` — Preserved unchanged
- `.azure-pipelines/scripts/ad-hoc-oc-scripts.sh` — Extended with sections A-F
- `.azure-pipelines/scripts/validate_dev_two_account_manifest.py` — YAML-aware validation
- `apps/confluent-platform/dev/kafka.yaml` — Corrected SSO configurations
- `apps/confluent-platform/dev/controlcenter.yaml` — Verified correct
- `apps/confluent-platform/dev/rbac/rolebindings.yaml` — Verified correct
- `CHANGES.md` — This document
- `VALIDATION_RESULTS.txt` — Machine-executed validation results
