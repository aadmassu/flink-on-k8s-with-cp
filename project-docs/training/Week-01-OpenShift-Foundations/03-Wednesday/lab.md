# Week 1 Wednesday — Lab: Expose an App via Service + Route

**Time**: ~3 hours

## Hands-on Lab — trace one request all the way through

```bash
oc project <you>-training

# 1. Deploy the app
oc create deployment hello --image=nginx:1.27 --replicas=2
oc expose deployment hello --port=80 --target-port=80     # creates a ClusterIP Service

# 2. Confirm the Service + EndpointSlice are wired
oc get svc hello
oc get endpoints hello                                    # should list both Pod IPs
oc get endpointslice -l kubernetes.io/service-name=hello

# 3. Confirm reachability from inside the cluster
oc run curl-test --rm -it --image=curlimages/curl --restart=Never -- curl -s http://hello/

# 4. Expose externally via Route
oc create route edge --service=hello --hostname=hello-<you>.apps.<env>.ocp.example.com
oc get route hello

# 5. Hit it from your laptop
curl -k https://hello-<you>.apps.<env>.ocp.example.com/
```

If step 5 doesn't return the nginx welcome page, work backward through the morning's traffic-flow diagram one layer at a time.

## Variant Walk-Through — NodePort and LoadBalancer

Now that the ClusterIP + Route path works end-to-end, apply the two other Service types against the SAME `hello` Deployment and observe what changes — and what the cluster's policy actually says about each. The manifests here match the ones in this morning's `discussion.md`.

### NodePort

```bash
cat <<'YAML' | oc apply -f -
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

Two outcomes are possible — record which one you got:

- **Rejected by admission control.** FCB's production guardrail blocks `type: NodePort`. Copy the rejection message; it names the policy that denied the request (typically a Gatekeeper / OPA constraint). This is the *expected* outcome in any namespace governed by the production admission set.
- **Accepted.** Your training namespace doesn't enforce that constraint. Continue:

  ```bash
  oc get svc hello-np
  # TYPE: NodePort, PORT(S): 80:30080/TCP

  # Grab a node IP and curl directly
  NODE_IP=$(oc get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
  echo "node IP: $NODE_IP"
  curl -s http://$NODE_IP:30080/ | head -5
  ```

  If the `curl` hangs or refuses, the node-network firewall is in front of you — the Service is wired correctly; the path just isn't reachable from your laptop.

Either outcome is a valid lesson. Production blocks NodePort precisely because every node ends up listening on a high port that isn't governed by Routes, HAProxy TLS, or hostname-based admission.

### LoadBalancer

```bash
cat <<'YAML' | oc apply -f -
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

oc get svc hello-lb
```

Expected output:

```
NAME       TYPE           CLUSTER-IP     EXTERNAL-IP   PORT(S)        AGE
hello-lb   LoadBalancer   10.96.x.x      <pending>     80:30523/TCP   10s
```

Two observations to record:

- `EXTERNAL-IP` is `<pending>` — FCB OpenShift is on-prem and has no cloud LB controller to satisfy the request. On cloud OpenShift (ROSA, ARO, OCP-on-AWS) this would resolve to a provisioned external LB IP within ~60 seconds.
- A `nodePort` was still allocated (the `80:30523/TCP` half of `PORT(S)`). Structurally, a `LoadBalancer` Service is a `NodePort` Service with the cloud-LB layer on top — same admission concern as NodePort applies, which is why FCB uses Routes + HAProxy instead.

Confirm the underlying nodePort:

```bash
oc get svc hello-lb -o jsonpath='{.spec.ports[0]}{"\n"}'
```

You'll see `nodePort:` populated even though `spec.type` is `LoadBalancer`.

## Troubleshooting Exercise — break the path in three different places

For each of the three breakages, predict what error the user will see before you check.

**Break 1 — Service selector mismatch**

```bash
oc patch svc hello -p '{"spec":{"selector":{"app":"WRONG-LABEL"}}}'
curl -k https://hello-<you>.apps.<env>.ocp.example.com/
oc get endpoints hello             # what does Endpoints show now?
# Fix:
oc patch svc hello -p '{"spec":{"selector":{"app":"hello"}}}'
```

**Break 2 — Route's hostname doesn't match what HAProxy is configured for**

```bash
oc patch route hello -p '{"spec":{"host":"hello-typo.apps.<env>.ocp.example.com"}}'
curl -k https://hello-<you>.apps.<env>.ocp.example.com/        # original hostname
# What does HAProxy return?
# Fix:
oc patch route hello -p '{"spec":{"host":"hello-<you>.apps.<env>.ocp.example.com"}}'
```

**Break 3 — Pod readinessProbe fails, so Service drops the endpoints**

```bash
# Add a readiness probe that will fail
oc set probe deployment/hello --readiness --get-url=http://:80/never-exists
oc get endpoints hello             # endpoints empty? why?
curl -k https://hello-<you>.apps.<env>.ocp.example.com/
# Fix:
oc set probe deployment/hello --readiness --remove
```

## Deliverable — `deliverables/<you>/week01/wednesday.md`

1. **The traffic-flow trace** — the actual `curl` you ran + each `oc get` you ran along the path, with the working-state outputs
2. **The three breakages** — for each, predict-then-confirm: what error the user saw, where in the diagram the failure happened, what fixed it
3. **An updated traffic-flow trace** with one new layer added that the morning diagram didn't have (e.g. EndpointSlice — read `oc get endpointslice` output and explain its role)
4. Two questions

Cleanup:

```bash
oc delete route hello
oc delete svc hello hello-np hello-lb --ignore-not-found
oc delete deployment hello
```
