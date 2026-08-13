# Week 3 Wednesday — Lab: Pod-to-AWS Auth via IRSA

**Time**: ~4 hours
**Note**: this lab requires an IAM Role pre-created by the AWS team. Ask Tushar / platform for a sandbox role you can assume from `<you>-training` namespace.

## Hands-on Lab Part 1 — confirm the cluster's OIDC issuer is registered with AWS

```bash
# 1. Find the cluster's OIDC issuer URL
oc get authentication cluster -o jsonpath='{.spec.serviceAccountIssuer}{"\n"}'
# Should look like: https://rh-oidc.s3.us-east-1.amazonaws.com/<cluster-id>

# 2. Confirm this URL is registered as an IAM Identity Provider in AWS (requires AWS CLI)
#    Run from a host that has AWS read-only access to the the production account:
aws iam list-open-id-connect-providers
# Look for one whose URL matches the cluster's issuer
```

## Hands-on Lab Part 2 — create an IRSA-enabled SA and Pod

Assuming Tushar gave you a Role ARN like `arn:aws:iam::123456789:role/<you>-training-sandbox`:

```bash
oc project <you>-training

# 1. Create the SA with the role annotation
cat <<EOF | oc apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: aws-pod-sa
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789:role/<you>-training-sandbox
EOF

# 2. Deploy a Pod with the AWS CLI image, using that SA
cat <<EOF | oc apply -f -
apiVersion: v1
kind: Pod
metadata: {name: aws-pod}
spec:
  serviceAccountName: aws-pod-sa
  containers:
    - name: c
      image: amazon/aws-cli:2.17.0
      command: ["sleep","3600"]
EOF

oc wait --for=condition=Ready pod/aws-pod --timeout=60s

# 3. Inspect what got projected into the Pod
oc exec aws-pod -- ls -la /var/run/secrets/eks.amazonaws.com/serviceaccount/  # if EKS-style
oc exec aws-pod -- env | grep AWS                # AWS_WEB_IDENTITY_TOKEN_FILE + AWS_ROLE_ARN

# 4. Try a read-only AWS call
oc exec aws-pod -- aws sts get-caller-identity   # who am I? Should show the assumed role ARN
oc exec aws-pod -- aws s3 ls                     # list buckets — works if the Role allows
```

If `get-caller-identity` succeeds, the IRSA chain is complete end-to-end. The output ARN should NOT be a user ARN — it should be the `assumed-role/<your-role-name>/<session-name>` form, proving STS exchanged the projected token.

## Troubleshooting Exercise — break IRSA in 3 different places

**Break 1 — wrong Role ARN on the SA**

```bash
oc annotate sa aws-pod-sa eks.amazonaws.com/role-arn=arn:aws:iam::123456789:role/does-not-exist --overwrite
oc delete pod aws-pod
# Re-apply the Pod manifest...
oc exec aws-pod -- aws sts get-caller-identity     # what error?
```

Look at the error message — it'll tell you the STS call failed at `AssumeRoleWithWebIdentity`. That's diagnostic level 1.

**Break 2 — SA without the annotation**

```bash
oc annotate sa aws-pod-sa eks.amazonaws.com/role-arn- --overwrite     # remove the annotation
oc delete pod aws-pod
# Re-apply the Pod with the same SA...
oc exec aws-pod -- aws sts get-caller-identity     # different error?
oc exec aws-pod -- env | grep AWS                  # AWS_ env vars even set?
```

Without the SA annotation, the kubelet doesn't inject the projected token + env vars. The SDK has nothing to send to STS.

**Break 3 — Role trust policy doesn't match this SA**

This one you can't trigger directly from your training namespace (you don't own the IAM Role). But predict: if the trust policy's `sub` condition is `system:serviceaccount:<you>-training:DIFFERENT-SA`, what error does STS return?

Answer: `Not authorized to perform sts:AssumeRoleWithWebIdentity`.

## Deliverable — `deliverables/<you>/week03/wednesday.md`

1. **The cluster's OIDC issuer URL** + evidence it's registered in AWS IAM
2. **A successful `aws sts get-caller-identity`** from your Pod — paste the assumed-role ARN
3. **For each of the 3 breaks**: the exact error message + which step of the morning's chain failed
4. **NetApp S3 / future-state**: in 2 sentences, explain how the platform's current NetApp S3 endpoint (used for Flink checkpoints) would migrate to IRSA-based AWS S3 access. What would change?
5. Two questions

Cleanup:

```bash
oc delete pod aws-pod
oc delete sa aws-pod-sa
```
