# Okta OIDC App Configuration for Confluent Control Center

Last Updated: 2026-08-12  
Scope: MDS OIDC SSO for Control Center browser login

## Overview

Control Center (C3) uses Okta OIDC for user authentication and group claims in the UI. This document specifies the Okta OIDC application configuration required for each FCB environment (dev, qa, uat-p, uat-s, prd, dr).

## Okta OIDC App Settings

### Authorization Code Flow

The Control Center OIDC callback uses the **OAuth 2.0 Authorization Code Flow** (also called 3-legged OAuth or browser redirect flow).

| Setting | Value |
|---------|-------|
| **Application type** | Web Application (OIDC) |
| **Grant type** | Authorization Code |
| **Token type** | OpenID Connect (not Saml) |

### Base Configuration

#### Issuer / Okta Organization

- **Issuer URL**: `https://myapps.firstcitizens.com/oauth2/default`
  - This is FCB's Okta instance (FirstCitizens organization)
  - Authorization endpoint: `https://myapps.firstcitizens.com/oauth2/default/v1/authorize`
  - Token endpoint: `https://myapps.firstcitizens.com/oauth2/default/v1/token`
  - JWKS endpoint: `https://myapps.firstcitizens.com/oauth2/default/v1/keys`

#### Client Type

- `public` (OIDC flow can be initiated from a browser without a client secret)
  - ~~OR `confidential` with a client secret~~ (depends on Okta security policy)
  - Confluent's MDS documentation recommends `public` for browser flows

### Redirect URIs (By Environment)

The callback URI is where Okta redirects the user after authentication.

| Environment | Callback URI | Notes |
|-----------|--------------|-------|
| **dev** | `https://controlcenter.apps.dv.ocp.fcbint.net/api/metadata/security/1.0/oidc/authorization-code/callback` | Dev cluster wildcard DNS |
| **qa** | `https://controlcenter.apps.qa.ocp.fcbint.net/api/metadata/security/1.0/oidc/authorization-code/callback` | QA cluster wildcard DNS |
| **uat-p** | `https://controlcenter.apps.uat.ocp.fcbint.net/api/metadata/security/1.0/oidc/authorization-code/callback` | UAT-P floating DNS CNAME |
| **uat-s** | `https://controlcenter.apps.uat.ocp.fcbint.net/api/metadata/security/1.0/oidc/authorization-code/callback` | UAT-S (same floating DNS as UAT-P) |
| **prd** | `https://controlcenter.apps.prod.ocp.fcbint.net/api/metadata/security/1.0/oidc/authorization-code/callback` | PRD floating DNS CNAME |
| **dr** | `https://controlcenter.apps.dr.ocp.fcbint.net/api/metadata/security/1.0/oidc/authorization-code/callback` | DR floating DNS CNAME |

> **Important**: The callback URI is stored in both:
> 1. Okta app configuration (exact match required)
> 2. `kafka.yaml` spec.services.mds.provider.sso.configurations (Confluent-side)

### Scope Configuration

The OIDC scope determines which user claims are returned and whether the app can refresh tokens.

```
openid profile email
```

#### Individual Scopes

| Scope | Provides |
|-------|----------|
| `openid` | Standard OIDC scope; returns `sub` (subject) claim |
| `profile` | User profile info: name, given_name, family_name, etc. |
| `email` | Email address claim |

### Token Configuration

#### Refresh Token

- **Enable Refresh Token**: `true`
  - Allows MDS to obtain a new access token without user re-authentication when the initial token expires
  - Configured in `kafka.yaml` spec.services.mds.provider.sso.configurations.refreshToken: true

#### Token Lifetime

- **Access Token lifetime**: 1 hour (default) — Okta OIDC standard
- **Refresh Token lifetime**: 7 days (default) — or per Okta organization policy

### Groups Claim Configuration

Control Center displays user groups based on the `dahDev_groups`, `dahQA_groups`, etc. claim returned by Okta.

#### Claim Name Mapping

| Environment | Groups Claim Name | Use Case |
|-----------|------------------|----------|
| **dev** | `dahDev_groups` | DEV environment grouping for C3 role-based views |
| **qa** | `dahQA_groups` | QA environment |
| **uat-p** | `dahUAT_groups` | UAT (both -p and -s environments) |
| **uat-s** | `dahUAT_groups` | UAT (both -p and -s environments) |
| **prd** | `dahProd_groups` | Production |
| **dr** | `dahProd_groups` | Disaster Recovery (same as PRD) |

#### Claim Delivery Method

- **Token claim**: The groups claim should be included in the ID token returned by Okta
- **Okta app configuration**: Add a claim filter in the app's token configuration
  - Claim name: `dahDev_groups` (or environment-specific variant)
  - Value: User's membership in the corresponding Okta group
  - Token type: ID token

#### Okta Group Membership Prerequisite

Users must be members of the corresponding Okta security groups:

- `DAH(Dev)` — for DEV environment access
- `DAH(QA)` — for QA environment access
- `DAH(UAT)` — for UAT environment access (uat-p and uat-s)
- `DAH(Prod)` — for PRD and DR environment access

> Users can be members of multiple groups; the claim returns all matching group names.

### Subject Claim Configuration

The subject claim (`sub`) uniquely identifies the user to MDS for RBAC decisions.

| Setting | Value | Notes |
|---------|-------|-------|
| **Subject Claim** | `email` | Use email address as the durable user identity |
| **Alternative** | `sub` (Okta UID) | More stable if user email changes; less human-readable |

**Recommendation**: Use `email` for human readability in logs and audit trails. Use `sub` if email-change portability is critical.

## Pre-Deployment Checklist

- [ ] Okta OIDC app created in `https://myapps.firstcitizens.com`
- [ ] App assigned to all relevant user groups (`DAH(Dev)`, `DAH(QA)`, etc.)
- [ ] Callback URI configured exactly as listed above (no trailing slashes, case-sensitive)
- [ ] Redirect URIs saved (Okta app → General tab → Allowed grant types → Allowed redirect URIs)
- [ ] Groups claim configured to return `dahDev_groups` / `dahQA_groups` / etc.
- [ ] Refresh Token enabled in token settings
- [ ] Client ID and Client Secret generated
- [ ] Credentials stored in Azure DevOps variable group:
  - `<env>-oauth-mds-sso-client-id`
  - `<env>-oauth-mds-sso-client-secret`

## Post-Deployment Validation

After deploying Confluent Platform, verify OIDC flow:

### Test 1: Browser Login (Manual)

```bash
# Open in a browser (must be on FCB network or VPN):
https://controlcenter.apps.dv.ocp.fcbint.net/

# You should:
# 1. See Control Center login page
# 2. Click "Log in with Okta" (or similar button)
# 3. Be redirected to myapps.firstcitizens.com login
# 4. Enter your FCB username and password
# 5. Accept consent screen (if prompted)
# 6. Be redirected back to Control Center
# 7. See Control Center UI with your user name and groups displayed
```

### Test 2: Token Introspection (Automated)

```bash
# From a pod in the cluster:
oc exec -it kafka-0 -c kafka -n dah-flink-dev -- bash

# Inside the pod:
curl -sk https://localhost:8090/api/v1/metadata/security/1.0/validate

# Expected response (200 OK with your user identity):
# { "user": "your.email@fcb.com", "groups": ["DAH(Dev)", ...] }
```

### Test 3: Kafka broker OAuth listener

```bash
# Verify Kafka is accepting OAuth connections on :9092:
oc exec -it kafka-0 -c kafka -n dah-flink-dev -- bash

# Inside the pod:
netstat -tlnp | grep 9092

# Expected: tcp LISTEN 0.0.0.0:9092 (pod IP)
```

### Test 4: Schema Registry connection

```bash
# Verify SR can authenticate to Kafka via :9092:
oc logs -f schemaregistry-0 -n dah-flink-dev --all-containers | grep -i "connected\|oauth\|9092"

# Expected: Logs show successful OAuth token exchange and connection to Kafka
```

## Okta OIDC App Creation Steps (Admin Only)

> This section is for Okta administrators provisioning a new OIDC app.

1. **Log in to Okta Admin Console**
   - URL: `https://myapps.firstcitizens.com/admin`
   - Account: admin account for FirstCitizens org

2. **Create OIDC Web Application**
   - Menu: Applications → Applications
   - Button: Create App Integration
   - Platform: Web
   - Sign in method: OIDC — OpenID Connect
   - Application type: Web Application
   - Click: Next

3. **General Settings**
   - Application name: `Confluent Control Center — <Environment>` (e.g., "Confluent Control Center — DEV")
   - Redirect URIs:
     ```
     https://controlcenter.apps.dv.ocp.fcbint.net/api/metadata/security/1.0/oidc/authorization-code/callback
     ```
   - Allowed grant types:
     - ✓ Authorization Code
     - ☑ Refresh Token (check this)
   - Controlled access: ☑ Skip group assignment for now (will assign later)
   - Click: Save

4. **Assign App to Groups**
   - Tab: Assignments
   - Button: Assign → Assign to Groups
   - Select: `DAH(Dev)` (or `DAH(QA)`, `DAH(UAT)`, `DAH(Prod)` for other envs)
   - Click: Assign

5. **Configure Claims**
   - Tab: Sign On
   - Scroll to: OpenID Connect ID Token
   - Click: Edit (pencil icon)
   - Add claim:
     - **Name**: `dahDev_groups` (or environment-specific)
     - **Value type**: Groups
     - **Filter**: leave blank (or set to a regex if needed)
     - **Include in token type**: ID Token
     - Click: Save
   - Repeat for other groups if needed (e.g., `dahQA_groups`)

6. **Generate Credentials**
   - Tab: General
   - Section: Client Credentials
   - Click: Copy (Client ID)
   - Click: New Client Secret → Copy (Client Secret)
   - Store both securely in Azure DevOps

## Known Issues / Gotchas

### Issue: "Invalid redirect URI" error after login

**Cause**: Okta app's redirect URI doesn't match the browser's post-login callback.

**Fix**:
- Verify URI in Okta app == URI in `kafka.yaml` spec.services.mds.provider.sso.configurations.redirectUri (if defined)
- Check for trailing slashes, case sensitivity, exact query params
- Common mistake: copy-pasting from docs with `<env>` placeholder still in place

### Issue: Groups claim not appearing in token

**Cause**: Claim not configured in Okta app, or user not in any matching groups.

**Fix**:
- Go to Okta app → Sign On → OpenID Connect ID Token
- Verify claim name (`dahDev_groups`) is added
- User must be a member of the corresponding group (`DAH(Dev)`)
- Check user's direct group memberships: Admin Console → People → (user) → Groups

### Issue: "Invalid scope" error

**Cause**: Okta app doesn't have the requested scope enabled.

**Fix**:
- Go to Okta app → General → Scopes
- Ensure `openid`, `profile`, `email` are checked under "OpenID Connect Scopes"

## References

- Okta OIDC documentation: https://developer.okta.com/docs/concepts/oauth-openid/
- Confluent MDS OIDC: https://docs.confluent.io/kafka/operations-tools/manage-metadata.html
- Runbook A22: CFK OAuth configuration
- Runbook A23: MDS OAuth and impersonation

## Contact / Approval

- **Okta Admin**: [Contact Okta administration team or submit SNOW ticket]
- **FCB Security**: For group membership updates (DAH(Dev), DAH(QA), etc.)
- **Container Platform Team**: Rick Mulder (OpenShift / cert-manager) for DNS CNAME registration

