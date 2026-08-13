# CyberArk Secrets Required for Hybrid Authentication

## Per-Environment CFK Platform Secrets

Each environment requires **one CyberArk remote key** with these properties:

### DEV: `dev-cfk-platform-credentials`

```
sasl-plain-admin-password=<32-byte-admin-credential>
prometheus-username=<prometheus-user>
prometheus-password=<prometheus-pwd>
alertmanager-username=<alertmanager-user>
alertmanager-password=<alertmanager-pwd>
```

### QA: `qa-cfk-platform-credentials`

```
sasl-plain-admin-password=<32-byte-admin-credential>
prometheus-username=<prometheus-user>
prometheus-password=<prometheus-pwd>
alertmanager-username=<alertmanager-user>
alertmanager-password=<alertmanager-pwd>
```

### UAT-P: `uat-cfk-platform-credentials`

```
sasl-plain-admin-password=<32-byte-admin-credential>
prometheus-username=<prometheus-user>
prometheus-password=<prometheus-pwd>
alertmanager-username=<alertmanager-user>
alertmanager-password=<alertmanager-pwd>
```

### UAT-S: (Same as UAT-P)

```
sasl-plain-admin-password=<32-byte-admin-credential>
prometheus-username=<prometheus-user>
prometheus-password=<prometheus-pwd>
alertmanager-username=<alertmanager-user>
alertmanager-password=<alertmanager-pwd>
```

### PRD: `prd-cfk-platform-credentials`

```
sasl-plain-admin-password=<32-byte-admin-credential>
prometheus-username=<prometheus-user>
prometheus-password=<prometheus-pwd>
alertmanager-username=<alertmanager-user>
alertmanager-password=<alertmanager-pwd>
```

### DR: (Same as PRD)

```
sasl-plain-admin-password=<32-byte-admin-credential>
prometheus-username=<prometheus-user>
prometheus-password=<prometheus-pwd>
alertmanager-username=<alertmanager-user>
alertmanager-password=<alertmanager-pwd>
```

## Per-Environment CFK License

Each environment has existing CFK license ExternalSecrets that target:

| Environment | Remote Key | Property |
|-------------|-----------|----------|
| dev | `dev-confluent-license` | `Digital Analytics Hub` |
| qa | `qa-confluent-license` | `Digital Analytics Hub` |
| uat-p | `uat-confluent-license` | `Digital Analytics Hub` |
| uat-s | `uat-confluent-license` | `Digital Analytics Hub` |
| prd | `prd-confluent-license` | `Digital Analytics Hub` |
| dr | `dr-confluent-license` | `Digital Analytics Hub` |

## Per-Environment CMF Secrets

CMF has separate ExternalSecrets in `apps/confluent-cmf/<env>/externalsecrets/`:

| Environment | Remote Key | Properties |
|-------------|-----------|-----------|
| dev | `prod-cmf-encryption-key` | `Digital Analytics Hub` |
| qa | `qa-cmf-encryption-key` | `Digital Analytics Hub` |
| uat-p | `uat-cmf-encryption-key` | `Digital Analytics Hub` |
| uat-s | `uat-cmf-encryption-key` | `Digital Analytics Hub` |
| prd | `prod-cmf-encryption-key` | `Digital Analytics Hub` |
| dr | `dr-cmf-encryption-key` | `Digital Analytics Hub` |

**CMF Database Password:**

| Environment | Remote Key | Property |
|-------------|-----------|----------|
| dev | `prod-cmf-db` | Database password |
| qa | `qa-cmf-db` | Database password |
| uat-p | `uat-cmf-db` | Database password |
| uat-s | `uat-cmf-db` | Database password |
| prd | `prod-cmf-db` | Database password |
| dr | `dr-cmf-db` | Database password |

## Summary

**Onboard to CyberArk:**

- [ ] dev-cfk-platform-credentials (5 properties)
- [ ] qa-cfk-platform-credentials (5 properties)
- [ ] uat-cfk-platform-credentials (5 properties) — used by both uat-p and uat-s
- [ ] prd-cfk-platform-credentials (5 properties) — used by both prd and dr
- [ ] (CMF secrets already exist — no action needed)
- [ ] (License secrets already exist — no action needed)

**ExternalSecret manifests exist at:**

- CFK Platform: `apps/confluent-platform/<env>/externalsecrets/externalsecrets-hybrid-auth-cyberark-disabled.yaml` (commented out, ready to enable)
- CMF: `apps/confluent-cmf/<env>/externalsecrets/externalsecret-*.yaml` (existing)
