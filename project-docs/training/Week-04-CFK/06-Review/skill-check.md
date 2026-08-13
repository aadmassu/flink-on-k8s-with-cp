# Week 4 — Skill Check

## Task 1 — Full CFK stack from scratch (Mon, Tue)

1. Apply KRaftController + Kafka + SchemaRegistry + Connect CRs
2. Wait for all `cluster-ready=True`
3. Capture `oc get pods -l app in (kafka,kraftcontroller,schemaregistry,connect)`
4. Prove inter-component connectivity: exec into Connect, curl SR `/subjects`

**Verifies**: CFK Mon + Tue

## Task 2 — Listener inventory (Wed)

For your running cluster, produce a table:

| Listener name | Port | TLS | Auth | Service/Route | tracker |

Including the internal 9091, external 9092 SASL_OAUTHBEARER, custom 9094 mTLS.

**Verifies**: Wed (CFK listeners)

## Task 3 — TLS forensics (Thu)

1. From the wire (openssl s_client), capture the broker cert SAN
2. From the Secret, decode tls.crt + ca.crt
3. Trace back to the Certificate CR + ClusterIssuer
4. Confirm chain validity with `openssl verify`

**Verifies**: Thu (TLS architecture)

## Task 4 — Rolling upgrade narration (Fri)

1. Patch `spec.image.application` to a different (but valid) image tag
2. While the rollout runs, capture in 30-second intervals:
   - `oc get pods -l app=kafka` (which Pod is replacing)
   - Kafka `--describe --topic <something>` (ISR state during)
   - `oc get pdb -l app=kafka` (current allowed disruptions)
3. Verify rollout completed without ISR going below `min.insync.replicas`

**Verifies**: Fri (rolling upgrade safety)

## Task 5 — One induced failure (Fri)

Pick ONE of the four scenarios from Week 4 Fri lab (bad image, tight PDB drain, cert mismatch, PVC reattach). Run it end-to-end:

- Cause
- First symptom
- Diagnostic command that named the cause
- Recovery
- Time-to-recovery

**Verifies**: Wk 4 Fri break-things day

## Submission

`deliverables/<you>/week04/` — one file per task. Together this becomes your **personal CFK Deployment Guide** (final-deliverable item 2).
