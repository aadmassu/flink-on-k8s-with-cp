# Prerequisites — qa CFK CP

Same prereq pattern as dev and uat; only the env-suffixed names change. See the [dev prereqs README](../../dev/prereqs/README.md) for the full design rationale (TLS Secrets via cert-manager, 11 Opaque Secrets sourced from the variable group, MDS keypair encoding, etc.).

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

## Differences from dev / uat

- **Namespace**: `dah-flink-qa`
- **Keyfactor `Environment` annotation**: `Non-Prod-QA`
- **No VM CP analog**: FCB never built a VM QA CP, so there are no source `.properties` files under `cp-confluent/`. The prereq Secret *shape* (key names, file formats) is identical to dev/uat; the *values* must come from FCB. See "Variable group values" below.

## Variable group values

The `qa-openshift-credentials` variable group needs the same 24 entries as `dev-openshift-credentials` (see [dev prereqs README](../../dev/prereqs/README.md#dev-values-to-paste-into-dev-openshift-credentials-temporary--delete-this-section-after-tushar-has-loaded-them-into-the-variable-group)), prefixed `qa-` instead of `dev-`.

**QA-specific provisioning required before first install:**

| Group | What needs to be done | Owner |
|---|---|---|
| Okta clients | Decide whether QA reuses the UAT Okta application (cheapest — no new clients) or gets a dedicated QA application (cleanest separation). If dedicated, FCB Okta admins provision 6 new client IDs (broker, SR, Connect, REST, C3, MDS-REST) and the manifests get a `dahUAT_groups` → `dahQA_groups` and `11547.DAH(UAT)` → `11547.DAH(QA)` sweep. | FCB Okta admins |
| SASL inter-broker passwords | Pick six secrets (admin / client / schema_registry / kafka_connect / kafka_rest / control_center). UAT uses literal defaults (`<user>-secret`) — fine for non-prod, but at minimum pick something different per env so a leak in one doesn't compromise all. | Tushar |
| Confluent license | Reuse the existing org license (already in `dev-confluent-license` and `uat-confluent-license`). | Already on file |
| MDS token keypair | Choice between (a) reusing the same RSA keypair as dev/uat for development convenience, or (b) generating a fresh keypair per env for token-domain isolation. Either way: base64 the PEM as a single line (`sudo base64 -w0`) and paste into `qa-mds-token-keypair-pem` exactly as documented for dev. | Tushar / Operations |
| C3 Prometheus + AlertManager basic auth | Two username/password pairs. Reuse UAT's `confluent:bFGeIT2K` or rotate — both are dev-grade today and need rotating before prd anyway. | Tushar |

## Run order

```
1. confluent-platform.yaml  environment=qa  action=create-prereqs   (creates the 11 Opaque Secrets)
2. confluent-platform.yaml  environment=qa  action=install          (applies Certificates, waits for *-tls Secrets,
                                                                     then applies the CFK CRs)
```
