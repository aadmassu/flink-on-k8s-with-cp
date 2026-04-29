# Confluent Manager for Apache Flink (CMF)

Helm values for installing CMF into `dah-flink-<env>` on FCB OpenShift, against the **vendored chart** at [`charts/confluent-manager-for-apache-flink/`](../../charts/confluent-manager-for-apache-flink/) (the upstream chart with FCB-specific edits — namespace-scoped RBAC support).

Installed by [`.azure-pipelines/cmf.yaml`](../../.azure-pipelines/cmf.yaml).

## Layout

```
apps/confluent-cmf/
├── README.md
└── <env>/
    ├── values.yaml                # Helm values for CMF
    └── cmf-tls-certificate.yaml   # cert-manager Certificate for CMF REST endpoint TLS
```

## Per-env values — what you'll actually find

The four env files mostly differ in a handful of fields; everything else is the same shape:

| Field | dev | qa | uat | prd |
|---|---|---|---|---|
| `cmf.k8s.watchNamespaces` | `[dah-flink-dev]` | `[dah-flink-qa]` | `[dah-flink-uat]` | `[dah-flink-prd]` |
| `cmf.sql.production` | `false` | `false` (now; flip when DBA delivers) | `true` (target) | `true` |
| `cmf.database.type` | `jdbc` | `local` *(temporary; awaiting QA SQL Server from DBA team)* | `jdbc` | `jdbc` |
| `image.tag` | `2.3.0-fcb-preview-2` (FCB-specific build for namespace-scoped RBAC support) |
| `additionalLabels.fcbint.net/app-id` | `"11547"` (FCB CMDB app id) — every env |
| `namespaced` | `true` — every env (so the chart emits `Role` + `RoleBinding`, not `ClusterRole`) |
| `rbac` / `serviceAccount.create` | `false` / `false` — every env (the `flink-operator` SA is pre-created by FCB Container Platforms via the `fcb-security` ArgoCD chart; we only consume it) |
| `serviceAccount.name` | `flink-operator` — every env |
| `persistence.create` | `false` — every env |
| `resources.{requests,limits}` | dev = small; uat/prd = larger |

## Helm install command

The pipeline runs effectively:

```bash
helm upgrade --install confluent-cmf charts/confluent-manager-for-apache-flink \
  --namespace dah-flink-<env> \
  -f apps/confluent-cmf/<env>/values.yaml \
  --set namespaced=true \
  --set cmf.database.jdbc.url="<env>-cmf-sql-server-jdbc-url" \
  --set cmf.database.jdbc.user="<env>-cmf-sql-server-user" \
  --wait --timeout 10m
```

`url` and `user` come from the env's variable group; the corresponding **password**, **encryption key**, and **license** are created by the pipeline as Kubernetes Secrets (`cmf-db-credentials`, `cmf-encryption-key`, `confluent-license`) before the Helm install runs.

## TLS for the CMF REST endpoint

CMF terminates TLS at the pod. The cert is issued by FCB's Keyfactor `ClusterIssuer` via cert-manager, and consumed by Spring Boot via the chart's `cmf.ssl` block.

```
apps/confluent-cmf/<env>/cmf-tls-certificate.yaml   # cert-manager Certificate
                                                    #   commonName: *.ocp.fcbint.net
                                                    #   dnsNames:   *.ocp.fcbint.net, *.svc, *.svc.cluster.local
                                                    #   issuerRef: ClusterIssuer/keyfactor (group: command-issuer.keyfactor.com)
                                                    #   duration 8760h, RSA 4096, rotationPolicy Always

apps/confluent-cmf/<env>/values.yaml                # ssl block + mountedVolumes
  cmf.ssl.enabled: true
  cmf.ssl.certificate:               file:/etc/cmf/tls/tls.crt
  cmf.ssl.certificate-private-key:   file:/etc/cmf/tls/tls.key
  mountedVolumes.volumes:            cmf-tls (Secret) at /etc/cmf/tls
```

The Service exposes **port 443 → targetPort 8080** (the CMF Spring Boot server is HTTPS on 8080 inside the pod). Pipelines that call CMF go through the apiserver proxy as `services/https:cmf-service:443/proxy`.

### Required Keyfactor metadata (already on every cert manifest)

Per FCB's approver-policy, all six annotations must be present or Keyfactor rejects the request:

| Annotation | Value |
|---|---|
| `Certificate-Support-Group-Contact` | `dahkfkaksupportnotification@firstcitizens.com` |
| `Environment` | `Non-Prod-DEV` / `Non-Prod-QA` / `Non-Prod-UAT` / `Prod-Corp` |
| `Description` | `Confluent Manager for Apache Flink — REST endpoint TLS` |
| `Organization` | `FCB` |
| `Application-ID` | `11547` |
| `Platform` | `OPENSHIFT` |

### Run order per env

1. [`.azure-pipelines/cmf-tls.yaml`](../../.azure-pipelines/cmf-tls.yaml) — applies the Certificate, waits for Keyfactor approval, verifies the `cmf-tls` Secret has `tls.crt`, `tls.key`, `ca.crt`.
2. [`.azure-pipelines/cmf.yaml`](../../.azure-pipelines/cmf.yaml) — Helm-installs CMF; pre-flight checks `cmf-tls` exists and aborts with a clear message if not.

### Renewal

cert-manager rotates the cert before expiry (`renewBefore: 360h`). The Secret is updated in place. CMF reads the cert files only on startup, so the new cert takes effect at the next pod restart — schedule a planned restart per renewal window (~yearly).

## Resources the chart will apply

After `helm template`, only these are emitted (RBAC and SA are skipped because we consume the platform-team-managed ones):

```
ConfigMap   confluent-manager-for-apache-flink
Service     cmf-service
Deployment  confluent-manager-for-apache-flink
```

The `Service` and `flink-operator` SA are pre-created in FCB; the chart only renders/applies the `Deployment` and `ConfigMap` it owns.

## Pre-requisites in the cluster

1. **Namespace** `dah-flink-<env>` exists (FCB Container Platforms team via SNOW).
2. **`flink-operator` ServiceAccount** + `flink-operator` Role + RoleBinding in `dah-flink-<env>` (created by FCB's `fcb-security` ArgoCD chart, see screenshots in `docs/`).
3. **SQL Server database** for CMF state (FCB DBA team via SNOW). For envs without it yet, the values.yaml falls back to `database.type: local` (SQLite on ephemeral pod storage) — short-term validation only; state is lost on pod restart.
4. **NetApp S3 bucket** per env for Flink checkpoints (FCB Storage team via SNOW).

## Cross-references

| Resource | Path |
|---|---|
| Vendored chart | [`charts/confluent-manager-for-apache-flink/`](../../charts/confluent-manager-for-apache-flink/) |
| Install pipeline | [`.azure-pipelines/cmf.yaml`](../../.azure-pipelines/cmf.yaml) |
| FCB pre-created RBAC | [`openshift-prereqs/<env>/manifests/`](../../openshift-prereqs/) |
| Flink Environment / Catalog / Database manifests | [`apps/confluent-flink/<env>/`](../confluent-flink/) |
