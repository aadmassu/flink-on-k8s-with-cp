#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-dah-flink-dev}"
COMMAND="${1:-logs}"

case "$COMMAND" in
  logs)
    echo "=== Capturing Control Center and Kafka logs ==="
    oc -n "$NAMESPACE" logs controlcenter-0 -c controlcenter --since=10m | grep -Ei -C 40 'PKIX|SSLHandshakeException|certificate_unknown|trustStore|trustManager|X509TrustManager|Fatal.*certificate|unable to find valid certification path';
    oc -n "$NAMESPACE" logs kafka-0 -c kafka --since=30m > kafka-0.log;
    oc -n "$NAMESPACE" logs kafka-1 -c kafka --since=30m > kafka-1.log;
    oc -n "$NAMESPACE" logs kafka-2 -c kafka --since=30m > kafka-2.log;
    echo "Logs saved to kafka-{0,1,2}.log"
    ;;

  restore-cmf-secrets)
    echo "=== Restoring CMF ExternalSecrets ==="
    CMF_EXTERNALSECRETS_DIR="apps/confluent-cmf/$NAMESPACE/externalsecrets"
    if [ ! -d "$CMF_EXTERNALSECRETS_DIR" ]; then
      echo "ERROR: CMF externalsecrets directory not found: $CMF_EXTERNALSECRETS_DIR"
      exit 1
    fi

    for eso_file in "$CMF_EXTERNALSECRETS_DIR"/*.yaml; do
      [ -f "$eso_file" ] || continue
      echo "Restoring $(basename "$eso_file")..."
      oc apply -f "$eso_file" --wait=true
    done

    echo ""
    echo "=== Restored ExternalSecrets ==="
    oc -n "$NAMESPACE" get externalsecrets.external-secrets.io -l app.kubernetes.io/part-of=confluent-manager-for-flink
    ;;

  *)
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  logs              - Capture Control Center and Kafka logs (default)"
    echo "  restore-cmf-secrets - Restore CMF ExternalSecrets from apps/confluent-cmf/<env>/externalsecrets/"
    echo ""
    echo "Environment:"
    echo "  NAMESPACE - Target namespace (default: dah-flink-dev)"
    exit 1
    ;;
esac
