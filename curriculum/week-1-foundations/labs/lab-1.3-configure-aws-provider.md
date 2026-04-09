# Lab 1.3: Configure AWS Infrastructure Provider

**Duration:** 3 hours
**Type:** Hands-on Lab

## Table of Contents

- [Objectives](#objectives)
- [Prerequisites](#prerequisites)
- [Resuming This Lab](#resuming-this-lab)
- [Part 1: Understanding Infrastructure Providers (~5 min)](#part-1-understanding-infrastructure-providers-5-min)
  - [What are Infrastructure Providers?](#what-are-infrastructure-providers)
  - [Provider Components](#provider-components)
- [Part 2: AWS IAM Requirements (~5 min)](#part-2-aws-iam-requirements-5-min)
  - [Required Permissions](#required-permissions)
  - [Exercise: Verify AWS Permissions](#exercise-verify-aws-permissions)
- [Part 3: Create AWS Credentials in k0rdent (~10 min)](#part-3-create-aws-credentials-in-k0rdent-10-min)
  - [Step 1: Create AWS Secret](#step-1-create-aws-secret)
  - [Step 2: Create AWSClusterStaticIdentity](#step-2-create-awsclusterstaticidentity)
  - [Step 3: Create k0rdent Credential Object](#step-3-create-k0rdent-credential-object)
- [Part 4: Verify Provider Configuration (~5 min)](#part-4-verify-provider-configuration-5-min)
  - [Check AWS Provider Status](#check-aws-provider-status)
  - [Verify AWS Provider Controller](#verify-aws-provider-controller)
- [Part 5: Verify Provider Readiness (~5 min)](#part-5-verify-provider-readiness-5-min)
  - [Check CAPA Controller](#check-capa-controller)
  - [Verify the Credential Chain](#verify-the-credential-chain)
- [Part 6: SSH Key Pair for Managed Clusters (~5 min, Optional)](#part-6-ssh-key-pair-for-managed-clusters-5-min-optional)
- [Part 7: Review Available Cluster Templates (~5 min)](#part-7-review-available-cluster-templates-5-min)
  - [Template Parameters](#template-parameters)
- [Part 8: Provider Security Best Practices (~5 min)](#part-8-provider-security-best-practices-5-min)
  - [Principle of Least Privilege](#principle-of-least-privilege)
  - [Credential Rotation](#credential-rotation)
  - [Multi-Account Access](#multi-account-access)
- [Validation Checklist](#validation-checklist)
- [Troubleshooting](#troubleshooting)
  - [Credential Issues](#credential-issues)
  - [Provider Controller Issues](#provider-controller-issues)
- [Summary](#summary)
- [Next Lab](#next-lab)

## Objectives

In this lab, you will:
- Understand Cluster API (CAPI) provider architecture
- Configure AWS credentials for k0rdent
- Set up the AWS infrastructure provider
- Verify provider functionality
- Prepare for cluster provisioning

## Prerequisites

- Completed Labs 1.1 and 1.2
- AWS account with permissions to create:
  - EC2 instances
  - VPCs and networking
  - IAM roles and policies
  - Security groups
- AWS Access Key ID and Secret Access Key

## Resuming This Lab

If your SSH session dropped or you're returning the next day:

```bash
cd lab-infrastructure
./scripts/lab-connect.sh <your-engineer-id>
kubectl get nodes && kubectl get pods -n kcm-system
```

---

## Part 1: Understanding Infrastructure Providers (~5 min)

### What are Infrastructure Providers?

k0rdent uses Cluster API (CAPI) providers to manage infrastructure across different platforms:

```
+---------------------+
|     k0rdent KCM     |
+----------+----------+
           |
           v
+----------+----------+
|    Cluster API      |
+----------+----------+
           |
     +-----+-----+
     |     |     |
     v     v     v
  +---+ +---+ +------+
  |AWS| |AZR| |vSphere|
  +---+ +---+ +------+
```

### Provider Components

Each provider includes:
1. **Controller Manager** - Reconciles cluster resources
2. **Templates** - Defines cluster configurations
3. **Credentials** - Access to cloud infrastructure

## Part 2: AWS IAM Requirements (~5 min)

### Required Permissions

> **Training vs Production:** The policy below uses broad permissions (`ec2:*`, `elasticloadbalancing:*`) for simplicity in this training environment. For production deployments, use a scoped-down policy -- see [Theory 1.3: Infrastructure Providers](../theory/1.3-infrastructure-providers.md) for a least-privilege reference policy.

Create an IAM policy with these permissions:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:*",
        "elasticloadbalancing:*",
        "autoscaling:*",
        "iam:CreateServiceLinkedRole",
        "iam:PassRole",
        "iam:GetRole",
        "iam:ListAttachedRolePolicies",
        "ssm:GetParameter"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "iam:CreateRole",
        "iam:DeleteRole",
        "iam:AttachRolePolicy",
        "iam:DetachRolePolicy",
        "iam:PutRolePolicy",
        "iam:DeleteRolePolicy"
      ],
      "Resource": "arn:aws:iam::*:role/k0rdent-*"
    }
  ]
}
```

### Exercise: Verify AWS Permissions

From your local machine:

```bash
# Verify your AWS identity
aws sts get-caller-identity

# Check EC2 permissions
aws ec2 describe-instances --region <your-region> --max-items 1
```

## Part 3: Create AWS Credentials in k0rdent (~10 min)

### Step 1: Create AWS Secret

SSH to your management cluster and create the credentials secret.

#### Option A: Using IAM User Credentials (Recommended for Training)

```bash
# Set your AWS credentials
export AWS_ACCESS_KEY_ID="your-access-key-id"
export AWS_SECRET_ACCESS_KEY="your-secret-access-key"

# Delete the placeholder secret from cloud-init (if it exists)
kubectl delete secret aws-cluster-identity-secret -n kcm-system 2>/dev/null

# Create with your real credentials
kubectl create secret generic aws-cluster-identity-secret \
  --from-literal=AccessKeyID="${AWS_ACCESS_KEY_ID}" \
  --from-literal=SecretAccessKey="${AWS_SECRET_ACCESS_KEY}" \
  -n kcm-system
```

#### Option B: Using AWS SSO Credentials

If you're using AWS SSO, you must include the session token:

```bash
# First, ensure you're logged in to SSO
aws sso login --profile your-sso-profile

# Export credentials including session token
eval "$(aws configure export-credentials --format env --profile your-sso-profile)"

# Delete the placeholder secret from cloud-init (if it exists)
kubectl delete secret aws-cluster-identity-secret -n kcm-system 2>/dev/null

# Create the secret with session token
kubectl create secret generic aws-cluster-identity-secret \
  --from-literal=AccessKeyID="${AWS_ACCESS_KEY_ID}" \
  --from-literal=SecretAccessKey="${AWS_SECRET_ACCESS_KEY}" \
  --from-literal=SessionToken="${AWS_SESSION_TOKEN}" \
  -n kcm-system
```

> **Warning:** SSO session tokens expire (typically after 1-12 hours). For long-running cluster operations, IAM user credentials (Option A) are more reliable.

#### Refreshing Expired SSO Credentials

If your SSO session expires during cluster provisioning, CAPA will start logging `AuthFailure` errors. To refresh:

```bash
# 1. Re-login to SSO (from your LOCAL machine, not the bastion)
aws sso login --profile your-sso-profile
eval "$(aws configure export-credentials --format env --profile your-sso-profile)"

# 2. Update the secret via SSH (avoids terminal paste corruption of the long SessionToken)
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  -i <path-to-mgmt-key> \
  -o "ProxyCommand=ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i <path-to-bastion-key> -W %h:%p ec2-user@<bastion-ip>" \
  ubuntu@<mgmt-ip> \
  "kubectl delete secret aws-cluster-identity-secret -n kcm-system && \
   kubectl create secret generic aws-cluster-identity-secret -n kcm-system \
     --from-literal=AccessKeyID='$AWS_ACCESS_KEY_ID' \
     --from-literal=SecretAccessKey='$AWS_SECRET_ACCESS_KEY' \
     --from-literal=SessionToken='$AWS_SESSION_TOKEN'"

# 3. Restart CAPA to pick up the new credentials (it caches the AWS session)
ssh ... ubuntu@<mgmt-ip> "kubectl rollout restart deployment capa-controller-manager -n kcm-system"
```

> **Why from your local machine?** The SessionToken is ~1000 characters. Pasting it directly into a terminal on the bastion can truncate or corrupt the value. Sending it via SSH from your local machine preserves the full token.

> **Convenience script:** You can also use the provided refresh script which handles all of this automatically:
> ```bash
> ./scripts/lab-refresh-creds.sh <your-name>
> ```

### Step 2: Create AWSClusterStaticIdentity

Create a YAML file for the identity:

```bash
cat << 'EOF' | kubectl apply -f -
apiVersion: infrastructure.cluster.x-k8s.io/v1beta2
kind: AWSClusterStaticIdentity
metadata:
  name: aws-cluster-identity
  labels:
    k0rdent.mirantis.com/component: "kcm"
spec:
  secretRef: aws-cluster-identity-secret
  allowedNamespaces:
    list:
    - kcm-system
    selector:
      matchLabels: {}
EOF
```

> **Important:** The `allowedNamespaces.list` explicitly permits `kcm-system` to use this identity. The `selector` with empty `matchLabels: {}` also matches all namespaces, but CAPA v1beta2 requires the `list` field to be set for explicit namespace authorization. In production, restrict access to specific tenant namespaces (e.g., `list: [team-platform, team-ml]`).

### Step 3: Create k0rdent Credential Object

```bash
cat << 'EOF' | kubectl apply -f -
apiVersion: k0rdent.mirantis.com/v1beta1
kind: Credential
metadata:
  name: aws-cluster-identity-cred
  namespace: kcm-system
spec:
  identityRef:
    apiVersion: infrastructure.cluster.x-k8s.io/v1beta2
    kind: AWSClusterStaticIdentity
    name: aws-cluster-identity
    namespace: kcm-system
EOF
```

## Part 4: Verify Provider Configuration (~5 min)

### Check AWS Provider Status

```bash
# Verify the secret exists
kubectl get secret aws-cluster-identity-secret -n kcm-system

# Check the identity (cluster-scoped, no namespace needed)
kubectl get awsclusterstaticidentity

# Verify the credential (or use alias: kgcred)
kubectl get credential aws-cluster-identity-cred -n kcm-system
```

### Verify AWS Provider Controller

```bash
# Check CAPA (Cluster API Provider AWS) controller
# Note: In k0rdent Enterprise, CAPA runs in kcm-system namespace
kubectl get pods -n kcm-system | grep capa

# If no pods found in kcm-system, check capa-system
kubectl get pods -n capa-system 2>/dev/null || echo "CAPA pods are in kcm-system"

# View controller logs
kubectl logs -n kcm-system -l cluster.x-k8s.io/provider=infrastructure-aws --tail=50
```

## Part 5: Verify Provider Readiness (~5 min)

Now that credentials are configured, verify the entire chain is working — from the CAPA controller to the Credential object.

### Check CAPA Controller

The AWS infrastructure provider (CAPA) must be running and healthy:

```bash
# Verify CAPA controller is running
kubectl get pods -n kcm-system | grep capa

# Check for errors in CAPA logs
kubectl logs -n kcm-system -l cluster.x-k8s.io/provider=infrastructure-aws --tail=20
```

You should see `capa-controller-manager` with `1/1 Running`. If there are credential errors in the logs, revisit Parts 2-4.

### Verify the Credential Chain

Check that all three layers of the credential model are properly connected:

```bash
# 1. Secret exists with AWS keys
kubectl get secret aws-cluster-identity-secret -n kcm-system

# 2. AWSClusterStaticIdentity references the secret
kubectl get awsclusterstaticidentity aws-cluster-identity -o jsonpath='{.spec.secretRef}' && echo ""

# 3. k0rdent Credential references the identity
kubectl get credential aws-cluster-identity-cred -n kcm-system -o jsonpath='{.spec.identityRef}' && echo ""

# Full chain summary
echo "=== Credential Chain ==="
echo "Secret:   aws-cluster-identity-secret"
echo "Identity: aws-cluster-identity"
echo "Credential: aws-cluster-identity-cred"
echo ""
echo "Ready for cluster provisioning in Lab 1.5"
```

> **What you're verifying:** The Credential object is what ClusterDeployments reference. If this chain is broken (wrong secret name, missing identity, etc.), cluster provisioning will fail with credential errors in Lab 1.5.

## Part 6: SSH Key Pair for Managed Clusters (~5 min, Optional)

The `sshKeyName` field in a ClusterDeployment is **optional**. If omitted, CAPA creates EC2 instances without an SSH key — k0rdent manages the nodes via CAPI, so direct SSH access isn't required for normal operations.

**When you need it:**
- Debugging node-level issues (kubelet logs, networking, disk)
- Advanced troubleshooting that requires shell access to managed cluster nodes

**When you can skip it:**
- Standard cluster operations (scaling, upgrades, service deployment)
- The training labs in this course (Lab 1.5 does not require it)

If you want SSH access to managed cluster nodes, create a key pair now:

```bash
# Generate a key pair (run from your LOCAL machine)
ssh-keygen -t ed25519 -f /tmp/k0rdent-clusters -N ""

# Import to the region where you'll deploy managed clusters
aws ec2 import-key-pair \
  --key-name k0rdent-clusters \
  --public-key-material fileb:///tmp/k0rdent-clusters.pub \
  --region us-east-1

# Save the private key
mkdir -p ~/.ssh
mv /tmp/k0rdent-clusters ~/.ssh/
mv /tmp/k0rdent-clusters.pub ~/.ssh/
chmod 600 ~/.ssh/k0rdent-clusters
```

Then include it in your ClusterDeployment spec:

```yaml
spec:
  config:
    sshKeyName: "k0rdent-clusters"  # Optional - omit if you don't need SSH access
    bastion:
      enabled: true  # Recommended when using sshKeyName
```

> **Region-specific:** SSH key pairs exist per-region. If you deploy clusters to multiple regions, import the key pair in each one.

## Part 7: Review Available Cluster Templates (~5 min)

With the AWS provider configured, review templates available for AWS:

```bash
# List AWS cluster templates (or use alias: kgct)
kubectl get clustertemplates -n kcm-system | grep -i aws

# View details of an AWS template
kubectl get clustertemplate -n kcm-system -l provider=aws -o yaml | head -100
```

> **Note:** Template names vary by k0rdent version. Use `kubectl get clustertemplates -A` to see available templates.

### Template Parameters

Note the configurable parameters:
- `region` - AWS region
- `instanceType` - EC2 instance type
- `sshKeyName` - SSH key pair name (optional — for node SSH access)
- `k8sVersion` - Kubernetes version

## Part 8: Provider Security Best Practices (~5 min)

### Principle of Least Privilege

1. **Use IAM Roles** when possible instead of access keys
2. **Scope permissions** to specific resources
3. **Enable CloudTrail** for audit logging

### Credential Rotation

```bash
# To rotate credentials:
# 1. Create new AWS access key in AWS Console
# 2. Update the secret
kubectl create secret generic aws-cluster-identity-secret \
  --from-literal=AccessKeyID="${NEW_ACCESS_KEY_ID}" \
  --from-literal=SecretAccessKey="${NEW_SECRET_ACCESS_KEY}" \
  -n kcm-system \
  --dry-run=client -o yaml | kubectl apply -f -

# 3. Delete old AWS access key from AWS Console
```

### Multi-Account Access

For managing clusters across multiple AWS accounts:

```yaml
apiVersion: infrastructure.cluster.x-k8s.io/v1beta2
kind: AWSClusterRoleIdentity
metadata:
  name: cross-account-identity
  namespace: kcm-system
spec:
  sourceIdentityRef:
    kind: AWSClusterStaticIdentity
    name: aws-cluster-identity
  roleARN: arn:aws:iam::TARGET_ACCOUNT:role/k0rdent-assume-role
```

## Validation Checklist

Before completing this lab, verify:

- [ ] AWS credentials secret created
- [ ] AWSClusterStaticIdentity created
- [ ] k0rdent Credential object created
- [ ] CAPA controller running and healthy
- [ ] Full credential chain verified (Secret → Identity → Credential)
- [ ] (Optional) SSH key pair created if you need node SSH access
- [ ] Can list AWS cluster templates
- [ ] Understand credential rotation process

## Troubleshooting

### Credential Issues

**Error: InvalidClientTokenId**
- Verify access key is correct
- Check if access key is active in AWS console

**Error: UnauthorizedAccess**
- Review IAM policy permissions
- Ensure policy is attached to user/role

### Provider Controller Issues

```bash
# Check controller logs (CAPA runs in kcm-system in k0rdent Enterprise)
kubectl logs -n kcm-system -l cluster.x-k8s.io/provider=infrastructure-aws --tail=100

# Check events
kubectl get events -n kcm-system --sort-by='.lastTimestamp' | tail -20
```

## Summary

In this lab, you:
- Understood CAPI provider architecture
- Created AWS credentials using the three-layer model (Secret → Identity → Credential)
- Verified the CAPA controller and credential chain are healthy
- Created SSH key pairs for managed cluster node access
- Reviewed available AWS cluster templates
- Learned security best practices for credential management

## Next Lab

Continue to [Lab 1.4: Production Configuration](lab-1.4-production-configuration.md)
