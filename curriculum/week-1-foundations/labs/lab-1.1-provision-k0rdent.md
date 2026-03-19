# Lab 1.1: Provision k0rdent Management Cluster

**Duration:** 3 hours (active: ~1.5h, waiting for provisioning: ~1.5h)
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
- Terraform >= 1.8.0 installed
- Your own copy of this training repository (fork or template)
- Basic terminal/shell knowledge

> **Setup Note:** You should have either forked this repository or used "Use this template" on GitHub to create your own copy, then cloned it locally.

## How the Lab Infrastructure Works

Before provisioning, understand the per-student architecture:

```
┌─────────────────────────────────────────────────────────────┐
│           PER-STUDENT INFRASTRUCTURE                         │
│       Each student gets fully isolated resources              │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐          │
│  │  john-doe   │  │  jane-doe   │  │  bob-smith  │   ...    │
│  │  Own VPC    │  │  Own VPC    │  │  Own VPC    │          │
│  │  Own Bastion│  │  Own Bastion│  │  Own Bastion│          │
│  │  Own S3     │  │  Own S3     │  │  Own S3     │          │
│  │  k0rdent    │  │  k0rdent    │  │  k0rdent    │          │
│  └─────────────┘  └─────────────┘  └─────────────┘          │
│                                                              │
│  Each student has completely isolated infrastructure         │
└─────────────────────────────────────────────────────────────┘
```

**Key Points:**
- Each student gets their own VPC, bastion, S3 bucket, and k0rdent cluster
- Each engineer uses a unique ID (e.g., `john-doe`, `jane-doe`)
- Running with different IDs creates **completely isolated** environments
- State is stored in a per-student S3 bucket: `k0rdent-lab-<your-id>-<account-id>`

## Resuming This Lab

If your SSH session dropped or you're returning the next day:

```bash
# Reconnect to your environment (use the same region you provisioned in)
cd lab-infrastructure
./scripts/lab-connect.sh <your-engineer-id>

# Verify the cluster is running
kubectl get nodes
kubectl get pods -n kcm-system
```

---

## Part 1: Configure AWS Credentials

Choose ONE of these methods:

### Option A: AWS CLI Profile (Recommended)

```bash
aws configure
# AWS Access Key ID: <your-access-key>
# AWS Secret Access Key: <your-secret-key>
# Default region name: <your-preferred-region>  (e.g. eu-west-1, us-east-1)
# Default output format: json

# Verify it works
aws sts get-caller-identity
```

### Option B: Environment Variables

```bash
export AWS_ACCESS_KEY_ID="your-key-id"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export AWS_DEFAULT_REGION="<your-preferred-region>"  # e.g. eu-west-1

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

> **AWS SSO Users:** If you use AWS SSO for authentication, see the [Troubleshooting](#troubleshooting) section for required workarounds before running the provisioning script.

## Lab Environment

| Component | Specification |
|-----------|--------------|
| Instance Type | t3.xlarge (4 vCPU, 16GB RAM) |
| OS | Ubuntu 22.04 LTS |
| Kubernetes | k0s v1.32.4 |
| k0rdent | Enterprise v1.2.2 |

## Part 2: Verify Prerequisites

From the root of your cloned training repository:

```bash
cd lab-infrastructure

# Check Terraform version (>= 1.8.0 required)
terraform --version

# Check AWS CLI (v2 required)
aws --version

# Verify AWS credentials (should show your account)
aws sts get-caller-identity
```

## Part 3: Provision the k0rdent Management Cluster

The provisioning script automates the entire setup process including:
- Creating a per-student S3 bucket for Terraform state
- Provisioning VPC, bastion host, and IAM resources
- Deploying the k0rdent management cluster
- Installing k0s and k0rdent Enterprise

Run the provisioning command:

```bash
./scripts/lab-provision.sh <your-engineer-id> --region <your-region> --auto-approve
```

Replace `<your-engineer-id>` with your unique identifier (e.g., `engineer-01`, `john-doe`) and `<your-region>` with the AWS region you chose (e.g., `us-east-1`, `eu-west-1`).

> **Example:** `./scripts/lab-provision.sh john-doe --region us-east-1 --auto-approve`

### Understanding the Output

The script will display progress as it:
1. Creates per-student S3 bucket for Terraform state
2. Provisions VPC, subnets, bastion host
3. Deploys the management cluster EC2 instance
4. Waits for the instance to be ready

**Expected Duration:** 10-15 minutes

## Part 4: Connect to the Management Cluster

Once provisioning completes, connect to your management cluster:

```bash
./scripts/lab-connect.sh <your-engineer-id>
```

This establishes an SSH connection through the bastion host.

### Verify k0rdent Installation

Once connected, wait for the installation to complete:

```bash
# Wait for k0rdent installation to finish (10-15 minutes after instance launch)
echo "Waiting for k0rdent installation to complete..."
while [ ! -f /opt/k0rdent-lab/.init-complete ]; do sleep 10; echo -n "."; done
echo " Done!"
```

If you want to watch the installation progress in real time instead:

```bash
# Watch the installation log (Ctrl+C to stop watching)
tail -f /var/log/k0rdent-init.log
```

> **Important:** Do not proceed to the next steps until installation is complete. The k0rdent pods and CRDs will not be available until the init script finishes.

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

The provisioning script waits for k0rdent and Envoy Gateway to be fully operational before printing the UI URL.

**How the UI is exposed:**

```
Browser (HTTP) → AWS NLB (auto-provisioned) → Envoy Gateway → HTTPRoute → k0rdent UI (:3000)
```

Envoy Gateway uses the Kubernetes Gateway API to route traffic. AWS Cloud Controller Manager automatically provisions a Network Load Balancer for the Gateway's Service.

**The URL is printed at the end of provisioning:**

```
============================================
  k0rdent UI
  URL:       http://xxxxx.elb.us-east-1.amazonaws.com
  Username:  admin
  Password:  <generated>
============================================
```

**To retrieve the URL later:**

```bash
# Get UI URL and credentials
./scripts/lab-connect.sh <your-name> --ui-url

# View Gateway API resource status
./scripts/lab-connect.sh <your-name> --show-gateway
```

**From inside the cluster (via SSH):**

```bash
# Get the Gateway LB address
kubectl get gateway k0rdent-gateway -n kcm-system

# View all Gateway API resources
kubectl get gatewayclass,gateway,httproute -A
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
./scripts/lab-status.sh your-name
```

**Error: Terraform version too old**

```bash
# Install newer Terraform
# macOS:
brew tap hashicorp/tap
brew install hashicorp/tap/terraform
```

**Error: AWS SSO profile not working with Terraform**

If you use AWS SSO and see an error like:
```
Error: profile "xxx" is configured to use SSO but is missing required configuration: sso_region, sso_start_url
```

This happens because Terraform's S3 backend doesn't fully support AWS SSO profiles. Use this workaround:

```bash
# First, ensure you're logged in to SSO
aws sso login --profile your-profile-name

# Export SSO credentials as environment variables
eval "$(aws configure export-credentials --format env --profile your-profile-name)"

# Now run the provisioning script (credentials are in environment)
./scripts/lab-provision.sh <your-engineer-id> --region <your-region> --auto-approve
```

> **Note:** The exported credentials are temporary session tokens. If your session expires, run the `aws sso login` and `eval` commands again.

### k0rdent Installation Issues

**Pods not starting:**
```bash
# Check pod events
kubectl describe pod <pod-name> -n kcm-system

# Check logs
kubectl logs <pod-name> -n kcm-system
```

**Installation still running:**
```bash
# Check k0rdent installation progress (on the lab instance)
tail -f /var/log/k0rdent-init.log

# Check if installation complete
ls /opt/k0rdent-lab/.init-complete && echo "Done!"
```

**Common issues:**
- **AWS credentials:** Re-run `aws configure` or check `aws sts get-caller-identity`
- **Terraform errors:** Check version with `terraform --version` (needs >= 1.8.0)
- **SSH connection:** Ensure correct key permissions (`chmod 600 config/keys/*.pem`)
- **Pods not starting:** Check with `kubectl describe pod <name> -n kcm-system`

For comprehensive troubleshooting, see the [Troubleshooting Guide](../../../lab-infrastructure/docs/troubleshooting.md).

## Clean Up

When finished with the lab, you can destroy the environment:

```bash
./scripts/lab-destroy.sh <your-engineer-id> --auto-approve
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
