# Lab 1.3: Configure AWS Infrastructure Provider

**Duration:** 3 hours
**Type:** Hands-on Lab

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

## Part 1: Understanding Infrastructure Providers

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

## Part 2: AWS IAM Requirements

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
aws ec2 describe-instances --region us-east-1 --max-items 1

# Check IAM permissions
aws iam get-user
```

## Part 3: Create AWS Credentials in k0rdent

### Step 1: Create AWS Secret

SSH to your management cluster and create the credentials secret.

#### Option A: Using IAM User Credentials (Recommended for Training)

```bash
# Set your AWS credentials
export AWS_ACCESS_KEY_ID="your-access-key-id"
export AWS_SECRET_ACCESS_KEY="your-secret-access-key"

# Create the secret
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

# Create the secret with session token
kubectl create secret generic aws-cluster-identity-secret \
  --from-literal=AccessKeyID="${AWS_ACCESS_KEY_ID}" \
  --from-literal=SecretAccessKey="${AWS_SECRET_ACCESS_KEY}" \
  --from-literal=SessionToken="${AWS_SESSION_TOKEN}" \
  -n kcm-system
```

> **Warning:** SSO session tokens expire (typically after 1-12 hours). For long-running cluster operations, IAM user credentials (Option A) are more reliable. If you use SSO and your session expires during cluster provisioning, you'll need to refresh the secret with new credentials.

### Step 2: Create AWSClusterStaticIdentity

Create a YAML file for the identity:

```bash
cat << 'EOF' | kubectl apply -f -
apiVersion: infrastructure.cluster.x-k8s.io/v1beta2
kind: AWSClusterStaticIdentity
metadata:
  name: aws-cluster-identity
spec:
  secretRef: aws-cluster-identity-secret
  allowedNamespaces:
    selector:
      matchLabels: {}
EOF
```

> **Important:** The `allowedNamespaces.selector` with empty `matchLabels: {}` permits **all namespaces** to use this identity. This is appropriate for training. In production, restrict access using specific labels (e.g., `matchLabels: {k0rdent.mirantis.com/project: "my-team"}`) or use `allowedNamespaces.list` to enumerate specific namespaces.

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

## Part 4: Verify Provider Configuration

### Check AWS Provider Status

```bash
# Verify the secret exists
kubectl get secret aws-cluster-identity-secret -n kcm-system

# Check the identity
kubectl get awsclusterstaticidentity -n kcm-system

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

## Part 5: Test Provider Connectivity

### Create a Test VPC (Optional)

To verify the provider works, create a simple VPC:

```bash
# This is a non-destructive test
aws ec2 describe-vpcs --region us-east-1

# List available AMIs for cluster nodes
aws ec2 describe-images \
  --region us-east-1 \
  --owners 099720109477 \
  --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*" \
  --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
  --output text
```

## Part 6: Configure Default AWS Region

Set the default region for cluster provisioning:

```bash
# Create a ConfigMap for AWS defaults (optional reference)
cat << 'EOF' | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: aws-provider-config
  namespace: kcm-system
data:
  AWS_REGION: "us-east-1"
  AWS_SSH_KEY_NAME: "k0rdent-clusters"
EOF
```

> **Note:** This ConfigMap is for reference. Actual cluster configuration is done via ClusterDeployment specs.

## Part 7: Create SSH Key Pair for Clusters

Clusters provisioned by k0rdent need SSH key pairs for node access:

```bash
# Generate SSH key pair
ssh-keygen -t ed25519 -f ~/.ssh/k0rdent-clusters -N ""

# Import to AWS
aws ec2 import-key-pair \
  --key-name k0rdent-clusters \
  --public-key-material fileb://~/.ssh/k0rdent-clusters.pub \
  --region us-east-1

# Verify
aws ec2 describe-key-pairs --key-names k0rdent-clusters --region us-east-1
```

## Part 8: Review Available Cluster Templates

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
- `sshKeyName` - SSH key pair name
- `k8sVersion` - Kubernetes version

## Part 9: Provider Security Best Practices

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
- [ ] AWS provider controller is running
- [ ] SSH key pair imported to AWS
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
- Created AWS credentials for k0rdent
- Configured the AWS infrastructure provider
- Verified provider functionality
- Prepared SSH keys for cluster provisioning
- Learned security best practices

## Next Lab

Continue to [Lab 1.4: Production Configuration](lab-1.4-production-configuration.md)
