# k0rdent AI Training Lab Infrastructure

Terraform-based infrastructure provisioning for k0rdent AI training labs.

## Quick Start

### Prerequisites

- AWS CLI configured with appropriate credentials
- Terraform >= 1.5.0
- bash shell

### Initial Setup

1. Configure lab settings:
```bash
cp config/lab-config.env.example config/lab-config.env
# Edit lab-config.env with your settings
```

2. Provision shared infrastructure:
```bash
./scripts/lab-provision.sh shared
```

3. Provision lab environments for engineers:
```bash
# Metal3 dev environment
./scripts/lab-provision.sh metal3 engineer-01

# KubeVirt lab environment
./scripts/lab-provision.sh kubevirt engineer-01

# GPU lab (shared instance for cohort)
./scripts/lab-provision.sh gpu cohort-2024-q1
```

## Lab Types

### Metal3 Dev Environment
Simulated bare metal provisioning with:
- k0s cluster with Metal3 operator
- Ironic for bare metal provisioning
- Virtual BMC for IPMI simulation
- 3 simulated bare metal workers

**Instance Type:** m5.2xlarge (8 vCPU, 32GB RAM)

### KubeVirt Lab Environment
VM workloads on Kubernetes:
- k0s cluster with KubeVirt
- CDI for VM image management
- Sample VM templates
- Multi-node cluster (1 controller + 2 workers)

**Instance Types:**
- Controller: m5.xlarge (4 vCPU, 16GB)
- Workers: m5.2xlarge (8 vCPU, 32GB)

### GPU Lab Environment
Shared GPU instance for AI workloads:
- k0s cluster with NVIDIA GPU Operator
- Multi-user namespaces with resource quotas
- vLLM inference templates
- Support for V100 (p3.8xlarge) and A100 (p4d.24xlarge)

**Instance Types:**
- Shared: p3.8xlarge (4x V100, 32GB each)
- Advanced: p4d.24xlarge (8x A100, 40GB each)

## CLI Scripts

### lab-provision.sh
Provision lab environments.

```bash
# Shared infrastructure
./scripts/lab-provision.sh shared

# Per-engineer environments
./scripts/lab-provision.sh metal3 <engineer-id> [--spot|--no-spot]
./scripts/lab-provision.sh kubevirt <engineer-id> [--workers N]

# Session-based environments
./scripts/lab-provision.sh gpu <session-id>
./scripts/lab-provision.sh gpu-advanced <session-id>  # 8x A100
```

### lab-status.sh
Check environment status.

```bash
./scripts/lab-status.sh all
./scripts/lab-status.sh metal3 engineer-01
./scripts/lab-status.sh list
```

### lab-connect.sh
Connect to lab instances.

```bash
# Direct SSH
./scripts/lab-connect.sh metal3 engineer-01
./scripts/lab-connect.sh kubevirt engineer-01 --worker 0

# With bastion jump
./scripts/lab-connect.sh metal3 engineer-01 --bastion <bastion-ip>

# Create tunnel for kubectl
./scripts/lab-connect.sh kubevirt engineer-01 --tunnel 6443:6443

# Copy kubeconfig
./scripts/lab-connect.sh metal3 engineer-01 --copy-kubeconfig
```

### lab-destroy.sh
Destroy lab environments.

```bash
./scripts/lab-destroy.sh metal3 engineer-01
./scripts/lab-destroy.sh all-engineer engineer-01
./scripts/lab-destroy.sh gpu cohort-2024-q1
```

## Directory Structure

```
lab-infrastructure/
├── config/
│   ├── lab-config.env         # Local configuration
│   ├── keys/                  # SSH keys (gitignored)
│   └── kubeconfig/            # Kubeconfigs (gitignored)
├── scripts/
│   ├── lab-provision.sh       # Provision environments
│   ├── lab-status.sh          # Check status
│   ├── lab-connect.sh         # Connect to instances
│   └── lab-destroy.sh         # Destroy environments
├── terraform/
│   ├── modules/
│   │   ├── shared-infra/      # VPC, S3, IAM
│   │   ├── metal3-dev/        # Metal3 environment
│   │   ├── kubevirt-lab/      # KubeVirt environment
│   │   └── gpu-lab/           # GPU environment
│   └── environments/
│       ├── shared/            # Shared infra config
│       ├── metal3-dev/        # Metal3 env config
│       ├── kubevirt-lab/      # KubeVirt env config
│       └── gpu-lab/           # GPU lab config
└── docs/
    └── architecture-design.md
```

## Cost Management

### Spot Instances (Default)
All labs use spot instances by default for ~60-70% cost savings.

Use `--no-spot` for critical sessions or when spot availability is low.

### GPU Cost Optimization
- Shared p3.8xlarge (4x V100) for most labs: ~$12/hour
- On-demand p4d.24xlarge (8x A100) only for Lab 3.3: ~$33/hour
- Estimated cohort cost: ~$2,300 for 15 engineers over 6 weeks

### Auto-Shutdown
Environments include CloudWatch alarms for low utilization.
Destroy unused environments promptly with `lab-destroy.sh`.

## Troubleshooting

### SSH Connection Issues
1. Check instance status: `./scripts/lab-status.sh <type> <id>`
2. Verify security groups allow SSH from your IP
3. Use bastion host if in private subnet: `--bastion <ip>`

### Terraform State Issues
State is stored in S3: `k0rdent-training-tfstate-<account-id>`
List all states: `./scripts/lab-status.sh list`

### GPU Not Detected
1. Check NVIDIA drivers: `nvidia-smi`
2. Check GPU Operator: `kubectl get pods -n gpu-operator`
3. Check node labels: `kubectl get nodes -o yaml | grep nvidia`

## Security Notes

- SSH keys are generated per-environment
- All EBS volumes are encrypted
- S3 buckets use server-side encryption
- IAM roles follow least-privilege principle
- Restrict `ALLOWED_SSH_CIDRS` in production
