# CMF dev — CyberArk integration via External Secrets Operator (ESO)

The container team installed an `external-secrets.io/v1` `SecretStore`
named **`11547-d-key-fp`** in the `dah-flink-dev` namespace. It proxies
to FCB CyberArk's Central Credential Provider (CCP) over a webhook
provider. Once an `ExternalSecret` in this directory is applied, ESO
calls the SecretStore on its `refreshInterval` (1h), pulls the
credential content from CyberArk, and materializes the Kubernetes
`Secret` objects the CMF Helm chart consumes.

## Concept reminder — SecretStore vs ExternalSecret

| | SecretStore (container team owns) | ExternalSecret (we own — this directory) |
|---|---|---|
| What it is | Connection to CyberArk | A request — "fetch X and materialize k8s Secret Y" |
| Number | One per namespace | One per Secret you need |
| Without the other | Dormant connection; creates nothing | Can't pull anything; no connection |

The SecretStore is parameterized — its URL has `UserName={{ .remoteRef.key }}` and `Address={{ .remoteRef.property }}` placeholders. Every `ExternalSecret` here supplies those values for one specific CyberArk Account.

## The SecretStore URL contract (read-only — for reference)

```
https://pam-ccp.fcpd.fcbint.net/AIMWebServiceIP/api/Accounts
  ?ConnectionTimeout=30
  &AppId=APP-11547-D
  &Query=Safe=11547_D_KEY_FP
         ;UserName={{ .remoteRef.key }}
         ;Address={{ .remoteRef.property }}
```

CyberArk responds with `{"Content": "<the-secret>"}`. The SecretStore extracts `$.Content` via `result.jsonPath` and ESO hands the raw string to the `template` block in each ExternalSecret.

## Files in this directory

| File | CyberArk UserName | Address | k8s Secret produced | CMF chart wiring | Status |
|---|---|---|---|---|---|
| `externalsecret-confluent-license.yaml` | `"dev-confluent-license"` | `"Digital Analytics Hub"` | `confluent-license` (key `license.txt`, **raw JWT**) | `license.secretRef: confluent-license` | **ACTIVE** |
| `externalsecret-cmf-db-password.yaml` | `"dev-cmf-sql-server-user-password"` | `"Digital Analytics Hub"` | `cmf-db-credentials` (key `password`) | `cmf.database.jdbc.password.kubernetesSecretName: cmf-db-credentials` | **ACTIVE** |
| `externalsecret-cmf-encryption-key.yaml` | `"dev-cmf-encryption-key"` | `"Digital Analytics Hub"` | `cmf-encryption-key` (key `key`) | `encryption.key.kubernetesSecretName: cmf-encryption-key` | **ACTIVE** |

**One non-obvious gotcha to know:** CMF wants the license as the **raw JWT** under `license.txt`. CFK / Confluent Platform Kafka wants the Java-properties shape `license=<JWT>` — different format. The cmf.yaml pipeline creates two distinct Secrets to cover the split: `confluent-license` (raw JWT, what this ExternalSecret produces, consumed by CMF) and `cfk-license` (`license=<JWT>` properties shape, created by the pipeline directly, consumed by CFK Kafka). Don't add the `license=` prefix to the template here.

## Apply order — all three ExternalSecrets

The `cmf.yaml` pipeline (`action=install`, `environment=dev`) applies all three, force-syncs each, and waits up to 120s for each to reach `Ready=True` before running the Helm install. Manual one-off application looks like:

```bash
# Apply all three.
oc apply -n dah-flink-dev -f apps/confluent-cmf/dev/externalsecrets/

# Verify each reached Ready=True.
oc -n dah-flink-dev get externalsecret \
  confluent-license cmf-db-credentials cmf-encryption-key

# If any shows SecretSyncedError, describe it for the underlying CCP error.
oc -n dah-flink-dev describe externalsecret <name>

# Verify materialized Secret content (raw JWT, no `license=` prefix for CMF).
oc -n dah-flink-dev get secret confluent-license -o jsonpath='{.data.license\.txt}' | base64 -d | head -1
```

## Rotation

ESO refreshes each ExternalSecret every `refreshInterval` (we set 1h).
When the container team rotates a credential in CyberArk, the next
refresh updates the k8s Secret. The CMF pod won't automatically restart
— it'll still hold the old value in memory until restarted. For
zero-touch rotation, layer in either:
- a Reloader-style controller annotation on the CMF Deployment, or
- a sidecar that watches the Secret mount and signals the JVM.

Out of scope for this initial integration — flag for hardening later.
**Special case: `cmf-encryption-key` MUST NOT rotate** — CMF's catalog
rows are encrypted with it; rotating breaks decryption. CyberArk should
have rotation locked for that account.
