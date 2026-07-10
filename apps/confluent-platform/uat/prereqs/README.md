# Prerequisites — dev CFK CP (non-TLS)

Documents the **non-TLS Opaque Secrets** the CFK Custom Resources one
level up depend on — license, MDS token keypair, OAuth client creds,
SASL passwords, Control Center basic auth. None of these are manifest-
based; they're created by the `confluent-platform.yaml` pipeline
`action=create-prereqs`.

The six **cert-manager Certificate CRs** that produce the `*-tls`
Secrets have moved to [`../cert-manager/`](../cert-manager/). See that
README for the TLS side.

## Non-TLS Secrets — pipeline-created (temporary)

Eleven Opaque Secrets the CFK CRs reference for OAuth, SASL, license, MDS token signing, and Control Center basic auth. **CyberArk via ESO is the target**; until that's wired up, the `confluent-platform` pipeline `action: create-prereqs` creates them from secret variables in the `kafka-openshift-credentials-<env>` variable group.

| Secret | Keys | Source variable(s) (in `kafka-openshift-credentials-<env>`) |
|---|---|---|
| `confluent-license` | `license.txt` | `<env>-confluent-license` |
| `mds-token-keypair` | `mdsTokenKeyPair.pem` | `<env>-mds-token-keypair-pem` |
| `sasl-plain-internal` | `admin`<br>`client`<br>`schema_registry`<br>`kafka_connect`<br>`kafka_rest`<br>`control_center` | `<env>-sasl-plain-admin-pwd`<br>`<env>-sasl-plain-client-pwd`<br>`<env>-sasl-plain-schema-registry-pwd`<br>`<env>-sasl-plain-kafka-connect-pwd`<br>`<env>-sasl-plain-kafka-rest-pwd`<br>`<env>-sasl-plain-control-center-pwd` |
| `oauth-broker` | `clientId`<br>`clientSecret` | `<env>-oauth-broker-client-id`<br>`<env>-oauth-broker-client-secret` |
| `oauth-schemaregistry` | `clientId`<br>`clientSecret` | `<env>-oauth-schemaregistry-client-id`<br>`<env>-oauth-schemaregistry-client-secret` |
| `oauth-connect` | `clientId`<br>`clientSecret` | `<env>-oauth-connect-client-id`<br>`<env>-oauth-connect-client-secret` |
| `oauth-kafkarest` | `clientId`<br>`clientSecret` | `<env>-oauth-kafkarest-client-id`<br>`<env>-oauth-kafkarest-client-secret` |
| `oauth-controlcenter` | `clientId`<br>`clientSecret` | `<env>-oauth-controlcenter-client-id`<br>`<env>-oauth-controlcenter-client-secret` |
| `oauth-mds-rest` | `clientId`<br>`clientSecret` | `<env>-oauth-mds-rest-client-id`<br>`<env>-oauth-mds-rest-client-secret` |
| `c3-prometheus-basic-auth` | `username`<br>`password` | `<env>-c3-prometheus-username`<br>`<env>-c3-prometheus-password` |
| `c3-alertmanager-basic-auth` | `username`<br>`password` | `<env>-c3-alertmanager-username`<br>`<env>-c3-alertmanager-password` |

The **MDS keypair** is the only one with a non-obvious source: the VM brokers' `/var/ssl/private/tokenKeypair.pem`. **The variable value must be base64-encoded as a single line** — ADO's UI silently strips newlines from multiline secret variables, which then breaks Java's PEM parser at runtime (it requires the BEGIN/END markers on their own lines). On any dev VM broker:

```
sudo base64 -w0 /var/ssl/private/tokenKeypair.pem
```

Paste the resulting single-line string (~4400 chars for a 4096-bit RSA key) into `<env>-mds-token-keypair-pem` with the 🔒 secret lock. The `create-prereqs` action decodes it back to PEM before landing the Secret, and validates that the decoded content actually starts with `-----BEGIN` — pipeline fails fast with a clear message if either step doesn't check out.

Reusing the VM keypair keeps VM-issued MDS tokens valid in the CFK cluster during the cluster-link migration window — **do not generate a fresh keypair without coordination** as doing so invalidates every outstanding token.

> **OAuth client decision**: today the variable group reuses the existing VM client IDs (e.g. `0oa1owlvf2p9hiaSx358` for the broker). When FCB Okta admins decide whether to keep reusing or to provision new CFK-specific clients, the only change needed is in the variable group — no manifest changes here.

## Run order

```
1. confluent-platform.yaml  action=create-prereqs   (creates the 11 Opaque Secrets)
2. confluent-platform.yaml  action=install          (applies Certificates, waits for *-tls Secrets,
                                                     then applies the CFK CRs)
```

`create-prereqs` is **idempotent** — it uses `oc apply` semantics under the hood, so re-running it overwrites Secrets with whatever's in the variable group at run time. Safe to re-run after rotating an OAuth client secret in Okta or rotating any user password.

The pipeline **`oc describe`s** each Secret after creation (showing key names + sizes) but **never dumps values into the log**. To verify a value, pull the Secret directly outside the pipeline:

```
oc -n dah-flink-uat get secret <name> -o jsonpath='{.data.<key>}' | base64 -d
```

---

## Dev values to paste into `dev-openshift-credentials` *(TEMPORARY — delete this section after Tushar has loaded them into the variable group)*

> ⚠️ This section contains real credentials extracted from the dev VM `.properties` files. **Remove it from the committed README as soon as Tushar finishes populating `dev-openshift-credentials`.** The values stay in the ADO secret variables and the pipeline reads them from there; no need to keep them in Git.
>
> Excludes `uat-confluent-license` (already in the variable group from CMF) and `uat-mds-token-keypair-pem` (multi-line PEM — copy verbatim from VM `/var/ssl/private/tokenKeypair.pem`).

### SASL PLAIN inter-broker passwords

Source: broker `.properties` line `listener.name.broker.plain.sasl.jaas.config=…user_<user>=<password>…`

| Variable | Value |
|---|---|
| `uat-sasl-plain-admin-pwd` | `admin-secret` |
| `uat-sasl-plain-client-pwd` | `client-secret` |
| `uat-sasl-plain-schema-registry-pwd` | `schema_registry-secret` |
| `uat-sasl-plain-kafka-connect-pwd` | `kafka_connect-secret` |
| `uat-sasl-plain-kafka-rest-pwd` | `kafka_rest-secret` |
| `uat-sasl-plain-control-center-pwd` | `control_center-secret` |

> These look like literal defaults that were never replaced (`<user>-secret`). Fine for dev; rotate before stg / prd-1 / prd-2.

### OAuth client credentials (Okta)

| Variable | Value | Source field in VM properties |
|---|---|---|
| `uat-oauth-broker-client-id` | `0oa1owlvf2p9hiaSx358` | broker `confluent.bearer.auth.client.id` |
| `uat-oauth-broker-client-secret` | `r4xpfcAyxhI6xng4DeWgSQ9sPodj99O-17xZ5hIZ-BSD1B8ai41_B2T8rSffdXJs` | broker `confluent.bearer.auth.client.secret` |
| `uat-oauth-schemaregistry-client-id` | `0oa1owlvf2p9hiaSx358` *(same client as broker)* | SR `confluent.metadata.oauthbearer.login.client.id` |
| `uat-oauth-schemaregistry-client-secret` | `r4xpfcAyxhI6xng4DeWgSQ9sPodj99O-17xZ5hIZ-BSD1B8ai41_B2T8rSffdXJs` *(same secret as broker)* | SR `confluent.metadata.oauthbearer.login.client.secret` |
| `uat-oauth-connect-client-id` | `0oa1owkc382b6S6oj358` | Connect `confluent.metadata.oauthbearer.login.client.id` |
| `uat-oauth-connect-client-secret` | `TGbBqg4XCIN6ktGkLmMQjZVeqc6ynXUBb-Pnv_8lScIQdKJZut40DPNAx2YNSgb6` | Connect `confluent.metadata.oauthbearer.login.client.secret` |
| `uat-oauth-kafkarest-client-id` | `0oa1owlmto7c5zBWy358` | REST Proxy `confluent.metadata.oauthbearer.login.client.id` |
| `uat-oauth-kafkarest-client-secret` | `WL8iLzfjwROtpGgKAgpmiiRY9jWREQEDLdW8AGeDiD6mieJoOly0_V0ZrfmJuSDh` | REST Proxy `confluent.metadata.oauthbearer.login.client.secret` |
| `uat-oauth-controlcenter-client-id` | `0oa1owk00kzjNnTxw358` | C3 `confluent.metadata.oauthbearer.login.client.id` |
| `uat-oauth-controlcenter-client-secret` | `Hsf0LrSnbs3rQMR_46bFXSIgwDRBZ_rj0c1ZO1VSAYsn9DuegbN3midCQBo36VRS` | C3 `confluent.metadata.oauthbearer.login.client.secret` |
| `uat-oauth-mds-rest-client-id` | `0oa1owjyrmdJ4KqUt358` | broker `kafka.rest.confluent.metadata.oauthbearer.login.client.id` |
| `uat-oauth-mds-rest-client-secret` | `nZRMA8zFHIjlqbsnCLZyJWI5mzyMOU2gLGJ_FSiHFH9kmSf8stpBDcbXe0o2AwZb` | broker `kafka.rest.confluent.metadata.oauthbearer.login.client.secret` |

> The VM reuses the **same Okta client** (`0oa1owlvf2p9hiaSx358`) for Broker and Schema Registry. CFK doesn't require them to be separate; carry the reuse over. If Okta admins want per-component identities later, only the variable group needs updating — no manifest changes.

A separate **OIDC client** (`0oa1o0ea1m26pITBQ358` / `rLioO_quXC_PJI1MOl-5B9r0GWveI8_QwchYxR-idD4S4rxH_X5BDbdaPsWrXEI3`) is used by the broker MDS for human SSO flow. Not referenced by any current CFK CR, so not added to the variable group today — keep in mind if the Confluent UI SSO is wired up later.

### Control Center basic-auth (Prometheus + AlertManager)

Source: C3 `.properties` lines `confluent.controlcenter.prometheus.basic.auth.user.info` and `confluent.controlcenter.alertmanager.basic.auth.user.info` (both `confluent:bFGeIT2K`).

| Variable | Value |
|---|---|
| `uat-c3-prometheus-username` | `confluent` |
| `uat-c3-prometheus-password` | `bFGeIT2K` |
| `uat-c3-alertmanager-username` | `confluent` |
| `uat-c3-alertmanager-password` | `bFGeIT2K` |

> Same `confluent:bFGeIT2K` pair is also used by the broker telemetry exporter (`confluent.telemetry.exporter._c3.api.key/secret`). Weak credential — rotate before prod.

**Total**: 22 variables here + `uat-confluent-license` (existing) + `uat-mds-token-keypair-pem` (paste VM PEM separately) = **24 variables in `dev-openshift-credentials`**.
