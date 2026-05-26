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

| File | CyberArk UserName | Address (URL-encoded) | k8s Secret produced | CMF chart wiring | Status |
|---|---|---|---|---|---|
| `externalsecret-confluent-license.yaml` | `dev-confluent-license` | `Digital%20Analytics%20Hub` | `confluent-license` (key `license.txt`, content `license=<JWT>`) | `license.secretRef: confluent-license` | **READY** — Tushar confirmed account works |
| `externalsecret-cmf-db-password.yaml` | `dev-cmf-sql-server-user-password` | `Digital%20Analytics%20Hub` | `cmf-db-credentials` (key `password`) | `cmf.database.jdbc.password.kubernetesSecretName: cmf-db-credentials` | **HOLD** — pending Tushar's CyberArk platform fix |
| `externalsecret-cmf-encryption-key.yaml` | `dev-cmf-encryption-key` | `Digital%20Analytics%20Hub` | `cmf-encryption-key` (key `key`) | `encryption.key.kubernetesSecretName: cmf-encryption-key` | **HOLD** — pending Tushar's CyberArk platform fix |
| `externalsecret-artifactory-pull-secret.yaml` | `artifactory-svc-user-password` (in different safe `11547_D_UNX_FP`) | TBD | `artifactory-pull-secret` (dockerconfigjson) | `imagePullSecrets` in values.yaml (currently commented out) | **HOLD** — different CyberArk safe; address + username placeholders unresolved |

> The Address values are stored in CyberArk as the literal text **"Digital Analytics Hub"** (with spaces). They appear URL-encoded above because the FCB-owned SecretStore (`11547-d-key-fp`) renders its webhook URL with Go `text/template` literal substitution — no auto-encoding. A raw space in `property` ends up as a literal space in the request URL, Go's `url.Parse` rejects it, and the ExternalSecret status shows the opaque `SecretSyncedError: could not get secret data from provider`. Encoding the spaces as `%20` on our side avoids needing to touch the FCB-managed SecretStore template.

## Why two are on HOLD

Tushar's CyberArk view shows `dev-cmf-encryption-key` and
`dev-cmf-sql-server-user-password` are on Platform `UNIX-UNXSSH-...`,
which the AIM Web Service can't currently fetch from. He's adjusting the
platform mapping. Once that's in, the two HOLD ExternalSecrets become
apply-able with no further edits to this directory — but the cmf
pipeline (`.azure-pipelines/cmf.yaml`) will also need the equivalent
"dev → ExternalSecret, other envs → variable group" branch we added for
the license. Flag this when you're ready to flip them.

## Apply order — license only (current state)

```bash
# 1. Apply the ExternalSecret. (The variable-group flow in cmf.yaml is
#    already gated to skip license creation when env=dev — applying the
#    ExternalSecret separately is also safe.)
oc apply -f apps/confluent-cmf/dev/externalsecrets/externalsecret-confluent-license.yaml

# 2. Verify the ExternalSecret reaches SecretSynced=True.
oc -n dah-flink-dev get externalsecret confluent-license
oc -n dah-flink-dev describe externalsecret confluent-license  # if SyncError, look here

# 3. Verify the materialized Secret has the right content.
oc -n dah-flink-dev get secret confluent-license -o jsonpath='{.data.license\.txt}' | base64 -d | head -1
# Expect: license=eyJ...   (CFK's expected format)
# If the decoded content already begins with `license=` and is followed
# by another `license=`, CyberArk stored the value with the prefix
# already — drop the `license=` prefix in the template and re-apply.

# 4. The cmf.yaml pipeline (action=install, env=dev) now treats this
#    ExternalSecret as the source of truth — it skips the variable-group
#    create_labeled_secret call and waits for the Secret to materialize
#    before running the Helm install.
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
