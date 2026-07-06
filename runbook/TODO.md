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
