# Week 2 — Q&A (20 reinforcement questions)

---

## Monday — RBAC + ServiceAccounts (+ SCC gap-fill)

**Q1. What does a RoleBinding actually do at the apiserver?**
A. It links a Subject (User, Group, or ServiceAccount) to a Role inside a namespace. When that Subject makes a request, the apiserver evaluates RBAC: "is there a RoleBinding in this namespace giving Subject X a Role that allows verb Y on resource Z?" The first allow wins; otherwise deny.

**Q2. Why does the platform use namespace-scoped Roles for CMF, not ClusterRoles?**
A. Project memory `project_cmf_namespace_scoped`. CMF deploys to dah-flink-<env> only; granting cluster-wide permissions is an unnecessary blast radius. Namespace-scoped RBAC limits CMF to its own resources, which is auditable and survives  the platform security review (Rick's review style).

**Q3. What's a ServiceAccount token, and how does a Pod get it?**
A. Each ServiceAccount auto-generates a token (a JWT). When a Pod has `spec.serviceAccountName: foo`, kubelet projects that SA's token into `/var/run/secrets/kubernetes.io/serviceaccount/token` in the Pod. Kubernetes API client libraries read it from there. K8s 1.24+ uses projected, time-bound tokens by default.

**Q4. Two production-relevant differences between RBAC Roles and SCCs.**
A. (1) RBAC gates **what API operations** a Subject can call. SCCs gate **what Pod spec fields** are allowed (privileged, hostNetwork, runAsUser ranges, volumes). (2) RBAC is namespace-scoped (Roles) or cluster-scoped (ClusterRoles). SCCs are cluster-wide and assigned to Subjects via separate `oc adm policy add-scc-to-user`. CFK Pods run under `restricted-v2` in production by default.

---

## Tuesday — Operators

**Q5. Walk the Operator reconciliation loop in 5 steps.**
A. (1) Watch — controller subscribes to CR changes via the apiserver; (2) Read current state — both the CR spec and the live K8s objects it owns; (3) Compute desired state — what objects should exist for this spec; (4) Apply diff — create/update/delete owned objects (server-side apply); (5) Update status — write `status.conditions` back to the CR. Repeat on any change, or every N seconds as a sanity check.

**Q6. What does "level-triggered" mean?**
A. The Operator looks at the current STATE of the world, not at events. If it missed 50 events while it was down, it doesn't replay them — it just looks at "where are we now vs. where should we be" and converges. This is more robust than event-driven (edge-triggered) systems that lose work on missed events.

**Q7. The CFK operator in production needed a verb added — which one and why?**
A. `update` + `patch` on PVCs (RITM1093307, tracker 2.3). When CFK rotates PV ownerReferences after a broker StatefulSet change, the operator must mutate the PVC's metadata. Without the verb, brokers fail to come up cleanly during certain rotations. Documented in runbook + the standard  the platform RBAC bundle.

**Q8. If you delete a CR, what should happen to the objects it owned?**
A. They should be deleted too via ownerReferences. K8s' garbage collector finds objects whose `ownerReferences` point at the now-deleted CR and removes them. Finalizers on the CR can hold the deletion if the Operator needs to do cleanup first (e.g. external resource teardown). Stuck finalizers are a common production headache — runbook A13.

---

## Wednesday — Monitoring

**Q9. Trace the metrics journey from a CFK broker Pod to your eyes.**
A. (1) Broker exposes JMX MBeans inside the JVM; (2) JMX exporter sidecar scrapes JMX, exposes Prometheus-format HTTP on port 7203; (3) Prometheus discovers the Pod via ServiceMonitor + scrapes at intervals; (4) Prometheus stores time series; (5) Grafana panel queries Prometheus via PromQL; (6) engineer's browser renders the graph.

**Q10. What's a ServiceMonitor and why do you need one?**
A. A CRD provided by the Prometheus Operator. It tells Prometheus "scrape Pods matching label X on port Y at path Z." Without it, Prometheus doesn't know what to scrape. CFK ships ServiceMonitors for brokers + Connect + SR; you typically don't write your own in production.

**Q11. Difference between a Prometheus rule and an alert?**
A. A rule is a PromQL expression evaluated periodically — can output a derived metric (recording rule) or a binary firing/not (alerting rule). An alert is the FIRING state of an alerting rule plus the rule's metadata (severity, runbook link). Alerts flow to Alertmanager which routes to Slack/PagerDuty.

**Q12. What's the 5-metric checklist for "is this Kafka broker healthy?"**
A. (Cross-ref Wk5 too.) (1) under_replicated_partitions = 0; (2) under_min_isr_partition_count = 0; (3) request_handler_avg_idle_percent > 50%; (4) request_throttle_time_avg per client (anomalies?); (5) log_log_size trend (growing as expected?).

---

## Thursday — GitOps

**Q13. What does ArgoCD's "Sync" status mean vs "Health"?**
A. Sync: does the live cluster match what git declares? `Synced` = yes, `OutOfSync` = no. Health: are the deployed objects working? `Healthy` = Pods Ready, services up; `Degraded` = something broke at runtime. You can be Synced + Degraded (git is correct but runtime failed) or OutOfSync + Healthy (cluster works but someone hand-edited an object).

**Q14. the platform uses ArgoCD for what, and what does it NOT manage?**
A. Project memory `project_deployment_tools`: ArgoCD manages **operators only** (cert-manager, CFK operator, ESO, etc.). Azure DevOps pipelines manage **workloads** (Kafka CRs, Connect, Flink applications). This split reduces ArgoCD blast radius — an ArgoCD outage doesn't block a Kafka topic change.

**Q15. What's "App of Apps" and when do you use it?**
A. An ArgoCD Application whose source is a directory of OTHER Application manifests. Use it when you have 20+ operators to manage — instead of clicking through 20 sync buttons, sync the parent and ArgoCD reconciles all children. the platform uses this for the standard operator bundle per cluster.

---

## Friday — Quotas + Limits

**Q16. What's the difference between a ResourceQuota and a LimitRange?**
A. ResourceQuota = namespace-wide cap on total resource consumption (e.g. 100 CPU across all Pods). LimitRange = default + maximum for each Pod/container (e.g. each container gets 100m CPU if not specified, max 4 CPU). Quota blocks at admission when total would exceed; LimitRange injects defaults and rejects per-pod overages.

**Q17. The DEV ResourceQuota story — what tripped CFK?**
A. Tracker 2.5, runbook A3. DEV's quota was originally 2 CPU, but the CFK 3.1 init container has ~500m baseline that becomes the Pod's effective minimum. 6 CFK Pods × 500m = ~3 CPU — exceeded the 2 CPU quota. Symptom was "Pod Pending — exceeded quota". Fix was raising quota to 6 CPU.

**Q18. If a Pod is Pending with `Insufficient cpu`, is that a quota error or scheduler error?**
A. Scheduler. Quota errors fail at admission (`oc apply` returns an error). Insufficient CPU at schedule-time means no node has the CPU headroom to run the Pod's request — different problem. Fix: scale workers, drain non-essential, or reduce the request.

**Q19. What does `LimitRange.spec.limits[].default` do?**
A. If a Pod creates a container WITHOUT a limit specified, this value is injected. Useful for namespaces where engineers forget to set limits — LimitRange ensures every container has some upper bound, which is required for the Pod to land in the "Guaranteed" QoS class or to be evictable safely.

**Q20. One thing Week 2 wants you to internalize before Week 3.**
A. Failures in production are usually **admission-time policy issues** (RBAC, SCC, Quota, NetworkPolicy) — not bugs. The first question for any "it won't apply" or "Pod is Pending" is "what admission controller rejected this, and which CR/policy needs updating?" That mental model makes Weeks 3-6 way faster.

---

## After completing Q&A

Flag the tracker questions (Q2, Q7, Q14, Q17) — those are the questions the operations team will ask in real incidents.
