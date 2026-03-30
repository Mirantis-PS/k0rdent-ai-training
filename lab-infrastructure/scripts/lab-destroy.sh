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
    echo "k0rdent-lab-${engineer_id}-${account_id}-${REGION}"
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

get_state_output() {
    local bucket="$1"
    local output_name="$2"
    aws s3 cp "s3://${bucket}/terraform.tfstate" - 2>/dev/null \
        | jq -r ".outputs.${output_name}.value // empty" 2>/dev/null
}

# Clean up CCM-provisioned LoadBalancers before destroying infrastructure.
# The AWS CCM creates ELBs at runtime (not managed by Terraform). If we
# destroy the EC2 instance first, the CCM pod dies and the ELB is orphaned.
# The fix: SSH in and delete the Gateway/Services so CCM cleans up the ELB.
cleanup_load_balancers() {
    local engineer_id="$1"
    local bucket="$2"

    log_info "Cleaning up CCM-provisioned LoadBalancers..."

    # Get connection details from Terraform state
    local bastion_ip mgmt_ip
    bastion_ip=$(get_state_output "$bucket" "bastion_public_ip")
    mgmt_ip=$(get_state_output "$bucket" "primary_node_private_ip")

    if [[ -z "$bastion_ip" || -z "$mgmt_ip" ]]; then
        log_warn "Could not get IPs from state. Skipping LB cleanup."
        return 0
    fi

    # Get SSH keys
    local mgmt_key="$CONFIG_DIR/keys/${engineer_id}-k0rdent.pem"
    local bastion_key="$CONFIG_DIR/keys/${engineer_id}-bastion.pem"

    if [[ ! -f "$mgmt_key" || ! -f "$bastion_key" ]]; then
        # Try to retrieve from state
        local ssh_key bastion_ssh_key
        ssh_key=$(get_state_output "$bucket" "ssh_private_key")
        bastion_ssh_key=$(get_state_output "$bucket" "bastion_ssh_private_key")

        if [[ -n "$ssh_key" ]]; then
            mkdir -p "$CONFIG_DIR/keys"
            echo "$ssh_key" > "$mgmt_key"
            chmod 600 "$mgmt_key"
        fi
        if [[ -n "$bastion_ssh_key" ]]; then
            mkdir -p "$CONFIG_DIR/keys"
            echo "$bastion_ssh_key" > "$bastion_key"
            chmod 600 "$bastion_key"
        fi
    fi

    if [[ ! -f "$mgmt_key" || ! -f "$bastion_key" ]]; then
        log_warn "SSH keys not available. Skipping LB cleanup."
        return 0
    fi

    local ssh_opts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=10"
    local proxy_cmd="ssh ${ssh_opts} -i ${bastion_key} -W %h:%p ec2-user@${bastion_ip}"

    # Delete Gateway resources so CCM removes the ELB
    log_info "Deleting Gateway API resources (triggers CCM to remove ELB)..."
    ssh ${ssh_opts} -i "$mgmt_key" -o "ProxyCommand=${proxy_cmd}" ubuntu@"${mgmt_ip}" \
        'export KUBECONFIG=/home/ubuntu/.kube/config
         kubectl delete gateway --all -n kcm-system --timeout=60s 2>/dev/null || true
         kubectl delete httproute --all -n kcm-system --timeout=30s 2>/dev/null || true
         kubectl delete gatewayclass --all --timeout=30s 2>/dev/null || true
         # Wait for CCM to finish deleting the ELB
         echo "Waiting for LoadBalancer cleanup..."
         for i in $(seq 1 24); do
             LB_COUNT=$(kubectl get svc -A --field-selector spec.type=LoadBalancer --no-headers 2>/dev/null | wc -l)
             if [ "$LB_COUNT" -eq 0 ]; then
                 echo "All LoadBalancers cleaned up"
                 break
             fi
             echo -n "."
             sleep 5
         done' 2>/dev/null || log_warn "Could not SSH to clean up LBs (instance may already be down)"

    log_success "LoadBalancer cleanup complete"
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

    # Clean up CCM-provisioned LoadBalancers BEFORE destroying infrastructure
    cleanup_load_balancers "$engineer_id" "$bucket"

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
