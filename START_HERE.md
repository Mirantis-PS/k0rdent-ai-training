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
- Default region (e.g., `us-east-1`, `eu-west-1`)
- Output format: `json`

**Verify it works:**
```bash
aws sts get-caller-identity
```

---

## Step 3: Launch Your k0rdent Management Cluster

```bash
cd lab-infrastructure

# Replace 'your-name' with your name (e.g., john-doe)
./scripts/lab-provision.sh k0rdent your-name --auto-approve
```

This command automatically:
1. Creates S3 bucket for Terraform state
2. Creates shared infrastructure (VPC, bastion host)
3. Creates your k0rdent management cluster with:
   - k0s Kubernetes (v1.32.4)
   - k0rdent Enterprise (v1.2.1)
   - k0rdent UI
4. Saves SSH keys to `config/keys/`

**Wait 15-20 minutes** for k0rdent to fully initialize.

---

## Connect to Your Lab

```bash
./scripts/lab-connect.sh k0rdent your-name
```

Once connected, check k0rdent status:
```bash
# View installation progress
tail -f /var/log/k0rdent-init.log

# Check pods
kubectl get pods -n kcm-system
```

You're now connected! Start with [Week 1 Labs](curriculum/week-1-foundations/).

---

## Access k0rdent UI

From your management cluster SSH session:
```bash
kubectl port-forward svc/k0rdent-ui -n kcm-system 8080:80 --address 0.0.0.0 &
```

From your local machine:
```bash
./scripts/lab-connect.sh k0rdent your-name --tunnel 8080:8080
```

Open browser: `http://localhost:8080`
- Username: admin
- Password: Run `terraform output -raw ui_password` in the k0rdent environment directory

---

## When You're Done

Always destroy your lab to avoid costs:

```bash
./scripts/lab-destroy.sh k0rdent your-name --auto-approve
```

---

## Quick Reference

| Action | Command |
|--------|---------|
| Provision k0rdent | `./scripts/lab-provision.sh k0rdent your-name --auto-approve` |
| Connect | `./scripts/lab-connect.sh k0rdent your-name` |
| Check status | `./scripts/lab-status.sh all your-name` |
| Destroy | `./scripts/lab-destroy.sh k0rdent your-name --auto-approve` |

---

## Lab Types by Week

| Week | Lab Type | Command |
|------|----------|---------|
| 1 | k0rdent Enterprise | `./scripts/lab-provision.sh k0rdent your-name` |
| 2 | Metal3 (BMaaS) | `./scripts/lab-provision.sh metal3 your-name` |
| 3 | KubeVirt (VMaaS) | `./scripts/lab-provision.sh kubevirt your-name` |
| 4-5 | GPU Lab | `./scripts/lab-provision.sh gpu session-name` |

---

## Need Help?

- [Full Provisioning Guide](curriculum/lab-environment/provisioning-guide.md)
- [Training Curriculum](curriculum/k0rdent-ai-infrastructure-training-curriculum.md)
- [k0rdent Documentation](https://docs.mirantis.com/k0rdent-enterprise/latest/)
- Slack: #k0rdent-training
