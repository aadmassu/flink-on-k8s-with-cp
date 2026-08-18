# Shared CA Certificates

This directory contains the corporate trust hierarchy required by all Confluent Platform environments (DEV, QA, UAT, STG, PRD-1, PRD-2, DR).

## Certificates

### fcb-root-ca-2.pem
- **Subject:** CN=FCB Root CA 2
- **Purpose:** Root CA for Kafka server certificates
- **Usage:** Validates server certificates for Kafka brokers and KRaft controllers
- **Rotation:** Managed by FCB Security; notify Container Platforms team

### fcb-root-ca-1.pem
- **Subject:** CN=FCB Root CA 1
- **Purpose:** Root CA for FCB/Zscaler inspection chain
- **Usage:** Validates certificates in the Zscaler MITM inspection path
- **Rotation:** Managed by FCB Security; notify Container Platforms team

### fcb-zscaler-issuing-ca.pem
- **Subject:** CN=firstcitizens.com, OU=Platform Security Engineering
- **Purpose:** Zscaler inspection CA issued by FCB Root CA 1
- **Usage:** Validates SSL certificates for Okta endpoints (OIDC/OAuth token exchange)
- **Rotation:** Managed by Zscaler/FCB Security; notify Container Platforms team
- **Note:** Despite the subject name, this is NOT Okta's public CA. It is the FCB/Zscaler inspection CA that intercepts TLS traffic to Okta.

## Usage

Each environment declares which CAs it requires via its `ca-bundle.conf` file.

The pipeline script `build-and-apply-derived-kafka-tls-secret.sh` assembles the CA bundle in the declared order and creates the `kafka-tls-cfk` derived Secret.

## Validation

```bash
# List all certificates
for ca in *.pem; do
  echo "=== $ca ==="
  openssl x509 -noout -subject -in "$ca"
  openssl x509 -noout -dates -in "$ca"
done

# Compute checksums
sha256sum *.pem > checksums.sha256
```

## Certificate Renewal

When CAs are rotated:

1. Obtain new PEM files from FCB Security
2. Verify fingerprints and subjects
3. Replace files in this directory
4. Run pipeline with `action=create-prereqs` on all environments
5. Monitor Kafka pod restarts; verify new truststore.p12 contains updated CAs
6. Test OIDC/OAuth workflows

Do NOT update individual environment ca-bundle.conf files unless the environment's trust requirements differ from the corporate standard.
