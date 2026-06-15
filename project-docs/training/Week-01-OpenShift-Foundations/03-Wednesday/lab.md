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
oc delete svc hello
oc delete deployment hello
```
