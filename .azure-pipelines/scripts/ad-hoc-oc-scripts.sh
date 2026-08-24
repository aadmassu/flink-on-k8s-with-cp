#!/usr/bin/env bash
set -euo pipefail

NS="${OC_NS:-dah-flink-dev}"
NS=dah-flink-qa

echo "Secret clientId:"
oc -n "$NS" get secret oauth-connect -o jsonpath='{.data.clientId}' | base64 -d; echo

echo "SystemAdmin principal:"
oc -n "$NS" get confluentrolebinding connect-systemadmin -o jsonpath='{.spec.principal.name}'; echo

echo "Rolebinding state:"
oc -n "$NS" get confluentrolebinding connect-systemadmin -o jsonpath='{.status.state}'; echo