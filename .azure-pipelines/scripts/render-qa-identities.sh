#!/usr/bin/env bash
set -euo pipefail

ENV_DIR=${1:-apps/confluent-platform/qa}

if [ ! -d "$ENV_DIR" ]; then
  echo "FATAL: QA manifest directory does not exist: $ENV_DIR" >&2
  exit 1
fi

require_id() {
  local variable_name=$1
  local value=${!variable_name:-}
  if [[ ! "$value" =~ ^0oa[[:alnum:]]+$ ]]; then
    echo "FATAL: $variable_name must contain a nonempty Okta client ID beginning with 0oa." >&2
    exit 1
  fi
}

require_id QA_OAUTH_BROKER_ID
require_id QA_OAUTH_SR_ID
require_id QA_OAUTH_CONNECT_ID
require_id QA_OAUTH_REST_ID
require_id QA_OAUTH_C3_ID

python3 - "$ENV_DIR" <<'PY'
import os
import pathlib
import sys

env_dir = pathlib.Path(sys.argv[1])
replacements = {
    "__QA_OAUTH_BROKER_CLIENT_ID__": os.environ["QA_OAUTH_BROKER_ID"],
    "__QA_OAUTH_SR_CLIENT_ID__": os.environ["QA_OAUTH_SR_ID"],
    "__QA_OAUTH_CONNECT_CLIENT_ID__": os.environ["QA_OAUTH_CONNECT_ID"],
    "__QA_OAUTH_REST_CLIENT_ID__": os.environ["QA_OAUTH_REST_ID"],
    "__QA_OAUTH_C3_CLIENT_ID__": os.environ["QA_OAUTH_C3_ID"],
}

changed = 0
for path in sorted(env_dir.rglob("*.yaml")):
    text = path.read_text(encoding="utf-8")
    rendered = text
    for token, value in replacements.items():
        rendered = rendered.replace(token, value)
    if rendered != text:
        path.write_text(rendered, encoding="utf-8")
        changed += 1

remaining = []
for path in sorted(env_dir.rglob("*.yaml")):
    text = path.read_text(encoding="utf-8")
    if "__QA_OAUTH_" in text:
        remaining.append(str(path))

if remaining:
    print("FATAL: unresolved QA identity tokens remain:", file=sys.stderr)
    for path in remaining:
        print("  " + path, file=sys.stderr)
    raise SystemExit(1)

print("Rendered verified QA identities into {} manifest file(s).".format(changed))
PY

echo "PASS: QA manifests contain no unresolved identity tokens."
