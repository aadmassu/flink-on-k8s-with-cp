# Prerequisites — uat CFK CP

Everything in this folder is a **supporting prerequisite** for the CFK Custom Resources one level up. Nothing here is a Confluent Platform CR itself; it's the TLS material and the bag of Opaque Secrets the CRs depend on.

## What's here

```
prereqs/
├── README.md  (this file)
├── kafka-tls-certificate.yaml           # cert-manager Certificate, lands secret/kafka-tls
├── kraftcontroller-tls-certificate.yaml # cert-manager Certificate, lands secret/kraftcontroller-tls
├── schemaregistry-tls-certificate.yaml  # cert-manager Certificate, lands secret/schemaregistry-tls  (SANs for 2 replicas)
├── connect-tls-certificate.yaml         # cert-manager Certificate, lands secret/connect-tls
├── kafkarest-tls-certificate.yaml       # cert-manager Certificate, lands secret/kafkarest-tls       (SANs for 2 replicas)
└── controlcenter-tls-certificate.yaml   # cert-manager Certificate, lands secret/controlcenter-tls
```

## TLS Secrets — managed by cert-manager

The six Certificate CRs each request a Keyfactor-issued cert and land a Secret with `tls.crt` / `tls.key` / `ca.crt`. Same pattern used by [`apps/confluent-cmf/`](../../../confluent-cmf/) for the CMF TLS cert. The pipeline applies them as part of the `install` action — no manual `oc apply` needed.

The Schema Registry and Kafka REST Proxy certs each carry **two per-pod SANs** (`<name>-0…`, `<name>-1…`) because the UAT topology runs **two replicas** of each (matching the VM UAT cluster).

## Non-TLS Secrets — pipeline-created (temporary)

Eleven Opaque Secrets the CFK CRs reference for OAuth, SASL, license, MDS token signing, and Control Center basic auth. **CyberArk via ESO is the target**; until that's wired up, the `confluent-platform` pipeline `action: create-prereqs` creates them from secret variables in the `uat-openshift-credentials` variable group.

The set of Secrets and the source-variable mapping is identical to dev — see [`../../dev/prereqs/README.md`](../../dev/prereqs/README.md) for the full table. Only the value prefix changes (`uat-…` instead of `dev-…`).

## Variable group values

Source: [`../../cp-confluent/uat/`](../../cp-confluent/uat/) — the VM UAT `.properties` files. Extract the same fields documented in the dev README:

| Variable | Source field in VM UAT properties |
|---|---|
| `uat-sasl-plain-admin-pwd` | broker `listener.name.broker.plain.sasl.jaas.config` → `user_admin=…` |
| `uat-sasl-plain-client-pwd` | broker `listener.name.broker.plain.sasl.jaas.config` → `user_client=…` |
| `uat-sasl-plain-schema-registry-pwd` | broker `…user_schema_registry=…` |
| `uat-sasl-plain-kafka-connect-pwd` | broker `…user_kafka_connect=…` |
| `uat-sasl-plain-kafka-rest-pwd` | broker `…user_kafka_rest=…` |
| `uat-sasl-plain-control-center-pwd` | broker `…user_control_center=…` |
| `uat-oauth-broker-client-id` | broker `confluent.bearer.auth.client.id` |
| `uat-oauth-broker-client-secret` | broker `confluent.bearer.auth.client.secret` |
| `uat-oauth-schemaregistry-client-id` | SR `confluent.metadata.oauthbearer.login.client.id` |
| `uat-oauth-schemaregistry-client-secret` | SR `confluent.metadata.oauthbearer.login.client.secret` |
| `uat-oauth-connect-client-id` | Connect `confluent.metadata.oauthbearer.login.client.id` |
| `uat-oauth-connect-client-secret` | Connect `confluent.metadata.oauthbearer.login.client.secret` |
| `uat-oauth-kafkarest-client-id` | REST Proxy `confluent.metadata.oauthbearer.login.client.id` |
| `uat-oauth-kafkarest-client-secret` | REST Proxy `confluent.metadata.oauthbearer.login.client.secret` |
| `uat-oauth-controlcenter-client-id` | C3 `confluent.metadata.oauthbearer.login.client.id` |
| `uat-oauth-controlcenter-client-secret` | C3 `confluent.metadata.oauthbearer.login.client.secret` |
| `uat-oauth-mds-rest-client-id` | broker `kafka.rest.confluent.metadata.oauthbearer.login.client.id` |
| `uat-oauth-mds-rest-client-secret` | broker `kafka.rest.confluent.metadata.oauthbearer.login.client.secret` |
| `uat-c3-prometheus-username` | C3 `confluent.controlcenter.prometheus.basic.auth.user.info` (left of `:`) |
| `uat-c3-prometheus-password` | C3 `confluent.controlcenter.prometheus.basic.auth.user.info` (right of `:`) |
| `uat-c3-alertmanager-username` | C3 `confluent.controlcenter.alertmanager.basic.auth.user.info` (left of `:`) |
| `uat-c3-alertmanager-password` | C3 `confluent.controlcenter.alertmanager.basic.auth.user.info` (right of `:`) |
| `uat-confluent-license` | broker `confluent.license` (raw JWT — same as CMF's license variable) |
| `uat-mds-token-keypair-pem` | VM `/var/ssl/private/tokenKeypair.pem` (single-line base64-encoded, see dev README) |

**Total**: 22 variables here + `uat-confluent-license` + `uat-mds-token-keypair-pem` = **24 variables in `uat-openshift-credentials`**.

## Run order

```
1. confluent-platform.yaml  environment=uat  action=create-prereqs   (creates the 11 Opaque Secrets)
2. confluent-platform.yaml  environment=uat  action=install          (applies Certificates, waits for *-tls Secrets,
                                                                     then applies the CFK CRs)
```

`create-prereqs` is **idempotent** — safe to re-run after rotating an OAuth client secret in Okta or rotating any user password.
