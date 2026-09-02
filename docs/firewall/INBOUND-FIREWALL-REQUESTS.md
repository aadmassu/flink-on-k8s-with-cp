# Inbound Firewall Requests — CFK + Flink native ports

Single source of truth for the **inbound** firewall-rule asks needed to expose
the CFK + Flink + CMF stack on OpenShift to non-pod-network clients
(producers, consumers, browser/admin access, cluster-link source brokers).

Companion: [OUTBOUND-FIREWALL-REQUESTS.md](OUTBOUND-FIREWALL-REQUESTS.md) lists
the egress destinations the same pods need to reach.

## Rule of thumb

Ask FCB Security to allow inbound traffic to the **native product ports**
documented by Confluent and Apache Flink — **not** the OpenShift Ingress
port (TCP/443). The native-port ask is what lets producer / consumer / admin
clients at FCB switch from VM CP to CFK without reconfiguring URLs or ports.

References:

- Confluent system requirements (ports): https://docs.confluent.io/platform/current/installation/system-requirements.html#ports
- Apache Flink — JobManager REST + Web Dashboard: TCP/8081
- Confluent Manager for Flink (CMF) — REST API + UI: TCP/8080

## CFK component ports

| Service | Eventual DNS name | Port | Description |
|---|---|---|---|
| Kafka broker (SASL_SSL / OAuth) | `bootstrap.kafka.<env>.dah.fcbint.net` and `b0.kafka.<env>.dah.fcbint.net` / `b1...` / `b2...` | 9092 | Producer / consumer wire protocol; OAuth via Okta |
| Kafka broker (mTLS, `certonly` listener) — bind port | same broker hostnames as above | 9094 | mTLS-authenticated wire protocol for cert-only clients (incl. cluster-link source) |
| Kafka broker (mTLS, `certonly` listener) — **advertised** via F5 | `broker0{1,2,3}.dah-kafka-{pdc,sdc}.firstcitizens.com` | **7055** | F5 VIP port presented to the FIS partner; the F5 translates to 9094 on the brokers. Not a broker port — see the section below |
| Schema Registry | `schemaregistry.apps.<env>.ocp.fcbint.net` | 8081 | Schema register / lookup over HTTPS |
| Kafka REST Proxy | `kafkarest.apps.<env>.ocp.fcbint.net` | 8082 | HTTP producer / consumer for browser / FaaS clients |
| Kafka Connect | `connect.apps.<env>.ocp.fcbint.net` | 8083 | Connector REST API |
| MDS (embedded in broker) | `kafka-mds.apps.<env>.ocp.fcbint.net` | 8090 | OAuth tokens, RBAC, principal mapping |
| Control Center | `controlcenter.apps.<env>.ocp.fcbint.net` | 9021 | C3 web UI |

Broker hostnames re-use the VM CP domain (`kafka.<env>.dah.fcbint.net`) so
existing producer / consumer configs point at the same FQDN before and after
switchover. The other CFK components use the OCP cluster's apps domain
(`<svc>.apps.<env>.ocp.fcbint.net`).

### certonly / 7055 — partner traffic through the F5, not a broker port

Confirmed against the FCB VM network architecture diagram (held locally in
`project-docs/diagrams/`). **7055 is an F5 VIP port.** The brokers bind 9094;
the F5 presents 7055 to the partner and translates. So the inbound ask has two
distinct legs, with different sources:

| Leg | Source | Destination | Port |
|---|---|---|---|
| Partner → perimeter | FIS partner connection (external) | public VIPs 69.89.143.28-30 (PDC) / 69.89.156.28-30 (SDC) | 7055 |
| F5 → brokers | F5 VIP 10.0.192.196-198 (PDC) / 10.208.4.36-38 (SDC) | CFK broker pods, `certonly` listener | 9094 |

This corrects the earlier framing on this page, which treated 7055 as a broker
port reachable from the App / VM zone. It is neither: the source is an external
partner, and only the F5 ever talks to 9094.

**Migration action is on the F5, not the firewall.** Re-pointing the F5 pool
members from the VM brokers to the CFK brokers preserves the partner's DNS
name, VIP and port unchanged. What is genuinely new for the firewall is only
the second leg — F5 VIPs reaching the CFK broker pods on 9094.

Still to settle before filing (see `../LISTENER_PORT_MATRIX.md`):

- **Advertised names.** CFK emits `broker0/1/2` from 0-indexed broker IDs where
  the partner expects `broker01/02/03`. Resolved by adding DNS records for the
  CFK-advertised names against the same three VIPs — partner config untouched —
  then adding those names as SANs on the broker certificate.
- **Whether the F5 terminates or passes through mTLS.** Determines the
  principal the broker actually authenticates and therefore the `certonly`
  listener's `principalMappingRules`.

## Flink component ports

| Service | Eventual DNS name | Port | Description |
|---|---|---|---|
| Confluent Manager for Flink (CMF) | `cmf.apps.<env>.ocp.fcbint.net` | 8080 | CMF REST API + Web UI; outward-facing client port |
| Flink JobManager (per FlinkApplication) | `<job>.flink.apps.<env>.ocp.fcbint.net` | 8081 | JobManager REST + Web Dashboard; one DNS entry per Flink job |

`<job>` is the FlinkApplication name (e.g. `aep-rate-limit-job`). Each running
job has its own DNS entry; the same TCP/8081 rule covers all jobs in the env.

## Source zones — the "from" side of each rule

| Traffic pattern | Source zone | Ports to allow |
|---|---|---|
| Producer / consumer clients running on VMs | App / VM zone | Kafka 9092, Schema Registry 8081 |
| Cluster-link source broker (VM CP → CFK migration) | VM CP broker host IPs | Kafka 9092 / 9094 |
| Partner mTLS (FIS) via F5 | F5 VIPs 10.0.192.196-198 (PDC) / 10.208.4.36-38 (SDC) | Kafka 9094 (`certonly`) |
| Browser / admin access | User Zone | C3 9021, Connect 8083, Kafka REST 8082, MDS 8090, CMF 8080, Flink JM 8081 |

Tushar (kafka admin) supplies the exact App / VM zone CIDRs and VM CP broker
host IPs; FCB Security supplies the User Zone CIDR list, before each per-env
firewall request is filed.

## Load Balancer IPs per env

The destination side of every rule, from the FCB OpenShift Ingress Confluence
page (https://confluence.fcpd.fcbint.net/spaces/CONV/pages/172530278/OpenShift+Ingress):

| Env | LB IP |
|---|---|
| DEV | 10.7.72.209 |
| QA | 10.7.72.212 |
| UAT-P | 10.7.72.215 |
| UAT-S | 10.7.72.218 |
| PRD-P | 10.0.192.194 |
| PRD-S | 10.208.4.34 |

## Implementation note (separate from this firewall ask)

This document captures the firewall request scope — the native ports inbound
traffic should be allowed to. It is intentionally independent of *how*
OpenShift exposes those ports externally on the cluster side. That decision
is a separate piece of work and may involve:

- LoadBalancer Services (already declared on the Kafka CR via
  `externalAccess.type: loadBalancer`; for the HTTP components this requires
  a policy exception against the FCB ClusterIP-only standard)
- NodePort Services
- OpenShift Routes with TLS passthrough
- An external HAProxy / F5 perimeter proxy

Tracker 2.10 in [`../ISSUE-TRACKER.md`](../ISSUE-TRACKER.md) is the consolidated action item; the
implementation choice (and any associated standards exceptions) is documented
there and confirmed with Container team before each env's CFK install.
