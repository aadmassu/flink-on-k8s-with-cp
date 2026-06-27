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

### A15. CFK 3.2.0 v1beta1 silent-strip pattern + Kafka CR silent-bail-on-state-corruption

* **Symptom (silent-bail)**: a fresh `apply` of the production
  `apps/confluent-platform/dev/kafka.yaml` succeeds at the API server,
  but the operator emits zero events, never updates the CR status, and
  never creates `sts/kafka`. The CR sits there indefinitely.
* **Symptom (silent-strip)**: sub-blocks declared in the Kafka CR
  yaml are absent from the post-admission CR (`oc get kafka -o yaml`)
  even though the original spec is preserved in the
  `last-applied-configuration` annotation. The operator behaves
  correctly with respect to what it actually sees, but the cluster
  ends up missing OAuth / MDS / mTLS features the yaml declares.
* **Root cause (silent-bail)**: operator-state corruption from prior
  partial installs (orphaned PVCs, leftover finalizers, stale
  informer cache) — NOT a spec-driven trigger. Verified by a 4-round
  bisect (Try A=`configOverrides.server`, Try B=`services.mds`, Try
  C=`listeners.external` OAuth, Try D=`listeners.custom` mTLS) on
  2026-06-27. The operator reconciled cleanly in every round; the
  original silent-bail did not reproduce after a clean
  `uninstall + wipePVCs=true`.
* **Root cause (silent-strip)**: CFK 3.2.0 v1beta1 prunes
  schema-mismatched sub-blocks at admission with no warning and no
  rejection. Confirmed-stripped sub-blocks at the time of bisect:
  `dependencies.kRaftController.{authentication,tls}` as siblings of
  `clusterRef` (must be nested under `controllerListener`),
  `listeners.external.authentication.oauthSettings` (whole sub-block
  silently dropped — CFK falls back to a PLAINTEXT external default),
  `listeners.custom` (entire array dropped), and `services.mds`
  (entire block dropped). The production yaml has carried these
  blocks since initial commit and they have NEVER taken effect on
  this cluster — OAuth, mTLS-certonly, and embedded MDS have never
  actually been provisioned at FCB on CFK 3.2.0.
* **Fix (silent-bail)**: the consolidated `action=uninstall` step in
  `.azure-pipelines/confluent-platform.yaml` (commit 840e0e2) with
  the `wipePVCs=true` checkbox tears down CRs, patches stuck
  finalizers, and wipes orphaned PVCs in one run. Run that before
  every `install-or-update` on a stuck cluster — that's the
  streamlined recovery path now.
* **Fix (silent-strip, interim)**: remove the stripped blocks from
  `kafka.yaml` so the file reflects what's actually running on the
  cluster, and drop the **entire `ConfluentServerAuthorizer` line**
  alongside the `confluent.authorizer.access.rule.providers` line —
  not just `CONFLUENT` from the providers list. An earlier attempt at
  this fix kept `authorizer.class.name=ConfluentServerAuthorizer` and
  set `providers=KRAFT_ACL` (no CONFLUENT) on the theory that listing
  only KRAFT_ACL would skip RBAC initialization. That doesn't hold up:
  ConfluentServerAuthorizer loads its RBAC provider on startup
  regardless of the providers list (the list narrows *which rules are
  evaluated*, not *whether RBAC plumbing is loaded*), so the broker
  still fatals with "You must specify
  `confluent.metadata.bootstrap.servers` to configure the RBAC
  provider". Until MDS is correctly defined in CFK 3.2 v1beta1,
  ConfluentServerAuthorizer cannot be loaded at all — brokers run
  with no authorizer; client access is gated by the listener-level
  auth (PLAIN+TLS on internal). `super.users=User:admin` is kept
  (inert without an authorizer but harmless). Telemetry reporters
  dropped at the same time (already disabled on KRaftController for
  unprovisioned API creds — see memory
  `project_fcb_telemetry_audit_reenable_later`).
* **Fix (silent-strip, follow-up)**: the diagnostics.yaml `oc explain`
  coverage was extended at commit e67188f to cover
  `kafka.spec.services{,.mds,.kafkaRest}`,
  `kafka.spec.authorization`, `kafka.spec.identityProvider`,
  `kafka.spec.listeners.{external,custom}`. Once that runs against
  the cluster, the v1beta1 schema for each path is known and the
  OAuth / MDS / mTLS blocks can be re-added in the correct shape.
* **Why it matters**: a yaml that looks like the VM config is not the
  same as a cluster configured like the VM. Always verify
  post-admission yaml with `oc get kafka -o yaml` before assuming a
  feature is enabled. See memory `project_cfk_v1beta1_silent_strips`
  for the recurring pattern and `project-docs/pump.txt` for the
  schema-fix follow-up workstream.

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

---

## How to add an entry here

1. Pick the right section (A–H). If your issue doesn't fit, add a new
   section letter.
2. Number the entry within the section (e.g. C5 if C currently goes up
   to C4).
3. Follow the **Symptom → Root cause → Fix → Why it matters** shape.
4. Keep it dense. One screenful of terminal output is too much; a few
   sentences plus a code block if needed is right.
5. Update `runbook/CHECKLIST.md` if the issue suggests a new gate to
   add to the per-env checklist.
