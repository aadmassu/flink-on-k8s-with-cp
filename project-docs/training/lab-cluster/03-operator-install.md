# Confluent for Kubernetes (CFK) — operator install

The operator lives in its own namespace (`confluent`) and watches the whole cluster — one operator install serves every namespace that has Confluent CRs in it. Do this once per kind cluster.

## Install

```bash
helm repo add confluentinc https://packages.confluent.io/helm
helm repo update confluentinc

helm install confluent-operator confluentinc/confluent-for-kubernetes \
  --version 0.1514.40 \
  --namespace confluent \
  --create-namespace \
  --set 'namespaceList={confluent,kafka-dev}' \
  --wait --timeout 5m
```

`0.1514.40` is CFK app version `3.2.2`. Pin to a specific version so the lab is reproducible. Check available versions with:

```bash
helm search repo confluentinc/confluent-for-kubernetes --versions | head
```

> **Important — `namespaceList`.** The chart defaults to *namespaced* mode (`--namespaces=confluent`), where the operator only watches its own namespace. CRs applied anywhere else are silently ignored. List every namespace that will hold Confluent CRs (here: `kafka-dev`) explicitly. To add a namespace later, `helm upgrade` with the new list.

## Verify

```bash
kubectl -n confluent get pods                        # 1 operator pod, Running
kubectl get crd | grep platform.confluent.io         # 20+ CRDs registered
kubectl get crd kraftcontrollers.platform.confluent.io \
  -o jsonpath='{.spec.versions[*].name}'             # v1beta1
```

You should see the operator pod ready and CRDs for `Kafka`, `KRaftController`, `SchemaRegistry`, `Connect`, `Connector`, `ControlCenter`, `KsqlDB`, `KafkaRestProxy`, `Zookeeper`, and friends.

## Uninstall

```bash
helm uninstall confluent-operator -n confluent
kubectl delete namespace confluent
kubectl get crd -o name | grep platform.confluent.io | xargs -n1 kubectl delete
```

Order matters: uninstall the chart first, then delete CRDs. The Helm chart's owner reference on the CRDs is intentionally loose so a `helm uninstall` doesn't wipe data — you need to delete the CRDs explicitly when fully tearing down.
