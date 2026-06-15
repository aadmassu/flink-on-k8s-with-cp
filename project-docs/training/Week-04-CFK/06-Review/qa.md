# Week 4 — Q&A (20 reinforcement questions)

The week you'll reference most on call. Keep this file open during your first 90 days.

---

## Monday — CFK Architecture

**Q1. CFK is an Operator. What does "Operator" mean here precisely?**
A. CFK is a controller running in its own namespace (`confluent-operator`) that watches Custom Resources (Kafka, KRaftController, SchemaRegistry, Connect, Cluster Link, KafkaTopic, ...) and reconciles them into K8s primitives (StatefulSet, Deployment, Service, ConfigMap, Secret, PVC). It does NOT run brokers itself — it tells K8s how to run them.

**Q2. The five Confluent components CFK manages.**
A. (1) Kafka brokers (StatefulSet) — the data plane; (2) KRaftController (StatefulSet) — metadata layer (replaces ZooKeeper); (3) Schema Registry (Deployment) — Avro/Protobuf/JSON schemas; (4) Connect (Deployment) — source/sink framework; (5) Kafka REST Proxy + Control Center (Deployments) — HTTP gateway + UI. In production the first 4 are core; KRP/C3 are optional.

**Q3. Image tag the platform requires + why?**
A. `confluentinc/cp-server:7.7.0` + `confluentinc/confluent-init-container:2.9.0`, paired with CFK operator build matching CFK 3.1.2 (`0.1351.103`). Project memory `project_cmf_image_tag` and `project_cfk_operator_ownership`: stock CFK 3.1.0 had site-incompatible defaults; only Confluent-issued preview builds are safe.

**Q4. CFK's relationship to the platform-team owned operator.**
A. The CFK operator deployment is OWNED by Container Platforms team (Rick's team). Our repo has a vendored chart for reference only — it's stale. Build number 0.1351.x maps to CFK 3.1.x; init container minor MUST match operator minor. Currently deployed: 0.1351.103 = CFK 3.1.2.

---

## Tuesday — CR → Pod

**Q5. Walk reconciliation for `oc apply -f kafka.yaml`.**
A. (1) Watch — operator's informer sees new/changed Kafka object; (2) Validate spec (required fields, valid image, storage class exists); (3) Read dependencies — find KRaftController CR named in spec, ensure it's Ready; (4) Render child objects (StatefulSet + Services + ConfigMap + PVCs + RBAC) and server-side apply; (5) Watch child objects; when ready replicas == desired, write `cluster-ready=True` to status.

**Q6. First diagnostic command when CFK Kafka isn't healthy?**
A. `oc get kafka kafka -o jsonpath='{.status.conditions}' | python3 -m json.tool`. Read the `cluster-ready` condition. Its `message` field names the reason. Common: `cluster-ready=False, message="dependent KRaftController not ready"` — then go check KRaftController status.

**Q7. The operator never restarts a broker Pod directly. Why is that important?**
A. The operator writes the StatefulSet spec; K8s (kubelet + StatefulSet controller) manages Pods. Separation means: (a) Pod deletion (drain, eviction) doesn't go through operator; (b) you can do `oc delete pod kafka-0` and K8s recreates it without operator involvement; (c) operator can be down briefly without breaking running workloads.

**Q8. If you delete the Kafka CR, do PVCs get deleted?**
A. Generally NO — that's a deliberate K8s safety policy for StatefulSet PVCs. The Pods + StatefulSet go away but PVCs (and underlying PVs with `Retain` reclaimPolicy) remain. This protects against accidental data loss. To truly wipe broker data: delete the CR, then manually delete each PVC.

---

## Wednesday — Listeners

**Q9. Three listeners in production — port + auth + audience.**
A. **9091 internal** — TLS only, broker↔broker + broker↔KRaft, no client auth. **9092 external** — SASL_SSL + SASL_OAUTHBEARER, client apps via Okta JWT (tracker 2.9). **9094 custom-mtls** — SSL + mTLS client cert, VM CP brokers as cluster-link source (tracker 2.10, the policy exception port).

**Q10. How does the same broker JVM speak different auth on different ports?**
A. Kafka's per-listener config — `listener.name.external.sasl.mechanism=OAUTHBEARER`, `listener.name.custom-mtls.ssl.client.auth=required`, etc. The broker doesn't route between ports — it serves each port with its own auth profile. CFK exposes this via `spec.listeners` in the Kafka CR.

**Q11. Bootstrap connects but first produce fails — what's wrong?**
A. Almost always: advertised listener returning a hostname the client can't reach. The bootstrap broker correctly accepts the SASL/TLS handshake and returns "broker 2 is at internal-name:9092"; the client tries to connect to that internal-name and fails. Fix: ensure each broker's advertised listener for the external listener is the externally-reachable Route hostname, not the in-cluster name.

**Q12. Why does 9094 need a firewall exception?**
A. 9094 is not in the  the platform default policy for OpenShift Routes/LBs (which assume HTTPS 443 or Kafka 9092). The cluster-link source brokers in VM CP need to reach this port directly; that requires an explicit exception ticket = tracker 2.10. Without the exception, mTLS handshake fails at the TCP layer (connection refused or timeout).

---

## Thursday — TLS

**Q13. Who issues CFK Pod certs in production?**
A. cert-manager + Keyfactor ClusterIssuer. CFK does NOT issue certs. cert-manager creates a Secret with `tls.crt`, `tls.key`, `ca.crt`; CFK's CR references the Secret name; init container builds JKS keystores from the PEM contents; broker reads keystores at startup. Project memory `project_certmanager_keyfactor`.

**Q14. What's the trust bundle problem and how does it surface?**
A. The broker's truststore = `ca.crt` from its Secret. If a client's cert was signed by a CA NOT in the truststore, handshake fails with `bad_certificate`. Tracker 2.8. In production, two CAs need to coexist in the truststore: Keyfactor (for new CFK-side certs) AND the VM CP CA (for mTLS clients from VM brokers during migration). The Secret's `ca.crt` must contain BOTH chains.

**Q15. cert-manager rotates a Secret. What happens automatically vs manually?**
A. cert-manager rotates auto-renews per Certificate.spec.duration + renewBefore. New cert lands in the Secret. CFK operator notices the Secret change and ROLLING-RESTARTS the StatefulSet to pick up the new key. Rolling restart respects the PDB. Brief client connection blips during the rollout but no data loss. Some components (Connect) reload on SIGHUP without restart — verify per-component.

**Q16. A new Kafka client gets `unable to find valid certification path`. Most likely cause?**
A. The client is missing the issuing CA in its truststore. The broker has presented a valid cert signed by Keyfactor, but the client's JVM doesn't trust Keyfactor. Fix: add the internal CA bundle to the client's truststore (or use the JVM's default + cacerts). Common in production when a team uses a non-corporate-image JVM that doesn't include the platform's internal CA.

---

## Friday — Rolling Upgrade

**Q17. The PDB for the Kafka StatefulSet in production — value + reason.**
A. `maxUnavailable: 1`. Reason: only one broker can be unavailable at a time during voluntary disruption (drain, upgrade). If two were allowed offline simultaneously, partitions with RF=3 could drop below `min.insync.replicas=2` — producers would fail. The PDB is the safety belt on rolling upgrades.

**Q18. Four common rolling-upgrade failures, ordered by recovery cost (low → high).**
A. (1) Bad image tag — ImagePullBackOff, recovery = revert CR; cost LOW. (2) Tight PDB + planned drain — drain hangs; recovery = relax or abort drain; cost LOW. (3) Cert mismatch on new image — CrashLoopBackOff TLS error; recovery = revert image OR update Secret; cost MEDIUM. (4) PVC reattach failure — new Pod stuck Pending; recovery may require manually re-binding PV; cost HIGH (risk of data loss if mishandled).

**Q19. During an upgrade, kafka-2 is restarting on the new image. What ISR state is acceptable?**
A. For partitions where kafka-2 was a replica: ISR shrinks by 1 momentarily. As long as the remaining ISR ≥ `min.insync.replicas`, producers + consumers continue. If ISR drops below min.insync, producers see `NotEnoughReplicasException`. The PDB prevents kafka-1 from being touched until kafka-2 rejoins ISR.

**Q20. The single habit Week 4 wants you to lock in.**
A. **Always read CR `status.conditions` first.** Not `oc get pod`. Not `oc logs`. Not `oc describe`. The CR status is CFK's authoritative health report — the operator wrote it for exactly this purpose. If `cluster-ready=True`, the cluster is healthy at the CFK level and the customer's issue is application-side. If `cluster-ready=False`, the message names the problem.

---

## After completing Q&A

The "first diagnostic command" answers (Q6, Q11, Q14, Q16) form your top-of-funnel CFK runbook. Memorize them.
