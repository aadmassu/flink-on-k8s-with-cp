# platform-chart — Operators + CMF

Umbrella Helm chart that pulls in the three upstream operator/component charts as dependencies and installs them into the `flink-lab` namespace with lab-scale resource requests.

## Contents

- `Chart.yaml` — declares the three dependency charts (CFK, Flink Kubernetes operator, CMF)
- `values.yaml` — laptop-friendly resource requests + a namespace-scoped operator watch
- `templates/namespace.yaml` — creates the `flink-lab` namespace

## Install

```
# 1. Pull the dependency charts into ./charts/
#    Use `helm dependency build` (not `update`) once a Chart.lock is present —
#    it's stricter and reproducible against the versions pinned in Chart.yaml.
helm dependency build .

# 2. Install. --create-namespace lets Helm own the namespace; the
#    templates/namespace.yaml is templated with Helm's ownership annotations so
#    it's adoption-safe if the namespace happens to exist already.
helm install lab-platform . -n flink-lab --create-namespace -f values.yaml

# 3. Verify
oc      get pods -n flink-lab
kubectl get pods -n flink-lab
```

**Slow first boot**: expect ~5 minutes before both operator Pods are Ready. The Flink operator's startup probe is generous (30 × 10 s) because JVM init is slow on the 256 Mi memory request in this lab's `values.yaml`. If you have memory to spare, bump `flink-operator.operatorPod.resources.requests.memory` to 512Mi for a noticeably faster boot.

You should see, within ~3 minutes:

- `confluent-operator-*` (CFK operator)
- `lab-platform-flink-kubernetes-operator-*` (Flink operator)
- `lab-platform-cmf-*` (CMF)

## Uninstall

```
helm uninstall lab-platform -n flink-lab
```

CRDs are not removed by `helm uninstall` — remove them manually if you want a clean slate:

```
kubectl delete crd -l app.kubernetes.io/part-of=confluent-platform
kubectl delete crd -l app.kubernetes.io/part-of=flink-kubernetes-operator
```

## Notes on the dependency versions

Pinned in `Chart.yaml`:

- `confluent-for-kubernetes` 0.1145.0 — CFK 3.1.x baseline
- `flink-kubernetes-operator` 1.10.0 — supports Flink 1.17 + 1.18
- `confluent-manager-for-apache-flink` 2.3.0 — CMF stable

If a dependency chart isn't reachable (behind a proxy, etc.), you can install each of the three components independently with the equivalent `helm install` invocations; see the discussion.md and lab.md files in Week 5 Mon / Tue for those.

## Why one namespace, one operator each

Production installs typically put operators in their own namespaces (`confluent`, `flink-operator`) so operator upgrades don't disturb workload namespaces. For a laptop lab this adds friction with zero benefit — one namespace keeps the walkthrough tight.
