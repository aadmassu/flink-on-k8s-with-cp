# Lab Teardown

Reverse-dependency-order cleanup. Do NOT skip steps or you may leave orphaned PVCs / dangling finalizers.

## Nuclear option — delete the whole kind cluster

If you're just moving on and don't care about anything in the cluster:

```
kind delete cluster --name flink-lab
```

Everything is gone. Done.

## Surgical teardown (keep the kind cluster)

### 1. Delete Flink jobs

```
oc      delete flinkdeployment --all -n flink-lab
kubectl delete flinkdeployment --all -n flink-lab
```

Wait until `kubectl get pods -n flink-lab` shows no JM/TM Pods.

### 2. Delete the jar-server + producer

```
oc      delete deployment jar-server -n flink-lab
oc      delete configmap event-counter-jar -n flink-lab
oc      delete job event-generator -n flink-lab
kubectl delete deployment jar-server -n flink-lab
kubectl delete configmap event-counter-jar -n flink-lab
kubectl delete job event-generator -n flink-lab
```

### 3. Delete Kafka topics + cluster

```
oc      delete kafkatopic --all -n flink-lab
oc      delete kafka --all -n flink-lab
oc      delete kraftcontroller --all -n flink-lab
kubectl delete kafkatopic --all -n flink-lab
kubectl delete kafka --all -n flink-lab
kubectl delete kraftcontroller --all -n flink-lab
```

Wait until Kafka Pods are gone.

### 4. Delete orphaned PVCs

```
oc      delete pvc --all -n flink-lab
kubectl delete pvc --all -n flink-lab
```

Skip this only if you plan to redeploy immediately and want to preserve state.

### 5. Uninstall the umbrella chart

```
helm uninstall lab-platform -n flink-lab
```

### 6. Optional — delete CRDs for a truly clean slate

```
kubectl delete crd -l app.kubernetes.io/part-of=confluent-platform
kubectl delete crd -l app.kubernetes.io/part-of=flink-kubernetes-operator
```

### 7. Delete the namespace

```
oc      delete namespace flink-lab
kubectl delete namespace flink-lab
```

If the namespace hangs in `Terminating` for more than a minute, some CR still has a stuck finalizer. Diagnose with:

```
kubectl get namespace flink-lab -o json | jq '.spec.finalizers, .status.conditions'
kubectl api-resources --verbs=list --namespaced -o name \
  | xargs -n 1 kubectl get -n flink-lab --show-kind --ignore-not-found 2>/dev/null
```

Force-clear a stuck finalizer (last resort):

```
kubectl patch <resource>/<name> -n flink-lab -p '{"metadata":{"finalizers":[]}}' --type=merge
```

## Re-deploying from a clean slate

After teardown, run through [`README.md`](README.md) from step 1. First-time boot takes ~5 minutes; subsequent redeploys with cached images take ~2 minutes.
