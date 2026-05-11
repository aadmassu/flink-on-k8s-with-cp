# Prerequisite Secrets — dev CFK CP

Non-TLS Secrets that must exist in `dah-flink-dev` **before** any CR in this folder applies. Same pattern as the CMF stack: pipeline-managed today, will move to **CyberArk via External Secrets Operator (ESO)** alongside the rest of FCB's secrets (see [`docs/External Secrets.pdf`](../../../docs/External%20Secrets.pdf)).

## TLS Secrets — handled inline by cert-manager Certificate CRs

TLS Secrets (`kafka-tls`, `kraftcontroller-tls`, `schemaregistry-tls`, `connect-tls`, `kafkarest-tls`, `controlcenter-tls`) are **not** pipeline-managed. Each has a sibling `*-tls-certificate.yaml` in this folder that issues the cert through FCB's Keyfactor `ClusterIssuer` and lands the Secret with `tls.crt` / `tls.key` / `ca.crt`. Same pattern as [`apps/confluent-cmf/dev/cmf-tls-certificate.yaml`](../../confluent-cmf/dev/cmf-tls-certificate.yaml).

Apply the Certificate CRs before the component CRs; the operator will block reconciliation until the Secret each `tls.secretRef` points at exists.

## Confluent license

| Secret name | Component scope | Key |
|---|---|---|
| `confluent-license` | brokers, SR, Connect, REST Proxy, C3 | `license.txt` |

Same Secret name CMF uses; populated by the existing pipeline-managed flow from the `dev-confluent-license` variable group.

## OAuth / IDP credentials (Okta — `myapps.firstcitizens.com`)

The VM cluster uses a different OAuth client per component (visible in each `.properties` file as `confluent.metadata.oauthbearer.login.client.id`). Mirror that in K8s Secrets so each component authenticates to MDS/Okta with its own identity.

| Secret name | Keys | Source in VM properties |
|---|---|---|
| `oauth-broker` | `clientId`, `clientSecret` | broker `confluent.bearer.auth.client.*` (`0oa1owiage2MyoHdt358`) |
| `oauth-schemaregistry` | `clientId`, `clientSecret` | SR `kafkastore.sasl.jaas.config` clientId (`0oa1owiage2MyoHdt358`) |
| `oauth-connect` | `clientId`, `clientSecret` | Connect `confluent.metadata.oauthbearer.login.client.*` (`0oa1owi0yntGMBvPS358`) |
| `oauth-kafkarest` | `clientId`, `clientSecret` | REST Proxy `confluent.metadata.oauthbearer.login.client.*` (`0oa1owi3wkxJS3b3b358`) |
| `oauth-controlcenter` | `clientId`, `clientSecret` | C3 `confluent.metadata.oauthbearer.login.client.*` (`0oa1ov6h5mwmQTCKI358`) |
| `oauth-mds-rest` | `clientId`, `clientSecret` | broker `kafka.rest.confluent.metadata.oauthbearer.login.client.*` (`0oa1owhtq2olDZWwf358`) |

> **Action required**: confirm whether FCB Okta admins want us to **reuse the existing VM client IDs** for the CFK cluster or **provision new ones** for the CFK identities. Reusing means simpler migration; new ones means we can revoke them independently. Defaults below assume **reuse** until told otherwise.

## SASL PLAIN inter-broker credentials

The VM brokers use SASL PLAIN for the inter-broker `BROKER` listener with shared passwords baked into `listener.name.broker.plain.sasl.jaas.config`. CFK auto-generates these when you enable PLAIN, but if you want exact parity with the VM (so a cluster-link to VM keeps working) carry the same users over:

| Secret name | Keys |
|---|---|
| `sasl-plain-internal` | `admin`, `client`, `schema_registry`, `kafka_connect`, `kafka_rest`, `control_center` (each value = the user's password) |

Pull values from the VM `listener.name.broker.plain.sasl.jaas.config` line.

## SBC / Metrics Reporter & Telemetry

These don't need their own Secrets — they use the inter-broker SASL PLAIN credentials (`sasl-plain-internal`) and the existing TLS material. C3's Prometheus / AlertManager basic-auth user (`confluent:bFGeIT2K` in the VM C3 properties) goes into:

| Secret name | Keys |
|---|---|
| `c3-prometheus-basic-auth` | `username` (= `confluent`), `password` |
| `c3-alertmanager-basic-auth` | `username`, `password` |

## Creation pattern

Same as the CMF stack: pipeline creates them with FCB labels, sources values from the per-env variable group. Will move to CyberArk ESO once that integration is in place. The pipeline that installs this CP cluster (TBD — `confluent-platform.yaml`?) will create the OAuth / license / SASL Secrets the same way `cmf.yaml` creates `cmf-db-credentials`, `cmf-encryption-key`, `confluent-license`.

TLS Secrets are different — they are created by **cert-manager** from `Certificate` CRs, not by the pipeline directly. The pipeline pre-flight should verify each `*-tls` Secret exists (same guard `cmf.yaml` has for `cmf-tls`) and abort with a clear message if any are missing.
