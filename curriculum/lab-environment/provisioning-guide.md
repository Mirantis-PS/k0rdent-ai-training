# Lab Environment Provisioning Guide

## Overview

Each engineer receives on-demand cloud environments for hands-on labs. This guide explains how to provision, use, and manage your lab environments.

## Quick Start (TL;DR)

```bash
# 1. Install prerequisites
terraform version   # >= 1.5.0
aws --version       # v2.x

# 2. Configure AWS
aws configure

# 3. Provision your k0rdent management cluster (Week 1)
cd lab-infrastructure
./scripts/lab-provision.sh k0rdent your-name --auto-approve

# 4. Connect
./scripts/lab-connect.sh k0rdent your-name

# 5. Destroy when done
./scripts/lab-destroy.sh k0rdent your-name --auto-approve
```

> **Note:** The script automatically creates all shared infrastructure (VPC, bastion, S3) on first run.

## How It Works

The lab infrastructure supports **multiple engineers running simultaneously** with complete isolation:

```
┌─────────────────────────────────────────────────────────────┐
│           SHARED INFRASTRUCTURE (auto-created)               │
│         VPC, Bastion, S3 Buckets, IAM Roles                 │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐         │
│  │  john-doe   │  │  jane-doe   │  │  bob-smith  │   ...   │
│  │   Metal3    │  │   Metal3    │  │  KubeVirt   │         │
│  │ 10.0.8.x    │  │ 10.0.8.y    │  │ 10.0.8.z    │         │
│  └─────────────┘  └─────────────┘  └─────────────┘         │
│                                                             │
│  Each engineer has isolated state and resources             │
└─────────────────────────────────────────────────────────────┘
```

**Key Points:**
- Shared infrastructure is created **automatically** on first run
- Each engineer uses a unique name (e.g., `john-doe`, `jane-doe`)
- Running the same command with different names creates **completely isolated** environments
- State files are stored separately: `<lab-type>/<your-name>/terraform.tfstate`

## Environment Types

| Type | Use Case | Weeks | Instance Type | Est. Cost/hr (Spot) |
|------|----------|-------|---------------|---------------------|
| **Shared Infra** | Foundation (VPC, S3, IAM) | All | N/A | ~$0.05 (NAT only) |
| **k0rdent Mgmt** | k0rdent Enterprise installation | 1 | t3.xlarge (4 vCPU, 16GB) | ~$0.06 |
| **Metal3 Dev** | BMaaS labs | 2 | m5.2xlarge (8 vCPU, 32GB) | ~$0.15 |
| **KubeVirt Lab** | VMaaS (non-GPU) | 3 | m5.xlarge + m5.2xlarge workers | ~$0.25 |
| **GPU Lab** | VMaaS/KaaS/AI | 4-5 | p3.8xlarge (4x V100) | ~$4.50 |
| **GPU Advanced** | NVLink topology | 4-5 | p4d.24xlarge (8x A100) | ~$15.00 |
| **Full Stack** | Capstone | 6 | Multi-node cluster | ~$5.00 |

> **Note:** For validation/testing, use smaller instances (t3.medium) before deploying production sizes.

## Prerequisites

### Required Tools

```bash
# Check Terraform (>= 1.5.0 required)
terraform version

# Check AWS CLI
aws --version

# Verify AWS credentials
aws sts get-caller-identity
```

### AWS Credentials Setup

Option 1: AWS CLI Profile (Recommended)
```bash
aws configure
# AWS Access Key ID: <your-access-key>
# AWS Secret Access Key: <your-secret-key>
# Default region name: <your-preferred-region>  (e.g., eu-west-1, us-east-1, us-west-2)
# Default output format: json
```

Option 2: Environment Variables
```bash
export AWS_ACCESS_KEY_ID="your-key-id"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export AWS_DEFAULT_REGION="your-region"  # Must match terraform.tfvars region
```

Option 3: AWS SSO
```bash
aws sso login --profile your-sso-profile
export AWS_PROFILE=your-sso-profile
```

### Configuring Your Region

Update `terraform.tfvars` in the shared environment to use your preferred region:

```bash
cd lab-infrastructure/terraform/environments/shared
cp terraform.tfvars.example terraform.tfvars
vim terraform.tfvars
```

Set your region and a valid availability zone:
```hcl
region  = "us-east-1"      # Your preferred region
gpu_az  = "us-east-1a"     # Must be a valid AZ in that region
```

**Common region/AZ combinations:**
| Region | GPU AZ | Notes |
|--------|--------|-------|
| `us-east-1` | `us-east-1a` | N. Virginia - good GPU availability |
| `us-west-2` | `us-west-2a` | Oregon - good GPU availability |
| `eu-west-1` | `eu-west-1a` | Ireland |
| `ap-northeast-1` | `ap-northeast-1a` | Tokyo |

> **Note:** GPU instances (P3, P4) are only available in specific regions/AZs. Check [AWS GPU instance availability](https://aws.amazon.com/ec2/instance-types/p3/) when planning GPU labs.

## First-Time Setup

### Step 1: Install Prerequisites

```bash
# Check Terraform (>= 1.5.0 required)
terraform version

# Check AWS CLI (v2 required)
aws --version
```

### Step 2: Configure AWS Credentials

```bash
aws configure
# AWS Access Key ID: <your-access-key>
# AWS Secret Access Key: <your-secret-key>
# Default region name: us-east-1  (or your preferred region)
# Default output format: json

# Verify it works
aws sts get-caller-identity
```

### Step 3: Provision Your k0rdent Management Cluster

```bash
cd lab-infrastructure

# This single command does everything:
# - Creates S3 bucket for Terraform state
# - Creates shared infrastructure (VPC, bastion, S3, IAM) if needed
# - Creates your k0rdent management cluster with:
#   - k0s Kubernetes (v1.32.4)
#   - k0rdent Enterprise (v1.2.1)
#   - k0rdent UI
# - Saves SSH keys to config/keys/
./scripts/lab-provision.sh k0rdent your-name --auto-approve
```

### Step 4: Connect

```bash
./scripts/lab-connect.sh k0rdent your-name
```

### Step 5: Verify k0rdent Installation

```bash
# Check installation progress (runs in background)
tail -f /var/log/k0rdent-init.log

# Or check if complete
ls /opt/k0rdent-lab/.init-complete

# Verify k0rdent pods
kubectl get pods -n kcm-system
```

That's it! You're ready to start the labs.

## Provisioning Lab Environments

### Option 1: Manual Terraform (Recommended for Learning)

#### Metal3 Environment

```bash
cd lab-infrastructure/terraform/environments/metal3-dev

# Create terraform.tfvars
cat > terraform.tfvars << 'EOF'
region       = "eu-west-1"
project_name = "k0rdent-training"

# For validation: use small instances
controller_instance_type = "t3.medium"

# For production: use nested virtualization capable
# controller_instance_type = "m5.2xlarge"

simulated_worker_count = 1
use_spot_instances = true
use_simple_cloud_init = true  # Set false for full Metal3 setup

k0s_version    = "v1.32.4+k0s.0"
metal3_version = "v1.8.0"

tags = {
  CostCenter  = "training"
  Owner       = "ps-team"
  Environment = "validation"
}
EOF

# Get AWS account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Initialize Terraform
terraform init \
  -backend-config="bucket=k0rdent-training-tfstate-${ACCOUNT_ID}" \
  -backend-config="key=metal3-dev/terraform.tfstate" \
  -backend-config="region=eu-west-1"

# Plan and apply
terraform plan -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars

# Save the SSH key (Metal3 generates its own key)
mkdir -p ../../config/keys
terraform output -raw ssh_private_key > ../../config/keys/metal3-key.pem
chmod 600 ../../config/keys/metal3-key.pem
```

#### Connect to Metal3 via Bastion

```bash
# Get instance IP
METAL3_IP=$(terraform output -raw controller_private_ip)
BASTION_IP=$(cd ../shared && terraform output -raw bastion_public_ip)

# SSH via bastion jump host (note: different keys!)
ssh -i ../../config/keys/metal3-key.pem \
  -o ProxyCommand="ssh -i ../../config/keys/bastion.pem -W %h:%p ec2-user@${BASTION_IP}" \
  ubuntu@${METAL3_IP}
```

### Option 2: CLI Scripts (Automation)

```bash
cd lab-infrastructure

# Provision Metal3 environment for an engineer
./scripts/lab-provision.sh metal3 engineer-01

# Provision KubeVirt environment
./scripts/lab-provision.sh kubevirt engineer-01 --workers 2

# Provision GPU lab for a cohort session
./scripts/lab-provision.sh gpu cohort-2024-q1

# Use on-demand instances instead of spot
./scripts/lab-provision.sh metal3 engineer-01 --no-spot

# Preview only (no changes)
./scripts/lab-provision.sh metal3 engineer-01 --plan-only
```

### Connecting to Lab Environments

```bash
# SSH to lab instance
./scripts/lab-connect.sh metal3 engineer-01

# Connect via bastion (if instance in private subnet)
./scripts/lab-connect.sh metal3 engineer-01 --bastion

# Copy kubeconfig locally
./scripts/lab-connect.sh metal3 engineer-01 --copy-kubeconfig

# Create kubectl tunnel
./scripts/lab-connect.sh kubevirt engineer-01 --tunnel 6443:6443
```

### Check Environment Status

```bash
# Check all environments
./scripts/lab-status.sh all

# Check specific environment
./scripts/lab-status.sh metal3 engineer-01

# List all deployed environments
./scripts/lab-status.sh list
```

### Destroy Lab Environments

```bash
# Destroy specific environment
./scripts/lab-destroy.sh metal3 engineer-01

# Destroy all environments for an engineer
./scripts/lab-destroy.sh all-engineer engineer-01

# Destroy GPU lab
./scripts/lab-destroy.sh gpu cohort-2024-q1
```

## Environment-Specific Instructions

### k0rdent Management Cluster

**Purpose:** Week 1 - k0rdent Enterprise installation and configuration

**Includes:**
- k0s Kubernetes distribution (v1.32.4)
- k0rdent Enterprise (v1.2.1) with:
  - KCM (Cluster Manager)
  - KSM (State Manager)
  - KOF (Observability & FinOps)
- k0rdent UI (web interface)
- Cluster API providers

**Getting Started:**
```bash
# Provision (15-20 min for k0rdent to fully initialize)
./scripts/lab-provision.sh k0rdent your-name --auto-approve

# Connect
./scripts/lab-connect.sh k0rdent your-name

# On the lab instance - verify installation
tail -f /var/log/k0rdent-init.log  # Watch progress
kubectl get pods -n kcm-system  # Should show Running

# Access k0rdent UI
kubectl port-forward svc/k0rdent-ui -n kcm-system 8080:80 --address 0.0.0.0 &
# Then from local machine: ./scripts/lab-connect.sh k0rdent your-name --tunnel 8080:8080
# Open http://localhost:8080 (admin / run: terraform output -raw ui_password)
```

### Metal3 Dev Environment

**Purpose:** Week 2 BMaaS labs

**Includes:**
- Ubuntu VM with nested virtualization support
- metal3-dev-env pre-cloned
- Virtual BMC emulation (sushy-tools)
- 3 simulated bare metal hosts

**Getting Started:**
```bash
# Connect to lab
./scripts/lab-connect.sh metal3 engineer-01

# On the lab instance
cd ~/metal3-dev-env
make  # Runs full setup
```

### KubeVirt Lab Environment

**Purpose:** Week 3 VMaaS (non-GPU portions)

**Includes:**
- k0s Kubernetes cluster (1 controller + 2 workers)
- KubeVirt operator pre-installed
- CDI for VM image management
- Sample VM templates

**Getting Started:**
```bash
# Connect to lab
./scripts/lab-connect.sh kubevirt engineer-01

# On the lab instance
kubectl get nodes  # Should show 3 nodes
kubectl get pods -n kubevirt  # KubeVirt operator running
```

### GPU Lab Environment

**Purpose:** Weeks 3-5 GPU-related labs

**Includes:**
- AWS p3.8xlarge (4x V100 GPUs, 32GB each)
- Kubernetes with NVIDIA GPU Operator
- Pre-configured for GPU passthrough
- vLLM inference templates

**Getting Started:**
```bash
# Connect to lab
./scripts/lab-connect.sh gpu cohort-2024-q1

# On the lab instance
nvidia-smi  # Should show 4 GPUs
kubectl get nodes -l nvidia.com/gpu.present=true
```

**IMPORTANT:** GPU labs are expensive (~$4.50/hr spot, ~$12/hr on-demand). Always terminate when not actively using.

### Full Stack Environment

**Purpose:** Week 6 Capstone

**Includes:**
- k0rdent control plane (HA)
- GPU worker nodes
- Pre-configured tenant namespaces
- Full multi-tenancy setup

## Troubleshooting

### AWS Credentials Issues

**Error:** `InvalidClientTokenId: The security token included in the request is invalid`

**Solution:**
```bash
# Re-authenticate
aws sts get-caller-identity

# If using SSO
aws sso login --profile your-profile

# Check credentials are exported
echo $AWS_ACCESS_KEY_ID
```

### Terraform State Issues

**Error:** `Error acquiring state lock` or `S3 bucket not found`

**Solution:**
```bash
# Check bucket exists
aws s3 ls | grep k0rdent-training-tfstate

# If missing, recreate (see Bootstrap section)

# Force unlock (use with caution)
terraform force-unlock LOCK_ID
```

### SSH Connection Issues

**Error:** `Connection refused` or `Permission denied`

**Check:**
1. Instance is running: `./scripts/lab-status.sh metal3 engineer-01`
2. Your IP is in allowed CIDRs
3. SSH key permissions: `chmod 600 key.pem`
4. **Using correct key for each environment** (see below)

**Important: Each environment uses its own SSH key!**

| Environment | SSH Key | User |
|-------------|---------|------|
| Bastion | `bastion.pem` | `ec2-user` |
| Metal3 | `metal3-key.pem` | `ubuntu` |
| KubeVirt | `kubevirt-key.pem` | `ubuntu` |
| GPU Lab | `gpu-key.pem` | `ubuntu` |

**Correct multi-hop SSH (Metal3 example):**
```bash
# This uses bastion key for proxy, metal3 key for target
ssh -i metal3-key.pem \
  -o ProxyCommand="ssh -i bastion.pem -W %h:%p ec2-user@BASTION_IP" \
  ubuntu@METAL3_PRIVATE_IP
```

**Debug:**
```bash
# Verbose SSH
ssh -v -i key.pem ec2-user@IP

# Check security group allows your IP
aws ec2 describe-security-groups --group-ids sg-xxx

# Verify instance is reachable from bastion
ssh -i bastion.pem ec2-user@BASTION_IP "ping -c 2 PRIVATE_IP"
```

### Instance Launch Failures

**Error:** `InvalidBlockDeviceMapping: Volume size smaller than snapshot`

**Solution:** Update the module's `volume_size` to meet AMI requirements (e.g., AL2023 needs 30GB minimum).

**Error:** `InsufficientInstanceCapacity` for spot instances

**Solution:**
```bash
# Use on-demand instead
./scripts/lab-provision.sh metal3 engineer-01 --no-spot
```

### Terraform Import (for existing resources)

If resources exist outside Terraform:
```bash
# Import existing S3 bucket
terraform import 'module.shared_infra.aws_s3_bucket.tfstate' bucket-name
```

## Cost Management

### Spot vs On-Demand

| Instance | Spot Price | On-Demand | Savings |
|----------|-----------|-----------|---------|
| t3.micro | $0.004/hr | $0.01/hr | 60% |
| m5.xlarge | $0.07/hr | $0.19/hr | 63% |
| m5.2xlarge | $0.14/hr | $0.38/hr | 63% |
| p3.8xlarge | $4.50/hr | $12.24/hr | 63% |

### Cost Guidelines

| Action | Estimated Cost |
|--------|---------------|
| Shared infra running 24/7 | ~$35/month (NAT Gateway) |
| Metal3 Dev - 8 hours | ~$1.20 (spot) |
| KubeVirt Lab - 8 hours | ~$2.00 (spot) |
| GPU Lab - 4 hours | ~$18.00 (spot) |
| Forgotten GPU Lab - 24 hours | ~$108 (spot) / ~$294 (on-demand) |

### Best Practices

**Do:**
- Use spot instances (default) for 60-70% savings
- Terminate environments when not in use
- Check `lab-status.sh` regularly for forgotten environments

**Don't:**
- Leave GPU environments running overnight
- Provision larger instances than needed
- Skip the `--plan-only` flag for major changes

## Architecture Reference

### Network Layout

```
VPC: 10.0.0.0/16
├── Public Subnets (10.0.1.0/24, 10.0.2.0/24, 10.0.3.0/24)
│   └── Bastion Host, NAT Gateway
├── Private Subnets (10.0.8.0/22, 10.0.12.0/22, 10.0.16.0/22)
│   └── Lab instances (Metal3, KubeVirt)
└── GPU Subnet (10.0.100.0/24)
    └── GPU instances (p3, p4d)
```

### Key Resources Created

| Resource | Name | Purpose |
|----------|------|---------|
| VPC | k0rdent-training-vpc | Network isolation |
| Bastion | k0rdent-training-bastion | SSH jump host |
| S3 | k0rdent-training-tfstate-* | Terraform state |
| S3 | k0rdent-training-images-* | OS images |
| S3 | k0rdent-training-artifacts-* | Lab artifacts |
| IAM | k0rdent-training-lab-instance | Instance role |

## Quick Reference

```bash
# Week 1: Provision k0rdent management cluster
./scripts/lab-provision.sh k0rdent your-name --auto-approve

# Connect to k0rdent
./scripts/lab-connect.sh k0rdent your-name

# Verify k0rdent installation
sudo k0s kubectl get pods -n kcm-system

# Access k0rdent UI (from management cluster)
sudo k0s kubectl port-forward svc/k0rdent-ui -n kcm-system 8080:80 --address 0.0.0.0 &

# Week 2: Provision Metal3 lab
./scripts/lab-provision.sh metal3 your-name --auto-approve

# Connect to Metal3
./scripts/lab-connect.sh metal3 your-name

# Check what's running
./scripts/lab-status.sh all

# Clean up when done
./scripts/lab-destroy.sh k0rdent your-name --auto-approve
./scripts/lab-destroy.sh metal3 your-name --auto-approve

# On lab instance - common k8s commands
sudo k0s kubectl get nodes
sudo k0s kubectl get pods -A
sudo k0s kubectl get clusters -A

# On GPU lab
nvidia-smi
kubectl get nodes -l nvidia.com/gpu.present=true
```

## Support

### Self-Service
1. Check this guide first
2. Review lab-infrastructure/README.md
3. Search Slack #k0rdent-training

### Escalation
- Slack: #k0rdent-training-support
- Email: training-support@mirantis.com
- Instructor: During lab sessions

### Reporting Issues

When reporting issues, include:
1. Command that failed
2. Full error message
3. Output of `terraform version` and `aws sts get-caller-identity`
4. Region being used
