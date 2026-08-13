# Hybrid Authentication Refactor — All Environments

## What Changed

**Kafka internal infrastructure path (inter-broker, internal listener, metrics reporter, KRaft controller):**
- Was: OAuth
- Now: SASL/PLAIN + TLS

**Kafka external listener and managed components (SR, Connect, REST, C3):**
- No change: OAuth + TLS + RBAC

**Admin credential:**
- One per environment: `<env>-sasl-plain-admin-pwd`
- Used for: internal listener, inter-broker, KRaft controller listener, metrics reporter
- Not reused by managed components (they have separate OAuth identities)

## Credential: `sasl-plain-internal` Secret

Created from `<env>-sasl-plain-admin-pwd` variable. Contains five keys (all with same admin password):

```
plain-users.json
kafka-server-listener-internal-plain-users.json
kraftcontroller-server-listener-controller-plain-users.json
plain.txt
plain-interbroker.txt
```

## Manifests Updated

| Environment | kafka.yaml | kraftcontroller.yaml |
|-------------|-----------|-------------------|
| dev | ✅ | ✅ |
| qa | ✅ | ✅ |
| uat-p | ✅ | ✅ |
| uat-s | ✅ | ✅ |
| prd | ✅ | ✅ |
| dr | ✅ | ✅ |

**Changes in each:**
- Internal listener: `type: plain` + `secretRef: sasl-plain-internal`
- KRaft controller dependency: `type: plain` + `secretRef: sasl-plain-internal`
- Metric reporter: `type: plain` + `secretRef: sasl-plain-internal`
- Broker authorization: Added `User:admin` superuser
- Config overrides: Removed internal SASL configs (CFK generates them automatically)

**⚠️ Still needed:**
- OAuth client IDs and scopes per environment (see OAUTH_CONFIGURATION_PER_ENVIRONMENT.md)

## Pipeline

No code changes needed. Pipeline already:
- Requires only `<env>-sasl-plain-admin-pwd`
- Creates `sasl-plain-internal` Secret with five keys
- Does not consume legacy component-specific PLAIN variables

**Legacy variables (no longer used, marked for removal after validation):**
```
<env>-sasl-plain-client-pwd
<env>-sasl-plain-schema-registry-pwd
<env>-sasl-plain-kafka-connect-pwd
<env>-sasl-plain-kafka-rest-pwd
<env>-sasl-plain-control-center-pwd
```

## CyberArk

Onboard one property per environment: `sasl-plain-admin-password`

ExternalSecret manifests exist (commented out, ready to enable) at:
`apps/confluent-platform/<env>/externalsecrets/externalsecrets-hybrid-auth-cyberark-disabled.yaml`

See CYBERARK_SECRETS_REQUIRED.md for full list.

## Deployment Order Per Environment

1. Confirm OAuth client IDs for the environment
2. Update kafka.yaml with correct OAuth IDs, scope, groups claim
3. Onboard CyberArk `sasl-plain-admin-password` property
4. Run pipeline `action=create-prereqs` → verify `sasl-plain-internal` Secret exists
5. Run pipeline `action=install-or-update` with KRaft + Kafka
6. Wait for `cluster-ready=True`
7. Deploy managed components (SR/Connect/REST/C3)

## Validation Checklist

- [ ] OAuth configuration confirmed per environment
- [ ] kafka.yaml and kraftcontroller.yaml updated with correct IDs, scope, claims
- [ ] `sasl-plain-internal` Secret created with five expected keys
- [ ] Kafka and KRaft reach `cluster-ready=True`
- [ ] Managed components deploy without auth errors
- [ ] CyberArk ExternalSecret reports `SecretSynced=True` (if using CyberArk)

## References

- OAUTH_CONFIGURATION_PER_ENVIRONMENT.md — OAuth client IDs and scopes per env
- CYBERARK_SECRETS_REQUIRED.md — CyberArk property list
- PIPELINE_CHANGES_HYBRID_AUTH.md — Pipeline variable groups and validation
- apps/confluent-platform/dev/externalsecrets/externalsecrets-hybrid-auth-cyberark-disabled.yaml — ExternalSecret template (commented out)
