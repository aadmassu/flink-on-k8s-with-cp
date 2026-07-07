# Open Follow-ups

Lightweight tracker for outstanding work that isn't yet a lesson (no fix
applied) and isn't yet a deploy gate (not a pre-flight check). Move items
into `LESSONS_LEARNED.md` or `CHECKLIST.md` when they graduate.

---

## Kafka broker `advertised.listeners` — write-up for FCB Container Platforms

**Ask from Rick** (Container Platforms, during dev floating-DNS follow-up
on 2026-07-06): document how the Kafka broker advertises its hostname to
clients so his support teams aren't surprised when they see broker traffic
land on a name different from what the client bootstrapped to.

**What the doc needs to cover:**

- Bootstrap → metadata → reconnect flow: client hits the bootstrap FQDN,
  gets back a list of `advertised.listeners`, opens new TCP connections
  to those advertised names for actual produce/consume.
- Why the advertised hostname is baked into the CR: CFK's
  `spec.listeners.external` (Kafka CR) sets what brokers advertise;
  changing it rolls the StatefulSet — not a hot rename.
- Why floating DNS doesn't help the broker path: DNS-flipping the
  bootstrap FQDN still leaves clients reconnecting to the *advertised*
  names, which are cluster-specific. This is the reason we kept the
  broker on `kafka.apps.dv-p.ocp.fcbint.net` (direct name) instead of
  the floating `kafka.apps.dv.ocp.fcbint.net` when we moved the five
  REST/UI components to floating.
- What broker failover actually is: whole-cluster event (cluster-link
  or stretched cluster), not a DNS switch. SG rules + advertised names
  must both be right on the destination cluster.
- One diagram of bootstrap → metadata → per-broker connection.

**Target delivery**: a self-contained brief (email-friendly / Confluence-
pastable) plus a canonical copy under `runbook/`. Ayu owns writing it;
Rick's team is the audience.

**Not blocking any current deploy** — this is a communication artifact,
not a manifest change.

---

## QA `qa_db_dah_azdo-svc` — missing NetworkPolicy RBAC (Container Platforms ask)

**Discovered** 2026-07-07 while running `confluent-platform.yaml action=install-or-update
environment=qa`. First `oc apply` (of `apps/confluent-platform/qa/network-policy.yaml`)
failed with:

```
Error from server (Forbidden): error when creating
  "apps/confluent-platform/qa/network-policy.yaml":
  networkpolicies.networking.k8s.io is forbidden:
  User "qa_db_dah_azdo-svc" cannot create resource "networkpolicies"
  in API group "networking.k8s.io" in the namespace "dah-flink-qa"
```

**Gap**: dev's SA (`dv_db_dah_azdo-svc`) has this permission in `dah-flink-dev` and
the same pipeline succeeds there; qa's SA is missing the same. Env-parity RBAC
issue on Container Platforms' side.

**Ask** (draft for Teams / SNOW to Rick or Tom):
> Our QA CFK deploy is failing at first-apply on the namespace-scoped
> NetworkPolicy. Service account `qa_db_dah_azdo-svc` in `dah-flink-qa`
> lacks `create` on `networkpolicies.networking.k8s.io`. DEV's
> `dv_db_dah_azdo-svc` has it in `dah-flink-dev`. Please grant the equivalent
> Role in QA: verbs `create, get, list, patch, delete` on
> `networkpolicies.networking.k8s.io`. File in scope:
> `apps/confluent-platform/qa/network-policy.yaml` — CFK operator ingress on
> Jolokia :7777 per runbook A14.

**Interim workaround**: `confluent-platform.yaml` now has an
`allowNpRbacForbidden` boolean parameter (default false). Setting it to
`true` on `install-or-update` runs makes the NetworkPolicy apply
warn-and-continue on Forbidden instead of exiting. Deploy proceeds but per
runbook A14 the CFK operator may hit ApplyFailed on Jolokia :7777 until
Container Platforms provisions the NP by other means. Use as a bridge only;
retire once RBAC lands.

**Clears when**: qa's Role is patched to include `networkpolicies.networking.k8s.io`
and a plain `install-or-update` (no bypass) succeeds. Delete this TODO section
at that point.
