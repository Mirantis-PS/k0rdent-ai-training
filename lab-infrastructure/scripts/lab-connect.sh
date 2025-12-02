#!/bin/bash
# k0rdent Training Lab Connection Script
# Usage: ./lab-connect.sh <lab-type> <identifier> [options]

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
k0rdent Training Lab Connection Script

Usage: $0 <lab-type> <identifier> [options]

Lab Types:
  metal3 <engineer-id>        Connect to Metal3 dev environment
  kubevirt <engineer-id>      Connect to KubeVirt lab controller
  gpu <session-id>            Connect to GPU lab instance

Options:
  --region <region>           AWS region (default: us-east-1)
  --bastion <ip>              Bastion host IP for jump connection
  --worker <n>                Connect to specific worker (kubevirt)
  --advanced                  Connect to advanced GPU (8x A100)
  --tunnel <local:remote>     Create SSH tunnel (e.g., 8080:80)
  --copy-kubeconfig           Copy kubeconfig to local machine
  --help                      Show this help message

Examples:
  $0 metal3 engineer-01
  $0 kubevirt engineer-01 --worker 0
  $0 gpu cohort-2024-q1
  $0 gpu cohort-2024-q1 --advanced
  $0 kubevirt engineer-01 --tunnel 6443:6443
  $0 metal3 engineer-01 --copy-kubeconfig

EOF
    exit 1
}

get_tfstate_bucket() {
    local account_id
    account_id=$(aws sts get-caller-identity --query Account --output text)
    echo "k0rdent-training-tfstate-${account_id}"
}

get_ssh_key() {
    local lab_type="$1"
    local identifier="$2"
    local key_file="$CONFIG_DIR/keys/${identifier}-${lab_type}.pem"

    if [[ -f "$key_file" ]]; then
        echo "$key_file"
        return 0
    fi

    # Try to extract from Terraform state
    local env_dir="$TERRAFORM_DIR/environments/${lab_type}"
    local tfstate_bucket
    tfstate_bucket=$(get_tfstate_bucket)
    local state_key

    case $lab_type in
        metal3-dev|metal3)
            state_key="metal3-dev/${identifier}/terraform.tfstate"
            env_dir="$TERRAFORM_DIR/environments/metal3-dev"
            ;;
        kubevirt-lab|kubevirt)
            state_key="kubevirt-lab/${identifier}/terraform.tfstate"
            env_dir="$TERRAFORM_DIR/environments/kubevirt-lab"
            ;;
        gpu-lab|gpu)
            state_key="gpu-lab/${identifier}/terraform.tfstate"
            env_dir="$TERRAFORM_DIR/environments/gpu-lab"
            ;;
    esac

    cd "$env_dir"
    terraform init -backend-config="bucket=${tfstate_bucket}" \
        -backend-config="key=${state_key}" \
        -backend-config="region=${REGION}" &>/dev/null

    mkdir -p "$CONFIG_DIR/keys"
    terraform output -raw ssh_private_key > "$key_file" 2>/dev/null || {
        log_error "Could not retrieve SSH key. Is the environment provisioned?"
        return 1
    }
    chmod 600 "$key_file"

    echo "$key_file"
}

get_instance_ip() {
    local lab_type="$1"
    local identifier="$2"
    local target="${3:-controller}"

    local env_dir="$TERRAFORM_DIR/environments/${lab_type}"
    local tfstate_bucket
    tfstate_bucket=$(get_tfstate_bucket)
    local state_key

    case $lab_type in
        metal3-dev|metal3)
            state_key="metal3-dev/${identifier}/terraform.tfstate"
            env_dir="$TERRAFORM_DIR/environments/metal3-dev"
            ;;
        kubevirt-lab|kubevirt)
            state_key="kubevirt-lab/${identifier}/terraform.tfstate"
            env_dir="$TERRAFORM_DIR/environments/kubevirt-lab"
            ;;
        gpu-lab|gpu)
            state_key="gpu-lab/${identifier}/terraform.tfstate"
            env_dir="$TERRAFORM_DIR/environments/gpu-lab"
            ;;
    esac

    cd "$env_dir"
    terraform init -backend-config="bucket=${tfstate_bucket}" \
        -backend-config="key=${state_key}" \
        -backend-config="region=${REGION}" &>/dev/null

    case $target in
        controller)
            terraform output -raw controller_private_ip 2>/dev/null
            ;;
        worker-*)
            local worker_index="${target#worker-}"
            terraform output -json worker_private_ips 2>/dev/null | jq -r ".[$worker_index]"
            ;;
        shared)
            terraform output -raw shared_gpu_private_ip 2>/dev/null
            ;;
        advanced)
            terraform output -raw advanced_gpu_private_ip 2>/dev/null
            ;;
    esac
}

connect_ssh() {
    local ip="$1"
    local key_file="$2"
    local user="${3:-ubuntu}"
    local bastion="${4:-}"
    local tunnel="${5:-}"

    local ssh_opts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

    if [[ -n "$bastion" ]]; then
        ssh_opts="$ssh_opts -o ProxyJump=${user}@${bastion}"
    fi

    if [[ -n "$tunnel" ]]; then
        local local_port="${tunnel%%:*}"
        local remote_port="${tunnel##*:}"
        log_info "Creating SSH tunnel: localhost:$local_port -> $ip:$remote_port"
        ssh $ssh_opts -i "$key_file" -L "${local_port}:localhost:${remote_port}" "${user}@${ip}"
    else
        log_info "Connecting to $ip..."
        ssh $ssh_opts -i "$key_file" "${user}@${ip}"
    fi
}

copy_kubeconfig() {
    local ip="$1"
    local key_file="$2"
    local user="${3:-ubuntu}"
    local bastion="${4:-}"
    local identifier="$5"

    local ssh_opts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
    local scp_opts="$ssh_opts"

    if [[ -n "$bastion" ]]; then
        scp_opts="$scp_opts -o ProxyJump=${user}@${bastion}"
    fi

    local kubeconfig_dir="$CONFIG_DIR/kubeconfig"
    mkdir -p "$kubeconfig_dir"

    local local_kubeconfig="$kubeconfig_dir/${identifier}.kubeconfig"

    log_info "Copying kubeconfig from $ip..."

    scp $scp_opts -i "$key_file" "${user}@${ip}:~/.kube/config" "$local_kubeconfig" || {
        log_error "Failed to copy kubeconfig"
        return 1
    }

    # Update server address to use tunnel or direct IP
    if [[ -n "$bastion" ]]; then
        log_warn "Kubeconfig uses private IP. Create a tunnel to access the API server:"
        echo "  $0 $LAB_TYPE $IDENTIFIER --tunnel 6443:6443"
        sed -i.bak "s|server:.*|server: https://localhost:6443|" "$local_kubeconfig"
    else
        sed -i.bak "s|server:.*|server: https://${ip}:6443|" "$local_kubeconfig"
    fi

    rm -f "${local_kubeconfig}.bak"

    log_success "Kubeconfig saved to: $local_kubeconfig"
    echo ""
    echo "To use this kubeconfig:"
    echo "  export KUBECONFIG=$local_kubeconfig"
    echo "  kubectl get nodes"
}

# Default values
REGION="${AWS_REGION:-us-east-1}"
BASTION=""
WORKER_INDEX=""
ADVANCED="false"
TUNNEL=""
COPY_KUBECONFIG="false"

# Global vars for copy_kubeconfig
LAB_TYPE=""
IDENTIFIER=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        metal3|kubevirt|gpu)
            LAB_TYPE="$1"
            shift
            if [[ $# -gt 0 ]] && [[ ! "$1" =~ ^-- ]]; then
                IDENTIFIER="$1"
                shift
            fi
            ;;
        --region)
            REGION="$2"
            shift 2
            ;;
        --bastion)
            BASTION="$2"
            shift 2
            ;;
        --worker)
            WORKER_INDEX="$2"
            shift 2
            ;;
        --advanced)
            ADVANCED="true"
            shift
            ;;
        --tunnel)
            TUNNEL="$2"
            shift 2
            ;;
        --copy-kubeconfig)
            COPY_KUBECONFIG="true"
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
if [[ -z "$LAB_TYPE" ]]; then
    log_error "Lab type required"
    usage
fi

if [[ -z "$IDENTIFIER" ]]; then
    log_error "Identifier required"
    usage
fi

# Determine target
TARGET="controller"
if [[ -n "$WORKER_INDEX" ]]; then
    TARGET="worker-$WORKER_INDEX"
elif [[ "$ADVANCED" == "true" ]]; then
    TARGET="advanced"
elif [[ "$LAB_TYPE" == "gpu" ]]; then
    TARGET="shared"
fi

# Get connection details
log_info "Retrieving connection details..."

KEY_FILE=$(get_ssh_key "$LAB_TYPE" "$IDENTIFIER")
IP=$(get_instance_ip "$LAB_TYPE" "$IDENTIFIER" "$TARGET")

if [[ -z "$IP" ]] || [[ "$IP" == "null" ]]; then
    log_error "Could not determine target IP. Is the environment provisioned?"
    exit 1
fi

log_info "Target: $IP"
log_info "SSH Key: $KEY_FILE"

if [[ "$COPY_KUBECONFIG" == "true" ]]; then
    copy_kubeconfig "$IP" "$KEY_FILE" "ubuntu" "$BASTION" "$IDENTIFIER"
else
    connect_ssh "$IP" "$KEY_FILE" "ubuntu" "$BASTION" "$TUNNEL"
fi
