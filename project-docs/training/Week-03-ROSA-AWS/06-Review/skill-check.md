# Week 3 — Skill Check

Tasks below confirm ROSA + AWS skills. Some are read-only inspections (you may not have IAM write in production).

## Task 1 — ROSA cluster inventory (Mon)

1. `oc get clusterversion` — capture current version
2. `oc get nodes -L topology.kubernetes.io/zone` — map nodes to AZs
3. `oc get machineset -A` — count + capacity per pool
4. Identify whether this is HCP or Classic from the apiserver URL pattern

**Verifies**: ROSA architecture (Mon)

## Task 2 — OIDC trace (Tue)

1. Open browser dev-tools, hit `oc login --web` or the console URL
2. Capture the Network log: every redirect from initial URL through to Console
3. Identify which step issues which token

**Verifies**: OIDC flow (Tue)

## Task 3 — IRSA pod (Wed)

If you have IAM rights (or can ask an admin):

1. Create a small IAM role with `s3:ListAllMyBuckets` only
2. Annotate a ServiceAccount with the role ARN
3. Deploy a Pod that uses that SA + runs `aws s3 ls`
4. Confirm it works WITHOUT any AWS access keys mounted

If no IAM rights:

1. Inspect an existing IRSA-using Pod in production (if applicable)
2. Show the projected SA token + the `eks.amazonaws.com/role-arn` annotation

**Verifies**: STS / IRSA chain (Wed)

## Task 4 — VPC connectivity ladder (Thu)

From a Pod in your training namespace, attempt + capture:

1. `nc -zv okta.example.com 443` — should succeed (tracker 2.9)
2. `nc -zv artifactory.example.com 443` — image pulls
3. `nc -zv netapp-s3.example.com 443` — Flink checkpoints
4. `nc -zv vm-kafka-dev.example.com 9094` — cluster-link path (tracker 2.10)

For each: document expected vs actual, and which firewall rule permits it.

**Verifies**: VPC + SG + firewall connectivity (Thu)

## Task 5 — Upgrade dry-run (Fri)

1. Read the current ROSA channel + available versions
2. Write a dry-run upgrade plan: minor version target, MachineConfigPool surge strategy, PDB review per StatefulSet
3. Document the "stop conditions" — when would you abort mid-upgrade?

**Verifies**: Cluster upgrade reasoning (Fri)

## Submission

`deliverables/<you>/week03/` with one file per task.
