# k0rdent AI Infrastructure Training

A comprehensive 6-week training program for engineers to master k0rdent implementation, enabling them to build AI infrastructure products: BMaaS, VMaaS, KaaS, and MaaS.

## Quick Start

```bash
# 1. Clone the repository
git clone git@github.com:mgueye01/k0rdent-ai-training.git
cd k0rdent-ai-training

# 2. Set up your lab environment (one-time admin setup)
cd lab-infrastructure
./scripts/lab-provision.sh shared --auto-approve

# 3. Provision your personal lab (use your unique ID)
./scripts/lab-provision.sh metal3 your-name --auto-approve

# 4. Connect to your lab
./scripts/lab-connect.sh metal3 your-name

# 5. Start with Week 1
# Open: curriculum/week-1-foundations/
```

## Repository Structure

```
k0rdent-ai-training/
├── README.md                    # You are here
├── curriculum/                  # Training content
│   ├── overview/               # Program introduction
│   ├── week-1-foundations/     # k0rdent, GPU hardware, BMC
│   ├── week-2-bmaas/          # Metal3, Ironic, bare metal provisioning
│   ├── week-3-vmaas/          # KubeVirt, GPU passthrough
│   ├── week-4-kaas/           # Cluster API, GPU operator
│   ├── week-5-ai-workloads/   # vLLM, Run:AI, service catalog
│   ├── week-6-multitenancy/   # RBAC, tenancy, capstone project
│   ├── lab-environment/       # Lab provisioning guide
│   └── appendix/              # Reference materials
└── lab-infrastructure/         # Terraform + scripts for labs
    ├── scripts/               # Provisioning scripts
    ├── terraform/             # Infrastructure as Code
    │   ├── environments/      # Deployment configurations
    │   └── modules/           # Reusable Terraform modules
    └── config/                # Local configuration (gitignored)
```

## Training Flow

### Phase 1: Setup (Day 1)

| Step | Action | Guide |
|------|--------|-------|
| 1 | Install prerequisites (Terraform, AWS CLI) | [Lab Guide](curriculum/lab-environment/provisioning-guide.md) |
| 2 | Configure AWS credentials | [Lab Guide](curriculum/lab-environment/provisioning-guide.md#aws-credentials-setup) |
| 3 | Deploy shared infrastructure (admin) | `./scripts/lab-provision.sh shared` |
| 4 | Provision your personal lab | `./scripts/lab-provision.sh metal3 <your-id>` |

### Phase 2: Weekly Curriculum (Weeks 1-6)

```
Week 1: Foundations          Week 2: BMaaS              Week 3: VMaaS
┌────────────────────┐      ┌────────────────────┐      ┌────────────────────┐
│ • k0rdent arch     │      │ • Metal3 operator  │      │ • KubeVirt basics  │
│ • GPU hardware     │  ──▶ │ • Ironic setup     │  ──▶ │ • GPU passthrough  │
│ • BMC/Redfish      │      │ • BM provisioning  │      │ • NVLink topology  │
│ • Lab: 10.5 hrs    │      │ • Lab: 10.5 hrs    │      │ • Lab: 10.5 hrs    │
└────────────────────┘      └────────────────────┘      └────────────────────┘
         │                           │                           │
         ▼                           ▼                           ▼
Week 4: KaaS                 Week 5: AI Workloads       Week 6: Capstone
┌────────────────────┐      ┌────────────────────┐      ┌────────────────────┐
│ • Cluster API      │      │ • vLLM inference   │      │ • Multi-tenancy    │
│ • GPU operator     │  ──▶ │ • Run:AI           │  ──▶ │ • RBAC & policies  │
│ • CNI/CSI          │      │ • Service catalog  │      │ • Final project    │
│ • Lab: 10.5 hrs    │      │ • Lab: 10.5 hrs    │      │ • Lab: 10.5 hrs    │
└────────────────────┘      └────────────────────┘      └────────────────────┘
```

### Phase 3: Cleanup

```bash
# Destroy your personal lab when done
./scripts/lab-destroy.sh metal3 <your-id> --auto-approve
```

## For Engineers

### Starting Your Lab

```bash
cd lab-infrastructure

# Provision (creates isolated environment with your ID)
./scripts/lab-provision.sh metal3 john-doe --auto-approve

# Connect via SSH
./scripts/lab-connect.sh metal3 john-doe

# Check status
./scripts/lab-status.sh metal3 john-doe

# Destroy when done
./scripts/lab-destroy.sh metal3 john-doe --auto-approve
```

### Each Week

1. **Read theory** → `curriculum/week-X-*/theory/`
2. **Do labs** → `curriculum/week-X-*/labs/`
3. **Check resources** → `curriculum/week-X-*/resources/`

### Lab Types by Week

| Week | Lab Environment | Command |
|------|----------------|---------|
| 1-2 | Metal3 Dev | `./scripts/lab-provision.sh metal3 <id>` |
| 3 | KubeVirt | `./scripts/lab-provision.sh kubevirt <id>` |
| 4-5 | GPU Lab | `./scripts/lab-provision.sh gpu <session-id>` |
| 6 | Full Stack | Multi-node cluster |

## For Admins

### Initial Deployment

```bash
cd lab-infrastructure/terraform/environments/shared

# Create config from template
cp terraform.tfvars.example terraform.tfvars

# Edit with your IP: vim terraform.tfvars

# Deploy shared infrastructure
cd ../../..
./scripts/lab-provision.sh shared --auto-approve

# Save bastion key
cd terraform/environments/shared
terraform output -raw bastion_ssh_private_key > ../../config/keys/bastion.pem
chmod 600 ../../config/keys/bastion.pem
```

### Multi-Tenant Architecture

Each engineer gets isolated infrastructure:

```
Shared Infrastructure (deployed once)
├── VPC: 10.0.0.0/16
├── Bastion Host (SSH jump)
├── S3 Buckets (state, artifacts, images)
└── IAM Roles

Per-Engineer Environments
├── metal3-dev/engineer-01/  → State: s3://.../metal3-dev/engineer-01/terraform.tfstate
├── metal3-dev/engineer-02/  → State: s3://.../metal3-dev/engineer-02/terraform.tfstate
├── kubevirt-lab/engineer-03/ → State: s3://.../kubevirt-lab/engineer-03/terraform.tfstate
└── ...
```

## Prerequisites

- **Terraform** >= 1.5.0
- **AWS CLI** v2
- **AWS credentials** configured
- **SSH client**

```bash
# 1. Verify tools are installed
terraform version    # >= 1.5.0
aws --version        # v2.x

# 2. Configure AWS credentials
aws configure
# Enter: Access Key ID, Secret Key
# Region: Choose your preferred region (e.g., eu-west-1, us-east-1, us-west-2)
# Output format: json

# 3. Verify credentials
aws sts get-caller-identity  # Should show your account
```

> **Note:** Choose a region with GPU instance availability if you plan to run GPU labs. Update `region` and `gpu_az` in `terraform.tfvars` to match your chosen region.

## Key Documents

| Document | Location | Purpose |
|----------|----------|---------|
| Full Curriculum | [curriculum/k0rdent-ai-infrastructure-training-curriculum.md](curriculum/k0rdent-ai-infrastructure-training-curriculum.md) | Complete training syllabus |
| Lab Provisioning | [curriculum/lab-environment/provisioning-guide.md](curriculum/lab-environment/provisioning-guide.md) | Detailed lab setup |
| Week 1 Start | [curriculum/week-1-foundations/](curriculum/week-1-foundations/) | First week content |

## Cost Awareness

| Resource | Cost (Spot) | Cost (On-Demand) |
|----------|-------------|------------------|
| Shared Infra (NAT) | ~$35/month | ~$35/month |
| Metal3 Lab (t3.medium) | ~$0.02/hr | ~$0.04/hr |
| Metal3 Lab (m5.2xlarge) | ~$0.15/hr | ~$0.38/hr |
| GPU Lab (p3.8xlarge) | ~$4.50/hr | ~$12.24/hr |

**Always destroy labs when not in use!**

## Support

- **Slack:** #k0rdent-training
- **Issues:** Create GitHub issue
- **Instructor:** During scheduled sessions

---

**Version:** 1.0 | **Last Updated:** December 2025
