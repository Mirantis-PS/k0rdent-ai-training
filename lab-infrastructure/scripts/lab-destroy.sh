#!/bin/bash
# k0rdent Training Lab Destroy Script
# Usage: ./lab-destroy.sh <lab-type> <identifier> [options]

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
k0rdent Training Lab Destroy Script

Usage: $0 <lab-type> <identifier> [options]

Lab Types:
  shared                      Destroy shared infrastructure (CAUTION!)
  k0rdent <engineer-id>       Destroy k0rdent management cluster
  metal3 <engineer-id>        Destroy Metal3 dev environment
  kubevirt <engineer-id>      Destroy KubeVirt lab environment
  gpu <session-id>            Destroy GPU lab environment
  all-engineer <engineer-id>  Destroy all environments for an engineer
  all-session <session-id>    Destroy all session-based environments

Options:
  --region <region>           AWS region (default: us-east-1)
  --auto-approve              Skip confirmation prompts
  --keep-state                Keep Terraform state files
  --help                      Show this help message

Examples:
  $0 k0rdent engineer-01
  $0 metal3 engineer-01
  $0 kubevirt engineer-01 --auto-approve
  $0 gpu cohort-2024-q1
  $0 all-engineer engineer-01

WARNING: Destroying 'shared' infrastructure will affect ALL lab environments!

EOF
    exit 1
}

get_tfstate_bucket() {
    local account_id
    account_id=$(aws sts get-caller-identity --query Account --output text)
    echo "k0rdent-training-tfstate-${account_id}"
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

cleanup_local_files() {
    local identifier="$1"
    local lab_type="$2"

    # Remove SSH key
    local key_file="$CONFIG_DIR/keys/${identifier}-${lab_type}.pem"
    if [[ -f "$key_file" ]]; then
        rm -f "$key_file"
        log_info "Removed SSH key: $key_file"
    fi

    # Remove kubeconfig
    local kubeconfig="$CONFIG_DIR/kubeconfig/${identifier}.kubeconfig"
    if [[ -f "$kubeconfig" ]]; then
        rm -f "$kubeconfig"
        log_info "Removed kubeconfig: $kubeconfig"
    fi
}

destroy_environment() {
    local lab_type="$1"
    local identifier="$2"
    local state_key="$3"

    local env_dir="$TERRAFORM_DIR/environments/${lab_type}"
    local tfstate_bucket
    tfstate_bucket=$(get_tfstate_bucket)

    cd "$env_dir"

    log_info "Initializing Terraform..."
    terraform init \
        -backend-config="bucket=${tfstate_bucket}" \
        -backend-config="key=${state_key}" \
        -backend-config="region=${REGION}" &>/dev/null || true

    # Check if state exists
    if ! terraform state list &>/dev/null; then
        log_warn "No state found for $identifier. Environment may not exist."
        return 0
    fi

    log_info "Destroying $lab_type environment: $identifier"

    local destroy_args=""
    [[ "$AUTO_APPROVE" == "true" ]] && destroy_args="-auto-approve"

    # Get required variables
    case $lab_type in
        k0rdent)
            terraform destroy $destroy_args \
                -var="engineer_id=${identifier}" \
                -var="tfstate_bucket=${tfstate_bucket}" \
                -var="region=${REGION}"
            cleanup_local_files "$identifier" "k0rdent"
            ;;
        metal3-dev)
            terraform destroy $destroy_args \
                -var="engineer_id=${identifier}" \
                -var="tfstate_bucket=${tfstate_bucket}" \
                -var="region=${REGION}"
            cleanup_local_files "$identifier" "metal3"
            ;;
        kubevirt-lab)
            terraform destroy $destroy_args \
                -var="engineer_id=${identifier}" \
                -var="tfstate_bucket=${tfstate_bucket}" \
                -var="region=${REGION}"
            cleanup_local_files "$identifier" "kubevirt"
            ;;
        gpu-lab)
            terraform destroy $destroy_args \
                -var="lab_session_id=${identifier}" \
                -var="tfstate_bucket=${tfstate_bucket}" \
                -var="region=${REGION}"
            cleanup_local_files "$identifier" "gpu"
            ;;
        shared)
            terraform destroy $destroy_args \
                -var="region=${REGION}"
            ;;
    esac

    # Optionally remove state
    if [[ "$KEEP_STATE" != "true" ]]; then
        log_info "State will be removed from S3 by Terraform"
    fi

    log_success "Environment $identifier destroyed!"
}

destroy_shared() {
    confirm_destroy "SHARED INFRASTRUCTURE (VPC, S3, IAM)"

    echo ""
    log_warn "This will destroy all shared resources!"
    log_warn "All lab environments will become non-functional!"
    echo ""

    read -p "Are you ABSOLUTELY sure? Type 'yes-destroy-shared': " final_confirm

    if [[ "$final_confirm" != "yes-destroy-shared" ]]; then
        log_warn "Destruction cancelled"
        exit 0
    fi

    destroy_environment "shared" "shared" "shared/terraform.tfstate"
}

destroy_k0rdent() {
    local engineer_id="$1"
    confirm_destroy "k0rdent management cluster for $engineer_id"
    destroy_environment "k0rdent" "$engineer_id" "k0rdent/${engineer_id}/terraform.tfstate"
}

destroy_metal3() {
    local engineer_id="$1"
    confirm_destroy "Metal3 dev environment for $engineer_id"
    destroy_environment "metal3-dev" "$engineer_id" "metal3-dev/${engineer_id}/terraform.tfstate"
}

destroy_kubevirt() {
    local engineer_id="$1"
    confirm_destroy "KubeVirt lab environment for $engineer_id"
    destroy_environment "kubevirt-lab" "$engineer_id" "kubevirt-lab/${engineer_id}/terraform.tfstate"
}

destroy_gpu() {
    local session_id="$1"
    confirm_destroy "GPU lab environment for $session_id"
    destroy_environment "gpu-lab" "$session_id" "gpu-lab/${session_id}/terraform.tfstate"
}

destroy_all_engineer() {
    local engineer_id="$1"

    confirm_destroy "ALL environments for $engineer_id"

    log_info "Destroying all environments for $engineer_id..."

    # Destroy k0rdent management cluster
    log_info "Checking k0rdent environment..."
    destroy_environment "k0rdent" "$engineer_id" "k0rdent/${engineer_id}/terraform.tfstate" || true

    # Destroy Metal3
    log_info "Checking Metal3 environment..."
    destroy_environment "metal3-dev" "$engineer_id" "metal3-dev/${engineer_id}/terraform.tfstate" || true

    # Destroy KubeVirt
    log_info "Checking KubeVirt environment..."
    destroy_environment "kubevirt-lab" "$engineer_id" "kubevirt-lab/${engineer_id}/terraform.tfstate" || true

    log_success "All environments for $engineer_id destroyed!"
}

destroy_all_session() {
    local session_id="$1"

    confirm_destroy "ALL environments for session $session_id"

    log_info "Destroying all environments for session $session_id..."

    # Destroy GPU lab
    destroy_environment "gpu-lab" "$session_id" "gpu-lab/${session_id}/terraform.tfstate" || true

    log_success "All environments for session $session_id destroyed!"
}

# Default values
REGION="${AWS_REGION:-us-east-1}"
AUTO_APPROVE="false"
KEEP_STATE="false"

# Parse arguments
COMMAND=""
IDENTIFIER=""

while [[ $# -gt 0 ]]; do
    case $1 in
        shared|k0rdent|metal3|kubevirt|gpu|all-engineer|all-session)
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
        --auto-approve)
            AUTO_APPROVE="true"
            shift
            ;;
        --keep-state)
            KEEP_STATE="true"
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
    log_error "Command required"
    usage
fi

if [[ "$COMMAND" != "shared" ]] && [[ -z "$IDENTIFIER" ]]; then
    log_error "Identifier required"
    usage
fi

# Execute
case $COMMAND in
    shared)
        destroy_shared
        ;;
    k0rdent)
        destroy_k0rdent "$IDENTIFIER"
        ;;
    metal3)
        destroy_metal3 "$IDENTIFIER"
        ;;
    kubevirt)
        destroy_kubevirt "$IDENTIFIER"
        ;;
    gpu)
        destroy_gpu "$IDENTIFIER"
        ;;
    all-engineer)
        destroy_all_engineer "$IDENTIFIER"
        ;;
    all-session)
        destroy_all_session "$IDENTIFIER"
        ;;
esac
