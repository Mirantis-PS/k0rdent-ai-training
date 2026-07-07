# Per-Student Lab Infrastructure Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the shared infrastructure model with per-student isolation — one command creates everything (VPC, bastion, IAM, k0rdent cluster) in a single Terraform apply.

**Architecture:** Extract networking and IAM from `modules/shared-infra/` into standalone modules. Create a new `environments/student-lab/` root that composes networking + bastion + IAM + k0rdent-mgmt (+ optional GPU/Metal3/KubeVirt). Rewrite all 4 scripts to work with per-student S3 buckets and a single state file. Delete the old shared/k0rdent/gpu/metal3/kubevirt environments.

**Tech Stack:** Terraform >= 1.5, AWS provider ~> 5.0, Bash scripts

**Design doc:** `docs/plans/2026-02-20-per-student-infrastructure-design.md`

---

## Task 1: Create `modules/networking/`

Extract VPC, subnets, NAT, security groups from `modules/shared-infra/main.tf`. Add `engineer_id` to all resource names to avoid collisions between students in the same account.

**Files:**
- Create: `terraform/modules/networking/main.tf`
- Create: `terraform/modules/networking/variables.tf`
- Create: `terraform/modules/networking/outputs.tf`

**Step 1: Create `modules/networking/variables.tf`**

```hcl
variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "k0rdent-training"
}

variable "engineer_id" {
  description = "Unique identifier for the engineer"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "gpu_az" {
  description = "Availability zone with GPU instance capacity. Empty = auto-select first AZ."
  type        = string
  default     = ""
}

variable "allowed_ssh_cidrs" {
  description = "CIDR blocks allowed to SSH to bastion"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "tags" {
  description = "Additional tags for all resources"
  type        = map(string)
  default     = {}
}
```

**Step 2: Create `modules/networking/main.tf`**

Copy from `modules/shared-infra/main.tf` lines 1-367 (everything except the S3 section which is already a comment). Key changes:
- Remove `variable "region"` (not needed — provider handles it)
- Remove `data "aws_caller_identity"` and all S3 bucket locals (lines 25-34)
- Add `engineer_id` to all resource `Name` tags: `"${var.project_name}-${var.engineer_id}-vpc"` etc.
- Add `engineer_id` to security group `name` fields to avoid AWS name collisions
- Update `local.gpu_az` reference: `local.effective_gpu_az = var.gpu_az != "" ? var.gpu_az : local.azs[0]`
- Keep `local.common_tags` but add `EngineerID = var.engineer_id`

Resource naming pattern — all resources get `${var.project_name}-${var.engineer_id}-` prefix:
- VPC: `k0rdent-training-crusu-vpc`
- Subnets: `k0rdent-training-crusu-public-us-east-1a`
- NAT: `k0rdent-training-crusu-nat`
- Security groups: `k0rdent-training-crusu-bastion-sg`, etc.

**Step 3: Create `modules/networking/outputs.tf`**

```hcl
output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "VPC CIDR block"
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "List of public subnet IDs"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "List of private subnet IDs"
  value       = aws_subnet.private[*].id
}

output "gpu_subnet_id" {
  description = "GPU subnet ID"
  value       = aws_subnet.gpu.id
}

output "bastion_security_group_id" {
  description = "Bastion security group ID"
  value       = aws_security_group.bastion.id
}

output "lab_instance_security_group_id" {
  description = "Lab instance security group ID"
  value       = aws_security_group.lab_instance.id
}

output "k8s_cluster_security_group_id" {
  description = "K8s cluster security group ID"
  value       = aws_security_group.k8s_cluster.id
}

output "gpu_lab_security_group_id" {
  description = "GPU lab security group ID"
  value       = aws_security_group.gpu_lab.id
}

output "availability_zones" {
  description = "Availability zones in use"
  value       = local.azs
}

output "nat_gateway_ip" {
  description = "NAT Gateway public IP"
  value       = aws_eip.nat.public_ip
}
```

**Step 4: Validate**

Run: `cd terraform/modules/networking && terraform init && terraform validate`
Expected: `Success! The configuration is valid.`

**Step 5: Commit**

```bash
git add terraform/modules/networking/
git commit -m "feat(infra): create per-student networking module

Extracted from shared-infra. All resource names include engineer_id
to support multiple students in the same AWS account."
```

---

## Task 2: Create `modules/iam/`

Extract IAM roles, policies, and instance profiles from `modules/shared-infra/iam.tf`. Add `engineer_id` to role names.

**Files:**
- Create: `terraform/modules/iam/main.tf`
- Create: `terraform/modules/iam/variables.tf`
- Create: `terraform/modules/iam/outputs.tf`

**Step 1: Create `modules/iam/variables.tf`**

```hcl
variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "k0rdent-training"
}

variable "engineer_id" {
  description = "Unique identifier for the engineer"
  type        = string
}

variable "region" {
  description = "AWS region (used in IAM role names for uniqueness)"
  type        = string
}

variable "artifacts_bucket_arn" {
  description = "ARN of the artifacts S3 bucket"
  type        = string
}

variable "student_bucket_arn" {
  description = "ARN of the student's S3 bucket (for tfstate + images)"
  type        = string
}

variable "tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}
```

**Step 2: Create `modules/iam/main.tf`**

Copy from `modules/shared-infra/iam.tf`. Key changes:
- Replace all `${var.region}` in role names with `${var.engineer_id}-${var.region}` to ensure uniqueness per student
- Replace hardcoded S3 bucket ARN locals with `var.student_bucket_arn` and `var.artifacts_bucket_arn`
- Add `data "aws_caller_identity" "current" {}` (was in shared-infra main.tf)
- Remove `lab_provisioner` and `lab_admin` roles — students don't need these for self-service. Keep only `lab_instance` role + instance profile.

**Step 3: Create `modules/iam/outputs.tf`**

```hcl
output "lab_instance_profile_name" {
  description = "IAM instance profile name for lab instances"
  value       = aws_iam_instance_profile.lab_instance.name
}

output "lab_instance_role_arn" {
  description = "IAM role ARN for lab instances"
  value       = aws_iam_role.lab_instance.arn
}
```

**Step 4: Validate**

Run: `cd terraform/modules/iam && terraform init && terraform validate`
Expected: `Success! The configuration is valid.`

**Step 5: Commit**

```bash
git add terraform/modules/iam/
git commit -m "feat(infra): create per-student IAM module

Extracted from shared-infra/iam.tf. Role names include engineer_id
to avoid collisions. Removed lab_provisioner and lab_admin roles
(not needed for self-service student deployments)."
```

---

## Task 3: Update `modules/bastion/`

Add `engineer_id` to resource names so multiple students can have their own bastion in the same account.

**Files:**
- Modify: `terraform/modules/bastion/variables.tf` — add `engineer_id` variable
- Modify: `terraform/modules/bastion/main.tf` — update resource names

**Step 1: Add `engineer_id` variable**

Add to `terraform/modules/bastion/variables.tf`:
```hcl
variable "engineer_id" {
  description = "Unique identifier for the engineer"
  type        = string
}
```

**Step 2: Update resource names in `main.tf`**

Change all Name tags and `key_name` to include engineer_id:
- `key_name`: `"${var.project_name}-bastion"` -> `"${var.project_name}-${var.engineer_id}-bastion"`
- Instance Name tag: same pattern
- EIP Name tag: same pattern
- CloudWatch log group: `"/k0rdent-training/bastion"` -> `"/k0rdent-training/${var.engineer_id}/bastion"`

**Step 3: Validate**

Run: `cd terraform/modules/bastion && terraform init && terraform validate`
Expected: `Success! The configuration is valid.`

**Step 4: Commit**

```bash
git add terraform/modules/bastion/
git commit -m "feat(bastion): add engineer_id to resource names

Enables per-student bastion hosts in shared AWS accounts."
```

---

## Task 4: Update `modules/k0rdent-mgmt/`

Remove the `aws.s3` provider alias (no more cross-region S3). All S3 operations use the default provider in the student's region.

**Files:**
- Modify: `terraform/modules/k0rdent-mgmt/main.tf`
- Modify: `terraform/modules/k0rdent-mgmt/variables.tf`

**Step 1: Remove `aws.s3` provider alias from `main.tf`**

In the `terraform` block (lines 8-10), remove:
```hcl
configuration_aliases = [aws.s3]
```

For the three `aws_s3_object` resources (lines 318-357), remove:
```hcl
provider = aws.s3
```

**Step 2: Remove `images_bucket` variable from `variables.tf`**

The `images_bucket` variable is no longer needed since the student bucket replaces it. Keep `artifacts_bucket` — it now points to the student's own bucket.

Also remove `tfstate_bucket` variable — not needed by the module.

**Step 3: Validate**

Run: `cd terraform/modules/k0rdent-mgmt && terraform init && terraform validate`
Expected: `Success! The configuration is valid.`

**Step 4: Commit**

```bash
git add terraform/modules/k0rdent-mgmt/
git commit -m "refactor(k0rdent-mgmt): remove cross-region S3 provider alias

S3 operations now use the default provider. Student bucket is
always in the same region as the deployment."
```

---

## Task 5: Create `environments/student-lab/`

The new single root module. Composes networking + bastion + IAM + k0rdent-mgmt, with optional GPU/Metal3/KubeVirt.

**Files:**
- Create: `terraform/environments/student-lab/main.tf`
- Create: `terraform/environments/student-lab/variables.tf`
- Create: `terraform/environments/student-lab/outputs.tf`

**Step 1: Create `variables.tf`**

```hcl
# Core
variable "engineer_id" {
  description = "Unique identifier for the engineer (e.g., 'crusu', 'john-doe')"
  type        = string
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "k0rdent-training"
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "student_bucket" {
  description = "S3 bucket name for this student (created by the script)"
  type        = string
}

# Networking
variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "allowed_ssh_cidrs" {
  description = "CIDR blocks allowed to SSH to bastion"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "gpu_az" {
  description = "Availability zone for GPU instances. Empty = auto-select."
  type        = string
  default     = ""
}

# k0rdent cluster
variable "node_count" {
  description = "Number of management cluster nodes (1 for lab, 3 for HA)"
  type        = number
  default     = 1
}

variable "instance_type" {
  description = "EC2 instance type for management nodes"
  type        = string
  default     = "t3.xlarge"
}

variable "root_volume_size" {
  description = "Root volume size in GB"
  type        = number
  default     = 100
}

variable "k0s_version" {
  description = "k0s version"
  type        = string
  default     = "v1.32.4+k0s.0"
}

variable "k0rdent_version" {
  description = "k0rdent Enterprise version"
  type        = string
  default     = "1.2.1"
}

variable "ui_password" {
  description = "k0rdent UI password (empty = auto-generate)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "flux_version" {
  description = "Flux CD version"
  type        = string
  default     = "v2.4.0"
}

# Training metadata
variable "cohort_id" {
  description = "Training cohort ID"
  type        = string
  default     = "cohort-01"
}

variable "current_week" {
  description = "Current training week (1-6)"
  type        = number
  default     = 1
}

variable "ttl_hours" {
  description = "Time to live in hours"
  type        = number
  default     = 8
}

# Optional lab environments (enabled for later weeks)
variable "enable_gpu_lab" {
  description = "Enable GPU lab environment"
  type        = bool
  default     = false
}

variable "enable_metal3" {
  description = "Enable Metal3 dev environment"
  type        = bool
  default     = false
}

variable "enable_kubevirt" {
  description = "Enable KubeVirt lab environment"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}
```

**Step 2: Create `main.tf`**

```hcl
# Student Lab Environment
# Single Terraform apply creates all resources for one student

terraform {
  required_version = ">= 1.5.0"

  backend "s3" {}

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = var.project_name
      ManagedBy   = "terraform"
      Owner       = var.engineer_id
      Environment = "student-lab"
    }
  }
}

# --- Networking ---
module "networking" {
  source = "../../modules/networking"

  project_name      = var.project_name
  engineer_id       = var.engineer_id
  vpc_cidr          = var.vpc_cidr
  gpu_az            = var.gpu_az
  allowed_ssh_cidrs = var.allowed_ssh_cidrs
  tags              = var.tags
}

# --- Bastion ---
module "bastion" {
  source = "../../modules/bastion"

  project_name    = var.project_name
  engineer_id     = var.engineer_id
  subnet_id       = module.networking.public_subnet_ids[0]
  security_group_id = module.networking.bastion_security_group_id
  tags            = var.tags
}

# --- IAM ---
module "iam" {
  source = "../../modules/iam"

  project_name         = var.project_name
  engineer_id          = var.engineer_id
  region               = var.region
  student_bucket_arn   = "arn:aws:s3:::${var.student_bucket}"
  artifacts_bucket_arn = "arn:aws:s3:::${var.student_bucket}"
  tags                 = var.tags
}

# --- k0rdent Management Cluster ---
module "k0rdent_mgmt" {
  source = "../../modules/k0rdent-mgmt"

  project_name = var.project_name
  engineer_id  = var.engineer_id
  region       = var.region

  vpc_id                = module.networking.vpc_id
  subnet_id             = module.networking.private_subnet_ids[0]
  public_subnet_ids     = module.networking.public_subnet_ids
  security_group_ids    = [module.networking.lab_instance_security_group_id]
  instance_profile_name = module.iam.lab_instance_profile_name
  bastion_sg_id         = module.networking.bastion_security_group_id

  node_count       = var.node_count
  instance_type    = var.instance_type
  root_volume_size = var.root_volume_size

  k0s_version     = var.k0s_version
  k0rdent_version = var.k0rdent_version
  ui_password     = var.ui_password
  flux_version    = var.flux_version

  artifacts_bucket = var.student_bucket

  cohort_id    = var.cohort_id
  current_week = var.current_week
  ttl_hours    = var.ttl_hours

  tags = var.tags
}

# --- Optional: GPU Lab ---
module "gpu_lab" {
  count  = var.enable_gpu_lab ? 1 : 0
  source = "../../modules/gpu-lab"

  project_name   = var.project_name
  lab_session_id = var.engineer_id
  region         = var.region

  gpu_subnet_id         = module.networking.gpu_subnet_id
  security_group_ids    = [module.networking.gpu_lab_security_group_id]
  instance_profile_name = module.iam.lab_instance_profile_name

  artifacts_bucket = var.student_bucket
  images_bucket    = var.student_bucket

  tags = var.tags
}

# --- Optional: Metal3 ---
module "metal3_dev" {
  count  = var.enable_metal3 ? 1 : 0
  source = "../../modules/metal3-dev"

  project_name = var.project_name
  engineer_id  = var.engineer_id
  region       = var.region

  subnet_id             = module.networking.private_subnet_ids[0]
  security_group_ids    = [module.networking.lab_instance_security_group_id]
  instance_profile_name = module.iam.lab_instance_profile_name

  artifacts_bucket = var.student_bucket
  images_bucket    = var.student_bucket

  tags = var.tags
}

# --- Optional: KubeVirt ---
module "kubevirt_lab" {
  count  = var.enable_kubevirt ? 1 : 0
  source = "../../modules/kubevirt-lab"

  project_name = var.project_name
  engineer_id  = var.engineer_id
  region       = var.region

  subnet_id             = module.networking.private_subnet_ids[0]
  security_group_ids    = [module.networking.k8s_cluster_security_group_id]
  instance_profile_name = module.iam.lab_instance_profile_name

  artifacts_bucket = var.student_bucket
  images_bucket    = var.student_bucket

  tags = var.tags
}
```

**Step 3: Create `outputs.tf`**

```hcl
# --- Bastion ---
output "bastion_public_ip" {
  description = "Bastion host public IP"
  value       = module.bastion.public_ip
}

output "bastion_ssh_private_key" {
  description = "Bastion SSH private key"
  value       = module.bastion.ssh_private_key
  sensitive   = true
}

# --- Networking ---
output "vpc_id" {
  description = "VPC ID"
  value       = module.networking.vpc_id
}

output "nat_gateway_ip" {
  description = "NAT Gateway public IP"
  value       = module.networking.nat_gateway_ip
}

# --- k0rdent ---
output "mgmt_node_ids" {
  description = "Instance IDs of management cluster nodes"
  value       = module.k0rdent_mgmt.node_instance_ids
}

output "primary_node_private_ip" {
  description = "Private IP of primary management node"
  value       = module.k0rdent_mgmt.primary_node_ip
}

output "ssh_private_key" {
  description = "SSH private key for k0rdent nodes"
  value       = module.k0rdent_mgmt.ssh_private_key
  sensitive   = true
}

output "connection_info" {
  description = "Connection instructions"
  value       = module.k0rdent_mgmt.connection_info
}

output "ui_url" {
  description = "k0rdent UI URL"
  value       = module.k0rdent_mgmt.ui_url
}

output "ui_password" {
  description = "k0rdent UI password"
  value       = module.k0rdent_mgmt.ui_password
  sensitive   = true
}

# --- Optional labs ---
output "shared_gpu_private_ip" {
  description = "Shared GPU instance IP"
  value       = var.enable_gpu_lab ? module.gpu_lab[0].shared_gpu_private_ip : null
}

output "metal3_controller_ip" {
  description = "Metal3 controller IP"
  value       = var.enable_metal3 ? module.metal3_dev[0].controller_private_ip : null
}

output "kubevirt_controller_ip" {
  description = "KubeVirt controller IP"
  value       = var.enable_kubevirt ? module.kubevirt_lab[0].controller_private_ip : null
}
```

**Step 4: Validate**

Run: `cd terraform/environments/student-lab && terraform init && terraform validate`
Expected: `Success! The configuration is valid.`

**Step 5: Commit**

```bash
git add terraform/environments/student-lab/
git commit -m "feat(infra): create student-lab environment

Single Terraform root per student. Composes networking, bastion,
IAM, and k0rdent-mgmt modules. Optional GPU/Metal3/KubeVirt via
feature flags. No terraform_remote_state dependencies."
```

---

## Task 6: Rewrite `scripts/lab-provision.sh`

Replace the multi-environment provisioning logic with a single per-student flow. Delete ~200 lines of shared infrastructure detection and migration.

**Files:**
- Modify: `scripts/lab-provision.sh`

**Step 1: Replace bucket functions**

Delete: `get_tfstate_bucket()`, `get_bucket_region()`, `ensure_tfstate_bucket()`, `ensure_s3_buckets()`

Replace with:
```bash
get_student_bucket() {
    local engineer_id="$1"
    local account_id
    account_id=$(aws sts get-caller-identity --query Account --output text)
    echo "k0rdent-lab-${engineer_id}-${account_id}"
}

ensure_student_bucket() {
    local bucket_name="$1"

    if aws s3api head-bucket --bucket "$bucket_name" 2>/dev/null; then
        log_info "Using existing bucket: $bucket_name"
        return 0
    fi

    log_info "Creating student bucket: $bucket_name in $REGION"

    if [[ "$REGION" == "us-east-1" ]]; then
        aws s3api create-bucket --bucket "$bucket_name" --region "$REGION"
    else
        aws s3api create-bucket --bucket "$bucket_name" --region "$REGION" \
            --create-bucket-configuration LocationConstraint="$REGION"
    fi

    aws s3api put-bucket-versioning --bucket "$bucket_name" \
        --versioning-configuration Status=Enabled

    aws s3api put-bucket-encryption --bucket "$bucket_name" \
        --server-side-encryption-configuration \
        '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

    log_success "Created bucket: $bucket_name"
}
```

**Step 2: Delete shared infrastructure functions**

Delete entirely:
- `check_shared_infrastructure()`
- `ensure_shared_infrastructure()`
- `ensure_bastion_key()`
- `provision_shared()`
- `migrate_legacy_state_keys()`
- `save_config()` / `load_config()` (BUCKET_REGION no longer needed)

**Step 3: Replace all provision functions with single `provision_lab()`**

```bash
provision_lab() {
    local engineer_id="$1"
    log_info "Provisioning lab environment for $engineer_id..."

    local bucket
    bucket=$(get_student_bucket "$engineer_id")
    ensure_student_bucket "$bucket"

    local env_dir="$TERRAFORM_DIR/environments/student-lab"
    cd "$env_dir"

    terraform init -reconfigure \
        -backend-config="bucket=${bucket}" \
        -backend-config="key=terraform.tfstate" \
        -backend-config="region=${REGION}"

    if [[ "$PLAN_ONLY" == "true" ]]; then
        terraform plan \
            -var="engineer_id=${engineer_id}" \
            -var="region=${REGION}" \
            -var="student_bucket=${bucket}" \
            -var="node_count=${NODE_COUNT}" \
            -var="enable_gpu_lab=${ENABLE_GPU}" \
            -var="enable_metal3=${ENABLE_METAL3}" \
            -var="enable_kubevirt=${ENABLE_KUBEVIRT}"
        return 0
    fi

    local apply_args=""
    [[ "$AUTO_APPROVE" == "true" ]] && apply_args="-auto-approve"

    terraform apply $apply_args \
        -var="engineer_id=${engineer_id}" \
        -var="region=${REGION}" \
        -var="student_bucket=${bucket}" \
        -var="node_count=${NODE_COUNT}" \
        -var="enable_gpu_lab=${ENABLE_GPU}" \
        -var="enable_metal3=${ENABLE_METAL3}" \
        -var="enable_kubevirt=${ENABLE_KUBEVIRT}"

    # Wait for primary instance
    local instance_id
    instance_id=$(terraform output -json mgmt_node_ids 2>/dev/null | jq -r '.[0]' || echo "")
    if [[ -n "$instance_id" && "$instance_id" != "null" ]]; then
        wait_for_instance "$instance_id" 600
    fi

    # Save SSH keys locally
    local key_dir="$CONFIG_DIR/keys"
    mkdir -p "$key_dir"
    terraform output -raw ssh_private_key > "$key_dir/${engineer_id}-k0rdent.pem"
    chmod 600 "$key_dir/${engineer_id}-k0rdent.pem"
    terraform output -raw bastion_ssh_private_key > "$key_dir/${engineer_id}-bastion.pem"
    chmod 600 "$key_dir/${engineer_id}-bastion.pem"

    # Save config for connect/status/destroy scripts
    mkdir -p "$CONFIG_DIR"
    cat > "$CONFIG_DIR/lab-config.env" <<ENVEOF
LAB_REGION="${REGION}"
LAB_ENGINEER_ID="${engineer_id}"
LAB_BUCKET="${bucket}"
ENVEOF

    log_success "Lab environment provisioned for $engineer_id!"
    log_info "Bastion IP: $(terraform output -raw bastion_public_ip)"
    log_info "Primary node IP: $(terraform output -raw primary_node_private_ip)"
    log_info "SSH key: $key_dir/${engineer_id}-k0rdent.pem"
    log_info "Connect via: ./lab-connect.sh $engineer_id"
    echo ""
    log_info "k0rdent UI:"
    log_info "  URL:      $(terraform output -raw ui_url 2>/dev/null || echo 'initializing...')"
    log_info "  Password: run: terraform output ui_password"
}
```

**Step 4: Update usage, argument parsing, and main dispatch**

Update `usage()` to reflect simplified interface:
```
Usage: $0 <your-name> [options]

Options:
  --region <region>     AWS region (required on first run)
  --gpu                 Enable GPU lab environment
  --metal3              Enable Metal3 dev environment
  --kubevirt            Enable KubeVirt lab environment
  --nodes <n>           Number of k0rdent management nodes (default: 1)
  --auto-approve        Skip confirmation prompts
  --plan-only           Show plan without applying
```

Update argument parsing — single command pattern:
```bash
IDENTIFIER=""
ENABLE_GPU="false"
ENABLE_METAL3="false"
ENABLE_KUBEVIRT="false"
# ... parse args ...

provision_lab "$IDENTIFIER"
```

**Step 5: Validate script syntax**

Run: `bash -n scripts/lab-provision.sh`
Expected: no output (no syntax errors)

**Step 6: Commit**

```bash
git add scripts/lab-provision.sh
git commit -m "refactor(scripts): rewrite lab-provision for per-student model

Single provision_lab() replaces 5 separate provision functions.
Per-student S3 bucket. No shared infrastructure detection.
~200 lines of complexity removed."
```

---

## Task 7: Rewrite `scripts/lab-connect.sh`

Read bastion IP and SSH keys from the student's own state instead of shared state.

**Files:**
- Modify: `scripts/lab-connect.sh`

**Step 1: Replace bucket/state functions**

Delete: `get_tfstate_bucket()`, `get_bucket_region()`

Replace with:
```bash
get_student_bucket() {
    local engineer_id="$1"
    local account_id
    account_id=$(aws sts get-caller-identity --query Account --output text)
    echo "k0rdent-lab-${engineer_id}-${account_id}"
}

get_state_output() {
    local bucket="$1"
    local output_name="$2"
    aws s3 cp "s3://${bucket}/terraform.tfstate" - 2>/dev/null \
        | jq -r ".outputs.${output_name}.value // empty" 2>/dev/null
}
```

**Step 2: Simplify `get_bastion_ip()`, `get_ssh_key()`, `get_instance_ip()`**

All read from the single student state:
```bash
get_bastion_ip() {
    local bucket
    bucket=$(get_student_bucket "$IDENTIFIER")
    get_state_output "$bucket" "bastion_public_ip"
}
```

`get_ssh_key()` and `get_instance_ip()` similarly simplified — no more `case` on lab_type for state key construction.

**Step 3: Update `load_config()` to use new config format**

Read `LAB_BUCKET` and `LAB_ENGINEER_ID` from the config saved by `lab-provision.sh`.

**Step 4: Validate**

Run: `bash -n scripts/lab-connect.sh`

**Step 5: Commit**

```bash
git add scripts/lab-connect.sh
git commit -m "refactor(scripts): rewrite lab-connect for per-student model

Reads from single student state file. No shared state dependency.
No BUCKET_REGION tracking."
```

---

## Task 8: Rewrite `scripts/lab-destroy.sh`

Single `terraform destroy` tears down everything.

**Files:**
- Modify: `scripts/lab-destroy.sh`

**Step 1: Simplify to single destroy function**

```bash
destroy_lab() {
    local engineer_id="$1"
    local bucket
    bucket=$(get_student_bucket "$engineer_id")

    confirm_destroy "all lab resources for $engineer_id"

    local env_dir="$TERRAFORM_DIR/environments/student-lab"
    cd "$env_dir"

    terraform init -reconfigure \
        -backend-config="bucket=${bucket}" \
        -backend-config="key=terraform.tfstate" \
        -backend-config="region=${REGION}" &>/dev/null || true

    if ! terraform state list &>/dev/null 2>&1; then
        log_warn "No state found for $engineer_id."
        return 0
    fi

    local destroy_args=""
    [[ "$AUTO_APPROVE" == "true" ]] && destroy_args="-auto-approve"

    terraform destroy $destroy_args \
        -var="engineer_id=${engineer_id}" \
        -var="region=${REGION}" \
        -var="student_bucket=${bucket}"

    # Clean up local files
    rm -f "$CONFIG_DIR/keys/${engineer_id}-k0rdent.pem"
    rm -f "$CONFIG_DIR/keys/${engineer_id}-bastion.pem"
    rm -f "$CONFIG_DIR/kubeconfig/${engineer_id}.kubeconfig"

    # Optionally delete the S3 bucket
    if [[ "$DELETE_BUCKET" == "true" ]]; then
        log_info "Deleting student bucket: $bucket"
        aws s3 rb "s3://${bucket}" --force 2>/dev/null || true
    fi

    log_success "All resources for $engineer_id destroyed!"
}
```

Delete: `destroy_shared()`, `destroy_k0rdent()`, `destroy_metal3()`, `destroy_kubevirt()`, `destroy_gpu()`, `destroy_all_engineer()`, `destroy_all_session()`, `get_bucket_region()`

**Step 2: Update usage and argument parsing**

```
Usage: $0 <your-name> [options]

Options:
  --region <region>     AWS region
  --auto-approve        Skip confirmation
  --delete-bucket       Also delete the student's S3 bucket
```

**Step 3: Validate**

Run: `bash -n scripts/lab-destroy.sh`

**Step 4: Commit**

```bash
git add scripts/lab-destroy.sh
git commit -m "refactor(scripts): rewrite lab-destroy for per-student model

Single terraform destroy removes everything. Optional --delete-bucket
to clean up S3. No shared infrastructure destroy risk."
```

---

## Task 9: Rewrite `scripts/lab-status.sh`

Read all status from the student's single state file.

**Files:**
- Modify: `scripts/lab-status.sh`

**Step 1: Simplify to single status function**

Read outputs from student state via S3. Show: bastion IP, k0rdent node IPs, UI URL, instance states, optional lab status.

Delete: `show_shared_status()`, `show_metal3_status()`, `show_kubevirt_status()`, `show_gpu_status()`, `get_bucket_region()`

**Step 2: Validate**

Run: `bash -n scripts/lab-status.sh`

**Step 3: Commit**

```bash
git add scripts/lab-status.sh
git commit -m "refactor(scripts): rewrite lab-status for per-student model"
```

---

## Task 10: Delete old environments and shared-infra module

Remove the old directory structure now that everything is replaced.

**Files:**
- Delete: `terraform/environments/shared/`
- Delete: `terraform/environments/k0rdent/`
- Delete: `terraform/environments/gpu-lab/`
- Delete: `terraform/environments/metal3-dev/`
- Delete: `terraform/environments/kubevirt-lab/`
- Delete: `terraform/modules/shared-infra/`

**Step 1: Remove directories**

```bash
rm -rf terraform/environments/shared
rm -rf terraform/environments/k0rdent
rm -rf terraform/environments/gpu-lab
rm -rf terraform/environments/metal3-dev
rm -rf terraform/environments/kubevirt-lab
rm -rf terraform/modules/shared-infra
```

**Step 2: Verify no dangling references**

Run: `grep -r "shared-infra\|terraform_remote_state\|BUCKET_REGION\|get_bucket_region" terraform/ scripts/`
Expected: no matches

**Step 3: Validate remaining Terraform**

Run: `cd terraform/environments/student-lab && terraform init && terraform validate`
Expected: `Success!`

**Step 4: Commit**

```bash
git add -A
git commit -m "refactor(infra): remove old shared and per-environment directories

Replaced by per-student student-lab environment. Eliminates
terraform_remote_state, shared infrastructure detection, and
cross-student interference."
```

---

## Task 11: Final integration validation

End-to-end dry run to verify everything wires together.

**Step 1: Run `terraform plan` with test values**

```bash
cd terraform/environments/student-lab
terraform init \
    -backend-config="bucket=test-bucket" \
    -backend-config="key=terraform.tfstate" \
    -backend-config="region=us-east-1" \
    -backend=false

terraform plan \
    -var="engineer_id=test-student" \
    -var="region=us-east-1" \
    -var="student_bucket=test-bucket"
```

Expected: plan shows ~30-40 resources to create (VPC, subnets, NAT, bastion, IAM, k0rdent instances, NLB, etc.)

**Step 2: Verify script syntax**

```bash
bash -n scripts/lab-provision.sh
bash -n scripts/lab-connect.sh
bash -n scripts/lab-destroy.sh
bash -n scripts/lab-status.sh
```

Expected: all pass with no output

**Step 3: Final commit**

```bash
git add -A
git commit -m "chore: final validation of per-student infrastructure rework"
```
