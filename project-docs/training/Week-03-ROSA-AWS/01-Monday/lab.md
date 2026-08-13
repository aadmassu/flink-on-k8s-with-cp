# Week 3 Monday — Lab: Inventory Your ROSA Cluster (`cfk-dev`)

**Time**: ~2 hours (lighter — Tuesday/Wednesday are the dense ones)
**Target cluster**: `cfk-dev` — provisioned by the `01-Provision ROSA` Terraform workflow
**Expected API**: `https://api.cfk-dev.2lcu.p1.openshiftapps.com:6443`
**Expected apps domain**: `apps.cfk-dev.2lcu.p1.openshiftapps.com`
**Expected custom domain**: `dev.confluent.psyncopate.io` (wildcard CNAME → ROSA apps domain)

## Hands-on Lab — produce a one-page ROSA inventory for your team

Log in first. On `oc`:

```bash
oc login --web https://api.cfk-dev.2lcu.p1.openshiftapps.com:6443
```

On `kubectl`, retrieve a kubeconfig from the workflow run artifact (`rosa-cluster-dev-terraform`) or from your team's password manager, then:

```bash
kubectl config use-context cfk-dev
kubectl cluster-info
```

### 1. Identify cluster shape

```bash
# oc
oc get clusterversion
oc get infrastructure cluster -o jsonpath='{.status.platformStatus.aws.region}{"\n"}'
oc get nodes -o custom-columns=NAME:.metadata.name,INSTANCE:.metadata.labels.node\\.kubernetes\\.io/instance-type,ZONE:.metadata.labels.topology\\.kubernetes\\.io/zone,READY:.status.conditions[?\(@.type==\"Ready\"\)].status
```

```bash
# kubectl (the OpenShift CRDs aren't readable via kubectl, but Node labels are)
kubectl get nodes -o custom-columns=NAME:.metadata.name,INSTANCE:.metadata.labels.node\\.kubernetes\\.io/instance-type,ZONE:.metadata.labels.topology\\.kubernetes\\.io/zone,READY:.status.conditions[?\(@.type==\"Ready\"\)].status
```

Expected on `cfk-dev`: ~4 worker nodes of type `m5.xlarge`, spread across multiple AZs in `us-east-1`.

### 2. Is this cluster ROSA Classic or HCP?

```bash
# oc — the presence of a hostedcontrolplane object is the Classic-vs-HCP signal
oc get hostedcontrolplane -A 2>/dev/null && echo "-> ROSA HCP" || echo "-> ROSA Classic (or self-managed OCP)"
```

```bash
# kubectl
kubectl get hostedcontrolplane -A 2>/dev/null && echo "-> ROSA HCP" || echo "-> ROSA Classic (or self-managed OCP)"
```

For `cfk-dev` you should see `-> ROSA Classic` — the Terraform module used was `rosa-classic/rhcs` and a `cfk-dev-ControlPlane-Role` IAM role was created (HCP wouldn't have one).

### 3. Cluster operators — health overview

```bash
# oc
oc get clusteroperators -o custom-columns=NAME:.metadata.name,AVAILABLE:.status.conditions[?\(@.type==\"Available\"\)].status,DEGRADED:.status.conditions[?\(@.type==\"Degraded\"\)].status | head -20
```

`kubectl` cannot read `ClusterOperator` (OpenShift CRD). Note that for the inventory.

A healthy CO has `Available=True`, `Progressing=False`, `Degraded=False`. Any other combination is a signal.

### 4. MachineConfigPools — how worker upgrades roll

```bash
# oc
oc get machineconfigpools
oc get machinesets -A
```

`kubectl` cannot read `MachineConfigPool` either — it's an MCO-managed CRD only OpenShift has.

### 5. Network shape — confirm the CIDRs from the Terraform output

```bash
# oc
oc get network.config cluster -o jsonpath='{"machineCIDR: "}{.spec.clusterNetwork[*].cidr}{"\n"}{"serviceCIDR: "}{.spec.serviceNetwork[*]}{"\n"}'
oc get infrastructure cluster -o jsonpath='{.status.platformStatus.aws}{"\n"}'
```

```bash
# kubectl
kubectl get network.config cluster -o jsonpath='{"machineCIDR: "}{.spec.clusterNetwork[*].cidr}{"\n"}{"serviceCIDR: "}{.spec.serviceNetwork[*]}{"\n"}'
```

Expected on `cfk-dev`:
- Machine CIDR: `10.0.0.0/16`
- Pod CIDR: `10.128.0.0/14`
- Service CIDR: `172.30.0.0/16`

### 6. Cluster authentication shape (matters for OIDC tomorrow)

```bash
# oc
oc get oauth cluster -o jsonpath='{.spec.identityProviders[*].name}{"\n"}'
```

`OAuth` is an OpenShift-only CRD; no `kubectl` form. Note for tomorrow whether Okta is wired up yet or whether only `kube:admin` exists.

### 7. Ingress — where Routes actually land

```bash
# oc
oc -n openshift-ingress get svc router-default -o wide
oc get ingresscontroller -n openshift-ingress-operator default -o yaml | sed -n '/^spec:/,/status:/p'
```

```bash
# kubectl — the Service is readable, the IngressController CRD is not
kubectl -n openshift-ingress get svc router-default -o wide
```

The `router-default` Service's `EXTERNAL-IP` (an AWS NLB hostname) is what `*.apps.cfk-dev.2lcu.p1.openshiftapps.com` resolves to, and therefore what your custom-domain CNAME `*.dev.confluent.psyncopate.io` ultimately points at.

### 8. DNS — confirm the wildcard CNAME is in place

This is read-only DNS, runnable on any laptop with `dig`:

```bash
dig +short controlcenter.dev.confluent.psyncopate.io CNAME
dig +short controlcenter.dev.confluent.psyncopate.io A
```

You should see the chain `*.dev.confluent.psyncopate.io.` → `*.apps.cfk-dev.2lcu.p1.openshiftapps.com.` → the AWS NLB hostnames → A records.

## Troubleshooting Exercise — read the cluster operator status correctly

```bash
# oc — pick any cluster operator and read its conditions deeply
oc get clusteroperator authentication -o yaml | sed -n '/^status:/,/relatedObjects/p'
```

Look for `Available`, `Progressing`, `Degraded` in `.status.conditions[]`. A healthy CO is `Available=True`, `Progressing=False`, `Degraded=False`. Any other combination is a signal.

If any cluster operator is `Degraded`, the most useful next two commands are:

```bash
# oc
oc describe clusteroperator authentication            # tells you which component is unhealthy
oc -n openshift-authentication get pods               # check that operator's own pods
```

`kubectl` has no equivalent — `ClusterOperator` is OpenShift-only — but you can still read the underlying Deployment + Pods of the failing operator:

```bash
kubectl -n openshift-authentication get pods
kubectl -n openshift-authentication get deploy
```

## Deliverable — `deliverables/<you>/week03/monday.md`

A **one-page ROSA inventory** the team can pin to a wiki:

1. **Cluster version, region, AWS account ID** (mask the account if needed — the workflow Outputs show it explicitly)
2. **Classic or HCP** + how you confirmed (the `oc get hostedcontrolplane -A` check + the `*-ControlPlane-Role` IAM role)
3. **Worker node count, instance types, AZ spread** (paste the `oc get nodes` table)
4. **The full `oc get clusteroperators` output** (or a screenshot)
5. **Network CIDRs** — machine, pod, service
6. **Identity providers configured** (Okta or just `kube:admin`)
7. **The Ingress NLB hostname** (the `EXTERNAL-IP` of `router-default`)
8. **The custom-domain CNAME chain** confirmed via `dig`
9. Two questions you couldn't answer from `oc` alone

Cleanup: nothing — you only ran read-only commands.
