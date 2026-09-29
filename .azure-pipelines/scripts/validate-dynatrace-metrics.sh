#!/usr/bin/env bash
# Validate the Dynatrace metrics wiring for the CFK stack in one namespace (runbook H9).
#   1. one <component>-dynatrace-metrics Service per running component, with the
#      metrics.dynatrace.com annotations the FCB ActiveGate expects
#   2. every Service resolves to as many ready endpoints as the component has pods
#   3. each endpoint answers 200 on :7778/metrics (probed from kafka-0)
#   4. a NetworkPolicy admits the dynatrace namespace to 7778 (DEV: our own file;
#      upper envs: the Inter-Namespace Request filed with Container Platforms)
#
# Read-only. STRICT=1 (validate pipeline) exits 1 on any FAIL; STRICT=0 (ad hoc) always
# exits 0. Needs OC_NS and TARGET_ENV from the pipeline; oc already logged in.
set -uo pipefail

NS="${OC_NS:-$(oc project -q 2>/dev/null)}"
ENV_NAME="${TARGET_ENV:-unknown}"
STRICT="${STRICT:-0}"
PORT=7778
PASS=0; WARN=0; FAIL=0
pass() { PASS=$((PASS+1)); echo "  PASS $*"; }
warn() { WARN=$((WARN+1)); echo "  WARN $*"; }
fail() { FAIL=$((FAIL+1)); echo "  FAIL $*"; }

echo "=== Dynatrace metrics wiring: $ENV_NAME / $NS ==="

# --- 1+2. Services, annotations, endpoints vs pods -------------------------------
echo ""
echo "--- Services and endpoints"
COMPONENTS=$(oc -n "$NS" get statefulset -l app.kubernetes.io/part-of=confluent-platform \
  -o jsonpath='{range .items[*]}{.metadata.labels.app\.kubernetes\.io/name}{"="}{.status.readyReplicas}{"\n"}{end}' 2>/dev/null | sort -u)
[ -n "$COMPONENTS" ] || fail "no CFK StatefulSets found in $NS (label app.kubernetes.io/part-of=confluent-platform)"
for entry in $COMPONENTS; do
  comp=${entry%%=*}; ready=${entry#*=}; ready=${ready:-0}
  svc="${comp}-dynatrace-metrics"
  if ! oc -n "$NS" get svc "$svc" >/dev/null 2>&1; then
    fail "$svc missing (apply apps/confluent-platform/$ENV_NAME/monitoring/ via install-or-update)"
    continue
  fi
  ann=$(oc -n "$NS" get svc "$svc" -o go-template='{{index .metadata.annotations "metrics.dynatrace.com/scrape"}} {{index .metadata.annotations "metrics.dynatrace.com/port"}} {{index .metadata.annotations "metrics.dynatrace.com/path"}} {{index .metadata.annotations "metrics.dynatrace.com/secure"}}' 2>/dev/null)
  if [ "$ann" = "true $PORT /metrics false" ]; then
    pass "$svc annotations: scrape=true port=$PORT path=/metrics secure=false"
  else
    fail "$svc annotations wrong or missing: got '$ann', want 'true $PORT /metrics false'"
  fi
  eps=$(oc -n "$NS" get endpointslices -l kubernetes.io/service-name="$svc" -o json 2>/dev/null \
    | python3 -c 'import json,sys
d=json.load(sys.stdin); n=0
for s in d.get("items",[]):
    for e in s.get("endpoints",[]) or []:
        if e.get("conditions",{}).get("ready",True) is not False: n+=len(e.get("addresses",[]))
print(n)' 2>/dev/null || echo 0)
  if [ "$eps" -eq "$ready" ] && [ "$ready" -gt 0 ]; then
    pass "$svc -> $eps ready endpoint(s), matches $comp readyReplicas=$ready"
  else
    fail "$svc -> $eps ready endpoint(s) but $comp readyReplicas=$ready (selector mismatch or pods not ready)"
  fi
done

# --- 3. Probe every endpoint from kafka-0 ----------------------------------------
echo ""
echo "--- Exporter probe (curl from kafka-0 to each Service endpoint)"
PROBE=$(oc -n "$NS" get pods -l app.kubernetes.io/name=kafka -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -z "$PROBE" ]; then
  warn "no kafka pod to probe from"
else
  for entry in $COMPONENTS; do
    comp=${entry%%=*}; svc="${comp}-dynatrace-metrics"
    for ip in $(oc -n "$NS" get endpointslices -l kubernetes.io/service-name="$svc" -o jsonpath='{range .items[*].endpoints[*]}{.addresses[0]}{" "}{end}' 2>/dev/null); do
      pod=$(oc -n "$NS" get pods -o jsonpath="{range .items[?(@.status.podIP==\"$ip\")]}{.metadata.name}{end}" 2>/dev/null)
      res=$(oc -n "$NS" exec "$PROBE" -c kafka -- sh -c "curl -s -o /tmp/dt.txt -w '%{http_code}' --max-time 10 http://$ip:$PORT/metrics; echo; grep -c '' /tmp/dt.txt 2>/dev/null; rm -f /tmp/dt.txt" 2>/dev/null)
      code=$(printf '%s\n' "$res" | sed -n 1p); lines=$(printf '%s\n' "$res" | sed -n 2p)
      if [ "$code" = "200" ] && [ "${lines:-0}" -gt 100 ]; then
        pass "$pod ($ip) :$PORT/metrics -> 200, ${lines} lines"
      else
        fail "$pod ($ip) :$PORT/metrics -> HTTP ${code:-none}, ${lines:-0} lines"
      fi
    done
  done
fi

# --- 4. NetworkPolicy admitting the dynatrace namespace --------------------------
echo ""
echo "--- NetworkPolicy: who may reach :$PORT"
NP_JSON=$(oc -n "$NS" get networkpolicy -o json 2>/dev/null)
verdict=$(printf '%s' "$NP_JSON" | python3 -c '
import json,sys
d=json.load(sys.stdin); port=int(sys.argv[1]); hits=[]; rows=[]
for np in d.get("items",[]):
    name=np["metadata"]["name"]
    for rule in np.get("spec",{}).get("ingress",[]) or []:
        ports=[str(p.get("port")) for p in rule.get("ports",[]) or []]
        if ports and str(port) not in ports: continue
        for f in rule.get("from",[]) or []:
            ns=f.get("namespaceSelector",{}).get("matchLabels",{}) or {}
            pod=f.get("podSelector",{}).get("matchLabels",{}) or {}
            rows.append("%s: from ns=%s pod=%s ports=%s" % (name, ns or "any", pod or "any", ",".join(ports) or "ALL"))
            if ns.get("kubernetes.io/metadata.name")=="dynatrace": hits.append(name)
for r in rows: print("  rule " + r)
print("DYNATRACE_RULE=" + (",".join(hits) if hits else "none"))
' "$PORT" 2>/dev/null)
printf '%s\n' "$verdict" | grep '^  rule' || echo "  (no ingress rules mention :$PORT)"
dt=$(printf '%s\n' "$verdict" | sed -n 's/^DYNATRACE_RULE=//p')
if [ "$dt" != "none" ] && [ -n "$dt" ]; then
  pass "NetworkPolicy admits namespace dynatrace to :$PORT ($dt)"
elif [ "$ENV_NAME" = "dev" ]; then
  fail "no NetworkPolicy rule from namespace dynatrace to :$PORT; apply apps/confluent-platform/dev/network-policy/network-policy.yaml via install-or-update"
else
  warn "no NetworkPolicy rule from namespace dynatrace to :$PORT yet; the Inter-Namespace Request for $NS is still pending with Container Platforms"
fi

# --- Summary ----------------------------------------------------------------------
echo ""
echo "=== Dynatrace metrics summary ($ENV_NAME): PASS=$PASS WARN=$WARN FAIL=$FAIL ==="
if [ "$STRICT" = "1" ] && [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
