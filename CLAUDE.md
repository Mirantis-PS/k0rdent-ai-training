# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is the **k0rdent AI Infrastructure Training Program** - a 6-week curriculum and AWS-based lab platform for teaching engineers how to implement Mirantis k0rdent. The project enables hands-on learning for building: Bare Metal as a Service (BMaaS), Virtual Machines as a Service (VMaaS), Kubernetes as a Service (KaaS), and Models as a Service (MaaS).

## Common Commands

### Lab Provisioning (from lab-infrastructure/)

```bash
# Provision shared infrastructure (admin, one-time)
./scripts/lab-provision.sh shared --auto-approve

# Provision per-engineer environments
./scripts/lab-provision.sh metal3 <engineer-id> --auto-approve
./scripts/lab-provision.sh kubevirt <engineer-id> --auto-approve
./scripts/lab-provision.sh gpu <session-id> --auto-approve

# Key options: --spot/--no-spot, --workers N, --plan-only, --region <region>
```

### Lab Operations

```bash
./scripts/lab-status.sh all                           # Check all environments
./scripts/lab-status.sh metal3 <engineer-id>          # Specific environment status
./scripts/lab-connect.sh metal3 <engineer-id>         # SSH via bastion
./scripts/lab-connect.sh kubevirt <engineer-id> --worker 0  # Connect to worker
./scripts/lab-destroy.sh metal3 <engineer-id>         # Destroy environment
```

### Terraform Direct Usage

```bash
cd terraform/environments/<env-type>
terraform init -backend-config=backend.conf
terraform plan -var-file=<engineer>.tfvars
terraform apply -auto-approve
```

## Architecture

### Directory Structure

- **curriculum/** - 6-week training content (theory, labs, resources per week)
- **lab-infrastructure/** - IaC for AWS lab environments
  - **terraform/modules/** - Reusable Terraform modules (shared-infra, bastion, metal3-dev, kubevirt-lab, gpu-lab, full-stack)
  - **terraform/environments/** - Per-environment configurations
  - **scripts/** - Bash orchestration for provisioning/connection/status/destroy

### Multi-Tenancy Model

**Shared Infrastructure (deployed once):**
- VPC (10.0.0.0/16), S3 buckets for state/artifacts, IAM roles, Bastion host

**Per-Engineer Environments:**
- Isolated Terraform state: `s3://k0rdent-training-tfstate-<account>/<env-type>/<engineer-id>/terraform.tfstate`
- Individual SSH key pairs, security groups, resource quotas

### Lab Environment Types

| Type | Use Case | Instance | Cost/hr |
|------|----------|----------|---------|
| metal3-dev | Weeks 1-2: Simulated bare metal via libvirt | m5.2xlarge | ~$0.12 (spot) |
| kubevirt-lab | Week 3: Multi-node K8s with KubeVirt | 3x t3.xlarge | ~$0.20 (spot) |
| gpu-lab | Weeks 3-5: GPU workloads | p3.8xlarge (shared) | ~$4.50 (spot) |
| full-stack | Week 6: Complete k0rdent environment | Multi-node | varies |

### Provisioning Flow

```
lab-provision.sh → Terraform Apply → cloud-init Bootstrap → SSH via Bastion
```

Cloud-init templates in `terraform/modules/*/templates/` are parameterized with Terraform variables.

## Key Technologies

- **k0s** (v1.32.4+k0s.0): Kubernetes distribution
- **Metal3** (v1.8.0) + **Ironic**: Bare metal provisioning
- **KubeVirt** (v1.6.3): VMs on Kubernetes
- **Cluster API** (v1.11): K8s cluster provisioning
- **NVIDIA GPU Operator** (v25.10.0): GPU management
- **Terraform** (>= 1.5.0) with AWS Provider (~5.0)
- **vLLM**, **Run:AI**, **Kubeflow**, **MLflow**, **SLURM**: AI/ML workloads

## Development Patterns

### Terraform Modules

Each module follows the pattern:
- `main.tf` - Resources
- `variables.tf` - Inputs with defaults
- `outputs.tf` - Exported values
- `templates/` - cloud-init YAML templates

### Bash Scripts

All scripts use:
- `set -euo pipefail` for strict error handling
- Color-coded logging (`log_info`, `log_success`, `log_error`)
- Comprehensive `--help` documentation

### Cloud-Init Templates

Templates use Terraform interpolation (`${variable}`) for:
- SSH key injection
- k0s/Metal3 version configuration
- Network settings
- User provisioning

## Key Documentation

- `lab-infrastructure/docs/architecture-design.md` - Complete architecture (1,070 lines)
- `curriculum/lab-environment/provisioning-guide.md` - Lab setup guide
- `curriculum/k0rdent-ai-infrastructure-training-curriculum.md` - Full 6-week syllabus

## Cost Optimization

The platform uses spot instances by default (60-70% savings), shared GPU resources across engineers, and TTL tags for auto-termination. Estimated cost: ~$2,300 per 15-engineer cohort.
