# DEV: Kafka brokers through TLS passthrough on 443

Status: IMPLEMENTED in DEV manifests 2026-10-01 (trial; Rick's agreement needed before QA).
Design and caveats: `runbook/LESSONS_LEARNED.md` H10.

What changed in `apps/confluent-platform/dev/`:

| File | Change |
|---|---|
| `kafka.yaml` | new `custom` listener `client` (9093, OAuth, `kafka-tls`) with `externalAccess: staticForHostBasedRouting` on `apps.dv-p.ocp.fcbint.net:443`, `brokerPrefix: kafka-`; validator chain mirrored for `listener.name.client` |
| `cert-manager/kafka-tls-certificate.yaml` | SANs `kafka-client.apps.dv-p…`, `kafka-{0,1,2}.apps.dv-p…`, `kafka-client-{0,1,2}.apps.dv-p…` |
| `network-policy/network-policy.yaml` | routers (`openshift-ingress`) may reach 9093 |
| `ingress/kafka-client-passthrough.yaml.tmpl` | rendered per endpoint by `.azure-pipelines/scripts/kafka-passthrough.sh` at install time |

Rollout order for DEV: `confluent-platform.yaml` `install-or-update` with **Kafka Broker** ticked
(rolls brokers once for the SAN reissue + new listener), then `validate-confluent-platform.yaml`.
The install log ends with the client bootstrap string to hand to application teams.

Why not `externalAccess` on `external:9092`: SR / Connect / REST / C3 bootstrap there; router-side
advertised names would hairpin all in-cluster traffic through HAProxy.
