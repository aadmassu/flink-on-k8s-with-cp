#!/usr/bin/env bash
set -euo pipefail

NS="dah-flink-qa"
TOKEN_URL="https://myapps.firstcitizens.com/oauth2/default/v1/token"
SCOPE="11547.DAH(QA)"
MDS_URL="https://kafka.dah-flink-qa.svc.cluster.local:8090"
MDS_HOST="kafka.dah-flink-qa.svc.cluster.local"
LOCAL_PORT="18090"

WORK_DIR=$(mktemp -d)
PF_PID=""

cleanup() {
  [ -n "$PF_PID" ] && kill "$PF_PID" 2>/dev/null || true
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

get_secret_value() {
  oc -n "$NS" get secret "$1" -o "jsonpath={.data.$2}" | base64 -d
}

get_token() {
  local secret_name=$1 client_id client_secret response

  client_id=$(get_secret_value "$secret_name" clientId)
  client_secret=$(get_secret_value "$secret_name" clientSecret)

  response=$(curl -fsS \
    --user "$client_id:$client_secret" \
    --data-urlencode grant_type=client_credentials \
    --data-urlencode "scope=$SCOPE" \
    "$TOKEN_URL")

  printf '%s' "$response" |
    python3 -c 'import json,sys; t=json.load(sys.stdin).get("access_token"); print(t) if t else sys.exit("No access_token returned")'
}

echo "=== Obtain OAuth tokens ==="
ADMIN_TOKEN=$(get_token oauth-mds-rest)
CONNECT_TOKEN=$(get_token oauth-connect)
CONNECT_ID=$(get_secret_value oauth-connect clientId)
PRINCIPAL="User:$CONNECT_ID"
PRINCIPAL_PATH=$(PRINCIPAL="$PRINCIPAL" python3 -c \
  'import os; from urllib.parse import quote; print(quote(os.environ["PRINCIPAL"], safe=""))')

echo "=== Prepare trusted MDS connection ==="
oc -n "$NS" get secret kafka-tls \
  -o jsonpath='{.data.ca\.crt}' | base64 -d > "$WORK_DIR/ca.crt"

oc -n "$NS" port-forward service/kafka "$LOCAL_PORT:8090" \
  >"$WORK_DIR/port-forward.log" 2>&1 &
PF_PID=$!

for attempt in $(seq 1 30); do
  if curl -sS --output /dev/null \
      --cacert "$WORK_DIR/ca.crt" \
      --connect-to "$MDS_HOST:8090:127.0.0.1:$LOCAL_PORT" \
      "$MDS_URL/security/1.0/metadataClusterId"; then
    break
  fi
  sleep 2
done

echo
echo "=== MDS rolebinding lookup using admin identity ==="
LOOKUP_CODE=$(curl -sS \
  --output "$WORK_DIR/lookup.json" \
  --write-out '%{http_code}' \
  --cacert "$WORK_DIR/ca.crt" \
  --connect-to "$MDS_HOST:8090:127.0.0.1:$LOCAL_PORT" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  "$MDS_URL/security/1.0/lookup/rolebindings/principal/$PRINCIPAL_PATH")

echo "HTTP status: $LOOKUP_CODE"
python3 -m json.tool "$WORK_DIR/lookup.json" 2>/dev/null ||
  cat "$WORK_DIR/lookup.json"

echo
echo "=== Authenticate Connect identity directly against MDS ==="
AUTH_CODE=$(curl -sS \
  --output "$WORK_DIR/authenticate.json" \
  --write-out '%{http_code}' \
  --cacert "$WORK_DIR/ca.crt" \
  --connect-to "$MDS_HOST:8090:127.0.0.1:$LOCAL_PORT" \
  -H "Authorization: Bearer $CONNECT_TOKEN" \
  "$MDS_URL/security/1.0/authenticate")

echo "HTTP status: $AUTH_CODE"
python3 -m json.tool "$WORK_DIR/authenticate.json" 2>/dev/null ||
  cat "$WORK_DIR/authenticate.json"

unset ADMIN_TOKEN CONNECT_TOKEN

echo
echo "=== Result interpretation ==="
echo "Lookup 200 + authenticate 200: MDS recognizes the identity; inspect Connect REST authentication."
echo "Lookup 200 + authenticate 401: role exists, but MDS rejects the OAuth identity."
echo "Lookup empty/404: CFK CR says CREATED, but the binding is absent from MDS."