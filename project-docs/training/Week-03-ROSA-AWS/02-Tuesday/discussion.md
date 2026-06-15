# Tuesday — OIDC Flow (How Humans Sign Into the Cluster)

**Time**: ~90 min
**Diagram**: [`31-oidc-flow.drawio`](31-oidc-flow.drawio) — User → Okta → OAuth2 token → OpenShift apiserver

## Learning objective

> **Why does `oc login` open a browser?** And what does the apiserver actually verify when it accepts your bearer token? Understanding this trace explains ~80% of "I can't log in / I get 401 / my permissions are wrong" issues.

## Architecture Discussion (~40 min)

OIDC = OpenID Connect — an authentication layer built on top of OAuth 2.0. ROSA federates with an external IdP (Okta in production) instead of managing its own user database.

### The five players

1. **User** — engineer with an Okta account
2. **Browser** — the agent that drives the OAuth dance
3. **OpenShift OAuth Server** (in `openshift-authentication` namespace) — issues OpenShift-side bearer tokens
4. **Okta** — the IdP that authenticates the user (password, MFA, federated to AD)
5. **OpenShift apiserver** — accepts requests + validates bearer tokens

### The dance (Authorization Code Flow with PKCE)

```
User runs: oc login --web https://api.<cluster>.openshiftapps.com:6443
   │
   │ Step 1: oc opens the OpenShift OAuth Server's /authorize URL in a browser
   ▼
OpenShift OAuth Server
   │
   │ Step 2: OAuth Server redirects browser to Okta (the configured IdP)
   ▼
Okta
   │
   │ Step 3: User enters Okta credentials + MFA
   │ Step 4: Okta redirects back to OAuth Server with an Authorization Code
   ▼
OpenShift OAuth Server
   │
   │ Step 5: OAuth Server exchanges code for Okta token (server-to-server)
   │ Step 6: OAuth Server validates the Okta token's signature against Okta's JWKS endpoint
   │ Step 7: OAuth Server reads user's groups/claims from the token
   │ Step 8: OAuth Server mints an OpenShift bearer token (different from Okta's token!)
   ▼
oc CLI
   │
   │ Step 9: oc receives the OpenShift bearer token, writes it to ~/.kube/config
   │ Step 10: Every subsequent oc command sends this token as Authorization: Bearer <...>
   ▼
OpenShift apiserver
   │
   │ Step 11: apiserver validates the bearer token against OAuth Server's introspection
   │ Step 12: apiserver looks up RBAC for that user (Monday's RBAC lesson from Week 2)
   │ Step 13: returns 200 OK or 403 Forbidden
```

### The two-token distinction

The "OpenShift bearer token" the apiserver sees is NOT the same as the Okta token. The OAuth Server bridges the two. Engineers confuse these:

- **Okta token** — issued by Okta, signed by Okta's keys, validated against Okta's JWKS. Has Okta-specific claims (sub, groups, etc.).
- **OpenShift bearer token** — issued by OpenShift's OAuth Server, used only to call the apiserver. The OAuth Server keeps track of which OpenShift token maps to which Okta user.

### Group → role mapping

When the OAuth Server processes Okta's token, it reads the `groups` claim. Those groups become OpenShift Group objects. Engineers + RBAC bindings target those Groups. In production, `dahDev_groups`, `dahProd_groups` are the Okta groups that map to OpenShift access.

The CFK Kafka CR's OAuth listener uses the SAME pattern (Week 4 will get into this) — Kafka brokers validate OAuth tokens issued by the same Okta tenant. Different OAuth flow (client_credentials grant for service-to-service), same trust chain.

## Diagram Walkthrough (~30 min)

Trace one `oc login --web` end-to-end. Stop at each redirect: *what URL is the browser at right now? What state is the user in?*

Then trace a SUBSEQUENT `oc get pods` call — the OAuth flow is done; the apiserver only validates the cached token.

## Failure Scenarios

| Symptom | Likely cause | Where to look |
|---|---|---|
| Browser redirect loop during `oc login --web` | OAuth Server can't reach Okta (egress firewall) | tracker 2.9 — Okta egress |
| Login succeeds; `oc get pods` returns 401 | Bearer token expired (default ~24h); re-login | `~/.kube/config` token, run `oc login --web` again |
| Login succeeds; `oc get pods` returns 403 | RBAC missing for this user/group | `oc auth can-i ...` — Week 2 Monday's drill |
| `oc login` returns "invalid client" | OpenShift OAuth Server's IdP config is wrong (wrong client ID, wrong redirect URI) | `oc get oauth cluster -o yaml` |
| User's Okta group doesn't appear in OpenShift | Group claim mapping wrong in the IdP config OR Okta token doesn't include groups claim | Decode Okta token at jwt.io and check the groups claim |

## Q&A

1. What's the difference between OpenID Connect and OAuth 2.0?
2. Why does the OpenShift OAuth Server mint its OWN token instead of accepting the Okta token directly?
3. If Okta is down, can engineers who are ALREADY logged in continue using the cluster?
4. What lives in `~/.kube/config` — the Okta token or the OpenShift token?
5. In production, what's the Okta group that the typical engineer needs to be in to admin `dah-flink-uat`?


## Added Enhancement — STS/OIDC Troubleshooting

This directly supports future OAuth and service account troubleshooting.

Commands and checks:
- Verify service account annotations
- Validate IAM role trust relationships
- Review OIDC provider configuration

Scenario: Pod cannot assume AWS role.
