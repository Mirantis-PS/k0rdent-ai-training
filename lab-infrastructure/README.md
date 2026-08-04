# k0rdent AI Training Lab Infrastructure

Terraform-based infrastructure provisioning for k0rdent AI training labs.

## Script Reference

> **Taking the training?** Don't start here — start at [Week 1: Foundations](../curriculum/week-1-foundations/README.md). Lab 1.1 walks you through provisioning step by step using these scripts, including credential setup and verification. This page is a technical reference.

### Prerequisites

- AWS CLI configured with appropriate credentials
- Terraform >= 1.8.0 (install via `brew install hashicorp/tap/terraform` on macOS — see Lab 1.1 Troubleshooting if you hit a Homebrew collision)
- `jq`
- bash shell

### Provision Your Lab

Each student gets a fully isolated environment (VPC, bastion, k0rdent cluster):

```bash
# Provision your student lab environment (interactive plan review)
./scripts/lab-provision.sh <your-name> --region <your-region>

# Examples:
./scripts/lab-provision.sh john-doe --region us-east-1
./scripts/lab-provision.sh john-doe --gpu                   # Add GPU support
./scripts/lab-provision.sh john-doe --metal3 --kubevirt     # Add Metal3 + KubeVirt
# Add --auto-approve to skip the interactive plan confirmation (CI / re-runs)
```

## Lab Types

All lab types are provisioned via the single `lab-provision.sh` script with feature flags.

### Metal3 Dev Environment (`--metal3`)
Simulated bare metal provisioning with:
- k0s cluster with Metal3 operator
- Ironic for bare metal provisioning
- Virtual BMC for IPMI simulation
- 3 simulated bare metal workers

**Instance Type:** m5.2xlarge (8 vCPU, 32GB RAM)

### KubeVirt Lab Environment (`--kubevirt`)
VM workloads on Kubernetes:
- k0s cluster with KubeVirt
- CDI for VM image management
- Sample VM templates
- Multi-node cluster (1 controller + 2 workers)

**Instance Types:**
- Controller: m5.xlarge (4 vCPU, 16GB)
- Workers: m5.2xlarge (8 vCPU, 32GB)

### GPU Lab Environment (`--gpu`)
GPU instance for AI workloads:
- k0s cluster with NVIDIA GPU Operator
- Multi-user namespaces with resource quotas
- vLLM inference templates
- Support for V100 (p3.8xlarge) and A100 (p4d.24xlarge)

**Instance Types:**
- Shared: p3.8xlarge (4x V100, 32GB each)
- Advanced: p4d.24xlarge (8x A100, 40GB each)

## CLI Scripts

### lab-provision.sh
Provision your student lab environment.

```bash
# Base lab (Week 1)
./scripts/lab-provision.sh <your-name> --region us-east-1 --auto-approve

# With GPU support
./scripts/lab-provision.sh <your-name> --gpu

# With Metal3 + KubeVirt
./scripts/lab-provision.sh <your-name> --metal3 --kubevirt

# Plan only (no changes)
./scripts/lab-provision.sh <your-name> --plan-only
```

### lab-status.sh
Check environment status.

```bash
./scripts/lab-status.sh <your-name>
./scripts/lab-status.sh <your-name> --json
```

### lab-connect.sh
Connect to lab instances.

```bash
# SSH to management cluster (auto-detects bastion)
./scripts/lab-connect.sh <your-name>

# Show k0rdent UI password
./scripts/lab-connect.sh <your-name> --show-password

# Create tunnel for kubectl
./scripts/lab-connect.sh <your-name> --tunnel 6443:6443

# Copy kubeconfig to local machine
./scripts/lab-connect.sh <your-name> --copy-kubeconfig
```

### lab-destroy.sh
Destroy lab environments.

```bash
./scripts/lab-destroy.sh <your-name> --auto-approve
./scripts/lab-destroy.sh <your-name> --auto-approve --delete-bucket
```

### lab-reap.sh
Find training environments that are still billing after being abandoned. The
`TTLHours` tag is informational only — nothing terminates anything — so the usual
leak is a NAT Gateway left behind by a partial teardown, billing ~$32/month
whether or not any instance is running.

Report-only by default; `--delete` is opt-in.

```bash
./scripts/lab-reap.sh                          # scan all regions, report only
./scripts/lab-reap.sh --region eu-central-1    # scan one region
./scripts/lab-reap.sh --owner <your-name>      # just your environments
./scripts/lab-reap.sh --json                   # machine-readable
```

Environments are reported as `orphaned` (NAT gateway but no instances at all —
structurally stranded, since `lab-destroy.sh` needs a reachable node), `stale`
(instances survive but older than `--max-age-days`, default 7), `active`, or
`idle`. Exits 2 when anything is flagged, so it can drive a cron or CI alert.

## Directory Structure

```
lab-infrastructure/
├── config/
│   ├── lab-config.env         # Local configuration (auto-created)
│   ├── keys/                  # SSH keys (gitignored)
│   └── kubeconfig/            # Kubeconfigs (gitignored)
├── scripts/
│   ├── lab-provision.sh       # Provision student environment
│   ├── lab-status.sh          # Check status
│   ├── lab-connect.sh         # Connect to instances
│   ├── lab-destroy.sh         # Destroy environment
│   └── lab-reap.sh            # Find environments still billing after abandonment
├── terraform/
│   ├── modules/
│   │   ├── networking/        # VPC, subnets, NAT, security groups
│   │   ├── iam/               # IAM roles, policies, instance profiles
│   │   ├── bastion/           # SSH jump host
│   │   ├── k0rdent-mgmt/     # k0rdent management cluster
│   │   ├── gpu-lab/           # GPU environment (optional)
│   │   ├── metal3-dev/        # Metal3 environment (optional)
│   │   └── kubevirt-lab/      # KubeVirt environment (optional)
│   └── environments/
│       └── student-lab/       # Per-student environment (single entry point)
└── docs/
    ├── architecture-design.md
    └── troubleshooting.md
```

## Cost Management

This is the single reference for lab infrastructure costs.

### Environment Costs

| Environment | Instance Type | Spot $/hr | On-Demand $/hr | Weekly Use Case |
|-------------|--------------|-----------|----------------|-----------------|
| Shared Infra | NAT Gateway | ~$0.05 | ~$0.05 | All weeks |
| k0rdent Mgmt | t3.2xlarge (8 vCPU, 32GB) | ~$0.13 | ~$0.33 | Week 1 |
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

### Best Practices

- **Always destroy** environments when not in use
- Check `./scripts/lab-status.sh your-name` regularly
- Use `--plan-only` flag before major changes
- Never leave GPU environments running overnight

## Troubleshooting

For quick diagnostics:

```bash
./scripts/lab-status.sh your-name          # Check your environment
./scripts/lab-status.sh your-name --json   # JSON output for debugging
```

For comprehensive troubleshooting (AWS credentials, SSH issues, Terraform state, GPU problems), see the **[Troubleshooting Guide](docs/troubleshooting.md)**.

## Security Notes

- SSH keys are generated per-environment
- All EBS volumes are encrypted
- S3 buckets use server-side encryption
- IAM roles follow least-privilege principle
- Restrict `ALLOWED_SSH_CIDRS` in production
