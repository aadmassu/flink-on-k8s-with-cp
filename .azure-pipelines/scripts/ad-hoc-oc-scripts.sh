#!/usr/bin/env bash
set -euo pipefail
umask 077

NS="${OC_NS:-dah-flink-dev}"
TOKEN_URL="https://myapps.firstcitizens.com/oauth2/default/v1/token"
EXPECTED_ISSUER="https://myapps.firstcitizens.com/oauth2/default"
EXPECTED_SCOPE="11547.DAH(Dev)"

COMPONENTS=(
  "schemaregistry:oauth-schemaregistry"
  "connect:oauth-connect"
  "kafkarest:oauth-kafkarest"
  "controlcenter:oauth-controlcenter"
  "mds-rest:oauth-mds-rest"
)

WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

echo "=== Runtime validation ==="

python3 - <<'PY'
import sys

if sys.version_info < (3, 6):
    raise SystemExit(
        "FATAL: Python 3.6 or newer is required; found "
        + sys.version.split()[0]
    )

print("Python: {}".format(sys.version.split()[0]))
PY

failures=0

echo
echo "=== Managed-component OAuth identity audit ==="

for item in "${COMPONENTS[@]}"; do
  component=${item%%:*}
  secret=${item#*:}

  response_file="$WORK_DIR/${component}-response.json"
  claims_file="$WORK_DIR/${component}-claims.json"
  bindings_file="$WORK_DIR/${component}-bindings.txt"

  echo
  echo "------------------------------------------------------------"
  echo "Component: $component"
  echo "Secret:    $secret"

  if ! oc -n "$NS" get secret "$secret" >/dev/null 2>&1; then
    echo "FAIL: Secret/$secret does not exist"
    failures=$((failures + 1))
    continue
  fi

  cid=$(
    oc -n "$NS" get secret "$secret" \
      -o jsonpath='{.data.clientId}' |
      base64 -d
  )

  csecret=$(
    oc -n "$NS" get secret "$secret" \
      -o jsonpath='{.data.clientSecret}' |
      base64 -d
  )

  if [ -z "$cid" ] || [ -z "$csecret" ]; then
    echo "FAIL: Secret/$secret has an empty clientId or clientSecret"
    failures=$((failures + 1))
    unset csecret
    continue
  fi

  echo "Secret clientId: $cid"

  http_code=$(
    curl --silent --show-error \
      --output "$response_file" \
      --write-out '%{http_code}' \
      -X POST "$TOKEN_URL" \
      -H 'Content-Type: application/x-www-form-urlencoded' \
      --data-urlencode "client_id=$cid" \
      --data-urlencode "client_secret=$csecret" \
      --data-urlencode 'grant_type=client_credentials' \
      --data-urlencode "scope=$EXPECTED_SCOPE" ||
      true
  )

  unset csecret

  if [ "$http_code" != "200" ]; then
    echo "FAIL: Okta token request returned HTTP $http_code"

    RESPONSE_FILE="$response_file" python3 - <<'PY'
import json
import os

path = os.environ["RESPONSE_FILE"]

try:
    with open(path, encoding="utf-8") as stream:
        response = json.load(stream)
except Exception:
    print("Unable to parse the Okta error response.")
else:
    safe_error = {
        "error": response.get("error"),
        "error_description": response.get("error_description"),
    }
    print(json.dumps(safe_error, indent=2))
PY

    failures=$((failures + 1))
    continue
  fi

  token=$(
    RESPONSE_FILE="$response_file" python3 - <<'PY'
import json
import os

with open(os.environ["RESPONSE_FILE"], encoding="utf-8") as stream:
    response = json.load(stream)

token = response.get("access_token")

if not isinstance(token, str) or not token:
    raise SystemExit(
        "FATAL: Okta response did not contain access_token"
    )

print(token)
PY
  )

  TOKEN="$token" CLAIMS_FILE="$claims_file" python3 - <<'PY'
import base64
import json
import os

token = os.environ["TOKEN"]
claims_file = os.environ["CLAIMS_FILE"]

parts = token.split(".")

if len(parts) != 3:
    raise SystemExit(
        "FATAL: access token is not a three-part JWT"
    )

payload = parts[1]
payload += "=" * (-len(payload) % 4)

try:
    decoded = base64.urlsafe_b64decode(
        payload.encode("ascii")
    )
    claims = json.loads(decoded.decode("utf-8"))
except Exception as exc:
    raise SystemExit(
        "FATAL: unable to decode JWT payload: {}".format(exc)
    )

with open(claims_file, "w", encoding="utf-8") as stream:
    json.dump(claims, stream)
PY

  unset token

  echo "Token claims:"

  CLAIMS_FILE="$claims_file" python3 - <<'PY'
import json
import os

with open(os.environ["CLAIMS_FILE"], encoding="utf-8") as stream:
    claims = json.load(stream)

safe_claims = {
    "sub": claims.get("sub"),
    "client_id": claims.get("client_id"),
    "iss": claims.get("iss"),
    "aud": claims.get("aud"),
    "scp": claims.get("scp"),
    "scope": claims.get("scope"),
    "dahDev_groups": claims.get("dahDev_groups"),
}

print(json.dumps(safe_claims, indent=2))
PY

  echo "Claim validation:"

  if ! CLAIMS_FILE="$claims_file" \
       EXPECTED_CLIENT_ID="$cid" \
       EXPECTED_ISSUER="$EXPECTED_ISSUER" \
       EXPECTED_SCOPE="$EXPECTED_SCOPE" \
       python3 - <<'PY'
import json
import os
import sys

with open(os.environ["CLAIMS_FILE"], encoding="utf-8") as stream:
    claims = json.load(stream)

expected_client_id = os.environ["EXPECTED_CLIENT_ID"]
expected_issuer = os.environ["EXPECTED_ISSUER"]
expected_scope = os.environ["EXPECTED_SCOPE"]

failed = False

subject = claims.get("sub")

if subject == expected_client_id:
    print("PASS: sub matches clientId")
else:
    print(
        "FAIL: token sub {!r} does not equal clientId {!r}".format(
            subject,
            expected_client_id,
        )
    )
    failed = True

issuer = claims.get("iss")

if issuer == expected_issuer:
    print("PASS: issuer")
else:
    print(
        "FAIL: issuer {!r}; expected {!r}".format(
            issuer,
            expected_issuer,
        )
    )
    failed = True

scope_value = claims.get(
    "scp",
    claims.get("scope", []),
)

if isinstance(scope_value, str):
    scopes = scope_value.split()
elif isinstance(scope_value, list):
    scopes = [
        str(value)
        for value in scope_value
    ]
else:
    scopes = []

if expected_scope in scopes:
    print("PASS: required scope exists")
else:
    print(
        "FAIL: required scope {!r} is absent; "
        "token scopes={!r}".format(
            expected_scope,
            scopes,
        )
    )
    failed = True

groups = claims.get("dahDev_groups")

if isinstance(groups, list) and groups:
    print(
        "PASS: dahDev_groups claim exists and is nonempty"
    )
elif isinstance(groups, str) and groups.strip():
    print(
        "PASS: dahDev_groups claim exists and is nonempty"
    )
else:
    print(
        "FAIL: dahDev_groups claim is absent or empty"
    )
    failed = True

audience = claims.get("aud")

if audience:
    print("PASS: audience claim exists")
else:
    print("FAIL: audience claim is absent")
    failed = True

sys.exit(1 if failed else 0)
PY
  then
    failures=$((failures + 1))
  fi

  echo "RBAC bindings:"

  binding_rc=0

  oc -n "$NS" get confluentrolebinding -o json |
    EXPECTED_CLIENT_ID="$cid" python3 -c '
import json
import os
import sys

document = json.load(sys.stdin)
expected = os.environ["EXPECTED_CLIENT_ID"]
matches = []

for item in document.get("items", []):
    spec = item.get("spec", {})
    principal = spec.get("principal", {})

    if principal.get("name") != expected:
        continue

    metadata = item.get("metadata", {})
    status = item.get("status", {})

    matches.append(
        "{}: role={}, state={}".format(
            metadata.get("name", "<unknown>"),
            spec.get("role", "<unknown>"),
            status.get("state", "unknown"),
        )
    )

if matches:
    print("\n".join(matches))
else:
    print("NONE")

sys.exit(0 if matches else 3)
' >"$bindings_file" || binding_rc=$?

  cat "$bindings_file"

  if [ "$binding_rc" -ne 0 ] &&
     [ "$component" != "mds-rest" ]; then
    echo "FAIL: no ConfluentRolebinding matches clientId $cid"
    failures=$((failures + 1))
  fi
done

echo
echo "=== Kafka MDS impersonation administrators ==="

oc -n "$NS" get kafka kafka -o json |
  python3 -c '
import json
import sys

document = json.load(sys.stdin)

admins = (
    document.get("spec", {})
    .get("services", {})
    .get("mds", {})
    .get("impersonation", {})
    .get("admins", [])
)

if not admins:
    print("NONE")
else:
    for admin in admins:
        print(admin)
'

echo
echo "=== ConfluentRolebinding states ==="

oc -n "$NS" get confluentrolebinding -o json |
  python3 -c '
import json
import sys

document = json.load(sys.stdin)

header = "{:<48} {:<28} {:<18} {}".format(
    "NAME",
    "PRINCIPAL",
    "ROLE",
    "STATE",
)

print(header)
print("-" * len(header))

items = sorted(
    document.get("items", []),
    key=lambda item: (
        item.get("metadata", {}).get("name", "")
    ),
)

for item in items:
    metadata = item.get("metadata", {})
    spec = item.get("spec", {})
    status = item.get("status", {})
    principal = spec.get("principal", {})

    print(
        "{:<48} {:<28} {:<18} {}".format(
            metadata.get("name", "<unknown>"),
            principal.get("name", "<unknown>"),
            spec.get("role", "<unknown>"),
            status.get("state", "unknown"),
        )
    )

    for condition in status.get("conditions", []):
        if condition.get("status") != "True":
            print(
                "  condition: {}={} reason={} message={}".format(
                    condition.get("type", ""),
                    condition.get("status", ""),
                    condition.get("reason", ""),
                    condition.get("message", ""),
                )
            )
'

echo

if [ "$failures" -ne 0 ]; then
  echo "RESULT: FAIL — $failures OAuth/RBAC identity checks failed"
  exit 1
fi

echo "RESULT: PASS — managed-component token identities align"
