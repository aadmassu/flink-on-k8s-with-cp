# Prerequisites — dr CFK CP (non-TLS)

> **PLACEHOLDER stub.** Walk this file with FCB ops before the first
> `action=create-prereqs` run on dr. dr is the secondary location of the
> prod fleet; design is identical to dev/qa/uat/prd — only the env-suffixed
> names + dr-cluster specifics change.

Same non-TLS prereq pattern as the lower envs — eleven Opaque Secrets
(license, MDS token keypair, OAuth client creds, SASL passwords, Control
Center basic auth) that the CFK Custom Resources one level up depend on.
None are manifest-based; the `confluent-platform.yaml` pipeline
`action=create-prereqs` creates them from secret variables in the
`dr-openshift-credentials` variable group.

See the [dev prereqs README](../../dev/prereqs/README.md) for the full
table, design rationale, and the MDS-keypair base64 gotcha.

The six **cert-manager Certificate CRs** that produce the `*-tls`
Secrets live in [`../cert-manager/`](../cert-manager/) — see that
README for the TLS side.

## Differences from dev / qa / uat / prd

- **Namespace**: `dah-flink-dr`
- **Keyfactor `Environment` annotation**: `Prod` (DR runs production-grade certs)
- **OAuth scope**: `11547.DAH(Prod)` (DR shares the Prod Okta tenant with prd)
- **Groups claim**: `dahProd_groups`
- **Source VM properties**: [`../../cp-confluent/prd-2/`](../../cp-confluent/) — VM CP prd secondary (matches the prd-1 → prd / prd-2 → dr OpenShift mapping)
- **Cluster apps domain**: `apps.pd-s.ocp.fcbint.net` (secondary cluster, per the FCB OpenShift Ingress Confluence page Load Balancer table)

## Variable group values

The `dr-openshift-credentials` variable group needs the same 24 entries
as the prd variable group, with the `dr-` prefix.

**DR-specific provisioning required before first install:**

| Group | What needs to be done | Owner |
|---|---|---|
| Okta clients | Same Prod Okta application as prd. The six client IDs (broker, SR, Connect, REST, C3, MDS-REST) **must be the same as prd** — a Flink job or client failover between prd and dr must not require re-authentication with a different Okta client. Confirm with FCB Okta admins. | FCB Okta admins |
| SASL inter-broker passwords | **Must match prd** for cluster-link compatibility during failover. Tushar copies the six prd passwords into the dr variable group. | Tushar |
| Confluent license | Reuse the existing org license; the `confluent-license` ExternalSecret for dr already references CyberArk safe `11547_P_KEY_FP`. | Already on file |
| MDS token keypair | **Must match prd** — tokens minted by prd MDS must validate against dr MDS post-failover. Copy the same base64-encoded PEM into `dr-mds-token-keypair-pem`. | Operations |
| C3 Prometheus + AlertManager basic auth | Two username/password pairs. Can match prd or be DR-specific — operational preference. | Tushar |

## Run order

```
1. confluent-platform.yaml  environment=dr   action=create-prereqs   (creates the 11 Opaque Secrets)
2. confluent-platform.yaml  environment=dr   action=install          (applies Certificates, waits for *-tls Secrets,
                                                                      then applies the CFK CRs)
```

## Open items before first dr install

- Confirm the cluster-link migration plan: dr is the failover target for prd, so the active-passive vs active-active topology choice determines what runs on dr at steady state (cold standby? hot cluster-link sink? both?). Affects everything from broker sizing to whether C3 and Connect run on dr at all.
- Confirm the cluster's external Kafka LB domain — placeholder is `kafka.dr.dah.fcbint.net`; the SANs in `../cert-manager/kafka-tls-certificate.yaml` must match what Container team configured for the secondary cluster.
- Confirm dr ResourceQuota — every CR sizing block is inherited from dev and undersized for production traffic.
