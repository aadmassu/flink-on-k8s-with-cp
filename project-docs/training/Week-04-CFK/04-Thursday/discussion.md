# Thursday — CFK TLS Architecture

**Time**: ~90 min
**Diagram**: [`43-cfk-tls.drawio`](43-cfk-tls.drawio)

## Learning objective

> **Where do CFK's TLS certs come from, how are they renewed, and what breaks when trust bundles drift?**

## Architecture Discussion (~45 min)

CFK does not issue certs. cert-manager + Keyfactor does (project memory `project_certmanager_keyfactor`). CFK consumes the resulting Secrets.

### The three cert audiences

1. **Server certs on brokers / SR / Connect** — signed by Keyfactor, SAN includes broker DNS + external route hostname
2. **Server certs on the operator's webhook endpoints** — OpenShift Service CA is often enough
3. **Client certs for mTLS** — used by the 9094 listener for cluster-link source brokers (tracker 2.10)

### How CFK consumes a cert

CFK CRs have `spec.tls.secretRef.name`. The referenced Secret has these keys:

- `tls.crt` — PEM-encoded cert chain
- `tls.key` — PEM-encoded private key
- `ca.crt` — issuing CA cert(s) — used to build the broker's truststore

The operator mounts this Secret into each broker Pod, the init container builds JKS keystores from the PEM files, and the broker JVM reads them at startup.

### How cert-manager builds the Secret

```
Certificate CR  →  cert-manager Controller  →  Keyfactor ClusterIssuer
                                                       ↓
                                              Keyfactor CA issues cert
                                                       ↓
                                              cert-manager stores in Secret
                                                       ↓
                                              CFK operator picks up
                                              (Secret watch or restart)
```

### Why trust bundles are the #1 TLS pain point

A broker validates the client cert against its **truststore** = `ca.crt` from its Secret. If the client cert was issued by a CA that the broker doesn't trust, handshake fails with `bad_certificate`.

In production, this surfaces:

- **Tracker 2.8** — broker truststore needs the same internal CA chain that's in the platform PKI. If cert-manager builds the Secret from a Keyfactor issuer that uses a different chain, mTLS clients fail.
- **VM CP brokers** — VM-side CA may not match the OpenShift-side CA. For the cluster-link migration, both sides need to trust each other's CAs.

The fix is always: **make sure `ca.crt` is the union of every CA you need to trust**, not just the issuing CA.

### Renewal

cert-manager auto-renews based on `Certificate.spec.duration` + `renewBefore`. When the Secret rotates:

- The operator notices and **rolling-restarts the StatefulSet** to pick up the new cert
- This is fine for brokers (PDB respected) but causes brief connection blips for clients during the rollout
- Some components (Connect workers) reload on SIGHUP without a restart — check per-component behavior

### What CFK does NOT do

- Does not generate keys
- Does not register with the CA
- Does not validate client trust externally (the broker JVM does that)
- Does not handle CRL / OCSP — that's all JVM-side

## Diagram Walkthrough (~30 min)

Open `43-cfk-tls.drawio`. Walk the issuance path top-to-bottom, then the consumption path side-to-side: Secret mounted into Pod → init container builds JKS → broker reads at startup → client handshake validates against truststore.

## Failure Scenarios

| Symptom | Where to look |
|---|---|
| Broker won't start, log mentions `KeyStoreException` | Secret missing or malformed |
| TLS handshake fails — `bad_certificate` | truststore missing client's CA |
| TLS handshake fails — `expired` | cert-manager renewal failed |
| Broker SAN mismatch — `unable to find valid certification path to requested target` | external client connecting via a hostname not in the SAN |

## Q&A

1. If cert-manager fails to renew a cert before expiry, what's the order of failure: client errors first, broker errors first, or simultaneous?
2. Why does CFK need a restart on cert rotation but Connect doesn't?
3. What's the difference between `ca.crt` in the Secret and the JVM's default truststore?
4. In production, why are server certs from Keyfactor but operator webhook certs from OpenShift Service CA — wouldn't one issuer simplify things?


## Added Enhancement — TLS Certificate Lifecycle

Topics:
- Broker certificates
- Truststores
- Certificate rotation
- Expiration troubleshooting

Failure Workshop:
Expired certificate causes client authentication failures.
Students identify root cause.
