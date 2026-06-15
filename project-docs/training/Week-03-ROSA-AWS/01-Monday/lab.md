# Week 3 Monday — Lab: Inventory Your ROSA Cluster

**Time**: ~2 hours (lighter — Tuesday/Wednesday are the dense ones)

## Hands-on Lab — produce a one-page ROSA inventory for your team

```bash
# 1. Identify cluster shape
oc get clusterversion -o jsonpath='{.items[0].status.desired.version}{"\n"}'
oc get infrastructure cluster -o jsonpath='{.status.platformStatus.aws.region}{"\n"}'
oc get nodes -o custom-columns=NAME:.metadata.name,INSTANCE:.metadata.labels.node\\.kubernetes\\.io/instance-type,ZONE:.metadata.labels.topology\\.kubernetes\\.io/zone,READY:.status.conditions[?\(@.type==\"Ready\"\)].status

# 2. Is it ROSA Classic or HCP?
oc get hostedcontrolplane -A 2>/dev/null && echo "→ ROSA HCP" || echo "→ ROSA Classic (or self-managed OCP)"

# 3. Cluster operators — health overview
oc get clusteroperators -o custom-columns=NAME:.metadata.name,AVAILABLE:.status.conditions[?\(@.type==\"Available\"\)].status,DEGRADED:.status.conditions[?\(@.type==\"Degraded\"\)].status | head -20

# 4. MachineConfigPools — how worker upgrades roll
oc get machineconfigpools
oc get machinesets -A

# 5. The AWS-side identifiers (read-only)
oc get infrastructure cluster -o yaml | sed -n '/platformStatus:/,/regionalEndpoints/p'

# 6. Cluster authentication shape (matters for OIDC tomorrow)
oc get oauth cluster -o jsonpath='{.spec.identityProviders[*].name}{"\n"}'

# 7. Find the ingress controller's load balancer IP — engineers need this for any Route work
oc -n openshift-ingress get svc router-default -o wide
```

## Troubleshooting Exercise — read the cluster operator status correctly

```bash
# Pick any cluster operator and read its conditions deeply
oc get clusteroperator authentication -o yaml | sed -n '/^status:/,/relatedObjects/p'

# Look for: Available, Progressing, Degraded conditions. What does each mean?
# A healthy CO has: Available=True, Progressing=False, Degraded=False.
# Any other combination is a signal.
```

If any cluster operator is `Degraded`, the most useful next command is:

```bash
oc describe clusteroperator <name>          # tells you which component is unhealthy
oc -n openshift-<component> get pods        # check that operator's own pods
```

## Deliverable — `deliverables/<you>/week03/monday.md`

A **one-page ROSA inventory** the team can pin to a wiki:

1. **Cluster version, region, AWS account ID** (mask the account if needed)
2. **HCP or Classic** + how you confirmed
3. **Worker node count, instance types, AZ spread**
4. **The full `oc get clusteroperators` output** (or a screenshot)
5. **Identity providers configured** (Okta, htpasswd, etc.)
6. **The Ingress LB IP** (useful for Route troubleshooting later)
7. Two questions

Cleanup: nothing — you only ran read-only commands.
