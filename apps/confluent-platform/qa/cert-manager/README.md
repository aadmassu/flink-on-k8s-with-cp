# cert-manager Certificates — qa CFK CP

Six `cert-manager.io/v1` Certificate CRs. Each one asks Keyfactor (via
the `keyfactor` ClusterIssuer) for a Keyfactor-issued cert and lands a
Kubernetes Secret with `tls.crt` / `tls.key` / `ca.crt` that the
matching CFK CR consumes:

```
cert-manager/
├── README.md  (this file)
├── kafka-tls-certificate.yaml           → secret/kafka-tls
├── kraftcontroller-tls-certificate.yaml → secret/kraftcontroller-tls
├── schemaregistry-tls-certificate.yaml  → secret/schemaregistry-tls
├── connect-tls-certificate.yaml         → secret/connect-tls
├── kafkarest-tls-certificate.yaml       → secret/kafkarest-tls
└── controlcenter-tls-certificate.yaml   → secret/controlcenter-tls
```

The `confluent-platform.yaml` pipeline `action=install` applies all six
and waits up to 10 minutes per Secret to materialize before applying the
CFK CRs. Same Keyfactor + cert-manager pattern as
[`apps/confluent-cmf/qa/cmf-tls-certificate.yaml`](../../../confluent-cmf/qa/cmf-tls-certificate.yaml)
on the CMF side.

The non-cert prerequisites (license, MDS keypair, OAuth client creds,
SASL passwords) are not manifest-based — they're created by the
`action=create-prereqs` pipeline step. See [`../prereqs/README.md`](../prereqs/README.md)
for the variable-group / CyberArk-ESO sourcing of those.
