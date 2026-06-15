# Week 4 Thursday — Lab: TLS Forensics

**Time**: ~4 hours

## Hands-on Lab — inspect every cert in the path

### From the broker side — what's the broker presenting?

```bash
# Pick the bootstrap host from the external listener
BS=$(oc get kafka kafka -o jsonpath='{.status.kafkaListenerStatus.external.bootstrapServer}')

# Pull the cert and inspect
openssl s_client -connect $BS:9092 -servername $BS -showcerts </dev/null 2>/dev/null | \
  openssl x509 -noout -text | head -40

# Get the SAN
openssl s_client -connect $BS:9092 -servername $BS </dev/null 2>/dev/null | \
  openssl x509 -noout -ext subjectAltName
```

### From the Secret side — what's CFK consuming?

```bash
# Find the Secret name from the Kafka CR
SECRET=$(oc get kafka kafka -o jsonpath='{.spec.tls.secretRef.name}')

# Inspect each key
oc get secret $SECRET -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -dates -subject
oc get secret $SECRET -o jsonpath='{.data.ca\.crt}'  | base64 -d | openssl x509 -noout -subject -issuer

# Verify the cert chain validates
oc get secret $SECRET -o jsonpath='{.data.tls\.crt}' | base64 -d > /tmp/leaf.pem
oc get secret $SECRET -o jsonpath='{.data.ca\.crt}'  | base64 -d > /tmp/ca.pem
openssl verify -CAfile /tmp/ca.pem /tmp/leaf.pem
```

### From the cert-manager side — find the source Certificate

```bash
oc get certificate -A | grep -i kafka
NAMESPACE=<the one above>
CERT_NAME=<the one above>

oc get certificate -n $NAMESPACE $CERT_NAME -o yaml | grep -A 5 'spec:\|status:'

# Trace to the issuer
ISSUER=$(oc get certificate -n $NAMESPACE $CERT_NAME -o jsonpath='{.spec.issuerRef.name}')
oc get clusterissuer $ISSUER -o yaml | head -50
```

## Troubleshooting Exercise — corrupt the truststore

```bash
# Backup the Secret
oc get secret $SECRET -o yaml > /tmp/secret-backup.yaml

# Edit ca.crt to be invalid (rotate two bytes)
oc get secret $SECRET -o yaml | \
  sed 's|ca.crt: [A-Za-z0-9+/=]\{1,4\}|ca.crt: ZGVhZGJlZWY=|' | \
  oc apply -f -

# Restart broker StatefulSet to pick up the change
oc rollout restart statefulset/kafka

# Observe failure mode
oc get pods -l app=kafka -w
oc logs kafka-0 -c kafka --tail=200 | grep -i -E 'tls|ssl|certificate'

# Restore
oc apply -f /tmp/secret-backup.yaml
oc rollout restart statefulset/kafka
```

In your runbook, capture: **what does a corrupt truststore look like in broker logs?**

## Deliverable — `deliverables/<you>/week04/thursday.md`

1. **Cert inventory** — for each TLS-using CFK CR, the Secret name + cert subject + SAN + expiry + issuer
2. **Issuer trace** — from broker Secret → Certificate CR → ClusterIssuer → Keyfactor (high-level diagram or table)
3. **Corrupt-truststore log excerpt** — captured from the experiment
4. **Two questions** — anything you couldn't answer about TLS in production
