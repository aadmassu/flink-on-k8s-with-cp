#!/usr/bin/env bash

set -euo pipefail

NS="${OC_NS:-dah-flink-dev}"
URL="https://myapps.firstcitizens.com/oauth2/default/v1/keys"
TRUSTSTORE="/var/ssl/truststore/bundle.p12"
TRUSTSTORE_PASSWORD="changeit"
JAVA_SOURCE="/tmp/JavaTlsProbe.java"

echo "============================================================"
echo "${TARGET_ENV:-dev} Kafka Java TLS comparison"
echo "Namespace: $NS"
echo "URL:       $URL"
echo "============================================================"

echo "=== 1. Locate a running Kafka pod ==="
POD="$(oc -n "$NS" get pods -l app.kubernetes.io/name=kafka --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}')"
if [[ -z "$POD" ]]; then
  echo "FATAL: No running Kafka pod found in namespace $NS"
  exit 1
fi
echo "Kafka pod: $POD"

echo "=== 2. Confirm Java and the mounted truststore ==="
oc -n "$NS" exec "$POD" -c kafka -- java -version
oc -n "$NS" exec "$POD" -c kafka -- sh -c "test -r '$TRUSTSTORE' && ls -l '$TRUSTSTORE' && sha256sum '$TRUSTSTORE'"
oc -n "$NS" exec "$POD" -c kafka -- keytool -list -keystore "$TRUSTSTORE" -storetype PKCS12 -storepass "$TRUSTSTORE_PASSWORD" >/dev/null
echo "PASS: bundle.p12 is readable and its password is valid"

echo "=== 3. Install temporary Java HTTPS probe in the Kafka container ==="
oc -n "$NS" exec -i "$POD" -c kafka -- sh -c "cat > '$JAVA_SOURCE'" <<'JAVA'
import java.net.URL;
import java.security.cert.Certificate;
import java.security.cert.X509Certificate;
import javax.net.ssl.HttpsURLConnection;

public class JavaTlsProbe {
    public static void main(String[] args) {
        if (args.length != 1) {
            System.err.println("Usage: JavaTlsProbe <https-url>");
            System.exit(64);
        }

        System.out.println("java.version=" + System.getProperty("java.version"));
        System.out.println("javax.net.ssl.trustStore=" + System.getProperty("javax.net.ssl.trustStore", "<JVM default>"));
        System.out.println("javax.net.ssl.trustStoreType=" + System.getProperty("javax.net.ssl.trustStoreType", "<JVM default>"));

        HttpsURLConnection connection = null;
        try {
            connection = (HttpsURLConnection) new URL(args[0]).openConnection();
            connection.setConnectTimeout(15000);
            connection.setReadTimeout(15000);
            connection.setInstanceFollowRedirects(false);
            connection.setRequestMethod("GET");
            connection.setRequestProperty("Accept", "application/json");

            int status = connection.getResponseCode();
            System.out.println("HTTP status=" + status);
            System.out.println("cipherSuite=" + connection.getCipherSuite());

            Certificate[] chain = connection.getServerCertificates();
            for (int i = 0; i < chain.length; i++) {
                if (chain[i] instanceof X509Certificate) {
                    X509Certificate certificate = (X509Certificate) chain[i];
                    System.out.println("certificate[" + i + "].subject=" + certificate.getSubjectX500Principal());
                    System.out.println("certificate[" + i + "].issuer=" + certificate.getIssuerX500Principal());
                }
            }

            if (status >= 200 && status < 400) {
                System.out.println("RESULT=PASS");
                System.exit(0);
            }

            System.out.println("RESULT=HTTP_FAILURE");
            System.exit(3);
        } catch (Throwable error) {
            System.out.println("RESULT=TLS_OR_CONNECTION_FAILURE");
            error.printStackTrace(System.out);
            System.exit(2);
        } finally {
            if (connection != null) {
                connection.disconnect();
            }
        }
    }
}
JAVA

cleanup() {
  oc -n "$NS" exec "$POD" -c kafka -- rm -f "$JAVA_SOURCE" >/dev/null 2>&1 || true
}
trap cleanup EXIT
echo "PASS: Temporary probe created"

echo "=== 4. Test A: Java with bundle.p12 ==="
set +e
oc -n "$NS" exec "$POD" -c kafka -- java \
  -Djavax.net.ssl.trustStore="$TRUSTSTORE" \
  -Djavax.net.ssl.trustStorePassword="$TRUSTSTORE_PASSWORD" \
  -Djavax.net.ssl.trustStoreType=PKCS12 \
  "$JAVA_SOURCE" "$URL"
BUNDLE_RC=$?
set -e
echo "Test A exit code: $BUNDLE_RC"

echo "=== 5. Test B: Java with its default truststore ==="
set +e
oc -n "$NS" exec "$POD" -c kafka -- java "$JAVA_SOURCE" "$URL"
DEFAULT_RC=$?
set -e
echo "Test B exit code: $DEFAULT_RC"

echo "=== 6. Comparison ==="
if [[ $BUNDLE_RC -eq 0 && $DEFAULT_RC -eq 0 ]]; then
  echo "RESULT: BOTH_PASS"
  echo "Interpretation: Both truststores validate the endpoint. The MDS JWKS failure is specific to its internally created SSL context or endpoint configuration."
elif [[ $BUNDLE_RC -eq 0 && $DEFAULT_RC -ne 0 ]]; then
  echo "RESULT: BUNDLE_ONLY_PASS"
  echo "Interpretation: bundle.p12 is correct, but the JVM default truststore is insufficient. MDS is likely not using bundle.p12."
elif [[ $BUNDLE_RC -ne 0 && $DEFAULT_RC -eq 0 ]]; then
  echo "RESULT: DEFAULT_ONLY_PASS"
  echo "Interpretation: bundle.p12 is incomplete or invalid for the endpoint, while the image JVM default truststore works."
else
  echo "RESULT: BOTH_FAIL"
  echo "Interpretation: Neither Java trust configuration validates the endpoint. Review the exceptions above."
fi

echo "============================================================"
echo "Java TLS comparison completed."
echo "Test A exit code: $BUNDLE_RC"
echo "Test B exit code: $DEFAULT_RC"
echo "============================================================"

# Keep the pipeline task successful so both diagnostic results remain visible.
exit 0
