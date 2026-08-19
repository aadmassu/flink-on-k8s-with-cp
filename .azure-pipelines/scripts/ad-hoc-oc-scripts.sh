#!/usr/bin/env bash
set -euo pipefail

NS="dah-flink-dev"

echo "=== 1. Wait for Control Center ==="
oc -n "$NS" wait controlcenter/controlcenter \
  --for=condition=platform.confluent.io/cluster-ready=True \
  --timeout=15m

oc -n "$NS" wait pod/controlcenter-0 \
  --for=condition=Ready \
  --timeout=15m

echo "=== 2. Confirm corrected rendered property ==="
oc -n "$NS" exec controlcenter-0 -c controlcenter -- sh -c \
  'grep -E "^confluent\.controlcenter\.rest\.ssl\." /opt/confluentinc/etc/controlcenter/control-center.properties 2>/dev/null ||
   grep -R -E "^confluent\.controlcenter\.rest\.ssl\." /opt/confluentinc/etc 2>/dev/null'

echo "=== 3. Confirm obsolete property is absent ==="
if oc -n "$NS" exec controlcenter-0 -c controlcenter -- sh -c \
  'grep -R -q "^confluent\.controlcenter\.rest\.client\.ssl\." /opt/confluentinc/etc 2>/dev/null'
then
  echo "FAIL: obsolete rest.client.ssl property remains"
  exit 1
else
  echo "PASS: obsolete property is absent"
fi

echo "=== 4. Confirm JVM truststore ==="
oc -n "$NS" exec controlcenter-0 -c controlcenter -- sh -c \
  'tr "\000" "\n" </proc/1/cmdline |
   grep -E "javax.net.ssl.trustStore(=|Password=|Type=)"'

echo "=== 5. Recent C3 errors before SSO test ==="
oc -n "$NS" logs controlcenter-0 -c controlcenter --since=10m |
  grep -Ei -C 10 \
  'PKIX|SSLHandshakeException|certificate_unknown|ProcessingException|oidc|authorization-code' || true

echo "PASS: Control Center is ready for an SSO test."