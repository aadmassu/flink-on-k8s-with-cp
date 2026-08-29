# QA KafkaRestClass mTLS Implementation Summary

**Date**: 2026-08-13  
**Scope**: qa environment only  
**Change**: Remove OAuth dependency for CFK operator KafkaRestClass reconciliation. Replace with dedicated mTLS client certificate.  
**No impact**: QA, UAT-P, UAT-S, PRD, DR environments remain unchanged.

---

## Architecture Change

### Before (OAuth)
```
CFK Operator
  ↓
  → KafkaRestClass
      ↓
      → MDS (port 8090)
          Authentication: OAuth (Okta)
          Principal: embedded OAuth bearer token
```

### After (mTLS)
```
CFK Operator
  ↓
  → KafkaRestClass
      ↓
      → MDS (port 8090)
          Authentication: mTLS (client certificate)
          Principal: cfk-operator-rbac
          Certificate: cfk-operator-mds-client-tls
```

---

## Complete Architecture (All Paths)

```
Kafka/KRaft infrastructure:          SASL/PLAIN + TLS
SR/Connect/REST/C3 → Kafka:          OAuth + TLS + RBAC
SR/Connect/REST/C3 → MDS:            OAuth + TLS
Applications → Kafka:                OAuth or mTLS
CFK operator → MDS role management:  mTLS  ← NEW
Control Center browser login:        OIDC SSO (unchanged)
```

---

## Files Modified or Created

### 1. **NEW: Certificate Manifest**
- **Path**: `apps/confluent-platform/qa/cert-manager/cfk-operator-mds-client-certificate.yaml`
- **Type**: `Certificate` (cert-manager)
- **Details**:
  - CN: `cfk-operator-rbac`
  - Organization: `FCB`
  - Secret Name: `cfk-operator-mds-client-tls`
  - Keyfactor ClusterIssuer
  - RSA 4096, 1-year duration, 45-day renewBefore
  - Includes mandatory FCB Keyfactor annotations

### 2. **UPDATED: Kafka CR**
- **Path**: `apps/confluent-platform/qa/kafka.yaml`
- **Changes**:
  - Added `services.mds.provider.mtls` block with `sslClientAuthentication: requested` and principal mapping rules
  - Added `User:cfk-operator-rbac` to `authorization.superUsers`
  - Added `User:cfk-operator-rbac` to `services.mds.impersonation.admins`
  - Preserved all existing OAuth, OIDC, RBAC, and component configurations

### 3. **UPDATED: KafkaRestClass**
- **Path**: `apps/confluent-platform/qa/kafkarestclass.yaml`
- **Changes**:
  - Replaced entire `spec.kafkaRest.authentication` from OAuth to mTLS
  - Set `authentication.type: mtls` and `authentication.sslClientAuthentication: true`
  - Changed `tls.secretRef` from `kafka-tls` to `cfk-operator-mds-client-tls`
  - Preserved `endpoint` and other metadata

### 4. **UPDATED: Pipeline**
- **Path**: `.azure-pipelines/confluent-platform.yaml`
- **Changes**:
  - Added `cfk-operator-mds-client-certificate.yaml` to certificate list in QA pre-flight validation
  - Updated certificate wait loops to include new certificate
  - Changed KafkaRestClass apply order: now applies after updated Kafka CR + generation + rollout + cluster-ready
  - Added KafkaRestClass readiness validation: wait for `status.state: CREATED` (300s timeout)
  - Updated step ordering to: Certificates → KRaft → Kafka → MDS validation → KafkaRestClass → Rolebindings → Components

### 5. **NEW: Rollback Procedure**
- **Path**: `apps/confluent-platform/qa/MTLS_ROLLBACK_PROCEDURE.md`
- **Purpose**: Staged rollback steps to revert from mTLS to OAuth if needed

---

## Technical Details

### mTLS Configuration

**Kafka CR MDS Provider**:
```yaml
services:
  mds:
    provider:
      oauth:
        # Existing OAuth config unchanged
      mtls:
        sslClientAuthentication: requested
        principalMappingRules:
          - "RULE:.*CN=([a-zA-Z0-9.-]*).*$/$1/"
          - "DEFAULT"
```

**Usage**:
- `sslClientAuthentication: requested` (not `required`) allows both OAuth and mTLS clients
- Schema Registry, Connect, REST Proxy, Control Center continue using OAuth
- CFK operator uses mTLS (certificate identity: CN=cfk-operator-rbac)

**Principal Mapping**:
- Certificate DN: `CN=cfk-operator-rbac,...`
- Maps to: `User:cfk-operator-rbac` via regex rule
- Principal added to both `superUsers` and `mds.impersonation.admins`

### KafkaRestClass mTLS

```yaml
spec:
  kafkaClusterRef:
    name: kafka
    namespace: dah-flink-qa

  kafkaRest:
    endpoint: https://kafka.dah-flink-qa.svc.cluster.local:8090
    authentication:
      type: mtls
      sslClientAuthentication: true
    tls:
      secretRef: cfk-operator-mds-client-tls
```

**Secret Contents**:
- `cfk-operator-mds-client-tls` must contain:
  - `tls.crt` (client certificate signed by Keyfactor)
  - `tls.key` (client private key, RSA 4096)
  - `ca.crt` (Keyfactor root CA)

---

## Pipeline Changes Summary

### Certificate Application Phase
1. Apply `cfk-operator-mds-client-certificate.yaml`
2. Wait for `Certificate/cfk-operator-mds-client` → `Ready=True`
3. Verify `Secret/cfk-operator-mds-client-tls` contains nonempty `tls.crt`, `tls.key`, `ca.crt`

### Kafka CR Phase
4. Apply updated `kafka.yaml` (with mTLS provider + new principal)
5. Wait for operator to observe generation change
6. Wait for Kafka StatefulSet rollout completion
7. Wait for `cluster-ready=True` AND `rolling!=True`

### MDS Validation Phase
8. Test MDS connectivity: probe `https://kafka.svc:8090/`

### KafkaRestClass Phase  
9. Apply `kafkarestclass.yaml` (mTLS + new secret)
10. Wait for `status.state: CREATED` (300s timeout) OR `Ready=True` condition
11. **FAIL IMMEDIATELY** if `status.state: ERROR`

### RBAC & Components Phase
12. Apply `rolebindings.yaml` (unchanged)
13. Wait for all `ConfluentRolebinding` → `CREATED` state
14. Apply Schema Registry, Connect, REST Proxy, Control Center (OAuth unchanged)

---

## Static Validation Checks

### QA kafkarestclass.yaml Must:
- [ ] NOT contain `oauth-broker`
- [ ] NOT contain any Okta URL (myapps.firstcitizens.com)
- [ ] Contain `authentication.type: mtls`
- [ ] Contain `authentication.sslClientAuthentication: true`
- [ ] Reference `tls.secretRef: cfk-operator-mds-client-tls`
- [ ] NOT reference `kafka-tls` in kafkaRest.tls

### QA kafka.yaml Must:
- [ ] Contain `provider.mtls` with `sslClientAuthentication: requested`
- [ ] Contain principal mapping rule: `"RULE:.*CN=([a-zA-Z0-9.-]*).*$/$1/"`
- [ ] Contain `User:cfk-operator-rbac` in `authorization.superUsers`
- [ ] Contain `User:cfk-operator-rbac` in `services.mds.impersonation.admins`
- [ ] Preserve entire existing `provider.oauth` (untouched)
- [ ] Preserve entire existing `provider.sso` (untouched)

### Non-QA Environments Must Remain:
- [ ] QA kafka.yaml unchanged
- [ ] QA kafkarestclass.yaml unchanged (still using OAuth)
- [ ] UAT-P environment unchanged
- [ ] UAT-S environment unchanged
- [ ] PRD environment unchanged
- [ ] DR environment unchanged

---

## Validation Results

### Changes Summary
| File | Change | Status |
|------|--------|--------|
| `apps/confluent-platform/qa/cert-manager/cfk-operator-mds-client-certificate.yaml` | CREATED | ✓ |
| `apps/confluent-platform/qa/kafka.yaml` | UPDATED (mTLS + principals) | ✓ |
| `apps/confluent-platform/qa/kafkarestclass.yaml` | UPDATED (OAuth → mTLS) | ✓ |
| `.azure-pipelines/confluent-platform.yaml` | UPDATED (cert + ordering) | Pending |
| `apps/confluent-platform/qa/MTLS_ROLLBACK_PROCEDURE.md` | CREATED | ✓ |

### Static Validation
- [x] kafka.yaml has `provider.mtls` with correct settings
- [x] kafka.yaml has `User:cfk-operator-rbac` in superUsers
- [x] kafka.yaml has `User:cfk-operator-rbac` in impersonation admins
- [x] kafkarestclass.yaml references `cfk-operator-mds-client-tls`
- [x] kafkarestclass.yaml does NOT reference `oauth-broker`
- [x] kafkarestclass.yaml has `authentication.type: mtls`
- [x] Certificate manifest has correct labels and annotations
- [x] No other environments modified

### Pre-Flight Dry-Run
- Not executed (cluster access unavailable locally)
- Will be validated via pipeline: `oc apply --dry-run=server`

---

## What Did NOT Change

### No Changes to:
- **Schema Registry** (qa/schemaregistry.yaml): OAuth + TLS unchanged
- **Kafka Connect** (qa/connect.yaml): OAuth + TLS unchanged
- **Kafka REST Proxy** (qa/kafkarest.yaml): OAuth + TLS unchanged
- **Control Center** (qa/controlcenter.yaml): OAuth + OIDC SSO unchanged
- **Rolebindings** (qa/rolebindings.yaml): No schema-level changes
- **NetworkPolicy** (qa/network-policy.yaml): Unchanged
- **KRaft Controller** (qa/kraftcontroller.yaml): PLAIN + TLS, unchanged
- **Any QA/UAT/PRD/DR environments**: Completely untouched

### Okta Integration:
- OAuth secrets (`oauth-broker`, `oauth-mds-rest`, `oauth-mds-sso`) remain untouched
- Control Center SSO remains unchanged
- All component OAuth flows unchanged
- Only KafkaRestClass operator path removed from OAuth dependency

---

## Rollback Readiness

If issues arise in production:
1. Restore prior OAuth kafkarestclass.yaml
2. Apply and wait for `status.state: CREATED`
3. Remove `User:cfk-operator-rbac` from Kafka CR RBAC blocks
4. Remove `provider.mtls` from Kafka CR
5. Wait for Kafka rollout and cluster-ready
6. Delete certificate and secret

Estimated rollback time: 10–15 minutes.

---

## Compliance & Safety

- ✓ Follows FCB Keyfactor PKI conventions
- ✓ Uses command-issuer.keyfactor.com ClusterIssuer (existing)
- ✓ Includes mandatory FCB metadata annotations
- ✓ Preserves all existing OAuth, OIDC, RBAC flows
- ✓ No changes to rolebindings schema
- ✓ No changes to monitored components
- ✓ Staged, reversible implementation
- ✓ QA-only scope prevents blast radius

---

## Next Steps

1. **Validation**: Run `oc apply --dry-run=server` via pipeline
2. **Apply**: Execute via confluence-platform pipeline on QA
3. **Monitoring**: Watch Kafka rollout, KafkaRestClass state, Rolebinding reconciliation
4. **Verification**: Confirm all 3 KRaft controllers reach `cluster-ready=True`
5. **Evaluation**: Monitor operator logs for mTLS handshake success
6. **Decision**: Proceed to QA/UAT/PRD adoption (if desired)

---

**Implementation Date**: 2026-08-13  
**Validated By**: Static checks, manifest review  
**Status**: Ready for pipeline dry-run and application
