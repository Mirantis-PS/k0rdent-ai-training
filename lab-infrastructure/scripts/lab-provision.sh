#!/bin/bash
# k0rdent Training Lab Provisioning Script (Per-Student Model)
# Usage: ./lab-provision.sh <your-name> [options]

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
    local max_wait="${2:-300}"
    local start_time=$(date +%s)

    log_info "Waiting for instance $instance_id to be running..."

    while true; do
        local state
        state=$(aws ec2 describe-instances --region "$REGION" --instance-ids "$instance_id" \
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

    log_info "Waiting for instance status checks..."
    while true; do
        local status
        status=$(aws ec2 describe-instance-status --region "$REGION" --instance-ids "$instance_id" \
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
k0rdent Training Lab Provisioning Script (Per-Student)

Usage: $0 <your-name> [options]

Arguments:
  <your-name>                 Your unique identifier (e.g., 'john-doe', 'crusu')

Options:
  --region <region>           AWS region (required on first run)
  --gpu                       Enable GPU lab environment
  --metal3                    Enable Metal3 dev environment
  --kubevirt                  Enable KubeVirt lab environment
  --nodes <n>                 Number of k0rdent management nodes (default: 1)
  --auto-approve              Skip confirmation prompts
  --plan-only                 Show plan without applying
  --help                      Show this help message

Quick Start (Week 1):
  $0 john-doe --region us-east-1 --auto-approve

  This will automatically:
    1. Create per-student S3 bucket for state/artifacts
    2. Provision VPC, bastion, IAM, k0rdent cluster
    3. Save SSH keys to config/keys/

Examples:
  $0 john-doe --region us-east-1                  # Week 1: base lab
  $0 john-doe --gpu                               # Add GPU lab
  $0 john-doe --metal3 --kubevirt                  # Add Metal3 + KubeVirt

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

# Default values
REGION=""
NODE_COUNT="1"
ENABLE_GPU="false"
ENABLE_METAL3="false"
ENABLE_KUBEVIRT="false"
AUTO_APPROVE="false"
PLAN_ONLY="false"
IDENTIFIER=""

# Parse arguments
[[ $# -eq 0 ]] && usage

while [[ $# -gt 0 ]]; do
    case $1 in
        --region)
            REGION="$2"
            shift 2
            ;;
        --gpu)
            ENABLE_GPU="true"
            shift
            ;;
        --metal3)
            ENABLE_METAL3="true"
            shift
            ;;
        --kubevirt)
            ENABLE_KUBEVIRT="true"
            shift
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
        -*)
            log_error "Unknown option: $1"
            usage
            ;;
        *)
            if [[ -z "$IDENTIFIER" ]]; then
                IDENTIFIER="$1"
            else
                log_error "Unexpected argument: $1"
                usage
            fi
            shift
            ;;
    esac
done

# Validate
if [[ -z "$IDENTIFIER" ]]; then
    log_error "Your name/identifier is required"
    usage
fi

# Load saved config
if [[ -f "$CONFIG_DIR/lab-config.env" ]]; then
    source "$CONFIG_DIR/lab-config.env"
fi

# Resolve region
if [[ -z "$REGION" && -n "${LAB_REGION:-}" ]]; then
    REGION="$LAB_REGION"
fi
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

# Execute
check_prerequisites
provision_lab "$IDENTIFIER"
