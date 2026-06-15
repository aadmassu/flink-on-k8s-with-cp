# Wednesday — Kafka OAuth / OIDC End-to-End

**Time**: ~90 min
**Diagram**: [`52-kafka-oauth.drawio`](52-kafka-oauth.drawio)

## Learning objective

> **How does a Kafka client authenticate via OAuth in production?** Trace the full token flow from Okta through SASL_OAUTHBEARER into the broker's authorizer.

## Architecture Discussion (~45 min)

OAuth on Kafka is unusual — Kafka was traditionally SASL/PLAIN or mTLS. In production it's SASL_OAUTHBEARER, tied to Okta. The mechanism is built on JWTs and a custom callback handler.

### The five-player flow

1. **App / Service** — wants to produce/consume
2. **Okta (IdP)** — issues JWT bearer tokens
3. **Kafka client library** (e.g. `confluent-kafka-java`) — fetches token at connection, attaches to SASL handshake
4. **Kafka broker** — runs JaasOauthBearerLoginCallbackHandler equivalents to validate
5. **Kafka authorizer** — maps token claims → ACLs

### The handshake step-by-step

```
1. App startup:
   client config has sasl.oauthbearer.token.endpoint.url=https://okta.../oauth2/token
   client config has client_id + client_secret (in Secret/env)

2. Producer.send():
   Kafka client sees no cached token → calls OAuthLoginCallbackHandler
   Callback handler hits Okta /oauth2/token with client_credentials grant
   Okta returns JWT

3. SASL handshake on broker connection (port 9092):
   Client sends SASL_OAUTHBEARER, passing the JWT
   Broker validates: signature (Okta JWKS), audience, issuer, expiry
   On success, broker extracts principal from token claim (e.g. "sub" or "preferred_username")

4. Authorization:
   Broker authorizer (e.g. Confluent's RBAC, or Kafka ACLs) checks principal vs requested action
   e.g. "user 'svc-orders' can WRITE topic 'orders'"
   Allowed → return success; Denied → return TOPIC_AUTHORIZATION_FAILED

5. Subsequent requests on the same connection reuse the SASL state.
   Token expiry: client refreshes proactively per refresh.token.url config.
```

### The two trust elements

- **JWKS endpoint trust** — broker fetches Okta's public keys from a URL like `https://okta.../oauth2/v1/keys` to validate signature. Requires Okta egress (Week 3 Thursday — tracker 2.9) + CA trust.
- **Audience + issuer** — broker config must match Okta's `aud` and `iss` claims exactly. Mismatch = auth failure.

### Token claims → Kafka principal

A typical Okta token:

```json
{
  "iss": "https://okta.example.com",
  "aud": "kafka-cluster",
  "sub": "svc-orders",
  "preferred_username": "svc-orders@example.com",
  "groups": ["kafka-orders-producers"],
  "exp": 1717920000
}
```

Kafka broker has `sasl.oauthbearer.sub.claim.name=preferred_username` so principal = `svc-orders@example.com`.

The authorizer then asks "does `svc-orders@example.com` have WRITE on `orders`?" Answer comes from either ACLs in Kafka or Confluent RBAC (via MDS).

### Environment specifics

- **Tracker 2.9** — Okta egress firewall rule from OpenShift workers
- **Tracker 2.8** — Okta's TLS chain in broker truststore
- **Operator vs end-user OAuth** — CFK operator uses its own client credential to do management calls (e.g. metric reporter setup); end-user apps use their own
- **Token caching** — broker caches validated tokens for ~5 min by default to avoid hitting Okta JWKS on every request

## Diagram Walkthrough (~30 min)

Open `52-kafka-oauth.drawio`. Walk the 5 players in order; identify where each tracker maps.

## Failure Scenarios

| Symptom | Where to look |
|---|---|
| `SASL authentication failed: invalid token` | check `aud` + `iss` claims vs broker config |
| `unable to retrieve token from URL` (client side) | client → Okta connectivity OR Okta client creds wrong |
| `unable to fetch JWKS` (broker side) | broker → Okta egress (tracker 2.9) OR trust bundle (2.8) |
| Auth succeeds but `TOPIC_AUTHORIZATION_FAILED` | principal vs ACL/RBAC mapping |

## Q&A

1. If Okta is briefly unavailable, can existing connected clients keep producing?
2. What is the difference between authentication failure and authorization failure in Kafka, and where in the connection does each surface?
3. Why does the platform use `client_credentials` grant rather than `authorization_code`?
4. How would you debug a "token is expired" error coming from the broker?


## Added Enhancement — Authentication Failure Analysis

Topics:
- OAuth/OIDC troubleshooting
- mTLS troubleshooting
- ACL troubleshooting
- RBAC troubleshooting

Scenario Workshop:

Application receives authentication errors.

Students identify whether the issue is:
- Token acquisition
- Token validation
- TLS
- ACL
- RBAC
