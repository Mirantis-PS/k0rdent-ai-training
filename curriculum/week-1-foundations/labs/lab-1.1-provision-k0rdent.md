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

- AWS CLI v2 installed
- Terraform >= 1.5.0 installed
- Your own copy of this training repository (fork or template)
- Basic terminal/shell knowledge

> **Setup Note:** You should have either forked this repository or used "Use this template" on GitHub to create your own copy, then cloned it locally.

## How the Lab Infrastructure Works

Before provisioning, understand the multi-tenant architecture:

```
┌─────────────────────────────────────────────────────────────┐
│           SHARED INFRASTRUCTURE (auto-created)               │
│         VPC, Bastion, S3 Buckets, IAM Roles                 │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐         │
│  │  john-doe   │  │  jane-doe   │  │  bob-smith  │   ...   │
│  │   k0rdent   │  │   k0rdent   │  │   k0rdent   │         │
│  │ 10.0.8.x    │  │ 10.0.8.y    │  │ 10.0.8.z    │         │
│  └─────────────┘  └─────────────┘  └─────────────┘         │
│                                                             │
│  Each engineer has isolated state and resources             │
└─────────────────────────────────────────────────────────────┘
```

**Key Points:**
- Shared infrastructure is created **automatically** on first run
- Each engineer uses a unique ID (e.g., `john-doe`, `jane-doe`)
- Running with different IDs creates **completely isolated** environments
- State files are stored separately: `k0rdent/<your-id>/terraform.tfstate`

## Part 1: Configure AWS Credentials

Choose ONE of these methods:

### Option A: AWS CLI Profile (Recommended)

```bash
aws configure
# AWS Access Key ID: <your-access-key>
# AWS Secret Access Key: <your-secret-key>
# Default region name: us-east-1  (or your preferred region)
# Default output format: json

# Verify it works
aws sts get-caller-identity
```

### Option B: Environment Variables

```bash
export AWS_ACCESS_KEY_ID="your-key-id"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export AWS_DEFAULT_REGION="us-east-1"

# Verify
aws sts get-caller-identity
```

### Option C: AWS SSO

```bash
aws sso login --profile your-sso-profile
export AWS_PROFILE=your-sso-profile

# Verify
aws sts get-caller-identity
```

### Region Selection

Choose a region with good availability. Common choices:

| Region | Location | Notes |
|--------|----------|-------|
| `us-east-1` | N. Virginia | Good GPU availability |
| `us-west-2` | Oregon | Good GPU availability |
| `eu-west-1` | Ireland | European option |

> **Note:** For GPU labs (Weeks 4-5), check [AWS GPU instance availability](https://aws.amazon.com/ec2/instance-types/p3/) in your region.

## Lab Environment

| Component | Specification |
|-----------|--------------|
| Instance Type | t3.xlarge (4 vCPU, 16GB RAM) |
| OS | Ubuntu 22.04 LTS |
| Kubernetes | k0s v1.32.4 |
| k0rdent | Enterprise v1.2.1 |

## Part 2: Verify Prerequisites

From the root of your cloned training repository:

```bash
cd lab-infrastructure

# Check Terraform version (>= 1.5.0 required)
terraform --version

# Check AWS CLI (v2 required)
aws --version

# Verify AWS credentials (should show your account)
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
./scripts/lab-provision.sh k0rdent <your-engineer-id> --auto-approve
```

Replace `<your-engineer-id>` with your unique identifier (e.g., `engineer-01`, `john-doe`).

> **Example:** `./scripts/lab-provision.sh k0rdent john-doe --auto-approve`

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
# Check k0rdent installation log (live progress)
tail -f /var/log/k0rdent-init.log

# Or check if installation is complete
ls /opt/k0rdent-lab/.init-complete && echo "Installation complete!"
```

The installation runs in the background and may take 10-15 minutes after the instance is available.

> **Tip:** The lab environment includes helpful aliases. Type `alias` to see them all.

## Part 5: Verify k0s Cluster

Check that the k0s cluster is running:

```bash
# Check k0s status
sudo k0s status

# Get cluster nodes (using alias: kgn)
kubectl get nodes

# Check system pods (using alias: kgaa)
kubectl get pods -A
```

**Expected output:**
```
NAME                   STATUS   ROLES           AGE   VERSION
ip-10-0-xxx-xxx        Ready    control-plane   10m   v1.32.4+k0s
```

## Part 6: Verify k0rdent Enterprise Installation

Check k0rdent components:

```bash
# Check k0rdent namespace (using alias: kgp -n kcm-system)
kubectl get pods -n kcm-system
```

**Expected output:**
```
NAME                                      READY   STATUS    RESTARTS   AGE
kcm-controller-manager-xxx                1/1     Running   0          5m
kcm-cert-manager-xxx                      1/1     Running   0          5m
k0rdent-ui-xxx                            1/1     Running   0          5m
```

```bash
# Check k0rdent CRDs (they use k0rdent.mirantis.com domain)
kubectl get crds | grep k0rdent.mirantis.com

# Check available cluster templates (using alias: kgct)
kubectl get clustertemplates -A

# Check credentials (using alias: kgcred)
kubectl get credentials -A
```

**Expected CRDs include:**
- `managements.k0rdent.mirantis.com`
- `clusterdeployments.k0rdent.mirantis.com`
- `clustertemplates.k0rdent.mirantis.com`
- `credentials.k0rdent.mirantis.com`

## Part 7: Access the k0rdent UI

The k0rdent UI is accessible via port-forwarding.

**Option A: Two-terminal approach**

Terminal 1 (SSH to management cluster):
```bash
./scripts/lab-connect.sh k0rdent <your-engineer-id>
# Then start port-forward:
kubectl port-forward svc/kcm-k0rdent-ui -n kcm-system 8080:3000 --address 0.0.0.0
```

Terminal 2 (local machine - create tunnel):
```bash
./scripts/lab-connect.sh k0rdent <your-engineer-id> --tunnel 8080:8080
```

**Option B: Single command with background port-forward**

From your SSH session on the management cluster:
```bash
kubectl port-forward svc/kcm-k0rdent-ui -n kcm-system 8080:3000 --address 0.0.0.0 &
```

Then open a new local terminal:
```bash
./scripts/lab-connect.sh k0rdent <your-engineer-id> --tunnel 8080:8080
```

**Access the UI:**

Open your browser to: `http://localhost:8080`

**Credentials:**
- **Username:** `admin`
- **Password:** From your local machine, run:
  ```bash
  cd lab-infrastructure/terraform/environments/k0rdent && terraform output -raw ui_password
  ```

## Part 8: Explore k0rdent Resources

Using kubectl (or the pre-configured aliases), explore the k0rdent resources:

```bash
# List management objects (using alias: kgm)
kubectl get management -A

# List available cluster templates (using alias: kgct)
kubectl get clustertemplates -A

# List cluster deployments (using alias: kgcd)
kubectl get clusterdeployments -A

# List configured credentials (using alias: kgcred)
kubectl get credentials -A

# View the Management object configuration
kubectl get management -n kcm-system -o yaml
```

**Understanding the Output:**

- **Management**: The core k0rdent configuration object
- **ClusterTemplates**: Pre-defined cluster configurations (AWS, Azure, vSphere, etc.)
- **ClusterDeployments**: Actual deployed clusters (none yet - you'll create these in later labs)
- **Credentials**: Cloud provider credentials for provisioning

## Validation Checklist

Before completing this lab, verify:

- [ ] Provisioning script completed successfully
- [ ] SSH connection to management cluster works
- [ ] k0s cluster shows node as Ready
- [ ] All pods in kcm-system namespace are Running
- [ ] k0rdent CRDs are installed
- [ ] k0rdent UI is accessible (optional)

## Troubleshooting

For quick diagnostics:

```bash
# Check environment status
./scripts/lab-status.sh k0rdent your-name

# Check k0rdent installation progress (on the lab instance)
tail -f /var/log/k0rdent-init.log

# Check if installation complete
ls /opt/k0rdent-lab/.init-complete && echo "Done!"
```

**Common issues:**
- **AWS credentials:** Re-run `aws configure` or check `aws sts get-caller-identity`
- **Terraform errors:** Check version with `terraform --version` (needs >= 1.5.0)
- **SSH connection:** Ensure correct key permissions (`chmod 600 config/keys/*.pem`)
- **Pods not starting:** Check with `kubectl describe pod <name> -n kcm-system`

For comprehensive troubleshooting, see the [Troubleshooting Guide](../../../lab-infrastructure/docs/troubleshooting.md).

## Clean Up

When finished with the lab, you can destroy the environment:

```bash
./scripts/lab-destroy.sh k0rdent <your-engineer-id> --auto-approve
```

> **Important:** Only destroy if you're done with **all Week 1 labs**, as subsequent labs build on this environment.

## Summary

In this lab, you:
- Provisioned a k0rdent Enterprise management cluster using automated scripts
- Connected to the cluster via SSH through a bastion host
- Verified k0s and k0rdent Enterprise installation
- Explored the k0rdent UI and Kubernetes resources

## Quick Reference: Aliases

Your lab environment includes these helpful aliases:

| Alias | Command | Description |
|-------|---------|-------------|
| `k` | `kubectl` | Short kubectl |
| `kgp` | `kubectl get pods` | List pods |
| `kgn` | `kubectl get nodes` | List nodes |
| `kgaa` | `kubectl get all -A` | All resources, all namespaces |
| `kgm` | `kubectl get management -A` | k0rdent management objects |
| `kgcd` | `kubectl get clusterdeployment -A` | Cluster deployments |
| `kgct` | `kubectl get clustertemplates -A` | Cluster templates |
| `kgcred` | `kubectl get credentials -A` | Credentials |

## Next Lab

Continue to [Lab 1.2: Explore k0rdent UI](lab-1.2-explore-k0rdent-ui.md)
