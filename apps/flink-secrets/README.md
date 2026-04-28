# Flink Secrets — ExternalSecret manifests

This folder holds the `ExternalSecret` resources that pull CMF (and, later, Flink workload)
secrets from the FCB CyberArk safe via the External Secrets Operator (ESO). Per FCB
policy, every secret value must originate in CyberArk — nothing in Git holds a
literal password, key, or license string.

See `docs/External Secrets.pdf` (the FCB SCP — External Secrets reference) for
the architectural rationale and CCP authentication details.

## Layout

```
apps/flink-secrets/
├── dev/flink-secrets.yaml   # ExternalSecrets for dah-flink-dev
├── qa/flink-secrets.yaml    # ExternalSecrets for dah-flink-qa
├── stg/flink-secrets.yaml   # ExternalSecrets for dah-flink-stg
└── prd/flink-secrets.yaml   # ExternalSecrets for dah-flink-prd
```

Each env's file currently declares three `ExternalSecret`s, one per K8s `Secret` CMF needs:

| K8s Secret name      | Key inside Secret | Consumed by CMF for                       |
| -------------------- | ----------------- | ----------------------------------------- |
| `cmf-db-credentials` | `password`        | SQL Server JDBC password                  |
| `cmf-encryption-key` | `key`             | AES-GCM key for column-level CMF DB encryption (one-time, never rotated) |
| `confluent-license`  | `license.txt`     | Confluent license JWT                     |

More `ExternalSecret`s will be added here as Flink workloads come online (Kafka SASL/OAuth credentials, Schema Registry, NetApp S3, etc.).

## Onboarding workflow

The files in this folder cannot be applied until FCB Container Platforms has onboarded our safe to ESO. Order of operations:

1. **Submit the SNOW form** "Container Platforms: Onboard Namespace to CyberArk" — request that our app team's CyberArk safe be onboarded for use by ESO in the OpenShift cluster.
2. **Container Platforms creates a `ClusterSecretStore`** on the cluster, named after the safe (with `_` replaced by `-` to comply with RFC1123). They give us that name.
3. **Populate the safe** with the credential entries CMF needs (DB password, encryption key, license). Per-env entries — dev/qa/stg/prd values must each be distinct.
4. **Edit each env's `flink-secrets.yaml`** and replace every `<TODO-...>` placeholder with the real values:
   - `<TODO-fcb-clustersecretstore>` → name of the `ClusterSecretStore` from step 2
   - `<TODO-cyberark-key-...>` → the CyberArk credential entry name for that secret
   - `<TODO-cyberark-property>` → the field on that entry (e.g. `password`, `Content`, or whatever IAM specifies)
5. **Apply**:
   ```bash
   oc apply -f apps/flink-secrets/<env>/flink-secrets.yaml
   ```
6. **Verify** the K8s Secrets are populated and owned by ESO:
   ```bash
   oc get secret -n dah-flink-<env> cmf-db-credentials cmf-encryption-key confluent-license
   oc get externalsecret -n dah-flink-<env>
   ```
   The `STATUS` column on each `ExternalSecret` should read `SecretSynced`.
7. **Cut the pipeline over.** Once ESO is verified producing the Secrets, remove the `oc create secret generic` block from `.azure-pipelines/cmf.yaml` and delete the now-unused ADO variables (`<env>-cmf-sql-server-user-password`, `<env>-cmf-encryption-key`, `<env>-confluent-license`).

Recommend doing this in **dev first, end-to-end** before duplicating to qa/stg/prd.

## decodingStrategy choices

| Secret              | `decodingStrategy` | Why |
| ------------------- | ------------------ | --- |
| `cmf-db-credentials` (`password`) | `None` | DB password is plaintext in CyberArk. Pass through verbatim. |
| `cmf-encryption-key` (`key`)      | `None` | AES key is stored as a base64 string; CMF expects to read the base64 string and base64-decode it itself. ESO must not pre-decode. |
| `confluent-license` (`license.txt`) | `None` | JWT must arrive verbatim. |

If FCB later changes how a value is stored (e.g. base64 vs. clear-text), revisit the relevant `decodingStrategy` line.

## Migration phasing

The `.azure-pipelines/cmf.yaml` pipeline currently creates these three Secrets via `oc create secret generic` from ADO variable groups. **Do not remove that block until ESO is proven** in at least one env, otherwise CMF will start with no Secrets and crash.

The ESO-managed Secrets use `creationPolicy: Owner`, which means ESO will refuse to manage a Secret that already exists with a different controller. Two safe approaches when cutting over:

- **Recommended:** delete the pipeline-created Secret first, then apply the `ExternalSecret`. ESO will create a fresh Secret it owns. Pod restart picks up the new value (which should be identical if you copied the value to CyberArk correctly).
- **Or** change `creationPolicy` to `Merge` temporarily during cutover, verify, then change back to `Owner`.
