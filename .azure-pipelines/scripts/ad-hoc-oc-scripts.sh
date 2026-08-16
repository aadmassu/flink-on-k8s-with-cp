#!/bin/bash
# Ad-hoc OpenShift cluster scripts for debugging and inspection
# User can edit this file locally, commit, and run via the validate-confluent-platform pipeline
# when executeAdHocScript=true

set -euo pipefail

NS=dah-flink-dev
TOKEN_URL=https://myapps.firstcitizens.com/oauth2/default/v1/token
EXPECTED_ISSUER=https://myapps.firstcitizens.com/oauth2/default
EXPECTED_SCOPE='11547.DAH(Dev)'

COMPONENTS=(
  "schemaregistry:oauth-schemaregistry"
  "connect:oauth-connect"
  "kafkarest:oauth-kafkarest"
  "controlcenter:oauth-controlcenter"
  "mds-rest:oauth-mds-rest"
)

decode_payload() {
  local token=$1
  local payload

  payload=$(printf '%s' "$token" | cut -d. -f2 | tr '_-' '/+')

  case $((${#payload} % 4)) in
    2) payload="${payload}==" ;;
    3) payload="${payload}=" ;;
  esac

  printf '%s' "$payload" | base64 -d 2>/dev/null
}

failures=0

echo "=== Managed-component OAuth identity audit ==="

for item in "${COMPONENTS[@]}"; do
  component=${item%%:*}
  secret=${item#*:}

  echo
  echo "------------------------------------------------------------"
  echo "Component: $component"
  echo "Secret:    $secret"

  cid=$(oc -n "$NS" get secret "$secret" \
    -o jsonpath='{.data.clientId}' | base64 -d)

  csecret=$(oc -n "$NS" get secret "$secret" \
    -o jsonpath='{.data.clientSecret}' | base64 -d)

  echo "Secret clientId: $cid"

  response=$(curl -fsS \
    -X POST "$TOKEN_URL" \
    -H 'Content-Type: application/x-www-form-urlencoded' \
    --data-urlencode "client_id=$cid" \
    --data-urlencode "client_secret=$csecret" \
    --data-urlencode 'grant_type=client_credentials' \
    --data-urlencode "scope=$EXPECTED_SCOPE") || {
      echo "FAIL: Okta token request failed"
      failures=$((failures + 1))
      continue
    }

  token=$(printf '%s' "$response" | jq -r '.access_token // empty')

  if [ -z "$token" ]; then
    echo "FAIL: Okta returned no access_token"
    printf '%s' "$response" | jq '{error,error_description}'
    failures=$((failures + 1))
    continue
  fi

  claims=$(decode_payload "$token")

  sub=$(printf '%s' "$claims" | jq -r '.sub // empty')
  issuer=$(printf '%s' "$claims" | jq -r '.iss // empty')
  groups=$(printf '%s' "$claims" | jq -c '.dahDev_groups // empty')
  scope=$(printf '%s' "$claims" | jq -c '.scp // .scope // empty')
  audience=$(printf '%s' "$claims" | jq -c '.aud // empty')

  echo "Token claims:"
  printf '%s' "$claims" |
    jq '{sub,client_id,iss,aud,scp,scope,dahDev_groups}'

  echo "RBAC bindings:"
  bindings=$(
    oc -n "$NS" get confluentrolebinding -o json |
      jq -r --arg cid "$cid" '
        .items[]
        | select(.spec.principal.name == $cid)
        | "\(.metadata.name): role=\(.spec.role), state=\(.status.state // "unknown")"
      '
  )

  if [ -n "$bindings" ]; then
    printf '%s\n' "$bindings"
  else
    echo "NONE"
  fi

  if [ "$sub" != "$cid" ]; then
    echo "FAIL: token sub '$sub' does not equal clientId '$cid'"
    failures=$((failures + 1))
  else
    echo "PASS: sub matches clientId"
  fi

  if [ "$issuer" != "$EXPECTED_ISSUER" ]; then
    echo "FAIL: unexpected issuer '$issuer'"
    failures=$((failures + 1))
  else
    echo "PASS: issuer"
  fi

  if [ -z "$groups" ] || [ "$groups" = "null" ]; then
    echo "FAIL: dahDev_groups claim is absent"
    failures=$((failures + 1))
  else
    echo "PASS: dahDev_groups claim exists"
  fi

  if [ -z "$bindings" ] && [ "$component" != "mds-rest" ]; then
    echo "FAIL: no ConfluentRolebinding matches this token identity"
    failures=$((failures + 1))
  fi

  unset csecret token response claims
done

echo
echo "=== Kafka MDS impersonation administrators ==="
oc -n "$NS" get kafka kafka -o json |
  jq -r '.spec.services.mds.impersonation.admins[]'

echo
echo "=== ConfluentRolebinding states ==="
oc -n "$NS" get confluentrolebinding -o json |
  jq -r '
    .items[]
    | [
        .metadata.name,
        .spec.principal.name,
        .spec.role,
        (.status.state // "unknown"),
        (
          [.status.conditions[]?
           | select(.status != "True")
           | "\(.type):\(.reason // "")"
          ] | join(",")
        )
      ]
    | @tsv
  ' |
  column -t -s $'\t'

echo
if [ "$failures" -ne 0 ]; then
  echo "RESULT: FAIL — $failures OAuth/RBAC identity checks failed"
  exit 1
fi

echo "RESULT: PASS — managed-component token identities align"
