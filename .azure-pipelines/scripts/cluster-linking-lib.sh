#!/usr/bin/env bash
# Shared helpers for .azure-pipelines/cluster-linking.yaml. Source this file;
# every function assumes `oc` is logged in and $LINK_DIR points at
# apps/confluent-platform/<env>/cluster-linking. Runbook I1-I4.

fatal() { echo "FATAL: $*" >&2; exit 1; }
info()  { echo "--- $*"; }

# Load link.env into the current shell (KEY=VALUE lines, # comments allowed).
load_link_env() {
  local f="$LINK_DIR/link.env"
  [ -f "$f" ] || fatal "missing $f"
  local line key val
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|\#*) continue ;; esac
    key=${line%%=*}
    val=${line#*=}
    [[ "$key" =~ ^[A-Z0-9_]+$ ]] || fatal "link.env: bad key on line: $line"
    printf -v "$key" '%s' "$val"
    export "$key"
  done < "$f"
  : "${LINK_NAME:?link.env must set LINK_NAME}"
  : "${SCHEMA_LINK_NAME:?link.env must set SCHEMA_LINK_NAME}"
  : "${DEST_NAMESPACE:?link.env must set DEST_NAMESPACE}"
  : "${SOURCE_BOOTSTRAP:?link.env must set SOURCE_BOOTSTRAP}"
  : "${LOCAL_BOOTSTRAP:?link.env must set LOCAL_BOOTSTRAP}"
  resolve_vargroup_markers
  LINK_OAUTH_SECRET=${LINK_OAUTH_SECRET:-oauth-clusterlink}
  SOURCE_CA_SECRET=${SOURCE_CA_SECRET:-clusterlink-source-ca}
  DEST_KAFKA_NAME=${DEST_KAFKA_NAME:-kafka}
  DEST_SR_NAME=${DEST_SR_NAME:-schemaregistry}
  KAFKA_POD="${DEST_KAFKA_NAME}-0"
  SR_POD="${DEST_SR_NAME}-0"
  POD_DIR=/tmp/cl-$(date +%s)-$$
}

# A variable-group value handed in through the environment; rejects unset and unexpanded $(..) macros.
vg_value() {
  local name=$1 val=${!1:-}
  if [ -z "$val" ] || [[ "$val" =~ ^\$\( ]]; then
    fatal "$2 is @vargroup but pipeline variable $3 is missing from the variable group (got '${val:-<empty>}')"
  fi
  printf '%s' "$val"
}

# Replace @vargroup markers in link.env with values from kafka-openshift-credentials-<env>
# (passed to the step as VG_KAFKA_BROKER_HOSTS, VG_SCHEMA_REGISTRY_HOSTS, VG_OAUTH_TOKEN_URL).
resolve_vargroup_markers() {
  local raw hosts=() h out=""
  if [ "$SOURCE_BOOTSTRAP" = "@vargroup" ]; then
    raw=$(vg_value VG_KAFKA_BROKER_HOSTS SOURCE_BOOTSTRAP "<env>-kafka-broker-hosts")
    IFS=',' read -ra hosts <<< "$raw"
    for h in "${hosts[@]}"; do
      h=$(printf '%s' "$h" | tr -d '[:space:]'); h=${h#*://}; h=${h%%:*}; h=${h%%/*}
      [ -n "$h" ] || continue
      out+="${out:+,}$h:${SOURCE_BOOTSTRAP_PORT:-9092}"
    done
    [ -n "$out" ] || fatal "<env>-kafka-broker-hosts resolved to no hosts"
    SOURCE_BOOTSTRAP=$out
    info "SOURCE_BOOTSTRAP from variable group: $SOURCE_BOOTSTRAP"
  fi
  if [ -n "${SOURCE_HOST_PREFIX:-}" ] && [[ "$SOURCE_BOOTSTRAP" != REPLACE_WITH_* ]]; then
    IFS=',' read -ra hosts <<< "$SOURCE_BOOTSTRAP"
    for h in "${hosts[@]}"; do
      case "$h" in
        "$SOURCE_HOST_PREFIX"*) ;;
        *) fatal "source broker $h does not start with SOURCE_HOST_PREFIX=$SOURCE_HOST_PREFIX; <env>-kafka-broker-hosts points at another environment's cluster" ;;
      esac
    done
  fi
  if [ "${SOURCE_SR_URL:-}" = "@vargroup" ]; then
    raw=$(vg_value VG_SCHEMA_REGISTRY_HOSTS SOURCE_SR_URL "<env>-schema-registry-hosts")
    h=${raw%%,*}; h=$(printf '%s' "$h" | tr -d '[:space:]'); h=${h#*://}; h=${h%%:*}; h=${h%%/*}
    [ -n "$h" ] || fatal "<env>-schema-registry-hosts resolved to no host"
    SOURCE_SR_URL="https://$h:${SOURCE_SR_PORT:-8081}"
    info "SOURCE_SR_URL from variable group: $SOURCE_SR_URL"
    if [ -n "${SOURCE_HOST_PREFIX:-}" ]; then
      case "$h" in "$SOURCE_HOST_PREFIX"*) ;; *) fatal "source SR host $h does not start with SOURCE_HOST_PREFIX=$SOURCE_HOST_PREFIX" ;; esac
    fi
  fi
  if [ "${SOURCE_OAUTH_TOKEN_ENDPOINT:-}" = "@vargroup" ]; then
    SOURCE_OAUTH_TOKEN_ENDPOINT=$(vg_value VG_OAUTH_TOKEN_URL SOURCE_OAUTH_TOKEN_ENDPOINT "kafka-oauthbearer-token-endpoint-url")
    info "SOURCE_OAUTH_TOKEN_ENDPOINT from variable group: $SOURCE_OAUTH_TOKEN_ENDPOINT"
  fi
  export SOURCE_BOOTSTRAP SOURCE_SR_URL SOURCE_OAUTH_TOKEN_ENDPOINT
}

# Fail if any value the current action depends on is still a placeholder.
require_no_placeholders() {
  local v
  for v in "$@"; do
    case "${!v:-}" in
      REPLACE_WITH_*) fatal "$v is still a placeholder (${!v}) in $LINK_DIR/link.env" ;;
      '') fatal "$v is empty in $LINK_DIR/link.env" ;;
    esac
  done
}

# Run a command inside the kafka broker pod.
kexec() { oc -n "$DEST_NAMESPACE" exec "$KAFKA_POD" -c kafka -- "$@"; }

# Run a Kafka CLI tool inside the broker pod with the OAuth URL allowlist that Kafka 4.x
# clients require (org.apache.kafka.sasl.oauthbearer.allowed.urls); without it every
# OAUTHBEARER login fails with "The URL cannot be accessed due to restrictions" (runbook I6).
# The JVM truststore flags matter too: the token retriever speaks HTTPS to Okta through the
# JVM default trust, not through ssl.truststore.* in the client properties, and the JDK
# cacerts do not carry the FCB / Zscaler chain that fronts Okta (runbook I6).
kcli() {
  local allowed="${SOURCE_OAUTH_TOKEN_ENDPOINT:-}"
  case "$allowed" in */v1/token) allowed="$allowed,${allowed%/v1/token}/v1/keys" ;; esac
  local ts="${LOCAL_TRUSTSTORE:-/var/ssl/truststore/bundle.p12}" tsp="${LOCAL_TRUSTSTORE_PASSWORD:-changeit}"
  oc -n "$DEST_NAMESPACE" exec "$KAFKA_POD" -c kafka -- sh -c \
    'export KAFKA_OPTS="${KAFKA_OPTS:-} -Dorg.apache.kafka.sasl.oauthbearer.allowed.urls=$1 -Djavax.net.ssl.trustStore=$2 -Djavax.net.ssl.trustStorePassword=$3 -Djavax.net.ssl.trustStoreType=PKCS12"; shift 3; exec "$@"' \
    sh "$allowed" "$ts" "$tsp" "$@"
}
# Run a command inside the schema registry pod.
srexec() { oc -n "$DEST_NAMESPACE" exec "$SR_POD" -c schemaregistry -- "$@"; }

# Copy stdin into a file inside the kafka pod without echoing it.
kput() {
  local dest=$1
  oc -n "$DEST_NAMESPACE" exec -i "$KAFKA_POD" -c kafka -- sh -c "mkdir -p '$(dirname "$dest")' && umask 077 && cat > '$dest'"
}

pod_prepare() {
  oc -n "$DEST_NAMESPACE" get pod "$KAFKA_POD" >/dev/null || fatal "pod $KAFKA_POD not found in $DEST_NAMESPACE"
  kexec sh -c "mkdir -p '$POD_DIR' && chmod 700 '$POD_DIR'"
}

pod_cleanup() {
  kexec sh -c "rm -rf '$POD_DIR'" >/dev/null 2>&1 || true
}

# Read one key out of an Opaque Secret (base64-decoded). go-template `index` handles
# keys with dots (plain.txt, ca.crt), which jsonpath would misread as nested fields.
secret_key() {
  local name=$1 key=$2
  oc -n "$DEST_NAMESPACE" get secret "$name" -o go-template="{{index .data \"$key\"}}" 2>/dev/null | base64 -d
}

# Linking principal credentials from the oauth-clusterlink Secret.
load_link_credentials() {
  LINK_CLIENT_ID=$(secret_key "$LINK_OAUTH_SECRET" clientId)
  LINK_CLIENT_SECRET=$(secret_key "$LINK_OAUTH_SECRET" clientSecret)
  [ -n "$LINK_CLIENT_ID" ] && [ -n "$LINK_CLIENT_SECRET" ] \
    || fatal "Secret $LINK_OAUTH_SECRET in $DEST_NAMESPACE lacks clientId/clientSecret (run create-link-prereqs)"
}

# Admin password for the CFK internal listener from sasl-plain-internal.
load_local_admin() {
  local plain
  plain=$(secret_key sasl-plain-internal plain.txt)
  LOCAL_ADMIN_USER=$(printf '%s\n' "$plain" | sed -n 's/^username=//p' | head -1)
  LOCAL_ADMIN_PWD=$(printf '%s\n' "$plain" | sed -n 's/^password=//p' | head -1)
  [ -n "$LOCAL_ADMIN_USER" ] && [ -n "$LOCAL_ADMIN_PWD" ] \
    || fatal "sasl-plain-internal/plain.txt does not carry username=/password= lines"
}

# Client properties for the SOURCE cluster (OAUTHBEARER over TLS), written into the pod.
write_source_props() {
  load_link_credentials
  SOURCE_PROPS="$POD_DIR/source.properties"
  kput "$SOURCE_PROPS" <<EOF
bootstrap.servers=$SOURCE_BOOTSTRAP
security.protocol=SASL_SSL
sasl.mechanism=OAUTHBEARER
sasl.login.callback.handler.class=org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginCallbackHandler
sasl.oauthbearer.token.endpoint.url=$SOURCE_OAUTH_TOKEN_ENDPOINT
sasl.oauthbearer.client.credentials.client.id=$LINK_CLIENT_ID
sasl.oauthbearer.client.credentials.client.secret=$LINK_CLIENT_SECRET
sasl.oauthbearer.scope=$SOURCE_OAUTH_SCOPE
sasl.jaas.config=org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginModule required;
ssl.truststore.location=${LOCAL_TRUSTSTORE:-/var/ssl/truststore/bundle.p12}
ssl.truststore.password=${LOCAL_TRUSTSTORE_PASSWORD:-changeit}
ssl.truststore.type=PKCS12
request.timeout.ms=30000
default.api.timeout.ms=60000
EOF
}

# Client properties for the LOCAL (CFK) cluster over the internal PLAIN listener.
write_local_props() {
  load_local_admin
  LOCAL_PROPS="$POD_DIR/local.properties"
  kput "$LOCAL_PROPS" <<EOF
bootstrap.servers=$LOCAL_BOOTSTRAP
security.protocol=SASL_SSL
sasl.mechanism=PLAIN
sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username="$LOCAL_ADMIN_USER" password="$LOCAL_ADMIN_PWD";
ssl.truststore.location=${LOCAL_TRUSTSTORE:-/var/ssl/truststore/bundle.p12}
ssl.truststore.password=${LOCAL_TRUSTSTORE_PASSWORD:-changeit}
ssl.truststore.type=PKCS12
request.timeout.ms=30000
default.api.timeout.ms=60000
EOF
}

# curl config carrying the OAuth client credentials, used to mint a bearer token in-pod.
write_token_config() {
  load_link_credentials
  TOKEN_CFG="$POD_DIR/token.curl"
  kput "$TOKEN_CFG" <<EOF
url = "$SOURCE_OAUTH_TOKEN_ENDPOINT"
user = "$LINK_CLIENT_ID:$LINK_CLIENT_SECRET"
data = "grant_type=client_credentials&scope=$SOURCE_OAUTH_SCOPE"
silent
show-error
EOF
}

# PEM copy of the FCB trust bundle for curl (the pod only carries the PKCS12 form).
pod_ca_pem() {
  CA_PEM="$POD_DIR/ca.pem"
  if ! kexec sh -c "openssl pkcs12 -in '${LOCAL_TRUSTSTORE:-/var/ssl/truststore/bundle.p12}' -passin pass:'${LOCAL_TRUSTSTORE_PASSWORD:-changeit}' -nokeys -out '$CA_PEM' >/dev/null 2>&1 && test -s '$CA_PEM'"; then
    echo "WARN: could not extract a PEM bundle from the pod truststore; curl falls back to -k"
    CA_PEM=""
  fi
  CURL_CA=${CA_PEM:+--cacert $CA_PEM}
  CURL_CA=${CURL_CA:--k}
}

# Mint a bearer token for the linking principal from inside the pod; prints only the token length.
mint_token() {
  write_token_config
  pod_ca_pem
  TOKEN_FILE="$POD_DIR/token.txt"
  kexec sh -c "curl -K '$TOKEN_CFG' $CURL_CA" \
    | python3 -c 'import json,sys; print(json.load(sys.stdin).get("access_token",""))' \
    | kput "$TOKEN_FILE"
  local n
  n=$(kexec sh -c "wc -c < '$TOKEN_FILE'")
  if [ "${n:-0}" -le 20 ]; then
    echo "Okta response for client ${LINK_CLIENT_ID:0:8}... scope $SOURCE_OAUTH_SCOPE:"
    kexec sh -c "curl -K '$TOKEN_CFG' $CURL_CA -w '\nHTTP %{http_code}\n'" | sed -E 's/"access_token" *: *"[^"]*"/"access_token":"***"/'
    return 1
  fi
  info "OAuth token obtained (${n} bytes) for client ${LINK_CLIENT_ID:0:8}..."
}

# HTTP GET against a Schema Registry URL with the bearer token; prints "<status> <body>".
sr_get() {
  local url=$1
  kexec sh -c "curl -s $CURL_CA -o '$POD_DIR/sr.body' -w '%{http_code}' -H \"Authorization: Bearer \$(cat '$TOKEN_FILE')\" '$url'; echo; cat '$POD_DIR/sr.body'; rm -f '$POD_DIR/sr.body'"
}

# Source cluster id via kafka-cluster (Kafka 3.x) with the source client config.
discover_source_cluster_id() {
  local out
  out=$(kcli kafka-cluster cluster-id --bootstrap-server "${SOURCE_BOOTSTRAP%%,*}" --config "$SOURCE_PROPS" 2>&1) \
    || { echo "$out"; fatal "kafka-cluster cluster-id against the source failed"; }
  SOURCE_CLUSTER_ID_LIVE=$(printf '%s\n' "$out" | sed -n 's/^Cluster ID: *//p' | tail -1)
  [ -n "$SOURCE_CLUSTER_ID_LIVE" ] || { echo "$out"; fatal "could not parse the source cluster id"; }
}

# Live schema.registry.group.id of the CFK SR (its RBAC cluster id). Tried in order:
# CFK shared-config ConfigMap, properties files inside the pod, the CR's configOverrides,
# then CFK's default id_schemaregistry_<namespace>. Each attempt is echoed for diagnosis.
discover_dest_sr_cluster_id() {
  local v="" src=""
  v=$(oc -n "$DEST_NAMESPACE" get configmap "${DEST_SR_NAME}-shared-config" -o jsonpath='{.data.schema-registry\.properties}' 2>/dev/null \
      | grep '^schema.registry.group.id=' | head -1 | cut -d= -f2-)
  echo "  configmap ${DEST_SR_NAME}-shared-config: ${v:-<not found>}"
  [ -n "$v" ] && src="configmap"
  if [ -z "$v" ]; then
    v=$(srexec sh -c 'for f in /mnt/config/schema-registry.properties /mnt/config/init/schema-registry.properties /opt/confluentinc/etc/schema-registry/schema-registry.properties /etc/schema-registry/schema-registry.properties $(find /mnt /opt/confluentinc/etc /etc/schema-registry -maxdepth 4 -name "schema-registry.properties" 2>/dev/null); do [ -f "$f" ] && grep -h "^schema.registry.group.id=" "$f" 2>/dev/null && break; done' 2>/dev/null | head -1 | cut -d= -f2-)
    echo "  properties file in $SR_POD: ${v:-<not found>}"
    [ -n "$v" ] && src="pod"
  fi
  if [ -z "$v" ]; then
    v=$(oc -n "$DEST_NAMESPACE" get schemaregistry "$DEST_SR_NAME" -o jsonpath='{.spec.configOverrides.server}' 2>/dev/null \
      | tr ',[]" ' '\n' | grep '^schema.registry.group.id=' | head -1 | cut -d= -f2-)
    echo "  CR spec.configOverrides.server: ${v:-<not set>}"
    [ -n "$v" ] && src="cr-override"
  fi
  if [ -z "$v" ]; then
    v="id_schemaregistry_${DEST_NAMESPACE}"; src="cfk-default"
    echo "  falling back to CFK default: $v"
  fi
  DEST_SR_CLUSTER_ID_LIVE=$v
  info "destination SR cluster id: $DEST_SR_CLUSTER_ID_LIVE (from $src)"
}

# Resolve @discover / @live markers into SOURCE_CLUSTER_ID / DEST_SR_CLUSTER_ID.
resolve_markers() {
  if [ "${SOURCE_CLUSTER_ID:-@discover}" = "@discover" ]; then
    discover_source_cluster_id
    SOURCE_CLUSTER_ID=$SOURCE_CLUSTER_ID_LIVE
  fi
  if [ "${DEST_SR_CLUSTER_ID:-@live}" = "@live" ]; then
    discover_dest_sr_cluster_id
    DEST_SR_CLUSTER_ID=$DEST_SR_CLUSTER_ID_LIVE
  fi
  export SOURCE_CLUSTER_ID DEST_SR_CLUSTER_ID
  info "source Kafka cluster id: $SOURCE_CLUSTER_ID"
  info "destination SR cluster id: $DEST_SR_CLUSTER_ID"
}

# Mirror-topic names from topics.txt (mirror side of any rename).
mirror_topic_names() {
  python3 .azure-pipelines/scripts/render_clusterlink.py --env-dir "$LINK_DIR" --list-mirrors
}

# kafka-mirrors --describe for one topic on the local cluster.
describe_mirror() {
  local topic=$1
  kcli kafka-mirrors --describe --topics "$topic" --pedantic \
    --bootstrap-server "$LOCAL_BOOTSTRAP" --command-config "$LOCAL_PROPS" 2>&1
}

# kafka-cluster-links --describe for the link on the local cluster.
describe_link() {
  kcli kafka-cluster-links --list --link "$LINK_NAME" --include-topics \
    --bootstrap-server "$LOCAL_BOOTSTRAP" --command-config "$LOCAL_PROPS" 2>&1
}

# Wait until every mirror topic reports the wanted state (default ACTIVE).
wait_for_mirror_state() {
  local want=${1:-ACTIVE} timeout_min=${2:-10}; shift 2 || true
  local topics=("$@") deadline=$(( $(date +%s) + timeout_min*60 ))
  local pending t out state
  while :; do
    pending=()
    for t in "${topics[@]}"; do
      out=$(describe_mirror "$t") || true
      state=$(printf '%s\n' "$out" | grep -E '^\s*Topic:' | grep -oE 'State: *[A-Z_]+' | head -1 | awk '{print $2}')
      [ "$state" = "$want" ] || pending+=("$t:${state:-UNKNOWN}")
    done
    if [ ${#pending[@]} -eq 0 ]; then
      info "all ${#topics[@]} mirror topic(s) are $want"
      return 0
    fi
    if [ "$(date +%s)" -ge "$deadline" ]; then
      echo "still not $want after ${timeout_min}m: ${pending[*]}"
      return 1
    fi
    echo "waiting for $want: ${pending[*]}"
    sleep 20
  done
}
