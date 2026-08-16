#!/bin/bash
# Ad-hoc OpenShift cluster scripts for debugging and inspection
# User can edit this file locally, commit, and run via the validate-confluent-platform pipeline
# when executeAdHocScript=true

set -euo pipefail

# Default to dev if not set
NS="${1:-dah-flink-dev}"

echo "=== OAuth Connect Token Inspection ==="
echo "Namespace: $NS"
echo ""

# Extract OAuth Connect credentials from cluster
echo "Fetching OAuth Connect credentials from Secret/oauth-connect..."
CID=$(oc -n "$NS" get secret oauth-connect -o jsonpath='{.data.clientId}' | base64 -d)
CSECRET=$(oc -n "$NS" get secret oauth-connect -o jsonpath='{.data.clientSecret}' | base64 -d)
echo "✓ Retrieved Client ID and Secret"
echo ""

# Request token from Okta
echo "Requesting access token from Okta..."
RESPONSE=$(curl -fsS \
  -X POST https://myapps.firstcitizens.com/oauth2/default/v1/token \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode "client_id=$CID" \
  --data-urlencode "client_secret=$CSECRET" \
  --data-urlencode 'grant_type=client_credentials' \
  --data-urlencode 'scope=11547.DAH(Dev)')

TOKEN=$(printf '%s' "$RESPONSE" | jq -r '.access_token')
echo "✓ Token received"
echo ""

# Decode JWT payload
echo "Decoding JWT payload..."
PAYLOAD=$(printf '%s' "$TOKEN" | cut -d. -f2)
PAYLOAD=$(printf '%s' "$PAYLOAD" | tr '_-' '/+')

case $((${#PAYLOAD} % 4)) in
  2) PAYLOAD="${PAYLOAD}==" ;;
  3) PAYLOAD="${PAYLOAD}=" ;;
esac

echo "=== Token Claims ==="
printf '%s' "$PAYLOAD" | \
  base64 -d 2>/dev/null | \
  jq '{sub,client_id,scp,aud,iss,dahDev_groups}'
