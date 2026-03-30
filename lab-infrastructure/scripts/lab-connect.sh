#!/bin/bash
# k0rdent Training Lab Connection Script (Per-Student Model)
# Usage: ./lab-connect.sh <your-name> [options]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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
k0rdent Training Lab Connection Script (Per-Student)

Usage: $0 <your-name> [options]

Arguments:
  <your-name>                 Your unique identifier (same as used in lab-provision.sh)

Options:
  --region <region>           AWS region (auto-detected from saved config)
  --tunnel <local:remote>     Create SSH tunnel (e.g., 8080:8080)
  --copy-kubeconfig           Copy kubeconfig to local machine
  --show-password             Show k0rdent UI password
  --ui-url            Show k0rdent UI URL (via Envoy Gateway) and exit
  --show-gateway      Show Gateway API resource status and exit
  --help                      Show this help message

Examples:
  $0 john-doe
  $0 john-doe --tunnel 8080:8080
  $0 john-doe --show-password
  $0 john-doe --copy-kubeconfig

EOF
    exit 1
}

get_student_bucket() {
    local engineer_id="$1"
    local account_id
    account_id=$(aws sts get-caller-identity --query Account --output text)
    echo "k0rdent-lab-${engineer_id}-${account_id}-${REGION}"
}

get_state_output() {
    local bucket="$1"
    local output_name="$2"
    aws s3 cp "s3://${bucket}/terraform.tfstate" - 2>/dev/null \
        | jq -r ".outputs.${output_name}.value // empty" 2>/dev/null
}

get_bastion_ip() {
    local bucket
    bucket=$(get_student_bucket "$IDENTIFIER")
    get_state_output "$bucket" "bastion_public_ip"
}

get_ssh_key() {
    local identifier="$1"
    local key_file="$CONFIG_DIR/keys/${identifier}-k0rdent.pem"

    if [[ -f "$key_file" ]] && [[ -s "$key_file" ]]; then
        echo "$key_file"
        return 0
    fi

    # Extract from S3 state directly
    local bucket
    bucket=$(get_student_bucket "$identifier")
    local ssh_key
    ssh_key=$(get_state_output "$bucket" "ssh_private_key")

    if [[ -z "$ssh_key" ]]; then
        log_error "Could not retrieve SSH key. Is the environment provisioned?"
        return 1
    fi

    mkdir -p "$CONFIG_DIR/keys"
    echo "$ssh_key" > "$key_file"
    chmod 600 "$key_file"
    echo "$key_file"
}

ensure_bastion_key() {
    local identifier="$1"
    local key_file="$CONFIG_DIR/keys/${identifier}-bastion.pem"

    if [[ -f "$key_file" ]] && [[ -s "$key_file" ]]; then
        return 0
    fi

    log_info "Bastion SSH key not found locally, retrieving from state..."
    local bucket
    bucket=$(get_student_bucket "$identifier")
    local ssh_key
    ssh_key=$(get_state_output "$bucket" "bastion_ssh_private_key")

    if [[ -z "$ssh_key" ]]; then
        log_error "Could not retrieve bastion SSH key from state"
        return 1
    fi

    mkdir -p "$CONFIG_DIR/keys"
    echo "$ssh_key" > "$key_file"
    chmod 600 "$key_file"
    log_success "Bastion SSH key saved to: $key_file"
}

get_instance_ip() {
    local identifier="$1"
    local bucket
    bucket=$(get_student_bucket "$identifier")
    get_state_output "$bucket" "primary_node_private_ip"
}

connect_ssh() {
    local ip="$1"
    local key_file="$2"
    local user="${3:-ubuntu}"
    local bastion="${4:-}"
    local tunnel="${5:-}"

    local ssh_opts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
    local bastion_key="$CONFIG_DIR/keys/${IDENTIFIER}-bastion.pem"

    if [[ -n "$bastion" ]]; then
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
    local bastion_key="$CONFIG_DIR/keys/${identifier}-bastion.pem"

    if [[ -n "$bastion" ]]; then
        scp_opts="$scp_opts -o ProxyCommand=\"ssh -i $bastion_key -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -W %h:%p ec2-user@${bastion}\""
    fi

    local kubeconfig_dir="$CONFIG_DIR/kubeconfig"
    mkdir -p "$kubeconfig_dir"
    local local_kubeconfig="$kubeconfig_dir/${identifier}.kubeconfig"

    log_info "Copying kubeconfig from $ip..."
    eval scp $scp_opts -i "$key_file" "${user}@${ip}:~/.kube/config" "$local_kubeconfig" || {
        log_error "Failed to copy kubeconfig"
        return 1
    }

    if [[ -n "$bastion" ]]; then
        log_warn "Kubeconfig uses private IP. Create a tunnel to access the API server:"
        echo "  $0 $identifier --tunnel 6443:6443"
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

# Load config if exists
if [[ -f "$CONFIG_DIR/lab-config.env" ]]; then
    source "$CONFIG_DIR/lab-config.env"
fi

# Default values
REGION=""
TUNNEL=""
COPY_KUBECONFIG="false"
SHOW_PASSWORD="false"
SHOW_UI_URL="false"
SHOW_GATEWAY="false"
IDENTIFIER=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --region)
            REGION="$2"
            shift 2
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
        --ui-url)
            SHOW_UI_URL="true"
            shift
            ;;
        --show-gateway)
            SHOW_GATEWAY="true"
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

# Show password and exit if requested
if [[ "$SHOW_PASSWORD" == "true" ]]; then
    BUCKET=$(get_student_bucket "$IDENTIFIER")
    UI_PASSWORD=$(get_state_output "$BUCKET" "ui_password")
    # UI URL is now served via Envoy Gateway, not Terraform output
    UI_URL="Retrieve via: ./lab-connect.sh $IDENTIFIER --ui-url"
    if [[ -n "$UI_PASSWORD" ]]; then
        echo ""
        log_success "k0rdent UI Password: $UI_PASSWORD"
        echo ""
        echo "UI Access:"
        echo "  URL:   ${UI_URL}"
        echo "  Login: admin / $UI_PASSWORD"
    else
        log_error "Could not retrieve UI password"
        exit 1
    fi
    exit 0
fi

# Show Gateway UI URL and exit if requested
if [[ "$SHOW_UI_URL" == "true" ]]; then
    KEY_FILE=$(get_ssh_key "$IDENTIFIER")
    IP=$(get_instance_ip "$IDENTIFIER")
    BASTION=$(get_bastion_ip)
    ensure_bastion_key "$IDENTIFIER"
    BASTION_KEY="$CONFIG_DIR/keys/${IDENTIFIER}-bastion.pem"

    SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"
    PROXY_CMD="ssh ${SSH_OPTS} -i ${BASTION_KEY} -W %h:%p ec2-user@${BASTION}"

    GW_ADDR=$(ssh ${SSH_OPTS} -i "$KEY_FILE" -o "ProxyCommand=${PROXY_CMD}" ubuntu@"${IP}" \
        "kubectl get gateway k0rdent-gateway -n kcm-system -o jsonpath='{.status.addresses[0].value}'" 2>/dev/null || true)
    # Password is stored in Terraform state, not in a Kubernetes secret
    BUCKET=$(get_student_bucket "$IDENTIFIER")
    UI_PASSWORD=$(get_state_output "$BUCKET" "ui_password")

    if [[ -n "$GW_ADDR" ]]; then
        echo ""
        log_success "k0rdent UI"
        echo "  URL:       http://${GW_ADDR}"
        echo "  Username:  admin"
        echo "  Password:  ${UI_PASSWORD:-unknown}"
        echo ""
    else
        log_error "Gateway LB address not available. Is initialization complete?"
        log_info "Check: ssh into node and run: kubectl get gateway -n kcm-system"
        exit 1
    fi
    exit 0
fi

# Show Gateway status and exit if requested
if [[ "$SHOW_GATEWAY" == "true" ]]; then
    KEY_FILE=$(get_ssh_key "$IDENTIFIER")
    IP=$(get_instance_ip "$IDENTIFIER")
    BASTION=$(get_bastion_ip)
    ensure_bastion_key "$IDENTIFIER"
    BASTION_KEY="$CONFIG_DIR/keys/${IDENTIFIER}-bastion.pem"

    SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"
    PROXY_CMD="ssh ${SSH_OPTS} -i ${BASTION_KEY} -W %h:%p ec2-user@${BASTION}"

    echo ""
    log_info "Gateway API Resources:"
    ssh ${SSH_OPTS} -i "$KEY_FILE" -o "ProxyCommand=${PROXY_CMD}" ubuntu@"${IP}" \
        "kubectl get gatewayclass,gateway,httproute -A -o wide" 2>/dev/null
    echo ""
    log_info "Envoy Gateway Pods:"
    ssh ${SSH_OPTS} -i "$KEY_FILE" -o "ProxyCommand=${PROXY_CMD}" ubuntu@"${IP}" \
        "kubectl get pods -n envoy-gateway-system -o wide" 2>/dev/null
    exit 0
fi

# Get connection details
log_info "Retrieving connection details..."

KEY_FILE=$(get_ssh_key "$IDENTIFIER")
IP=$(get_instance_ip "$IDENTIFIER")

if [[ -z "$IP" ]] || [[ "$IP" == "null" ]]; then
    log_error "Could not determine target IP. Is the environment provisioned?"
    exit 1
fi

# Auto-detect bastion for private IPs
BASTION=""
if [[ "$IP" =~ ^10\. ]]; then
    log_info "Target is a private IP, auto-detecting bastion..."
    BASTION=$(get_bastion_ip)
    if [[ -z "$BASTION" ]]; then
        log_error "Could not determine bastion IP. Is the environment provisioned?"
        exit 1
    fi
    log_info "Using bastion: $BASTION"
    ensure_bastion_key "$IDENTIFIER"
fi

log_info "Target: $IP"
log_info "SSH Key: $KEY_FILE"

if [[ "$COPY_KUBECONFIG" == "true" ]]; then
    copy_kubeconfig "$IP" "$KEY_FILE" "ubuntu" "$BASTION" "$IDENTIFIER"
else
    connect_ssh "$IP" "$KEY_FILE" "ubuntu" "$BASTION" "$TUNNEL"
fi
