# Wednesday — STS / IRSA (How Pods Authenticate to AWS APIs)

**Time**: ~90 min
**Diagram**: [`32-sts-irsa-flow.drawio`](32-sts-irsa-flow.drawio) — Pod → projected SA token → STS AssumeRoleWithWebIdentity → AWS credentials → AWS API

## Learning objective

> **No long-lived AWS credentials anywhere. Yet Pods can call AWS APIs (e.g. S3, KMS, SQS) with fine-grained IAM Roles.** How? IRSA — IAM Roles for Service Accounts. Understanding this trace prevents 90% of future "Pod can't access AWS" tickets.

## Architecture Discussion (~45 min)

The problem IRSA solves: traditionally, AWS APIs required long-lived `AWS_ACCESS_KEY_ID` + `AWS_SECRET_ACCESS_KEY`. Storing these in a K8s Secret is bad (audit, rotation, blast radius). IRSA replaces credentials with a chain of trust.

### The chain — three identity systems handshaking

1. **K8s ServiceAccount** — the Pod's identity inside the cluster
2. **OIDC trust** — AWS IAM trusts the cluster's OIDC issuer (a specific URL serving the cluster's public keys)
3. **IAM Role** — AWS identity with permissions; configured to trust SAs from the cluster

The flow:

```
Pod is created with serviceAccountName: my-app-sa
   │
   │ ServiceAccount has annotation: eks.amazonaws.com/role-arn=arn:aws:iam::ACCT:role/my-app-role
   │ (or rosa-equivalent annotation)
   ▼
kubelet projects a SHORT-LIVED SA token into the Pod at /var/run/secrets/eks.amazonaws.com/serviceaccount/token
   │
   │ Token is a JWT signed by the cluster's OIDC issuer
   │ Token has audience: sts.amazonaws.com
   ▼
The AWS SDK in the Pod sees env var AWS_WEB_IDENTITY_TOKEN_FILE pointing at the projected token
   │
   ▼
SDK calls AWS STS: AssumeRoleWithWebIdentity({RoleArn: my-app-role, WebIdentityToken: <projected token>})
   │
   ▼
AWS STS validates:
   - Is the token signed by an OIDC issuer we trust? (cluster OIDC issuer ARN registered in AWS IAM)
   - Does my-app-role's trust policy allow this specific SA (sub claim) to assume it?
   - Is the audience claim "sts.amazonaws.com"?
   │
   ▼
STS returns short-lived AWS credentials (AccessKey, SecretKey, SessionToken) — valid ~1 hour
   │
   ▼
SDK calls the actual AWS API (e.g. S3 GetObject) using those credentials
   │
   ▼
AWS API authorizes based on my-app-role's permission policy
```

Everything is short-lived. Nothing is stored. Credentials rotate automatically.

### What the engineer must configure

Three things, in three different places:

1. **K8s ServiceAccount with annotation** — `eks.amazonaws.com/role-arn` pointing at the IAM Role ARN
2. **IAM Role's trust policy** — `Principal: Federated: arn:aws:iam::ACCT:oidc-provider/<cluster-issuer>`, plus a `Condition: StringEquals: <cluster-issuer>:sub: system:serviceaccount:<ns>:<sa-name>`
3. **IAM Role's permission policy** — actual `s3:GetObject`, `kms:Decrypt`, etc.

If ANY of these is wrong, the chain breaks. Common bugs:
- SA annotation typo (wrong Role ARN)
- Trust policy missing the SA's exact `sub` claim
- Trust policy uses wrong OIDC issuer (wrong cluster)
- Permission policy doesn't include the action being called

### NetApp S3 in production — where this shows up

the platform uses NetApp S3 for Flink checkpoints (see `OUTBOUND-FIREWALL-REQUESTS.md`). NetApp S3 isn't AWS S3 — but if  the platform ever moves to AWS S3 for storage, IRSA is the auth pattern. ROSA also uses IRSA internally for the cluster operators (the EBS CSI driver, the cluster autoscaler, the image registry's S3 backend).

## Diagram Walkthrough (~25 min)

Trace one Pod-to-S3 call end-to-end. Stop at each layer: *what AWS API does it call, what does AWS verify, what could go wrong?*

## Failure Scenarios

| Symptom | Likely cause |
|---|---|
| `aws s3 ls` from Pod returns `Unable to locate credentials` | SA missing the `role-arn` annotation, OR projected token volume not mounted |
| `aws s3 ls` returns `AccessDenied` for the IAM Role | Trust policy doesn't allow this SA (check the `sub` claim) |
| `aws s3 ls` returns `AccessDenied` for a specific bucket | Permission policy missing the action — different bug |
| Credentials expire mid-job | SDK didn't refresh — usually a buggy old SDK; upgrade |
| `AssumeRoleWithWebIdentity` returns `InvalidIdentityToken` | OIDC issuer not registered in AWS IAM, or wrong audience |

## Q&A

1. Why does AWS need to be told about the cluster's OIDC issuer URL?
2. What's the `sub` claim in the SA token, and why does the IAM Role trust policy condition on it?
3. If a Pod runs as `default` SA (no role-arn annotation), can it call AWS APIs?
4. How long does a typical IRSA-issued credential live?
5. Why is IRSA "better" than mounting an `AWS_ACCESS_KEY_ID` Secret? Name three reasons.


## Added Enhancement — Network Path Analysis

Trace traffic:
Client -> DNS -> Load Balancer -> Security Group -> Route -> Service -> Pod

Exercise:
Identify where traffic is blocked and how to isolate the failure.
