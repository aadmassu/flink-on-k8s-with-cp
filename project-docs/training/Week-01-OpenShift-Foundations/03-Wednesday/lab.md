# Week 1 Wednesday — Lab: Expose an App via Service + Route

**Time**: ~3 hours

## Pick your target

This lab runs on three targets. Pick one and use the substitutions below for all commands that follow. (Or `export` the variables in your shell.)

| Variable | FCB OpenShift | OpenShift Local (CRC) | kind |
|---|---|---|---|
| `$CLI` | `oc` | `oc` | `kubectl` |
| `$NS` | `<you>-training` | `hello-lab` | `hello-lab` |
| `$EXT_HOST` | `hello-<you>.apps.<env>.ocp.example.com` | `hello.apps-crc.testing` | `localhost:8080` (port-forward) or `hello.local.test` (Ingress) |
| External-access object | `Route` (edge TLS) | `Route` (edge TLS) | `kubectl port-forward` OR `Ingress` (ingress-nginx) |
| NodePort outcome | Rejected by admission | Usually accepted | Accepted |
| LoadBalancer `EXTERNAL-IP` | `<pending>` (no cloud LB) | `<pending>` | `<pending>` unless `cloud-provider-kind` / MetalLB installed |

Per-target prereq (one-time):

- **FCB OCP** — `oc login` to the FCB cluster; namespace `$NS` is pre-created.
- **OpenShift Local (CRC)** — `crc start`, then `oc login -u developer -p developer https://api.crc.testing:6443`, then `oc new-project $NS`.
- **kind** — `kind create cluster`, then `kubectl create namespace $NS && kubectl config set-context --current --namespace=$NS`. For the Ingress path, additionally install ingress-nginx: `kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml`, and re-create the cluster with `extraPortMappings` for 80/443 if you want host-port access.

## Hands-on Lab — trace one request all the way through

```bash
# 1. Deploy the app
$CLI -n $NS create deployment hello --image=nginx:1.27 --replicas=2
$CLI -n $NS expose deployment hello --port=80 --target-port=80   # creates a ClusterIP Service

# 2. Confirm the Service + EndpointSlice are wired
$CLI -n $NS get svc hello
$CLI -n $NS get endpoints hello                                   # should list both Pod IPs
$CLI -n $NS get endpointslice -l kubernetes.io/service-name=hello

# 3. Confirm reachability from inside the cluster
$CLI -n $NS run curl-test --rm -it --image=curlimages/curl --restart=Never -- curl -s http://hello/
```

External access — branch on target:

```bash
# 4a. OpenShift (FCB or CRC) — create an edge-TLS Route
oc -n $NS create route edge --service=hello --hostname=$EXT_HOST
oc -n $NS get route hello

# 5a. Hit it from your laptop
curl -k https://$EXT_HOST/
```

```bash
# 4b. kind — no Routes. Pick one of the two options:

# (a) Port-forward (quickest; skips the Ingress layer, but proves the Service works):
kubectl -n $NS port-forward svc/hello 8080:80 &
curl -s http://localhost:8080/

# (b) Ingress (requires ingress-nginx installed on kind):
kubectl -n $NS create ingress hello --rule="hello.local.test/=hello:80"
# Add to /etc/hosts on your laptop: 127.0.0.1 hello.local.test
curl -s http://hello.local.test/
```

If the external hit doesn't return the nginx welcome page, work backward through the morning's traffic-flow diagram one layer at a time.

## Variant Walk-Through — NodePort and LoadBalancer

Apply the two other Service types against the SAME `hello` Deployment and observe what changes on your target. The manifests match this morning's `discussion.md`.

### NodePort

```bash
cat <<'YAML' | $CLI -n $NS apply -f -
apiVersion: v1
kind: Service
metadata:
  name: hello-np
spec:
  type: NodePort
  selector:
    app: hello
  ports:
  - port: 80
    targetPort: 80
    nodePort: 30080
YAML
```

Expected outcomes by target — record which one you got:

- **FCB OCP** — *rejected* by admission control. Copy the rejection message; it names the policy that denied the request (typically a Gatekeeper / OPA constraint). This is the expected outcome in any namespace governed by the production admission set.
- **OpenShift Local (CRC)** — *accepted*. Get a node IP and hit it directly:

  ```bash
  oc get nodes -o wide                                            # find the InternalIP
  curl -s http://<node-ip>:30080/ | head -5
  ```

- **kind** — *accepted*. From inside the kind container the NodePort is always reachable; from the host, only if you launched kind with `extraPortMappings`:

  ```bash
  # From inside the kind control-plane container (always works):
  docker exec -it kind-control-plane curl -s http://localhost:30080/

  # From your laptop (only if extraPortMappings was set):
  curl -s http://localhost:30080/
  ```

In every case the lesson is the same: NodePort opens a fixed high port on every node — production blocks it for that reason.

### LoadBalancer

```bash
cat <<'YAML' | $CLI -n $NS apply -f -
apiVersion: v1
kind: Service
metadata:
  name: hello-lb
spec:
  type: LoadBalancer
  selector:
    app: hello
  ports:
  - port: 80
    targetPort: 80
YAML

$CLI -n $NS get svc hello-lb
```

Expected output:

```
NAME       TYPE           CLUSTER-IP     EXTERNAL-IP   PORT(S)        AGE
hello-lb   LoadBalancer   10.96.x.x      <pending>     80:30523/TCP   10s
```

Expected `EXTERNAL-IP` by target:

- **FCB OCP** — `<pending>` (on-prem, no cloud LB controller).
- **OpenShift Local (CRC)** — `<pending>` (same reason).
- **kind** — `<pending>` unless `cloud-provider-kind` or MetalLB is installed.

Two observations regardless of target:

- `EXTERNAL-IP` stays `<pending>`. On cloud OpenShift (ROSA, ARO, OCP-on-AWS) this would resolve to a provisioned LB IP within ~60 seconds.
- A `nodePort` is still allocated under the hood (the `80:30xxx/TCP` half of `PORT(S)`). Structurally, `LoadBalancer = NodePort + external LB`.

Confirm the underlying nodePort:

```bash
$CLI -n $NS get svc hello-lb -o jsonpath='{.spec.ports[0]}{"\n"}'
```

`nodePort:` is populated even though `spec.type` is `LoadBalancer`.

## Troubleshooting Exercise — break the path in three different places

For each breakage, predict the error the user will see before you check. The break-and-fix patches use `$CLI patch`, which works identically on `oc` and `kubectl`.

**Break 1 — Service selector mismatch**

```bash
$CLI -n $NS patch svc hello -p '{"spec":{"selector":{"app":"WRONG-LABEL"}}}'
# Re-run your external hit:
#   OpenShift:   curl -k https://$EXT_HOST/
#   kind (pf):   curl -s http://localhost:8080/
#   kind (ing):  curl -s http://hello.local.test/
$CLI -n $NS get endpoints hello                                  # what does Endpoints show now?
# Fix:
$CLI -n $NS patch svc hello -p '{"spec":{"selector":{"app":"hello"}}}'
```

**Break 2 — External-access object's hostname doesn't match what the ingress layer expects**

```bash
# OpenShift (FCB or CRC) — patch the Route:
oc -n $NS patch route hello -p '{"spec":{"host":"hello-typo.apps.<env>.ocp.example.com"}}'
curl -k https://$EXT_HOST/                                       # original hostname; what does HAProxy return?
# Fix:
oc -n $NS patch route hello -p "{\"spec\":{\"host\":\"$EXT_HOST\"}}"

# kind with Ingress — patch the rule:
kubectl -n $NS patch ingress hello --type=json \
  -p='[{"op":"replace","path":"/spec/rules/0/host","value":"hello-typo.local.test"}]'
curl -s http://hello.local.test/                                 # original hostname; what does ingress-nginx return?
# Fix:
kubectl -n $NS patch ingress hello --type=json \
  -p='[{"op":"replace","path":"/spec/rules/0/host","value":"hello.local.test"}]'
```

**Break 3 — Pod readinessProbe fails, so Service drops the endpoints**

```bash
# OpenShift has a convenience subcommand; kubectl uses patch:

# OpenShift:
oc -n $NS set probe deployment/hello --readiness --get-url=http://:80/never-exists

# kubectl (kind):
kubectl -n $NS patch deployment hello --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/readinessProbe","value":{"httpGet":{"path":"/never-exists","port":80},"periodSeconds":5}}]'

$CLI -n $NS get endpoints hello                                  # endpoints empty? why?

# Fix:
# OpenShift:
oc -n $NS set probe deployment/hello --readiness --remove
# kubectl:
kubectl -n $NS patch deployment hello --type=json \
  -p='[{"op":"remove","path":"/spec/template/spec/containers/0/readinessProbe"}]'
```

## Deliverable — `deliverables/<you>/week01/wednesday.md`

1. **Which target you ran on** — FCB OpenShift, OpenShift Local (CRC), or kind. If you tried more than one, note the differences you saw.
2. **The traffic-flow trace** — the actual external hit you ran (curl + Route, port-forward, or Ingress) plus each `$CLI get` along the path, with the working-state outputs.
3. **The three breakages** — for each, predict-then-confirm: what error the user saw, where in the diagram the failure happened, what fixed it.
4. **NodePort & LoadBalancer observations** — what happened on your target. For NodePort: accepted or rejected? If rejected, the admission policy that did it. For LoadBalancer: confirm `EXTERNAL-IP: <pending>` and that a nodePort was still allocated.
5. **An updated traffic-flow trace** with one new layer added that the morning diagram didn't have (e.g. EndpointSlice — read `$CLI get endpointslice` output and explain its role).
6. Two questions.

Cleanup:

```bash
$CLI -n $NS delete route hello --ignore-not-found            # OpenShift only
$CLI -n $NS delete ingress hello --ignore-not-found          # kind only
$CLI -n $NS delete svc hello hello-np hello-lb --ignore-not-found
$CLI -n $NS delete deployment hello
# Stop any port-forward you started:
pkill -f "port-forward svc/hello" 2>/dev/null || true
```
