# Control Center OIDC SSO Validation Guide

Last Updated: 2026-08-12  
Purpose: Post-deployment testing of Control Center browser login via Okta OIDC

## Quick Validation (5 min)

### 1. Verify C3 Pod is Running

```bash
ENV=dev  # or qa, uat-p, uat-s, prd, dr
OC_NS="dah-flink-${ENV}"

oc get pod -n "$OC_NS" -l app.kubernetes.io/name=controlcenter

# Expected output:
# NAME                 READY   STATUS    RESTARTS   AGE
# controlcenter-0      1/1     Running   0          5m
```

### 2. Verify Ingress and Floating DNS

```bash
oc get ingress -n "$OC_NS" -l app.kubernetes.io/component=control-center

# Expected: controlcenter-ingress shows HOSTS and READY=True
# Example:
# NAME                         CLASS   HOSTS                                      ADDRESS        READY
# controlcenter-ingress        ...     controlcenter.apps.dv.ocp.fcbint.net       10.x.x.x       True
```

### 3. DNS Connectivity Test

```bash
# From any machine on FCB network (or bastion):
dig controlcenter.apps.dv.ocp.fcbint.net

# Expected: CNAME and A record resolve to floating IP
# dig +short controlcenter.apps.dv.ocp.fcbint.net
# controlcenter.apps.dv.ocp.fcbint.net. 300 IN CNAME <floating-dns>.fcb.com.
# <floating-dns>.fcb.com. 300 IN A 10.x.x.x
```

### 4. TLS Certificate Verification

```bash
# Verify cert-manager issued the certificate:
oc get certificate -n "$OC_NS" controlcenter-ingress-tls

# Expected: READY=True, ISSUER=keyfactor-clusterissuer, AGE should be recent
# NAME                            READY   SECRET                          ISSUER                    AGE
# controlcenter-ingress-tls       True    controlcenter-ingress-tls       keyfactor-clusterissuer   3d
```

### 5. HTTP Redirect Test (No Browser Needed)

```bash
# From your machine:
curl -skI --max-redirs 0 https://controlcenter.apps.dv.ocp.fcbint.net/

# Expected: HTTP 302 Redirect (not 200)
# HTTP/2 302
# location: https://myapps.firstcitizens.com/oauth2/default/v1/authorize?...
# content-length: 0
```

**Interpretation**:
- ✓ **302 with location header** = C3 is running and ready to redirect to Okta
- ✗ **502 Bad Gateway** = C3 pod not healthy (check pod logs, pod restarts)
- ✗ **404** = Ingress routing issue (check Ingress config, HAProxy routes)
- ✗ **SSL_ERROR / certificate issues** = TLS Secret missing (check cert-manager, keystore)

## Full Validation (Manual Browser Test)

### Prerequisites

- Browser with internet access
- FCB network access (or VPN to `myapps.firstcitizens.com`)
- User account is member of `DAH(Dev)`, `DAH(QA)`, etc. Okta group for the target environment

### Step-by-Step

#### 1. Navigate to Control Center URL

```
https://controlcenter.apps.dv.ocp.fcbint.net/
```

**Expected**: Page loads (may show "Loading..." while Kubernetes serves the page)

**If stuck on "Loading..."** (>30 sec):
- Check pod logs: `oc logs -f controlcenter-0 -n dah-flink-dev --all-containers`
- Check if pod is restarting: `oc get pod controlcenter-0 -n dah-flink-dev`

#### 2. Okta Redirect

**Expected**: Browser automatically redirects to:
```
https://myapps.firstcitizens.com/oauth2/default/v1/authorize?...
```

(May not see this if redirect is transparent.)

**If page shows error** like "Invalid redirect URI":
- Okta callback URI mismatch
- Check `kafka.yaml` spec.services.mds.provider.sso.configurations (not documented)
- Check Okta app settings for exact callback URI

#### 3. Okta Login Page

**Expected**: FirstCitizens Okta login page:
```
Username: [_______________]
Password: [_______________]
     [Sign In]
```

**If "Application not found" or "Invalid client"**:
- Okta OIDC app not created or not assigned to your user
- Contact Okta admin; verify you're in `DAH(Dev)` group

#### 4. Enter Credentials

```
Username: your_username
Password: your_password
[Sign In]
```

**Expected**: Okta verifies credentials; redirects back to Control Center.

**If "Invalid credentials"**:
- Credentials are wrong; try again
- If account is disabled, contact FCB identity team

#### 5. Accept Consent (If Prompted)

**Expected**: Okta may ask:
```
"Confluent Control Center — DEV" wants to:
  - View your profile
  - View your email address
  - View your group memberships
         [Allow]
```

**If not shown**: Either already consented, or Okta admin pre-approved the app.

#### 6. Control Center Dashboard

**Expected**: Control Center UI loads with your user info displayed (top-right corner).

```
Control Center — DEV

[Cluster][Brokers][Topics][Schemas][Connectors]

Logged in as: your.email@fcb.com
Groups: DAH(Dev), ...
```

**If redirected back to login page**:
- Session did not establish
- Check C3 pod logs for OIDC validation errors
- Check oauth-mds-sso Secret: `oc get secret oauth-mds-sso -n dah-flink-dev -o yaml`

**If 500 Internal Server Error**:
- C3 application error
- Check pod logs: `oc logs controlcenter-0 -n dah-flink-dev --all-containers | tail -100`

## Automated Validation Commands

### Pod Health

```bash
ENV=dev
OC_NS="dah-flink-${ENV}"

echo "=== C3 Pod Status ==="
oc get pod -n "$OC_NS" -l app.kubernetes.io/name=controlcenter \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.phase}{"\t"}{.status.containerStatuses[0].ready}{"\n"}{end}'

echo "=== C3 Pod Logs (last 50 lines) ==="
oc logs -n "$OC_NS" controlcenter-0 --tail=50 --all-containers=true
```

### Service and Endpoint Check

```bash
echo "=== C3 Service ==="
oc get svc controlcenter -n "$OC_NS"

echo "=== C3 Endpoints ==="
oc get endpoints controlcenter -n "$OC_NS"

echo "=== Ingress Status ==="
oc get ingress controlcenter-ingress -n "$OC_NS" \
  -o jsonpath='{.status.loadBalancer.ingress[0]}'
```

### Secret Validation

```bash
echo "=== oauth-mds-sso Secret (for OIDC) ==="
oc get secret oauth-mds-sso -n "$OC_NS" \
  -o jsonpath='{.data.clientId}' | base64 -d && echo ""
# Should show a client ID like "0oa1xxxxxxxxxxxx"

echo ""
echo "=== mds-token-keypair Secret ==="
oc get secret mds-token-keypair -n "$OC_NS" \
  -o go-template="{{ index .data \"mdsTokenKeyPair.pem\" }}" | base64 -d | head -3
# Should show "-----BEGIN RSA PRIVATE KEY-----"
```

### MDS OIDC Readiness

```bash
echo "=== Testing MDS OIDC endpoint ==="
oc exec -it kafka-0 -n "$OC_NS" -- \
  curl -sk https://localhost:8090/api/v1/metadata/security/1.0/validate

# Expected response (200 OK):
# {"user":"<your email>","groups":["DAH(Dev)","..."]}
```

### Kafka Listeners Verification

```bash
echo "=== Kafka Listener Status ==="
oc exec -it kafka-0 -n "$OC_NS" -- \
  netstat -tlnp 2>/dev/null | grep -E "(9071|9092|8090)"

# Expected output:
# tcp   0  0  0.0.0.0:9071   0.0.0.0:*  LISTEN  1/java
# tcp   0  0  0.0.0.0:9092   0.0.0.0:*  LISTEN  1/java
# tcp   0  0  0.0.0.0:8090   0.0.0.0:*  LISTEN  1/java
```

### Control Center OIDC Configuration

```bash
echo "=== C3 OIDC Configuration (from kafka.yaml) ==="
oc get kafka kafka -n "$OC_NS" \
  -o jsonpath='{.spec.services.mds.provider.sso}' | jq .

# Should show:
# {
#   "clientCredentials": {
#     "secretRef": "oauth-mds-sso"
#   },
#   "configurations": {
#     "issuer": "https://myapps.firstcitizens.com/oauth2/default",
#     "audience": "Confluent,account,api://default",
#     "authorizeBaseEndpointUri": "https://...",
#     ...
#   }
# }
```

## Common Issues and Fixes

### Issue: "Unauthorized — Callback URI mismatch"

**Symptom**: After logging in to Okta, redirected back with "Invalid redirect_uri" error.

**Root cause**: Okta app's configured callback URI doesn't match the URI in Control Center config.

**Fix**:
1. Verify Okta app callback URI: `https://controlcenter.apps.dv.ocp.fcbint.net/api/metadata/security/1.0/oidc/authorization-code/callback`
2. Verify in `kafka.yaml` (if defined — not all versions use this explicit config)
3. Verify Ingress hostname: `oc get ingress controlcenter-ingress -n $OC_NS`
4. Ensure floating DNS CNAME matches (for UAT/PRD)

### Issue: "Client not found" / "Invalid client"

**Symptom**: Okta login page shows "The requested client could not be found."

**Root cause**: oauth-mds-sso Secret has wrong client ID, or Okta app doesn't exist.

**Fix**:
1. Verify Okta OIDC app is created for this environment
2. Check oauth-mds-sso Secret: `oc get secret oauth-mds-sso -n $OC_NS -o jsonpath='{.data.clientId}' | base64 -d`
3. Compare with Okta app Client ID
4. If missing, run pipeline: `action=create-prereqs`

### Issue: "Invalid scopes"

**Symptom**: Okta error: "Invalid value for parameter 'scope'."

**Root cause**: OIDC app doesn't have requested scopes enabled.

**Fix**: In Okta app settings, ensure these scopes are enabled:
- ✓ openid
- ✓ profile
- ✓ email

### Issue: Groups claim missing from token

**Symptom**: C3 shows user is logged in, but no group memberships visible.

**Root cause**: Okta claim not configured, or user not in any groups.

**Fix**:
1. User must be in a group: `DAH(Dev)`, `DAH(QA)`, etc.
2. Okta admin must add claim `dahDev_groups` to OIDC app
3. Claim must be included in ID token (not access token)

### Issue: C3 Pod keeps restarting

**Symptom**: `oc get pod controlcenter-0 -n $OC_NS` shows RESTARTS > 0

**Root cause**: Pod out of memory, license invalid, or TLS cert missing.

**Diagnosis**:
```bash
oc logs controlcenter-0 -n $OC_NS --previous --all-containers

# Look for:
# - OutOfMemory error
# - License validation failed
# - Certificate not found
```

**Fix**: Check pod logs, adjust resources, redeploy with pipeline.

## Backup: Testing Without Browser

If browser access is not available, simulate the OAuth flow with `curl`:

```bash
# 1. Get OIDC authorization code
AUTHORIZE_URI="https://myapps.firstcitizens.com/oauth2/default/v1/authorize?client_id=<CLIENT_ID>&response_type=code&scope=openid%20profile%20email&redirect_uri=https%3A%2F%2Fcontrolcenter.apps.dv.ocp.fcbint.net%2Fapi%2Fmetadata%2Fsecurity%2F1.0%2Foidc%2Fauthorization-code%2Fcallback"

# (This requires browser interaction for login — can't be fully automated)

# 2. Exchange code for token (if you have the code):
curl -X POST \
  https://myapps.firstcitizens.com/oauth2/default/v1/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "client_id=<CLIENT_ID>" \
  -d "client_secret=<CLIENT_SECRET>" \
  -d "grant_type=authorization_code" \
  -d "code=<AUTH_CODE>" \
  -d "redirect_uri=https%3A%2F%2Fcontrolcenter.apps.dv.ocp.fcbint.net%2Fapi%2Fmetadata%2Fsecurity%2F1.0%2Foidc%2Fauthorization-code%2Fcallback"

# 3. Inspect ID token (JWT):
# Decode the "id_token" from the response using https://jwt.io or:
echo "<ID_TOKEN>" | cut -d'.' -f2 | base64 -d | jq .
# Should show "dahDev_groups" claim with your groups
```

## Summary Checklist

- [ ] C3 pod is running and healthy
- [ ] Ingress has valid TLS certificate
- [ ] Floating DNS resolves to ingress IP
- [ ] `curl -skI https://controlcenter.apps.dv.ocp.fcbint.net/` returns 302 with Okta redirect
- [ ] Browser login completes without errors
- [ ] Logged-in user sees Control Center dashboard
- [ ] User identity displayed in top-right corner
- [ ] Group memberships visible (if RBAC enabled)
- [ ] oauth-mds-sso Secret exists and has valid credentials
- [ ] mds-token-keypair Secret exists with RSA key
- [ ] Kafka :8090 MDS endpoint responds to /api/v1/metadata/security/1.0/validate

## References

- OKTA_OIDC_REQUIREMENTS.md — Okta app setup
- LISTENER_PORT_MATRIX.md — Port and listener config
- Runbook A22 — CFK OAuth configuration
