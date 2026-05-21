# Prerequisites — stg CFK CP

Same prereq pattern as dev / qa / uat; only the env-suffixed names change. See the [dev prereqs README](../../dev/prereqs/README.md) for the full design rationale (TLS Secrets via cert-manager, 11 Opaque Secrets sourced from the variable group, MDS keypair encoding, etc.).

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

## Differences from dev / qa / uat

- **Namespace**: `dah-flink-stg`
- **Keyfactor `Environment` annotation**: `Non-Prod-STG`
- **VM CP analog exists but is not yet sourced in this repo**: FCB does run a VM STG CP (per `project_cfk_migration.md`), but the VM `.properties` files have not been added to [`../../cp-confluent/stg/`](../../cp-confluent/stg/) yet. Until they are, the OAuth Secret *values* reuse UAT's (same approach used for QA). The prereq Secret *shape* — key names, file formats — is identical to dev/qa/uat.

## Variable group values

The `stg-openshift-credentials` variable group needs the same 24 entries as `dev-openshift-credentials` (see [dev prereqs README](../../dev/prereqs/README.md#dev-values-to-paste-into-dev-openshift-credentials-temporary--delete-this-section-after-tushar-has-loaded-them-into-the-variable-group)), prefixed `stg-` instead of `dev-`.

**STG-specific provisioning required before first install:**

| Group | What needs to be done | Owner |
|---|---|---|
| VM STG `.properties` | Pull the VM STG broker/controller/SR/Connect/REST/C3 `.properties` files into [`../../cp-confluent/stg/`](../../cp-confluent/stg/). Mirrors what we already have under `cp-confluent/dev/` and `cp-confluent/uat/`. Source of truth for all the values below. | Tushar |
| Okta clients | Once the VM STG `.properties` are in repo, lift the STG OAuth client IDs / secrets out of them — same fields the UAT README points at (broker `confluent.bearer.auth.client.{id,secret}`, etc.). If Okta admins want CFK-specific clients instead of reusing the VM-side ones, they provision and Tushar pastes the new values into the variable group. | FCB Okta admins / Tushar |
| SASL inter-broker passwords | Lift from the VM STG broker properties `listener.name.broker.plain.sasl.jaas.config` line (`user_admin`, `user_client`, `user_schema_registry`, `user_kafka_connect`, `user_kafka_rest`, `user_control_center`). **Rotate** before STG ever sees real staging traffic — the dev/uat values are literal defaults (`<user>-secret`). | Tushar |
| Confluent license | Reuse the existing org license (already in the dev / uat variable groups). | Already on file |
| MDS token keypair | Reuse the VM STG broker's `/var/ssl/private/tokenKeypair.pem` so VM-issued tokens stay valid during cluster-link migration. Base64 the PEM as a single line (`sudo base64 -w0`) and paste into `stg-mds-token-keypair-pem` exactly as documented for dev. | Tushar / Operations |
| C3 Prometheus + AlertManager basic auth | Lift from the VM C3 `.properties` `confluent.controlcenter.{prometheus,alertmanager}.basic.auth.user.info` lines. Rotate before staging traffic. | Tushar |

## Run order

```
1. confluent-platform.yaml  environment=stg  action=create-prereqs   (creates the 11 Opaque Secrets)
2. confluent-platform.yaml  environment=stg  action=install          (applies Certificates, waits for *-tls Secrets,
                                                                     then applies the CFK CRs)
```
