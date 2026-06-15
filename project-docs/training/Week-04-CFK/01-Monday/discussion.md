# Monday — CFK Architecture

**Time**: ~90 min
**Diagram**: [`40-cfk-network.drawio`](40-cfk-network.drawio) — the canonical canonical CFK network diagram

## Learning objective

> **What does CFK actually deploy when you apply a Kafka CR?** And how do the Confluent components fit together — broker, Schema Registry, Connect, REST Proxy, Control Center?

## Architecture Discussion (~45 min)

CFK = Confluent for Kubernetes. It's an Operator (Week 2 Tuesday pattern) that takes Custom Resources for each Confluent Platform component and reconciles them into running StatefulSets / Deployments / Services.

### The five Confluent components

Walk the diagram top-to-bottom:

- **Kafka brokers** — the heart. StatefulSet, identity-preserving (Week 1 Tuesday). In production this is 3 brokers per cluster with KRaftController as the metadata layer.
- **KRaftController** — replaces ZooKeeper. Manages cluster metadata: topics, ACLs, controller elections. Apache Kafka 4.0 removed ZK entirely; CFK 3.x is KRaft-only. Its PVCs need the operator update/patch verbs (tracker 2.3 / RITM1093307).
- **Schema Registry (SR)** — HTTP service holding Avro / Protobuf / JSON-Schema schemas with compatibility checks. Producers + consumers register / lookup schemas by name; the broker doesn't care about schemas itself.
- **Connect** — distributed framework for source + sink connectors (JDBC, S3, Elasticsearch, ...). In production primarily used for moving data between Kafka and external systems. Workers are stateless; offsets stored in internal Kafka topics.
- **Kafka REST Proxy (KRP)** — HTTP gateway for produce/consume from clients that don't speak the Kafka wire protocol (browsers, FaaS).
- **Control Center (C3)** — web UI for admins. Reads metrics from JMX + Kafka itself. Not load-bearing in the data path.

### How CFK glues them together

For each component, the operator emits:
- A **StatefulSet** (for Kafka + KRaftController) or **Deployment** (for SR + Connect + KRP + C3)
- One or more **Services** (cluster-internal for Pod-to-Pod; external load balancer per the Kafka CR's `externalAccess` block)
- **ConfigMaps + Secrets** holding broker.properties + TLS certs + OAuth credentials
- **PVCs** (for stateful components)

You don't apply any of these directly. You apply a `Kafka` CR + a `SchemaRegistry` CR + a `Connect` CR; the operator does the rest. This is the Week 2 Tuesday pattern in action.

### CFK on production OpenShift — the specific constraints

The site-specific bits engineers must know (read `runbook/LESSONS_LEARNED.md`):

- **CFK 3.1.2 / preview-2 build** is the version the platform runs. Stock CFK 3.1.0 has site-incompatible defaults (`project_cmf_image_tag`).
- **CRD limitations** (runbook A2, A3): no `startupProbe`, no `initContainers` override. Default init container has ~500m CPU floor that becomes the pod-effective minimum.
- **ResourceQuota** (tracker 2.5 / runbook A3): 6 CFK Pods × ~500m init CPU = ~3 CPU minimum. DEV's original 2-CPU quota fit only 4 pods.
- **OAuth integration** (tracker 2.9): Kafka broker SASL_SSL listener authenticates clients via Okta tokens. Operator OAuth flow vs end-user OAuth (Week 3 Tuesday) — different grant types, same trust.
- **External access patterns** (tracker 2.10): native ports 9092 (OAuth) + 9094 (mTLS) for brokers; HAProxy Ingress 443 for HTTP services. The 9094 case needs the policy exception.

### What's NOT CFK — the boundary

CFK does NOT manage:
- The K8s cluster itself (that's ROSA / OpenShift)
- Storage provisioning (that's the CSI driver via StorageClass)
- TLS certs (that's cert-manager + Keyfactor)
- Secrets (that's ESO + CyberArk)
- Workload monitoring (Prometheus / Grafana, but CFK does emit JMX metrics for them to scrape)

CFK is a thin layer that orchestrates Confluent components on top of K8s primitives.

## Diagram Walkthrough (~30 min)

Open `40-cfk-network.drawio` — the diagram from the Rick walk. Trace each Confluent component:
- Where it sits inside the OCP cluster
- What other components it talks to (broker ↔ SR, broker ↔ Connect, etc.)
- What external systems it reaches (Okta, NetApp S3, VM CP brokers during migration)
- Which firewall rule each connection depends on

## Failure Scenarios — preview the week

| Symptom | Where to look |
|---|---|
| `kafka` CR applied; no Pods come up | CFK operator logs; operator's RBAC (tracker 2.3) |
| Pods come up but `cluster-ready=False` | CR status conditions; usually operator missing a verb |
| Broker can't get OAuth token | tracker 2.9 — Okta egress; trust bundle (2.8) |
| Cross-component (broker → SR → Connect → C3) auth chain broken | per-listener SSL config; SASL inheritance |
| Cluster-link source can't reach destination | tracker 2.10 — broker 9094 mTLS port |

## Q&A

1. Why does CFK use a StatefulSet for brokers and a Deployment for Schema Registry?
2. If you delete the `Kafka` CR, what happens to broker PVCs? (Hint: ownerReferences + reclaimPolicy)
3. How does the operator know which CFK image tag to deploy?
4. What's the difference between the operator's RBAC and each broker Pod's RBAC?
5. In production, name three OpenShift-side prerequisites that must be in place BEFORE a CFK install will succeed.


## Added Enhancement — CFK Reconciliation Deep Dive

Most production troubleshooting starts with understanding reconciliation.

Flow:

Kafka CR
  -> CFK Operator
  -> StatefulSets
  -> Services
  -> PVCs
  -> Pods

Required commands:

```bash
oc get kafka
oc describe kafka <cluster>
oc get events -A
oc logs deployment/confluent-operator
```

Failure Scenario:
A Kafka CR exists but brokers never appear.
Students must identify where reconciliation failed.
