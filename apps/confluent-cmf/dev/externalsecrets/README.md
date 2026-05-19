# CMF dev — CyberArk integration via External Secrets Operator (ESO)

The container team installed an `external-secrets.io/v1` `SecretStore`
named **`11547-d-key-fp`** in the `dah-flink-dev` namespace. It proxies
to FCB CyberArk's Central Credential Provider (CCP) over a webhook
provider. Once these `ExternalSecret` objects are applied, ESO calls
the SecretStore on its `refreshInterval` (1h), pulls the credential
content from CyberArk, and materializes the Kubernetes `Secret` objects
the CMF Helm chart consumes.

## Architecture

```
+---------------------------+        +----------------------------+
| CyberArk safe             |        | dah-flink-dev namespace    |
|   11547_D_KEY_FP          |        |                            |
|                           |        |  +-------------------+     |
|   accounts:               |        |  | SecretStore       |     |
|     - artifactory-svc-... | <--ESO-+--+ 11547-d-key-fp    |     |
|     - artifactory-db-...  | webhook|  | (container team)  |     |
|     - dev-confluent-licen.|        |  +---------+---------+     |
+---------------------------+        |            ^               |
                                     |            | secretStoreRef|
                                     |  +---------+---------+     |
                                     |  | ExternalSecret    |     |
                                     |  | (this directory)  |     |
                                     |  +---------+---------+     |
                                     |            | creates       |
                                     |            v               |
                                     |  +-------------------+     |
                                     |  | Secret            |     |
                                     |  | (consumed by CMF) |     |
                                     |  +-------------------+     |
                                     +----------------------------+
```

## The SecretStore URL contract (read-only — for reference)

From Tushar's screenshot, the webhook URL the container team configured is:

```
https://pam-ccp.fcpd.fcbint.net/AIMWebServiceIP/api/Accounts
  ?ConnectionTimeout=30
  &AppId=APP-11547-D
  &Query=Safe=11547_D_KEY_FP
         ;UserName={{ .remoteRef.key }}
         ;Address={{ .remoteRef.property }}
```

So every `ExternalSecret` in this directory passes:
- `remoteRef.key` → the **CyberArk Account UserName** field
- `remoteRef.property` → the **CyberArk Account Address** field

CyberArk responds with `{"Content": "<the-secret>"}`. The SecretStore
extracts `$.Content` (via `result.jsonPath`) and ESO hands the bare
string to our `template` block.

## Files in this directory

| File | CyberArk account (`UserName`) | Creates k8s Secret | Used by CMF as… |
|---|---|---|---|
| `externalsecret-confluent-license.yaml` | `dev-confluent-license` | `confluent-license` (key `license.txt` in `license=<JWT>` format) | `license.secretRef: confluent-license` |
| `externalsecret-cmf-db-password.yaml` | `artifactory-db-user-password` *(see naming note below)* | `cmf-db-credentials` (key `password`) | `cmf.database.jdbc.password.kubernetesSecretName: cmf-db-credentials` |
| `externalsecret-artifactory-pull-secret.yaml` | `artifactory-svc-user-password` | `artifactory-pull-secret` (type `kubernetes.io/dockerconfigjson`) | `imagePullSecrets: [{ name: artifactory-pull-secret }]` |

### Naming note on `artifactory-db-user-password`

That account name is confusing for CMF's DB password — the literal
account name in CyberArk per Tushar's screenshot is
`artifactory-db-user-password`, but we're using it for CMF's SQL
Server connection. Two possibilities:

1. The container team is reusing the name conventionally — same account
   holds the password CMF needs. (Most likely.)
2. There's a separate `cmf-db-user-password` account we should be using
   instead, and the screenshot just enumerated what was visible.

Confirm with Tushar before applying. If the latter, change `data[0].remoteRef.key`
in `externalsecret-cmf-db-password.yaml`.

## Three pieces you must fill in before applying

Every manifest has a `TODO-…` placeholder where the **CyberArk Account
`Address`** value belongs (the URL template feeds this as the
`Address=` query parameter). CyberArk accounts are uniquely identified
by Safe + UserName + Address, so we can't omit it.

Ask Tushar or look in CyberArk UI for the Address attribute on each of
the three accounts. Common patterns:
- A hostname (e.g., `artifactory.fcbint.net`, `sqlserver-dev.fcbint.net`)
- An environment marker (e.g., `dev`, `non-prod`)
- A system identifier (e.g., `FCB-DAH-DEV`)

Also in `externalsecret-artifactory-pull-secret.yaml`, two more
TODOs you must fill in:
- `TODO-artifactory-svc-username` (appears twice — username + the
  pre-base64'd `auth` string). CyberArk only stores the password,
  not the username. Use whatever service-account name Tushar
  configured the password for, e.g. `svc-flink-cp-d` or `svc-11547-d`.

## Apply order

ESO ExternalSecrets must be applied **before** the CMF Helm install so
the secrets exist by the time CMF pods start.

```bash
# 1. Apply the ExternalSecrets in dah-flink-dev.
oc apply -f externalsecret-confluent-license.yaml
oc apply -f externalsecret-cmf-db-password.yaml
oc apply -f externalsecret-artifactory-pull-secret.yaml

# 2. Verify each ExternalSecret reaches SecretSynced=True.
oc -n dah-flink-dev get externalsecrets
oc -n dah-flink-dev get externalsecret confluent-license       -o yaml | grep -A 5 status:
oc -n dah-flink-dev get externalsecret cmf-db-credentials      -o yaml | grep -A 5 status:
oc -n dah-flink-dev get externalsecret artifactory-pull-secret -o yaml | grep -A 5 status:

# 3. Verify the materialized Secrets exist and have the right keys.
oc -n dah-flink-dev get secret confluent-license            -o jsonpath='{.data.license\.txt}'      | base64 -d | head -1
oc -n dah-flink-dev get secret cmf-db-credentials           -o jsonpath='{.data.password}'         | base64 -d | wc -c
oc -n dah-flink-dev get secret artifactory-pull-secret      -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d | jq .

# 4. Re-run the existing CMF Helm install. It will pick up the existing
#    Secrets by name (cmf-db-credentials and confluent-license are
#    already referenced in apps/confluent-cmf/dev/values.yaml).
#    Add the imagePullSecret wiring per the values.yaml section below.
```

## CMF values.yaml wiring

The existing `apps/confluent-cmf/dev/values.yaml` already references
`cmf-db-credentials` (for DB password) and `confluent-license` (for
license) by name, so those slot in with **zero values.yaml changes**.

The only addition is `imagePullSecrets`, which CMF doesn't reference
today (the cluster has been pulling via a cluster-default pull secret).
Add this near the `image:` block:

```yaml
# Pull images from FCB Artifactory using the CyberArk-sourced credential
# materialized by externalsecrets/externalsecret-artifactory-pull-secret.yaml.
imagePullSecrets:
  - name: artifactory-pull-secret
```

## Rotation

ESO refreshes each `ExternalSecret` every `refreshInterval` (we set 1h).
When the container team rotates a credential in CyberArk, the next
refresh picks it up and updates the k8s `Secret`. The CMF pod won't
automatically restart — it'll still hold the old value in memory until
restarted. For zero-touch rotation, layer in either:
- `kyverno/reloader` annotations on the CMF Deployment, or
- a sidecar that watches the `Secret` mount and signals the JVM.

Out of scope for this initial integration — flag for hardening later.
