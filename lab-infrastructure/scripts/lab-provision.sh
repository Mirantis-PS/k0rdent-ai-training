#!/bin/bash
# k0rdent Training Lab Provisioning Script
# Usage: ./lab-provision.sh <lab-type> <identifier> [options]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$SCRIPT_DIR/../terraform"
CONFIG_DIR="$SCRIPT_DIR/../config"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Wait for an EC2 instance to be running and SSH-ready
wait_for_instance() {
    local instance_id="$1"
    local max_wait="${2:-300}"  # Default 5 minutes
    local start_time=$(date +%s)

    log_info "Waiting for instance $instance_id to be running..."

    # Wait for instance to be in running state
    while true; do
        local state
        state=$(aws ec2 describe-instances --instance-ids "$instance_id" \
            --query 'Reservations[0].Instances[0].State.Name' --output text 2>/dev/null || echo "unknown")

        if [[ "$state" == "running" ]]; then
            log_success "Instance is running"
            break
        fi

        local elapsed=$(($(date +%s) - start_time))
        if [[ $elapsed -ge $max_wait ]]; then
            log_error "Timeout waiting for instance to be running (state: $state)"
            return 1
        fi

        echo -n "."
        sleep 5
    done

    # Wait for instance status checks to pass
    log_info "Waiting for instance status checks..."
    while true; do
        local status
        status=$(aws ec2 describe-instance-status --instance-ids "$instance_id" \
            --query 'InstanceStatuses[0].InstanceStatus.Status' --output text 2>/dev/null || echo "initializing")

        if [[ "$status" == "ok" ]]; then
            log_success "Instance status checks passed"
            break
        fi

        local elapsed=$(($(date +%s) - start_time))
        if [[ $elapsed -ge $max_wait ]]; then
            log_warn "Timeout waiting for status checks (status: $status), but instance is running"
            break
        fi

        echo -n "."
        sleep 10
    done

    return 0
}

usage() {
    cat <<EOF
k0rdent Training Lab Provisioning Script

Usage: $0 <lab-type> <your-name> [options]

Lab Types:
  k0rdent <your-name>         Provision k0rdent Enterprise management cluster (Week 1)
  metal3 <your-name>          Provision Metal3 dev environment (Week 2: BMaaS)
  kubevirt <your-name>        Provision KubeVirt lab environment (Week 3: VMaaS)
  gpu <session-id>            Provision GPU lab environment (Week 4-5: AI workloads)
  gpu-advanced <session-id>   Provision advanced GPU lab (8x A100)

Options:
  --region <region>           AWS region (or set AWS_REGION env var)
  --spot                      Use spot instances for cost savings
  --no-spot                   Use on-demand instances (default, more reliable)
  --workers <n>               Number of workers (kubevirt only, default: 2)
  --nodes <n>                 Number of nodes (k0rdent only, default: 1)
  --auto-approve              Skip confirmation prompts
  --plan-only                 Only show Terraform plan, don't apply
  --help                      Show this help message

Quick Start (Week 1 - k0rdent Enterprise):
  $0 k0rdent john-doe --auto-approve

  This will automatically:
    1. Create S3 bucket for Terraform state
    2. Provision shared infrastructure (VPC, bastion) if not exists
    3. Provision k0s + k0rdent Enterprise management cluster
    4. Save SSH keys to config/keys/

Examples:
  $0 k0rdent john-doe                   # Week 1: k0rdent management cluster
  $0 metal3 john-doe                    # Week 2: Metal3/BMaaS lab
  $0 kubevirt john-doe --workers 3      # Week 3: KubeVirt/VMaaS lab
  $0 gpu cohort-2024-q1                 # Week 4-5: Shared GPU lab

EOF
    exit 1
}

check_prerequisites() {
    log_info "Checking prerequisites..."

    if ! command -v terraform &> /dev/null; then
        log_error "terraform is not installed. Please install Terraform 1.5+"
        exit 1
    fi

    if ! command -v aws &> /dev/null; then
        log_error "aws CLI is not installed. Please install AWS CLI"
        exit 1
    fi

    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Please run 'aws configure'"
        exit 1
    fi

    log_success "Prerequisites check passed"
}

load_config() {
    if [[ -f "$CONFIG_DIR/lab-config.env" ]]; then
        source "$CONFIG_DIR/lab-config.env"
        log_info "Loaded configuration from lab-config.env"
    fi

    # If no region set yet via --region flag, try saved config
    if [[ -z "$REGION" && -n "${LAB_REGION:-}" ]]; then
        REGION="$LAB_REGION"
        log_info "Using region from saved config: $REGION"
    fi
}

save_config() {
    mkdir -p "$CONFIG_DIR"
    cat > "$CONFIG_DIR/lab-config.env" <<EOF
# k0rdent Training Lab Configuration
# Auto-generated by lab-provision.sh

# AWS Region used for provisioning (last deployed region)
LAB_REGION="${REGION}"

# AWS Region where the S3 state bucket is located (stable across deployments)
LAB_BUCKET_REGION="${BUCKET_REGION}"

# Last updated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF
    log_info "Saved configuration to lab-config.env"
}

get_tfstate_bucket() {
    local account_id
    account_id=$(aws sts get-caller-identity --query Account --output text)
    echo "k0rdent-training-tfstate-${account_id}"
}

# Detect the actual AWS region of the S3 state bucket.
# The Terraform S3 backend region must match the bucket's real location,
# which may differ from the region where resources are being deployed.
get_bucket_region() {
    local bucket_name
    bucket_name=$(get_tfstate_bucket)
    local location
    location=$(aws s3api get-bucket-location --bucket "$bucket_name" \
        --query LocationConstraint --output text 2>/dev/null)
    # get-bucket-location returns "None" for us-east-1 (the original S3 region)
    if [[ "$location" == "None" || -z "$location" ]]; then
        echo "us-east-1"
    else
        echo "$location"
    fi
}

ensure_tfstate_bucket() {
    local bucket_name
    bucket_name=$(get_tfstate_bucket)

    if ! aws s3api head-bucket --bucket "$bucket_name" 2>/dev/null; then
        log_info "Creating Terraform state bucket: $bucket_name"

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

        BUCKET_REGION="$REGION"
        log_success "Created bucket: $bucket_name (region: $BUCKET_REGION)"
    else
        BUCKET_REGION=$(get_bucket_region)
        log_info "Using existing bucket: $bucket_name (region: $BUCKET_REGION)"
    fi
}

# Create images and artifacts S3 buckets if they don't exist.
# These are global buckets (created once in BUCKET_REGION, shared across regions).
# Managed by the script rather than Terraform to avoid cross-region API failures.
ensure_s3_buckets() {
    local account_id
    account_id=$(aws sts get-caller-identity --query Account --output text)

    for bucket_type in "images" "artifacts"; do
        local bucket_name="${PROJECT_NAME:-k0rdent-training}-${bucket_type}-${account_id}"

        if aws s3api head-bucket --bucket "$bucket_name" 2>/dev/null; then
            log_info "S3 bucket already exists: $bucket_name"
        else
            log_info "Creating S3 bucket: $bucket_name in ${BUCKET_REGION}..."

            if [[ "$BUCKET_REGION" == "us-east-1" ]]; then
                aws s3api create-bucket --bucket "$bucket_name" --region "$BUCKET_REGION"
            else
                aws s3api create-bucket --bucket "$bucket_name" --region "$BUCKET_REGION" \
                    --create-bucket-configuration LocationConstraint="$BUCKET_REGION"
            fi

            aws s3api put-bucket-encryption --bucket "$bucket_name" \
                --server-side-encryption-configuration \
                '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

            # Add lifecycle rule to artifacts bucket (expire after 30 days)
            if [[ "$bucket_type" == "artifacts" ]]; then
                aws s3api put-bucket-lifecycle-configuration --bucket "$bucket_name" \
                    --lifecycle-configuration '{"Rules":[{"ID":"expire-old-artifacts","Status":"Enabled","Filter":{},"Expiration":{"Days":30}}]}'
            fi

            log_success "Created bucket: $bucket_name"
        fi
    done
}

# Check if shared infrastructure exists by looking for VPC with our tag
check_shared_infrastructure() {
    local vpc_id
    vpc_id=$(aws ec2 describe-vpcs \
        --filters "Name=tag:Project,Values=k0rdent-training" \
        --query 'Vpcs[0].VpcId' --output text 2>/dev/null || echo "None")

    if [[ "$vpc_id" != "None" && -n "$vpc_id" ]]; then
        return 0  # Shared infra exists
    else
        return 1  # Shared infra does not exist
    fi
}

# Ensure bastion SSH key is available locally (fetch from S3 state if needed)
ensure_bastion_key() {
    local key_dir="$CONFIG_DIR/keys"
    local key_file="$key_dir/bastion-${REGION}.pem"

    if [[ -f "$key_file" ]] && [[ -s "$key_file" ]]; then
        return 0
    fi

    log_info "Bastion SSH key not found locally, retrieving from Terraform state..."
    local tfstate_bucket
    tfstate_bucket=$(get_tfstate_bucket)

    local ssh_key
    ssh_key=$(aws s3 cp "s3://${tfstate_bucket}/${REGION}/shared/terraform.tfstate" - 2>/dev/null \
        | jq -r '.outputs.bastion_ssh_private_key.value // empty' 2>/dev/null)

    if [[ -z "$ssh_key" ]]; then
        log_warn "Could not retrieve bastion SSH key from state"
        return 1
    fi

    mkdir -p "$key_dir"
    echo "$ssh_key" > "$key_file"
    chmod 600 "$key_file"
    log_success "Bastion SSH key saved to: $key_file"
}

# Auto-provision shared infrastructure if it doesn't exist
ensure_shared_infrastructure() {
    if check_shared_infrastructure; then
        log_info "Shared infrastructure already exists, skipping..."
        ensure_bastion_key || true
        return 0
    fi

    log_warn "Shared infrastructure not found. Provisioning automatically..."
    echo ""
    log_info "This creates: VPC, subnets, bastion host, S3 buckets, IAM roles"
    log_info "One-time cost: ~\$35/month (NAT Gateway)"
    echo ""

    # If not auto-approve, ask for confirmation
    if [[ "$AUTO_APPROVE" != "true" ]]; then
        read -p "Proceed with shared infrastructure setup? [y/N]: " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            log_error "Shared infrastructure is required. Please run with --auto-approve or confirm."
            exit 1
        fi
    fi

    # Temporarily set auto-approve for shared provisioning
    local original_auto_approve="$AUTO_APPROVE"
    AUTO_APPROVE="true"

    provision_shared

    AUTO_APPROVE="$original_auto_approve"

    echo ""
    log_success "Shared infrastructure ready! Continuing with your lab environment..."
    echo ""
}

provision_shared() {
    log_info "Provisioning shared infrastructure..."

    ensure_tfstate_bucket
    ensure_s3_buckets

    local env_dir="$TERRAFORM_DIR/environments/shared"
    local tfstate_bucket
    tfstate_bucket=$(get_tfstate_bucket)

    cd "$env_dir"

    # Initialize Terraform (reconfigure to handle different backends)
    # BUCKET_REGION = where the S3 bucket lives; REGION = where resources are deployed
    terraform init -reconfigure \
        -backend-config="bucket=${tfstate_bucket}" \
        -backend-config="key=${REGION}/shared/terraform.tfstate" \
        -backend-config="region=${BUCKET_REGION}"

    # Remove legacy S3 resources from state (now managed by script, not Terraform).
    # These state rm calls are no-ops if the resources aren't in state.
    terraform state rm 'module.shared_infra.data.aws_s3_bucket.tfstate' 2>/dev/null || true
    terraform state rm 'module.shared_infra.aws_s3_bucket.images' 2>/dev/null || true
    terraform state rm 'module.shared_infra.aws_s3_bucket.artifacts' 2>/dev/null || true
    terraform state rm 'module.shared_infra.aws_s3_bucket_lifecycle_configuration.artifacts' 2>/dev/null || true

    if [[ "$PLAN_ONLY" == "true" ]]; then
        terraform plan -var-file="terraform.tfvars" 2>/dev/null || terraform plan
        return 0
    fi

    local apply_args=""
    [[ "$AUTO_APPROVE" == "true" ]] && apply_args="-auto-approve"

    # Use terraform.tfvars if it exists, otherwise use CLI vars
    if [[ -f "terraform.tfvars" ]]; then
        terraform apply $apply_args -var-file="terraform.tfvars"
    else
        terraform apply $apply_args \
            -var="region=${REGION}" \
            -var="allowed_ssh_cidrs=${ALLOWED_SSH_CIDRS:-[\"0.0.0.0/0\"]}"
    fi

    # Save bastion SSH key (region-scoped — each region has its own bastion)
    local key_dir="$CONFIG_DIR/keys"
    mkdir -p "$key_dir"
    terraform output -raw bastion_ssh_private_key > "$key_dir/bastion-${REGION}.pem"
    chmod 600 "$key_dir/bastion-${REGION}.pem"

    log_success "Shared infrastructure provisioned!"
    log_info "VPC ID: $(terraform output -raw vpc_id)"
    log_info "Bastion IP: $(terraform output -raw bastion_public_ip)"
    log_info "Artifacts Bucket: $(terraform output -raw artifacts_bucket)"
    log_info "Bastion SSH key saved to: $key_dir/bastion-${REGION}.pem"

    # Save region to config for lab-connect.sh
    save_config
}

provision_metal3() {
    local engineer_id="$1"
    log_info "Provisioning Metal3 dev environment for $engineer_id..."

    ensure_tfstate_bucket
    ensure_shared_infrastructure

    local env_dir="$TERRAFORM_DIR/environments/metal3-dev"
    local tfstate_bucket
    tfstate_bucket=$(get_tfstate_bucket)

    cd "$env_dir"

    # Use -reconfigure to allow switching between different engineer_ids
    terraform init -reconfigure \
        -backend-config="bucket=${tfstate_bucket}" \
        -backend-config="key=${REGION}/metal3-dev/${engineer_id}/terraform.tfstate" \
        -backend-config="region=${BUCKET_REGION}"

    if [[ "$PLAN_ONLY" == "true" ]]; then
        terraform plan \
            -var="engineer_id=${engineer_id}" \
            -var="tfstate_bucket=${tfstate_bucket}" \
            -var="bucket_region=${BUCKET_REGION}" \
            -var="region=${REGION}" \
            -var="use_spot_instances=${USE_SPOT}"
        return 0
    fi

    local apply_args=""
    [[ "$AUTO_APPROVE" == "true" ]] && apply_args="-auto-approve"

    terraform apply $apply_args \
        -var="engineer_id=${engineer_id}" \
        -var="tfstate_bucket=${tfstate_bucket}" \
        -var="bucket_region=${BUCKET_REGION}" \
        -var="region=${REGION}" \
        -var="use_spot_instances=${USE_SPOT}"

    # Get instance ID and wait for it to be ready
    local instance_id
    instance_id=$(terraform output -raw controller_instance_id 2>/dev/null || echo "")
    if [[ -n "$instance_id" ]]; then
        wait_for_instance "$instance_id" 300
    fi

    # Save SSH key
    local key_dir="$CONFIG_DIR/keys"
    mkdir -p "$key_dir"
    terraform output -raw ssh_private_key > "$key_dir/${engineer_id}-metal3.pem"
    chmod 600 "$key_dir/${engineer_id}-metal3.pem"

    log_success "Metal3 dev environment provisioned for $engineer_id!"
    log_info "Controller IP: $(terraform output -raw controller_private_ip)"
    log_info "SSH key saved to: $key_dir/${engineer_id}-metal3.pem"
    log_info "Connect via: ./lab-connect.sh metal3 $engineer_id"
}

provision_kubevirt() {
    local engineer_id="$1"
    log_info "Provisioning KubeVirt lab environment for $engineer_id..."

    ensure_tfstate_bucket
    ensure_shared_infrastructure

    local env_dir="$TERRAFORM_DIR/environments/kubevirt-lab"
    local tfstate_bucket
    tfstate_bucket=$(get_tfstate_bucket)

    cd "$env_dir"

    terraform init -reconfigure \
        -backend-config="bucket=${tfstate_bucket}" \
        -backend-config="key=${REGION}/kubevirt-lab/${engineer_id}/terraform.tfstate" \
        -backend-config="region=${BUCKET_REGION}"

    if [[ "$PLAN_ONLY" == "true" ]]; then
        terraform plan \
            -var="engineer_id=${engineer_id}" \
            -var="tfstate_bucket=${tfstate_bucket}" \
            -var="bucket_region=${BUCKET_REGION}" \
            -var="region=${REGION}" \
            -var="worker_count=${WORKER_COUNT}" \
            -var="use_spot_instances=${USE_SPOT}"
        return 0
    fi

    local apply_args=""
    [[ "$AUTO_APPROVE" == "true" ]] && apply_args="-auto-approve"

    terraform apply $apply_args \
        -var="engineer_id=${engineer_id}" \
        -var="tfstate_bucket=${tfstate_bucket}" \
        -var="bucket_region=${BUCKET_REGION}" \
        -var="region=${REGION}" \
        -var="worker_count=${WORKER_COUNT}" \
        -var="use_spot_instances=${USE_SPOT}"

    local key_dir="$CONFIG_DIR/keys"
    mkdir -p "$key_dir"
    terraform output -raw ssh_private_key > "$key_dir/${engineer_id}-kubevirt.pem"
    chmod 600 "$key_dir/${engineer_id}-kubevirt.pem"

    log_success "KubeVirt lab environment provisioned for $engineer_id!"
    log_info "Controller IP: $(terraform output -raw controller_private_ip)"
    log_info "Worker IPs: $(terraform output -json worker_private_ips)"
    log_info "SSH key saved to: $key_dir/${engineer_id}-kubevirt.pem"
}

provision_gpu() {
    local session_id="$1"
    local advanced="${2:-false}"

    if [[ "$advanced" == "true" ]]; then
        log_info "Provisioning advanced GPU lab (8x A100) for session $session_id..."
    else
        log_info "Provisioning shared GPU lab (4x V100) for session $session_id..."
    fi

    ensure_tfstate_bucket
    ensure_shared_infrastructure

    local env_dir="$TERRAFORM_DIR/environments/gpu-lab"
    local tfstate_bucket
    tfstate_bucket=$(get_tfstate_bucket)

    cd "$env_dir"

    terraform init -reconfigure \
        -backend-config="bucket=${tfstate_bucket}" \
        -backend-config="key=${REGION}/gpu-lab/${session_id}/terraform.tfstate" \
        -backend-config="region=${BUCKET_REGION}"

    local enable_advanced="false"
    [[ "$advanced" == "true" ]] && enable_advanced="true"

    if [[ "$PLAN_ONLY" == "true" ]]; then
        terraform plan \
            -var="lab_session_id=${session_id}" \
            -var="tfstate_bucket=${tfstate_bucket}" \
            -var="bucket_region=${BUCKET_REGION}" \
            -var="region=${REGION}" \
            -var="enable_advanced_gpu=${enable_advanced}" \
            -var="use_spot_instances=${USE_SPOT}"
        return 0
    fi

    local apply_args=""
    [[ "$AUTO_APPROVE" == "true" ]] && apply_args="-auto-approve"

    terraform apply $apply_args \
        -var="lab_session_id=${session_id}" \
        -var="tfstate_bucket=${tfstate_bucket}" \
        -var="bucket_region=${BUCKET_REGION}" \
        -var="region=${REGION}" \
        -var="enable_advanced_gpu=${enable_advanced}" \
        -var="use_spot_instances=${USE_SPOT}"

    local key_dir="$CONFIG_DIR/keys"
    mkdir -p "$key_dir"
    terraform output -raw ssh_private_key > "$key_dir/${session_id}-gpu.pem"
    chmod 600 "$key_dir/${session_id}-gpu.pem"

    log_success "GPU lab environment provisioned for session $session_id!"

    if [[ -n "$(terraform output -raw shared_gpu_private_ip 2>/dev/null)" ]]; then
        log_info "Shared GPU IP: $(terraform output -raw shared_gpu_private_ip)"
    fi

    if [[ "$advanced" == "true" ]] && [[ -n "$(terraform output -raw advanced_gpu_private_ip 2>/dev/null)" ]]; then
        log_info "Advanced GPU IP: $(terraform output -raw advanced_gpu_private_ip)"
    fi

    log_info "SSH key saved to: $key_dir/${session_id}-gpu.pem"
}

provision_k0rdent() {
    local engineer_id="$1"
    log_info "Provisioning k0rdent Enterprise management cluster for $engineer_id..."

    ensure_tfstate_bucket
    ensure_shared_infrastructure

    local env_dir="$TERRAFORM_DIR/environments/k0rdent"
    local tfstate_bucket
    tfstate_bucket=$(get_tfstate_bucket)

    cd "$env_dir"

    terraform init -reconfigure \
        -backend-config="bucket=${tfstate_bucket}" \
        -backend-config="key=${REGION}/k0rdent/${engineer_id}/terraform.tfstate" \
        -backend-config="region=${BUCKET_REGION}"

    if [[ "$PLAN_ONLY" == "true" ]]; then
        terraform plan \
            -var="engineer_id=${engineer_id}" \
            -var="tfstate_bucket=${tfstate_bucket}" \
            -var="bucket_region=${BUCKET_REGION}" \
            -var="region=${REGION}" \
            -var="node_count=${NODE_COUNT}"
        return 0
    fi

    local apply_args=""
    [[ "$AUTO_APPROVE" == "true" ]] && apply_args="-auto-approve"

    terraform apply $apply_args \
        -var="engineer_id=${engineer_id}" \
        -var="tfstate_bucket=${tfstate_bucket}" \
        -var="bucket_region=${BUCKET_REGION}" \
        -var="region=${REGION}" \
        -var="node_count=${NODE_COUNT}"

    # Get instance ID and wait for it to be ready
    local instance_id
    instance_id=$(terraform output -json mgmt_node_ids 2>/dev/null | jq -r '.[0]' || echo "")
    if [[ -n "$instance_id" && "$instance_id" != "null" ]]; then
        wait_for_instance "$instance_id" 600  # 10 min for k0rdent setup
    fi

    # Save SSH key
    local key_dir="$CONFIG_DIR/keys"
    mkdir -p "$key_dir"
    terraform output -raw ssh_private_key > "$key_dir/${engineer_id}-k0rdent.pem"
    chmod 600 "$key_dir/${engineer_id}-k0rdent.pem"

    log_success "k0rdent Enterprise management cluster provisioned for $engineer_id!"
    log_info "Primary node IP: $(terraform output -raw primary_node_private_ip)"
    log_info "SSH key saved to: $key_dir/${engineer_id}-k0rdent.pem"
    log_info "Connect via: ./lab-connect.sh k0rdent $engineer_id"
    echo ""
    log_info "k0rdent initialization is running in the background."
    log_info "After connecting, check progress with: tail -f /var/log/k0rdent-init.log"
    log_info "Once complete, access k0rdent UI:"
    log_info "  URL:      $(terraform output -raw ui_url 2>/dev/null || echo 'run: terraform output ui_url')"
    log_info "  Password: run: terraform output ui_password"
}

# Default values
REGION=""  # Resolved after argument parsing
BUCKET_REGION=""  # Detected from S3 bucket; used for backend-config
USE_SPOT="false"
WORKER_COUNT="2"
NODE_COUNT="1"
AUTO_APPROVE="false"
PLAN_ONLY="false"

# Parse arguments
[[ $# -eq 0 ]] && usage

COMMAND=""
IDENTIFIER=""

while [[ $# -gt 0 ]]; do
    case $1 in
        shared|k0rdent|metal3|kubevirt|gpu|gpu-advanced)
            # Note: 'shared' is kept for manual/advanced use but auto-provisioned when needed
            COMMAND="$1"
            shift
            if [[ "$COMMAND" != "shared" ]] && [[ $# -gt 0 ]] && [[ ! "$1" =~ ^-- ]]; then
                IDENTIFIER="$1"
                shift
            fi
            ;;
        --region)
            REGION="$2"
            shift 2
            ;;
        --spot)
            USE_SPOT="true"
            shift
            ;;
        --no-spot)
            USE_SPOT="false"
            shift
            ;;
        --workers)
            WORKER_COUNT="$2"
            shift 2
            ;;
        --nodes)
            NODE_COUNT="$2"
            shift 2
            ;;
        --auto-approve)
            AUTO_APPROVE="true"
            shift
            ;;
        --plan-only)
            PLAN_ONLY="true"
            shift
            ;;
        --help|-h)
            usage
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            ;;
    esac
done

# Validate
if [[ -z "$COMMAND" ]]; then
    log_error "No command specified"
    usage
fi

if [[ "$COMMAND" != "shared" ]] && [[ -z "$IDENTIFIER" ]]; then
    log_error "Identifier required for $COMMAND"
    usage
fi

# Execute
check_prerequisites
load_config

# Resolve region: --region flag already set REGION during arg parsing.
# Otherwise try env vars, then saved config (loaded above), then AWS CLI default.
if [[ -z "$REGION" ]]; then
    REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-}}"
fi
if [[ -z "$REGION" ]]; then
    REGION=$(aws configure get region 2>/dev/null || true)
fi
if [[ -z "$REGION" ]]; then
    log_error "No AWS region specified. Use one of:"
    log_error "  --region <region>              (e.g. --region eu-west-1)"
    log_error "  export AWS_REGION=<region>     (environment variable)"
    log_error "  aws configure set region <region>  (AWS CLI default)"
    exit 1
fi
log_info "Using AWS region: $REGION"

# Migrate legacy (non-region-scoped) state keys to the new format.
# Runs automatically on first use after the multi-region update.
migrate_legacy_state_keys() {
    local tfstate_bucket
    tfstate_bucket=$(get_tfstate_bucket)

    # Only migrate if the bucket exists
    if ! aws s3api head-bucket --bucket "$tfstate_bucket" 2>/dev/null; then
        return 0
    fi

    # Check if legacy shared state exists and new one does not
    if aws s3api head-object --bucket "$tfstate_bucket" --key "shared/terraform.tfstate" &>/dev/null; then
        if ! aws s3api head-object --bucket "$tfstate_bucket" --key "${REGION}/shared/terraform.tfstate" &>/dev/null; then
            log_info "Migrating legacy state key: shared/ -> ${REGION}/shared/"
            aws s3 cp "s3://${tfstate_bucket}/shared/terraform.tfstate" \
                "s3://${tfstate_bucket}/${REGION}/shared/terraform.tfstate" --quiet
            log_success "Migrated shared infrastructure state to region-scoped key"
        fi
    fi

    # Migrate lab-type state keys for the current identifier
    if [[ -n "${IDENTIFIER:-}" ]]; then
        local lab_prefixes=("k0rdent" "metal3-dev" "kubevirt-lab" "gpu-lab")
        for prefix in "${lab_prefixes[@]}"; do
            local old_key="${prefix}/${IDENTIFIER}/terraform.tfstate"
            local new_key="${REGION}/${prefix}/${IDENTIFIER}/terraform.tfstate"
            if aws s3api head-object --bucket "$tfstate_bucket" --key "$old_key" &>/dev/null; then
                if ! aws s3api head-object --bucket "$tfstate_bucket" --key "$new_key" &>/dev/null; then
                    log_info "Migrating legacy state key: ${prefix}/${IDENTIFIER}/ -> ${REGION}/${prefix}/${IDENTIFIER}/"
                    aws s3 cp "s3://${tfstate_bucket}/${old_key}" \
                        "s3://${tfstate_bucket}/${new_key}" --quiet
                    log_success "Migrated ${prefix} state to region-scoped key"
                fi
            fi
        done
    fi
}

migrate_legacy_state_keys

case $COMMAND in
    shared)
        provision_shared
        ;;
    k0rdent)
        provision_k0rdent "$IDENTIFIER"
        ;;
    metal3)
        provision_metal3 "$IDENTIFIER"
        ;;
    kubevirt)
        provision_kubevirt "$IDENTIFIER"
        ;;
    gpu)
        provision_gpu "$IDENTIFIER"
        ;;
    gpu-advanced)
        provision_gpu "$IDENTIFIER" "true"
        ;;
esac
