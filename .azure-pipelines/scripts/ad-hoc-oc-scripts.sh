#!/usr/bin/env bash

set -euo pipefail

NS="dah-flink-dev"
POD="controlcenter-0"
CONTAINER="controlcenter"
TRUSTSTORE="/var/ssl/truststore/bundle.p12"
STOREPASS="changeit"

echo "=== 1. Wait for Control Center ==="
oc -n "$NS" wait controlcenter/controlcenter \
  --for=condition=platform.confluent.io/cluster-ready=True \
  --timeout=15m
oc -n "$NS" wait pod/"$POD" --for=condition=Ready --timeout=15m

echo "=== 2. Verify the actual PKCS12 truststore ==="
oc -n "$NS" exec "$POD" -c "$CONTAINER" -- sh -c \
  "test -r '$TRUSTSTORE' && keytool -list -keystore '$TRUSTSTORE' -storetype PKCS12 -storepass '$STOREPASS' | sed -n '1,12p'"

echo "=== 3. Verify supported rendered Control Center REST truststore ==="
oc -n "$NS" exec "$POD" -c "$CONTAINER" -- sh -c \
  'grep -E "^confluent\.controlcenter\.rest\.ssl\.(truststore|endpoint)" /opt/confluentinc/etc/controlcenter/controlcenter.properties'

echo "=== 4. Verify JVM default truststore ==="
oc -n "$NS" exec "$POD" -c "$CONTAINER" -- sh -c \
  'tr "\000" "\n" </proc/1/cmdline | grep -E "^-Djavax\.net\.ssl\.trustStore(=|Password=|Type=)"'

echo "=== 5. Java TLS probes from the Control Center JVM environment ==="
oc -n "$NS" exec -i "$POD" -c "$CONTAINER" -- sh -c \
  'cat >/tmp/C3TlsProbe.java && java \
    -Djavax.net.ssl.trustStore=/var/ssl/truststore/bundle.p12 \
    -Djavax.net.ssl.trustStorePassword=changeit \
    -Djavax.net.ssl.trustStoreType=PKCS12 \
    /tmp/C3TlsProbe.java' <<'JAVA'
import java.io.InputStream;
import java.net.URL;
import java.security.cert.Certificate;
import java.security.cert.X509Certificate;
import javax.net.ssl.HttpsURLConnection;

public class C3TlsProbe {
    private static int failures = 0;

    private static void probe(String name, String address) {
        System.out.println("--- " + name + " ---");
        try {
            HttpsURLConnection connection =
                (HttpsURLConnection) new URL(address).openConnection();
            connection.setConnectTimeout(15000);
            connection.setReadTimeout(15000);
            connection.setInstanceFollowRedirects(false);
            connection.setRequestMethod("GET");

            int status = connection.getResponseCode();
            System.out.println("TLS PASS: HTTP " + status);
            System.out.println("Cipher: " + connection.getCipherSuite());

            Certificate[] chain = connection.getServerCertificates();
            for (int i = 0; i < chain.length; i++) {
                X509Certificate certificate = (X509Certificate) chain[i];
                System.out.println("Certificate[" + i + "] subject: "
                    + certificate.getSubjectX500Principal());
                System.out.println("Certificate[" + i + "] issuer:  "
                    + certificate.getIssuerX500Principal());
            }

            InputStream stream = status >= 400
                ? connection.getErrorStream() : connection.getInputStream();
            if (stream != null) {
                try (InputStream ignored = stream) {
                    byte[] buffer = new byte[1024];
                    while (stream.read(buffer) != -1) { }
                }
            }
        } catch (Throwable failure) {
            failures++;
            System.out.println("TLS FAIL: " + failure);
            failure.printStackTrace(System.out);
        }
    }

    public static void main(String[] args) {
        System.out.println("Truststore: "
            + System.getProperty("javax.net.ssl.trustStore"));
        System.out.println("Truststore type: "
            + System.getProperty("javax.net.ssl.trustStoreType"));

        probe("Okta discovery",
            "https://myapps.firstcitizens.com/oauth2/default/.well-known/openid-configuration");
        probe("Okta JWKS",
            "https://myapps.firstcitizens.com/oauth2/default/v1/keys");
        probe("Okta token endpoint TLS",
            "https://myapps.firstcitizens.com/oauth2/default/v1/token");
        probe("Kafka MDS",
            "https://kafka.dah-flink-dev.svc.cluster.local:8090/security/1.0/activenodes");

        if (failures != 0) {
            System.out.println("RESULT: FAIL (" + failures + " TLS probe(s) failed)");
            System.exit(1);
        }
        System.out.println("RESULT: PASS (all TLS handshakes succeeded)");
    }
}
JAVA

echo "=== 6. Callback-correlated C3 errors ==="
oc -n "$NS" logs "$POD" -c "$CONTAINER" --since=20m | \
  grep -Ei -C 15 \
    'authorization-code/callback|PKIX|SSLHandshakeException|certificate_unknown|ProcessingException' \
  || true

echo "PASS: Focused Control Center TLS diagnostics completed."