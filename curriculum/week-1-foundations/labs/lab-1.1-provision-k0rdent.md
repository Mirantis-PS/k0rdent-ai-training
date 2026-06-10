# Lab 1.1: Provision k0rdent Management Cluster

**Duration:** ~1.5 hours (active: ~1h; unattended provisioning wait: ~15-20 min)
**Type:** Hands-on Lab

## Table of Contents

- [Objectives](#objectives)
- [Prerequisites](#prerequisites)
- [How the Lab Infrastructure Works](#how-the-lab-infrastructure-works)
- [Resuming This Lab](#resuming-this-lab)
- [Part 1: Configure AWS Credentials (~5 min)](#part-1-configure-aws-credentials-5-min)
  - [Option A: AWS CLI Profile (Recommended)](#option-a-aws-cli-profile-recommended)
  - [Option B: Environment Variables](#option-b-environment-variables)
  - [Option C: AWS SSO](#option-c-aws-sso)
  - [Region Selection](#region-selection)
- [Lab Environment](#lab-environment)
- [Part 2: Verify Prerequisites (~2 min)](#part-2-verify-prerequisites-2-min)
- [Part 3: Provision the k0rdent Management Cluster (~20 min)](#part-3-provision-the-k0rdent-management-cluster-20-min)
  - [Understanding the Output](#understanding-the-output)
  - [Under the Hood: What the Script Actually Runs](#under-the-hood-what-the-script-actually-runs)
- [Part 4: Connect to the Management Cluster (~2 min)](#part-4-connect-to-the-management-cluster-2-min)
  - [Verify k0rdent Installation](#verify-k0rdent-installation)
- [Part 5: Verify k0s Cluster (~2 min)](#part-5-verify-k0s-cluster-2-min)
- [Part 6: Verify k0rdent Enterprise Installation (~5 min)](#part-6-verify-k0rdent-enterprise-installation-5-min)
- [Part 7: Access the k0rdent UI (~10 min)](#part-7-access-the-k0rdent-ui-10-min)
  - [Hands-On: Trace the Chain That Gave the UI Its URL](#hands-on-trace-the-chain-that-gave-the-ui-its-url)
- [Part 8: Explore k0rdent Resources (~5 min)](#part-8-explore-k0rdent-resources-5-min)
  - [Explore Other Namespaces](#explore-other-namespaces)
- [Validation Checklist](#validation-checklist)
- [Troubleshooting](#troubleshooting)
  - [k0rdent Installation Issues](#k0rdent-installation-issues)
- [Clean Up](#clean-up)
- [Summary](#summary)
- [Quick Reference: Aliases](#quick-reference-aliases)
- [Next Lab](#next-lab)

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
- `jq` installed (the lab scripts use it to parse AWS CLI output)
- Your own copy of this training repository (fork or template)
- Basic terminal/shell knowledge
- **Supported OS:** macOS or Linux. Windows is supported via **WSL2 only** — all lab scripts are bash and do not run in PowerShell or Git Bash.

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

## Part 1: Configure AWS Credentials (~5 min)

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

## Part 2: Verify Prerequisites (~2 min)

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

## Part 3: Provision the k0rdent Management Cluster (~20 min)

The provisioning script automates the entire setup process including:
- Creating a per-student S3 bucket for Terraform state
- Provisioning VPC, bastion host, and IAM resources
- Deploying the k0rdent management cluster
- Installing k0s and k0rdent Enterprise

> **SSO users — log in fresh first:** The apply plus cloud-init takes 15-20+ minutes, so don't rely on credentials cached earlier in the session. Run `aws sso login` (and re-run the `eval "$(aws configure export-credentials ...)"` workaround if you use it — see [Troubleshooting](#troubleshooting)) **immediately before** the provisioning command. If your token expires mid-apply, Terraform aborts with `ExpiredToken` and leaves partially created resources recorded in state — that's recoverable: log in again and re-run the same command. Terraform is idempotent and resumes from the saved state.

Run the provisioning command:

```bash
./scripts/lab-provision.sh <your-engineer-id> --region <your-region> --auto-approve
```

Replace `<your-engineer-id>` with your unique identifier (e.g., `engineer-01`, `john-doe`) and `<your-region>` with the AWS region you chose (e.g., `us-east-1`, `eu-west-1`).

> **Example:** `./scripts/lab-provision.sh john-doe --region us-east-1 --auto-approve`

### Understanding the Output

The script will display progress as it:
1. Creates per-student S3 bucket for Terraform state (~1 min)
2. Runs `terraform apply` — provisions VPC, subnets, bastion, EC2 instance (~5 min)
3. Waits for the instance to be ready (~2 min)
4. **Streams the cloud-init log live** — shows each installation step as it happens (~15 min)
5. Waits for the Gateway LoadBalancer address (~1 min)
6. Prints the k0rdent UI URL and credentials

**Expected Duration:** ~20 minutes total

**What you'll see during step 4 (live streaming):**

```
[INFO] Streaming initialization progress (live)...

  [1/6] Installing k0s Kubernetes...
  === Installing k0s v1.32.4+k0s.0 ===
  [2/6] Installing CLI tools...
  === CLI tools installed ===
  [3/6] Waiting for cluster readiness...
  === Cluster is ready ===
  Installing AWS Cloud Controller Manager...
  Setting providerID on node ip-10-0-x-x: aws:///eu-west-1a/i-xxx
  [4/6] Installing k0rdent Enterprise...
  Installing k0rdent Enterprise Helm chart...
  Waiting for cert-manager webhook...
  [5/6] Configuring providers...
  [6/6] Verifying installation...
  Installation Complete!
  Lab initialization complete!

[SUCCESS] k0rdent initialization complete
```

> **Don't worry if it pauses:** Step 4 (k0rdent Enterprise Helm install) takes 8-10 minutes. The stream may appear to hang — this is normal while Helm pulls images and waits for pods.

### Under the Hood: What the Script Actually Runs

`lab-provision.sh` is a convenience wrapper — the commands it hides are exactly what you'd run on a real customer engagement. Two layers:

**1. Terraform** (`terraform apply` over four modules): `networking` (VPC, subnets, NAT), `bastion` (Amazon Linux 2023 jump host), `iam` (instance role so the node can call AWS APIs), and `k0rdent-mgmt` (the t3.xlarge management node).

**2. Cloud-init on the management node**, in order:

1. Installs **k0s** v1.32.4+k0s.0 as a single-node cluster (`k0s install controller --enable-worker`)
2. Installs the **local-path-provisioner** as the default StorageClass
3. Installs the **AWS Cloud Controller Manager** Helm chart into `kube-system` and patches the node's `providerID` — this is what makes `LoadBalancer` Services work
4. Installs **k0rdent Enterprise** — the one command customers pay for:

```bash
helm install kcm oci://registry.mirantis.com/k0rdent-enterprise/charts/k0rdent-enterprise \
  --version 1.2.2 \
  --namespace kcm-system --create-namespace \
  --set k0rdent-ui.enabled=true \
  --set k0rdent-ui.auth.basic.password="$K0RDENT_UI_PASSWORD"
```

5. Installs the **Gateway API CRDs** and **Envoy Gateway** (Helm chart into `envoy-gateway-system`), then exposes the UI with a Gateway + HTTPRoute (sketch):

```yaml
kind: Gateway                       # kcm-system/k0rdent-gateway
spec:
  gatewayClassName: envoy-gateway
  listeners: [{ name: http, protocol: HTTP, port: 80 }]
---
kind: HTTPRoute                     # routes / to the UI Service
spec:
  parentRefs: [{ name: k0rdent-gateway }]
  rules:
    - backendRefs: [{ name: kcm-k0rdent-ui, port: 3000 }]
```

The generated UI password lands in `/opt/k0rdent-lab/config/lab-info.env` on the node. For the full scripts, see [`lab-infrastructure/terraform/modules/k0rdent-mgmt/templates/mgmt-cloud-init.yaml`](../../../lab-infrastructure/terraform/modules/k0rdent-mgmt/templates/mgmt-cloud-init.yaml).

## Part 4: Connect to the Management Cluster (~2 min)

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

## Part 5: Verify k0s Cluster (~2 min)

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

## Part 6: Verify k0rdent Enterprise Installation (~5 min)

Check k0rdent components:

```bash
# Check k0rdent namespace (using alias: kgp -n kcm-system)
kubectl get pods -n kcm-system
```

**Expected output (core components — running immediately):**
```
NAME                                                         READY   STATUS    AGE
kcm-k0rdent-enterprise-controller-manager-xxx                1/1     Running   5m
kcm-cert-manager-xxx                                         1/1     Running   5m
kcm-k0rdent-ui-xxx                                           1/1     Running   5m
helm-controller-xxx                                          1/1     Running   5m
source-controller-xxx                                        1/1     Running   5m
velero-xxx                                                   1/1     Running   5m
```

> **Note:** CAPI provider pods (capa, capz, capv, k0smotron, etc.) may show `ContainerCreating` for 2-3 minutes while they pull images. This is normal. They'll reach `Running` shortly after. The Management object will show `READY: False` until all providers finish initializing.

```bash
# Check k0rdent CRDs (they use k0rdent.mirantis.com domain)
kubectl get crds | grep k0rdent.mirantis.com

# Check available cluster templates (using alias: kgct)
kubectl get clustertemplates -A

# Check credentials (using alias: kgcred)
kubectl get credentials -A
# Empty is expected — you'll configure credentials in Lab 1.3
```

**Expected CRDs include:**
- `managements.k0rdent.mirantis.com`
- `clusterdeployments.k0rdent.mirantis.com`
- `clustertemplates.k0rdent.mirantis.com`
- `credentials.k0rdent.mirantis.com`

### Wait for Management READY

Before proceeding to the next labs, wait for the Management object to finish initializing all CAPI providers. This takes 2-5 minutes after cloud-init completes.

```bash
# Wait for Management to be fully ready (required before Lab 1.3)
kubectl wait management kcm --for=condition=Ready=True --timeout=300s
```

> **Why this matters:** Lab 1.3 requires CAPI CRDs (like `AWSClusterStaticIdentity`) that are only installed after the Management object finishes deploying all providers. If you skip this step, `kubectl apply` commands in Lab 1.3 will fail with "no matches for kind".

## Part 7: Access the k0rdent UI (~10 min)

The provisioning script waits for k0rdent and Envoy Gateway to be fully operational before printing the UI URL.

**How the UI is exposed:**

```
Browser (HTTP) → AWS Classic ELB (auto-provisioned) → Envoy Gateway → HTTPRoute → k0rdent UI (:3000)
```

Envoy Gateway uses the Kubernetes Gateway API to route traffic. AWS Cloud Controller Manager automatically provisions a Classic ELB for the Gateway's Service.

> **Why a Classic ELB?** The Gateway's `LoadBalancer` Service carries no load-balancer annotations, and the in-tree AWS CCM's default for an unannotated Service is a Classic ELB — an NLB would require the `service.beta.kubernetes.io/aws-load-balancer-type: nlb` annotation. Theory 1.2 covers this chain in depth.

**The URL is printed at the end of provisioning:**

```
============================================
  k0rdent UI
  URL:       http://xxxxx.us-east-1.elb.amazonaws.com
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

**Exercise:** Try the `--show-gateway` flag to see the full Gateway API resource status:

```bash
./scripts/lab-connect.sh <your-name> --show-gateway
```

**From inside the cluster (via SSH):**

```bash
# Get the Gateway LB address
kubectl get gateway k0rdent-gateway -n kcm-system

# View all Gateway API resources
kubectl get gatewayclass,gateway,httproute -A
```

### Hands-On: Trace the Chain That Gave the UI Its URL

The UI URL didn't appear by magic — the AWS Cloud Controller Manager built it. Trace the chain yourself with three commands (this is the same chain Theory 1.2 teaches):

**1. The node's `providerID` maps the Kubernetes node to its EC2 instance** (run via SSH):

```bash
kubectl get nodes -o jsonpath='{.items[0].spec.providerID}'
```

```
aws:///us-east-1a/i-0a1b2c3d4e5f67890
```

CCM uses this `aws:///<az>/<instance-id>` value to know which EC2 instance to register behind load balancers. Note the instance ID — you'll use it in step 3.

**2. The LoadBalancer Service that Envoy Gateway created** (run via SSH):

```bash
kubectl get svc -n envoy-gateway-system
```

```
NAME                                      TYPE           CLUSTER-IP      EXTERNAL-IP                          PORT(S)
envoy-gateway                             ClusterIP      10.96.x.x       <none>                               18000/TCP,...
envoy-kcm-system-k0rdent-gateway-xxxxx    LoadBalancer   10.96.x.x       xxxxx.us-east-1.elb.amazonaws.com    80:3xxxx/TCP
```

The `EXTERNAL-IP` is the Classic ELB hostname CCM provisioned — it's exactly the hostname in your UI URL.

**3. The cluster tag CCM uses to find its AWS resources** (run from your laptop, using the instance ID from step 1):

```bash
aws ec2 describe-tags \
  --filters "Name=resource-id,Values=<instance-id>" \
            "Name=key,Values=kubernetes.io/cluster/k0rdent-mgmt-<your-engineer-id>"
```

```json
{
    "Tags": [
        {
            "Key": "kubernetes.io/cluster/k0rdent-mgmt-<your-engineer-id>",
            "ResourceId": "i-0a1b2c3d4e5f67890",
            "ResourceType": "instance",
            "Value": "owned"
        }
    ]
}
```

This `kubernetes.io/cluster/<name> = owned` tag (also on the VPC subnets) is how CCM discovers which instances and subnets belong to this cluster when it creates the ELB and registers instances behind it.

## Part 8: Explore k0rdent Resources (~5 min)

Using kubectl (or the pre-configured aliases), explore the k0rdent resources:

```bash
# List management objects (using alias: kgm)
kubectl get management -A

# List available cluster templates (using alias: kgct)
kubectl get clustertemplates -A

# List cluster deployments (using alias: kgcd)
kubectl get clusterdeployments -A
# Empty is expected — you'll create clusters in Lab 1.5

# List configured credentials (using alias: kgcred)
kubectl get credentials -A
# Empty is expected — you'll configure credentials in Lab 1.3
```

**Understanding the Output:**

- **Management**: The core k0rdent configuration object
- **ClusterTemplates**: Pre-defined cluster configurations (AWS, Azure, vSphere, etc.)
- **ClusterDeployments**: Actual deployed clusters (none yet — you'll create these in Lab 1.5)
- **Credentials**: Cloud provider credentials (none yet — you'll configure these in Lab 1.3)

### Explore Other Namespaces

k0rdent runs components across multiple namespaces (see Theory 1.2 for the full component reference):

```bash
# Sveltos — the service distribution engine (powers MultiClusterService)
kubectl get pods -n projectsveltos

# Envoy Gateway — routes traffic to the k0rdent UI
kubectl get pods -n envoy-gateway-system

# View all namespaces with running pods
kubectl get pods -A --no-headers | awk '{print $1}' | sort | uniq -c | sort -rn
```

## Validation Checklist

Before completing this lab, verify:

- [ ] Provisioning script completed successfully
- [ ] SSH connection to management cluster works
- [ ] k0s cluster shows node as Ready
- [ ] All pods in kcm-system namespace are Running
- [ ] k0rdent CRDs are installed
- [ ] k0rdent UI is accessible (optional)
- [ ] You traced the CCM chain: node `providerID` → LoadBalancer Service → `kubernetes.io/cluster/<name>` tag

## Troubleshooting

For quick diagnostics:

```bash
# Check environment status
./scripts/lab-status.sh your-name
```

**Error: Terraform version too old**

```bash
# Install newer Terraform (macOS)

# 1. If you have an old terraform from the core homebrew formula, uninstall it first.
#    Homebrew's plain `terraform` formula is pinned to 1.5.7 (the last MPL release
#    before HashiCorp switched to BSL). The `hashicorp/tap` formula ships the latest.
brew uninstall terraform 2>/dev/null || true

# 2. Tap and install from the HashiCorp tap
brew tap hashicorp/tap
brew install hashicorp/tap/terraform

# 3. Verify
terraform version
```

```bash
# Install newer Terraform (Linux)

# Option 1: HashiCorp apt repository (Debian/Ubuntu)
wget -O - https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install terraform

# Option 2: Direct binary download (any distro) — pick the latest
# version from https://releases.hashicorp.com/terraform/
curl -fsSL -o terraform.zip "https://releases.hashicorp.com/terraform/<version>/terraform_<version>_linux_amd64.zip"
unzip terraform.zip && sudo mv terraform /usr/local/bin/

# Verify
terraform version
```

> **Windows:** Use WSL2 and install Terraform *inside* your WSL2 distro with the Linux instructions above. The lab scripts are bash — they do not run in PowerShell, cmd, or Git Bash.

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

> **Important:** Only destroy if you're done with **all labs in the curriculum**. The management cluster is reused in every subsequent week — Week 5 GPU labs create GPU clusters via ClusterDeployment on this same management cluster. If you need to stop for the day, leave the management cluster running and use `lab-connect.sh` to reconnect later.

> **Cost reality check:** The management instance carries a `TTLHours` tag (default 8), but it is **informational only** — there is no reaper, and nothing auto-terminates the instance. You are billed continuously until you stop or destroy the environment yourself. Pause and final teardown guidance lives at the end of [Lab 1.8](lab-1.8-upgrade-k0rdent.md) (pausing = `aws ec2 stop-instances`; note the NAT gateway, EIP, and EBS volumes still bill while instances are stopped).

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
