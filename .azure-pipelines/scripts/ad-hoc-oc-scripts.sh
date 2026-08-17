#!/usr/bin/env bash
set -euo pipefail

# Read-only Java TLS probes from the actual Control Center container.
# Called by validate-confluent-platform.yaml with namespace as argument.
# Does not use jq/Python and does not print credentials or tokens.

NS="${1:-${OC_NS:-dah-flink-dev}}"
POD="${C3_POD:-controlcenter-0}"
CONTAINER="controlcenter"
STORE="/var/ssl/truststore/bundle.jks"
STORE_PASSWORD="truststorepass"

fatal() { echo "FATAL: $*" >&2; exit 1; }
heading() { printf '\n=== %s ===\n' "$*"; }

command -v oc >/dev/null 2>&1 || fatal "oc is unavailable"
oc whoami >/dev/null 2>&1 || fatal "not logged into OpenShift"
oc -n "$NS" get pod "$POD" >/dev/null 2>&1 || fatal "Pod/$POD does not exist"

heading "Target"
echo "Namespace: $NS"
echo "Pod:       $POD"
echo "Container: $CONTAINER"

heading "Running JVM truststore arguments"
oc -n "$NS" exec "$POD" -c "$CONTAINER" -- sh -c \
  'tr "\000" " " </proc/1/cmdline; echo' | \
  sed -E 's/(-D[^ =]*(password|secret)[^ =]*=)[^ ]+/\1<redacted>/Ig'

heading "Install temporary Java TLS probe"
oc -n "$NS" exec -i "$POD" -c "$CONTAINER" -- sh -c 'cat > /tmp/C3TlsProbe.java' <<'JAVA'
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.security.KeyStore;
import java.security.cert.Certificate;
import java.security.cert.X509Certificate;
import java.time.Duration;
import java.util.Collections;
import javax.net.ssl.HttpsURLConnection;

public class C3TlsProbe {
  public static void main(String[] args) {
    String url = args[0];
    System.out.println("URL=" + url);
    System.out.println("trustStore=" + System.getProperty("javax.net.ssl.trustStore"));
    System.out.println("trustStoreType=" + System.getProperty("javax.net.ssl.trustStoreType"));
    try {
      KeyStore ks = KeyStore.getInstance(System.getProperty("javax.net.ssl.trustStoreType"));
      try (java.io.InputStream in = new java.io.FileInputStream(System.getProperty("javax.net.ssl.trustStore"))) {
        ks.load(in, System.getProperty("javax.net.ssl.trustStorePassword").toCharArray());
      }
      System.out.println("trustEntries=" + ks.size());
      for (String alias : Collections.list(ks.aliases())) {
        Certificate cert = ks.getCertificate(alias);
        if (cert instanceof X509Certificate) {
          X509Certificate x = (X509Certificate) cert;
          System.out.println("trustAlias=" + alias + " owner=" + x.getSubjectX500Principal());
        }
      }

      HttpsURLConnection connection = (HttpsURLConnection) URI.create(url).toURL().openConnection();
      connection.setConnectTimeout(10000);
      connection.setReadTimeout(20000);
      connection.setInstanceFollowRedirects(false);
      int status = connection.getResponseCode();
      System.out.println("httpStatus=" + status);
      for (Certificate cert : connection.getServerCertificates()) {
        if (cert instanceof X509Certificate) {
          X509Certificate x = (X509Certificate) cert;
          System.out.println("peerSubject=" + x.getSubjectX500Principal());
          System.out.println("peerIssuer=" + x.getIssuerX500Principal());
        }
      }
      System.out.println("RESULT=TLS_PASS");
    } catch (Throwable t) {
      System.out.println("RESULT=TLS_FAIL");
      Throwable current = t;
      int depth = 0;
      while (current != null && depth++ < 12) {
        System.out.println("error=" + current.getClass().getName() + ": " + current.getMessage());
        current = current.getCause();
      }
      System.exit(2);
    }
  }
}
JAVA

heading "Java runtime"
oc -n "$NS" exec "$POD" -c "$CONTAINER" -- java -version 2>&1
oc -n "$NS" exec "$POD" -c "$CONTAINER" -- test -r "$STORE" || fatal "$STORE is not readable"

probe() {
  local store_type="$1"
  local url="$2"
  echo
  echo "--- type=$store_type url=$url ---"
  set +e
  oc -n "$NS" exec "$POD" -c "$CONTAINER" -- \
    java \
      "-Djavax.net.ssl.trustStore=$STORE" \
      "-Djavax.net.ssl.trustStorePassword=$STORE_PASSWORD" \
      "-Djavax.net.ssl.trustStoreType=$store_type" \
      /tmp/C3TlsProbe.java "$url"
  local rc=$?
  set -e
  echo "probeExitCode=$rc"
}

heading "OIDC and MDS TLS matrix using actual mounted truststore"
for type in PKCS12 JKS; do
  probe "$type" "https://myapps.firstcitizens.com/oauth2/default/.well-known/openid-configuration"
  probe "$type" "https://myapps.firstcitizens.com/oauth2/default/v1/keys"
  probe "$type" "https://myapps.firstcitizens.com/oauth2/default/v1/token"
  probe "$type" "https://kafka.dah-flink-dev.svc.cluster.local:8090/kafka/v3/clusters"
done

heading "Recent full Control Center exception context"
oc -n "$NS" logs "$POD" -c "$CONTAINER" --since=20m 2>&1 | \
  grep -Ei -B 12 -A 30 'PKIX path building failed|SSLHandshakeException|certificate_unknown|ProcessingException' | \
  tail -n 240 || true

heading "Cleanup"
oc -n "$NS" exec "$POD" -c "$CONTAINER" -- sh -c 'rm -f /tmp/C3TlsProbe.java' || true
echo "COMPLETE: Review each RESULT=TLS_PASS/TLS_FAIL entry above."
