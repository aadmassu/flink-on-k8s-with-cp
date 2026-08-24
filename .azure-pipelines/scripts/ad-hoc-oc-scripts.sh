#!/usr/bin/env bash
set -euo pipefail

NS="dah-flink-qa"
TOKEN_URL="https://myapps.firstcitizens.com/oauth2/default/v1/token"
SCOPE="11547.DAH(QA)"

CLIENT_ID=$(oc -n "$NS" get secret oauth-connect \
  -o jsonpath='{.data.clientId}' | base64 -d)

CLIENT_SECRET=$(oc -n "$NS" get secret oauth-connect \
  -o jsonpath='{.data.clientSecret}' | base64 -d)

PRINCIPAL=$(oc -n "$NS" get confluentrolebinding connect-systemadmin \
  -o jsonpath='{.spec.principal.name}')

TOKEN_RESPONSE=$(curl -fsS \
  --user "$CLIENT_ID:$CLIENT_SECRET" \
  --data-urlencode grant_type=client_credentials \
  --data-urlencode "scope=$SCOPE" \
  "$TOKEN_URL")

CLIENT_ID="$CLIENT_ID" PRINCIPAL="$PRINCIPAL" \
python3 -c '
import os, sys, json, base64, time

response = json.load(sys.stdin)
token = response.get("access_token")
if not token:
    print("FAIL: Okta returned no access_token:", response.get("error_description", response.get("error", "unknown error")))
    sys.exit(1)

try:
    payload = token.split(".")[1]
    payload += "=" * (-len(payload) % 4)
    claims = json.loads(base64.urlsafe_b64decode(payload.encode()).decode())
except Exception as exc:
    print("FAIL: unable to decode JWT claims:", exc)
    sys.exit(1)

client_id = os.environ["CLIENT_ID"]
principal = os.environ["PRINCIPAL"]
subject = str(claims.get("sub", ""))

print("Secret clientId:      " + client_id)
print("JWT sub:              " + subject)
print("Rolebinding principal:" + principal)
print("Issuer:               " + str(claims.get("iss", "")))
print("Audience:             " + str(claims.get("aud", "")))
print("Scope:                " + str(claims.get("scp", claims.get("scope", ""))))
print("Token expired:        " + str(int(claims.get("exp", 0)) <= int(time.time())))

if client_id == subject == principal:
    print("PASS: all three identities match")
else:
    print("FAIL: OAuth clientId, JWT sub, and RBAC principal are not identical")
    sys.exit(1)
' <<< "$TOKEN_RESPONSE"