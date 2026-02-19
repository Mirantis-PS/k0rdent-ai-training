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
  k0rdent <engineer-id>       Connect to k0rdent management cluster
  metal3 <engineer-id>        Connect to Metal3 dev environment
  kubevirt <engineer-id>      Connect to KubeVirt lab controller
  gpu <session-id>            Connect to GPU lab instance

Options:
  --region <region>           AWS region (or set AWS_REGION env var)
  --bastion <ip>              Bastion host IP for jump connection
  --worker <n>                Connect to specific worker (kubevirt)
  --advanced                  Connect to advanced GPU (8x A100)
  --tunnel <local:remote>     Create SSH tunnel (e.g., 8080:8080)
  --copy-kubeconfig           Copy kubeconfig to local machine
  --show-password             Show k0rdent UI password (k0rdent only)
  --help                      Show this help message

Examples:
  $0 k0rdent engineer-01
  $0 k0rdent engineer-01 --tunnel 8080:8080   # For k0rdent UI access
  $0 k0rdent engineer-01 --show-password      # Get UI password
  $0 metal3 engineer-01
  $0 kubevirt engineer-01 --worker 0
  $0 gpu cohort-2024-q1

EOF
    exit 1
}

get_tfstate_bucket() {
    local account_id
    account_id=$(aws sts get-caller-identity --query Account --output text)
    echo "k0rdent-training-tfstate-${account_id}"
}

# Detect the actual AWS region of the S3 state bucket
get_bucket_region() {
    local bucket_name
    bucket_name=$(get_tfstate_bucket)
    local location
    location=$(aws s3api get-bucket-location --bucket "$bucket_name" \
        --query LocationConstraint --output text 2>/dev/null)
    if [[ "$location" == "None" || -z "$location" ]]; then
        echo "us-east-1"
    else
        echo "$location"
    fi
}

# Read terraform output from S3 state directly (bypasses terraform credential issues)
get_state_output() {
    local bucket="$1"
    local key="$2"
    local output_name="$3"

    aws s3 cp "s3://${bucket}/${key}" - 2>/dev/null | jq -r ".outputs.${output_name}.value // empty" 2>/dev/null
}

get_bastion_ip() {
    local tfstate_bucket
    tfstate_bucket=$(get_tfstate_bucket)

    get_state_output "$tfstate_bucket" "${REGION}/shared/terraform.tfstate" "bastion_public_ip"
}

ensure_bastion_key() {
    local key_file="$CONFIG_DIR/keys/bastion-${REGION}.pem"

    if [[ -f "$key_file" ]] && [[ -s "$key_file" ]]; then
        return 0
    fi

    log_info "Bastion SSH key not found locally, retrieving from Terraform state..."
    local tfstate_bucket
    tfstate_bucket=$(get_tfstate_bucket)

    local ssh_key
    ssh_key=$(get_state_output "$tfstate_bucket" "${REGION}/shared/terraform.tfstate" "bastion_ssh_private_key")

    if [[ -z "$ssh_key" ]]; then
        log_error "Could not retrieve bastion SSH key from state. Was shared infrastructure provisioned?"
        return 1
    fi

    mkdir -p "$CONFIG_DIR/keys"
    echo "$ssh_key" > "$key_file"
    chmod 600 "$key_file"
    log_success "Bastion SSH key retrieved and saved to: $key_file"
}

get_ssh_key() {
    local lab_type="$1"
    local identifier="$2"
    local key_file="$CONFIG_DIR/keys/${identifier}-${lab_type}.pem"

    if [[ -f "$key_file" ]] && [[ -s "$key_file" ]]; then
        echo "$key_file"
        return 0
    fi

    # Extract from S3 state directly
    local tfstate_bucket
    tfstate_bucket=$(get_tfstate_bucket)
    local state_key

    case $lab_type in
        k0rdent-mgmt|k0rdent)
            state_key="${REGION}/k0rdent/${identifier}/terraform.tfstate"
            ;;
        metal3-dev|metal3)
            state_key="${REGION}/metal3-dev/${identifier}/terraform.tfstate"
            ;;
        kubevirt-lab|kubevirt)
            state_key="${REGION}/kubevirt-lab/${identifier}/terraform.tfstate"
            ;;
        gpu-lab|gpu)
            state_key="${REGION}/gpu-lab/${identifier}/terraform.tfstate"
            ;;
    esac

    mkdir -p "$CONFIG_DIR/keys"
    local ssh_key
    ssh_key=$(get_state_output "$tfstate_bucket" "$state_key" "ssh_private_key")

    if [[ -z "$ssh_key" ]]; then
        log_error "Could not retrieve SSH key. Is the environment provisioned?"
        return 1
    fi

    echo "$ssh_key" > "$key_file"
    chmod 600 "$key_file"

    echo "$key_file"
}

get_instance_ip() {
    local lab_type="$1"
    local identifier="$2"
    local target="${3:-controller}"

    local tfstate_bucket
    tfstate_bucket=$(get_tfstate_bucket)
    local state_key

    case $lab_type in
        k0rdent-mgmt|k0rdent)
            state_key="${REGION}/k0rdent/${identifier}/terraform.tfstate"
            ;;
        metal3-dev|metal3)
            state_key="${REGION}/metal3-dev/${identifier}/terraform.tfstate"
            ;;
        kubevirt-lab|kubevirt)
            state_key="${REGION}/kubevirt-lab/${identifier}/terraform.tfstate"
            ;;
        gpu-lab|gpu)
            state_key="${REGION}/gpu-lab/${identifier}/terraform.tfstate"
            ;;
    esac

    case $target in
        controller)
            # k0rdent uses different output name
            if [[ "$lab_type" =~ ^k0rdent ]]; then
                get_state_output "$tfstate_bucket" "$state_key" "primary_node_private_ip"
            else
                get_state_output "$tfstate_bucket" "$state_key" "controller_private_ip"
            fi
            ;;
        worker-*)
            local worker_index="${target#worker-}"
            aws s3 cp "s3://${tfstate_bucket}/${state_key}" - 2>/dev/null | jq -r ".outputs.worker_private_ips.value[${worker_index}] // empty" 2>/dev/null
            ;;
        shared)
            get_state_output "$tfstate_bucket" "$state_key" "shared_gpu_private_ip"
            ;;
        advanced)
            get_state_output "$tfstate_bucket" "$state_key" "advanced_gpu_private_ip"
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
    local bastion_key="$CONFIG_DIR/keys/bastion-${REGION}.pem"

    if [[ -n "$bastion" ]]; then
        # Use ProxyCommand with bastion key for the jump host
        ssh_opts="$ssh_opts -o ProxyCommand=\"ssh -i $bastion_key -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -W %h:%p ec2-user@${bastion}\""
    fi

    if [[ -n "$tunnel" ]]; then
        local local_port="${tunnel%%:*}"
        local remote_port="${tunnel##*:}"
        log_info "Creating SSH tunnel: localhost:$local_port -> $ip:$remote_port"
        eval ssh $ssh_opts -i "$key_file" -L "${local_port}:localhost:${remote_port}" "${user}@${ip}"
    else
        log_info "Connecting to $ip via bastion $bastion..."
        eval ssh $ssh_opts -i "$key_file" "${user}@${ip}"
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

# Load config if exists (created by lab-provision.sh)
load_config() {
    if [[ -f "$CONFIG_DIR/lab-config.env" ]]; then
        source "$CONFIG_DIR/lab-config.env"
    fi
}

load_config

# Default values - region resolved after arg parsing
REGION=""
BASTION=""
WORKER_INDEX=""
ADVANCED="false"
TUNNEL=""
COPY_KUBECONFIG="false"
SHOW_PASSWORD="false"

# Global vars for copy_kubeconfig
LAB_TYPE=""
IDENTIFIER=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        k0rdent|metal3|kubevirt|gpu)
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
        --show-password)
            SHOW_PASSWORD="true"
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

# Resolve region: --region flag > saved LAB_REGION > env vars > AWS CLI default
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

# Auto-detect bastion for private IPs (10.x.x.x)
if [[ -z "$BASTION" ]] && [[ "$IP" =~ ^10\. ]]; then
    log_info "Target is a private IP, auto-detecting bastion..."
    BASTION=$(get_bastion_ip)
    if [[ -z "$BASTION" ]]; then
        log_error "Could not determine bastion IP. Is shared infrastructure provisioned?"
        exit 1
    fi
    log_info "Using bastion: $BASTION"
    ensure_bastion_key
fi

log_info "Target: $IP"
log_info "SSH Key: $KEY_FILE"

# Show password and exit if requested
if [[ "$SHOW_PASSWORD" == "true" ]]; then
    if [[ ! "$LAB_TYPE" =~ ^k0rdent ]]; then
        log_error "--show-password is only available for k0rdent environments"
        exit 1
    fi
    TFSTATE_BUCKET=$(get_tfstate_bucket)
    UI_PASSWORD=$(get_state_output "$TFSTATE_BUCKET" "${REGION}/k0rdent/${IDENTIFIER}/terraform.tfstate" "ui_password")
    if [[ -n "$UI_PASSWORD" ]]; then
        echo ""
        log_success "k0rdent UI Password: $UI_PASSWORD"
        echo ""
        echo "UI Access:"
        echo "  1. Run: ./scripts/lab-connect.sh k0rdent $IDENTIFIER --tunnel 8080:8080"
        echo "  2. On server: kubectl port-forward svc/kcm-k0rdent-ui -n kcm-system 8080:3000 --address 0.0.0.0 &"
        echo "  3. Open: http://localhost:8080"
        echo "  4. Login: admin / $UI_PASSWORD"
    else
        log_error "Could not retrieve UI password"
        exit 1
    fi
    exit 0
fi

if [[ "$COPY_KUBECONFIG" == "true" ]]; then
    copy_kubeconfig "$IP" "$KEY_FILE" "ubuntu" "$BASTION" "$IDENTIFIER"
else
    connect_ssh "$IP" "$KEY_FILE" "ubuntu" "$BASTION" "$TUNNEL"
fi
