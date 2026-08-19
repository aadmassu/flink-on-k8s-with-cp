#!/usr/bin/env bash
set -euo pipefail

oc -n dah-flink-dev logs controlcenter-0 -c controlcenter --since=10m | grep -Ei -C 40 'PKIX|SSLHandshakeException|certificate_unknown|trustStore|trustManager|X509TrustManager|Fatal.*certificate|unable to find valid certification path';

oc -n dah-flink-dev logs kafka-0 -c kafka --since=30m > kafka-0.log;
oc -n dah-flink-dev logs kafka-1 -c kafka --since=30m > kafka-1.log;
oc -n dah-flink-dev logs kafka-2 -c kafka --since=30m > kafka-2.log;