# Week 3 Tuesday — Lab: Trace Your Own OAuth Flow

**Time**: ~3 hours

## Hands-on Lab — login + decode the token

```bash
# 1. Log into the dev cluster with web flow
oc login --web https://api.<cluster>.openshiftapps.com:6443

# 2. Find your bearer token in ~/.kube/config
oc whoami -t        # prints the OpenShift bearer token

# 3. Decode it (it's a JWT — header.payload.signature)
TOKEN=$(oc whoami -t)
echo "$TOKEN" | cut -d. -f2 | base64 -d 2>/dev/null | python3 -m json.tool || \
echo "(Token may not be JWT; might be opaque — OpenShift defaults to opaque tokens)"

# 4. Inspect your user object
oc get user ~ -o yaml             # ~ resolves to "me"

# 5. Inspect your groups
oc get user.user.openshift.io ~ -o jsonpath='{.groups}{"\n"}'

# 6. What identity providers does the cluster have?
oc get oauth cluster -o jsonpath='{.spec.identityProviders[*].name}{"\n"}'
oc get oauth cluster -o yaml | sed -n '/identityProviders:/,/templates:/p'
```

In your runbook, note: what groups are you in? Which of those came from Okta?

## Hands-on Lab Part 2 — capture the redirect chain

In your browser:

1. Open Developer Tools → Network tab (preserve log enabled)
2. Clear log
3. Run `oc login --web ...` from terminal — it opens a browser window
4. Sign in via Okta (full MFA dance)
5. Browser eventually shows "You can now close this window"
6. **Inspect the Network log** — list every URL the browser hit in order

Paste the URL sequence (HTTP method, host, path, status) into your deliverable. You should see:

```
GET https://oauth-openshift.apps.<cluster>...../oauth/authorize  → 302
GET https://okta.../oauth2/.../authorize                     → 302 (Okta sign-in page)
POST https://okta.../oauth2/.../token                        → 200 (or shown elsewhere if server-to-server)
GET https://oauth-openshift.apps.<cluster>..../oauth/callback     → 302
GET https://oauth-openshift.apps.<cluster>..../oauth/display      → 200 (your token)
```

That sequence IS the diagram from this morning, made visible.

## Troubleshooting Exercise — predict what would fail at each step

For each of the following scenarios, predict which step of the morning's flow breaks and what the user sees:

1. Okta is completely down — outage
2. The OpenShift OAuth Server's IdP config has the wrong Okta client ID
3. The user's Okta password is wrong
4. The user's Okta account has been disabled (but token in browser is still cached)
5. The user is in NONE of the OpenShift-mapped Okta groups

Now actually try ONE of them on the dev cluster (e.g., scenario 4 — `oc logout` then try to use a stale token from `~/.kube/config`).

## Deliverable — `deliverables/<you>/week03/tuesday.md`

1. **The URL redirect chain** from the browser network log — paste verbatim
2. **Your group memberships** — output of `oc get user ~ -o jsonpath='{.groups}'`
3. **Identity provider config** — the IdP names + their type (Okta / htpasswd / OIDC)
4. **The 5 failure predictions** — what the engineer sees in each case
5. **The one you actually tested** — predicted vs actual outcome
6. **CFK preview** — in 2 sentences, explain how the Kafka broker's OAuth listener (Week 4) uses the SAME Okta tenant but via a DIFFERENT grant type (client_credentials). What does that look like at the protocol level?
7. Two questions

Cleanup: re-login if your session expired during testing — `oc login --web`.
