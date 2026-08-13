# Hybrid Authentication Refactor — All Environments (dev, qa, uat-p, uat-s, prd, dr)

## Decision

Implement a unified hybrid authentication model across all six Confluent Platform environments:

| Communication path                                  | Authentication                                      |
| --------------------------------------------------- | --------------------------------------------------- |
| Kafka internal listener                             | SASL/PLAIN over TLS                                 |
| Broker-to-broker communication                      | SASL/PLAIN over TLS                                 |
| KRaft controller listener                           | SASL/PLAIN over TLS                                 |
| Kafka-to-KRaft controller communication             | SASL/PLAIN over TLS                                 |
| Broker metrics reporter using the internal listener | SASL/PLAIN over TLS                                 |
| Schema Registry                                     | Existing environment-specific OAuth identity + RBAC |
| Kafka Connect                                       | Existing environment-specific OAuth identity + RBAC |
| Kafka REST Proxy                                    | Existing environment-specific OAuth identity + RBAC |
| Control Center                                      | Existing environment-specific OAuth identity + RBAC |
| Kafka external application listener                 | OAuth over TLS                                      |
| Approved B2B/FIS clients                            | Dedicated mTLS listener when approved               |

## Credential Model

One SASL/PLAIN identity per environment:

```text
admin
```

Corresponding Azure DevOps variable per environment:

```text
<env>-sasl-plain-admin-pwd
```

**Do not** reuse this password for Schema Registry, Connect, REST Proxy, Control Center, application clients, Prometheus, Alertmanager, MDS OAuth, or Control Center SSO. Those consumers already have their own OAuth or Basic Auth identities.

## Legacy Pipeline Variables

The following variables are now **Legacy/unused** after hybrid migration:

```text
<env>-sasl-plain-client-pwd
<env>-sasl-plain-schema-registry-pwd
<env>-sasl-plain-kafka-connect-pwd
<env>-sasl-plain-kafka-rest-pwd
<env>-sasl-plain-control-center-pwd
```

**Do not delete** these variables automatically. Mark them for manual removal after validation to provide rollback safety during first deployment.

The pipeline **no longer requires or consumes** these variables. The `sasl-plain-internal` Secret is created exclusively from the single `<env>-sasl-plain-admin-pwd` value.

## Secret Structure: `sasl-plain-internal`

The `sasl-plain-internal` Secret must contain exactly these five keys, all with the same admin password:

```text
plain-users.json
kafka-server-listener-internal-plain-users.json
kraftcontroller-server-listener-controller-plain-users.json
plain.txt
plain-interbroker.txt
```

Each JSON file contains:

```json
{
  "admin": "<env-specific-admin-password>"
}
```

Each property file contains:

```text
username=admin
password=<env-specific-admin-password>
```

**Do not create:**
- `kafka-server-listener-external-plain-users.json` (external listener uses OAuth)
- `schemaregistry-client-plain.txt` (uses OAuth)
- `connect-client-plain.txt` (uses OAuth)
- `kafkarestproxy-client-plain.txt` (uses OAuth)
- `controlcenter-client-plain.txt` (uses OAuth)

## CyberArk Integration

Onboard **one property per environment:**

```text
sasl-plain-admin-password
```

Use the environment's existing SecretStore and environment-specific CyberArk remote key.

The disabled ExternalSecret will retrieve that property and template all five required Kubernetes Secret keys.

**Do not onboard** the five legacy component PLAIN passwords.

## Manifest Changes

### Kafka Listener Configuration

**Internal listener (SASL/PLAIN):**

```yaml
listeners:
  internal:
    authentication:
      type: plain
      jaasConfig:
        secretRef: sasl-plain-internal
    tls:
      enabled: true
      secretRef: kafka-tls
```

**External listener (OAuth — environment-specific):**

```yaml
listeners:
  external:
    authentication:
      type: oauth
      jaasConfig:
        secretRef: oauth-broker
      oauthSettings:
        audience: "Confluent,account,api://default"
        expectedIssuer: <env-specific-okta-issuer>
        groupsClaimName: <env-specific-groups-claim>
        subClaimName: sub
        jwksEndpointUri: <env-specific-jwks-uri>
        tokenEndpointUri: <env-specific-token-uri>
        scope: <env-specific-scope>
        # ... timeout settings
    tls:
      enabled: true
      secretRef: kafka-tls
```

### KRaft Controller Configuration

**Controller listener (SASL/PLAIN):**

```yaml
listeners:
  controller:
    tls:
      enabled: true
    authentication:
      type: plain
      jaasConfig:
        secretRef: sasl-plain-internal
```

**Kafka-to-controller dependency:**

```yaml
dependencies:
  kRaftController:
    clusterRef:
      name: kraftcontroller
    controllerListener:
      authentication:
        type: plain
        jaasConfig:
          secretRef: sasl-plain-internal
      tls:
        enabled: true
        secretRef: kafka-tls
```

### Broker Metrics Reporter

```yaml
metricReporter:
  enabled: true
  bootstrapEndpoint: kafka.dah-flink-<env>.svc.cluster.local:9071
  tls:
    enabled: true
    secretRef: kafka-tls
  authentication:
    type: plain
    jaasConfig:
      secretRef: sasl-plain-internal
```

### Authorization

```yaml
authorization:
  type: rbac
  superUsers:
    - User:<env-specific-broker-oauth-id>   # infrastructure superuser
    - User:admin                              # SASL/PLAIN infrastructure user
```

### Configuration Overrides

**Do NOT override SASL mechanism for internal listener or controller — CFK generates these automatically from `sasl-plain-internal`.**

Only include environment-specific overrides:

```yaml
configOverrides:
  server:
    # External application listener OAuth (environment-specific)
    - listener.name.external.oauthbearer.sasl.jaas.config=org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginModule required unsecuredLoginStringClaim_sub="thePrincipalName" publicKeyPath="/mnt/secrets/mds-token/mdsPublicKey.pem";

    # Embedded kafkaRest at :8090 (environment-specific OAuth)
    - confluent.kafkarest.security.protocol=SASL_SSL
    - confluent.kafkarest.sasl.mechanism=OAUTHBEARER
    - confluent.kafkarest.sasl.oauthbearer.token.endpoint.url=<env-specific>
    - confluent.kafkarest.sasl.oauthbearer.jwks.endpoint.url=<env-specific>
    - confluent.kafkarest.sasl.oauthbearer.expected.issuer=<env-specific>
    - confluent.kafkarest.sasl.oauthbearer.scope=<env-specific>

    # Broker defaults (non-authentication)
    - log.retention.hours=168
    - log.segment.bytes=1073741824
    # ... other broker settings
```

## Per-Environment OAuth Configuration

Each environment has **unique OAuth credentials and Okta scopes**. Do not copy OAuth values between environments.

### DEV

- **Kafka internal listener:** SASL/PLAIN over TLS
- **Okta client ID (broker):** (see qa/kafka.yaml superUsers)
- **Groups claim:** dahDev_groups
- **Scope:** 11547.DAH(Dev)
- **Okta issuer:** https://myapps.firstcitizens.com/oauth2/default

**Updated manifests:** `apps/confluent-platform/dev/kafka.yaml`, `kraftcontroller.yaml`

### QA

- **Kafka internal listener:** SASL/PLAIN over TLS
- **OAuth client IDs:** Verify in `apps/confluent-platform/qa/kafka.yaml` (currently inherited from dev structure — **may need environment-specific IDs**)
- **Groups claim:** Currently dahDev_groups (update to dahQA_groups if QA has separate Okta scope)
- **Scope:** Currently 11547.DAH(Dev) (update to 11547.DAH(QA) if applicable)
- **Okta issuer:** https://myapps.firstcitizens.com/oauth2/default (confirm same across all envs)

**Updated manifests:** `apps/confluent-platform/qa/kafka.yaml`, `kraftcontroller.yaml`

### UAT-P (UAT Primary)

- **Kafka internal listener:** SASL/PLAIN over TLS
- **OAuth client IDs:** Verify in `apps/confluent-platform/uat-p/kafka.yaml` (currently inherited from qa structure)
- **Groups claim:** Confirm (likely dahUAT_groups or similar)
- **Scope:** Confirm (likely 11547.DAH(UAT) or similar)
- **Okta issuer:** Confirm same endpoint

**Updated manifests:** `apps/confluent-platform/uat-p/kafka.yaml`, `kraftcontroller.yaml`

### UAT-S (UAT Secondary)

- **Kafka internal listener:** SASL/PLAIN over TLS
- **OAuth client IDs:** Same as uat-p (secondary cluster, same Okta realm)
- **Groups claim:** Same as uat-p
- **Scope:** Same as uat-p

**Updated manifests:** `apps/confluent-platform/uat-s/kafka.yaml`, `kraftcontroller.yaml`

### PRD (Production)

- **Kafka internal listener:** SASL/PLAIN over TLS
- **OAuth client IDs:** Verify in `apps/confluent-platform/prd/kafka.yaml` (currently inherited from qa structure)
- **Groups claim:** Confirm (likely dahProd_groups or similar)
- **Scope:** Confirm (likely 11547.DAH(Prod) or similar)
- **Okta issuer:** Confirm same endpoint
- **Namespace:** `dah-flink-prod` (not `dah-flink-prd`)

**Updated manifests:** `apps/confluent-platform/prd/kafka.yaml`, `kraftcontroller.yaml`

### DR (Disaster Recovery)

- **Kafka internal listener:** SASL/PLAIN over TLS
- **OAuth client IDs:** Same as prd (mirrors production)
- **Groups claim:** Same as prd
- **Scope:** Same as prd

**Updated manifests:** `apps/confluent-platform/dr/kafka.yaml`, `kraftcontroller.yaml`

## Implementation Checklist

- [ ] **Pipeline validation:**
  - [ ] Only one SASL variable per environment: `<env>-sasl-plain-admin-pwd`
  - [ ] `sasl-plain-internal` Secret creation uses that single variable for all five keys
  - [ ] Five legacy SASL variables are documented as legacy (not consumed)

- [ ] **Environment-specific OAuth:**
  - [ ] DEV: Okta client IDs, groups claims, and scopes verified ✓ (already live)
  - [ ] QA: Okta client IDs, groups claims, scopes confirmed (currently inherits dev values — **needs review**)
  - [ ] UAT-P: Okta client IDs, groups claims, scopes confirmed
  - [ ] UAT-S: Okta client IDs, groups claims, scopes confirmed (same as uat-p)
  - [ ] PRD: Okta client IDs, groups claims, scopes confirmed (namespace = dah-flink-prod)
  - [ ] DR: Okta client IDs, groups claims, scopes confirmed (mirrors prd)

- [ ] **Manifest correctness (per environment):**
  - [ ] kafka.yaml:
    - [ ] Namespace correct
    - [ ] Internal listener: type=plain, secretRef=sasl-plain-internal
    - [ ] External listener: type=oauth, environment-specific settings
    - [ ] KRaft dependency: type=plain, secretRef=sasl-plain-internal
    - [ ] Metric reporter: type=plain, secretRef=sasl-plain-internal
    - [ ] metricsClient dependency: basic auth, correct C3 service endpoint
    - [ ] Authorization: superUsers include broker OAuth ID and User:admin
    - [ ] configOverrides: Only external OAuth and non-auth broker settings
  - [ ] kraftcontroller.yaml:
    - [ ] Namespace correct
    - [ ] Listener controller: type=plain, secretRef=sasl-plain-internal
    - [ ] metricsClient dependency: basic auth, correct C3 endpoint
    - [ ] Authorization: superUsers include broker OAuth ID and User:admin
    - [ ] configOverrides: No SASL mechanism overrides (CFK generates them)

- [ ] **CyberArk onboarding:**
  - [ ] `sasl-plain-admin-password` property onboarded for each environment
  - [ ] ExternalSecret CR targets that property with decodingStrategy: Base64
  - [ ] Five legacy PLAIN properties marked for manual removal

- [ ] **Deployment order (per environment):**
  1. Run pipeline with `action=create-prereqs` to provision `sasl-plain-internal` Secret
  2. Confirm Secret exists with expected five keys
  3. Run `install-or-update` with KRaft and Kafka selected
  4. Wait for both to reach `cluster-ready=True`
  5. Apply Phase 2 (SR/Connect/REST/C3) managed components
  6. Validate Routes are reencrypt with destination TLS cert

- [ ] **Post-deployment validation (per environment):**
  - [ ] Kafka and KRaft reach `cluster-ready=True` and stay healthy
  - [ ] No reconciliation errors related to SASL/PLAIN configuration
  - [ ] Managed components (SR/Connect/REST/C3) use their OAuth identities
  - [ ] No component-specific PLAIN failures or auth denials
  - [ ] CyberArk ExternalSecret reports `SecretSynced=True`
  - [ ] Readiness gates stay disabled (will re-enable after NetworkPolicy)

## When Separate PLAIN Accounts Would Be Required

If an environment later introduces:

- A legacy application unable to use OAuth
- A temporary migration client
- A separate operational tool that cannot use OAuth or mTLS

Create a **dedicated least-privilege identity** for that client (not `admin`), with:

- Unique username/password
- CyberArk ownership
- Least-privilege role bindings
- Explicit removal date if temporary

Do not pre-create dormant PLAIN accounts.

## Rollback Safety

The five legacy Azure DevOps variables:

```text
<env>-sasl-plain-client-pwd
<env>-sasl-plain-schema-registry-pwd
<env>-sasl-plain-kafka-connect-pwd
<env>-sasl-plain-kafka-rest-pwd
<env>-sasl-plain-control-center-pwd
```

Remain in the variable groups but are no longer consumed by the pipeline. Keep them until the new SASL/PLAIN configuration is validated in the cluster. Document them as:

```
Legacy/unused after hybrid migration — remove manually after validation
```

This provides a quick fallback path if the SASL/PLAIN configuration needs to be reverted.

## Summary of Changes

| Component | Was | Now |
|-----------|-----|-----|
| Kafka internal listener | OAuth | SASL/PLAIN + TLS |
| Kafka-to-KRaft | OAuth | SASL/PLAIN + TLS |
| KRaft controller listener | OAuth | SASL/PLAIN + TLS |
| Broker metric reporter | OAuth | SASL/PLAIN + TLS |
| Kafka external listener | OAuth | OAuth + TLS (unchanged) |
| Managed components (SR/Connect/REST/C3) | OAuth | OAuth + RBAC (unchanged) |
| Admin credential count | 5 environment-specific PLAIN passwords | 1 per environment (`admin`) |
| CyberArk onboarding | 5 PLAIN properties per env | 1 PLAIN property per env |

## References

- Runbook A22 (OAuth/RBAC configuration)
- Runbook A23 (Role binding deployment)
- Runbook A26 (Metric reporter troubleshooting)
- runbook A29 (C3 basic auth)
- HYBRID_AUTH_REFACTOR.md (DEV-only details — see dev-cfk-hybrid-auth.zip)
