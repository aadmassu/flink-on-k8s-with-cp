# CFK / CMF on OpenShift — Lessons Learned

Living document. Every time we hit a non-obvious problem during a deploy
(any env, any layer) and find the fix, add a numbered entry here. The
next person promoting to QA / UAT / STG / PRD should be able to scan this
once and avoid stepping on the same rakes.

Each entry follows the same shape: **Symptom → Root cause → Fix → Why it
matters**. Keep entries dense; this is meant to be read end-to-end.

---

## A. CFK CRD shape gotchas

### A1. Top-level `spec.resources` is silently pruned

* **Symptom**: pods come up with operator-default resources even though the
  CR clearly specifies `resources:` at the top of `spec`.
* **Root cause**: CFK CRDs validate `resources` only under
  `spec.podTemplate.resources`. A top-level `spec.resources` is not in the
  schema and OpenShift admission strips it without warning.
* **Fix**: put `resources:` under `spec.podTemplate.resources` in every CR.
* **Why it matters**: the prune is silent — no event, no error, no
  warning. You only notice when you see the StatefulSet's pod template has
  different limits than your manifest.

### A2. No `startupProbe` in CFK 3.1.x CRDs

* **Symptom**: FCB Gatekeeper `[startup]` policy raises a WARNING on every
  CFK pod: *"Container X in Pod Y has no `<startupProbe>`"*.
* **Root cause**: `spec.podTemplate.probe` exposes only `liveness` and
  `readiness`. Verified across all six CFK CRDs (kafkas,
  kraftcontrollers, schemaregistries, connects, kafkarestproxies,
  controlcenters) — no `startupProbe` field exists in the schema.
* **Fix**: there is no manifest-side fix. Document the limitation,
  escalate to FCB Container Platforms for a policy exemption on
  CFK-managed StatefulSets, or wait for a future CFK line.
* **Why it matters**: this is a *warning*, not a denial. Pods still
  create. Don't waste time hunting for a CR field that isn't there.

### A3. No `initContainers` resource override in CFK 3.1.x CRDs

* **Symptom**: every CFK pod claims ~500m CPU against the namespace
  ResourceQuota regardless of how small `podTemplate.resources` is set.
* **Root cause**: the operator injects a `config-init-container` with a
  default `limits.cpu` near 500m. Kubernetes computes pod-effective
  resources as `max(initContainers, sum(regularContainers))`, so the init
  container is the floor. The CFK 3.1.x CRD does *not* expose
  `podTemplate.initContainers`, so there is no way to shrink it.
* **Fix**: budget at least ~500m × (number of CFK pods) in the
  ResourceQuota. For tight dev quotas, suspend non-critical components
  to `replicas: 0` to fit (we did this for ControlCenter and Connect
  in dev).
* **Why it matters**: any napkin math that assumes "main container limit
  = pod claim" undercounts by 5×. A 2 CPU quota fits ~4 CFK pods, not 6.

### A4. `metadataServer:` block silently pruned (one example of many)

* **Symptom**: configured `metadataServer:` on the Kafka CR, no MDS
  endpoint comes up.
* **Root cause**: `metadataServer` is not in the CFK 3.1.x Kafka schema.
  CFK delivers MDS via the *broker's* listener block + `dependencies.mds`
  on consumers (SR, Connect, REST, C3). Stale field pruned at admission.
* **Fix**: before relying on any unusual CFK CR field, verify it exists:
  `oc get crd kafkas.platform.confluent.io -o yaml | grep -A3 <field>`,
  or `oc explain kafka.spec.<field>`.
* **Why it matters**: silent pruning + sparse error messaging means you
  can spend hours debugging "why isn't MDS up" when the field never
  reached the StatefulSet template at all.

### A5. CFK 3.1.x ControlCenter only allows `basic|ldap|mtls` for top-level inbound auth

* **Symptom**: setting `spec.authentication.type: oauth` on
  ControlCenter is rejected by the CRD validator (other CFK components
  *do* support oauth top-level, which makes this easy to miss).
* **Root cause**: OIDC SSO for C3's UI is delivered through MDS, not
  through C3's own top-level auth. The CRD reflects that.
* **Fix**: set top-level `authentication.type: mtls` with
  `sslClientAuthentication: requested` to satisfy the schema's required
  `type` field, and put the OIDC config under
  `dependencies.mds.ssoProtocol: oidc`.
* **Why it matters**: the VM cluster ran
  `confluent.controlcenter.auth.sso.mode=oidc` as a top-level setting,
  so it's tempting to mirror it as `authentication.type: oauth`.
  That mapping is wrong for CFK; OIDC lives under MDS dependency.

### A6. OAuth must be nested under `authentication.oauth.{secretRef, configuration}`

* **Symptom**: CRs are rejected at apply with errors like
  *"oauthForRest: missing authentication.oauth struct"*.
* **Root cause**: CFK 3.1.x requires the OAuth config nested, not as
  flat fields directly under `authentication`. Older docs / examples may
  show the flat form.
* **Fix**: use this shape:
  ```yaml
  authentication:
    type: oauth
    oauth:
      secretRef: <secret>
      configuration:
        jwksEndpointUri: ...
        expectedIssuer: ...
        ...
  ```
* **Why it matters**: applies to every CFK consumer of OAuth — SR,
  Connect, KafkaRest, MDS dependency, etc.

### A7. `injectLabels` ≠ `podTemplate.labels`

* **Symptom**: FCB Gatekeeper `[required-workload-labels]` denies either
  the StatefulSet OR the Pod (intermittent depending on which one the
  policy hits first).
* **Root cause**: `injectLabels` (top-level on `spec`) only labels the
  StatefulSet object. `podTemplate.labels` only labels the Pod template
  inside the StatefulSet. FCB Gatekeeper inspects *both* objects at
  admission, so both must carry the FCB common-metadata set
  (`app.kubernetes.io/{name,instance,component,part-of}`,
  `fcbint.net/app-id`).
* **Fix**: set both blocks in every CFK CR. They will look nearly
  identical — that's intentional.
* **Why it matters**: easy to set one and forget the other. The errors
  read like a generic "missing label" but identify the SS or the Pod
  specifically; pay attention to which object the policy named.

### A8. KRaftController can't use the `CONFLUENT` RBAC provider

* **Symptom**: kraftcontroller-0 starts, JVM comes up, Kafka config
  block prints in the log, then the process exits with:
  ```
  [ERROR] ProcessTerminatingFaultHandler handleFault -
    app=kraftcontroller, clusterId=dah-flink-<env>, server=0 -
    Encountered fatal fault: caught exception
  org.apache.kafka.common.config.ConfigException:
    You must specify confluent.metadata.bootstrap.servers to
    configure the RBAC provider.
  ```
  Pod CrashLoopBackOff, the stack never starts.
* **Root cause**: the original VM controller `.properties` files
  (which we ported into the CR's `configOverrides`) declared:
  ```
  authorizer.class.name=io.confluent.kafka.security.authorizer.ConfluentServerAuthorizer
  confluent.authorizer.access.rule.providers=CONFLUENT,KRAFT_ACL
  ```
  The `CONFLUENT` provider is the centralized-RBAC provider. It needs
  `confluent.metadata.bootstrap.servers` to point at an MDS endpoint
  so it can pull RBAC rules at startup. **MDS is hosted on the
  brokers (port 8090), not on the controller** — and the brokers
  can't start until the controllers do. Chicken-and-egg, controller
  fails fatally.
* **Fix**: drop the `CONFLUENT` entry from the controller's
  authorizer providers list; keep only `KRAFT_ACL`, which stores ACLs
  in the metadata log itself and requires no MDS lookup. **Brokers
  keep `CONFLUENT,KRAFT_ACL`** — they DO host MDS and DO need
  centralized RBAC for client-request authorization.
  ```yaml
  - authorizer.class.name=io.confluent.kafka.security.authorizer.ConfluentServerAuthorizer
  - confluent.authorizer.access.rule.providers=KRAFT_ACL
  ```
* **Why it matters**: the VM didn't expose this dependency because
  controllers and brokers were either co-located or had a known MDS
  endpoint wired up. CFK pod-separates them and the dependency
  becomes load-bearing on bring-up order. This is the first thing
  to check when a controller boots cleanly through the Kafka config
  print and then dies — easy to mistake for a missing-config bug
  in the CR.

### A9. `ConfluentMetricsReporter` on the controller retries forever

* **Symptom**: KRaftController boots cleanly (no fatal exit), but the
  log emits an ERROR every 16-32 seconds from
  `DynamicMetricsReportersScheduler`:
  ```
  Failed to initiate DynamicMetricsReporters. Elapsed time: ... ms,
    retrying in 32000 ms (Attempt 7).
  org.apache.kafka.common.config.ConfigException:
    Missing required configuration "confluent.metrics.reporter.bootstrap.servers"
    which has no default value.
  ```
  Process stays alive (this is a background scheduler, not the main
  thread) but logs are noisy and Splunk/Dynatrace will alert on the
  recurring ERROR.
* **Root cause**: same chicken-and-egg shape as A8. The VM
  `.properties` we ported in carried:
  ```
  metric.reporters=io.confluent.telemetry.reporter.TelemetryReporter,io.confluent.metrics.reporter.ConfluentMetricsReporter
  ```
  `ConfluentMetricsReporter` publishes metrics to a Kafka topic
  (`_confluent-metrics`) for C3 / SBC to consume. It needs
  `confluent.metrics.reporter.bootstrap.servers` to know where the
  broker is. On the *controller*, that endpoint is the broker —
  which can't come up until the controllers do. The reporter's
  init keeps failing and the scheduler keeps retrying.
* **Fix**: drop `ConfluentMetricsReporter` from the controller's
  `metric.reporters` list. Keep `TelemetryReporter` — it ships
  directly to Confluent's telemetry endpoint (no broker dependency)
  and doesn't error. Brokers keep both reporters.
  ```yaml
  - metric.reporters=io.confluent.telemetry.reporter.TelemetryReporter
  ```
* **Why it matters**: not a fatal error, but the controller's logs
  fill with this every 16-32 seconds indefinitely. Combined with
  Dynatrace error-rate alerts on the namespace, this triggers
  noise that masks real failures. Same role-split principle as
  A8: don't ask the controller to do broker-side things.

### A10. CFK operator needs cluster-scoped `update`/`patch` on `persistentvolumes`

* **Symptom**: kraftcontroller (or any CFK CR with a PVC-backed
  StatefulSet) reports `status.conditions` with
  `type: platform.confluent.io/cluster-ready` stuck at `False` and
  `reason: ApplyFailed` carrying a message like:
  ```
  persistentvolumes "pvc-<uid>" is forbidden: User
  "system:serviceaccount:confluent-operator:confluent" cannot update
  resource "persistentvolumes" in API group "" at the cluster scope
  ```
  Downstream effect: the Kafka CR waits on kraft's `cluster-ready`
  before creating the broker StatefulSet, so the broker pod never
  gets created even though the controller pod is `1/1 Running`.
* **Root cause**: CFK 3.1.2 (operator build `0.1351.103`) updates
  the backing PV after PVC binding — typically to add ownership
  labels and adjust reclaim policy as part of CFK's data-loss
  protection housekeeping. PVs are cluster-scoped, so this requires
  cluster-level RBAC. The ClusterRole shipped with the older
  `0.1351.59` operator chart (the version vendored in this repo)
  doesn't grant `update`/`patch` on `persistentvolumes`; when
  Container Platforms upgraded the operator binary, they didn't
  refresh the ClusterRole alongside.
* **Fix**: Container Platforms adds to the `confluent-operator`
  ClusterRole:
  ```yaml
  - apiGroups: [""]
    resources: ["persistentvolumes"]
    verbs: ["get", "list", "watch", "update", "patch"]
  ```
  `get/list/watch` are usually already present; the new verbs are
  `update` and `patch`. After the ClusterRole is applied, the
  operator re-reconciles within ~30-60s and `cluster-ready` flips
  to True automatically. No restart needed on our side.
* **Why it matters**: this is owned by FCB Container Platforms, not
  by us — but the symptom appears in our CRs and our namespace,
  so it's easy to spend hours looking at CR-side configuration
  before realizing the operator itself lacks the permission. The
  pod-Ready-but-CR-not-Ready split is the diagnostic signal: when
  `statefulset-available=True` and `resources-ready=True` but
  `cluster-ready=False`, look at the message on the `cluster-ready`
  condition.

### A11. CFK emits `storageClassName: dummy` on every StatefulSet vct — intentional

* **Symptom**: every CFK-managed StatefulSet (Kafka, KRaftController,
  ControlCenter) shows `spec.volumeClaimTemplates[0].spec.storageClassName:
  dummy` in `oc get sts -o yaml`, regardless of what
  `spec.storageClass.name` is set to on the corresponding CR. FCB
  Gatekeeper `[ceph-storage]` constraint initially denied the
  StatefulSet with *"storage class name `<dummy>`"*.
* **Root cause**: not a bug. Confirmed with Confluent product
  engineers — CFK 3.1.x and 3.2.x both emit `dummy` as a sentinel
  in the auto-generated StatefulSet's `volumeClaimTemplate`. The
  real storage class is applied to each PVC through a separate
  operator code path after the StatefulSet is created. The `dummy`
  sentinel is intentionally distinct from any real storage class
  so nothing accidentally provisions storage against the wrong
  class during StatefulSet reconcile. Upgrading the operator
  doesn't change this; it's load-bearing CFK behavior.
* **Fix**: FCB relaxed the Gatekeeper `[ceph-storage]` policy to
  permit `storageClassName: dummy` on CFK-managed StatefulSets
  specifically. **Manifest-side: no change needed** — the
  `spec.storageClass.name: ocs-storagecluster-ceph-rbd` on the CR
  is correct as-is, and the PVCs that actually get provisioned
  reference that real class.
* **Why it matters**: easy to mistake for a misconfiguration on
  the CR ("we set the wrong storage class") and start hunting for
  a CFK CRD field that doesn't exist. It's not a config problem;
  it's the design. If a future CFK version stops emitting `dummy`
  and starts using the real class on the vct, the policy exception
  becomes harmless but unused — no harm in leaving it.

### A12. KRaftController audit log provider fails to start at boot

* **Symptom**: kraftcontroller pod boots cleanly, `KafkaRaftServer
  started` line appears, controller serves as quorum leader fine —
  but a single ERROR pollutes the log right before the "started"
  line:
  ```
  ERROR audit-init-1 ConfluentAuditLogProvider lambda$start$0 -
    Audit log provider could not be started
  org.apache.kafka.common.config.ConfigException: Missing required
    property confluent.security.event.logger.exporter.kafka.bootstrap.servers.
  ```
  Non-fatal — the audit subsystem stays disabled for the lifetime
  of the process; the controller keeps serving normally. But the
  ERROR shows up on every restart, and Splunk/Dynatrace error-rate
  alerts on the namespace can fire on it.
* **Root cause**: same chicken-and-egg as A8 (RBAC provider) and
  A9 (ConfluentMetricsReporter). The audit log provider publishes
  authentication / authorization / RBAC events to a Kafka topic
  (`confluent-audit-log-events`) and needs
  `confluent.security.event.logger.exporter.kafka.bootstrap.servers`
  to find the broker. On the controller, that endpoint is the
  broker — which can't come up until the controller does.
* **Fix**: disable the audit log provider on the controller
  specifically (brokers keep it — they host the audit topic and
  don't have the chicken-and-egg). Add to the kraftcontroller's
  `configOverrides.server`:
  ```yaml
  - confluent.security.event.logger.enable=false
  ```
  Applied across dev/qa/uat as of 2026-06-09. Re-enable on the
  controller only if FCB security team asks for controller-side
  audit events specifically — usually they only care about events
  flowing through the brokers.
* **Why it matters**: third instance of the same role-split pattern
  (A8 = RBAC, A9 = metrics, A12 = audit). When a controller-side
  Confluent subsystem fails to start at boot citing a missing
  broker bootstrap, the answer is almost always "this is broker-
  side functionality, disable it on the controller." Don't try to
  configure a placeholder bootstrap server pointing at the not-
  yet-running broker; that just delays the failure to first-poll
  rather than first-init.

### A13. Prereq Secret stuck in Terminating after uninstall blocks next install

* **Symptom**: a fresh `action=install-or-update` run fails to bring up the
  CFK stack. The kraftcontroller (or another stack CR) reports:
  ```
  type: platform.confluent.io/cluster-ready
  status: 'False'
  reason: ApplyFailed
  message: 'Secret "cfk-license" is invalid: metadata.finalizers:
    Forbidden: no new finalizers can be added if the object is being
    deleted, found new finalizers []string{
      "secret.finalizers.platform.confluent.io/kraftcontroller-kraftcontroller"
    }'
  ```
  `oc get secret cfk-license -o yaml` shows the Secret with a
  `deletionTimestamp` set but still present in the namespace, with
  a single `secret.finalizers.platform.confluent.io/<cr>-<cr>`
  finalizer (referencing whichever CR last claimed it — Connect in
  the dev case captured 2026-06-09).
* **Root cause**: the previous `action=uninstall` deleted a CFK CR
  that had been registered as an **owner** of the Secret (via
  `metadata.ownerReferences`). Kubernetes garbage collection saw
  the owner go away and queued the Secret for deletion (set its
  `deletionTimestamp`). The CFK operator's cleanup step — which
  should remove its own `secret.finalizers.platform.confluent.io/...`
  finalizer from the Secret before the deletion can finalize —
  didn't complete (operator crashed mid-reconcile, lost the watch,
  or just didn't get scheduled before the next install began). The
  Secret is now "dead but not gone": API returns it, the API
  server's gc'er is waiting on the finalizer, and the next
  install's reconcile that tries to ADD its own finalizer to track
  Secret dependency gets rejected — Kubernetes hard rule: **no new
  finalizers may be added once `deletionTimestamp` is set.**
* **Fix**: drop the lingering CFK finalizer so the Secret completes
  deletion, then re-create it fresh via `action=create-prereqs`.
  The pipeline ships a dedicated action — kafka team has no shell
  access, so it's pipeline-driven:
  ```
  confluent-platform.yaml  action: clear-stuck-prereq-finalizers
  ```
  This action finds every Secret in the namespace with a
  `deletionTimestamp` set and **selectively removes only the
  CFK-stamped finalizers** matching `secret.finalizers.platform.confluent.io/*`.
  Any non-CFK finalizers on the Secret (notably ESO's
  `external-secrets.io/finalizer` on ESO-managed Secrets like
  `confluent-license`, `cmf-encryption-key`, `cmf-db-credentials`
  at FCB) are **preserved** — the patch sets `finalizers` to the
  filtered list, not to `[]`. Sequence to recover for a
  pipeline-managed Secret: `clear-stuck-prereq-finalizers`
  → `create-prereqs` → `install`. For an ESO-managed Secret that
  somehow ends up stuck, see **ESO-safety** below — the action
  will report the Secret as "still held by foreign finalizers"
  and skip it, refusing to damage ESO bookkeeping.

* **ESO-safety constraint**: at FCB, three CMF-side Secrets are
  managed by External Secrets Operator from CyberArk —
  `confluent-license`, `cmf-encryption-key`, `cmf-db-credentials`.
  Never manually clear ESO's finalizers. If an ESO-managed Secret
  is stuck Terminating, the correct path is: delete the
  ExternalSecret CR that targets it, let ESO complete its own
  cleanup (removes its finalizer cleanly), then re-apply the
  ExternalSecret to trigger ESO to re-fetch from CyberArk and
  recreate the Secret. The diagnostic step now prints an
  "**ESO-managed Secrets in <namespace>**" inventory at the top so
  the boundary between pipeline-owned and ESO-owned Secrets is
  visible at a glance.
* **Why it matters**: the kraftcontroller log line ("Secret X is
  invalid: metadata.finalizers: Forbidden: no new finalizers...")
  is buried inside the CR's `status.conditions.message` field
  and easy to miss when scrolling raw `oc get -o yaml` output. The
  diagnostic step now flags any Secret with `deletionTimestamp` at
  the TOP of the dump (under `=== Pre-flight: Secrets stuck in
  Terminating? ===`), so the next person hits this in seconds
  instead of an hour. The license content itself was fine — same
  base64-encoded JWT survives across the delete/recreate cycle.
* **Why this happens at all (design observation)**: a shared prereq
  Secret like `cfk-license` carrying an `ownerReferences` to a
  single CR (e.g. Connect) is fragile — deleting that CR cascades
  to the Secret, breaking every OTHER CR that also references it.
  This appears to be how the CFK operator wires up Secret
  dependencies at FCB's version, and we don't control it. The
  defensive posture is to assume any uninstall *might* strand
  prereq Secrets, run `clear-stuck-prereq-finalizers` defensively
  between uninstall and the next install, and never count on the
  uninstall pipeline's own finalizer-cleanup being complete.

### A14. Schema Registry CrashLoopBackOff when applied alongside Kafka — race against broker boot

* **Symptom**: a fresh install applies all CFK CRs and within a
  minute or two `schemaregistry-0` (and often `connect-0` /
  `kafkarest-0` / `controlcenter-0`) is in `CrashLoopBackOff`. SR
  pod logs end with something like:
  ```
  ERROR Error starting the schema registry
  io.confluent.kafka.schemaregistry.exceptions.SchemaRegistryInitializationException:
    Error initializing kafka store while initializing schema registry
    Caused by: org.apache.kafka.common.errors.TimeoutException:
      Timed out waiting for a node assignment.
  ```
  Each restart of the SR pod fires another ~60s wait and another
  crash. The Kafka brokers come up eventually but SR is now stuck in
  exponential-backoff and may take an extra 10-20 minutes to
  recover on its own.
* **Root cause**: `oc apply` returns the instant a CR is admitted —
  it does NOT wait for the CR's pods to be running, let alone
  ready. The CFK operator then reconciles every CR in parallel.
  So at t+0 the operator creates StatefulSets for kraftcontroller,
  kafka, schemaregistry, connect, kafkarest, and controlcenter
  simultaneously. The Kafka brokers take 1-3 minutes to elect a
  controller and open the bootstrap listener. The SR pod, started
  at the same time, has `kafkastore.init.timeout.ms` defaulting to
  ~60s; it hits that window before brokers are reachable, exits
  non-zero, k8s restarts it, repeat.
* **Fix**: gate the apply at the pipeline level. The install action
  in `.azure-pipelines/confluent-platform.yaml` is now phased:
  ```
  Phase 1: oc apply kafkarestclass + kraftcontroller + kafka
  Wait:    up to 15 min for kraftcontroller to report cluster-ready
  Wait:    up to 15 min for kafka to report cluster-ready
  Phase 2: oc apply schemaregistry + connect + kafkarest + controlcenter
  ```
  The wait polls
  `.status.conditions[?(@.type=="platform.confluent.io/cluster-ready")].status`
  every 10s with a 60s heartbeat that dumps the current condition
  table so the log is useful when watching live. Phase 2 doesn't
  fire until both upstream CRs are healthy, so dependent pods are
  never created against an unready Kafka.
* **Why we couldn't do this at the pod level**: the obvious fix is
  an `initContainer` on the SR StatefulSet that runs
  `until nc -z kafka.dah-flink-<env>.svc 9092; do sleep 2; done`
  before the main container starts. CFK 3.1.x CRDs don't expose
  `podTemplate.initContainers` (runbook A3 — same shape as the
  startupProbe and other podTemplate omissions). Until the bank
  upgrades the operator to a version that allows it, pipeline-side
  gating is the only lever.
* **If the wait legitimately times out (15 min)**: don't bump the
  timeout reflexively. The usual root causes are (a) the brokers
  can't reach kraftcontroller (network or RBAC), (b) OAuth /
  bootstrap-listener config is wrong on the broker, (c) cluster is
  out of resources and pods are stuck Pending — the diagnostic
  dump (`action=diagnostics`) shows which. Fix the upstream issue;
  the 15 min ceiling is generous for a working install and a
  conservative ceiling for a broken one.

### A17. FIPS-mode CFK operator "TLS not Enabled in Application" — what it *isn't* and what it *is*

* **Symptom**: a CFK CR (Kafka, SchemaRegistry, …) sits at
  `cluster-ready=False ApplyFailed` with
  ```
  Cannot create http client: TLS not Enabled in Application when
  FIPS mode is true in Operator
  ```
  Pods may even be `1/1 Running`, but the CR never flips ready and the
  install pipeline's wait loop times out.
* **First-pass theory (wrong)**: add `tls.enabled: true` alongside
  `secretRef:` on `spec.tls`. This was the working theory in commit
  `94b3d0d` but the 2026-06-29 diagnostic disproved it. The post-
  admission `kafka.yaml` dump (`oc get kafka kafka -o yaml`) shows
  CFK 3.2.0 v1beta1 **silently strips** the top-level
  `spec.tls.enabled` field — only `spec.tls.secretRef` survives.
  Confirmed by the `kubectl.kubernetes.io/last-applied-configuration`
  annotation: the applied yaml has `"tls":{"enabled":true,"secretRef":
  "kafka-tls"}` but the live spec has only `secretRef:`. Same family
  of silent-strip as `services.mds` and `listeners.external.oauthSettings`
  (memory `project_cfk_v1beta1_silent_strips`). Adding the flag is
  inert — the schema doesn't accept it. The nested
  `dependencies.kRaftController.controllerListener.tls.enabled` and
  `listeners.internal.tls.enabled` both survive admission — only the
  *top-level* `spec.tls.enabled` is rejected.
* **Real root cause**: the CFK operator pod itself is crash-looping.
  The 2026-06-29 live operator pod yaml (`~/Downloads/operator.yaml`)
  shows `restartCount: 14` against a pod started 2026-06-26T22:14:33Z
  (3 days, ~5 crashes/day). The previous container died
  2026-06-29T10:51:13Z with `exitCode: 2 reason: Error`, ~30s before
  the current container started at 10:51:14Z. Every restart picks up
  CRs with stale conditions and either fails to re-evaluate them or
  dies again before it can — which is why the same spec shape came up
  green at 2026-06-27T17:59Z (operator fresh) and stuck at 19:15Z
  (operator restart cycle began). It's a Container-team-owned operator
  stability issue, not a spec-side problem. The `kafka.spec.fips`
  top-level field exists in the v1beta1 schema (per `oc explain
  kafka.spec`) and may still be relevant for FIPS configuration of
  the CR, but it cannot recover a CR stuck with stale conditions
  written by a previously-crashed reconciliation.
* **Workaround**: ask Container team to investigate operator pod
  crashes (Splunk operator log for `Exit 2` panics) and bounce both
  replicas after fixing. The 17:59Z green run is proof the cluster's
  spec is compatible with the operator when the operator stays up.
* **Why it matters**: this looked like an actionable spec fix and
  isn't. Don't burn cycles adding TLS flags to CRs in response to
  this condition — verify post-admission whether the field even
  survived. The condition's text ("TLS not Enabled in Application")
  is misleading: the operator is reporting its own inability to
  build an outbound HTTP client to the CR's services, not a spec
  validation failure.

---

### A16. `inter.broker.listener.name=internal` strands outbound broker-broker without client JAAS

* **Symptom**: Kafka cluster comes up (brokers `1/1 Running`, sts/kafka
  3/3, CR `cluster-ready=True`), but inter-broker operations
  (replication, controlled shutdown, controller-leader requests)
  silently fail or hang because outbound broker-to-broker connections
  have no client credentials to present on the `internal` listener.
* **Root cause**: when `inter.broker.listener.name=internal` is set as
  a `configOverrides.server` line in the Kafka CR, CFK wires only the
  **server-side** SASL/PLAIN accept-side credentials for `internal:9071`
  (the `apikeys.json` mount from the `sasl-plain-internal` Secret). CFK
  does NOT render the matching **client-side**
  `listener.name.internal.plain.sasl.jaas.config` `username=${file:...}` /
  `password=${file:...}` references — those are only generated for the
  auto-managed `replication:9072` listener that CFK uses by default for
  inter-broker traffic. The override moves inter-broker off the
  listener that has both sides of the JAAS handshake onto one that has
  only the inbound half.
* **Fix**: remove the `inter.broker.listener.name=internal` line from
  `spec.configOverrides.server`. CFK reverts to using its auto-managed
  `replication` listener for inter-broker, which has both sides wired.
  `internal` remains available as the in-cluster client listener for
  Flink / SR / Connect / REST / C3 — it just isn't used for
  broker-to-broker.
* **Why it matters**: the symptom is silent — brokers report
  `cluster-ready=True` because the listener-up healthcheck only
  exercises the server side. Cluster-link metadata replication, ACL
  propagation, and ISR maintenance start failing only when a broker
  actually needs to call another broker on the listener that has no
  client creds. Discovered 2026-06-27 by Ayu while diffing the
  rendered `server.properties` against the mounted Secret contents
  (`plain-interbroker.txt` had the credentials; the rendered
  `listener.name.internal.plain.sasl.jaas.config` did not reference
  them). The Secret was fine; the listener wiring was wrong.

---

### A15. CFK 3.2.0 v1beta1 "silent-strip" — narrower than first concluded; the real failure mode is operator crash + FIPS-on-auto-PLAINTEXT-external

> **Correction landed 2026-06-29.** The original entry generalized
> "CFK 3.2.0 v1beta1 silently strips every schema-mismatched block".
> Subsequent diagnostics (2026-06-29T21:13Z apply with the VM-aligned
> kafka.yaml) showed `listeners.external.authentication.oauthSettings`,
> `listeners.custom[name=certonly]`, and the explicit `tls.enabled:
> true` on each listener ALL SURVIVED admission. The earlier
> "stripped at admission" observations were partially correct and
> partially confounded by the operator's crash-loop window writing
> stale conditions; the over-generalized "everything strips" mental
> model led us to remove blocks that didn't need removing.

* **What is genuinely silent-stripped** (still confirmed):
  - `dependencies.kRaftController.{authentication,tls}` as siblings of
    `clusterRef` (must be nested under `controllerListener`).
  - Top-level `spec.tls.enabled: true` (v1beta1 schema accepts only
    `secretRef` at that level; `enabled` is dropped).
* **What is NOT silent-stripped** (despite earlier conclusions):
  - `listeners.external` block including `authentication.oauthSettings`
    with full Okta wiring — survives admission intact.
  - `listeners.custom` array with mTLS certonly — survives admission.
  - `listeners.{internal,external}.tls.enabled: true` — these
    listener-level TLS flags do survive.
  - `services.mds` — earlier dumps had this missing from post-admission
    spec; need fresh confirmation as part of the Phase 2 schema-fix
    workstream.
* **The actual repeating failure**: FIPS-mode CFK operator (Container
  team enables `fipsmode=true` at the operator helm release) inspects
  the running broker's rendered `listener.security.protocol.map` on
  every reconcile. If `spec.listeners.external` is absent from the CR,
  CFK auto-creates an `EXTERNAL:PLAINTEXT` default. FIPS rejects that
  and the CR oscillates `cluster-ready=True` ↔ `False ApplyFailed:
  Cannot create http client: TLS not Enabled in Application when FIPS
  mode is true in Operator` (observed at 19:41Z green → 20:34Z stuck
  on 2026-06-29 with no spec change). **The fix is to declare an
  explicit external listener with TLS enabled** — not to remove
  blocks.
* **Compounding factor — operator crash-loop**: when the operator pod
  is restarting (restartCount=14 over 2026-06-26 → 2026-06-29 per
  Rick's operator-pod yaml), partial reconciles leave the CR with
  stale conditions and incomplete StatefulSet rollouts. This produces
  the "I applied a new spec but the brokers still run the old config"
  symptom — not a strip, but a half-finished reconcile that looks
  like one. See memory `project_fcb_cfk_operator_crash_loop`.
* **What we changed in response** (commit landing this correction):
  - dev/kafka.yaml: Phase 1 baseline with `internal` AND `external`
    listeners both SASL_SSL/PLAIN against `sasl-plain-internal`. No
    OAuth, no mTLS, no MDS yet — those come in Phase 2.
  - Removed kafka-bisect.yaml + kafka-minimal.yaml (bisect concluded).
  - Removed `kafkaCRVariant` pipeline parameter (only one variant now).
  - kraftcontroller.yaml keeps `ConfluentServerAuthorizer` +
    `providers=KRAFT_ACL`: controllers manage ACLs from the KRaft
    metadata log directly, never reach for MDS. **Do NOT copy this
    combo to brokers** — broker RBAC plumbing demands an MDS bootstrap
    and brokers fatal `confluent.metadata.bootstrap.servers missing`
    without it.
* **Phase 2 plan** (next): re-add `services.mds` + OAuth on external +
  mTLS certonly + `spec.authorization` (now confirmed as a real
  v1beta1 field) + ConfluentServerAuthorizer with `CONFLUENT,KRAFT_ACL`
  on brokers. All credentials sourced from the existing variable
  group (`oauth-broker/sr/connect/c3/kafkarest/mds-rest` client-id +
  secret). Track in pump.txt.
* **What to verify post-apply**: ALWAYS dump `oc get kafka -o yaml`
  and check that the live spec matches what was applied. The
  `kubectl.kubernetes.io/last-applied-configuration` annotation shows
  what was sent; the live `spec:` shows what the operator sees. Diff
  the two before concluding a field was stripped — and check operator
  pod `restartCount` before blaming the schema.

---

## B. FCB Gatekeeper policies

### B1. `[pod-disruption-budget]` rejects CFK's default PDB (`maxUnavailable: 0`)

* **Symptom**: KRaftController and Kafka CRs admit but their
  auto-generated PDBs fail admission with
  *"PodDisruptionBudget has maxUnavailable of 0, only positive integers
  are allowed"*. Stack stays in *"waiting for at-least one kRaft
  controller pod availability"*.
* **Root cause**: CFK auto-creates a PDB per workload. For single-replica
  workloads, the default `maxUnavailable` lands at 0, which the policy
  treats as "blocks drains forever".
* **Fix**: add an explicit PDB block to every CFK CR:
  ```yaml
  pdb:
    enabled: true
    maxUnavailable: 1
  ```
  Required even for single-replica components like KRaftController and
  Kafka in dev. SchemaRegistry/Connect/KafkaRest/ControlCenter already
  had this block in the initial commits; Kafka + KRaftController did not.
* **Why it matters**: this was a hard blocker, not a warning — the whole
  stack fails to come up until the PDB validates.

### B2. `[replica-range]` requires `min_replicas: 2` for StatefulSets

* **Symptom**: warning fires on ControlCenter SS in dev (where C3 is at
  `replicas: 0` by design).
* **Root cause**: FCB policy demands min=2 replicas for StatefulSets to
  enforce HA. ControlCenter doesn't horizontally scale the way brokers
  do, and dev's tight quota doesn't fit two C3 pods anyway.
* **Fix**: in dev, accept the warning until quota is raised; in upper
  envs, run C3 at `replicas: 2` (CFK supports 2-replica C3 in HA mode).
* **Why it matters**: this is a *warning*, not a denial. The SS still
  comes up at replicas=0/1; you just see persistent warning events.

### B3. `[required-configmap-labels]` on `fcb-trust-bundle`

* **Symptom**: warning on the `fcb-trust-bundle` ConfigMap in the
  namespace.
* **Root cause**: that ConfigMap is distributed by an FCB cluster-wide
  trust-bundle job, not by anything in this repo.
* **Fix**: out of our scope. Document and ignore, or ask Container
  Platforms to fix it upstream.
* **Why it matters**: easy to mistake for one of *our* ConfigMaps.
  Verify ownership before chasing.

### B4. `WarningAdmission` is not the same as `FailedAdmission`

* **Symptom**: long admission-event lists mix warnings and denials,
  visually identical at a glance.
* **Root cause**: Gatekeeper has both *deny* and *warn* enforcement
  actions. WarningAdmission events do not prevent resource creation.
* **Fix**: filter for `reason=FailedAdmission` first when triaging.
  Warnings can be left for later (or escalated for policy exemption).
* **Why it matters**: time-wasters. Don't try to "fix" a warning that
  isn't blocking anything.

---

## C. Secret management (ESO + CyberArk CCP)

### C1. CMF wants the raw JWT; CFK Kafka wants `license=<JWT>` properties

* **Symptom**: ExternalSecret syncs but CMF fails to validate the
  license, with errors about malformed JWT.
* **Root cause**: CMF reads the secret value AS the JWT directly. CFK
  Kafka, by contrast, reads a properties file shape (`license=<JWT>`).
  Same CyberArk record, two different consumer expectations.
* **Fix**: for the CMF ExternalSecret, drop any `license=` prefix and
  pass the raw JWT. For the CFK Kafka ExternalSecret (different file),
  keep the `license=<JWT>` properties shape.
* **Why it matters**: we initially diagnosed this as URL-encoding of
  spaces in webhook addresses (a red herring). Stay disciplined about
  matching the consumer's expected format.

### C2. CyberArk "duplicate" records can live in different safes

* **Symptom**: ExternalSecret config points at one safe, but the record
  with that name is in a different safe.
* **Root cause**: FCB has multiple safes for the same app (e.g.
  `11547_D_KEY_FP` for keys/licenses, `11547_D_UNX_FP` for Unix SSH).
  Two records named the same can be split across them.
* **Fix**: confirm safe with Walter / Tushar before authoring the
  ExternalSecret. Double-check the path in the webhook URL.
* **Why it matters**: this looked like a sync error; it was actually
  looking in the wrong safe.

### C3. Webhook URL spaces must be `%20`-encoded

* **Symptom**: ExternalSecret fails to sync; `SecretSyncedError` events.
* **Root cause**: Go's `url.Parse` (used by the ESO webhook provider)
  refuses URLs with raw spaces in the path/query. CyberArk safe and
  account names with spaces in them need encoding.
* **Fix**: replace spaces with `%20` in the webhook URL string.
* **Why it matters**: not all CyberArk records have spaces, so this
  bites unpredictably. Worth a checklist item.

### C4. ExternalSecret object name must be RFC1123-safe

* **Symptom**: ExternalSecret apply fails with name-validation error.
* **Root cause**: Kubernetes object names must match DNS-1123. CyberArk
  record names with uppercase / special chars do not.
* **Fix**: name the ExternalSecret with a lowercase, hyphenated
  derivative of the CyberArk record name. Map back via the
  `remoteRef` block.
* **Why it matters**: keeps the K8s name stable even if the CyberArk
  record gets renamed.

### C5. CMF encryption key — must be base64 everywhere; `oc create --from-literal` double-encodes

* **Symptom**: UAT CMF pod crashloops at boot with
  `BeanCreationException: 'encryptionConfigInitializer' init failed`
  caused by `IllegalStateException: The provided encryption key is of
  352 bits. The encryption key should be either 128 or 256 bits long…`.
  The `cmf-encryption-key` Secret in the namespace has
  `data.key: NGxm…MD0=` (44-char base64 of a 44-char base64 string).
* **Root cause**: CMF's encryption key is 16 or 32 *raw bytes*. Those
  bytes are non-printable, so the canonical transport format
  (variable groups, CyberArk records, Helm `--set`, anything string-
  shaped) is the base64 encoding produced by `openssl rand -base64
  {16,32}` (i.e. a 24- or 44-char ASCII string). The Kubernetes Secret
  field where those bytes belong is `data.key`, which is itself
  defined to hold base64-encoded bytes — so the variable's value
  should be copied verbatim into `data.key`. Using
  `oc create secret generic --from-literal=key=$VAR` instead treats
  `$VAR` as a UTF-8 string and base64-encodes it a *second* time for
  transport into `data.key`. K8s decodes once at read time, CMF gets
  the original 44-char base64 string back as raw bytes (44 bytes = 352
  bits), rejects it, and refuses to boot.
* **Fix**:
  1. **Storage invariant (variable groups + CyberArk)**: always store the
     **base64** form (e.g. `4lfC07xMkR75PJOsu0RDMN0yCepTs8gdBK+FSAgyx30=`),
     never the raw 32-byte form. This applies equally to the
     `*-cmf-encryption-key` Azure DevOps variables today and to the
     CyberArk record CMF will read via ESO once onboarded.
  2. **Pipeline**: in `.azure-pipelines/cmf.yaml`, the non-dev branch
     creates the Secret via a dedicated `oc apply -f -` heredoc that
     writes `${CMF_ENC_KEY}` straight into `data.key` (the field where
     base64 belongs). Includes pre-flight validation: must be valid
     base64, must decode to exactly 16 or 32 bytes. Do **not** route
     this Secret through `create_labeled_secret` — that helper uses
     `--from-literal` and is right for `confluent-license` /
     `cmf-db-credentials` (which hold UTF-8 strings) but wrong here.
  3. **Re-deploy**: delete the corrupted Secret
     (`oc -n dah-flink-<env> delete secret cmf-encryption-key`) before
     the next pipeline run so the new `oc apply` writes a clean object.
     If CMF ever managed to write encrypted rows with the broken key
     (it hasn't in our case — it never finished boot), those rows are
     unrecoverable; a DB-level reset is required.
* **Why it matters**: this is a near-invisible foot-gun — the Secret
  object is created successfully, the labels are right, the field name
  is right; only the *byte length* is wrong, and only CMF notices, at
  init time. The double-encoding was already in the pipeline since
  uat was first wired up; dev only escaped because dev uses ESO/
  CyberArk (path renders the bytes correctly). The fix locks the
  base64-everywhere invariant so qa/uat/prd and the eventual CyberArk
  cut-over all behave identically. **Reference**: dumps/dump-2026-06-18*
  (UAT CMF crashloop); commit that landed the pipeline fix + this
  entry.

---

## D. Image versioning + CFK operator alignment

### D1. Operator and init container minor versions MUST match

* **Symptom**: opaque pod-startup failures (init container exits
  non-zero with cryptic message); pods stick in Init:0/1.
* **Root cause**: the `confluent-init-container` image is tightly
  coupled to the operator minor. Cross-minor (e.g. operator 3.1.x +
  init 3.2.x) breaks the config-rendering contract.
* **Fix**: keep `spec.image.init` aligned with the deployed operator's
  CFK minor. As of 2026-06-01 the operator is `0.1351.103` = CFK 3.1.2,
  so `image.init: ...confluent-init-container:3.1.2`. See the
  `[project-fcb-cfk-operator-ownership]` memory for the
  build-number ↔ semver mapping.
* **Why it matters**: the operator is owned by FCB Container Platforms;
  they upgrade on their own cadence. Every CR-set deploy is a chance
  to re-verify the alignment.

### D2. cp-* images stay on the 8.1 LTS line, not 8.2

* **Symptom**: tempting to use 8.2.x because it's "the latest" on Docker
  Hub.
* **Root cause**: 8.1 is the current LTS branch at FCB. 8.2 is newer but
  not what's mirrored to Artifactory and not what's been certified
  internally.
* **Fix**: cp-server, cp-schema-registry, cp-server-connect, cp-kafka-rest
  → `8.1.3`. ControlCenter next-gen is on its own version line (`2.5.0`)
  independent of cp-*. Init container tracks operator (currently `3.1.2`).
* **Why it matters**: image tags must exist in `artifactory.fcbint.net`
  before any deploy. Confirm with Tushar before bumping.

### D3. Vendored Helm chart in `charts/confluent-for-kubernetes/` is reference-only

* **Symptom**: dev cluster runs a newer operator than the chart's
  `Chart.yaml` says.
* **Root cause**: Container Platforms manages the live operator install
  outside this repo. The vendored chart is a snapshot, kept for CRD
  reference when authoring CRs.
* **Fix**: never `helm install` from the vendored chart. Always confirm
  the live operator version (Tushar can fetch from cluster). If
  authoring a CR with an unusual field, check the vendored CRD only
  after confirming it's recent enough.
* **Why it matters**: stale chart = stale CRD shape; you might write
  CRs against fields that don't exist in the deployed operator.

---

## E. OpenShift specifics

### E1. Disable CFK's injected `podSecurityContext` for OpenShift SCC compatibility

* **Symptom**: pods fail to start under OpenShift's `restricted-v2` SCC
  with permission errors on runtime paths.
* **Root cause**: CFK injects `fsGroup: 1001` and `runAsUser: 1001` by
  default. OpenShift's `restricted-v2` SCC requires the UID/GID to come
  from the namespace's allocated range (`1001320000–1001329999`), not
  hardcoded.
* **Fix**: set `podTemplate.podSecurityContext: {}` in every CFK CR.
  This tells the operator to inject nothing, and OpenShift then assigns
  from the namespace range. CP 8.1 images are built UID-agnostic with
  GID-0 group-write on runtime paths, so this works without any
  `anyuid` SCC binding.
* **Why it matters**: this is OpenShift-only. Vanilla Kubernetes
  deploys don't hit this. Don't omit on the assumption "default values
  are fine".

### E2. Ceph RBD CSI driver must be registered on every node that hosts CFK pods

* **Symptom**: `MountVolume.MountDevice failed for volume "pvc-..." :
  driver name openshift-storage.rbd.csi.ceph.com not found in the list
  of registered CSI drivers`. Pod stuck in `ContainerCreating`.
* **Root cause**: ODF/Ceph CSI driver is not running on every worker.
  Pod was scheduled on a node where the driver pod isn't healthy.
* **Fix**: escalate to Rick / Container Platforms — this is a
  cluster-platform issue, not a manifest fix. As a temporary
  workaround, you can use a node selector to keep CFK pods off the
  affected node(s), but the real fix is platform-side.
* **Why it matters**: hit this on dev kraftcontroller-0. Without
  kraft, nothing comes up. Easy to mistake for a CFK / manifest issue
  because the symptom is "Kafka won't start".

### E3. Connect's finalizer hangs on uninstall when the brokers are unhealthy

* **Symptom**: `Uninstall Confluent Platform CRs` step runs
  `oc delete -f connect.yaml --wait=true --timeout=5m`. The API
  reports `"connect" deleted` instantly, but the wait times out after
  five minutes. Final `oc get connect` still shows the CR with a
  `deletionTimestamp` set. Other CRs (kafkarest, SR, kafka, kraft,
  controlcenter, kafkarestclass) all delete clean in the same run.
* **Root cause**: the CFK operator's Connect-finalizer logic tries to
  do a graceful cluster shutdown — stop tasks, flush offsets to
  `connect-cluster-offsets`, leave the consumer group. All of that
  requires a healthy broker conversation. In a teardown of a
  cluster where kraft never came up (e.g. the Ceph CSI failure in
  E2), Kafka was never Ready, so the operator's graceful path hangs
  until the 5-minute timeout. With Connect at `replicas: 0` there's
  also no Connect pod for the operator to reach via REST — making
  even the "find the running cluster and shut it down nicely"
  alternative impossible.
* **Fix (immediate, manual)**:
  ```
  oc -n dah-flink-<env> patch connect connect \
    --type=merge -p '{"metadata":{"finalizers":[]}}'
  ```
  Force-drops the finalizer; the CR is GC'd within a second.
  Safe because the underlying StatefulSet and pods are already
  gone (the operator removed them before getting stuck on the
  graceful-flush call).
* **Fix (pipeline)**: the uninstall step in
  `.azure-pipelines/confluent-platform.yaml` already falls back to
  patching `metadata.finalizers: []` on any CR stuck with a
  deletionTimestamp after the per-CR delete timeout. This used to be
  behind a `forceFinalizerRemoval=true` opt-in but is now always-on:
  the inner safety gate refuses to patch when a live StatefulSet or
  Pod for the CR still exists, so the fallback only fires for the
  exact stuck-on-graceful-flush class of cases described here.
* **Why it matters**: this isn't a CFK bug per se — the operator
  doing graceful shutdown is the right behavior. It's the
  combination *broken cluster + uninstall* that gets you. Every
  CFK component that talks to Kafka during cleanup (Connect is the
  worst offender, SR is second-worst) can hit a variant of this.

---

## F. ResourceQuota / sizing arithmetic

### F1. Default dev quota (2 CPU / 8 Gi) is too tight for the full 6-CR stack

* **Symptom**: `FailedCreate ... pods "X" is forbidden: exceeded quota:
  compute-resources` on the 5th or 6th CFK pod.
* **Root cause**: see A3 — every CFK pod claims ~500m via the init
  container floor. 6 pods × ~500m = ~3 CPU, well over the 2 CPU dev
  quota.
* **Fix (short-term)**: scale down to JVM minimums on every CR's
  `podTemplate.resources` (cp-server: ~400m/1.5Gi; SR: ~150m/512Mi;
  etc.), and suspend non-critical components to `replicas: 0` to fit
  (as of 2026-06-01 dev has ControlCenter and Connect at 0).
* **Fix (long-term)**: ask Tom to raise the dev quota to at least
  ~6 CPU / 24 Gi before declaring dev "done".
* **Why it matters**: every TEMP scale-down has a corresponding
  `Revert to ... when Tom raises the quota` comment in the CR. When the
  quota does get raised, sweep all the TODOs.

### F2. C3 next-gen at 12 CPU / 16 Gi (UAT-like) does not fit dev

* **Symptom**: C3 SS is created but no pod schedules (quota exceeded).
* **Root cause**: C3 dev was initially copied from UAT sizing.
* **Fix**: C3 dev is suspended (`replicas: 0`) until quota allows. When
  it comes back, size to 2 CPU / 4 Gi for dev smoke testing — full
  12/16 sizing is for uat/prd/dr only.
* **Why it matters**: C3 RocksDB state is heavy, but in dev we don't
  need long retention.

### F3. TEMP-shrunk KRaftController memory caused chronic OOM after quota raise

* **Symptom**: `kraftcontroller-0/1/2` in CrashLoopBackOff with
  `exitCode: 137`, lifetime ~60 seconds, `restartCount` climbing into
  the hundreds (597 observed). Pod becomes Ready briefly after init,
  then SIGKILLed mid-`MetadataLoader stillNeedToCatchUp` between
  snapshot load and high-watermark catch-up. KRaft `epoch` field
  grows into the thousands as the three controllers churn through
  fresh elections every restart.
* **Root cause**: TEMP sizing from F1 left the main container at
  `requests.memory: 384Mi`, `limits.memory: 512Mi`. CFK 3.1.x sizes
  the JVM heap from `requests.memory` and pins it on the command
  line with `-Xms`/`-Xmx` (`MaxHeapSize=384Mi {command line}`
  visible in the PrintFlagsFinal dump). That leaves ~128 Mi between
  heap and limit for JVM non-heap — metaspace, code cache, direct
  buffers for the SASL_SSL listener, thread stacks. Snapshot replay
  + TLS at startup blows past 128 Mi non-heap in seconds → cgroup
  OOM kill. Every restart adds a new KRaft epoch + records → bigger
  snapshot for the next attempt → more memory pressure. Vicious
  loop, self-amplifying.
* **Fix**: restore the documented "real dev" sizing on
  `spec.podTemplate.resources` — `requests.cpu: "1"`,
  `requests.memory: 2Gi`, `limits.cpu: "2"`, `limits.memory: 2Gi`.
  Heap lands at 2 GiB with ~500 Mi headroom on top for non-heap.
  Memory request == limit makes the memory QoS class Guaranteed —
  the kernel won't pick this pod first under node memory pressure.
* **Why it matters**: the TEMP sizing was set under F1 when the dev
  quota was 2 CPU / 8 Gi. After the quota was raised to 11/22 CPU
  and 42/84 Gi mem, the TEMP shrinks weren't reverted and silently
  broke the cluster the moment metadata volume grew enough to need
  >128 Mi non-heap. Every `TEMP sizing` comment in
  `apps/confluent-platform/*/` is a landmine — sweep them all
  after any quota change, not just the file under the current PR.

---

## G. Apache Flink Kubernetes Operator

### G1. FlinkDeployment / FlinkApplication can't override Deployment-level labels

* **Symptom**: FCB Gatekeeper `[required-workload-labels]` denies the
  Deployment that the operator creates, even though we set labels on
  `spec.podTemplate.metadata.labels`.
* **Root cause**: the Apache Flink K8s Operator does not expose a
  Deployment-level label override; `podTemplate.labels` only lands on
  the Pod inside the Deployment.
* **Fix**: escalation only — request a cluster-level
  admission-mutation policy from Rick that adds FCB common-metadata
  labels to FlinkDeployment-managed Deployments at admission time.
  No manifest-side fix exists.
* **Why it matters**: contrast with CFK's `injectLabels`, which *does*
  solve this for CFK. Flink K8s Operator lacks the equivalent.

---

## H. Other / cross-cutting

### H1. CMF stock 2.3.0 has known bugs at FCB — use `2.3.0-fcb-preview-2`

* **Symptom**: CMF deploys but Flink jobs fail / behave oddly.
* **Root cause**: Confluent-issued preview build fixes a set of bugs
  specific to FCB's environment. Stock 2.3.0 is unsafe to run here.
* **Fix**: `image.tag: 2.3.0-fcb-preview-2` everywhere CMF appears.
* **Why it matters**: this is not a Docker Hub tag — it's an
  Artifactory-hosted Confluent preview. Confirm availability before
  bumping.

### H2. CMF RBAC is namespace-scoped, not cluster-scoped

* **Symptom**: cluster-scoped RBAC manifests get audit-flagged.
* **Root cause**: CMF deploys to `dah-flink-<env>`, not
  `dah-kafka-<env>`, and its operations are scoped to that namespace.
* **Fix**: use Role/RoleBinding, not ClusterRole/ClusterRoleBinding.
  See `apps/confluent-cmf/<env>/rbac/`.
* **Why it matters**: less blast radius, easier to defend at audit.

### H3. Flink Environment / Catalog / Database point at VM Kafka, not CFK Kafka

* **Symptom**: troubleshooting Flink jobs by checking the CFK Kafka
  cluster yields nothing relevant.
* **Root cause**: throughout the migration, CMF's Flink jobs are
  configured against the VM Confluent Platform (per-env). The CFK
  cluster doesn't take Flink traffic until per-env cluster-link
  migration completes for that env.
* **Fix**: when troubleshooting Flink, assume the VM CP brokers + SR
  are the data path until cluster-link cutover is announced for that
  env.
* **Why it matters**: saves hours of looking in the wrong place.

### H4. Don't embed multi-line `python3 -c "..."` inside a YAML `script: |` block

* **Symptom**: a pipeline action that shells out to a few lines of
  Python crashes immediately on the first python line with
  `IndentationError: unexpected indent`, even though the script
  "looks" properly indented in the YAML. Subsequent dependent
  python calls then hit `json.decoder.JSONDecodeError: Expecting
  value: line 2 column 1 (char 1)` because the upstream output is
  empty. The action reports `Failed: N Secret(s)` and patches that
  should have rendered like `'{"metadata":{"finalizers":[...]}}'`
  arrive at the API server as `'{"metadata":{"finalizers":}}'` and
  get rejected with `error decoding patch: invalid character '}'`.
* **Root cause**: YAML `script: |` preserves indentation inside the
  block literally. When the script does
  ```bash
  X=$(python3 -c "
                    import json, sys
                    ...
                    ")
  ```
  the `import` line is passed to python with the YAML block's
  18-space indent baked into the string. Python sees that as an
  invalid indent at module top level and bails.
* **Fix**: collapse the python to a single line and pipe input via
  stdin. Two birds with one stone — no indentation surface, and
  no risk of shell-quoting accidents if a value contains a special
  character:
  ```bash
  X=$(printf '%s' "$INPUT_JSON" \
    | python3 -c 'import json,sys; data=json.load(sys.stdin); print(json.dumps(...))')
  ```
  If the logic genuinely needs multiple statements, separate them
  with `;` and keep the whole thing on one line. For anything
  beyond ~3 statements, write a small `.py` helper in `tools/` and
  call it from the YAML instead.
* **Why it matters**: this failure mode is silent in the worst
  way — the python error is buried, and what surfaces is a
  downstream `oc patch` rejecting malformed JSON, which looks
  like an `oc` problem and sends the next person down the wrong
  trail. Caught 2026-06-10 in `clear-stuck-prereq-finalizers`;
  fixed in the same commit as this entry.

### H5. CMF Kafka catalog/database registers successfully but won't carry real traffic if `security.protocol` doesn't match the broker's listener

* **Symptom**: `flink-environments` pipeline succeeds, `cmf_get
  /cmf/api/v1/catalogs/kafka` and `.../databases` both list the new
  catalog and database. Engineers conclude the integration "works."
  The first real Flink SQL statement against the catalog later fails
  with SSL handshake or authentication errors, sometimes hours or
  days after the apparently-successful pipeline run.
* **Root cause**: CMF's `POST /cmf/api/v1/catalogs/kafka/...` and
  `.../databases` endpoints only **store the connection metadata**;
  they don't open a Kafka connection at creation time. So a
  `connectionConfig` block with the wrong `security.protocol` for the
  port being bootstrapped will register successfully and look
  healthy in every listing endpoint — but Flink jobs that actually
  use the catalog hit the real broker listener and fail.
  At FCB the VM brokers' `listeners=...` line binds:
  - `INTERNAL://:9092` mapped to `SASL_SSL` (Okta OAUTHBEARER)
  - `BROKER://:9091` mapped to `SASL_SSL` (PLAIN, interbroker)
  - `CERTONLY://:9094` mapped to `SSL` with
    `listener.name.certonly.ssl.client.auth=required` (mTLS)

  The dev and uat `apps/confluent-flink/<env>/kafka-database.json`
  files both point at `:9094` with `security.protocol: PLAINTEXT`
  today. That registers in CMF without complaint, but a real client
  connection sends plaintext bytes into a port that expects a TLS
  ClientHello + client certificate and gets reset immediately.
* **Fix (when ready to actually run Flink SQL through the catalog)**:
  fix the `connectionConfig` to match the listener. Two viable
  shapes:
  1. **Keep port 9094 (CERTONLY) with proper mTLS** — set
     `security.protocol: SSL`, and add `ssl.truststore.location`,
     `ssl.truststore.password`, `ssl.keystore.location`,
     `ssl.keystore.password`, `ssl.key.password`. The truststore +
     keystore must be projected into the CMF pod filesystem (via a
     mounted Secret) at the configured paths.
  2. **Switch to port 9092 (INTERNAL) with SASL_SSL OAUTHBEARER** —
     set `security.protocol: SASL_SSL`, `sasl.mechanism:
     OAUTHBEARER`, the OAuth `sasl.jaas.config` clientId/secret/scope
     block, the
     `io.confluent.kafka.clients.plugins.auth.oauth.OAuthBearerLoginCallbackHandler`
     callback, and Okta's token endpoint URL. Recommended long-term
     because it reuses the Okta wiring the rest of the platform
     already has — no per-component truststore/keystore mounts.
* **Why it matters**: this is a silent integration-test escape. The
  `flink-environments` pipeline going green proves CMF accepted the
  JSON, not that the data path works. Don't let a green pipeline
  close out the Flink-to-Kafka integration ticket — there has to be
  an actual SQL statement that reads or writes a Kafka topic before
  the catalog is "real." The current `:9094 + PLAINTEXT` config is
  deliberate during the dev/uat bootstrap (Tracker 2.10 is the
  ongoing non-standard-port + mTLS-credential workstream); flip to
  the right protocol per-env as Tracker 2.10 lands the broker-side
  pieces.

### H6. CFK operator-to-broker traffic is dropped by default-deny NetworkPolicies

* **Symptom**: KRaftController CR shows `cluster-ready=False`,
  `reason=ApplyFailed`, with the message
  `failed to query kRaft controller N for log end offset: ...
  dial tcp <pod-ip>:7777: i/o timeout`. KRaft pods themselves are
  Ready, the StatefulSet shows `readyReplicas: 3`, and
  `currentRevision != updateRevision` so the operator wants to roll
  but `rolling=True, 0/3 pods updated, ignore=false`. Downstream:
  Kafka CR sits at `replicas: 0` with
  `Timeout: request did not complete within requested timeout -
  context deadline exceeded`. No Kafka StatefulSet ever gets
  created. Dependents (SR, Connect, REST, C3) never get applied
  because the pipeline gates on `wait_for_cr_ready kafka`.
* **Root cause**: the namespace carries three Helm/Argo-managed
  NetworkPolicies from the `security` chart
  (RITM0993435 — `allow-from-ingress`, `allow-from-monitoring`,
  `allow-same-namespace`). None of them permit ingress from the
  CFK operator's namespace (`confluent-operator`). The operator's
  reconcile loop calls Jolokia on TCP/7777 on every KRaft pod
  before letting Kafka be reconciled — those packets get
  default-denied by the cluster's NP enforcer. Operator only sees
  `i/o timeout`, can't distinguish the no-route case from a real
  broker problem, and refuses to proceed.
* **Fix**: a fourth NetworkPolicy in the workload namespace —
  `apps/confluent-platform/<env>/network-policy.yaml`,
  `allow-from-confluent-operator` — Ingress-only, scoped to the
  CFK component management ports (7777 Jolokia, 7778 Prometheus,
  7203 JMX, 9074 KRaft, 9071 internal listener, 9092/9094 external
  + CERTONLY, 8081/8082/8083 SR/REST/Connect, 8090 MDS,
  9021 C3). Selector matches the operator namespace via the
  auto-applied `kubernetes.io/metadata.name=confluent-operator`
  label so the operator namespace doesn't have to be retro-labeled.
  Applied by `.azure-pipelines/confluent-platform.yaml` at the top
  of the CR apply phase, conditional on the file existing — so an
  env-by-env rollout works without breaking pipelines for envs
  that haven't adopted the file yet.
* **Why it matters**: this is the failure mode that masquerades as
  a CFK / KRaft / Kafka bug for the first hour of triage. The
  pods look healthy, the Secrets are in place, the CR spec is
  valid, but nothing converges. The signal is in the **CR status
  conditions** and the **`FailedToUpdate` events on the CR** —
  not in pod logs (the affected pods aren't even running yet) and
  not in the cert-manager / Secrets state. `diagnostics.yaml`'s
  per-CR events block and the NetworkPolicy dump section together
  catch it in one pass. When promoting to uat/qa/stg/prd/dr,
  drop the same `network-policy.yaml` into each env's folder —
  the security chart's three default NPs are identical across
  envs, so the same operator-namespace gap exists in all of them.

### A18. `spec.fips.enabled: true` on KRaftController flips the operator into a stricter config validator that demands explicit listener SSL config

* **Symptom**: KRaftController CR transitions from `cluster-ready=True`
  to `cluster-ready=False ApplyFailed: failed config validation:
  missing value for key listener.name.controller.ssl.keystore.location`
  the moment `spec.fips.enabled: true` is added to the CR. All 3
  controller pods stay 1/1 Running and the KRaft quorum stays formed
  — the failure is purely at the operator's reconcile / validate step.
  `wait_for_cr_ready kraftcontroller` then times out and the pipeline
  never gets to applying the Kafka CR.
* **Root cause**: the FIPS-attested code path in CFK 3.2.0 uses a
  stricter server-properties validator than the default. The default
  validator is satisfied by `spec.tls.secretRef` + a `listeners.*.tls.
  enabled: true` because it lets the init container auto-render the
  `listener.name.<name>.ssl.{keystore,truststore}.{location,password,
  type}` keys at startup. The FIPS-attested validator runs *before*
  init-container render and so finds those keys missing.
* **Fix**: don't put `spec.fips.enabled: true` on the KRaftController
  CR. The Kafka CR is the one the FIPS-mode operator actually rejects
  without the attestation (runbook A17); KRaftController reaches
  `cluster-ready=True` without it because the operator's outbound
  HTTP-client step on the KRaft reconcile path is narrower than on
  the broker path and the FIPS-on-operator check doesn't fire for it.
  Net rule: **set `spec.fips.enabled: true` on Kafka, leave it off
  KRaftController.** SchemaRegistry has no `spec.fips` field at all
  in v1beta1 (verified by `oc explain schemaregistry.spec`).
* **Why it matters**: the defensive "keep both CRs consistent"
  instinct is wrong here. Adding `fips.enabled` to a CR that doesn't
  need it actively breaks it, because that field doesn't just toggle
  an attestation flag — it switches the operator's whole validation
  pipeline for that CR. If you ever do need it on KRaft for some
  future hardening reason, the workaround is to also pre-render the
  six explicit SSL keys into `configOverrides.server`:
  `listener.name.controller.ssl.{keystore,truststore}.{location,
  password,type}` pointed at `/mnt/sslcerts/{keystore,truststore}.p12`
  with the password sourced from `${file:/mnt/sslcerts/
  jksPassword.txt:jksPassword}` — same shape the VM controller's
  `server.properties` uses today.

### A19. FIPS-strict validator extends to every internal client, not just listeners — `metric.reporters=` empty is NOT enough

* **Symptom**: with A18 cleared (controller is `cluster-ready=True`) and
  `spec.fips.enabled: true` on the Kafka CR (required to clear the
  operator's "TLS not Enabled in Application when FIPS mode is true in
  Operator" message — A17), the Kafka CR moves from one rejection to
  the next: `cluster-ready=False ApplyFailed: failed config validation:
  missing value for key confluent.metrics.reporter.ssl.truststore.
  location`. Set `metric.reporters=` (empty) in `configOverrides.server`
  to disable ConfluentMetricsReporter at runtime — the validator still
  complains about the same key. The CR's `status.observedGeneration`
  stays unset because the rejection is at admission, before the
  operator writes a normal status.
* **Root cause**: the same FIPS-attested validation pipeline behind A18
  applies on the broker path too, and it doesn't just enforce listener
  SSL — it enforces SSL config for *every* known internal client
  (`confluent.metrics.reporter`, presumably also Self-Balancer, the
  security event logger, the consumer-lag emitter, …). It gates on the
  keys being *set*, not on whether the client is enabled. Turning the
  client off via its `*.enable=false` flag does not satisfy the
  validator — the validator runs BEFORE the operator decides whether
  to wire the client in.
* **Fix (Phase 1)**: pre-render the SSL truststore *and* keystore
  keys for each internal client the validator complains about, mount
  the material at FCB-standard `/var/ssl/...` paths, and emit JKS via
  cert-manager rather than relying on the CFK init container's
  PKCS12 render. The shape that ended up working (matches the FCB
  Flink ui-tls pattern):
  1. Add a `keystores.jks` block to the Kafka broker's cert-manager
     `Certificate` so cert-manager writes `keystore.jks` +
     `truststore.jks` into the `kafka-tls` Secret alongside
     `tls.crt` / `tls.key` / `ca.crt`. Encrypt with `changeit` via a
     small `kafka-keystore-pw` `Secret` colocated in the same
     manifest.
  2. In the Kafka CR's `spec.mountedVolumes`, mount two volumes —
     `fcb-trust-bundle` (the trust-manager ConfigMap, via
     `configMap.items` for a deterministic single-file mount) at
     `/var/ssl/truststore`, and the `kafka-tls` Secret's
     `keystore.jks` + `truststore.jks` at `/var/ssl/kafka`.
  3. Point the JVM-wide truststore JVM args at
     `/var/ssl/truststore/bundle.jks` (broad outbound trust — same
     bundle Flink uses for the S3 SDK and other JVM-default-truststore
     consumers).
  4. Pre-render the *full* six-key SSL block for every internal
     client the validator complains about (truststore *and*
     keystore — not just truststore; the FIPS-strict validator gates
     on both):
     `confluent.metrics.reporter.ssl.truststore.{location,password,
     type}=/var/ssl/kafka/truststore.jks,changeit,JKS` and the
     matching `.keystore.*` triple at `/var/ssl/kafka/keystore.jks`.
  5. Disable Self-Balancer for Phase 1
     (`confluent.balancer.enable=false`); the balancer is a SASL_SSL
     client too and is the validator's next target after the metrics
     reporter is satisfied.
  Earlier iterations that **did not** clear the validator and are
  preserved here as negative results:
  * `metric.reporters=` empty alone (commit `3724127`) — validator
    gates on key existence, not runtime wiring.
  * Pre-rendering the truststore keys against
    `/mnt/sslcerts/truststore.p12` (commit `562d196`, reverted at
    `aafd80d`) — path is real at runtime once the init container has
    run, but is NOT declared in `spec.mountedVolumes` and reads as a
    "phantom mount" to anyone reviewing the manifest, which is the
    reason the revert call landed.
  * Pre-rendering ONLY the truststore triple against
    `/mnt/sslcerts/fcb-trust-bundle/bundle.jks` with
    `metric.reporters=` empty (commit `8ce409c`) — same error.
  * Same six-key truststore+keystore block under FCB-standard
    `/var/ssl/...` paths but still with `metric.reporters=` empty
    (commit `502cea5`) — same error. Proves the
    `metric.reporters=<empty>` value is itself the validator's
    trigger; the validator runs the existence check against the
    cp-server *default* reporter list (TelemetryReporter +
    ConfluentMetricsReporter), not against the override.
  Iteration under test (this commit): keep all the
  `/var/ssl` mounts and the six-key SSL block but ALSO set
  `metric.reporters=io.confluent.telemetry.reporter.TelemetryReporter,
  io.confluent.metrics.reporter.ConfluentMetricsReporter` and supply
  the full SASL_SSL stack (`bootstrap.servers`, `security.protocol`,
  `sasl.mechanism`, `sasl.jaas.config`, `topic.replicas`,
  `support.metrics.enable=false`) — 1:1 with the VM brokers'
  `server.properties` under `apps/confluent-platform/cp-confluent/
  dev/`. The validator passes because every key on its dependency
  graph for the cp-server default reporter list is present.
* **Why it matters**: this turns "telemetry off for Phase 1" from a
  one-line toggle into a full TLS-material-provisioning exercise.
  The pattern that works is the same one the FCB Flink ui-tls cert
  established — cert-manager-emitted JKS material at
  `/var/ssl/<component>/` plus the trust bundle at
  `/var/ssl/truststore/`, with full keystore+truststore SSL configs
  for every internal client the FIPS-strict validator demands. When
  Phase 2 re-enables each client at runtime, the SSL block stays in
  place and only the SASL/bootstrap/jaas configs get added on top.

### A20. CFK 3.2.0 FIPS-mode docs: BCFKS is required, not JKS — and the CR field path is `spec.tls.fips.enabled`

* **Symptom**: after iterations 1–4 of pre-rendering
  `confluent.metrics.reporter.ssl.*` keys against JKS material at
  `/var/ssl/kafka/` and `/mnt/sslcerts/fcb-trust-bundle/` (A19), the
  validator continues to reject with `missing value for key
  confluent.metrics.reporter.ssl.truststore.location` even though
  the key is present in `spec.configOverrides.server` on the live CR.
* **Root cause** (per
  https://docs.confluent.io/operator/current/co-security-compliance.html#deploy-cp-in-the-fips-mode):
  Two doc-level facts our iterations didn't account for.
  1. **FIPS requires BCFKS keystores, not JKS.** The docs are
     explicit: *"Confluent Server (Confluent Kafka), KRaft, Schema
     Registry, Connect, and ksqlDB require FIPS-compliant Java
     KeyStore type, Bouncy Castle"*. The component Secret must
     contain `keystore.bcfks`, `truststore.bcfks`,
     `keystore.jks`, `truststore.jks`, `jksPassword.txt`. JKS is
     only the legacy fallback for the Kafka↔ZooKeeper leg (we're on
     KRaft so don't need it).
  2. **The CR field is `spec.tls.fips.enabled`, not
     `spec.fips.enabled`.** The top-level path we'd been using
     since A17 may have been silent-stripped per the v1beta1
     pattern (project memory `project_cfk_v1beta1_silent_strips`);
     the documented path is nested under `spec.tls`.
* **Fix**:
  1. Set BOTH `spec.fips.enabled: true` (top-level, our pre-docs
     placement) AND `spec.tls.fips.enabled: true` (nested under
     tls, the documented path) — belt-and-suspenders so whichever
     the operator reads, the attestation is present. Once we
     confirm which one is canonical we can drop the other.
  2. The kafka-tls Secret must contain BCFKS material in addition
     to whatever cert-manager produces. cert-manager 1.x has no
     native BCFKS support — `spec.keystores` only emits `jks` and
     `pkcs12`. Two paths to BCFKS:
     * In-cluster conversion Job: read tls.crt/tls.key/ca.crt from
       the cert-manager-issued Secret, run the BouncyCastle CLI
       (`bc-fips` jar + keytool) to emit `keystore.bcfks` +
       `truststore.bcfks`, patch the Secret. Runs once per cert
       rotation. Right shape for stg/prd.
     * Disable operator-level `fipsmode=true` for dev only (Helm
       chart value); keep `spec.tls.fips.enabled: true` on the CR
       so manifests stay consistent across envs. Loses the
       operator-attested FIPS validation path for dev; broker
       runtime FIPS posture is governed by the JVM bootclasspath
       and the cp-server image, both unchanged.
* **Why it matters**: A19's "JKS at /var/ssl/kafka/ is enough"
  assumption was wrong — the FIPS validator's truststore
  type/location keys are expected to point at BCFKS files, not
  JKS files. The "missing value for key …truststore.location"
  message reads as "missing the value" but more accurately
  means "missing a value that resolves to a BCFKS truststore at
  a path the validator recognizes". The validator's behavior is
  documented as supported in CFK 3.2.0+ (not preview), which
  means the gap is on our side: we either provide BCFKS material
  or we relax the operator's fipsmode requirement for dev. There
  is no third path from CR-side `configOverrides` alone.
* **Follow-up after the operator-side helm rollback** (Rick
  disabled `fipsmode=true` for dev on 2026-06-30): the next
  install-or-update run STILL hit the same validator error.
  Root cause of the post-rollback failure: the Kafka CR still
  carried `spec.tls.fips.enabled: true` (iteration 5b
  manifest), and **that CR-level toggle alone re-triggers the
  FIPS-strict validator on a per-CR basis** independent of the
  operator's `fipsmode` flag. Per the docs, `spec.tls.fips.
  enabled: true` opts THIS CR into FIPS-attested processing
  even when the operator process itself is running with
  `--fipsmode=false`. So both knobs have to be off for dev to
  run with normal validation: (a) operator-level
  `fipsmode=false` (Rick's helm change), and (b) CR-level
  `spec.tls.fips.enabled` removed entirely (drop the field;
  setting `false` may not be schema-valid). Net rule for Phase 1
  dev: **neither toggle is set**. For stg/prd both come back
  once the BCFKS conversion pipeline lands.

### A21. Do NOT add a `keystores.jks` block to a cert-manager Certificate whose Secret feeds `spec.tls.secretRef` — it breaks the CFK init container's password render

* **Symptom**: Kafka CR cluster-ready clears (validator passes,
  reconcile starts, broker pod scheduled and `Running`), but the
  broker process exits during startup with `Fatal error during
  broker startup. Prepare to shutdown`. The stack trace shows
  `KafkaRaftManager.buildNetworkClient → SaslChannelBuilder.
  configure → DefaultSslEngineFactory.createKeystore` failing on:
  ```
  Failed to load SSL keystore /mnt/sslcerts/keystore.jks of type JKS
  Caused by: java.io.IOException: Keystore was tampered with,
    or password was incorrect
  Caused by: java.security.UnrecoverableKeyException:
    Password verification failed
  ```
* **Root cause**: A19's "add a `keystores.jks` block to the
  kafka-tls Certificate so cert-manager writes
  `keystore.jks` + `truststore.jks` directly into the Secret"
  trick was scaffolding for the FIPS-strict validator. It breaks
  the CFK init container's normal contract — *the init container
  is responsible for rendering JKS+PKCS12 from PEM at startup,
  and writing a matching `/mnt/sslcerts/jksPassword.txt`*. When
  it sees `keystore.jks` already present in the kafka-tls Secret
  (because cert-manager wrote one with the password from
  `kafka-keystore-pw`), the init container's render disagrees with
  the file: `/mnt/sslcerts/keystore.jks` ends up encrypted with
  one password (ours: `changeit`) while
  `/mnt/sslcerts/jksPassword.txt` carries the init container's
  separate auto-generated password. The broker reads the password
  from `jksPassword.txt` and applies it to the keystore, the two
  don't match, broker fails fatally during startup.
* **Fix**: revert the `keystores.jks` overlay entirely. Certificate
  emits PEM only (`tls.crt` / `tls.key` / `ca.crt`); init container
  produces the JKS material at `/mnt/sslcerts/` with consistent
  passwords. Also drop any `spec.mountedVolumes` that mount
  `keystore.jks` / `truststore.jks` from the kafka-tls Secret
  (those keys won't exist anymore). Internal clients that need
  SSL config (e.g. the metrics reporter) inherit the JVM-wide
  trustStore set in `configOverrides.jvm` — for SASL_SSL listeners
  the client also doesn't need a keystore.
* **Why it matters**: the FIPS-validator workaround chain in
  A19/A20 layered TLS material into the Secret in a way that
  conflicts with CFK's normal lifecycle. Once `fipsmode=true` is
  off at the operator and `spec.tls.fips.enabled` is removed from
  the CR, REVERT the cert-manager `keystores.jks` block in the
  same pass — otherwise the broker passes admission and then
  dies at startup on its own pre-baked keystore. Rule of thumb:
  **if `spec.tls.secretRef` points at a cert-manager Secret, that
  Secret must contain ONLY the PEM keys cert-manager normally
  produces; let the CFK init container generate any JKS / PKCS12
  material itself.**

### A22. Phase 2 layering — Okta-backed MDS + RBAC on top of the Phase 1 PLAIN/SASL_SSL baseline

* **Symptom (the trigger that moves us past Phase 1)**: SR pod
  successfully completes the SASL/PLAIN handshake against the
  broker on `:9071` but dies during init with
  `TopicAuthorizationException: Authorization failed` when it
  tries to create `_schemas`. cp-server's
  `ConfluentServerAuthorizer` is active by default in KRaft mode;
  with only `User:admin` in `super.users`, every other
  authenticated identity (`schemaregistry`, `kafkaconnect`,
  `kafkarest`, `controlcenter`) hits deny.
* **Two paths to clear it**:
  1. **Phase 1.5** — broaden `super.users` to include each
     component user. Single-line change in `kafka.yaml`. Doesn't
     introduce MDS; loses the per-component privilege separation.
     Acceptable for dev smoke-tests, not for the long-term shape.
  2. **Phase 2** — wire Okta-backed MDS on the broker + RBAC
     rolebindings per component. The proper FCB-grade end state.
* **Phase 2 shape**:
  * **Kafka CR**: `spec.services.mds` with `tokenKeyPair:
    mds-token-keypair` and `provider.type: oauth` pointing at
    Okta (issuer/jwks/token URIs + audience + groupsClaim from
    `myapps.firstcitizens.com`), using `oauth-mds-rest` Secret
    for the MDS service's own OIDC client credentials. Plus
    `spec.authorization.type: rbac` with `superUsers: [User:admin]`
    only — the other component users do NOT go in super.users in
    Phase 2; their access comes from rolebindings.
  * **SR / Connect / KafkaRest CRs**: `spec.dependencies.mds`
    with `endpoint: https://kafka.dah-flink-dev.svc.cluster.local:8090`
    and `authentication.type: oauth` using the per-component
    `oauth-<name>` Secret (populated by the pipeline from
    `<env>-oauth-<name>-client-id` / `client-secret` variables).
    Plus `spec.authentication.type: oauth` (Okta JWT auth on the
    component's REST API) and `spec.authorization.type: rbac`
    with `superUsers: [User:admin]`. The Kafka listener auth
    STAYS PLAIN — we're adding authz, not changing authn.
  * **`rolebindings.yaml`**: `ConfluentRolebinding` CRs per
    component, each with `kafkaRestClassRef.name: default`
    (transitively resolves cluster scope through KafkaRestClass
    → Kafka CR → MDS). SR gets `ResourceOwner` on Topic `_schemas`
    (literal) + Group `schema-registry` (literal). Connect gets
    `ResourceOwner` on its three internal topics
    (`connect-cluster-{configs,offsets,status}` literal) + Group
    `connect-cluster` (literal). KafkaRest gets `SystemAdmin` at
    cluster scope (acts as generic proxy; tighten in a follow-up
    once we know which topics REST clients actually exercise).
  * **Pipeline**: rolebindings.yaml applied AFTER Kafka cluster-ready
    and BEFORE the SR / Connect / KafkaRest CRs apply, so each
    component's user has the access it needs at first boot. The
    apply is idempotent (re-running merges into existing
    rolebindings); operator retries internally if MDS isn't yet
    serving.
* **Silent-strip caveat (resolved by CRD validation)**: memory
  `project_cfk_v1beta1_silent_strips` historically flagged
  `spec.services.mds:` as silent-stripped at admission. On the
  current operator build the CRD explicitly validates and
  REJECTS bad shapes with a real error (e.g., applying with
  `provider.oauth.configuration:` singular returned
  `spec.services.mds.provider.oauth.configurations: Required
  value`). Better than silent-strip — we get a clean failure
  with a path. After Phase 2 admission succeeds, still worth
  one verification pass with
  `oc get kafka kafka -o jsonpath='{.spec.services.mds}{"\n"}'`
  to confirm the block round-tripped.
* **Provider-vs-consumer field-name gotcha**: the Kafka CRD's
  **provider-side** oauth block uses **`configurations`
  (plural)** under `spec.services.mds.provider.oauth.
  configurations`. The **consumer-side** oauth blocks on SR /
  Connect / KafkaRest / KSqlDB / ControlCenter — under
  `spec.dependencies.{mds,schemaRegistry,kafka}.authentication.
  oauth.configuration` and `spec.authentication.oauth.
  configuration` — use **`configuration` (singular)**. Don't
  copy-paste blindly between them.
* **Every TLS block the operator's reconcile exercises needs an
  explicit `secretRef` or `directoryPathInContainer`** —
  `enabled: true` alone isn't sufficient anywhere the operator
  acts as a TLS *client*. Symptom is identical across all of
  them: `ApplyFailed: tls client secretRef or
  directoryPathInContainer must be set in kafka spec` while
  broker pods stay up (`statefulset-available=True`). The error
  message is generic (just says "in kafka spec") so attribute
  by elimination. Known blocks that need this for our Phase 2
  shape:
  * `spec.services.mds.tls` (Kafka CR) → `secretRef: kafka-tls`
  * `spec.dependencies.kafkaRest.tls` (Kafka CR) →
    `secretRef: kafka-tls`
  * `spec.dependencies.kafka.tls` (SR / Connect / KafkaRest CRs)
    → `secretRef: kafka-tls`
  All reuse `kafka-tls` because the MDS / kafkaRest / Kafka
  listener endpoints are all served by the broker pods, sharing
  the same cert chain.
* **`sasl-plain-internal` per-client-key naming is derived
  from the CRD KIND, not the CR name or a friendly component
  name**. The operator's admission validator demands
  `<lowercase-kind>-client-plain.txt` in the Secret when a
  component's `dependencies.kafka.authentication.type: plain`
  points at `sasl-plain-internal`. Concrete mapping:
  * `SchemaRegistry` → `schemaregistry-client-plain.txt`
  * `Connect` → `connect-client-plain.txt` (**not**
    `kafkaconnect-client-plain.txt`)
  * `KafkaRestProxy` → `kafkarestproxy-client-plain.txt`
    (**not** `kafkarest-client-plain.txt`)
  * `ControlCenter` → `controlcenter-client-plain.txt`
  Failing this returns admission `ApplyFailed: required at
  least one of the keys [<kind>-client-plain.txt plain.txt] in
  secretRef [sasl-plain-internal] for auth type [plain]` on
  Connect / KafkaRest / etc. The Secret is constructed by the
  `install-or-update` pipeline's Secret step in
  `.azure-pipelines/confluent-platform.yaml`.
* **Phase 2 side-effect: CFK auto-rewires consumer-side
  `authentication.type: plain` to `oauthbearer` when MDS is
  enabled**. Observed in SR's pod log
  (`schemaregistry-0-schemaregistry.log` 2026-06-30T23:30):
  even though `dependencies.kafka.authentication.type: plain`
  was on the CR, SR's effective config used SASL/OAUTHBEARER
  (login-thread name carried the Okta client id) and the
  AdminClient dialed `:9073` instead of the configured `:9071`.
  Consequence: SR times out — `Failed to get Kafka cluster ID
  Caused by: TimeoutException` — because our
  `spec.listeners` on the Kafka CR only declares
  `internal:9071` + `external:9092` and there's no `:9073`
  listener actually open on the brokers. Fix on our side:
  add a TOKEN listener (`type: oauthbearer` + Okta
  `oauthSettings`) at `:9073` under a custom listener on
  the Kafka CR. Until that lands, MDS-tokenized clients can't
  reach the broker.
* **`spec.dependencies.kafkaRest.authentication` is also
  required on the Kafka CR once `spec.services.mds` is set**.
  Symptom on first apply: `cluster-ready=False ApplyFailed:
  .spec.dependencies.kafkaRest.authentication must be
  configured` — broker pods come up fine (`statefulset-
  available=True`, `resources-ready=True`) but the operator
  refuses to mark the CR ready because the RBAC-management path
  needs to talk to the broker's embedded kafkaRest endpoint at
  `:8090` for ConfluentRolebinding reconciliation. Fix: add a
  `dependencies.kafkaRest` block alongside `dependencies.
  kRaftController`. For OAuth use `authentication.type:
  oauthbearer` with `oauthbearer.secretRef: oauth-broker` plus
  `oauthSettings` (FLAT fields — *not* nested under
  `configuration` / `configurations`; the dependency-side oauth
  shape uses flat-field-`oauthSettings` while the provider-side
  uses nested-`configurations` plural). `endpoint:
  https://kafka.dah-flink-dev.svc.cluster.local:8090` and
  `tls.enabled: true`.
* **Why it matters**: Phase 1.5 (broadened super.users) is a
  hack that works for dev smoke-tests but explicitly violates
  least-privilege for stg/prd. Phase 2 establishes the proper
  shape — Okta is the identity source, MDS is the
  authorization-decision-point, ConfluentRolebinding CRs are the
  declarative grants. The whole layout is GitOps-driven and
  reproducible across envs as the BCFKS / FIPS gear comes back
  online.
* **Status (2026-07-01) — RESOLVED**: closed by the same
  commit that closes A23 (`23a51c6`). Five FCB CFK components
  reached `cluster-ready=True`; ConfluentRolebindings for the
  four component principals (SR, Connect, KafkaRest,
  Kafka-broker) plus the human principal
  `aadmassu@psyncopate.com` were created without error.
  Follow-up: A24 for the ControlCenter shape addendum.

### A23. CFK 3.2 MDS/RBAC requires OAUTH listeners, not a magic "TOKEN listener" — the Psyncopate reference pattern

* **Symptom**: after commit `0a730d8` set `spec.services.mds` + `spec.authorization.type: rbac` on the Kafka CR with PLAIN/SASL_SSL listeners, SR crash-looped with `Failed to get Kafka cluster ID` timing out at `kafka.dah-flink-dev.svc.cluster.local:9073`; operator errored 100+ times with `kafka rest API request failed: Not Found (0)`. Kafka CR STATUS reported `listeners.token: {port: 9073, authenticationType: oauthbearer}` but the broker's rendered `/opt/confluentinc/etc/kafka/kafka.properties` (6446 bytes, path from `-Dkafka.config=…` on the JVM cmdline) contained only Phase 1 listeners: `listeners=EXTERNAL://:9092,INTERNAL://:9071,REPLICATION://:9072`, `listener.security.protocol.map=CONTROLLER:SASL_SSL,EXTERNAL:SASL_SSL,INTERNAL:SASL_SSL,REPLICATION:SASL_SSL`, `listener.name.*.sasl.enabled.mechanisms=PLAIN`. No TOKEN listener, no OAUTHBEARER anywhere. Reproduced via `diagnostics.yaml`'s revised broker-config probe (commit `9c79e37`) and via Splunk Q5 `KafkaConfig values:` dump.
* **Root cause**: CFK 3.2 doesn't inject a hidden TOKEN listener when `spec.services.mds` is enabled — the operator only emits the LISTENERS that spec.listeners declares. `status.listeners.token` on the CR is *aspirational operator state*, not observed reality. **For MDS/RBAC to work, the primary listeners themselves have to speak OAUTHBEARER.** Setting `spec.services.mds` alone (with PLAIN listeners) is a half-built shape that admits, reports "cluster-ready=True", but has no way for OAuth-tokenized clients to actually reach a Kafka listener. Rolebindings then fail because the operator's kafkaRest calls to the broker's MDS endpoint go through paths that expect OAUTHBEARER traffic at :9073, which doesn't exist.
* **Fix**: rewrite the whole confluent-platform manifest set to match the **Psyncopate-Technologies/openshift-cfk-gitops** dev reference (`env/dev/confluent-platform/*.yaml`), which is a proven-working Phase 2 layout. The five FCB-side rewrites (commit `<HEAD>`):
  * **`kafka.yaml`** — `spec.listeners.internal.authentication.type=oauth` + `spec.listeners.external.authentication.type=oauth` + `spec.dependencies.kRaftController.controllerListener.authentication.type=oauth` all pointed at Okta (`myapps.firstcitizens.com/oauth2/default` per the VM `d11547varc-*-server.properties` files). No PLAIN. `spec.services.mds.provider.oauth.configurations` + `spec.services.mds.provider.sso` (for browser SSO via C3), no `spec.services.mds.authentication`. `spec.metricReporter` as a first-class field (NOT configOverrides `confluent.metrics.reporter.*` keys). `spec.authorization.type=rbac` with `superUsers: [User:0oa1owhtq2olDZWwf358]` — Okta client id of the broker (per VM `super.users`). `configOverrides.server` has broker-as-CLIENT OAUTHBEARER defaults (`security.protocol=SASL_SSL`, `sasl.mechanism=OAUTHBEARER`, `sasl.oauthbearer.{token,jwks,expected.issuer,scope}`) plus per-prefix blocks for `confluent.license.*` and `confluent.kafkarest.*` (the broker's own internal clients now speak OAUTHBEARER since the listeners require it).
  * **`kraftcontroller.yaml`** — controller listener flipped from `type: plain` to `type: oauth`. Same Okta config as Kafka. `spec.authorization.type=rbac` matching Kafka.
  * **`schemaregistry.yaml`** / **`connect.yaml`** / **`kafkarest.yaml`** — `dependencies.kafka.authentication.type: oauth` (not `plain`) using the per-component `oauth-<name>` Secret. `dependencies.mds` unchanged (already OAUTH). `dependencies.schemaRegistry.tls.secretRef=schemaregistry-tls`. `spec.authorization.type=rbac`; no superUsers list — everything through rolebindings.
  * **`rolebindings.yaml`** — principal names changed from friendly names (`schemaregistry`, `kafkaconnect`, `kafkarest`) to Okta client IDs from the VM properties files: SR `0oa1owiage2MyoHdt358`, Connect `0oa1owi0yntGMBvPS358`, KafkaRest `0oa1owi3wkxJS3b3b358`. Plus per-user rolebindings for humans via email principals (SSO uses `subClaimName: email`).
  * **`kafkarestclass.yaml`** — added `spec.kafkaRest.authentication.oauth` block per the Psyncopate `rbac/kafkarestclass.yaml` shape. The operator uses this to figure out how to auth when applying ConfluentRolebindings via the broker's kafkaRest API.
  * **Pipeline** — added a new `oauth-mds-sso` Secret. `oauth-mds-rest` was the MDS server-side OAuth client (already existed); `oauth-mds-sso` is a distinct OIDC client used by MDS for browser SSO from `spec.services.mds.provider.sso.clientCredentials.secretRef`. Two new pipeline vars needed: `<env>-oauth-mds-sso-client-id` and `<env>-oauth-mds-sso-client-secret`.
* **Why it matters**: the "TOKEN listener at :9073" concept was a wild goose chase — it doesn't exist as a first-class thing in CFK 3.2. The operator STATUS field is misleading. Ground truth is the broker's rendered `/opt/confluentinc/etc/kafka/kafka.properties` (via the diagnostics probe at commit `9c79e37` or Splunk Q5 in `pump.txt`). The proven Phase 2 pattern is **OAUTHBEARER on every listener** — same across internal/external/controller — with matching broker-as-client OAUTHBEARER config so the JVM's own internal clients participate correctly. The Psyncopate reference cluster runs against Okta (`integrator-9299379.okta.com`) in exactly this shape; FCB's cluster now runs against FCB Okta (`myapps.firstcitizens.com`) in the same shape, adapted only in Okta URLs / client IDs / secret names / FCB-specific Gatekeeper labels.
* **Status (2026-07-01) — RESOLVED**: after commit `23a51c6` added `spec.services.mds.impersonation.admins` (the four component Okta client IDs) and the inter-broker OAUTHBEARER JAAS override with `publicKeyPath=/mnt/secrets/mds-token/mdsPublicKey.pem`, the Diagnostics dump at 20:28:22Z reported `cluster-ready=True` on every CFK component (kafka, kraftcontroller, schemaregistry, connect, kafkarestproxy), all kafka pods listening on the full 9073/8090/9071/9072 port set, and every ConfluentRolebinding produced `Normal SuccessfulCreate` events (no more `Not Found (0)`). The two lessons buried in the fix that weren't obvious from the Psyncopate reference alone: (1) `impersonation.admins` is required for the operator's own rolebinding-reconcile client to act on behalf of others through MDS; (2) inter-broker traffic must use MDS-signed tokens (not Okta tokens) or every hop stalls trying to re-fetch Okta credentials — the JAAS override with `publicKeyPath` tells the broker to sign+verify inter-broker OAUTHBEARER via the MDS keypair.

### A24. ControlCenter CR shape gotchas — top-level UI auth is `mtls+requested`, dep-side Kafka is flat like SR/Connect/KafkaRest

* **Symptom**: pre-Phase-2 `controlcenter.yaml` (last touched 2026-05, before the OAuth listener rewrite) mixed shapes — `dependencies.kafka.authentication` used the very-old flat `type: oauthbearer` + `oauthbearer.secretRef` + `oauthSettings` form, while `dependencies.{schemaRegistry,connect,mds}.authentication` used the newer nested `type: oauth` + `oauth.secretRef` + `oauth.configuration` form; `authorization.superUsers: [User:admin]` pointed at a principal that doesn't exist; TLS on every dep was `enabled: true` with no `secretRef`. Bringing C3 up against this shape at Phase 2 would have looped through the same wave of admission + reconcile errors we chased on kafka.yaml / kafkarest deps.
* **Root cause**: two-part.
  * (a) Dep-side auth shape rule (per commits `eb8e0e1` / `98747e0` / `de7b0b7`, live CRD wins over vendored 3.1.x reference): **`dependencies.kafka.authentication` uses flat `type: oauth + jaasConfig.secretRef + oauthSettings`** (client-to-broker uses raw JAAS/SASL under the hood, same shape as SR/Connect/KafkaRest); **`dependencies.{schemaRegistry,connect,mds}.authentication` uses nested `type: oauth + oauth.{secretRef, configuration}`** (HTTP APIs use a different auth handler). Mixing them per-block breaks admission on some, silently strips on others.
  * (b) `ControlCenter` CRD top-level `authentication.type` enum is `[basic|ldap|mtls]` — **`oauth` is not a valid type** at that field (unlike Kafka / SR / Connect / KafkaRest whose top-level authentication does allow oauth). CFK's answer is `authentication.type: mtls` with `sslClientAuthentication: requested` (no client cert forced) plus `dependencies.mds.ssoProtocol: oidc` — the OIDC redirect through MDS delivers the actual user auth. Confirmed against vendored `platform.confluent.io_controlcenters.yaml` L54-124.
* **Fix (commit `<HEAD>`)**: rewrite `apps/confluent-platform/dev/controlcenter.yaml` for Phase 2:
  * `dependencies.kafka.authentication` → flat `type: oauth` + `jaasConfig.secretRef: oauth-controlcenter` + `oauthSettings` (with timeout tuning `loginConnectTimeoutMs=10000` / `loginReadTimeoutMs=30000` / etc from Confluent example). `bootstrapEndpoint` moved to INTERNAL listener at `:9071` (not `:9092`).
  * `dependencies.{schemaRegistry,connect,mds}.authentication` → keep nested `oauth+configuration` shape but add timeout tuning to each `configuration` block.
  * `dependencies.{kafka,schemaRegistry,connect[0],mds}.tls.secretRef` → set explicitly (`kafka-tls`, `schemaregistry-tls`, `connect-tls`, `kafka-tls`). `enabled: true` alone was the exact gap runbook A20 documents.
  * `authorization.superUsers` → **omit** (all access via `ConfluentRolebinding` — matches SR/Connect/KafkaRest).
  * Top-level `authentication` → **keep** `type: mtls` + `sslClientAuthentication: requested` (documented workaround, not fixable at the CR level).
  * `configOverrides.server` gains explicit `confluent.controlcenter.streams.*` and `confluent.monitoring.interceptor.*` OAUTHBEARER prefixes (same pattern kafka.yaml uses for `confluent.license.*` / `confluent.kafkarest.*` — CFK doesn't auto-derive per-prefix from `dependencies.kafka.authentication`). VM property file lines 34-41 and 51-58 confirm both prefixes need `security.protocol=SASL_SSL` + `sasl.mechanism=OAUTHBEARER` + `sasl.oauthbearer.{token,jwks,expected.issuer,scope}`.
  * `spec.services.mds.impersonation.admins` on Kafka CR gains C3's Okta client `User:0oa1ov6h5mwmQTCKI358` (VM `d11547varc-g5w0-control-center.properties` L34, L43). Without it, users logging in via OIDC would 403 the moment C3 tries to act on their behalf against MDS/kafkaRest/etc.
  * `replicas` stays at `0`. Dev quota is tight after Phase 2 (3 kafka + 3 kraftcontroller + SR + KafkaRest + CMF); flip to 1 when quota is confirmed.
* **Why it matters**: C3 is the last of the six CFK component CRs. This entry closes the Phase 2 shape rulebook: **provider-side (Kafka `services.mds.provider`) uses nested `configurations` (plural); dep-side to Kafka broker uses flat `jaasConfig+oauthSettings`; dep-side to HTTP APIs (MDS/SR/Connect) uses nested `oauth.configuration` (singular); ControlCenter top-level auth is `mtls+requested` because the CRD enum forbids oauth there**. Any future component CR added at FCB should copy the pattern from the matching existing CR rather than guessing — SR is the reference for Kafka-facing components, C3 is the reference for anything that needs the mtls+SSO trick, and rolebindings.yaml is the reference for principal naming (always Okta client IDs, not friendly names).

### A25. Do NOT copy `confluent.controlcenter.data.dir=/var/lib/confluent/control-center` from VM property files into a CFK ControlCenter CR — the CFK dataVolume PVC mounts at `/mnt/data/data0`

* **Symptom**: `controlcenter-0` pod entered CrashLoopBackoff immediately on first bring-up (after flipping `replicas: 0 -> 1` at commit `795ade5`). Container startup dumped a Guice `CreationException` at bootstrap: `java.io.IOException: Unable to create parent directories of /var/lib/confluent/control-center/0/kafka-streams` — thrown by `io.confluent.controlcenter.streams.StreamsConfigModule.getStreamsStateDir()` → `com.google.common.io.Files.createParentDirs()`. Pod's uid line in the log: `uid=1001320000(1001320000) gid=0(root) groups=0(root),1001320000` — OpenShift's `restricted-v2` SCC assigned a UID from the namespace range as expected.
* **Root cause**: the C3 CR had `configOverrides.server: [confluent.controlcenter.data.dir=/var/lib/confluent/control-center, ...]` — copied from VM property file `d11547varc-g5w0-control-center.properties` line 12 without checking whether that path is meaningful on CFK. On CFK the `spec.dataVolumeCapacity` PVC is mounted at **`/mnt/data/data0`** (confirmed from `oc describe sts controlcenter` volumeMounts + matches the kafka broker mount path convention). The `/var/lib/confluent/control-center` path is just a directory baked into the `cp-enterprise-control-center-next-gen:2.5.0` image as `root:root` mode `755`; it is NOT a mount point on CFK; the OpenShift UID-range user has no write perms on it. C3 next-gen then tries to create the per-node subdir `/0/kafka-streams` under that path and immediately EACCES-fails. The bug was latent for weeks because the CR sat at `replicas: 0` from creation through the whole FIPS + Phase 2 + rewrite cycle — nothing ever tried to write.
* **Fix**: remove the `confluent.controlcenter.data.dir=...` override line from `configOverrides.server`. CFK's default is `/mnt/data/data0` (the PVC mount path) and the operator-managed init container chown's that path to the pod's UID before the app container starts. Do NOT re-add the override pointing at `/mnt/data/data0` either — omitting the override lets CFK's default kick in consistently across CFK version bumps, and if a future CFK version changes the mount path (unlikely but possible), an override would silently drift.
* **Why it matters**: this is a whole class of VM→CFK misconceptions: **VM CP property files reference filesystem paths that are meaningful in VMs (`/var/lib/confluent/control-center`, `/var/ssl/private/`, etc.) but wrong on CFK**. CFK has its own mount convention (`/mnt/data/data0` for dataVolume, `/mnt/secrets/<secret-name>` for auth Secrets, `/var/ssl/truststore` for the operator-rendered trust bundle if you `mountedVolumes` it there yourself, `/mnt/sslcerts/<tls-secret-name>` for operator-rendered TLS keystores). When porting VM `*.properties` into CFK `configOverrides`, always CHECK each `*.dir` / `*.location` / `*.path` key against the actual pod's `volumeMounts` (via `oc describe sts <name>` or diagnostics probe) and drop it if CFK's default already puts something at the right place. The list of VM-property keys to always vet: `confluent.controlcenter.data.dir`, any `*.ssl.keystore.location`, any `*.ssl.truststore.location`, `public.key.path`, `kafkastore.dir` (SR), `plugin.path` (Connect), `data.dir` (broker), `metric.reporters.dir`.

### A26. `spec.metricReporter` (first-class) does NOT propagate `sasl.oauthbearer.token.endpoint.url` into the `confluent.metrics.reporter.*` prefix — must add explicit `configOverrides.server` keys

* **Symptom**: `kafka-0` pod is `Running` and cluster-ready=True, but the broker log floods with `[WARN] [DynamicMetricsReportersScheduler] ... org.apache.kafka.common.config.ConfigException: The OAuth configuration option sasl.oauthbearer.token.endpoint.url value is required`. Stack trace shows the exception thrown from `DefaultJwtRetriever.configure()` → `OAuthBearerLoginCallbackHandler.configure()` → `SaslChannelBuilder.configure()` called by `ConfluentMetricsReporter.configure(:171)` via `CommonClientConfigs.metricsReporters` from every internal `Admin.create()` / `KafkaConsumer.<init>()` / `KafkaProducer.<init>()` in the broker. Zero broker-side failures — the reporter's own client init fails, gets caught, gets retried on the next Admin/Consumer/Producer instantiation; the broker keeps running and the metrics reporter just silently doesn't report. Volume was ~185 exceptions in ~5 minutes of a fresh broker log.
* **Root cause**: CFK's `spec.metricReporter` first-class block (Psyncopate reference pattern) translates the `authentication.type=oauth` + `jaasConfig` + `oauthSettings` shape into `confluent.metrics.reporter.security.protocol`, `confluent.metrics.reporter.sasl.mechanism`, and `confluent.metrics.reporter.sasl.jaas.config` — but NOT into `confluent.metrics.reporter.sasl.oauthbearer.token.endpoint.url` or the companion `jwks.endpoint.url` / `expected.issuer` / `scope` keys. The reporter reads from the `confluent.metrics.reporter.` prefix only (it does NOT fall back to broker-wide `sasl.oauthbearer.*` defaults for its own client), so those keys have to be set explicitly. Same class of gap that hit us earlier with `confluent.license.*` and `confluent.kafkarest.*` — CFK doesn't auto-propagate every OAuth sub-key into every per-prefix scope; we always have to add explicit overrides for each prefix that needs to speak OAUTHBEARER.
* **Fix (commit `<HEAD>`)**: add six explicit lines to `apps/confluent-platform/dev/kafka.yaml` `configOverrides.server`:
  ```
  - confluent.metrics.reporter.security.protocol=SASL_SSL
  - confluent.metrics.reporter.sasl.mechanism=OAUTHBEARER
  - confluent.metrics.reporter.sasl.oauthbearer.token.endpoint.url=https://myapps.firstcitizens.com/oauth2/default/v1/token
  - confluent.metrics.reporter.sasl.oauthbearer.jwks.endpoint.url=https://myapps.firstcitizens.com/oauth2/default/v1/keys
  - confluent.metrics.reporter.sasl.oauthbearer.expected.issuer=https://myapps.firstcitizens.com/oauth2/default
  - confluent.metrics.reporter.sasl.oauthbearer.scope=11547.DAH(Dev)
  ```
  Kept the `spec.metricReporter` first-class block as-is (bootstrapEndpoint + tls + authentication.jaasConfig) — that block still handles the mechanism/JAAS/security-protocol wiring the operator DOES translate correctly. `sasl.jaas.config` for the metrics reporter isn't added to configOverrides because the operator DOES inject it correctly from `spec.metricReporter.authentication.jaasConfig.secretRef=oauth-broker`. We only need to fill the OAuth-URL gap.
* **Why it matters**: the pattern is now: **any `confluent.<component>.*` prefix that speaks OAUTHBEARER needs its own explicit six-line block in `configOverrides.server`**. So far the confirmed list is `confluent.license.*`, `confluent.kafkarest.*`, `confluent.metrics.reporter.*`, `confluent.controlcenter.streams.*`, `confluent.monitoring.interceptor.*`. If a future entry to `spec.metricReporter` / `spec.telemetryReporter` / `spec.audit` / any new Confluent internal-client prefix appears in the CRD, verify against the broker log after bring-up: if you see `[DynamicMetricsReportersScheduler]` or `[<Component>Handler] ... sasl.oauthbearer.token.endpoint.url value is required`, add the six lines. The reporter's failure mode is silent (broker still cluster-ready), so this bug can hide for weeks — the diagnostics probe should be extended to grep for `sasl.oauthbearer.token.endpoint.url value is required` and flag it.
* **Also seen concurrently, do NOT confuse with this issue**: `[ERROR] [MultiLicenseBrokerHandler RUNNING] ... java.lang.NullPointerException: Cannot invoke "java.util.List.stream()" because "licenses" is null at KafkaRestLicensePolicyEnforcer.onLicenseValidated`. Fires every 30 s on a background license-fetcher thread. This is a **Confluent bug** in `cp-server:8.1.3`'s `MultiLicenseBackgroundFetcher.notifyListeners()` — it calls `onLicenseValidated(licenses)` with `licenses=null`, the listener catches the NPE, broker keeps running, license is still valid via the `cfk-license` Secret path. Cosmetic log noise. Not our fix; wait for CP upgrade.

### A27. CFK operator `KafkaRestClass` discovery to broker `:8090/kafka/v3` times out → new ConfluentRolebindings can't push to MDS → new components crash-loop on ACL denial

* **Symptom**: `controlcenter-0` in CrashLoopBackoff after we flipped `replicas: 0 → 1` at `795ade5`. Container comes up, C3's internal producers (`heartbeat-sender-0`, `c3-command`, `_confluent-controlcenter-*-StreamThread-1-producer`) all fail with `org.apache.kafka.common.errors.ClusterAuthorizationException: Cluster authorization failed`, JVM never gets to opening the Jetty HTTP server on :9021, k8s liveness probe (`dial tcp <pod-ip>:9021: connect: connection refused`) kills the pod, restart loop repeats. Cluster events show every `ConfluentRolebinding` (SR / Connect / KafkaRest / human-user / all `internal-*` / and the new `controlcenter-systemadmin`) stuck at `FailedToDiscover kafkarestclass [default] failed to discovery the kafka cluster endpoint`, plus a recurring `Warning KafkaRestClass default https://kafka.dah-flink-dev.svc.cluster.local:8090/kafka/v3 context deadline exceeded (Client.Timeout exceeded while awaiting headers)`. First observed 2026-06-30T20:26 (~6 min after the initial Phase 2 bring-up), persisted through all pipeline runs since.
* **Root cause**: the CFK operator's Go HTTP client hits `:8090/kafka/v3` (the broker's embedded kafka-rest endpoint, same port as MDS) with OAuth-bearer auth, gets no response within its default `Client.Timeout`, gives up. Result: any **NEW** ConfluentRolebinding submitted after 20:26 on 2026-06-30 never propagates from k8s into the `_confluent-metadata` topic that brokers cache ACLs from. **Existing rolebindings keep working** because their ACLs got into `_confluent-metadata` during the pre-20:26 window and brokers still see them; but any new component or grant added after that point sees `ClusterAuthorizationException` at every operation. Why the endpoint stopped responding is not conclusively known — the diagnostics pipeline can't reach the `confluent-operator` namespace (all `oc get pods/deployments/events` in that namespace return `Forbidden` for the pipeline service account), so we can't confirm operator restarts or read the operator log. Contributing factors visible from Kafka namespace events: at `22:44:44Z` and `22:44:57Z` (during the kafka roll that included the metrics-reporter fix from `d56225e`) the operator's own admission webhook rejected `StatefulSet kafka` pod deletes with `simultaneous kafka pod delete request being processed` and `ValidatingAdmissionWebhook failed to complete validation in 13s` — indicating operator-side stress; concurrent kafka rolling + controlcenter reconcile likely piled up.
* **Fix (commit `<HEAD>` — WORKAROUND, not root-cause fix)**: add all four component Okta client IDs (`0oa1owiage2MyoHdt358` SR, `0oa1owi0yntGMBvPS358` Connect, `0oa1owi3wkxJS3b3b358` KafkaRest, `0oa1ov6h5mwmQTCKI358` C3) to `apps/confluent-platform/dev/kafka.yaml` `spec.authorization.superUsers`, alongside the broker's own principal (`0oa1owhtq2olDZWwf358`). Brokers evaluate `super.users` before consulting the ACL cache from `_confluent-metadata`, so each component's principal short-circuits the RBAC check and gets full access — regardless of whether the operator ever manages to push its rolebinding to MDS, and regardless of whether the currently-cached ACLs in `_confluent-metadata` survive future broker restarts / topic-compaction / partition-reassignment events. SR / Connect / KafkaRest were working via cached ACLs from the pre-20:26 window; adding them to `super.users` too is belt-and-suspenders insurance so a future broker restart doesn't silently break them the same way it broke C3. Left every ConfluentRolebinding in `rolebindings.yaml` so they propagate the correct way (via MDS) once discovery is resolved; also added `loginConnectTimeoutMs=10000` / `loginReadTimeoutMs=30000` / etc. to `kafkarestclass.yaml` (the only Phase 2 OAuth block that was missing the timeouts) — unlikely to fix the Go HTTP client's outer timeout by itself, but removes one variable when we investigate root cause.
* **Why it matters — this is a WORKAROUND**: `super.users` is stronger than the SystemAdmin / ResourceOwner rolebindings we designed for each component; it bypasses MDS RBAC entirely, which is not the Phase 2 intent (Phase 2 is Okta identity + MDS decisions + declarative rolebindings). Every subsequent new component or new human user we add will hit the same wall until the discovery issue is fixed — human user grants CANNOT be worked around via `super.users` (would give all humans full cluster access), so any per-human-user rolebinding remains blocked. **Track this as an open bug**. Follow-up work required: (a) extend the diagnostics pipeline service account with `get/list` on `pods/events/deployments/services/endpoints` in the `confluent-operator` namespace so we can actually SEE the operator's log next time; (b) once operator log is accessible, capture what the operator sends on `POST/GET https://kafka.dah-flink-dev.svc.cluster.local:8090/kafka/v3` and what response it does or doesn't get; (c) once we know why it's timing out, either tune the operator's client timeout via env var, adjust `spec.dependencies.kafkaRest.authentication` on Kafka CR, fix a broker-side kafka-rest binding, or open a Confluent support ticket. Revert all four component principals out of `super.users` and re-verify the rolebinding path once the root cause is fixed.
* **Update (2026-07-01, post-wipe)**: performed the full wipe (uninstall + wipePVCs) and re-installed from a fresh baseline (commit `d56225e`+). The `:8090/kafka/v3` discovery timeout **RECURRED** on the fresh cluster within minutes of components coming up. That rules out "accumulated stale state" as the cause — this is either an operator-side bug or a network-side issue that persists across clean reinstalls. `super.users` workaround therefore remains permanent until root-caused. Diagnostics probe TLS.1 (see A28 for the pipeline change) confirmed the fcb-trust-bundle ConfigMap is complete (144 aliases, both FCB Root CA 1+2 and every major public CA present), so the reinstall's C3 failure was NOT the discovery issue — it was a separate C3-specific Armeria/Netty trustStore gap documented in A28.

### A28. CFK ControlCenter's Armeria/Netty HTTP client to Okta ignores `-Djavax.net.ssl.trustStore` — needs explicit `confluent.metadata.ssl.truststore.*` + `confluent.controlcenter.streams.ssl.truststore.*` overrides

* **Symptom**: `controlcenter-0` in CrashLoopBackoff on a fresh Phase 2 cluster (post-wipe, `super.users` bypass in effect, RBAC no longer the blocker). C3 log shows `javax.net.ssl.SSLHandshakeException: (certificate_unknown) PKIX path building failed: sun.security.provider.certpath.SunCertPathBuilderException: unable to find valid certification path to requested target` from a stack that runs `io.confluent.controlcenter.httpclient.OauthBearerTokenHttpCredential.authorizationHeaderValue()` → `OauthBearerTokenHttpCredential.getConfluentToken()` → `HttpOauthBearerCredentialProvider.getCredentials()` → `RefreshingAccessTokenRetriever.retrieve()` → `HttpJwtRetriever.retrieve()` → `HttpsURLConnection` to `myapps.firstcitizens.com/oauth2/default/v1/token`. Thread name `[armeria-common-worker-epoll-2-3]`. Retries 3 times (5s / 10s / 20s backoff), then Guice bails and the pod exits. `SchemaRegistry` and `KafkaRest` and `Connect`, all doing structurally-similar OAuth against the same Okta endpoint with the same JVM trustStore configOverrides, are fine (TLS.2 diagnostics probe confirms).
* **Root cause**: C3-next-gen (`cp-enterprise-control-center-next-gen:2.5.0`) uses **Armeria** (a Netty-based async HTTP client framework) for outbound HTTP under `io.confluent.controlcenter.httpclient.*`. **Netty/Armeria SSL contexts do NOT automatically inherit `-Djavax.net.ssl.trustStore` / `-Djavax.net.ssl.trustStorePassword` / `-Djavax.net.ssl.trustStoreType` JVM system properties.** They build their own `SslContext` at construction time, and unless explicitly told which trustStore to use, they fall back to the JRE's built-in `$JAVA_HOME/lib/security/cacerts` — which has the standard set of public CAs baked into OpenJDK but does NOT have FCB Root CA 1 or FCB Root CA 2. Since `myapps.firstcitizens.com` is signed by FCB Root CA 2 (per the actual cert chain), PKIX validation fails. SR / Connect / KafkaRest are unaffected because their HTTPS-to-Okta calls use stock `java.net.HttpsURLConnection` (which DOES respect `javax.net.ssl.trustStore`) — only C3 pipes its OAuth token fetch through Armeria.
* **Fix (commit `<HEAD>`)**: add six lines to `apps/confluent-platform/dev/controlcenter.yaml` `configOverrides.server`, pointing C3's per-prefix trustStore configs at the same CFK-mounted `bundle.jks` we already use for JVM defaults:
  ```
  - confluent.metadata.ssl.truststore.location=/var/ssl/truststore/bundle.jks
  - confluent.metadata.ssl.truststore.password=changeit
  - confluent.metadata.ssl.truststore.type=JKS
  - confluent.controlcenter.streams.ssl.truststore.location=/var/ssl/truststore/bundle.jks
  - confluent.controlcenter.streams.ssl.truststore.password=changeit
  - confluent.controlcenter.streams.ssl.truststore.type=JKS
  ```
  `confluent.metadata.*` feeds C3's `OauthBearerTokenHttpCredential` / `RefreshingAccessTokenRetriever` — the exact stack that was failing PKIX. `confluent.controlcenter.streams.*` covers C3's Streams client (which needs the same trustStore for its Okta token calls even if VM `d11547varc-g5w0-control-center.properties` sets it via the streams prefix). Explicit `.type=JKS` is added on both prefixes to remove ambiguity — the CFK bundle is JKS format, but if C3's SSL config code defaults to PKCS12 detection heuristics for password-less stores or falls back to a JVM default type, it might otherwise pick the wrong parser. VM CP set both keys with `.type` implicit; on CFK we set it explicit. Kept the global `configOverrides.jvm` `-Djavax.net.ssl.trustStore=...` block untouched — SR/Connect/KafkaRest still rely on it and they're clean, so no risk to touch it, and adding the per-prefix overrides only adds coverage without removing any.
* **Why it matters**: the pattern is now — **any CP component making OAuth-authenticated HTTP calls to MDS/Okta needs explicit `confluent.metadata.ssl.truststore.*` overrides**, even when the JVM's global trustStore is set correctly. This includes C3 (via Armeria/Netty) AND any component whose stack goes through Confluent's `io.confluent.security.auth.client.rest.RestClient` / `RefreshingAccessTokenRetriever` / `HttpJwtRetriever` path. Diagnostics probe TLS.3 (log filter for `PKIX|SSLHandshake|certificate_unknown|SunCertPathBuilder|X509TrustManager|oauth.*bearer|jwt|token.endpoint|RefreshingAccessTokenRetriever`) will catch this class of failure on future components — check TLS.3 first when a Confluent component crash-loops post-Phase-2 with no visible RBAC error.
* **Update (2026-07-02, Connect also hit this)**: after bumping Connect from `replicas: 0` to `replicas: 2` at commit `553ecb2`, `connect-0` pod immediately crash-looped with 261 identical PKIX failures in its startup log — same stack (`RefreshingAccessTokenRetriever` → `HttpJwtRetriever` → `HttpsURLConnection` to `myapps.firstcitizens.com/oauth2/default/v1/token`) as C3 hit. Note: **Connect does NOT use Armeria** — its failing path is stock Kafka common `HttpJwtRetriever` (`HttpsURLConnection`-based), which SHOULD respect `javax.net.ssl.trustStore` JVM args but for reasons yet not understood, doesn't. Fix at commit `<HEAD>` mirrors C3's: add three `confluent.metadata.ssl.truststore.{location,password,type}` lines to `apps/confluent-platform/dev/connect.yaml` `configOverrides.server`. This suggests the root cause is broader than "Armeria's SslContext ignores JVM defaults" — it's more like **Confluent's MDS-auth code path constructs its own SSLContext regardless of the underlying HTTP client library**, and that SSLContext only reads from `confluent.metadata.ssl.truststore.*` (not the JVM default). SR is presumably not hitting this because it either uses cached tokens through Kafka SASL client path (which uses its own trustStore config bound to the OAUTHBEARER SASL mechanism) or doesn't yet trigger the `RefreshingAccessTokenRetriever.retrieve()` code path during smoke-test workloads. **Preemptive**: if in the future any other CP component (KafkaRest, SR replicas > 1, future SASL clients) starts showing PKIX on the same `HttpJwtRetriever` stack, add the same three lines to that CR.

### A29. C3 basic-auth using Okta service-client credentials — smoke-test pattern that sidesteps SSO/OIDC/redirect complexity

* **Symptom / motivation**: after A28 unblocks C3 boot, we want to log into the C3 UI to smoke-test without (a) enabling interactive OIDC SSO (which needs Okta admin work to register the MDS callback URL and coordinates a per-user rolebinding that is currently blocked by A27's discovery timeout), (b) putting Ayu's personal email (`aadmassu@psyncopate.com`) into `spec.authorization.superUsers` (would give any Okta-authenticated user cluster admin), or (c) waiting on the A27 discovery timeout to be root-caused so per-user rolebindings can propagate.
* **Approach**: use CFK's **`spec.authentication.type: basic`** with a Jetty realm file where the "username" is the C3 Okta client ID and the "password" is its client secret. Backend calls from C3 to broker / MDS / SR / Connect / KafkaRest still run as the C3 service principal (`0oa1ov6h5mwmQTCKI358` via `oauth-controlcenter` Secret) which is already in Kafka's `spec.authorization.superUsers`, so every RBAC-gated action post-login succeeds via the super.user short-circuit rather than going through MDS. No Okta redirect. No callback URL registration. No per-user rolebinding.
* **Fix (commit `<HEAD>`)**: three-file change.
  * **`apps/confluent-platform/dev/controlcenter.yaml`**: `spec.authentication` block swapped from `type: mtls + sslClientAuthentication: requested` to `type: basic + basic.{secretRef: controlcenter-basic-auth, roles: [Administrators], restrictedRoles: [Restricted]}`. The CFK 3.1.x ControlCenter CRD enum is `[basic|ldap|mtls]` — `basic` is directly supported, no workaround needed. `dependencies.mds.ssoProtocol: oidc` is left in place but is ignored when top-level auth is `basic` (harmless config carryover).
  * **`.azure-pipelines/confluent-platform.yaml`**: new step in `create-prereqs` block that generates a `controlcenter-basic-auth` Secret from the existing `dev-oauth-controlcenter-client-id` + `dev-oauth-controlcenter-client-secret` variables. Secret has a single key `basic.txt` containing one Jetty realm line: `<c3-client-id>: <c3-client-secret>,Administrators,Restricted`. `controlcenter-basic-auth` added to the REQUIRED_SECRETS pre-flight check, the `oc describe` loop, and the Summary listing so it's treated on par with the other C3 auth Secrets.
* **How to log in**: browse to `https://controlcenter.apps.dv-p.ocp.fcbint.net`. Browser shows the native HTTP-Basic auth popup (`WWW-Authenticate: Basic realm=...`). Paste C3's Okta client ID as username and the client secret as password (values are in the AZDO variable group under `dev-oauth-controlcenter-client-id` / `dev-oauth-controlcenter-client-secret`, or in `apps/confluent-platform/cp-confluent/dev/d11547varc-g5w0-control-center.properties` line 34 `clientId=...`/`clientSecret=...`). C3 validates against `basic.txt`, grants `Administrators` role, UI renders. All backend API calls run as the C3 service principal (super.user in Kafka).
* **Why it matters**: this is a **smoke-test pattern**, not a target end-state. When A27's discovery timeout is root-caused and rolebindings can propagate reliably, switch to interactive OIDC SSO (add three lines to `configOverrides.server`: `confluent.controlcenter.auth.sso.mode=oidc` + `confluent.controlcenter.rest.authentication.method=BEARER` + `confluent.controlcenter.rest.advertised.url=https://controlcenter.apps.dv-p.ocp.fcbint.net`, register the MDS callback in Okta at `https://kafka-mds.apps.dv-p.ocp.fcbint.net/security/1.0/oidc/authorization-code/callback`, revert `spec.authentication.type` back to something that doesn't force basic auth). For dev/smoke-test, basic auth using service credentials is fine; do NOT ship this pattern to UAT/PRD without an active decision — using service credentials as human login is a compliance-audit red flag (no per-user attribution). Also does NOT give any human a rolebinding — human RBAC via SSO remains blocked until A27 is fixed regardless.

### A30. C3 browser SSO must use the Okta OIDC **web** app, never C3's machine client — and the pipeline never checked which one landed in the Secret

* **Symptom**: clicking through to the C3 UI redirects to Okta and fails immediately with `Error: Clients with 'application_type' of 'service' are not allowed to access the 'authorize' endpoint.` The authorize URL carries `client_id=<C3 machine client>` (UAT: `0oa1owk00kzjNnTxw358`).
* **Root cause**: two distinct Okta clients exist and they are not interchangeable. The VM property files make the split explicit — the **broker** carries `confluent.oidc.idp.client.id` (UAT `0oa1o55bn1mSPf0HY358`), an OIDC *web* app used for the browser authorization-code flow, because MDS runs inside the broker and MDS drives that flow. **Control Center** carries only `confluent.metadata.oauthbearer.login.client.id` (UAT `0oa1owk00kzjNnTxw358`), a *service* app used for client-credentials BEARER calls to MDS; C3 has no SSO client of its own. Okta refuses `application_type: service` at `/authorize`, so putting the C3 client in MDS's SSO slot fails at the first redirect. The CFK CRs were correct throughout (`kafka.yaml` `services.mds.provider.sso.clientCredentials.secretRef: oauth-mds-sso`; `controlcenter.yaml` `dependencies.mds.authentication.oauth.secretRef: oauth-controlcenter` + `ssoProtocol: oidc`) — the wrong client ID was in the runtime `oauth-mds-sso` **Secret**, which had gone stale because `create-prereqs` had never run to completion on that cluster (blocked by H7).
* **Fix**: the `oauth-mds-sso` validation only asserted `clientId` was non-empty, so a wrong-but-populated value passed silently. It now decodes the Secret and asserts the value: fails if `clientId` equals `$OAUTH_C3_ID` (echoing the exact Okta error so the cause is unmistakable), and fails if it does not equal `$OAUTH_MDS_SSO_ID`. Complements the existing variable-level separation check, which compares the two *variables* but never what actually reached the cluster.
* **Why it matters**: manifests and variable group can both be correct while the cluster is wrong — a stale Secret survives until something overwrites it. Structure-only checks ("key is present") do not catch identity errors. Also register the callback on the OIDC app for the **floating** host: `https://controlcenter.apps.ut.ocp.fcbint.net/api/metadata/security/1.0/oidc/authorization-code/callback` — after the floating-DNS ingress change a site-specific `apps.ut-p`/`apps.ut-s` registration yields `redirect_uri mismatch` immediately after this error clears.

### H7. `create-prereqs` failed on CMF's ExternalSecrets — the CFK ESO gate was namespace-wide, not CFK-scoped

* **Symptom**: on `uat-s`, `create-prereqs` cleared the `cfk-license` ESO bypass and then failed in **Create prerequisite Opaque Secrets** with three errors naming secrets CFK does not use:
  `ERROR: ExternalSecret CR confluent-license ... not Ready=True`, same for `cmf-encryption-key` and `cmf-db-credentials`, then `ERROR: 3 ExternalSecret(s) not synchronized`.
* **Root cause**: two independent things. (1) The **real fault** is the CyberArk `SecretStore` `11547-u-key-fp` in `dah-flink-uat` on the **ut-s** cluster — every ExternalSecret routed through it fails with `endpoint gave error 400 Bad Request`, CFK's and CMF's alike. Different remote keys, same store, all failing, so the fault is the store (malformed `Address`, AppID, or missing ut-s egress IP in the allowlist), not the individual `remoteRef`s. FCB Container team owns the fix. (2) The **reason CFK was blocked by it** is that STEP 2 of the prereq step discovered every ExternalSecret in the namespace (`oc get externalsecrets` with no selector) and hard-failed on any that was not `Ready=True`. CFK and CMF share `dah-flink-<env>` in every environment, so the gate had always been asserting on CMF's secrets — it simply never fired before, because CyberArk works in dev/qa and those secrets sync. Latent since `4743424`; newly exposed, not new behaviour.
* **Fix**: `PIPELINE_OWNED_SECRETS` moved above STEP 2 and a new `is_cfk_required()` helper classifies each discovered ExternalSecret by its **target Secret name**. Targets in that list still hard-fail; everything else logs `WARN ... not a CFK prerequisite, continuing` plus a closing NOTE that the owning component's own pipeline will still fail. The discovery loop stays namespace-wide because `is_eso_managed()` needs it to decide which Secrets to skip creating — only the *failure* is scoped.
* **Why it matters**: a broken CMF SecretStore must not block a CFK deploy, and vice versa. Note the knock-on: `apply_secret_from_literals` skips any name an ExternalSecret targets **regardless of that ExternalSecret's health**, so while CMF's `confluent-license` ES exists-but-fails, the `confluent-license` Secret is neither ESO-populated nor pipeline-created. CFK does not consume it (`kafka.yaml` uses `license.secretRef: cfk-license`), so CFK is unaffected — but do not read a green `create-prereqs` as meaning CMF is ready.

### A31. VM and CFK listener names are inverted — and CFK's listener keys cannot be renamed to match

* **Symptom**: reading a VM `.properties` file next to a CFK Kafka CR suggests the auth model was inverted during migration. VM puts OAUTHBEARER on `INTERNAL:9092` and SASL/PLAIN on `BROKER:9091`; CFK puts SASL/PLAIN on `internal:9071` and OAuth on `external:9092`. The names say the opposite of each other.
* **Root cause**: the two platforms scope the word "internal" differently. VM `INTERNAL` means *internal to the FCB network* — it is the client-facing listener, and every VM component (SR, Connect, REST Proxy, C3) bootstraps to it on 9092 with `sasl.mechanism=OAUTHBEARER`. CFK `internal` means *internal to the Kubernetes cluster* — inter-broker and controller traffic. There is **no functional inversion**: after the 2026-08-12 hybrid-auth refactor, CFK managed components bootstrap to `external:9092` with `type: oauth` and their own Okta client IDs, which is exactly what the VM components do, on the same port number. Verified across `apps/confluent-platform/cp-confluent/dev/` and `.../prd/` against the dev and prd Kafka CRs.
* **Fix**: none available in the manifests. The CFK v1beta1 Kafka CRD declares `spec.listeners` with `additionalProperties: false` and exactly four keys — `internal`, `external`, `replication`, `custom`. Arbitrary listener names are rejected at admission, so the VM names cannot be reproduced. The remedy is the VM→CFK mapping table now in `docs/LISTENER_PORT_MATRIX.md`; read it before comparing the two.
* **Why it matters**: this is a review trap, not a defect, and it costs time in exactly the wrong place — during a migration parity review, where "the listeners are backwards" reads as a blocking finding. Confirm parity by **role and port**, never by listener name.

### A32. VM advertises `CERTONLY` on 7055 because an F5 fronts it — the brokers bind 9094 and CFK already matches

* **Symptom**: VM `advertised.listeners` announces `CERTONLY://brokerNN.dah-kafka-{pdc,sdc}.firstcitizens.com:7055` while `listeners` binds `CERTONLY://:9094`. Reading only the property file, this looks like a parity gap that CFK cannot close.
* **Root cause**: **7055 is an F5 VIP port, not a broker port.** Confirmed against the FCB VM network architecture diagram (Platform Integration; held locally in `project-docs/diagrams/`, marked confidential — do not commit it). The path is `FIS partner --7055 mTLS--> public VIP --NAT--> F5 internal VIP --9094--> broker`. PDC: public 69.89.143.28-30 NAT to F5 VIPs 10.0.192.196-198, named `broker{1,2,3}-pdc.fcbint.net`. SDC: public 69.89.156.28-30 NAT to 10.208.4.38/.37/.36, named `broker{1,2,3}-sdc.fcpd.fcbint.net`. The broker binds 9094 at both sites; the F5 does the 7055→9094 translation. `advertised.listeners` says 7055 so the partner's client is sent back through the F5 rather than at the broker directly.
* **So CFK already has parity on the bind side** — `custom[certonly]` on 9094 is exactly what the VM brokers do. The cutover action is to re-point the **F5 pool members** from VM brokers to CFK brokers; the partner keeps the same DNS name, VIP and port and changes nothing.
* **Fix (partial)**: `listeners.custom[certonly]` added to `apps/confluent-platform/dev/kafka.yaml` — port 9094, `type: mtls`, `sslClientAuthentication: required`, `secretRef: kafka-tls`. Bind-only; no `externalAccess`.
* **The routing mode is `staticForHostBasedRouting`, not `staticForPortBasedRouting`**: VM advertises the *same* port (7055) on a *different* hostname per broker. `staticForPortBasedRouting` does the opposite — fixed host, port incremented per broker — so it cannot reproduce the VM shape. `staticForHostBasedRouting` takes `brokerPrefix` + `domain` + `port`.
* **Exact hostname parity is not achievable, and the near-miss is dangerous**: CFK builds each advertised name as `<brokerPrefix><brokerId>.<domain>` from **0-indexed** broker IDs, and the CFK 3.1.2 Kafka CR exposes no broker-id-offset field (checked the full `spec` schema). VM hostnames are 1-indexed (`broker1..3`, dev/uat) or zero-padded 1-indexed (`broker01..03`, prd/dr), and VM's `broker.id` values are 101/102/103 — decoupled from the hostname entirely. So `brokerPrefix: broker` emits `broker0/1/2`: in dev/uat that **partially overlaps** the VM names while resolving to a different broker, which is worse than no overlap; in prd/dr the zero-padding means no overlap at all. Resolve by choosing either new CFK-shaped names (and re-pointing cert-only clients) or FCB DNS aliases mapping VM names onto CFK endpoints — do not assume `brokerPrefix` alone gets you parity.
* **Why it matters**: the whole class of "the VM property file says something CFK cannot express" needs the network picture before it is called a gap. Here the property file was describing a perimeter mapping, not a broker capability. Two live follow-ons remain: (a) the CFK-advertised names must resolve to the same three VIPs and appear as SANs on `cert-manager/kafka-tls-certificate.yaml` — they are on `firstcitizens.com` while every CFK cert is on `fcbint.net`, a KeyFactor policy question for FCB PKI; (b) **does the F5 terminate or pass through mTLS?** The diagram labels the partner leg `mTLS` and the F5→broker leg `BSA` (server auth only). If the F5 terminates client-cert auth, the broker authenticates the *F5's* certificate, not the partner's, which changes `principalMappingRules` on the `certonly` listener. Unresolved — confirm with Tushar / Rick. Treat the diagram's protocol labels as approximate; every Kafka port on it is labelled "HTTPs".

### A33. C3 "Topics" kicks you back to login and shows 0 topics — the broker validates only Okta JWTs, not MDS-issued ones

* **Symptom**: Control Center dashboard renders fine — 3 brokers, live production/consumption throughput — but the Topics panel reads `0 Total` with `--` partitions, and clicking **Topics** immediately bounces you to the login screen. Log back in, click again, same thing. Reproduces identically in **every** environment. Broker log fills with:
  ```
  WARN [data-plane-kafka-network-thread-N-EXTERNAL-SASL_SSL-N]
    OAuthBearerValidatorCallbackHandler handleValidatorCallback -
    Could not validate the access token: JWT rejected due to invalid signature.
    Invalid JWS Signature: JsonWebSignature{"alg":"RS256","kid":null}
  ```
* **Root cause**: decode the rejected token and it is **not an Okta token** — `iss: "Confluent"`, `kid: null`, `sub: 00u…` (an Okta *user* id, not a `0oa…` client id), carrying the user's Okta groups. It is an **MDS-issued** token: when a human clicks Topics, C3 calls Kafka *on behalf of that user* with a token MDS minted and signed with `mds-token-keypair`. The broker's EXTERNAL listener hands it to Apache's `DefaultJwtValidator` → `BrokerJwtValidator`, which only verifies against the **Okta JWKS**. An MDS-signed token can never validate there, so SASL auth fails, C3 treats the session as invalid, and redirects to login — an unwinnable loop, since each fresh login mints another MDS token (confirmed: consecutive rejections carry different `ssid` and `auth_time` values seconds apart, on all three brokers).
* **Why metrics still work**: C3's own Streams app authenticates as its Okta *service* client (`0oa…`), an Okta-signed token that validates normally. Only the human-on-behalf-of path breaks — hence live broker throughput next to a zero topic count.
* **The VM does this correctly** and we dropped half of it in the port. VM pins the composite validator on its OAuth listener:
  ```
  listener.name.internal.oauthbearer.sasl.server.callback.handler.class=\
    io.confluent.kafka.server.plugins.auth.token.CompositeBearerValidatorCallbackHandler
  ```
  That handler validates **both** token families — Okta JWTs via JWKS, MDS tokens via `publicKeyPath`. Our CR carried the `publicKeyPath` on the *login module* but never the server callback handler, so nothing ever consumed the key.
* **Fix — two changes, and neither works alone**:
  1. Add the handler: `listener.name.external.oauthbearer.sasl.server.callback.handler.class=io.confluent.kafka.server.plugins.auth.token.CompositeBearerValidatorCallbackHandler`
  2. **Correct `publicKeyPath`.** It read `/mnt/secrets/mds-token/mdsPublicKey.pem` in all six envs; CFK actually mounts the `mds-token-keypair` Secret at **`/mnt/secrets/mds-token-keypair/`** (verified against a live `kafka-0` pod spec). The filename is right — the pipeline writes `mdsPublicKey.pem` — the directory was wrong.

  Applying only (1) turns a warning into a **fatal** startup failure: a missing `publicKeyPath` throws inside `SaslChannelBuilder.configure()`, the same position that crash-loops a broker (compare A34/the PRD JWKS timeout). Applying only (2) changes nothing, because nothing reads the file.
* **Why it hid for months**: the wrong path was unreachable code. No composite handler meant nothing opened the file, so the typo produced no error anywhere. The two bugs masked each other.
* **Why it matters**: never read "the dashboard loads" as "auth works". C3 has two distinct paths to Kafka — its own service identity and impersonation of the logged-in human — and they use different token issuers. A config that satisfies one can fail the other completely while the UI still looks half-alive. Also worth re-checking whether the CFK-generated `token` listener needs the same handler; the pod mounts `kafka-tokensasl-listener-apikeys`, but only `EXTERNAL` threads appear in the failure logs.

---

### H8. Floating DNS follows the primary — the secondary clusters need their own site Ingresses

* **Symptom**: with only `<component>.apps.ut.ocp.fcbint.net` /
  `apps.pd.ocp.fcbint.net` host rules, nothing on `uat-s` (ut-s) or `dr`
  (pd-s) is reachable from a browser or a client: the floating CNAME is
  flipped by Container Platforms on DNS failover and resolves to the
  primary cluster in normal operation, and OpenShift routes match on the
  Host header.
* **Root cause**: "secondary" at FCB is the failure domain of UAT and Prod
  (the only two envs that have one — see the FCB "OpenShift Ingress"
  doc). Our Ingresses carried the floating host only; the site name was
  present just as a Certificate SAN.
* **Fix (2026-09-08)**: `uat-s/ingress/` and `dr/ingress/` gained one
  `<component>-site-ingress.yaml` per component (`<component>-site`
  object, host `<component>.apps.ut-s` / `apps.pd-s`), identical to the
  floating file in termination, backend and TLS Secret. No Certificate
  change: every `*-ingress-tls` cert already has the site name as CN and
  the floating name as SAN, and `controlcenter-tls` (passthrough) lists
  both too. The `confluent-platform.yaml` ingress step validates and
  applies the site files whenever `site_ingress_domain` differs from
  `floating_ingress_domain` and the files exist; dev/qa/uat-p/prd are
  untouched.
* **Why it matters**: the secondary must be exercisable before a failover
  (smoke tests, RBAC onboarding, cluster-link source endpoints for the
  CFK→CFK links in I5). Anything that publishes a hostname for UAT or
  Prod needs a `-p` and a `-s` answer; floating alone is not enough. C3
  OIDC on the site host also needs the ut-s / pd-s callback URI
  registered on the Okta app, or SSO works only through the floating name.

## I. Cluster Linking + Schema Linking (VM CP → CFK)

### I1. The ClusterLink CR is rendered, not hand-edited — topic / group / ACL lists live in text files

* **Context**: the migration needs one destination-initiated link per env
  (VM DEV→CFK DEV, VM QA→CFK QA, VM UAT→CFK UAT-P, CFK UAT-P→CFK UAT-S,
  VM PRD→CFK PRD, CFK PRD→CFK DR). QA is the pilot.
* **Shape**: `apps/confluent-platform/<env>/cluster-linking/` holds `link.env`
  (endpoints, names, scope), `clusterlink.yaml` (CR template with empty
  `mirrorTopics` / `consumerGroupFilters` / `aclFilters`), and the lists
  `topics.txt`, `promote-topics.txt`, `consumer-groups.txt`, `acls.txt`.
  `.azure-pipelines/scripts/render_clusterlink.py` merges them and forces
  `consumer.offset.sync.enable` / `acl.sync.enable` to match whether the
  corresponding file is empty. The source cluster ID is discovered at run
  time (`kafka-cluster cluster-id` from `kafka-0` against the source) so a
  VM rebuild never leaves a stale ID in git.
* **Why it matters**: CFK deletes a mirror topic that disappears from
  `spec.mirrorTopics`. A promoted topic must therefore stay in BOTH
  `topics.txt` and `promote-topics.txt` for the life of the link; the
  renderer refuses a promote entry that is not also a mirror.
* **Source auth**: OAuth client credentials on the source 9092 listener
  (VM `INTERNAL`, CFK `external` — same port, see A31). The linking
  principal is an existing Okta pair from the variable group, chosen by
  the pipeline's `linkPrincipal` dropdown (default `<env>-oauth-broker-*`,
  the VM broker/MDS client that is already a VM super.user; a dedicated
  `<env>-clusterlink-oauth-client-*` pair is an option once issued),
  materialised as Secret `oauth-clusterlink` with the same five keys as the
  other `oauth-*` Secrets. Source endpoints also come from the variable
  group (`<env>-kafka-broker-hosts` with the port rewritten to 9092,
  `<env>-schema-registry-hosts`, `kafka-oauthbearer-token-endpoint-url`)
  when `link.env` says `@vargroup`; `SOURCE_HOST_PREFIX` (`q11547varc-`
  for QA) fails the run if a variable still points at another env's VM
  cluster, which the QA group did at one point. Trust for the source comes from
  `clusterlink-source-ca` (FCB root PEMs + `kafka-tls` `ca.crt`, stored as
  both `cacerts.pem` and `ca.crt`). CFK does not rotate TLS material on a
  live ClusterLink; re-apply after a CA change.

### I2. Schema Linking runs INSIDE the source Schema Registry — the CFK CR only manages it remotely

* **Symptom to expect**: `SchemaExporter` CR applied, exporter never reaches
  RUNNING, source SR answers `404` on `/exporters`.
* **Root cause**: exporters are a Schema Registry plugin. The source SR must
  load `io.confluent.schema.exporter.SchemaExporterResourceExtension` in
  `resource.extension.class`, register
  `kafkastore.update.handlers=io.confluent.schema.exporter.storage.SchemaExporterUpdateHandler`,
  and carry a `password.encoder.secret` (the exporter stores destination
  credentials encrypted in `_exporter_configs`). VM DEV/UAT/PRD/DR already
  have the two classes; **VM QA does not**, and no VM SR sets
  `password.encoder.secret`. Ask the Kafka Admin to add them (SR restart).
* **Fix / shape**: `schemaexporter.yaml` uses `sourceCluster.schemaRegistryRest`
  = the VM SR URL (the operator dials it) and
  `destinationCluster.schemaRegistryRest` = the CFK SR **Ingress hostname**
  (the VM SR dials it, so an in-cluster `svc` name would not resolve).
  `contextType: NONE` keeps subject names identical so clients cut over
  without renames; subjects land in IMPORT mode on the CFK SR and stay
  read-only until the exporter is deleted at cutover.
* **Pipeline gate**: `validate` mints a token as the linking principal and
  probes `/exporters` on both SRs; 404 = extension missing, 401/403 =
  extension present but role bindings missing.

### I3. Role bindings for the linking principal live on both sides — and the CFK SR cluster id is whatever `schema.registry.group.id` says

* **Destination (CFK)**: `cluster-linking/rbac/clusterlink-rolebindings.yaml`
  grants `ResourceOwner` on `Subject:*` in the CFK SR scope (needed to
  write subjects and flip them to IMPORT mode) and `Operator` on the Kafka
  cluster. The link itself is created by the operator through
  `KafkaRestClass default` (mTLS superuser), so no Kafka grant is needed
  for link creation.
* **Gotcha**: our SR CRs override `schema.registry.group.id=schema-registry`,
  while the onboarding role bindings scope
  `schemaRegistryClusterId: id_schemaregistry_<ns>` (CFK's default).
  Whichever value the running SR reports is the RBAC scope that counts.
  The pipeline reads the live value from `schemaregistry-0`
  (`DEST_SR_CLUSTER_ID=@live`) and renders it; audit the onboarding
  bindings against the same value.
* **Source (VM)**: the Kafka Admin runs `source-rolebindings.sh`
  (`discover-source` prints it fully rendered): `ClusterAdmin` on the
  source Kafka cluster, `DeveloperRead` + `DeveloperManage` per mirrored
  topic, `DeveloperRead` per synced group, and `ClusterAdmin` +
  `DeveloperRead Subject:*` in the source SR scope for the exporter.

### I4. Promote is gated on zero lag and is one-way; failover and delete need an explicit confirm

* `promote` re-describes every topic in `promote-topics.txt`
  (`kafka-mirrors --describe --pedantic` from `kafka-0` over the internal
  PLAIN listener) and refuses when any partition lag is non-zero or the
  state is not ACTIVE. Then it re-renders with `state: PROMOTE`, applies,
  verifies the stored object was not silently stripped
  (`verify_clusterlink_admission.py`), and waits for STOPPED. CFK creates
  a `clink-<topic>-<uid>` KafkaTopic CR for each promoted topic.
* `failover` ignores lag (disaster path) and `delete-link` fails over
  every remaining mirror; both require the `confirmDestructive` checkbox
  and `failover` also needs an explicit topic list.
* `mirror-status` publishes `mirror-status-report.md` (state, lag total /
  max, last fetch age, errors per topic; link describe; CR statuses;
  exporter status; broker log lines; Warning events) as the build artifact
  `cluster-linking-<env>-<action>`.

### I5. CFK→CFK links (UAT-P→UAT-S, PRD→DR) are blocked on broker exposure

* CFK brokers at FCB are ClusterIP-only (no LoadBalancer, no per-broker
  passthrough Routes). A destination-initiated link needs the destination
  brokers to dial the source brokers, which is fine for VM sources (egress
  to `fcpd.fcbint.net:9092`) but impossible for a CFK source in another
  OpenShift cluster until its brokers are reachable from outside.
  `uat-s/` and `dr/` `link.env` therefore carry `REPLACE_WITH_*` for the
  source bootstrap and the `validate` action stops at the placeholder gate.
  The floating `apps.ut` / `apps.pd` hostnames follow the primary cluster,
  so the secondary must use cluster-specific names once they exist.

## How to add an entry here

1. Pick the right section (A–I). If your issue doesn't fit, add a new
   section letter.
2. Number the entry within the section (e.g. C5 if C currently goes up
   to C4).
3. Follow the **Symptom → Root cause → Fix → Why it matters** shape.
4. Keep it dense. One screenful of terminal output is too much; a few
   sentences plus a code block if needed is right.
5. Update `runbook/CHECKLIST.md` if the issue suggests a new gate to
   add to the per-env checklist.
