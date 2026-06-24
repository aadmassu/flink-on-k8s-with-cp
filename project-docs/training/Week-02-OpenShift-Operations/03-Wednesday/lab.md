# Week 2 Wednesday — Lab: OpenShift Network Architecture (hands-on)

## Goal

Walk every layer of the discussion in your own terminal:

1. **Part 1** — Service mechanics in-cluster: Pod → ClusterIP → EndpointSlice → kube-proxy → Pod (recap of R1).
2. **Part 2** — Service-type ladder: ClusterIP vs NodePort vs LoadBalancer (recap of R2). Verify why production OpenShift usually rejects NodePort.
3. **Part 3** — Ingress / OpenShift Route + the three TLS termination modes (recap of R3 + discussion image 3). Edge / re-encrypt / passthrough demonstrated end-to-end.
4. **Part 4** — Kafka broker ingress against the `lab-cluster/` CFK install (discussion image 4). Bootstrap → metadata → direct-broker handshake observed by hand.
5. **Part 5** — Cloud-layer concepts (read-through). ROSA VPC, NAT, SG, observability hops. You can't replicate this on a laptop; you can map it.

Every command is given in both `oc` and `kubectl` forms. Run only the one that matches the cluster you started in.

## Pick your local cluster

The kind training cluster you (re)built last Friday — `lab-cluster/` — is the easiest target. It already has Kafka running in `kafka-dev`, which Part 4 uses directly.

```bash
# kind
kind get clusters                          # expect: training
kubectl config use-context kind-training

# oc / OpenShift Local (CRC) / any oc-connected cluster
oc whoami --show-server                    # confirm you're on the right cluster
```

> **On kind**, OpenShift Routes do not exist (no Route CRD). Part 3 substitutes a vanilla `Ingress` for the kind path and explains where Route would differ. The OCP-only sections in Part 3 are clearly marked.

If you're on kind, give yourself a fresh namespace for Parts 1–3:

```bash
# kubectl
kubectl create namespace netlab --dry-run=client -o yaml | kubectl apply -f -
kubectl config set-context --current --namespace=netlab

# oc
oc new-project netlab || oc project netlab
```

---

## Part 1 — Service mechanics: Pod → ClusterIP → EndpointSlice → kube-proxy

Anchors discussion image **R1**.

### 1.1 Deploy a 3-replica app with a ClusterIP Service

```bash
# kubectl
kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hello
  labels: {app: hello}
spec:
  replicas: 3
  selector:
    matchLabels: {app: hello}
  template:
    metadata:
      labels: {app: hello}
    spec:
      containers:
        - name: hello
          image: hashicorp/http-echo:1.0
          args: ["-text=hello from POD"]
          ports: [{containerPort: 5678, name: http}]
          readinessProbe:
            httpGet: {path: /, port: 5678}
            periodSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: hello
spec:
  selector: {app: hello}
  ports:
    - {name: http, port: 80, targetPort: 5678}
EOF

# oc — same manifest, swap kubectl for oc
oc apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hello
  labels: {app: hello}
spec:
  replicas: 3
  selector:
    matchLabels: {app: hello}
  template:
    metadata:
      labels: {app: hello}
    spec:
      containers:
        - name: hello
          image: hashicorp/http-echo:1.0
          args: ["-text=hello from POD"]
          ports: [{containerPort: 5678, name: http}]
          readinessProbe:
            httpGet: {path: /, port: 5678}
            periodSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: hello
spec:
  selector: {app: hello}
  ports:
    - {name: http, port: 80, targetPort: 5678}
EOF
```

### 1.2 Inspect every layer of the chain

```bash
# kubectl
kubectl wait --for=condition=Available deployment/hello --timeout=60s
kubectl get pods -l app=hello -o wide
kubectl get svc hello
kubectl get endpointslice -l kubernetes.io/service-name=hello

# oc
oc wait --for=condition=Available deployment/hello --timeout=60s
oc get pods -l app=hello -o wide
oc get svc hello
oc get endpointslice -l kubernetes.io/service-name=hello
```

**What you should see**: three Pods Ready, a Service with a `ClusterIP` like `10.96.x.x`, and an EndpointSlice listing exactly three Pod IPs + their port. That's the diagram, live.

### 1.3 Verify DNS resolution from inside the cluster

Run a one-shot debug Pod that lives only for the DNS lookup:

```bash
# kubectl
kubectl run dns-probe --rm -it --restart=Never --image=busybox:1.36 -- \
  nslookup hello.netlab.svc.cluster.local

# oc
oc run dns-probe --rm -it --restart=Never --image=busybox:1.36 -- \
  nslookup hello.netlab.svc.cluster.local
```

`nslookup` should return the Service's ClusterIP. That ClusterIP is what kube-proxy's iptables/IPVS rules DNAT to a real Pod IP.

### 1.4 Hit the Service from another Pod

```bash
# kubectl
kubectl run client --rm -it --restart=Never --image=busybox:1.36 -- \
  sh -c 'for i in 1 2 3 4 5; do wget -qO- http://hello.netlab.svc.cluster.local/; echo; done'

# oc
oc run client --rm -it --restart=Never --image=busybox:1.36 -- \
  sh -c 'for i in 1 2 3 4 5; do wget -qO- http://hello.netlab.svc.cluster.local/; echo; done'
```

Five times you should see `hello from POD`. Each request lands on a random backend Pod (kube-proxy round-robins).

### 1.5 Break it — Service selector mismatch → empty EndpointSlice

```bash
# kubectl
kubectl patch svc hello -p '{"spec":{"selector":{"app":"hello-typo"}}}'
kubectl get endpointslice -l kubernetes.io/service-name=hello
kubectl run client --rm -it --restart=Never --image=busybox:1.36 -- \
  wget --timeout=3 -qO- http://hello.netlab.svc.cluster.local/ ; echo "exit=$?"

# oc
oc patch svc hello -p '{"spec":{"selector":{"app":"hello-typo"}}}'
oc get endpointslice -l kubernetes.io/service-name=hello
oc run client --rm -it --restart=Never --image=busybox:1.36 -- \
  wget --timeout=3 -qO- http://hello.netlab.svc.cluster.local/ ; echo "exit=$?"
```

**What you should observe**: the EndpointSlice's `endpoints:` array is now empty. DNS still resolves the Service to a ClusterIP (the ClusterIP is owned by the Service, not the EndpointSlice). But there's nothing to route to — `wget` times out. This is **the most common CFK Service failure mode**: Service exists, ClusterIP looks healthy, app is just unreachable.

Fix it:

```bash
# kubectl
kubectl patch svc hello -p '{"spec":{"selector":{"app":"hello"}}}'

# oc
oc patch svc hello -p '{"spec":{"selector":{"app":"hello"}}}'
```

### 1.6 Break it — readiness probe failing → Pod silently removed from rotation

```bash
# kubectl
kubectl set probe deployment/hello --readiness --get-url=http://:5678/nowhere
sleep 15
kubectl get pods -l app=hello -o custom-columns='NAME:.metadata.name,READY:.status.conditions[?(@.type=="Ready")].status'
kubectl get endpointslice -l kubernetes.io/service-name=hello \
  -o jsonpath='{.items[*].endpoints[*].addresses}' ; echo

# oc
oc set probe deployment/hello --readiness --get-url=http://:5678/nowhere
sleep 15
oc get pods -l app=hello -o custom-columns='NAME:.metadata.name,READY:.status.conditions[?(@.type=="Ready")].status'
oc get endpointslice -l kubernetes.io/service-name=hello \
  -o jsonpath='{.items[*].endpoints[*].addresses}' ; echo
```

**What you should observe**: Pods are `Running` but **not Ready**, so they fall out of the EndpointSlice. Same `wget` failure as 1.5, but the Pod count is "fine."

Fix:

```bash
# kubectl
kubectl set probe deployment/hello --readiness --remove

# oc
oc set probe deployment/hello --readiness --remove
```

---

## Part 2 — Service types: ClusterIP, NodePort, LoadBalancer

Anchors discussion image **R2**.

### 2.1 Switch the existing Service to NodePort

```bash
# kubectl
kubectl patch svc hello -p '{"spec":{"type":"NodePort"}}'
kubectl get svc hello

# oc
oc patch svc hello -p '{"spec":{"type":"NodePort"}}'
oc get svc hello
```

You should see a `NodePort` column with a random high port (30000–32767). On kind, that port is bound on every kind node container. You can reach it from inside the cluster via `kind-control-plane:NODEPORT`, but **not** from your Mac/Linux host without an extra `kind` port-mapping in the cluster config — by design, kind keeps node ports private.

### 2.2 Try LoadBalancer (expect EXTERNAL-IP `<pending>` on kind)

```bash
# kubectl
kubectl patch svc hello -p '{"spec":{"type":"LoadBalancer"}}'
kubectl get svc hello -w &
sleep 5; kill %1 2>/dev/null

# oc
oc patch svc hello -p '{"spec":{"type":"LoadBalancer"}}'
oc get svc hello -w &
sleep 5; kill %1 2>/dev/null
```

**On kind / on-prem OCP with no LB controller**: `EXTERNAL-IP` stays `<pending>` forever. There's no cloud LB to allocate. On ROSA / EKS, this would provision a real ELB/NLB in seconds.

### 2.3 Reset the Service back to ClusterIP

```bash
# kubectl
kubectl patch svc hello --type=json -p='[{"op":"replace","path":"/spec/type","value":"ClusterIP"},{"op":"remove","path":"/spec/ports/0/nodePort"}]'
kubectl get svc hello

# oc
oc patch svc hello --type=json -p='[{"op":"replace","path":"/spec/type","value":"ClusterIP"},{"op":"remove","path":"/spec/ports/0/nodePort"}]'
oc get svc hello
```

### 2.4 Observation question (write up in your deliverable)

Engineering admission policy on enterprise OpenShift usually rejects `type: NodePort`. Knowing what you just saw:

- Why is that rejection sensible from a security / governance perspective?
- What does a team **actually** want when they ask for NodePort? Walk through which standard alternative (Service-only, Route, Ingress, headless+per-pod Services for Kafka) fits each likely use case.

---

## Part 3 — Ingress and OpenShift Route + TLS termination modes

Anchors discussion image **R3** and image **3** (TLS-Encryption.png).

This part **diverges between kind and OCP**. Run only the path that matches your cluster.

### 3a — kind path (Ingress via NGINX Ingress Controller)

kind has no Routes. If you want to see the Ingress side of things, install the NGINX Ingress Controller. Skip if you've already done this in Wk1 Wed lab.

```bash
# kubectl — install NGINX Ingress (kind-friendly variant)
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
kubectl wait --namespace ingress-nginx \
  --for=condition=Ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s
```

Then expose the `hello` Service via an Ingress:

```bash
# kubectl
kubectl apply -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: hello
spec:
  ingressClassName: nginx
  rules:
    - host: hello.lab.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: hello
                port:
                  number: 80
EOF

# Inspect the Ingress LB external IP (often <none> on kind unless a LoadBalancer extension is installed)
kubectl get svc -n ingress-nginx ingress-nginx-controller
```

If the EXTERNAL-IP column shows `<pending>` or `<none>`, your kind install lacks the LoadBalancer extension; in that case, port-forward instead:

```bash
# kubectl
kubectl -n ingress-nginx port-forward svc/ingress-nginx-controller 8080:80 &
sleep 2
curl -sH 'Host: hello.lab.local' http://localhost:8080/
kill %1
```

Now you've exercised the **Ingress object + Ingress Controller** split from R3. Cleanup:

```bash
kubectl delete ingress hello
```

### 3b — OCP path (Routes with all three TLS termination modes)

> **OCP-only**: requires an OCP cluster (CRC, ROSA, on-prem OCP). The OCP Router is part of the cluster — no install step needed.

You're going to expose `hello` three times, once with each TLS mode. Each Route gets a different hostname for clarity.

First, you need a TLS cert to terminate against. For the lab, generate a self-signed cert. (On a real cluster you'd use cert-manager backed by your enterprise PKI.)

```bash
openssl req -x509 -newkey rsa:2048 -days 1 -nodes \
  -subj "/CN=hello.apps.example.com" \
  -keyout /tmp/route-tls.key -out /tmp/route-tls.crt 2>/dev/null
```

#### Edge termination

Router decrypts TLS, sends HTTP to backend.

```bash
# oc
oc create route edge hello-edge --service=hello --hostname=hello-edge.apps.$(oc whoami --show-server | sed 's|.*api\.||' | sed 's|:.*||') \
  --cert=/tmp/route-tls.crt --key=/tmp/route-tls.key
oc get route hello-edge
curl -k https://$(oc get route hello-edge -o jsonpath='{.spec.host}')/
```

You should see `hello from POD`. TLS terminates at the router; the backend Pod receives plain HTTP.

#### Re-encrypt termination

Router decrypts, then opens a NEW TLS session to the backend. Requires a backend that speaks TLS — `hello-echo` doesn't, so this is mostly read-through unless you stand up a TLS-capable echo. The `oc create route reencrypt` command needs `--dest-ca-cert` pointing at the cert the backend presents:

```bash
# oc (reference only — backend hello-echo doesn't speak TLS)
# oc create route reencrypt hello-reenc --service=hello \
#   --hostname=hello-reenc.apps.example.com \
#   --cert=/tmp/route-tls.crt --key=/tmp/route-tls.key \
#   --dest-ca-cert=/tmp/backend-ca.crt
```

When you're ready to exercise this for real, deploy an nginx Pod with its own TLS cert and re-encrypt to it. Saves the experiment for the Kafka surface in Part 4.

#### Passthrough termination

Router does NOT decrypt. Backend terminates TLS. Required for Kafka broker listeners.

```bash
# oc — passthrough Route to a TLS-terminating Service
# Will fail until you have a Service whose Pods speak TLS. Reference syntax:
# oc create route passthrough hello-pt --service=hello-tls \
#   --hostname=hello-pt.apps.example.com
```

The Route definition has **no cert fields** for passthrough — the cert lives on the Pod. The router routes purely by SNI hostname. Cleanup of edge route:

```bash
oc delete route hello-edge
```

### 3c — Discussion check (both paths)

Whichever path you ran, you can now answer:

- When a client connects to an OpenShift Route, which object holds the public cert? (Edge / re-encrypt: the Route. Passthrough: the backend Pod.)
- Why can't a Kafka broker be put behind an `edge` Route? (Broker must terminate TLS itself; client cert (mTLS) needs to reach the broker, not the router.)
- What's the difference between an Ingress object and an Ingress Controller pod? (Object = declarative rules. Controller = the running proxy that listens on `:80`/`:443`.)

---

## Part 4 — Kafka broker ingress (hands-on, uses the lab-cluster CFK install)

Anchors discussion image **4** (Broker Ingress Traffic.png).

The lab-cluster you rebuilt Friday has Kafka running in `kafka-dev`. We'll talk to it the way real producer/consumer clients do — bootstrap → metadata → direct broker — and see why a single HTTP-style front hostname can't work for Kafka.

### 4.1 Confirm the lab-cluster Kafka is up

```bash
# kubectl
kubectl -n kafka-dev get kafka,sts,svc,pods -l app=kafka

# oc
oc -n kafka-dev get kafka,sts,svc,pods -l app=kafka
```

Expect: Kafka CR `RUNNING`, StatefulSet 3/3, three pods (kafka-0/1/2), a headless `kafka` Service, and three per-pod Services `kafka-0-internal` / `kafka-1-internal` / `kafka-2-internal`.

### 4.2 List topics via the bootstrap server

```bash
# kubectl
kubectl -n kafka-dev exec kafka-0 -- \
  kafka-topics --bootstrap-server kafka.kafka-dev.svc.cluster.local:9071 --list

# oc
oc -n kafka-dev exec kafka-0 -- \
  kafka-topics --bootstrap-server kafka.kafka-dev.svc.cluster.local:9071 --list
```

This call performs the same handshake any real client does:
1. TCP connect to the bootstrap (`kafka.kafka-dev.svc.cluster.local:9071`, the inter-broker listener inside the cluster).
2. Broker sends back cluster metadata, including each broker's advertised hostname and port.
3. Client opens direct TCP sessions to each broker at the advertised address.

### 4.3 Observe the per-broker DNS that Kafka relies on

Since the `kafka` Service is **headless** (`clusterIP: None`), DNS doesn't return a single VIP — it returns **one A record per broker pod**.

```bash
# kubectl
kubectl -n kafka-dev run dns-probe --rm -it --restart=Never --image=busybox:1.36 -- \
  nslookup kafka.kafka-dev.svc.cluster.local

# oc
oc -n kafka-dev run dns-probe --rm -it --restart=Never --image=busybox:1.36 -- \
  nslookup kafka.kafka-dev.svc.cluster.local
```

You should see **three Addresses**, one per broker Pod IP. This is the in-cluster mirror of what advertised.listeners does for external clients — one address per broker, not one front-door VIP.

### 4.4 Inspect the broker's advertised listeners

Look at what the broker would tell a client about itself:

```bash
# kubectl
kubectl -n kafka-dev exec kafka-0 -- bash -c '
  cat /mnt/config/server.properties 2>/dev/null \
    | grep -E "^(listeners|advertised\.listeners|listener\.security\.protocol\.map|inter\.broker\.listener\.name)=" \
  || cat /etc/kafka/kafka.properties 2>/dev/null \
    | grep -E "^(listeners|advertised\.listeners|listener\.security\.protocol\.map|inter\.broker\.listener\.name)="
'

# oc
oc -n kafka-dev exec kafka-0 -- bash -c '
  cat /mnt/config/server.properties 2>/dev/null \
    | grep -E "^(listeners|advertised\.listeners|listener\.security\.protocol\.map|inter\.broker\.listener\.name)=" \
  || cat /etc/kafka/kafka.properties 2>/dev/null \
    | grep -E "^(listeners|advertised\.listeners|listener\.security\.protocol\.map|inter\.broker\.listener\.name)="
'
```

Path differs by CFK version; the grep tries both. You should see lines like:

```
listeners=INTERNAL://0.0.0.0:9092,BROKER://0.0.0.0:9071,...
advertised.listeners=INTERNAL://kafka-0.kafka.kafka-dev.svc.cluster.local:9092,BROKER://kafka-0.kafka.kafka-dev.svc.cluster.local:9071,...
listener.security.protocol.map=INTERNAL:PLAINTEXT,BROKER:PLAINTEXT,...
inter.broker.listener.name=BROKER
```

**Key observation**: every broker advertises **its own per-pod hostname**. Not the headless Service DNS. The Service DNS resolves to per-pod A records; the advertised listener uses the per-pod stable hostname. Both pieces have to work for a client to reach a specific broker.

### 4.5 Create and produce to a topic

```bash
# kubectl
kubectl -n kafka-dev exec kafka-0 -- \
  kafka-topics --bootstrap-server kafka.kafka-dev.svc.cluster.local:9071 \
  --create --topic netlab-test --partitions 3 --replication-factor 3

kubectl -n kafka-dev exec -i kafka-0 -- \
  kafka-console-producer --bootstrap-server kafka.kafka-dev.svc.cluster.local:9071 \
  --topic netlab-test <<EOF
one
two
three
EOF

kubectl -n kafka-dev exec kafka-0 -- \
  kafka-console-consumer --bootstrap-server kafka.kafka-dev.svc.cluster.local:9071 \
  --topic netlab-test --from-beginning --max-messages 3 --timeout-ms 10000

# oc — same commands, swap kubectl for oc
oc -n kafka-dev exec kafka-0 -- \
  kafka-topics --bootstrap-server kafka.kafka-dev.svc.cluster.local:9071 \
  --create --topic netlab-test --partitions 3 --replication-factor 3

oc -n kafka-dev exec -i kafka-0 -- \
  kafka-console-producer --bootstrap-server kafka.kafka-dev.svc.cluster.local:9071 \
  --topic netlab-test <<EOF
one
two
three
EOF

oc -n kafka-dev exec kafka-0 -- \
  kafka-console-consumer --bootstrap-server kafka.kafka-dev.svc.cluster.local:9071 \
  --topic netlab-test --from-beginning --max-messages 3 --timeout-ms 10000
```

Produce + consume succeed. Notice: the producer's *bootstrap* connection went through the headless `kafka` Service, but the *partition produce* connections went directly to each leader broker by per-pod hostname. That's the bootstrap → metadata → direct-broker handshake the discussion describes.

### 4.6 Break it — point a client at a stale broker hostname

Replace one broker's per-pod Service selector so that broker becomes unreachable, even though the Service exists. Predict: what does a producer call do?

```bash
# kubectl
kubectl -n kafka-dev patch svc kafka-1-internal -p '{"spec":{"selector":{"app":"kafka","statefulset.kubernetes.io/pod-name":"kafka-DOES-NOT-EXIST"}}}'
kubectl -n kafka-dev get endpointslice -l kubernetes.io/service-name=kafka-1-internal

kubectl -n kafka-dev exec kafka-0 -- \
  kafka-console-producer --bootstrap-server kafka.kafka-dev.svc.cluster.local:9071 \
  --topic netlab-test --request-timeout-ms 8000 <<EOF
four
five
EOF

# oc — same pattern
oc -n kafka-dev patch svc kafka-1-internal -p '{"spec":{"selector":{"app":"kafka","statefulset.kubernetes.io/pod-name":"kafka-DOES-NOT-EXIST"}}}'
oc -n kafka-dev get endpointslice -l kubernetes.io/service-name=kafka-1-internal

oc -n kafka-dev exec kafka-0 -- \
  kafka-console-producer --bootstrap-server kafka.kafka-dev.svc.cluster.local:9071 \
  --topic netlab-test --request-timeout-ms 8000 <<EOF
four
five
EOF
```

**What you should observe**: the bootstrap still works (`kafka-0` and `kafka-2` are available). But for partitions whose leader is broker-1, the producer sees `NETWORK_EXCEPTION` / connection timeouts. **Partial Kafka failure is the worst kind** — bootstrap returns success, half the partitions write, the other half fail.

This is what happens in production when one broker's advertised hostname becomes unreachable (DNS, firewall, SG misconfig, NodePort overlap, OCP Route 503). Bootstrap "works"; specific produce calls fail. The discussion's image 4 calls this out as the most common Kafka ingress trap.

Restore the broker Service:

```bash
# kubectl
kubectl -n kafka-dev patch svc kafka-1-internal -p '{"spec":{"selector":{"app":"kafka","statefulset.kubernetes.io/pod-name":"kafka-1"}}}'
kubectl -n kafka-dev get endpointslice -l kubernetes.io/service-name=kafka-1-internal

# oc
oc -n kafka-dev patch svc kafka-1-internal -p '{"spec":{"selector":{"app":"kafka","statefulset.kubernetes.io/pod-name":"kafka-1"}}}'
oc -n kafka-dev get endpointslice -l kubernetes.io/service-name=kafka-1-internal
```

### 4.7 Thought exercise

The discussion shows the production pattern: **9092 (OAuth/SASL_SSL)** and **9094 (mTLS/SSL)** as the two external listeners, each fronted by **TCP passthrough OpenShift Routes**, one Route per broker. Given what you just did in 4.6:

- Why does the design need one passthrough Route **per broker**, not a single front Route with three backends?
- If a team proposed a single HTTPS Route in front of all three brokers (Round-robin), what would break?
- Map the diagnosis path: a producer in dev reports "intermittent NETWORK_EXCEPTION" — walk back through the seven hops from R1 + 1–4 to identify which hop you'd inspect first, second, third.

---

## Part 5 — Cloud-layer concepts (read-through)

Anchors discussion images **1** (ROSA VPC) and **2** (Network Monitoring and Observability).

You can't replicate VPC / NAT / Security Groups on a laptop. But you can map the hops conceptually so the picture is solid before your first ROSA exposure.

### 5.1 Map every hop in your `Part 4` produce call to its ROSA equivalent

| Hop in this lab (on kind / OCP) | Equivalent on ROSA |
|---|---|
| Pod inside `kafka-dev` | Pod inside a private subnet on a worker node EC2 |
| Headless `kafka` Service DNS | CoreDNS still resolves; underlying records are still per-pod |
| Per-pod hostname `kafka-1.kafka.kafka-dev.svc.cluster.local` | Same in-cluster; **plus** a public `broker1.kafka.example.com` hostname for external clients |
| Direct TCP to per-pod hostname | Outside the cluster: traffic flows DNS → Route53 → Ingress LB → OCP Router → backend per-pod Service → Pod |
| `kube-proxy` rules on the node | Same — kube-proxy still owns in-cluster DNAT; the cloud LB owns NodePort-level distribution |

The point: **the in-cluster mechanics are identical**. What changes on ROSA is the external entry: VPC + NAT + Security Group restrict which ports are reachable, and the OCP Router decides which backend to forward to per Route.

### 5.2 Observability per hop — pair each tool with what it tells you

(From discussion image 2 — keep this map handy for triage.)

| Hop | "I don't see traffic" → check this first |
|---|---|
| DNS / Route53 | `dig`, Route53 console, CloudWatch (LB health) |
| Ingress LB | CloudWatch target health + VPC Flow Logs (was the packet accepted?) |
| Network (VPC SG, NACL, NetworkPolicy) | VPC Flow Logs — ACCEPT vs REJECT on the 5-tuple |
| OCP Router (HAProxy) | Dynatrace router metrics + OpenShift Console (Route status) |
| Service / EndpointSlice | OpenShift Console + the `kubectl get endpointslice` discipline from 1.5/1.6 above |
| Pod / Broker | Splunk (logs), Dynatrace (per-pod metrics), `kubectl logs` |

This is the operational counterpart to the in-cluster troubleshooting tree from Wk1 Friday. Walk hops from outside-in; the tool that has visibility into the hop tells you where you are.

### 5.3 Read-through scenarios (for the deliverable write-up)

1. **External producer reports `Connection timed out`** on the very first bootstrap call. List the three observability tools you'd open, in order.
2. **External producer bootstraps fine, then fails to produce to topic X** with intermittent `NETWORK_EXCEPTION`. Which hop is most likely broken, and which tool surfaces it?
3. **OpenShift Console shows the OCP Route in Ready state, but Splunk shows the broker isn't receiving any TCP connections**. Where is the gap? (Hint: per-pod-hostname DNS, advertised.listeners, SG rule on the per-pod hostname's Route.)

---

## Deliverable — `deliverables/<your-name>/week02/wednesday.md`

1. **Part 1 traces** — paste outputs of:
   - `get endpointslice` for `hello` when the Service selector matched (1.2)
   - same after the selector mismatch (1.5) — show the empty endpoint slice
   - same after the readiness probe broke (1.6) — show Pods Running but not Ready and the empty endpoint slice
   - one sentence explaining the difference between "Pod is up" and "Pod is in the Service"
2. **Part 2 — NodePort vs LoadBalancer write-up** (2.4) — three sentences explaining what the team actually wants when they ask for NodePort, and the standard alternative you'd recommend instead.
3. **Part 3 evidence** — whichever path you ran:
   - kind path: paste the `curl -H 'Host: hello.lab.local'` output through the NGINX Ingress
   - OCP path: paste the `curl -k https://hello-edge...` output through the edge Route
4. **Part 4 — Kafka broker ingress trace** — paste:
   - the broker advertised.listeners (4.4)
   - the producer + consumer success output (4.5)
   - the partial-failure output after breaking `kafka-1-internal` (4.6)
   - your three-step diagnosis path from 4.7
5. **Part 5 read-through answers** — answer the three scenarios in 5.3 in 1–2 sentences each. Reference the specific tools.
6. **One paragraph on Kafka networking** — explain in your own words why Kafka cannot be put behind a single HTTPS Route with three backends. Reference what you saw in 4.5 + 4.6.
7. Two questions you still have.

---

## Cleanup

```bash
# kubectl
kubectl delete deployment hello svc/hello
kubectl -n kafka-dev delete topic netlab-test 2>/dev/null || \
  kubectl -n kafka-dev exec kafka-0 -- \
    kafka-topics --bootstrap-server kafka.kafka-dev.svc.cluster.local:9071 \
    --delete --topic netlab-test
kubectl delete ingress hello --ignore-not-found
kubectl delete namespace netlab

# oc — same pattern
oc delete deployment hello svc/hello
oc -n kafka-dev exec kafka-0 -- \
  kafka-topics --bootstrap-server kafka.kafka-dev.svc.cluster.local:9071 \
  --delete --topic netlab-test
oc delete route hello-edge --ignore-not-found
oc delete project netlab
```

The lab-cluster CFK install in `kafka-dev` is left intact — keep it for tomorrow.

---

## What you'll carry forward

By the end of this lab you've personally driven every hop in the discussion's seven diagrams:

- The **in-cluster path** (R1, R2, R3) — by hand, breaking and fixing each piece.
- The **OpenShift Route layer** (image 3) — at least one mode end-to-end on whichever cluster you have.
- The **Kafka-specific bootstrap → metadata → direct-broker handshake** (image 4) — observed and broken on your local lab cluster.
- The **cloud layer** (images 1 + 2) — read-through but with a hop-to-tool map you can reach for during real triage.

The next time someone says "the producer is failing intermittently against UAT Kafka," you'll have a 7-hop checklist instead of guessing.
