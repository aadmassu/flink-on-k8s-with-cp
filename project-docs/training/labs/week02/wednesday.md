# Week 2 Wednesday — Lab: Build a Working Prometheus + Grafana Dashboard

**Time**: ~4 hours

## Hands-on Lab — instrument a Pod + see the metric in Grafana

OpenShift's built-in monitoring stack scrapes user workloads when the cluster has `enableUserWorkload: true`. Verify first, then build.

```bash
# 1. Verify user-workload monitoring is on (cluster admin probably already set this)
oc get configmap cluster-monitoring-config -n openshift-monitoring -o yaml | grep -A2 enableUserWorkload

# 2. Deploy a sample app that exposes Prometheus metrics on /metrics
oc project <you>-training
cat <<EOF | oc apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: prom-demo
  labels: {app: prom-demo}
spec:
  replicas: 1
  selector:
    matchLabels: {app: prom-demo}
  template:
    metadata:
      labels: {app: prom-demo}
    spec:
      containers:
        - name: app
          image: prom/prometheus:v2.50.1
          args:
            - --config.file=/etc/prometheus/prometheus.yml
            - --web.listen-address=:9090
          ports:
            - {containerPort: 9090, name: metrics}
---
apiVersion: v1
kind: Service
metadata:
  name: prom-demo
  labels: {app: prom-demo}
spec:
  selector: {app: prom-demo}
  ports:
    - {port: 9090, targetPort: 9090, name: metrics}
EOF

oc wait --for=condition=Available deployment/prom-demo --timeout=60s

# 3. Confirm the /metrics endpoint is serving Prometheus-formatted data
oc port-forward svc/prom-demo 9090:9090 &
PF=$!
sleep 2
curl -s http://localhost:9090/metrics | head -20      # should be Prometheus text format
kill $PF
```

## Hands-on Lab Part 2 — register a ServiceMonitor so OpenShift Prometheus scrapes it

```bash
cat <<EOF | oc apply -f -
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: prom-demo
  labels: {app: prom-demo}
spec:
  selector:
    matchLabels: {app: prom-demo}
  endpoints:
    - port: metrics
      interval: 30s
      path: /metrics
EOF

# 4. Wait ~60s for Prometheus to discover the new ServiceMonitor, then check
#    the `up{job="prom-demo"}` metric — should be 1 if scraping is healthy.
#    Console: Observe → Metrics → query box → up{job="prom-demo"}
#    CLI alternative via thanos-querier or in-cluster Prometheus is cluster-specific.
```

If `up{job="prom-demo"}` returns no series, the ServiceMonitor isn't being discovered. Check:
- Is the ServiceMonitor in the same namespace as the Service?
- Does `spec.selector` match the Service's labels?
- Does the Service have the named port `metrics`?

## Hands-on Lab Part 3 — build a Grafana panel

In the OpenShift Console:
1. Observe → Dashboards → Create dashboard
2. Add panel → set the metric: `prometheus_tsdb_head_series{job="prom-demo"}` (a built-in metric the demo Pod exposes about itself)
3. Set the time range to last 5 min
4. Save the dashboard as `prom-demo-from-<you>`
5. Export the JSON: dashboard settings → JSON Model → copy

Save the JSON — it's part of your Week 2 deliverable.

## Troubleshooting Exercise — diagnose why a scrape isn't working

```bash
# Break 1 — wrong port name in ServiceMonitor
oc patch servicemonitor prom-demo --type='json' \
  -p='[{"op":"replace","path":"/spec/endpoints/0/port","value":"wrong-port"}]'

# Wait ~60s, then query `up{job="prom-demo"}` — what does Prometheus show?
# Why?
# Fix:
oc patch servicemonitor prom-demo --type='json' \
  -p='[{"op":"replace","path":"/spec/endpoints/0/port","value":"metrics"}]'

# Break 2 — make the Pod's /metrics endpoint refuse connections
# (set readiness probe to fail so the Service drops the endpoint)
oc set probe deployment/prom-demo --readiness --get-url=http://:9090/never-exists
sleep 30
# Query `up{job="prom-demo"}` — what does it show?
# Reading? `oc get endpoints prom-demo` — empty? That's why Prometheus can't find a target.
# Fix:
oc set probe deployment/prom-demo --readiness --remove
```

## Deliverable — `deliverables/<you>/week02/wednesday.md`

1. **The metric you successfully scraped** — paste the first 5 lines of `curl <pod>/metrics` and the PromQL query that returned data
2. **Your Grafana dashboard JSON** — committed in this MD file under a `<details>` block, OR in a sibling `prom-demo-dashboard.json` file
3. **The two breakage walks** — for each, the actual `up{...}` value Prometheus showed + the underlying reason
4. **CFK preview**: in 3 sentences, write what you'd build in Grafana to monitor "Kafka cluster health" — name 2–3 specific metrics (use the discussion's list)
5. Two questions

Cleanup:

```bash
oc delete servicemonitor prom-demo
oc delete svc prom-demo
oc delete deployment prom-demo
```
