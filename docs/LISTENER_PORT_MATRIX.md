# Confluent Platform Listener Port Matrix

Last Updated: 2026-08-12  
Refactor Phase: Hybrid Authentication (:9071→:9092 migration)

## Overview

Confluent Platform on CFK (Confluent for Kubernetes) uses a dual-listener architecture:

| Listener   | Port | Protocol   | Auth Mechanism       | Use Case                                                           |
|-----------|------|-----------|----------------------|--------------------------------------------------------------------|
| **INTERNAL** | 9071 | SASL_SSL  | SASL/PLAIN + TLS     | Inter-broker communication, KRaft controller traffic, admin ops    |
| **EXTERNAL** | 9092 | SASL_SSL  | OAuth + TLS          | Managed component clients (SR, Connect, REST, C3) using OAuth      |
| **MDS/REST** | 8090 | HTTPS    | OAuth (Bearer token) | Metadata Service REST API, rolebindings, RBAC queries             |

## Listener Details

### INTERNAL Listener (:9071)

- **Protocol**: `SASL_SSL` (SASL/PLAIN over TLS 1.3)
- **Authentication**: SASL/PLAIN with credentials from `sasl-plain-internal` Secret
  - User: `admin`
  - Password: From variable group `<env>-sasl-plain-admin-pwd`
- **TLS Certificate**: `kafka-tls` Secret (svc.cluster.local backend cert)
- **Clients**:
  - KRaft Controller nodes (inter-controller quorum)
  - Kafka Brokers (inter-broker replication)
  - Tools: AdminClient (broker/controller operations)
  - CFK Operator (cluster health probes)

### EXTERNAL Listener (:9092) — *NEW POST-REFACTOR*

- **Protocol**: `SASL_SSL` (OAuth over TLS 1.3)
- **Authentication**: OAuth + JAAS (OAUTHBEARER mechanism)
  - Each client uses its own OAuth app credentials
  - Token endpoint: `https://myapps.firstcitizens.com/oauth2/default/v1/token`
  - JWKS endpoint: `https://myapps.firstcitizens.com/oauth2/default/v1/keys`
- **TLS Certificate**: `kafka-tls` Secret (svc.cluster.local backend cert)
- **Clients**:
  - **Schema Registry**: `oauth-schemaregistry` Secret
  - **Kafka Connect**: `oauth-connect` Secret
  - **Kafka REST Proxy**: `oauth-kafkarest` Secret
  - **Control Center**: `oauth-controlcenter` Secret (C3 backend communication; OIDC is MDS responsibility)

### MDS Listener (:8090)

- **Protocol**: HTTPS (TLS 1.3)
- **Authentication**: OAuth Bearer tokens + OIDC for browser SSO
  - **For API clients** (Rolebinding operator): `oauth-mds-rest` Secret
  - **For browser SSO** (C3 UI login): `oauth-mds-sso` Secret (separate Okta OIDC app)
- **TLS Certificate**: `kafka-tls` Secret (svc.cluster.local backend cert)
- **Token signing**: `mds-token-keypair` Secret (RSA public/private pair)
- **Hostname**: `kafka.dah-flink-<env>.svc.cluster.local` (internal Kubernetes DNS)

## DNS Resolution

### By Environment

| Environment | Kafka Broker Service DNS        | Namespace            |
|------------|-------------------------------|----------------------|
| **dev**   | kafka.dah-flink-dev.svc.cluster.local | dah-flink-dev |
| **qa**    | kafka.dah-flink-qa.svc.cluster.local  | dah-flink-qa  |
| **uat-p** | kafka.dah-flink-uat.svc.cluster.local | dah-flink-uat |
| **uat-s** | kafka.dah-flink-uat.svc.cluster.local | dah-flink-uat |
| **prd**   | kafka.dah-flink-prd.svc.cluster.local | dah-flink-prd |
| **dr**    | kafka.dah-flink-dr.svc.cluster.local  | dah-flink-dr  |

> **Note**: UAT-P and UAT-S share the same kafka service DNS (`dah-flink-uat`) but are in separate logical environments with distinct Okta scopes and rolebindings.

## Managed Component Bootstrap Endpoints (Post-Refactor)

All managed components now connect to the **EXTERNAL listener (:9092)** instead of INTERNAL (:9071).

```yaml
dependencies:
  kafka:
    bootstrapEndpoint: kafka.dah-flink-<env>.svc.cluster.local:9092
    authentication:
      type: oauth
      jaasConfig:
        secretRef: oauth-<component>
```

### Manifest Examples

- **schemaregistry.yaml**: Line 70
- **connect.yaml**: Line 65
- **kafkarest.yaml**: Line 66
- **controlcenter.yaml**: Line 104

## Control Center Authentication (Post-Refactor)

Control Center uses **two separate authentication paths**:

1. **UI Login**: OIDC SSO via MDS (:8090)
   - User navigates to: `https://controlcenter.apps.<env>.ocp.fcbint.net/`
   - Redirect to Okta `<app-id>` OIDC client
   - Callback URI: `https://controlcenter.apps.<env>.ocp.fcbint.net/api/metadata/security/1.0/oidc/authorization-code/callback`

2. **Backend Communication** (removed): ~~Basic HTTP auth (REMOVED in refactor)~~
   - Now uses OAuth for all Kafka/SR/MDS API calls (same as other components)
   - Client credential: `oauth-controlcenter` Secret

### Removed (Legacy Basic Auth)

- Manifest block: `spec.authentication: { type: basic, secretRef: controlcenter-basic-auth }`
- Pipeline secret: `controlcenter-basic-auth` (no longer created)
- Variable group: `C3_BASIC_USER`, `C3_BASIC_PWD` (not used)

## Pre-Deployment Checklist

Before deploying Confluent Platform manifests in any environment:

- [ ] Okta OIDC app provisioned for `<env>` (see Okta OIDC requirements below)
- [ ] MDS token keypair provisioned: `<env>-mds-token-keypair-pem`
- [ ] OAuth client IDs and secrets provisioned in Azure DevOps variable group:
  - `oauth-broker-client-{id,secret}`
  - `oauth-schemaregistry-client-{id,secret}`
  - `oauth-connect-client-{id,secret}`
  - `oauth-kafkarest-client-{id,secret}`
  - `oauth-controlcenter-client-{id,secret}` (backend auth)
  - `oauth-mds-rest-client-{id,secret}` (rolebinding operator)
  - `oauth-mds-sso-client-{id,secret}` (C3 OIDC login) — **NEWLY REQUIRED**
- [ ] Floating DNS CNAMEs registered (UAT/PRD only):
  - `controlcenter.apps.<env>.ocp.fcbint.net` (C3 UI)
  - `kafka-mds.apps.<env>.ocp.fcbint.net` (MDS REST)
  - Similar entries for SR, Connect, REST Proxy

## Troubleshooting

### Symptom: "Connection refused" to :9092 from managed components

**Diagnosis**: Component is trying to connect to :9071 (old INTERNAL listener).

- Verify manifest uses `:9092` in `dependencies.kafka.bootstrapEndpoint`
- CFK auto-generates advertised.listeners → if CR shows `:9071`, listener config has not been reconciled yet
- Check Kafka pod logs: `oc logs -n $OC_NS kafka-0 -c kafka | grep listener`

### Symptom: Kafka OAuth listener not responding

**Diagnosis**: `oauth-broker` Secret missing or malformed.

- Verify: `oc get secret oauth-broker -n $OC_NS`
- Check keys: Must have `clientId`, `clientSecret`, `bearer.txt`, `oauth.txt`, `oidcClientSecret.txt`
- Redeploy with pipeline: `action=create-prereqs`

### Symptom: MDS not accessible at :8090

**Diagnosis**: MDS listener may be initializing or token keypair missing.

- Verify: `oc get secret mds-token-keypair -n $OC_NS` (must have `mdsTokenKeyPair.pem` and `mdsPublicKey.pem`)
- Check Kafka pod: `oc exec -n $OC_NS kafka-0 -- curl -sk https://localhost:8090/api/v1/metadata/brokers`
- Monitor: `oc get kafka kafka -n $OC_NS -o jsonpath='{.status.conditions[*]}'`

### Symptom: C3 OIDC redirect fails

**Diagnosis**: Callback URI mismatch or oauth-mds-sso Secret missing.

- Verify Okta app callback URI matches: `https://controlcenter.apps.<env>.ocp.fcbint.net/api/metadata/security/1.0/oidc/authorization-code/callback`
- Check Secret: `oc get secret oauth-mds-sso -n $OC_NS`
- Check Kafka MDS pod for OIDC errors: `oc logs -n $OC_NS kafka-0 | grep -i oidc`

## References

- Runbook A22: CFK OAuth and RBAC configuration
- Runbook A23: Kafka/MDS OAuth scopes and impersonation
- Runbook A29: Control Center authentication (legacy — now partially archived)
- Azure DevOps Pipeline: `.azure-pipelines/confluent-platform.yaml` (variables section)
