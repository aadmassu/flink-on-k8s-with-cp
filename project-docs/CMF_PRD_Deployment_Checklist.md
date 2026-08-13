# CMF PRD Deployment Checklist

**Environment:** Production (`dah-flink-prod`)  
**Status:** Pre-deployment validation  
**Updated:** 2026-08-05

---

## RBAC & Service Account

- [ ] **flink-operator SA in dah-flink-prod exists**
  - Contact: Rick Mulder (Container Platforms)
  - Verification: `oc get sa flink-operator -n dah-flink-prod`

- [ ] **flink-operator SA has required permissions**
  - Required: `get serviceaccounts`
  - Required: `get, list, watch rolebindings`
  - Required: `get, list, watch roles`
  - Verification: `oc describe sa flink-operator -n dah-flink-prod` (check RoleBindings)
  - Contact Rick if missing

---

## External Secrets & Credentials

- [ ] **ExternalSecrets synced and Ready=True**
  - `cmf-db-credentials` (pulls `prod-cmf-sql-server-user-password` from CyberArk)
  - `cmf-encryption-key` (pulls `prod-cmf-encryption-key` from CyberArk)
  - `confluent-license` (pulls `prod-confluent-license` from CyberArk)
  - Verification: `oc get externalsecret -n dah-flink-prod`
  - Expected: All show `Synced=True`, `Ready=True`

- [ ] **CyberArk AppID 11547-p-key-fp accessible**
  - Safe: `11547_P_KEY_FP`
  - Keys verified in CyberArk:
    - `prod-confluent-license`
    - `prod-cmf-sql-server-user-password`
    - `prod-cmf-encryption-key`
  - Contact: Tushar (Kafka Admin) if issues

---

## Database Connectivity

- [ ] **SQL Server reachable from pod**
  - Host: `AG-DAHBronze.fcpd.fcbint.net`
  - Port: `3085`
  - Database: `DAHFLINK`
  - Network access verified (firewall, VPN)
  - Contact: DBA team if connectivity issues

- [ ] **cmf-db-credentials Secret populated**
  - Verification: `oc get secret cmf-db-credentials -n dah-flink-prod -o yaml | grep password`
  - Expected: Non-empty base64-encoded password

---

## TLS & Certificates

- [ ] **cmf-tls Secret exists**
  - Ownership: cert-manager Certificate (Keyfactor-signed)
  - File: `apps/confluent-cmf/prd/cmf-tls-certificate.yaml`
  - Verification: `oc get secret cmf-tls -n dah-flink-prod`

- [ ] **cmf-ingress-tls Secret exists**
  - For UI access on `cmf.apps.pd-p.ocp.fcbint.net`
  - File: `apps/confluent-cmf/prd/cmf-ingress-tls-certificate.yaml`
  - Verification: `oc get secret cmf-ingress-tls -n dah-flink-prod`

- [ ] **fcb-trust-bundle ConfigMap exists**
  - Required for JVM truststore (TLS to Schema Registry, Okta, etc.)
  - Verification: `oc get cm fcb-trust-bundle -n dah-flink-prod`

---

## Helm Chart & Values

- [ ] **CMF Helm values configured**
  - File: `apps/confluent-cmf/prd/values.yaml`
  - Namespace: `dah-flink-prod` ✓
  - Image repository: `artifactory.fcbint.net/camdepositsharedservices-docker-dev/confluentinc` (temporary, non-prod repo)
  - Image tag: `2.3.0-fcb-preview-2` ✓
  - SQL production mode: `true` ✓

- [ ] **Helm chart dependencies satisfied**
  - Verification: `helm dependency update charts/confluent-manager-for-apache-flink`

---

## Deployment Execution

- [ ] **Run cmf.yaml pipeline for prd**
  - Pipeline: `.azure-pipelines/cmf.yaml`
  - Parameters:
    - `environment: prd`
    - `action: install`
  - Monitor: Pod startup logs for database connection and initialization

- [ ] **Verify pod is Running**
  - Verification: `oc get pod -n dah-flink-prod -l app.kubernetes.io/name=confluent-manager-for-apache-flink`
  - Expected: `1/1 Running`

- [ ] **Check CMF logs for errors**
  - Command: `oc logs -n dah-flink-prod <pod-name> | tail -100`
  - Expected: Application started successfully, no exceptions

---

## Post-Deployment Validation

- [ ] **CMF UI accessible**
  - URL: `https://cmf.apps.pd-p.ocp.fcbint.net`
  - Expected: Ingress routes to pod, TLS certificate valid

- [ ] **CMF health check passes**
  - Endpoint: `https://cmf-service.dah-flink-prod.svc.cluster.local:443/actuator/health`
  - Expected: `{"status":"UP"}`

- [ ] **Database migration completed**
  - Check logs for Flyway migration success
  - Expected: "Flyway migration completed"

---

## Artifactory Image Repository (Post-Tom's Fix)

- [ ] **Tom (FCB) configures prod Artifactory virtual repo**
  - Task: Set default local deployment repository
  - ETA: Evening/tomorrow morning (2026-08-05)
  - Contact: Tom Philipps

- [ ] **Image promoted/copied from non-prod to prod repo**
  - Source: `camdepositsharedservices-docker-dev`
  - Target: `camdepositsharedservices-docker-prod`
  - Image: `cp-cmf:2.3.0-fcb-preview-2`

- [ ] **Update prd/values.yaml image repository back to prod**
  - Change line 130 from `camdepositsharedservices-docker-dev` → `camdepositsharedservices-docker-prod`
  - Redeploy: `helm upgrade --install confluent-cmf ...`

- [ ] **Verify pod pulls from prod repo**
  - Check pod events: `oc describe pod -n dah-flink-prod <pod-name>`
  - Expected: Image pull from prod Artifactory

---

## Known Issues & Blockers

### Database Connection Failure (Previous)
- **Symptom:** CMF pod fails with "Could not get Connection for extracting meta-data"
- **Root cause:** ExternalSecret not synced; CyberArk credential fetch failed
- **Status:** To be resolved by verifying ExternalSecret readiness
- **Next step:** Monitor pod logs during deployment

### Artifactory Prod Repo Configuration (Current)
- **Symptom:** `docker push` fails with "Unable to upload into a virtual repository without default local deployment configured"
- **Root cause:** Virtual repo missing default deployment target
- **Status:** Tom Philipps fixing (ETA evening/tomorrow)
- **Workaround:** Using non-prod image temporarily
- **Next step:** Wait for Tom's Artifactory fix

### CyberArk IP Allowlist (Potential)
- **Symptom:** ExternalSecret stuck in pending state, CyberArk returns 400/403
- **Possible cause:** Pod egress IP not whitelisted in CyberArk for APP-11547-P
- **Status:** Monitor deployment; escalate if needed
- **Contact:** Tushar (Kafka Admin) / CyberArk admin

---

## Deployment Timeline

| Phase | Task | Owner | ETA | Status |
|-------|------|-------|-----|--------|
| Pre-flight | Verify RBAC permissions | Rick | Now | 🔄 |
| Pre-flight | Verify CyberArk keys | Tushar | Now | 🔄 |
| Pre-flight | Verify database connectivity | DBA | Now | 🔄 |
| Pre-flight | Verify TLS certificates | Container team | Now | 🔄 |
| Deployment | Run cmf.yaml pipeline (prd) | Ayu | Now | ⏳ |
| Post-deployment | Monitor pod startup | Ayu | Now | ⏳ |
| Infrastructure | Fix Artifactory prod repo | Tom | 2026-08-05 evening/AM | 🔄 |
| Final | Update values.yaml to prod repo | Ayu | 2026-08-05 after Tom | ⏳ |
| Final | Redeploy with prod image | Ayu | 2026-08-05 after Tom | ⏳ |

---

**Legend:**
- 🔄 = In progress / Pending verification
- ⏳ = Waiting for prior step
- ✓ = Complete

**Last Updated:** 2026-08-05  
**Owner:** Ayu (FCB Kafka/Flink delivery)
