#!/usr/bin/env bash
# Kafka `client` listener through TLS-passthrough Ingresses on 443 (runbook H10).
#
#   kafka-passthrough.sh render-apply   discover the advertised hosts + CFK Services for the
#                                       listener, render ingress/kafka-client-passthrough.yaml.tmpl
#                                       once per endpoint, apply, then prove the external TLS path
#   kafka-passthrough.sh check          read-only version (validate pipeline, ad hoc script)
#
# Needs OC_NS, TARGET_ENV, ENV_DIR (apps/confluent-platform/<env>); oc logged in.
# Skips cleanly when the env has no template. STRICT=1 makes `check` exit 1 on FAIL.
set -uo pipefail

MODE="${1:-check}"
NS="${OC_NS:?OC_NS required}"
ENV_NAME="${TARGET_ENV:-unknown}"
ENV_DIR="${ENV_DIR:-apps/confluent-platform/$ENV_NAME}"
TMPL="$ENV_DIR/ingress/kafka-client-passthrough.yaml.tmpl"
LISTENER="${KAFKA_CLIENT_LISTENER:-client}"
LPORT="${KAFKA_CLIENT_PORT:-9093}"
KAFKA_CR="${KAFKA_CR_NAME:-kafka}"
STRICT="${STRICT:-0}"
PASS=0; WARN=0; FAIL=0
pass() { PASS=$((PASS+1)); echo "  PASS $*"; }
warn() { WARN=$((WARN+1)); echo "  WARN $*"; }
fail() { FAIL=$((FAIL+1)); echo "  FAIL $*"; }
finish() {
  echo ""
  echo "=== Kafka passthrough summary ($ENV_NAME): PASS=$PASS WARN=$WARN FAIL=$FAIL ==="
  if [ "$FAIL" -gt 0 ] && { [ "$STRICT" = "1" ] || [ "$MODE" = "render-apply" ]; }; then exit 1; fi
  exit 0
}

echo "=== Kafka '$LISTENER' listener passthrough ($MODE): $ENV_NAME / $NS ==="
if [ ! -f "$TMPL" ]; then
  echo "No $TMPL in this environment; the client listener is not exposed here. Skipping."
  exit 0
fi

# --- 1. The CR carries the listener and admission kept externalAccess --------------------
echo ""
echo "--- Kafka CR"
ea=$(oc -n "$NS" get kafka "$KAFKA_CR" -o jsonpath="{.spec.listeners.custom[?(@.name==\"$LISTENER\")].externalAccess.type}" 2>/dev/null)
dom=$(oc -n "$NS" get kafka "$KAFKA_CR" -o jsonpath="{.spec.listeners.custom[?(@.name==\"$LISTENER\")].externalAccess.staticForHostBasedRouting.domain}" 2>/dev/null)
if [ "$ea" = "staticForHostBasedRouting" ] && [ -n "$dom" ]; then
  pass "stored CR has listeners.custom[$LISTENER].externalAccess=staticForHostBasedRouting domain=$dom"
else
  fail "stored CR lacks externalAccess on listener '$LISTENER' (got type='$ea' domain='$dom'); silent strip at admission or Kafka not applied yet"
  finish
fi
ready=$(oc -n "$NS" get kafka "$KAFKA_CR" -o jsonpath='{.status.conditions[?(@.type=="platform.confluent.io/cluster-ready")].status}' 2>/dev/null)
[ "$ready" = "True" ] && pass "Kafka cluster-ready=True" || warn "Kafka cluster-ready=$ready (brokers may still be rolling for the new listener)"

# --- 2. CFK Services that front the listener ---------------------------------------------
echo ""
echo "--- Services exposing :$LPORT"
SVC_JSON=$(oc -n "$NS" get svc -o json 2>/dev/null)
BOOT_SVC=$(printf '%s' "$SVC_JSON" | python3 -c '
import json,sys; port=int(sys.argv[1]); d=json.load(sys.stdin); out=[]
for s in d["items"]:
    n=s["metadata"]["name"]; ports=[p.get("port") for p in s["spec"].get("ports",[])]
    if port in ports and n.endswith("-bootstrap"): out.append(n)
print(" ".join(sorted(out)))' "$LPORT")
BROKER_SVCS=$(printf '%s' "$SVC_JSON" | python3 -c '
import json,sys,re; port=int(sys.argv[1]); d=json.load(sys.stdin); out=[]
for s in d["items"]:
    n=s["metadata"]["name"]; ports=[p.get("port") for p in s["spec"].get("ports",[])]
    if port in ports and re.match(r"^.+-\d+-internal$", n): out.append(n)
print(" ".join(sorted(out)))' "$LPORT")
echo "  bootstrap service(s): ${BOOT_SVC:-<none>}"
echo "  per-broker service(s): ${BROKER_SVCS:-<none>}"
if [ -z "$BOOT_SVC" ] || [ -z "$BROKER_SVCS" ]; then
  echo "  all Services in $NS:"; printf '%s' "$SVC_JSON" | python3 -c 'import json,sys; [print("   ", s["metadata"]["name"], [p.get("port") for p in s["spec"].get("ports",[])]) for s in json.load(sys.stdin)["items"]]'
  fail "CFK has not created the bootstrap / per-broker Services for :$LPORT yet"
  finish
fi
BOOT_SVC=${BOOT_SVC%% *}
pass "bootstrap Service $BOOT_SVC and $(echo $BROKER_SVCS | wc -w | tr -d ' ') per-broker Service(s) present"

# --- 3. Advertised hosts, read from the brokers themselves --------------------------------
echo ""
echo "--- Advertised listeners (kafka-configs from kafka-0 over the internal PLAIN listener)"
PLAIN=$(oc -n "$NS" get secret sasl-plain-internal -o go-template='{{index .data "plain.txt"}}' 2>/dev/null | base64 -d)
AUSER=$(printf '%s\n' "$PLAIN" | sed -n 's/^username=//p' | head -1); APWD=$(printf '%s\n' "$PLAIN" | sed -n 's/^password=//p' | head -1)
POD="${KAFKA_CR}-0"; PDIR="/tmp/kpt-$$"
oc -n "$NS" exec "$POD" -c kafka -- sh -c "mkdir -p $PDIR && chmod 700 $PDIR" >/dev/null 2>&1
printf 'security.protocol=SASL_SSL\nsasl.mechanism=PLAIN\nsasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username="%s" password="%s";\nssl.truststore.location=/var/ssl/truststore/bundle.p12\nssl.truststore.password=changeit\nssl.truststore.type=PKCS12\n' "$AUSER" "$APWD" \
  | oc -n "$NS" exec -i "$POD" -c kafka -- sh -c "umask 077; cat > $PDIR/admin.properties"
declare -A HOST_BY_ID=()
UP=$(printf '%s' "$LISTENER" | tr '[:lower:]' '[:upper:]')
for svc in $BROKER_SVCS; do
  id=$(printf '%s' "$svc" | sed -E 's/^.+-([0-9]+)-internal$/\1/')
  adv=$(oc -n "$NS" exec "$POD" -c kafka -- kafka-configs --bootstrap-server "${KAFKA_CR}.${NS}.svc.cluster.local:9071" --command-config "$PDIR/admin.properties" \
        --entity-type brokers --entity-name "$id" --describe --all 2>/dev/null | grep -oE 'advertised.listeners=[^ ]+' | head -1)
  host=$(printf '%s' "$adv" | tr ',' '\n' | grep -E "^(advertised.listeners=)?${UP}://" | sed -E 's#.*://##; s#:[0-9]+$##')
  if [ -n "$host" ]; then HOST_BY_ID[$id]="$host"; pass "broker $id advertises ${UP}://$host:443"; else fail "broker $id: no ${UP}:// entry in '$adv'"; fi
done
oc -n "$NS" exec "$POD" -c kafka -- sh -c "rm -rf $PDIR" >/dev/null 2>&1
[ "${#HOST_BY_ID[@]}" -gt 0 ] || finish
first=$(printf '%s\n' "${HOST_BY_ID[@]}" | head -1)
DOMAIN=${first#*.}
BOOT_HOST="${BOOT_SVC%-bootstrap}.${DOMAIN}"
echo "  bootstrap host: $BOOT_HOST:443  (derived: ${BOOT_SVC%-bootstrap} + .$DOMAIN)"

# --- 4. Render + apply (render-apply) or check presence (check) ---------------------------
echo ""
echo "--- Ingresses"
render_one() { # name host service
  sed -e "s/__NAME__/$1/g" -e "s/__HOST__/$2/g" -e "s/__SERVICE__/$3/g" "$TMPL"
}
OUT=$(mktemp)
{ render_one "kafka-${LISTENER}-bootstrap" "$BOOT_HOST" "$BOOT_SVC"
  for id in $(printf '%s\n' "${!HOST_BY_ID[@]}" | sort -n); do
    svc=$(printf '%s\n' $BROKER_SVCS | grep -E "^.+-${id}-internal$")
    render_one "kafka-${LISTENER}-${id}" "${HOST_BY_ID[$id]}" "$svc"
  done; } > "$OUT"
if [ "$MODE" = "render-apply" ]; then
  echo "  rendered $(grep -c '^kind: Ingress' "$OUT") Ingress object(s):"; grep -E '^\s+- host:|^  name:' "$OUT" | sed 's/^/    /'
  if oc apply --dry-run=server -f "$OUT" >/dev/null && oc apply -f "$OUT"; then
    pass "Ingresses applied"
  else
    fail "oc apply of the rendered passthrough Ingresses failed"; rm -f "$OUT"; finish
  fi
fi
rm -f "$OUT"
for name in "kafka-${LISTENER}-bootstrap" $(for id in "${!HOST_BY_ID[@]}"; do echo "kafka-${LISTENER}-${id}"; done); do
  if oc -n "$NS" get ingress "$name" >/dev/null 2>&1; then
    routes=$(oc -n "$NS" get route -l "app.kubernetes.io/instance=$name" -o jsonpath='{range .items[*]}{.spec.host}{" ("}{.spec.tls.termination}{") "}{end}' 2>/dev/null)
    [ -n "$routes" ] && pass "ingress $name -> route $routes" || warn "ingress $name exists but no Route admitted yet"
  else
    fail "ingress $name missing"
  fi
done

# --- 5. External proof from the build agent: TLS handshake through the router with SNI ----
echo ""
echo "--- External TLS path from this agent (openssl s_client with SNI; expects the kafka-tls cert)"
for h in "$BOOT_HOST" "${HOST_BY_ID[@]}"; do
  san=$(echo | timeout 15 openssl s_client -connect "$h:443" -servername "$h" 2>/dev/null | openssl x509 -noout -ext subjectAltName 2>/dev/null | tr -d ' \n')
  if printf '%s' "$san" | grep -q "DNS:$h"; then
    pass "$h:443 handshake OK, certificate lists $h"
  elif [ -n "$san" ]; then
    fail "$h:443 handshake OK but certificate SANs do not include $h (SAN: $(printf '%s' "$san" | cut -c1-160)); client hostname verification will fail"
  else
    fail "$h:443 no TLS handshake from the agent (DNS, firewall from this agent, or Route not admitted)"
  fi
done

echo ""
echo "Client bootstrap for applications outside the cluster: $BOOT_HOST:443  (SASL_SSL / OAUTHBEARER, keep hostname verification on)"
finish
