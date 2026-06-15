# Week 5 Wednesday — Lab: OAuth Client Connection

**Time**: ~4 hours

## Prerequisites

Instructor provides:
- An Okta client_id + client_secret (service account)
- Okta token endpoint URL
- Okta JWKS URL
- The expected `aud` claim for your training cluster
- The Kafka external bootstrap server

## Hands-on Lab — fetch a token; produce via OAuth

### Step 1 — fetch a token manually

```bash
curl -X POST $OKTA_TOKEN_URL \
  -d "grant_type=client_credentials" \
  -d "client_id=$CLIENT_ID" \
  -d "client_secret=$CLIENT_SECRET" \
  -d "scope=kafka" \
  -H "Content-Type: application/x-www-form-urlencoded" | python3 -m json.tool
```

Capture the JWT. Decode at jwt.io (or `cut -d. -f2 | base64 -d`). Inspect:
- `iss`, `aud`, `sub`, `preferred_username`, `groups`, `exp`

### Step 2 — configure a Kafka client with OAuth

Create `/tmp/oauth-client.properties`:

```properties
bootstrap.servers=<external-bootstrap>:9092
security.protocol=SASL_SSL
sasl.mechanism=OAUTHBEARER
sasl.login.callback.handler.class=org.apache.kafka.common.security.oauthbearer.secured.OAuthBearerLoginCallbackHandler
sasl.jaas.config=org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginModule required \
   clientId="$CLIENT_ID" \
   clientSecret="$CLIENT_SECRET" \
   scope="kafka";
sasl.oauthbearer.token.endpoint.url=$OKTA_TOKEN_URL
```

### Step 3 — produce + consume via OAuth

```bash
# Produce
echo "oauth-test-msg" | oc exec -i kafka-0 -c kafka -- \
  kafka-console-producer \
  --bootstrap-server <external-bootstrap>:9092 \
  --topic orders \
  --producer.config /tmp/oauth-client.properties
```

If this fails, you'll see one of the failure modes below.

### Step 4 — observe broker validation

```bash
# Tail broker logs while you connect
oc logs kafka-0 -c kafka -f | grep -i -E 'oauth|sasl|principal'
```

Capture:
- A successful authentication log line — what principal got extracted?
- The cached-token behavior (token reuse for ~5 min, no second Okta hit)

## Troubleshooting Exercise — three induced failures

### Failure A — wrong audience

Change `--producer.config` to set a scope that produces a wrong `aud` claim.
Capture broker log: `invalid_token` with audience mismatch.

### Failure B — JWKS unreachable

Block egress to Okta (or use a fake JWKS URL in broker config).
Capture broker startup behavior + per-client log error.

### Failure C — token-expired race

Wait for token to expire (5 min default for short-lived dev tokens).
Capture client behavior: does it refresh, or fail?

## Deliverable — `deliverables/<you>/week05/wednesday.md`

1. **Decoded token claims** — paste the JWT body from Step 1
2. **Successful auth log line** — from broker, showing principal extraction
3. **Three failure modes** — error message + your one-line explanation of root cause
4. **The Okta firewall rule** — which IP/CIDR and port, per tracker 2.9
5. **What happens to in-flight producers if Okta becomes unreachable** — your one-paragraph answer (cross-ref the discussion)
