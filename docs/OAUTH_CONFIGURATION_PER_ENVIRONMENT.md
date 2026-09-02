# OAuth Configuration Per Environment

Each environment uses its own Okta client IDs and scopes. Do not copy between environments.

## DEV

**Okta Scope:** `11547.DAH(Dev)`  
**Groups Claim:** `dahDev_groups`  
**Okta Issuer:** `https://myapps.firstcitizens.com/oauth2/default`

**Okta Client IDs:**

| Component | Client ID | Used in |
|-----------|-----------|---------|
| Kafka Broker | `0oa1owhtq2olDZWwf358` | kafka.yaml external listener, rolebindings superUsers |
| Schema Registry | `0oa1owiage2MyoHdt358` | Variable group: `dev-oauth-schemaregistry-client-id` |
| Kafka Connect | `0oa1owi0yntGMBvPS358` | Variable group: `dev-oauth-connect-client-id` |
| Kafka REST Proxy | `0oa1owi3wkxJS3b3b358` | Variable group: `dev-oauth-kafkarest-client-id` |
| Control Center | `0oa1ov6h5mwmQTCKI358` | Variable group: `dev-oauth-controlcenter-client-id` |
| MDS (API) | `0oa1owhtq2olDZWwf358` | Variable group: `dev-oauth-mds-rest-client-id` |
| MDS (SSO/Browser) | `0oa1o0ea1m26pITBQ358` | Variable group: `dev-oauth-mds-sso-client-id` |

**Status:** ✅ Already in kafka.yaml and kraftcontroller.yaml. Live.

---

## QA

**Okta Scope:** `11547.DAH(QA)` (currently shows Dev — needs update)  
**Groups Claim:** `dahQA_groups` (currently shows Dev — needs update)  
**Okta Issuer:** `https://myapps.firstcitizens.com/oauth2/default`

**Okta Client IDs (to be confirmed):**

| Component | Client ID | Source |
|-----------|-----------|--------|
| Kafka Broker | ? | Confirm with infrastructure |
| Schema Registry | ? | Confirm with infrastructure |
| Kafka Connect | ? | Confirm with infrastructure |
| Kafka REST Proxy | ? | Confirm with infrastructure |
| Control Center | ? | Confirm with infrastructure |
| MDS (API) | ? | Confirm with infrastructure |
| MDS (SSO/Browser) | ? | Confirm with infrastructure |

**Status:** ⚠️ Manifests have DEV configuration. Need to:
1. Confirm QA OAuth client IDs with infrastructure
2. Update `apps/confluent-platform/qa/kafka.yaml` with correct IDs, scope, and groups claim
3. Update `apps/confluent-platform/qa/kraftcontroller.yaml` if needed

---

## UAT-P (UAT Primary)

**Okta Scope:** `11547.DAH(UAT)`  
**Groups Claim:** `dahUAT_groups`  
**Okta Issuer:** `https://myapps.firstcitizens.com/oauth2/default`

**Okta Client IDs (reference from UAT broker config):**

| Component | Client ID | Source |
|-----------|-----------|--------|
| Kafka Broker | `0oa1owjyrmdJ4KqUt358` | cp-confluent/uat broker config |
| Schema Registry | ? | Confirm with infrastructure |
| Kafka Connect | ? | Confirm with infrastructure |
| Kafka REST Proxy | ? | Confirm with infrastructure |
| Control Center | ? | Confirm with infrastructure |
| MDS (API) | `0oa1owjyrmdJ4KqUt358` | cp-confluent/uat broker config |
| MDS (SSO/Browser) | `0oa1o55bn1mSPf0HY358` | cp-confluent/uat broker config |

**Status:** ⚠️ Manifests inherit DEV configuration. Need to:
1. Confirm remaining OAuth client IDs with infrastructure
2. Update `apps/confluent-platform/uat-p/kafka.yaml` with correct IDs, scope, and groups claim
3. Update `apps/confluent-platform/uat-p/kraftcontroller.yaml` if needed

---

## UAT-S (UAT Secondary)

**Same as UAT-P** — uses same Okta realm and client IDs.

**Status:** ⚠️ Manifests inherit DEV configuration. Need to:
1. Update `apps/confluent-platform/uat-s/kafka.yaml` with UAT client IDs, scope, and groups claim (same as uat-p)
2. Update `apps/confluent-platform/uat-s/kraftcontroller.yaml` if needed

---

## PRD (Production)

**Okta Scope:** `11547.DAH(PD)`  
**Groups Claim:** `dahPD_groups`  
**Okta Issuer:** `https://myapps.firstcitizens.com/oauth2/default`

**Okta Client IDs (to be provided):**

| Component | Client ID | Source |
|-----------|-----------|--------|
| Kafka Broker | ? | Ayu will provide |
| Schema Registry | ? | Ayu will provide |
| Kafka Connect | ? | Ayu will provide |
| Kafka REST Proxy | ? | Ayu will provide |
| Control Center | ? | Ayu will provide |
| MDS (API) | ? | Ayu will provide |
| MDS (SSO/Browser) | ? | Ayu will provide |

**Status:** ⚠️ Manifests inherit DEV configuration. Need to:
1. Update `apps/confluent-platform/prd/kafka.yaml` with correct IDs, scope, and groups claim
2. Update `apps/confluent-platform/prd/kraftcontroller.yaml` if needed

---

## DR (Disaster Recovery)

**Same as PRD** — mirrors production Okta realm and client IDs.

**Status:** ⚠️ Manifests inherit DEV configuration. Need to:
1. Update `apps/confluent-platform/dr/kafka.yaml` with PRD client IDs, scope, and groups claim
2. Update `apps/confluent-platform/dr/kraftcontroller.yaml` if needed

---

## Where to Make Changes

For each environment, update:

**kafka.yaml:**
- `listeners.external.oauthSettings.audience` (same for all: `Confluent,account,api://default`)
- `listeners.external.oauthSettings.expectedIssuer` (same for all: `https://myapps.firstcitizens.com/oauth2/default`)
- `listeners.external.oauthSettings.groupsClaimName` (environment-specific: `dahDev_groups` → `dahQA_groups` → `dahUAT_groups` → `dahPD_groups`)
- `listeners.external.oauthSettings.scope` (environment-specific: `11547.DAH(Dev)` → `11547.DAH(QA)` → `11547.DAH(UAT)` → `11547.DAH(PD)`)
- All other `oauthSettings` blocks under `listeners.external` and `services.mds.provider.oauth`
- `authorization.superUsers` (update broker OAuth client ID)
- `configOverrides.server` lines with OAuth settings (scope and endpoint URLs)

**kraftcontroller.yaml:**
- Update `authorization.superUsers` (add correct broker OAuth client ID)

**Variable groups** (Azure DevOps):
- `<env>-oauth-schemaregistry-client-id` / `-client-secret`
- `<env>-oauth-connect-client-id` / `-client-secret`
- `<env>-oauth-kafkarest-client-id` / `-client-secret`
- `<env>-oauth-controlcenter-client-id` / `-client-secret`
- `<env>-oauth-mds-rest-client-id` / `-client-secret`
- `<env>-oauth-mds-sso-client-id` / `-client-secret`

---

## Validation

After updating OAuth configuration:

1. Run YAML validation: `oc apply --dry-run=server -f kafka.yaml`
2. Confirm scopes and group claims match the OAuth realm
3. Confirm all client IDs are in the correct variable groups
