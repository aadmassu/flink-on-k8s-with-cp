#!/usr/bin/env bash
set -euo pipefail

NS="${NS:-dah-flink-dev}"
TRUSTSTORE="/var/ssl/truststore/bundle.p12"
TRUSTSTORE_PASSWORD="changeit"

OKTA_DISCOVERY="https://myapps.firstcitizens.com/oauth2/default/.well-known/openid-configuration"
OKTA_TOKEN="https://myapps.firstcitizens.com/oauth2/default/v1/token"
MDS_URL="https://kafka.dah-flink-dev.svc.cluster.local:8090/security/1.0/activenodes/https"

echo "============================================================"
echo "DEV Java TLS trust diagnostic (read-only)"
echo "Namespace: ${NS}"
echo "============================================================"

command -v oc >/dev/null 2>&1 || {
  echo "FATAL: oc is not installed on the pipeline agent"
  exit 1
}

get_ready_pod() {
  local component="$1"
  oc -n "$NS" get pods \
    -l "app.kubernetes.io/name=${component}" \
    --field-selector=status.phase=Running \
    -o jsonpath='{range .items[?(@.status.containerStatuses[0].ready==true)]}{.metadata.name}{"\n"}{end}' \
    | head -n 1
}

C3_POD="$(get_ready_pod controlcenter)"
KAFKA_POD="$(get_ready_pod kafka)"

[[ -n "$C3_POD" ]] || { echo "FATAL: no Ready Control Center pod found"; exit 1; }
[[ -n "$KAFKA_POD" ]] || { echo "FATAL: no Ready Kafka pod found"; exit 1; }

echo "Control Center pod: ${C3_POD}"
echo "Kafka pod:          ${KAFKA_POD}"

probe_pod() {
  local pod="$1"
  local container="$2"
  local label="$3"

  echo
  echo "============================================================"
  echo "${label}: ${pod}/${container}"
  echo "============================================================"

  echo "--- Truststore file and checksum ---"
  oc -n "$NS" exec "$pod" -c "$container" -- sh -c \
    "set -e; ls -l '$TRUSTSTORE'; (sha256sum '$TRUSTSTORE' 2>/dev/null || cksum '$TRUSTSTORE')"

  echo "--- Truststore readability ---"
  oc -n "$NS" exec "$pod" -c "$container" -- \
    keytool -list -storetype PKCS12 -keystore "$TRUSTSTORE" \
      -storepass "$TRUSTSTORE_PASSWORD" 2>&1 | sed -n '1,8p'

  echo "--- PID 1 JVM truststore arguments ---"
  oc -n "$NS" exec "$pod" -c "$container" -- sh -c \
    'tr "\000" "\n" </proc/1/cmdline | grep -E "javax\.net\.ssl\.trustStore" || true'

  echo "--- Genuine Java HTTPS handshakes ---"
  oc -n "$NS" exec -i "$pod" -c "$container" -- sh -c \
    "cat >/tmp/TlsProbe.java && java \
      -Djavax.net.ssl.trustStore='$TRUSTSTORE' \
      -Djavax.net.ssl.trustStorePassword='$TRUSTSTORE_PASSWORD' \
      -Djavax.net.ssl.trustStoreType=PKCS12 \
      /tmp/TlsProbe.java \
      '$OKTA_DISCOVERY' '$OKTA_TOKEN' '$MDS_URL'; rc=\$?; rm -f /tmp/TlsProbe.java; exit \$rc" <<'JAVA'
import java.net.HttpURLConnection;
import java.net.URL;
import javax.net.ssl.HttpsURLConnection;
import javax.net.ssl.SSLHandshakeException;
import java.security.cert.Certificate;
import java.security.cert.X509Certificate;

public class TlsProbe {
  public static void main(String[] args) {
    int failures = 0;
    for (String value : args) {
      HttpsURLConnection connection = null;
      System.out.println("TEST: " + value);
      try {
        connection = (HttpsURLConnection) new URL(value).openConnection();
        connection.setConnectTimeout(15000);
        connection.setReadTimeout(15000);
        connection.setInstanceFollowRedirects(false);
        connection.setRequestMethod("GET");
        int status = connection.getResponseCode();
        System.out.println("TLS PASS: HTTP " + status);
        Certificate[] certificates = connection.getServerCertificates();
        for (int i = 0; i < certificates.length; i++) {
          if (certificates[i] instanceof X509Certificate) {
            X509Certificate certificate = (X509Certificate) certificates[i];
            System.out.println("  peer[" + i + "] subject=" + certificate.getSubjectX500Principal());
            System.out.println("  peer[" + i + "] issuer=" + certificate.getIssuerX500Principal());
          }
        }
      } catch (SSLHandshakeException exception) {
        failures++;
        System.out.println("TLS FAIL: " + exception);
        Throwable cause = exception.getCause();
        while (cause != null) {
          System.out.println("  caused by: " + cause);
          cause = cause.getCause();
        }
      } catch (Exception exception) {
        failures++;
        System.out.println("REQUEST FAIL: " + exception);
        Throwable cause = exception.getCause();
        while (cause != null) {
          System.out.println("  caused by: " + cause);
          cause = cause.getCause();
        }
      } finally {
        if (connection != null) connection.disconnect();
      }
      System.out.println();
    }
    if (failures > 0) System.exit(2);
  }
}
JAVA
}

set +e
probe_pod "$C3_POD" controlcenter "CONTROL CENTER"
C3_RC=$?
probe_pod "$KAFKA_POD" kafka "KAFKA / MDS"
KAFKA_RC=$?
set -e

echo
echo "============================================================"
echo "RESULT"
echo "============================================================"
echo "Control Center probe exit code: ${C3_RC}"
echo "Kafka/MDS probe exit code:      ${KAFKA_RC}"

if (( C3_RC != 0 || KAFKA_RC != 0 )); then
  echo "FAIL: at least one real Java TLS handshake failed"
  exit 1
fi

echo "PASS: both JVMs trust the Okta and MDS endpoints using bundle.p12"