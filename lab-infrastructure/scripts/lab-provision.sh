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

usage() {
    cat <<EOF
k0rdent Training Lab Provisioning Script

Usage: $0 <command> [options]

Commands:
  shared                      Provision shared infrastructure (VPC, S3, IAM)
  metal3 <engineer-id>        Provision Metal3 dev environment for an engineer
  kubevirt <engineer-id>      Provision KubeVirt lab environment for an engineer
  gpu <session-id>            Provision GPU lab environment for a session
  gpu-advanced <session-id>   Provision advanced GPU lab (8x A100) for Lab 3.3

Options:
  --region <region>           AWS region (default: us-east-1)
  --spot                      Use spot instances (default: true)
  --no-spot                   Use on-demand instances
  --workers <n>               Number of workers (kubevirt only, default: 2)
  --auto-approve              Skip confirmation prompts
  --plan-only                 Only show Terraform plan, don't apply
  --help                      Show this help message

Examples:
  $0 shared
  $0 metal3 engineer-01
  $0 kubevirt engineer-01 --workers 3
  $0 gpu cohort-2024-q1
  $0 gpu-advanced cohort-2024-q1 --no-spot

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
}

get_tfstate_bucket() {
    local account_id
    account_id=$(aws sts get-caller-identity --query Account --output text)
    echo "k0rdent-training-tfstate-${account_id}"
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

        log_success "Created bucket: $bucket_name"
    else
        log_info "Using existing bucket: $bucket_name"
    fi
}

provision_shared() {
    log_info "Provisioning shared infrastructure..."

    ensure_tfstate_bucket

    local env_dir="$TERRAFORM_DIR/environments/shared"
    local tfstate_bucket
    tfstate_bucket=$(get_tfstate_bucket)

    cd "$env_dir"

    # Initialize Terraform (reconfigure to handle different backends)
    terraform init -reconfigure \
        -backend-config="bucket=${tfstate_bucket}" \
        -backend-config="key=shared/terraform.tfstate" \
        -backend-config="region=${REGION}"

    if [[ "$PLAN_ONLY" == "true" ]]; then
        terraform plan -var-file="terraform.tfvars" 2>/dev/null || terraform plan
        return 0
    fi

    local apply_args=""
    [[ "$AUTO_APPROVE" == "true" ]] && apply_args="-auto-approve"

    terraform apply $apply_args \
        -var="region=${REGION}" \
        -var="allowed_ssh_cidrs=${ALLOWED_SSH_CIDRS:-[]}"

    log_success "Shared infrastructure provisioned!"
    log_info "VPC ID: $(terraform output -raw vpc_id)"
    log_info "Artifacts Bucket: $(terraform output -raw artifacts_bucket)"
}

provision_metal3() {
    local engineer_id="$1"
    log_info "Provisioning Metal3 dev environment for $engineer_id..."

    ensure_tfstate_bucket

    local env_dir="$TERRAFORM_DIR/environments/metal3-dev"
    local tfstate_bucket
    tfstate_bucket=$(get_tfstate_bucket)

    cd "$env_dir"

    # Use -reconfigure to allow switching between different engineer_ids
    terraform init -reconfigure \
        -backend-config="bucket=${tfstate_bucket}" \
        -backend-config="key=metal3-dev/${engineer_id}/terraform.tfstate" \
        -backend-config="region=${REGION}"

    if [[ "$PLAN_ONLY" == "true" ]]; then
        terraform plan \
            -var="engineer_id=${engineer_id}" \
            -var="tfstate_bucket=${tfstate_bucket}" \
            -var="region=${REGION}" \
            -var="use_spot_instances=${USE_SPOT}"
        return 0
    fi

    local apply_args=""
    [[ "$AUTO_APPROVE" == "true" ]] && apply_args="-auto-approve"

    terraform apply $apply_args \
        -var="engineer_id=${engineer_id}" \
        -var="tfstate_bucket=${tfstate_bucket}" \
        -var="region=${REGION}" \
        -var="use_spot_instances=${USE_SPOT}"

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

    local env_dir="$TERRAFORM_DIR/environments/kubevirt-lab"
    local tfstate_bucket
    tfstate_bucket=$(get_tfstate_bucket)

    cd "$env_dir"

    terraform init -reconfigure \
        -backend-config="bucket=${tfstate_bucket}" \
        -backend-config="key=kubevirt-lab/${engineer_id}/terraform.tfstate" \
        -backend-config="region=${REGION}"

    if [[ "$PLAN_ONLY" == "true" ]]; then
        terraform plan \
            -var="engineer_id=${engineer_id}" \
            -var="tfstate_bucket=${tfstate_bucket}" \
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

    local env_dir="$TERRAFORM_DIR/environments/gpu-lab"
    local tfstate_bucket
    tfstate_bucket=$(get_tfstate_bucket)

    cd "$env_dir"

    terraform init -reconfigure \
        -backend-config="bucket=${tfstate_bucket}" \
        -backend-config="key=gpu-lab/${session_id}/terraform.tfstate" \
        -backend-config="region=${REGION}"

    local enable_advanced="false"
    [[ "$advanced" == "true" ]] && enable_advanced="true"

    if [[ "$PLAN_ONLY" == "true" ]]; then
        terraform plan \
            -var="lab_session_id=${session_id}" \
            -var="tfstate_bucket=${tfstate_bucket}" \
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

# Default values
REGION="${AWS_REGION:-eu-west-1}"
USE_SPOT="true"
WORKER_COUNT="2"
AUTO_APPROVE="false"
PLAN_ONLY="false"

# Parse arguments
[[ $# -eq 0 ]] && usage

COMMAND=""
IDENTIFIER=""

while [[ $# -gt 0 ]]; do
    case $1 in
        shared|metal3|kubevirt|gpu|gpu-advanced)
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

case $COMMAND in
    shared)
        provision_shared
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
