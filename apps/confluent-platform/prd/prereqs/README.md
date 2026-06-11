# Prerequisites — prd CFK CP (non-TLS)

> **PLACEHOLDER stub.** Walk this file with FCB ops before the first
> `action=create-prereqs` run on prd. The design is identical to dev/qa/uat;
> only the env-suffixed names + Prod-Okta values change.

Same non-TLS prereq pattern as dev / qa / uat — eleven Opaque Secrets
(license, MDS token keypair, OAuth client creds, SASL passwords, Control
Center basic auth) that the CFK Custom Resources one level up depend on.
None are manifest-based; the `confluent-platform.yaml` pipeline
`action=create-prereqs` creates them from secret variables in the
`prd-openshift-credentials` variable group.

See the [dev prereqs README](../../dev/prereqs/README.md) for the full
table, design rationale, and the MDS-keypair base64 gotcha.

The six **cert-manager Certificate CRs** that produce the `*-tls`
Secrets live in [`../cert-manager/`](../cert-manager/) — see that
README for the TLS side.

## Differences from dev / qa / uat

- **Namespace**: `dah-flink-prd`
- **Keyfactor `Environment` annotation**: `Prod`
- **OAuth scope**: `11547.DAH(Prod)`
- **Groups claim**: `dahProd_groups`
- **Source VM properties**: [`../../cp-confluent/prd-1/`](../../cp-confluent/) — VM CP prd primary (the prd-1 / prd-2 split mirrors the OpenShift prd / dr split)

## Variable group values

The `prd-openshift-credentials` variable group needs the same 24 entries
as `dev-openshift-credentials` / `uat-openshift-credentials`, prefixed
`prd-` instead. Source them from the VM CP prd-1 `.properties` files
following the same field-extraction table in the uat prereqs README.

**Prd-specific provisioning required before first install:**

| Group | What needs to be done | Owner |
|---|---|---|
| Okta clients | Confirm whether prd uses a dedicated Prod Okta application (typical for production) or reuses uat's. If dedicated, six client IDs (broker, SR, Connect, REST, C3, MDS-REST) need provisioning by FCB Okta admins. | FCB Okta admins |
| SASL inter-broker passwords | Pick six secrets (admin / client / schema_registry / kafka_connect / kafka_rest / control_center). **Do NOT reuse non-prod values** — prd needs distinct secrets that have never been used in lower envs. | Tushar |
| Confluent license | Reuse the existing org license; the `confluent-license` ExternalSecret for prd already references CyberArk safe `11547_P_KEY_FP`. | Already on file |
| MDS token keypair | Generate a fresh prd RSA keypair (do NOT reuse dev/qa/uat). Base64 the PEM as a single line (`sudo base64 -w0`) and paste into `prd-mds-token-keypair-pem` per the dev README's instructions. | Operations |
| C3 Prometheus + AlertManager basic auth | Two username/password pairs. **Rotate** — anything reused from non-prod must be replaced. | Tushar |

## Run order

```
1. confluent-platform.yaml  environment=prd  action=create-prereqs   (creates the 11 Opaque Secrets)
2. confluent-platform.yaml  environment=prd  action=install          (applies Certificates, waits for *-tls Secrets,
                                                                      then applies the CFK CRs)
```

## Open items before first prd install

- Confirm the OAuth scope / groupsClaim with FCB Okta admins — this stub assumes `11547.DAH(Prod)` and `dahProd_groups` but the actual Prod-tenant convention may differ.
- Confirm the cluster's external Kafka LB domain — placeholder is `kafka.prd.dah.fcbint.net`; the SANs in `../cert-manager/kafka-tls-certificate.yaml` must match what Container team configured.
- Confirm prd ResourceQuota — every CR sizing block is inherited from dev and undersized for production traffic. See `runbook/LESSONS_LEARNED.md` A3 for the init-container floor and the Application Infrastructure Workbook (linked from `ISSUE-TRACKER.md` tracker 2.5) for per-env target sizes.
