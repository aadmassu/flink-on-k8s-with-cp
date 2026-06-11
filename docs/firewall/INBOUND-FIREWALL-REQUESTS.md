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
| Kafka broker (mTLS, `certonly` listener) | same broker hostnames as above | 9094 | mTLS-authenticated wire protocol for cert-only clients (incl. cluster-link source) |
| Schema Registry | `schemaregistry.apps.<env>.ocp.fcbint.net` | 8081 | Schema register / lookup over HTTPS |
| Kafka REST Proxy | `kafkarest.apps.<env>.ocp.fcbint.net` | 8082 | HTTP producer / consumer for browser / FaaS clients |
| Kafka Connect | `connect.apps.<env>.ocp.fcbint.net` | 8083 | Connector REST API |
| MDS (embedded in broker) | `kafka-mds.apps.<env>.ocp.fcbint.net` | 8090 | OAuth tokens, RBAC, principal mapping |
| Control Center | `controlcenter.apps.<env>.ocp.fcbint.net` | 9021 | C3 web UI |

Broker hostnames re-use the VM CP domain (`kafka.<env>.dah.fcbint.net`) so
existing producer / consumer configs point at the same FQDN before and after
switchover. The other CFK components use the OCP cluster's apps domain
(`<svc>.apps.<env>.ocp.fcbint.net`).

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
| Producer / consumer clients running on VMs | App / VM zone | Kafka 9092 / 9094, Schema Registry 8081 |
| Cluster-link source broker (VM CP → CFK migration) | VM CP broker host IPs | Kafka 9092 / 9094 |
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
