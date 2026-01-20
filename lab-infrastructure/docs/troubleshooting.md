# Lab Infrastructure Troubleshooting Guide

This is the single reference for troubleshooting lab provisioning and connectivity issues.

## Quick Diagnostics

```bash
# Check your environment status
./scripts/lab-status.sh all

# Check specific environment
./scripts/lab-status.sh k0rdent your-name

# List all provisioned environments
./scripts/lab-status.sh list
```

## AWS Credentials Issues

### Error: `InvalidClientTokenId: The security token included in the request is invalid`

**Cause:** AWS credentials are missing, expired, or misconfigured.

**Solution:**
```bash
# Check current credentials
aws sts get-caller-identity

# If using standard credentials
aws configure
# Enter: Access Key ID, Secret Key, Region, Output format

# If using SSO
aws sso login --profile your-profile
export AWS_PROFILE=your-profile

# If using environment variables
export AWS_ACCESS_KEY_ID="your-key-id"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export AWS_DEFAULT_REGION="us-east-1"
```

### Error: `ExpiredToken` or `Token has expired`

**Solution:**
```bash
# For SSO profiles
aws sso login --profile your-profile

# For IAM users - regenerate credentials in AWS Console
```

## Terraform Issues

### Error: `Error acquiring state lock`

**Cause:** Previous Terraform operation didn't complete cleanly.

**Solution:**
```bash
# Get the lock ID from the error message, then:
cd lab-infrastructure/terraform/environments/<your-env>
terraform force-unlock LOCK_ID
```

### Error: `S3 bucket not found` or `NoSuchBucket`

**Cause:** Terraform state bucket doesn't exist.

**Solution:**
```bash
# Check if bucket exists
aws s3 ls | grep k0rdent-training-tfstate

# If missing, the provisioning script will create it automatically
./scripts/lab-provision.sh k0rdent your-name --auto-approve
```

### Error: `Error: Invalid provider configuration`

**Cause:** Region mismatch between config and environment.

**Solution:**
```bash
# Ensure AWS region is set
export AWS_DEFAULT_REGION=us-east-1

# Or configure via AWS CLI
aws configure set region us-east-1
```

## SSH Connection Issues

### Error: `Connection refused`

**Causes:**
1. Instance not running
2. SSH service not started
3. Security group blocking connection

**Diagnostics:**
```bash
# Check instance status
./scripts/lab-status.sh k0rdent your-name

# Check security groups in AWS Console
aws ec2 describe-security-groups --group-ids sg-xxx
```

### Error: `Permission denied (publickey)`

**Causes:**
1. Wrong SSH key
2. Wrong username
3. Key permissions too open

**Solution:**
```bash
# Fix key permissions
chmod 600 config/keys/*.pem

# Check you're using the correct key and username
# Each environment uses its OWN SSH key:
```

| Environment | SSH Key | Username |
|-------------|---------|----------|
| Bastion | `bastion.pem` | `ubuntu` |
| k0rdent | `k0rdent-<id>-key.pem` | `ubuntu` |
| Metal3 | `metal3-key.pem` | `ubuntu` |
| KubeVirt | `kubevirt-key.pem` | `ubuntu` |
| GPU Lab | `gpu-key.pem` | `ubuntu` |

### Error: `Host key verification failed`

**Solution:**
```bash
# Remove old host key (IP may have changed)
ssh-keygen -R <ip-address>
```

### Multi-hop SSH (via Bastion)

When connecting through bastion, use the correct keys for each hop:

```bash
# Correct: different keys for bastion and target
ssh -i metal3-key.pem \
  -o ProxyCommand="ssh -i bastion.pem -W %h:%p ubuntu@BASTION_IP" \
  ubuntu@METAL3_PRIVATE_IP

# Or use the lab-connect script which handles this automatically
./scripts/lab-connect.sh metal3 your-name
```

**Debug SSH:**
```bash
# Verbose mode shows connection details
ssh -v -i key.pem ubuntu@IP
```

## Instance Launch Failures

### Error: `InvalidBlockDeviceMapping: Volume size smaller than snapshot`

**Cause:** EBS volume size in Terraform is smaller than the AMI requires.

**Solution:** Update the volume_size in the module to meet AMI requirements (typically 30GB minimum for Ubuntu).

### Error: `InsufficientInstanceCapacity` (Spot)

**Cause:** No spot capacity available in the selected AZ.

**Solution:**
```bash
# Use on-demand instances instead
./scripts/lab-provision.sh metal3 your-name --no-spot
```

### Error: `VcpuLimitExceeded`

**Cause:** AWS account vCPU limits exceeded.

**Solution:**
1. Request limit increase in AWS Console (Service Quotas)
2. Or destroy unused environments: `./scripts/lab-destroy.sh all`

## k0rdent Installation Issues

### Installation Still Running

k0rdent installation takes 10-15 minutes after instance is available.

```bash
# Check progress
tail -f /var/log/k0rdent-init.log

# Check if complete
ls /opt/k0rdent-lab/.init-complete && echo "Installation complete!"
```

### Pods Not Starting

```bash
# Check pod status
kubectl get pods -n kcm-system

# Check pod events
kubectl describe pod <pod-name> -n kcm-system

# Check logs
kubectl logs <pod-name> -n kcm-system

# Common issue: waiting for cert-manager
kubectl get pods -n cert-manager
```

### CRDs Not Installed

```bash
# Check CRDs
kubectl get crds | grep k0rdent

# If missing, check controller logs
kubectl logs -n kcm-system -l app=kcm-controller-manager
```

## GPU Lab Issues

### GPU Not Detected

```bash
# Check NVIDIA drivers
nvidia-smi

# If not found, check cloud-init completed
cat /var/log/cloud-init-output.log | tail -50

# Check GPU Operator pods
kubectl get pods -n gpu-operator

# Check node labels
kubectl get nodes -o yaml | grep nvidia
```

### CUDA Errors

```bash
# Verify CUDA installation
nvcc --version

# Check GPU operator
kubectl get clusterpolicy
kubectl describe clusterpolicy gpu-cluster-policy
```

## Network Issues

### Cannot Reach Internet from Lab Instance

**Cause:** NAT Gateway issue or route table misconfiguration.

**Diagnostics:**
```bash
# From lab instance
curl -I https://google.com

# Check route table
ip route

# Check DNS
cat /etc/resolv.conf
nslookup google.com
```

### Cannot Reach Kubernetes API

```bash
# Check kubectl config
kubectl config current-context

# Check API server
kubectl cluster-info

# If using k0s
sudo k0s status
sudo k0s kubectl get nodes
```

## Cleanup Issues

### Destroy Fails with Dependencies

**Solution:**
```bash
# Destroy in correct order
./scripts/lab-destroy.sh k0rdent your-name --auto-approve
./scripts/lab-destroy.sh metal3 your-name --auto-approve
# Shared infrastructure last (if no other engineers using it)
./scripts/lab-destroy.sh shared --auto-approve
```

### Orphaned Resources

If Terraform state is corrupted:

```bash
# List resources manually
aws ec2 describe-instances --filters "Name=tag:Project,Values=k0rdent-training"

# Terminate orphaned instances
aws ec2 terminate-instances --instance-ids i-xxx

# Delete orphaned S3 state
aws s3 rm s3://k0rdent-training-tfstate-xxx/k0rdent/your-name/ --recursive
```

## Getting Help

1. **Check this guide first**
2. **Review logs:** `/var/log/k0rdent-init.log`, `/var/log/cloud-init-output.log`
3. **Slack:** #k0rdent-training
4. **Create GitHub issue** with:
   - Command that failed
   - Full error message
   - Output of `terraform version` and `aws sts get-caller-identity`
   - Region being used
