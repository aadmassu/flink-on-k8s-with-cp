# DEV KafkaRestClass mTLS Rollback Procedure

**Effective Date**: 2026-08-13  
**Environment**: dev only  
**Change**: KafkaRestClass authentication from OAuth to mTLS

## Rollback Steps

Follow these steps **in order** to revert from mTLS to OAuth for KafkaRestClass. The procedure removes mTLS and principals in a single Kafka CR update (one rollout), then transitions KafkaRestClass back to OAuth, then cleans up the certificate.

### 1. Prepare OAuth KafkaRestClass Manifest

Save or use the following OAuth-based KafkaRestClass manifest:

```yaml
---
apiVersion: platform.confluent.io/v1beta1
kind: KafkaRestClass
metadata:
  name: default
  namespace: dah-flink-dev
  labels:
    app.kubernetes.io/name: kafkarestclass
    app.kubernetes.io/instance: default
    app.kubernetes.io/component: kafka-rest-class
    app.kubernetes.io/part-of: confluent-platform
    fcbint.net/app-id: "11547"
spec:
  kafkaClusterRef:
    name: kafka
    namespace: dah-flink-dev
  kafkaRest:
    endpoint: https://kafka.dah-flink-dev.svc.cluster.local:8090
    authentication:
      type: oauth
      oauth:
        secretRef: oauth-broker
        configuration:
          audience: "Confluent,account,api://default"
          expectedIssuer: https://myapps.firstcitizens.com/oauth2/default
          groupsClaimName: dahDev_groups
          subClaimName: sub
          jwksEndpointUri: https://myapps.firstcitizens.com/oauth2/default/v1/keys
          tokenEndpointUri: https://myapps.firstcitizens.com/oauth2/default/v1/token
          scope: 11547.DAH(Dev)
          loginConnectTimeoutMs: 10000
          loginReadTimeoutMs: 30000
          loginRetryBackoffMaxMs: 5000
          loginRetryBackoffMs: 60000
    tls:
      secretRef: kafka-tls
```

### 2. Update Kafka CR: Remove mTLS Provider and Principal in One Change

Edit `apps/confluent-platform/dev/kafka.yaml` and make **both** changes in a single edit:

1. **Remove** the entire `provider.mtls` block (lines 134–138)
2. **Remove** `User:cfk-operator-rbac` from `authorization.superUsers` (line 73)
3. **Remove** `User:cfk-operator-rbac` from `services.mds.impersonation.admins` (line 161)

Apply the updated Kafka CR:
```bash
oc apply -f apps/confluent-platform/dev/kafka.yaml
```

This produces **one Kafka StatefulSet rollout**. Monitor:
```bash
oc rollout status statefulset/kafka -n dah-flink-dev --timeout=900s
oc get kafka kafka -n dah-flink-dev -o jsonpath='{.status.conditions[?(@.type=="platform.confluent.io/cluster-ready")].status}'
```

Wait for:
- `cluster-ready=True`
- `rolling!=True`

### 3. Apply OAuth KafkaRestClass

Apply the OAuth manifest prepared in step 1 (or restore from `apps/confluent-platform/dev/kafkarestclass.yaml` if you have a backup):

```bash
oc apply -f apps/confluent-platform/dev/kafkarestclass.yaml
```

Wait for KafkaRestClass to reach CREATED state:
```bash
oc get kafkarestclass default -n dah-flink-dev -o yaml
# or
oc get kafkarestclass default -n dah-flink-dev -o jsonpath='{.status.state}'
```

Expected: `status.state: CREATED` or `Ready=True`

If KafkaRestClass shows ERROR, dump diagnostics:
```bash
oc describe kafkarestclass default -n dah-flink-dev
oc get events -n dah-flink-dev --sort-by='.lastTimestamp' | grep -i kafkarestclass
```

### 4. Verify Rolebindings Still Reconcile

Confirm ConfluentRolebindings are CREATED (unchanged by rollback):
```bash
oc get confluentrolebinding -n dah-flink-dev -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.state}{"\n"}{end}'
```

All should show: `status.state: CREATED`

### 5. Delete mTLS Credentials

Only after KafkaRestClass is CREATED and rolebindings are stable, delete:

```bash
oc delete certificate cfk-operator-mds-client -n dah-flink-dev
oc delete secret cfk-operator-mds-client-tls -n dah-flink-dev
```

Verify deletion:
```bash
oc get certificate cfk-operator-mds-client -n dah-flink-dev 2>&1 | grep -q "not found" && echo "Certificate deleted" || echo "Certificate still present"
oc get secret cfk-operator-mds-client-tls -n dah-flink-dev 2>&1 | grep -q "not found" && echo "Secret deleted" || echo "Secret still present"
```

## Important Notes

- **OAuth Secrets Remain**: Do NOT delete `oauth-broker` or other OAuth secrets during rollback. Component services still use them.
- **Control Center SSO Unchanged**: Do NOT alter `services.mds.provider.sso` or `oauth-mds-sso` secret. Browser login remains unaffected.
- **No NetworkPolicy Changes**: The existing DEV ingress policy is already permissive for operator-to-MDS traffic.
- **Staged Approach**: This procedure is designed to work even if some steps take several minutes. Do not rush between steps.

## Verification Checklist

After complete rollback:

- [ ] KafkaRestClass shows `status.state: CREATED`
- [ ] Kafka shows `cluster-ready=True` and `rolling!=True`
- [ ] No pods are restarting
- [ ] Events show no certificate or authentication errors
- [ ] Schema Registry, Connect, REST Proxy, and Control Center are ready
- [ ] Role-binding reconciliation is working
- [ ] Control Center browser login still works

## Rollback Timeline

Typical rollback takes 10–15 minutes:
- kafkarestclass.yaml apply: 1 min
- Kafka CR update + rollout: 8–12 min
- mTLS provider removal + rollout: 5–8 min
- Certificate cleanup: 1 min

Do not delete credentials until the final Kafka rollout completes.
