#!/bin/bash
# k0rdent Training Lab Destroy Script (Per-Student Model)
# Usage: ./lab-destroy.sh <your-name> [options]

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
k0rdent Training Lab Destroy Script (Per-Student)

Usage: $0 <your-name> [options]

Arguments:
  <your-name>                 Your unique identifier (same as used in lab-provision.sh)

Options:
  --region <region>           AWS region (auto-detected from saved config)
  --auto-approve              Skip confirmation prompts
  --delete-bucket             Also delete the student's S3 bucket
  --help                      Show this help message

Examples:
  $0 john-doe
  $0 john-doe --auto-approve
  $0 john-doe --auto-approve --delete-bucket

EOF
    exit 1
}

get_student_bucket() {
    local engineer_id="$1"
    local account_id
    account_id=$(aws sts get-caller-identity --query Account --output text)
    echo "k0rdent-lab-${engineer_id}-${account_id}"
}

confirm_destroy() {
    local env_name="$1"

    if [[ "$AUTO_APPROVE" == "true" ]]; then
        return 0
    fi

    echo ""
    echo -e "${RED}WARNING: You are about to destroy: $env_name${NC}"
    echo ""
    read -p "Type 'destroy' to confirm: " confirmation

    if [[ "$confirmation" != "destroy" ]]; then
        log_warn "Destruction cancelled"
        exit 0
    fi
}

destroy_lab() {
    local engineer_id="$1"
    local bucket
    bucket=$(get_student_bucket "$engineer_id")

    confirm_destroy "all lab resources for $engineer_id"

    local env_dir="$TERRAFORM_DIR/environments/student-lab"
    cd "$env_dir"

    log_info "Initializing Terraform..."
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

# Load config if exists
if [[ -f "$CONFIG_DIR/lab-config.env" ]]; then
    source "$CONFIG_DIR/lab-config.env"
fi

# Default values
REGION=""
AUTO_APPROVE="false"
DELETE_BUCKET="false"
IDENTIFIER=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --region)
            REGION="$2"
            shift 2
            ;;
        --auto-approve)
            AUTO_APPROVE="true"
            shift
            ;;
        --delete-bucket)
            DELETE_BUCKET="true"
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
    log_error "No AWS region specified. Use --region or set AWS_REGION"
    exit 1
fi
log_info "Using AWS region: $REGION"

# Execute
destroy_lab "$IDENTIFIER"
