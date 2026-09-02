# Confluent Platform Listener Port Matrix

Last Updated: 2026-08-12  
Refactor Phase: Hybrid Authentication (:9071→:9092 migration)

## Overview

Confluent Platform on CFK (Confluent for Kubernetes) uses a multi-listener architecture:

| CFK listener key | Port | Protocol   | Auth Mechanism       | Use Case                                                           |
|-----------|------|-----------|----------------------|--------------------------------------------------------------------|
| `internal` | 9071 | SASL_SSL  | SASL/PLAIN + TLS     | Inter-broker communication, KRaft controller traffic, admin ops    |
| `external` | 9092 | SASL_SSL  | OAuth + TLS          | Managed component clients (SR, Connect, REST, C3) using OAuth      |
| `custom[certonly]` | 9094 | SSL | mTLS (client cert)   | Cert-only clients; mirrors the VM `CERTONLY` listener              |
| MDS/REST   | 8090 | HTTPS    | OAuth (Bearer token) | Metadata Service REST API, rolebindings, RBAC queries             |

> **CFK listener keys are fixed by the CRD.** `spec.listeners` accepts only
> `internal`, `external`, `replication` and `custom` (`additionalProperties:
> false`); arbitrary names are rejected at admission. The VM listener names
> cannot be reproduced on CFK — see the mapping table below.

## VM CP → CFK listener mapping

The two platforms use the same ports for the same jobs but **opposite names**.
VM `INTERNAL` means "internal to the FCB network" (client-facing); CFK
`internal` means "internal to the Kubernetes cluster" (inter-broker). Read this
table before comparing a VM `.properties` file against a CFK Kafka CR.

| Role | VM listener | VM port | CFK listener key | CFK port |
|---|---|---|---|---|
| Client-facing OAuth (SR, Connect, REST, C3, apps) | `INTERNAL` | 9092 | `external` | 9092 |
| Inter-broker replication (PLAIN) | `BROKER` | 9091 | `internal` | 9071 |
| KRaft controller quorum (PLAIN) | `CONTROLLER` | 9093 | `dependencies.kRaftController.controllerListener` | 9074 |
| mTLS cert-only clients | `CERTONLY` | 9094 (advertised 7055) | `custom[certonly]` | 9094 |

Port 9092 carries OAuth on **both** platforms, so client bootstrap strings keep
the same port across the migration. Only the hostname changes.

### The `certonly` path: 7055 is an F5 VIP port, not a broker port

Confirmed against the FCB VM network architecture diagram (Platform
Integration, held locally in `project-docs/diagrams/`). The brokers bind 9094;
**an F5 load balancer presents 7055 externally and translates to 9094**:

```
FIS partner  --7055 mTLS TLS1.3-->  public VIP  --NAT-->  F5 internal VIP  --9094-->  Kafka broker
```

| | PDC (primary) | SDC (secondary) |
|---|---|---|
| Advertised name | `broker0{1,2,3}.dah-kafka-pdc.firstcitizens.com` | `broker0{1,2,3}.dah-kafka-sdc.firstcitizens.com` |
| Public VIP | 69.89.143.28 / .29 / .30 | 69.89.156.28 / .29 / .30 |
| NAT to F5 VIP | 10.0.192.196 / .197 / .198 | 10.208.4.38 / .37 / .36 |
| F5 VIP name | `broker{1,2,3}-pdc.fcbint.net` | `broker{1,2,3}-sdc.fcpd.fcbint.net` |
| Broker port | 9094 | 9094 |

Note SDC's VIPs descend (`broker1`→.38, `broker2`→.37, `broker3`→.36) while
PDC's ascend; the name→VIP mapping is still 1:1 and consistent in both.

**What this means for the migration.** CFK brokers binding 9094 already match
VM broker behaviour exactly — there is no bind-port gap. The cutover action is
to re-point the **F5 pool members** from the VM brokers to the CFK brokers.
The partner changes nothing: same DNS name, same public VIP, same port 7055.

**The advertised-name problem survives, but is now cheap to solve.** Kafka's
metadata response must hand back names that route back through the F5. CFK
emits `<brokerPrefix><brokerId>.<domain>` from 0-indexed IDs, so it produces
`broker0/1/2` where the partner expects `broker01/02/03`. Because the partner
only ever *dials* the bootstrap names, the fix is to add DNS records for
whatever names CFK advertises, pointing at the **same three VIPs** — no partner
config change, no coordination window. Those advertised names then have to
appear as SANs on `cert-manager/kafka-tls-certificate.yaml` so the partner's
client can validate the broker cert after the metadata redirect.

> **Open question — does the F5 terminate or pass through mTLS?** The diagram
> labels the partner→F5 leg `mTLS` and the F5→broker leg `BSA` (server auth
> only). If the F5 terminates client-certificate auth, the broker's `certonly`
> listener sees the **F5's** certificate rather than the partner's, which
> changes both the authenticated principal and what `principalMappingRules`
> must produce. Confirm with Tushar / Rick before finalising the CFK
> `custom[certonly]` auth block. (Treat the diagram's protocol labels as
> approximate — Kafka ports are labelled "HTTPs" throughout, which they are not.)

## Listener Details

### `internal` listener (:9071) — VM equivalent: `BROKER:9091`

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

### `external` listener (:9092) — VM equivalent: `INTERNAL:9092`

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

### MDS listener (:8090)

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
| **prd**   | kafka.dah-flink-prod.svc.cluster.local | dah-flink-prod |
| **dr**    | kafka.dah-flink-prod.svc.cluster.local | dah-flink-prod (pd-s cluster) |

> **Note**: UAT-P and UAT-S share the same kafka service DNS (`dah-flink-uat`) but are in separate logical environments with distinct Okta scopes and rolebindings.

## Managed Component Bootstrap Endpoints (Post-Refactor)

All managed components now connect to the **`external` listener (:9092)** instead of `internal` (:9071) — matching how every VM component bootstraps to the VM `INTERNAL:9092` OAuth listener.

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
