# Week 4 Thursday — Lab: PKI, TLS, and cert-manager (with a CFK broker at the end)

**Time**: ~4 hours

Four exercises, one per topic in [`discussion.md`](discussion.md). Each is self-contained; do them in order.

Every `oc` command in this lab is shown alongside its `kubectl` equivalent (training convention). Use whichever you have on your laptop.

---

## Lab 1 — Walk a real PKI trust chain

**Goal**: verify that you can identify Root, Intermediate, and Leaf certs in any cert chain and check their signing relationship.

### 1a. Grab a real chain from a public site (before cluster access)

```bash
# Fetch the chain google.com presents (or any other HTTPS server)
openssl s_client -connect google.com:443 -servername google.com -showcerts </dev/null 2>/dev/null \
  | awk '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/'
```

You should see two or three `-----BEGIN CERTIFICATE-----` blocks. Save each to a file (`leaf.pem`, `intermediate.pem`, and optionally `root.pem` if the server sent it — most don't).

### 1b. Inspect each cert

```bash
openssl x509 -in leaf.pem         -noout -subject -issuer -dates -ext subjectAltName
openssl x509 -in intermediate.pem -noout -subject -issuer -dates
```

For each cert, write down: **Subject** (whose identity), **Issuer** (who signed it), **notBefore / notAfter** (validity window), **SANs** (only on leaf — which hostnames this cert is valid for).

### 1c. Verify the chain

```bash
# Root usually lives in your OS trust store, not on the wire. On macOS:
openssl verify -CAfile intermediate.pem leaf.pem
```

Expected: `leaf.pem: OK` if you also concatenate the OS-trusted roots. If you get `unable to get local issuer certificate`, that's the exact error your JVM sees when the truststore is missing a link.

### 1d. In your notes

- Draw the chain: Root → Intermediate → Leaf, with arrows labeled "signs".
- Note which cert(s) the server DID send on the wire and which one(s) it EXPECTED the client to already have.

---

## Lab 2 — Create and use a self-signed certificate

**Goal**: see first-hand why self-signed doesn't scale — and why it's still legitimate for internal tooling.

### 2a. Generate

```bash
openssl req -x509 -newkey rsa:2048 \
  -keyout selfsigned-key.pem \
  -out    selfsigned-cert.pem \
  -days 30 -nodes \
  -subj "/CN=my-lab.local"
```

### 2b. Observe the tell-tale property

```bash
openssl x509 -in selfsigned-cert.pem -noout -subject -issuer
```

**Both lines should be identical.** That's what "self-signed" means: the cert's Issuer field equals its Subject field, and the signature was made with the cert's own private key.

### 2c. Serve it and see the client warning

```bash
# One terminal — serve HTTPS
openssl s_server -cert selfsigned-cert.pem -key selfsigned-key.pem -accept 8443 -www

# Another terminal — connect. Note the ✕ verify error
openssl s_client -connect localhost:8443 -showcerts </dev/null 2>&1 | grep -E "verify|Verify"
```

Expected: `verify error:num=18:self-signed certificate` and `Verify return code: 18 (self-signed certificate)`.

### 2d. Bypass by pre-sharing the cert

```bash
# Same s_client call, but this time trust the specific cert
openssl s_client -connect localhost:8443 -CAfile selfsigned-cert.pem </dev/null 2>&1 | grep -E "verify|Verify"
```

Expected: `Verify return code: 0 (ok)`. That's the "manually import the self-signed cert into the client's trust store" pattern in action.

### 2e. In your notes

- Explain in your own words why step 2c fails but 2d succeeds.
- List two legitimate places to use self-signed and two places you absolutely wouldn't.

---

## Lab 3 — Observe a TLS handshake message by message

**Goal**: match the wire flow to the 5-message diagram in Topic 3. See what each `Hello`, `Certificate`, `KeyExchange`, and `Finished` looks like.

### 3a. Use openssl's `-debug` to see the handshake

```bash
openssl s_client -connect google.com:443 -servername google.com -debug -state \
  -tls1_2 </dev/null 2>&1 | head -80
```

`-state` prints the handshake state transitions in human-readable form; `-debug` dumps the raw bytes. Look for these lines in order:

- `SSL_connect:before/connect initialization`
- `SSL_connect:SSLv3/TLS write client hello`  ← **①** ClientHello
- `SSL_connect:SSLv3/TLS read server hello`   ← **②** ServerHello
- `SSL_connect:SSLv3/TLS read server certificate` ← **③** Certificate
- `SSL_connect:SSLv3/TLS read server key exchange` ← **④** ServerKeyExchange (only in DHE/ECDHE)
- `SSL_connect:SSLv3/TLS read server done`
- `SSL_connect:SSLv3/TLS write client key exchange` ← **⑦** ClientKeyExchange
- `SSL_connect:SSLv3/TLS write change cipher spec`  ← **⑧** ChangeCipherSpec
- `SSL_connect:SSLv3/TLS write finished`
- `SSL_connect:SSL negotiation finished successfully` ← ready for **⑨** Application Data

### 3b. Force a failure

```bash
# Trust no roots at all
openssl s_client -connect google.com:443 -servername google.com \
  -CApath /dev/null -CAfile /dev/null </dev/null 2>&1 | grep -E "verify|Verify"
```

Expected: `Verify return code: 20 (unable to get local issuer certificate)`. This is the client's cert-validation step (Topic 1) failing during handshake step **⑥**.

### 3c. Compare TLS 1.2 vs 1.3

```bash
openssl s_client -connect google.com:443 -servername google.com -tls1_3 -state </dev/null 2>&1 \
  | grep "SSL_connect" | wc -l
```

Compare the number of state transitions with the `-tls1_2` run. TLS 1.3 is materially shorter — the ServerHello already contains the key share, so ClientKeyExchange isn't a separate message.

### 3d. In your notes

- For your `-tls1_2` capture, label each `SSL_connect` line with the message number from the Topic 3 diagram.
- Write one sentence per message: what does the client / server accomplish here?

---

## Lab 4 — Trace a CFK broker's cert end-to-end

**Goal**: follow one Kafka broker's TLS material backwards from the wire, through the Secret and the Certificate CR, to the ClusterIssuer.

Assumes access to a cluster where CFK is running — replace `<namespace>` and `<broker-fqdn>` with values from your cluster. If you don't have cluster access, read through and reason about each step.

### 4a. What is the broker actually presenting on the wire?

```bash
openssl s_client -connect <broker-fqdn>:9092 -servername <broker-fqdn> -showcerts </dev/null 2>/dev/null \
  | openssl x509 -noout -subject -issuer -dates -ext subjectAltName
```

Record: Subject, Issuer, notAfter, and SANs.

### 4b. Which Secret is CFK reading that from?

Find the Kafka CR:

```bash
oc      get kafka -n <namespace>
# or
kubectl get kafka -n <namespace>
```

Read `.spec.tls.secretRef.name`:

```bash
oc      get kafka <kafka-cr-name> -n <namespace> -o yaml | grep -A 3 "tls:"
# or
kubectl get kafka <kafka-cr-name> -n <namespace> -o yaml | grep -A 3 "tls:"
```

Now inspect the Secret's three keys:

```bash
# tls.crt — leaf + intermediate chain
oc      get secret <secret-name> -n <namespace> -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -subject -dates
# ca.crt — issuing CA
oc      get secret <secret-name> -n <namespace> -o jsonpath='{.data.ca\.crt}'  | base64 -d | openssl x509 -noout -subject
# tls.key — do NOT print (private key)
oc      get secret <secret-name> -n <namespace> -o jsonpath='{.data.tls\.key}' | base64 -d | head -1
```

The last line should show `-----BEGIN RSA PRIVATE KEY-----` — that's confirmation it's a PEM key without printing the key bytes.

### 4c. Which Certificate CR wrote that Secret?

```bash
oc      get certificate -A | grep <secret-name>
# or
kubectl get certificate -A | grep <secret-name>
```

Read the full Certificate spec:

```bash
oc      get certificate <cert-name> -n <namespace> -o yaml
# or
kubectl get certificate <cert-name> -n <namespace> -o yaml
```

Note the `spec.dnsNames` (SANs), `spec.duration`, `spec.renewBefore`, and `spec.issuerRef` (which points to a ClusterIssuer).

### 4d. Which ClusterIssuer did that route through?

```bash
oc      get clusterissuer <issuer-name> -o yaml
# or
kubectl get clusterissuer <issuer-name> -o yaml
```

Note the provisioner type (Keyfactor / self-signed / letsencrypt / vault / CA) and the endpoint URL. That's the external CA that actually signed the cert.

### 4e. Break the truststore, watch what happens, then restore

```bash
# Backup the Secret first
oc      get secret <secret-name> -n <namespace> -o yaml > /tmp/secret-backup.yaml
# or
kubectl get secret <secret-name> -n <namespace> -o yaml > /tmp/secret-backup.yaml

# Corrupt ca.crt (rotate a few base64 chars)
oc      get secret <secret-name> -n <namespace> -o yaml \
  | sed 's|ca.crt: [A-Za-z0-9+/=]\{1,4\}|ca.crt: ZGVhZGJlZWY=|' \
  | oc apply -f -

# Roll the StatefulSet so the broker picks up the mangled Secret
oc      rollout restart statefulset/<statefulset-name> -n <namespace>

# Watch pods + inspect broker logs for the TLS error
oc      get pods -n <namespace> -l app.kubernetes.io/name=confluent-platform -w
oc      logs <broker-pod-name> -n <namespace> -c kafka --tail=200 | grep -i -E 'tls|ssl|certificate'

# Restore
oc      apply -f /tmp/secret-backup.yaml
oc      rollout restart statefulset/<statefulset-name> -n <namespace>
```

Capture the exact error line the broker logged with a corrupt truststore.

### 4f. In your notes

- Draw the chain of resources you traversed: **wire cert → Secret → Certificate CR → ClusterIssuer → external CA**. Add one line per hop naming who owns it (workload engineer / cluster admin / Container Platforms).
- Record the corrupted-truststore log line from step 4e. This is what production looks like when trust bundles drift.

---

## Deliverable — `deliverables/<you>/week04/thursday.md`

Combine your notes from all four labs into one file with these five sections:

1. **PKI chain diagram** (from Lab 1) — Root/Intermediate/Leaf with signing arrows, plus a one-line description of each cert's role.
2. **Self-signed contrast** (from Lab 2) — two lines: what worked without pre-sharing, what only worked after pre-sharing.
3. **TLS 1.2 handshake trace** (from Lab 3) — your annotated `SSL_connect` capture with message numbers, plus one sentence per message.
4. **CFK broker cert trace** (from Lab 4) — the five-hop chain (wire → Secret → Certificate → ClusterIssuer → external CA) with owner per hop.
5. **Corrupt-truststore log line** (from Lab 4e) — the exact broker log line captured under the fault.
6. **Two questions** — anything from PKI / self-signed / handshake / cert-manager that you couldn't answer after this session.
