# QA CFK prerequisite Secrets

The Azure QAOps `create-prereqs` action creates these Kubernetes Secrets from
the `kafka-openshift-credentials-<env>` variable group until an ExternalSecret
owns the same `spec.target.name`. The pipeline never overwrites an ESO-owned
Secret.

No credential values belong in this repository.

## Authentication model

- Kafka internal listener and the KRaft controller path: SASL/PLAIN over TLS.
- Managed Confluent components: their existing QA OAuth identities with RBAC.
- External Kafka application listener: OAuth over TLS.
- A dedicated mTLS application listener is intentionally deferred until its
  exposure, certificates, principal mapping, and role bindings are approved.

## Pipeline-created Secrets

| Secret | Required keys | Variable source |
|---|---|---|
| `confluent-license` | `license.txt` (raw license) | `<env>-confluent-license` |
| `cfk-license` | `license.txt` (`license=<value>`) | `<env>-confluent-license` |
| `mds-token-keypair` | `mdsTokenKeyPair.pem`, `mdsPublicKey.pem` | `<env>-mds-token-keypair-pem` |
| `sasl-plain-internal` | `plain-users.json`, listener aliases, `plain.txt`, `plain-interbroker.txt` | `<env>-sasl-plain-admin-pwd` |
| `oauth-broker` | `clientId`, `clientSecret`, `bearer.txt`, `oauth.txt`, `oidcClientSecret.txt` | `<env>-oauth-broker-client-*` |
| `oauth-schemaregistry` | same OAuth key set | `<env>-oauth-schemaregistry-client-*` |
| `oauth-connect` | same OAuth key set | `<env>-oauth-connect-client-*` |
| `oauth-kafkarest` | same OAuth key set | `<env>-oauth-kafkarest-client-*` |
| `oauth-controlcenter` | same OAuth key set | `<env>-oauth-controlcenter-client-*` |
| `oauth-mds-rest` | same OAuth key set | `<env>-oauth-mds-rest-client-*` |
| `oauth-mds-sso` | same OAuth key set | `<env>-oauth-mds-sso-client-*` |
| `c3-prometheus-server-basic-auth` | server `basic.txt` | `<env>-c3-prometheus-*` |
| `c3-prometheus-client-basic-auth` | client `basic.txt` | `<env>-c3-prometheus-*` |
| `c3-alertmanager-server-basic-auth` | server `basic.txt` | `<env>-c3-alertmanager-*` |
| `c3-alertmanager-client-basic-auth` | client `basic.txt` | `<env>-c3-alertmanager-*` |
| `controlcenter-basic-auth` | `basic.txt` | current Control Center credential variables |

The compatibility aliases in `sasl-plain-internal` all contain the same single
`admin` credential. They cover the canonical Confluent key names and the
listener-specific names required by the installed CFK 3.2 admission behavior.
Schema Registry, Connect, REST Proxy, and Control Center do not receive separate
PLAIN passwords because they retain OAuth/RBAC identities.

## MDS keypair input

The MDS private key variable is a single-line base64 value. The pipeline decodes
it, validates the PEM, derives the public key, and creates both required keys.
Coordinate rotation because changing the signing key invalidates outstanding
MDS tokens.

## Run order

1. Run `create-prereqs`.
2. Run `install-or-update`.
3. Confirm Kafka and KRaft are cluster-ready before applying dependent CRs.
4. Validate each ExternalSecret with `SecretSynced=True` before removing the
   corresponding Azure QAOps variable.
