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
./scripts/lab-provision.sh gpu cohort-2026-q1
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
./scripts/lab-destroy.sh gpu cohort-2026-q1
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

This is the single reference for lab infrastructure costs.

### Environment Costs

| Environment | Instance Type | Spot $/hr | On-Demand $/hr | Weekly Use Case |
|-------------|--------------|-----------|----------------|-----------------|
| Shared Infra | NAT Gateway | ~$0.05 | ~$0.05 | All weeks |
| k0rdent Mgmt | t3.xlarge (4 vCPU, 16GB) | ~$0.06 | ~$0.17 | Week 1 |
| Metal3 Dev | m5.2xlarge (8 vCPU, 32GB) | ~$0.15 | ~$0.38 | Week 2 |
| KubeVirt | m5.xlarge + workers | ~$0.25 | ~$0.60 | Week 3 |
| GPU Lab | p3.8xlarge (4x V100) | ~$4.50 | ~$12.24 | Weeks 4-5 |
| GPU Advanced | p4d.24xlarge (8x A100) | ~$15.00 | ~$33.00 | Week 5 (advanced) |

### Cost Examples

| Scenario | Estimated Cost |
|----------|---------------|
| Shared infra running 24/7 | ~$35/month |
| Metal3 Dev - 8 hour session | ~$1.20 (spot) |
| KubeVirt Lab - 8 hour session | ~$2.00 (spot) |
| GPU Lab - 4 hour session | ~$18.00 (spot) |
| **Forgotten GPU Lab - 24 hours** | **~$108 (spot) / ~$294 (on-demand)** |

### Spot Instances

The k0rdent management cluster uses **on-demand instances by default** for reliability during long-running operations (cluster provisioning, Helm installs). Other lab types (Metal3, KubeVirt, GPU) support spot instances for cost savings:

```bash
# Enable spot instances for non-k0rdent labs (~60-70% savings)
./scripts/lab-provision.sh metal3 your-name --spot

# Use on-demand if spot unavailable
./scripts/lab-provision.sh metal3 your-name --no-spot
```

### Best Practices

- **Always destroy** environments when not in use
- Check `./scripts/lab-status.sh all` regularly for forgotten environments
- Use `--plan-only` flag before major changes
- Never leave GPU environments running overnight

## Troubleshooting

For quick diagnostics:

```bash
./scripts/lab-status.sh all          # Check all environments
./scripts/lab-status.sh k0rdent your-name  # Check specific environment
./scripts/lab-status.sh list         # List all state files
```

For comprehensive troubleshooting (AWS credentials, SSH issues, Terraform state, GPU problems), see the **[Troubleshooting Guide](docs/troubleshooting.md)**.

## Security Notes

- SSH keys are generated per-environment
- All EBS volumes are encrypted
- S3 buckets use server-side encryption
- IAM roles follow least-privilege principle
- Restrict `ALLOWED_SSH_CIDRS` in production
