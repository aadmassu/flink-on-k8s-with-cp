# Prerequisites — dev CFK CP

Everything in this folder is a **supporting prerequisite** for the CFK Custom Resources one level up. Nothing here is a Confluent Platform CR itself; it's the TLS material and the bag of Opaque Secrets the CRs depend on.

## What's here

```
prereqs/
├── README.md  (this file)
├── kafka-tls-certificate.yaml           # cert-manager Certificate, lands secret/kafka-tls
├── kraftcontroller-tls-certificate.yaml # cert-manager Certificate, lands secret/kraftcontroller-tls
├── schemaregistry-tls-certificate.yaml  # cert-manager Certificate, lands secret/schemaregistry-tls
├── connect-tls-certificate.yaml         # cert-manager Certificate, lands secret/connect-tls
├── kafkarest-tls-certificate.yaml       # cert-manager Certificate, lands secret/kafkarest-tls
└── controlcenter-tls-certificate.yaml   # cert-manager Certificate, lands secret/controlcenter-tls
```

## TLS Secrets — managed by cert-manager

The six Certificate CRs each request a Keyfactor-issued cert and land a Secret with `tls.crt` / `tls.key` / `ca.crt`. Same pattern used by [`apps/confluent-cmf/dev/cmf-tls-certificate.yaml`](../../../confluent-cmf/dev/cmf-tls-certificate.yaml). The pipeline applies them as part of the `install` action — no manual `oc apply` needed.

## Non-TLS Secrets — pipeline-created (temporary)

Eleven Opaque Secrets the CFK CRs reference for OAuth, SASL, license, MDS token signing, and Control Center basic auth. **CyberArk via ESO is the target**; until that's wired up, the `confluent-platform` pipeline `action: create-prereqs` creates them from secret variables in the `<env>-openshift-credentials` variable group.

| Secret | Keys | Source variable(s) (in `<env>-openshift-credentials`) |
|---|---|---|
| `confluent-license` | `license.txt` | `<env>-confluent-license` |
| `mds-token-keypair` | `mdsTokenKeyPair.pem` | `<env>-mds-token-keypair-pem` |
| `sasl-plain-internal` | `admin`, `client`, `schema_registry`, `kafka_connect`, `kafka_rest`, `control_center` | `<env>-sasl-plain-<user>-pwd` (6 vars) |
| `oauth-broker` | `clientId`, `clientSecret` | `<env>-oauth-broker-client-id` / `-client-secret` |
| `oauth-schemaregistry` | `clientId`, `clientSecret` | `<env>-oauth-schemaregistry-client-id` / `-client-secret` |
| `oauth-connect` | `clientId`, `clientSecret` | `<env>-oauth-connect-client-id` / `-client-secret` |
| `oauth-kafkarest` | `clientId`, `clientSecret` | `<env>-oauth-kafkarest-client-id` / `-client-secret` |
| `oauth-controlcenter` | `clientId`, `clientSecret` | `<env>-oauth-controlcenter-client-id` / `-client-secret` |
| `oauth-mds-rest` | `clientId`, `clientSecret` | `<env>-oauth-mds-rest-client-id` / `-client-secret` |
| `c3-prometheus-basic-auth` | `username`, `password` | `<env>-c3-prometheus-username` / `-password` |
| `c3-alertmanager-basic-auth` | `username`, `password` | `<env>-c3-alertmanager-username` / `-password` |

The **MDS keypair** is the only one with a non-obvious source: the VM brokers' `/var/ssl/private/tokenKeypair.pem`. Copy that file's contents into the `<env>-mds-token-keypair-pem` secret variable verbatim (multiline PEM-encoded RSA). Reusing the VM keypair keeps VM-issued MDS tokens valid in the CFK cluster during the cluster-link migration window — **do not generate a fresh keypair without coordination** as doing so invalidates every outstanding token.

> **OAuth client decision**: today the variable group reuses the existing VM client IDs (e.g. `0oa1owiage2MyoHdt358` for the broker). When FCB Okta admins decide whether to keep reusing or to provision new CFK-specific clients, the only change needed is in the variable group — no manifest changes here.

## Run order

```
1. confluent-platform.yaml  action=create-prereqs   (creates the 11 Opaque Secrets)
2. confluent-platform.yaml  action=install          (applies Certificates, waits for *-tls Secrets,
                                                     then applies the CFK CRs)
```

`create-prereqs` is **idempotent** — it uses `oc apply` semantics under the hood, so re-running it overwrites Secrets with whatever's in the variable group at run time. Safe to re-run after rotating an OAuth client secret in Okta or rotating any user password.

The pipeline **`oc describe`s** each Secret after creation (showing key names + sizes) but **never dumps values into the log**. To verify a value, pull the Secret directly outside the pipeline:

```
oc -n dah-flink-dev get secret <name> -o jsonpath='{.data.<key>}' | base64 -d
```
