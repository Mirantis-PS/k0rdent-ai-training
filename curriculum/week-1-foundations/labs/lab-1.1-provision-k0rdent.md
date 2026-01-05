# Lab 1.1: Provision k0rdent Management Cluster

**Duration:** 3 hours
**Type:** Hands-on Lab

## Objectives

In this lab, you will:
- Provision a k0rdent Enterprise management cluster on AWS
- Understand the automated provisioning workflow
- Connect to the management cluster via SSH
- Verify k0rdent Enterprise installation
- Access the k0rdent UI

## Prerequisites

- AWS CLI configured with valid credentials
- Terraform >= 1.5.0 installed
- Git access to the training repository
- Basic terminal/shell knowledge

## Lab Environment

| Component | Specification |
|-----------|--------------|
| Instance Type | t3.xlarge (4 vCPU, 16GB RAM) |
| OS | Ubuntu 22.04 LTS |
| Kubernetes | k0s v1.32.4 |
| k0rdent | Enterprise v1.2.1 |

## Part 1: Clone the Training Repository

If you haven't already, clone the training repository:

```bash
git clone https://github.com/your-org/k0rdent-ai-training.git
cd k0rdent-ai-training/lab-infrastructure
```

## Part 2: Verify Prerequisites

Check that required tools are installed:

```bash
# Check Terraform version
terraform --version
# Should be >= 1.5.0

# Check AWS CLI
aws --version

# Verify AWS credentials
aws sts get-caller-identity
```

## Part 3: Provision the k0rdent Management Cluster

The provisioning script automates the entire setup process including:
- Creating S3 bucket for Terraform state
- Provisioning shared VPC infrastructure and bastion host
- Deploying the k0rdent management cluster
- Installing k0s and k0rdent Enterprise

Run the provisioning command:

```bash
./scripts/lab-provision.sh k0rdent <your-engineer-id>
```

Replace `<your-engineer-id>` with your unique identifier (e.g., `engineer-01`, `john-doe`).

### Understanding the Output

The script will display progress as it:
1. Creates S3 bucket for Terraform state
2. Provisions shared infrastructure (VPC, subnets, bastion)
3. Deploys the management cluster EC2 instance
4. Waits for the instance to be ready

**Expected Duration:** 10-15 minutes

## Part 4: Connect to the Management Cluster

Once provisioning completes, connect to your management cluster:

```bash
./scripts/lab-connect.sh k0rdent <your-engineer-id>
```

This establishes an SSH connection through the bastion host.

### Verify k0rdent Installation

Once connected, check the installation status:

```bash
# Check k0rdent installation log
tail -f /var/log/k0rdent-setup.log

# Or check the summary
cat /var/log/k0rdent-setup-complete
```

The installation runs in the background and may take 10-15 minutes after the instance is available.

## Part 5: Verify k0s Cluster

Check that the k0s cluster is running:

```bash
# Check k0s status
sudo k0s status

# Get cluster nodes
sudo k0s kubectl get nodes

# Check system pods
sudo k0s kubectl get pods -A
```

Expected output should show the node as Ready and system pods running.

## Part 6: Verify k0rdent Enterprise Installation

Check k0rdent components:

```bash
# Check k0rdent namespace
sudo k0s kubectl get pods -n kcm-system

# Expected pods:
# - kcm-controller-manager
# - kcm-cert-manager
# - k0rdent-ui (if enabled)

# Check k0rdent CRDs
sudo k0s kubectl get crds | grep k0rdent

# Check provider templates
sudo k0s kubectl get clustertemplate -A
sudo k0s kubectl get servicetemplate -A
```

## Part 7: Access the k0rdent UI

The k0rdent UI is accessible via port-forwarding. From your management cluster SSH session:

```bash
# Start port-forward in background
sudo k0s kubectl port-forward svc/k0rdent-ui -n kcm-system 8080:80 --address 0.0.0.0 &
```

Then, from your local machine, create an SSH tunnel:

```bash
./scripts/lab-connect.sh k0rdent <your-engineer-id> --tunnel 8080:8080
```

Open your browser to: `http://localhost:8080`

**Default credentials:**
- Username: admin
- Password: k0rdent-lab-2024

## Part 8: Explore k0rdent Resources

Using kubectl, explore the k0rdent resources:

```bash
# List management clusters
sudo k0s kubectl get management -A

# List available templates
sudo k0s kubectl get clustertemplate -A
sudo k0s kubectl get servicetemplate -A

# View k0rdent configuration
sudo k0s kubectl get management kcm -n kcm-system -o yaml
```

## Validation Checklist

Before completing this lab, verify:

- [ ] Provisioning script completed successfully
- [ ] SSH connection to management cluster works
- [ ] k0s cluster shows node as Ready
- [ ] All pods in kcm-system namespace are Running
- [ ] k0rdent CRDs are installed
- [ ] k0rdent UI is accessible (optional)

## Troubleshooting

### Provisioning Issues

**Error: AWS credentials not found**
```bash
# Configure AWS CLI
aws configure
# Or export credentials
export AWS_ACCESS_KEY_ID=<your-key>
export AWS_SECRET_ACCESS_KEY=<your-secret>
export AWS_REGION=us-east-1
```

**Error: Terraform version too old**
```bash
# Install newer Terraform
# macOS:
brew tap hashicorp/tap
brew install hashicorp/tap/terraform
```

### k0rdent Installation Issues

**Pods not starting:**
```bash
# Check pod events
sudo k0s kubectl describe pod <pod-name> -n kcm-system

# Check logs
sudo k0s kubectl logs <pod-name> -n kcm-system
```

**Installation still running:**
```bash
# Check progress
tail -f /var/log/k0rdent-setup.log

# Installation typically takes 10-15 minutes
```

## Clean Up

When finished with the lab, you can destroy the environment:

```bash
./scripts/lab-destroy.sh k0rdent <your-engineer-id>
```

**Note:** Only destroy if you're done with all Week 1 labs, as subsequent labs build on this environment.

## Summary

In this lab, you:
- Provisioned a k0rdent Enterprise management cluster using automated scripts
- Connected to the cluster via SSH through a bastion host
- Verified k0s and k0rdent Enterprise installation
- Explored the k0rdent UI and Kubernetes resources

## Next Lab

Continue to [Lab 1.2: Explore k0rdent UI](lab-1.2-explore-k0rdent-ui.md)
