# Wk2 Wed Q&A — Instructor Answer Key (LOCAL — do not commit yet)

> **Hold this back from engineers.** They should sit with each question, walk the diagrams, and produce their own answer before this is shared. Release this file to them only after the discussion (or after they've submitted their deliverable for Part 5).

---

## 1. Why is `9094` advertised as `broker0.kafka.example.com:9094` and not `kafka.example.com:9094` for all brokers?

Kafka's bootstrap → metadata handshake returns **per-broker advertised addresses** to the client. Each broker has to advertise its own reachable hostname. If all three brokers advertised the same `kafka.example.com:9094`, the client could connect (Round-robin) but couldn't address `broker-1 specifically` — produce requests for partitions whose leader is broker-1 would land randomly on broker-0 or broker-2 instead, and the broker would reject them as "not the leader." Per-broker hostnames + per-broker passthrough Routes (or per-broker Services in-cluster) give the client a unique TCP path to each broker.

**Walk diagram 4 (Broker Ingress Traffic) to see the per-broker Route fan-out.**

---

## 2. What's the difference between Edge, Re-encrypt, and Passthrough — and which one would you pick for Schema Registry's REST endpoint?

- **Edge** — router decrypts TLS, forwards plain HTTP (or unencrypted TCP) to the backend. Good for HTTPS UIs where the backend doesn't need to see the original TLS session. Backend cert is the *router's* cert.
- **Re-encrypt** — router decrypts TLS #1 (presenting the Route's cert), then opens TLS #2 to the backend (validating against `dest-ca-cert`). End-to-end encryption with two cert pairs. Good when backend requires TLS but doesn't need the original client cert.
- **Passthrough** — router never decrypts; uses SNI to route. Backend terminates TLS itself.

**For Schema Registry's REST endpoint**, pick **re-encrypt** if SR has a server cert and you want end-to-end TLS, or **edge** if SR speaks HTTP internally (common in dev). Don't use passthrough — SR is HTTP-shaped and passthrough is overkill (and loses the router's hostname-based routing flexibility). Match the diagram 3 inset: HTTPS UIs / REST APIs → edge or re-encrypt; Kafka broker listeners → passthrough.

---

## 3. The bootstrap connection works, but the producer logs say `Connection to broker1 (broker1.kafka.example.com:9094) failed`. What's the most likely cause, and which diagram do you walk first?

The advertised hostname for broker-1 specifically isn't reachable, even though one broker WAS reachable on bootstrap. Three most likely causes:

1. DNS for `broker1.kafka.example.com` doesn't resolve (per-broker A record missing in Route53).
2. The OpenShift Route for broker-1 doesn't exist, points at the wrong backend Service, or its passthrough TLS is misconfigured.
3. The `kafka-1-internal` ClusterIP Service has an empty EndpointSlice — broker-1 Pod isn't Ready, or the selector drifted.

**Walk diagram 4 first** — it traces the broker-specific path. Then diagram 1 (SG rules per hostname) and diagram 2 (observability — VPC Flow Logs to confirm packet reached the router; OCP Router metrics in Dynatrace to confirm a Route matched).

The diagnostic anti-pattern is checking the producer logs first. Producer logs only tell you which hop *failed* — not which hop *broke*.

---

## 4. A team requests `type: NodePort` for a new internal Kafka client because "it's easier than configuring DNS." What's wrong with that on a regulated OpenShift cluster?

Five things:

1. **NodePort exposes a port on every worker node.** That's a wider attack surface than a Route-fronted endpoint with named TLS.
2. **It bypasses Route/TLS governance.** No cert-manager-issued cert, no audit trail, no SNI-based routing.
3. **It bypasses Ingress Controller policy** — the enterprise OCP Router enforces rate limits, headers, and security policies that NodePort traffic never sees.
4. **High-port range (30000–32767)** doesn't match the standard cert/firewall posture. Each NodePort becomes a one-off SG rule.
5. **Cluster admission policy on enterprise OpenShift usually rejects NodePort entirely** — Gatekeeper / ValidatingWebhookConfigurations reject Services with `type: NodePort` for any namespace not explicitly allow-listed.

The team probably wants stable in-cluster addressing. The right answer is **ClusterIP Service + headless if they need per-pod DNS** (Kafka pattern), not NodePort.

---

## 5. Why does CFK never put broker Pods in a public subnet?

Two reasons:

1. **Security posture** — brokers carry the entire Kafka data path. Putting them in a public subnet means a single SG misconfiguration exposes the whole cluster to the internet. Defense-in-depth says: private subnets only, plus controlled ingress through LB + Router with explicit Routes.
2. **CFK isn't designed for it** — broker Pods don't get directly-routable public IPs. CFK assumes per-broker external access happens through Routes/LB at L7, not through Pod IPs at L3.

Walk diagram 1 — every workload (brokers, SR, Connect, C3, CMF) is inside the private-subnet zone. Only the LB + DNS + NAT Gateway sit in the public subnet.

---

## 6. Where does the `myapps.firstcitizens.com:443` egress dependency from broker Pods live in the picture — and which AWS object enforces that the dependency is reachable?

It's the **outbound** path from the broker Pod to the IdP (Okta), for OAuth/JWT verification on the 9092 SASL_SSL listener. Walk diagram 4's right side ("Broker outbound egress") and diagram 1.

Three AWS objects together enforce reachability:

1. **NAT Gateway** in the public subnet — translates the broker Pod's private IP to a public source for outbound traffic.
2. **Route Tables** in the private subnet — route `0.0.0.0/0` to the NAT Gateway.
3. **Security Group** on the worker nodes — must permit outbound to the IdP's hostname/IP on port 443.

If any of these is misconfigured (a private subnet without a NAT route, or an SG with too-narrow outbound rules), broker can't validate Okta tokens and the 9092 listener silently rejects every client.

---

## 7. The OpenShift Route has `tls.termination: edge`. Why would a Kafka broker behind that Route fail?

Three failures, in order of how the client experiences them:

1. **TLS terminates at the router** — broker never sees the original TLS session. Broker presents *no* cert to the client; the router's cert is what the client validates. mTLS client-cert validation impossible.
2. **Router speaks HTTP to the backend** by default in edge mode. The broker is expecting raw TCP / Kafka binary protocol, not HTTP. The bytes coming out of the router will look malformed to the broker.
3. **Even if you set up the broker to accept plain TCP**, OAuth tokens / mTLS certs in the metadata that Kafka clients need to validate identity would fail because the client and broker never see the same TLS session.

Kafka broker listeners require **passthrough**. The router only does SNI-based forwarding; the broker terminates TLS itself.

---

## 8. Reading image 2: which tool would you check FIRST if a producer says "TLS handshake reset" on connection to a broker? Which one second?

**First — VPC Flow Logs.** A TLS-handshake reset is a transport-level rejection. Before reading app logs, confirm the packet even got accepted at the network layer. If Flow Logs show REJECT for the broker port, the issue is SG/NACL, not TLS.

**Second — Dynatrace router metrics + OpenShift Console Route status.** Once you've confirmed the packet hit the cluster, check whether the OCP Router received the connection, whether the Route matched by SNI, and whether the backend Service has Endpoints. A TLS-handshake reset from the router (rather than the broker) means SNI didn't match or the backend cert isn't where the router expects it.

Only after both of those say "everything looks healthy at the network and router layer" do you go to Splunk / broker logs for cert content issues.

---

## 9. The 9092 listener carries SASL_SSL + OAuth. Where is the JWT verified — at the OCP Router, at the broker, or both?

**At the broker, exclusively.** The Router does TCP passthrough on 9092; it never decrypts the TLS session. The broker terminates TLS, reads the OAuthbearer SASL handshake, extracts the JWT, validates the signature against Okta's JWKS endpoint (which is the outbound egress dependency from question 6), and authenticates the client.

The Router has no opinion on the JWT — it forwards bytes. This is by design: the broker owns identity. (Compare to an edge-terminated HTTPS API where the router *could* enforce OAuth via a JWT-validating annotation; that's a different architecture and not how Kafka works.)

---

## 10. A new requirement comes in: expose Control Center UI externally over HTTPS. Walk through which OpenShift Route TLS mode you'd use and why.

**Edge termination** is the cleanest answer for the C3 UI:

- C3's UI is HTTP-shaped (HTTPS in the browser).
- The browser doesn't need to validate a broker-style cert; it validates the Route's cert.
- The C3 backend doesn't need to know about the original TLS session — it just serves HTML/JSON over HTTP.
- The router can terminate TLS with a cert-manager-issued cert, simplifying cert rotation (cert is on the Route, not on the C3 Pod).

**Re-encrypt** would also work if C3 has a server cert and you want end-to-end TLS, but it adds the complexity of managing the backend cert *and* the Route cert.

**Don't use passthrough.** The Router would have to forward by SNI, but the UI's hostname routing benefits from the Router seeing the request — you lose URL-path routing and Route-level annotations.

---

## 11. Describe the difference between the "advertised hostname" Kafka returns to the client and the in-cluster Service DNS name. Why does Kafka need both?

- **Advertised hostname** (in `advertised.listeners`) is what the broker tells **external clients** to use when they connect directly to that broker after the bootstrap → metadata handshake. Examples: `broker0.kafka.example.com:9094` for external mTLS, `kafka-0.kafka.kafka-dev.svc.cluster.local:9092` for in-cluster.
- **In-cluster Service DNS name** is what **in-cluster callers** (Connect, Schema Registry, CMF, other K8s workloads) use. The headless `kafka` Service returns per-pod A records; per-pod ClusterIP Services like `kafka-0-internal` return stable VIPs.

Kafka needs both because **clients reach brokers via different paths depending on where they are**:

- An external producer over the public Route uses `broker0.kafka.example.com:9094`.
- An in-cluster Connect worker uses `kafka.kafka-dev.svc.cluster.local:9071` for bootstrap and follows `kafka-0.kafka.kafka-dev.svc.cluster.local:9092` for direct broker addressing.

The broker has to advertise both, scoped per-listener. The `INTERNAL://` advertised value matches in-cluster DNS; the `CERTONLY://` advertised value matches the external Route hostname.

---

## 12. If VPC Flow Logs show `ACCEPT` for the bootstrap packet but the Route status says no backend, where did the packet stop — and which next tool would isolate it?

The packet **made it past the SG/NACL layer to the LB and onward to the OCP Router**, but the Router didn't find a matching backend with healthy Endpoints. That puts the failure at the **Service / EndpointSlice layer** of the in-cluster path.

Next tools:

1. **OpenShift Console** — Route status, Service endpoints view.
2. **`oc get endpointslice -l kubernetes.io/service-name=<service>`** — confirm Endpoints aren't empty.
3. **`oc get pods -l <selector> -o wide`** — confirm Pods are Ready (readiness probe passing).

Common causes: selector mismatch (Service selects `app: kafka` but Pods have `app: kafka-broker`), readiness probe failing silently, Service `targetPort` doesn't match `containerPort` name.

The triage rule: ACCEPT in Flow Logs + no backend at Route = look at the **in-cluster** path next, not at the network. Walk diagram R1 (Pod → Service path) and the EndpointSlice check from Wk1 Wed lab.

---

## Release plan

When ready to share these answers with engineers:

1. Wait until they've submitted their Part 5 deliverable answers to the three observability scenarios.
2. Either commit this file alongside the next training-material update, OR share as a private PDF/handout (depends on whether engineers will reference it later).
3. If committing, drop the `INSTRUCTOR-ONLY` from the filename — at that point it's just `Q-AND-A-ANSWERS.md`.
