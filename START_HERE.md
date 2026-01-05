# Start Here

Welcome to the k0rdent AI Infrastructure Training! Follow these 3 steps to get started.

---

## Step 1: Prerequisites

Make sure you have these tools installed:

```bash
# Terraform (>= 1.5.0)
terraform version

# AWS CLI (v2)
aws --version
```

**Don't have them?**
- Terraform: https://developer.hashicorp.com/terraform/install
- AWS CLI: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html

---

## Step 2: Configure AWS

```bash
aws configure
```

Enter your AWS credentials when prompted:
- AWS Access Key ID
- AWS Secret Access Key
- Default region (e.g., `us-east-1`)
- Output format: `json`

**Verify it works:**
```bash
aws sts get-caller-identity
```

---

## Step 3: Launch Your Lab

```bash
cd lab-infrastructure

# Replace 'your-name' with your name (e.g., john-doe)
./scripts/lab-provision.sh metal3 your-name --auto-approve
```

This command automatically:
1. Creates S3 bucket for Terraform state
2. Creates shared infrastructure (VPC, bastion host)
3. Creates your personal Metal3 lab environment
4. Saves SSH keys to `config/keys/`

**Wait 5-10 minutes** for the infrastructure to be ready.

---

## Connect to Your Lab

```bash
./scripts/lab-connect.sh metal3 your-name
```

You're now connected! Start with [Week 1](curriculum/week-1-foundations/).

---

## When You're Done

Always destroy your lab to avoid costs:

```bash
./scripts/lab-destroy.sh metal3 your-name --auto-approve
```

---

## Quick Reference

| Action | Command |
|--------|---------|
| Provision lab | `./scripts/lab-provision.sh metal3 your-name --auto-approve` |
| Connect | `./scripts/lab-connect.sh metal3 your-name` |
| Check status | `./scripts/lab-status.sh metal3 your-name` |
| Destroy | `./scripts/lab-destroy.sh metal3 your-name --auto-approve` |

---

## Lab Types by Week

| Week | Lab Type | Command |
|------|----------|---------|
| 1-2 | Metal3 (BMaaS) | `./scripts/lab-provision.sh metal3 your-name` |
| 3 | KubeVirt (VMaaS) | `./scripts/lab-provision.sh kubevirt your-name` |
| 4-5 | GPU Lab | `./scripts/lab-provision.sh gpu session-name` |

---

## Need Help?

- [Full Provisioning Guide](curriculum/lab-environment/provisioning-guide.md)
- [Training Curriculum](curriculum/k0rdent-ai-infrastructure-training-curriculum.md)
- Slack: #k0rdent-training
