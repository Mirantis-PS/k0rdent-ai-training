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

# Respect NO_COLOR and non-TTY output (piped logs, CI, screen readers)
if [[ -n "${NO_COLOR:-}" || ! -t 1 ]]; then
    RED="" GREEN="" YELLOW="" BLUE="" NC=""
fi

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

# Wait for cloud-init, stream progress, and retrieve Gateway LB URL.
# NOTE: this function is called inside a command substitution, so ALL
# progress/log output goes to stderr (>&2) to display live; ONLY the
# final URL is echoed to stdout.
wait_for_gateway_url() {
    local bastion_ip="$1"
    local mgmt_ip="$2"
    local key_file="$3"
    local bastion_key="$4"
    local max_wait="${5:-1200}"  # 20 min default (cloud-init takes ~15 min)

    # SSH options for bastion jump (bastion is Amazon Linux = ec2-user)
    local ssh_opts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=10"
    local proxy_cmd="ssh ${ssh_opts} -i ${bastion_key} -W %h:%p ec2-user@${bastion_ip}"

    # Wait for SSH to become available (instance needs ~60s to boot)
    log_info "Waiting for SSH access to management node..." >&2
    local ssh_ready="false"
    for i in $(seq 1 20); do
        if ssh ${ssh_opts} -i "$key_file" -o "ProxyCommand=${proxy_cmd}" ubuntu@"${mgmt_ip}" \
            "echo ok" 2>/dev/null | grep -q ok; then
            ssh_ready="true"
            break
        fi
        echo -n "." >&2
        sleep 5
    done
    echo "" >&2

    if [[ "$ssh_ready" != "true" ]]; then
        log_warn "Could not SSH to management node. Check bastion/instance status." >&2
        return 1
    fi

    # Stream init log in real-time until .init-complete marker appears
    log_info "Streaming initialization progress (live)..." >&2
    echo "" >&2
    ssh ${ssh_opts} -i "$key_file" -o "ProxyCommand=${proxy_cmd}" ubuntu@"${mgmt_ip}" \
        "timeout ${max_wait} bash -c '
            # Wait for log file to appear
            while [ ! -f /var/log/k0rdent-init.log ]; do sleep 2; done
            # Stream log, filtering for key progress lines
            tail -f /var/log/k0rdent-init.log 2>/dev/null | while IFS= read -r line; do
                case \"\$line\" in
                    *\"[1/6]\"*|*\"[2/6]\"*|*\"[3/6]\"*|*\"[4/6]\"*|*\"[5/6]\"*|*\"[6/6]\"*)
                        echo \"  \$line\" ;;
                    *\"=== \"*\" ===\"*)
                        echo \"  \$line\" ;;
                    *\"Installing \"*|*\"Waiting for \"*|*\"Helm install\"*|*\"Creating \"*)
                        echo \"  \$line\" ;;
                    *\"STATUS: deployed\"*)
                        echo \"  \$line\" ;;
                    *\"providerID\"*)
                        echo \"  \$line\" ;;
                    *\"WARN:\"*|*\"ERROR:\"*)
                        echo \"  \$line\" ;;
                    *\"Installation Complete\"*|*\"Lab initialization complete\"*)
                        echo \"  \$line\"
                        break ;;
                esac
            done
        '" >&2 2>/dev/null || true
    echo "" >&2

    # Verify init completed
    local init_done
    init_done=$(ssh ${ssh_opts} -i "$key_file" -o "ProxyCommand=${proxy_cmd}" ubuntu@"${mgmt_ip}" \
        "test -f /opt/k0rdent-lab/.init-complete && echo yes || echo no" 2>/dev/null || echo "no")

    if [[ "$init_done" != "yes" ]]; then
        log_warn "Initialization did not complete within ${max_wait}s. Check: tail -f /var/log/k0rdent-init.log" >&2
        return 1
    fi
    log_success "k0rdent initialization complete" >&2

    # Poll for Gateway LB URL (CCM needs ~30-60s after init to provision the ELB)
    log_info "Waiting for Gateway LoadBalancer address..." >&2
    local gw_addr=""
    for i in $(seq 1 24); do  # 24 × 10s = 4 min
        gw_addr=$(ssh ${ssh_opts} -i "$key_file" -o "ProxyCommand=${proxy_cmd}" ubuntu@"${mgmt_ip}" \
            "kubectl get gateway k0rdent-gateway -n kcm-system -o jsonpath='{.status.addresses[0].value}'" 2>/dev/null || true)

        if [[ -n "$gw_addr" ]]; then
            echo "" >&2
            echo "http://${gw_addr}"
            return 0
        fi

        echo -n "." >&2
        sleep 10
    done

    echo "" >&2
    log_warn "Gateway LB address not available after 4 min. Retrieve later: ./lab-connect.sh <id> --ui-url" >&2
    return 1
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
  --no-gpu                    Destroy a previously-enabled GPU lab
  --no-metal3                 Destroy a previously-enabled Metal3 environment
  --no-kubevirt               Destroy a previously-enabled KubeVirt environment
  --ssh-cidr <cidr>[,<cidr>]  CIDR(s) allowed to SSH to the bastion (repeatable).
                              Default: your public IP/32 (auto-detected)
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

Re-runs:
  Optional environments (GPU, Metal3, KubeVirt) that are already provisioned
  are kept enabled automatically -- you do NOT need to repeat their flags.
  To remove one, pass the matching --no-<feature> flag; the script will warn
  and ask for confirmation before destroying it.

Examples:
  $0 john-doe --region us-east-1                  # Week 1: base lab
  $0 john-doe --gpu                               # Add GPU lab (base lab is kept)
  $0 john-doe --metal3 --kubevirt                  # Add Metal3 + KubeVirt
  $0 john-doe --no-gpu                            # Destroy the GPU lab only
  $0 john-doe --ssh-cidr 203.0.113.5/32           # Restrict bastion SSH source

EOF
    exit 1
}

check_prerequisites() {
    log_info "Checking prerequisites..."

    if ! command -v terraform &> /dev/null; then
        log_error "terraform is not installed. Please install Terraform >= 1.8.0"
        log_error "  brew install hashicorp/tap/terraform   # macOS"
        exit 1
    fi

    # Terraform version check: require >= 1.8.0
    local tf_version required_version="1.8.0"
    tf_version=$(terraform version 2>/dev/null | head -n1 | awk '{print $2}' | tr -d 'v')
    if [[ -z "$tf_version" ]]; then
        log_error "Could not determine Terraform version from 'terraform version' output"
        exit 1
    fi
    if [[ "$(printf '%s\n' "$required_version" "$tf_version" | sort -V | head -n1)" != "$required_version" ]]; then
        log_error "Terraform >= ${required_version} required (found ${tf_version})"
        log_error "  brew uninstall terraform 2>/dev/null || true       # remove old homebrew pin (1.5.7)"
        log_error "  brew tap hashicorp/tap"
        log_error "  brew install hashicorp/tap/terraform"
        exit 1
    fi
    log_info "Terraform ${tf_version} (>= ${required_version}) OK"

    if ! command -v aws &> /dev/null; then
        log_error "aws CLI is not installed. Please install AWS CLI"
        exit 1
    fi

    if ! command -v jq &> /dev/null; then
        log_error "jq is not installed (required by lab-connect.sh / lab-refresh-creds.sh / lab-status.sh)"
        log_error "  brew install jq                # macOS"
        log_error "  sudo apt-get install -y jq     # Ubuntu/Debian"
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
    echo "k0rdent-lab-${engineer_id}-${account_id}-${REGION}"
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

# Resolve the CIDR allow-list for bastion SSH access.
# Precedence: --ssh-cidr flag > ALLOWED_SSH_CIDRS env (e.g. from lab-config.env)
# > auto-detected public IP/32 > 0.0.0.0/0 (with a loud warning).
resolve_ssh_cidrs() {
    if [[ -n "$SSH_CIDRS" ]]; then
        log_info "Bastion SSH restricted to: $SSH_CIDRS (from --ssh-cidr)"
        return 0
    fi

    # Ignore the unedited example placeholder ("YOUR_IP/32")
    if [[ -n "${ALLOWED_SSH_CIDRS:-}" && "${ALLOWED_SSH_CIDRS}" != *"YOUR_IP"* ]]; then
        SSH_CIDRS="$ALLOWED_SSH_CIDRS"
        if [[ "$SSH_CIDRS" == *"0.0.0.0/0"* ]]; then
            log_warn "============================================================"
            log_warn "ALLOWED_SSH_CIDRS contains 0.0.0.0/0: bastion SSH will be"
            log_warn "OPEN TO THE ENTIRE INTERNET."
            log_warn "Re-run with --ssh-cidr <your-ip>/32 to restrict access."
            log_warn "============================================================"
        else
            log_info "Bastion SSH restricted to: $SSH_CIDRS (from ALLOWED_SSH_CIDRS)"
        fi
        return 0
    fi

    log_info "Detecting your public IP to restrict bastion SSH access..."
    local my_ip
    my_ip=$(curl -sf --max-time 5 https://checkip.amazonaws.com 2>/dev/null | tr -d '[:space:]' || true)
    if [[ "$my_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        SSH_CIDRS="${my_ip}/32"
        log_info "Bastion SSH restricted to: $SSH_CIDRS (override with --ssh-cidr)"
    else
        SSH_CIDRS="0.0.0.0/0"
        log_warn "============================================================"
        log_warn "Could not detect your public IP. Bastion SSH will be OPEN"
        log_warn "TO THE ENTIRE INTERNET (0.0.0.0/0)."
        log_warn "Re-run with --ssh-cidr <your-ip>/32 to restrict access."
        log_warn "============================================================"
    fi
}

# Convert the comma-separated SSH_CIDRS list to a Terraform list literal,
# e.g. "1.2.3.4/32,10.0.0.0/8" -> ["1.2.3.4/32","10.0.0.0/8"]
ssh_cidrs_tf_list() {
    local out="[" first="true" c
    local IFS=','
    for c in $SSH_CIDRS; do
        c="${c// /}"
        [[ -z "$c" ]] && continue
        [[ "$first" == "true" ]] || out+=","
        out+="\"${c}\""
        first="false"
    done
    echo "${out}]"
}

# Warn loudly and require confirmation before destroying a previously-enabled
# optional environment (triggered by an explicit --no-<feature> flag).
confirm_feature_destroy() {
    local feature_name="$1"

    echo ""
    echo -e "${RED}WARNING: ${feature_name} is currently provisioned and will be DESTROYED by this run.${NC}"
    echo ""

    if [[ "$AUTO_APPROVE" == "true" ]]; then
        log_warn "--auto-approve set: proceeding with ${feature_name} destruction"
        return 0
    fi

    local reply=""
    read -r -p "Destroy ${feature_name}? (y/N): " reply || reply=""
    if [[ ! "$reply" =~ ^[Yy]$ ]]; then
        log_warn "Aborting -- ${feature_name} was NOT destroyed"
        exit 1
    fi
}

# Re-runs with only one feature flag must not silently destroy the other
# optional environments: preserve whatever is already in the Terraform state
# unless an explicit --no-<feature> flag was passed.
preserve_enabled_features() {
    local state_resources
    state_resources=$(terraform state list 2>/dev/null || true)
    [[ -z "$state_resources" ]] && return 0

    if grep -q '^module\.gpu_lab\[' <<< "$state_resources"; then
        if [[ "$DISABLE_GPU" == "true" ]]; then
            ENABLE_GPU="false"
            confirm_feature_destroy "GPU lab"
        elif [[ "$ENABLE_GPU" != "true" ]]; then
            log_info "GPU lab is already provisioned -- keeping it enabled (use --no-gpu to remove)"
            ENABLE_GPU="true"
        fi
    fi

    if grep -q '^module\.metal3_dev\[' <<< "$state_resources"; then
        if [[ "$DISABLE_METAL3" == "true" ]]; then
            ENABLE_METAL3="false"
            confirm_feature_destroy "Metal3 dev environment"
        elif [[ "$ENABLE_METAL3" != "true" ]]; then
            log_info "Metal3 dev environment is already provisioned -- keeping it enabled (use --no-metal3 to remove)"
            ENABLE_METAL3="true"
        fi
    fi

    if grep -q '^module\.kubevirt_lab\[' <<< "$state_resources"; then
        if [[ "$DISABLE_KUBEVIRT" == "true" ]]; then
            ENABLE_KUBEVIRT="false"
            confirm_feature_destroy "KubeVirt lab environment"
        elif [[ "$ENABLE_KUBEVIRT" != "true" ]]; then
            log_info "KubeVirt lab environment is already provisioned -- keeping it enabled (use --no-kubevirt to remove)"
            ENABLE_KUBEVIRT="true"
        fi
    fi
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

    # Keep already-provisioned optional environments enabled on re-runs
    preserve_enabled_features

    # Resolve the bastion SSH allow-list
    resolve_ssh_cidrs
    local ssh_cidrs_var
    ssh_cidrs_var=$(ssh_cidrs_tf_list)

    if [[ "$PLAN_ONLY" == "true" ]]; then
        terraform plan \
            -var="engineer_id=${engineer_id}" \
            -var="region=${REGION}" \
            -var="student_bucket=${bucket}" \
            -var="node_count=${NODE_COUNT}" \
            -var="allowed_ssh_cidrs=${ssh_cidrs_var}" \
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
        -var="allowed_ssh_cidrs=${ssh_cidrs_var}" \
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
# Generated by lab-provision.sh -- this file is REWRITTEN on every provision
# run. Put persistent customizations in lab-config.env.example-documented
# environment variables or provision flags, not here.
LAB_REGION="${REGION}"
LAB_ENGINEER_ID="${engineer_id}"
LAB_BUCKET="${bucket}"
# Bastion SSH allow-list applied on the last run (reused on re-runs unless
# overridden with --ssh-cidr)
ALLOWED_SSH_CIDRS="${SSH_CIDRS}"
ENVEOF

    local bastion_ip
    bastion_ip=$(terraform output -raw bastion_public_ip)
    local mgmt_ip
    mgmt_ip=$(terraform output -raw primary_node_private_ip)
    local mgmt_key="$key_dir/${engineer_id}-k0rdent.pem"
    local bastion_key="$key_dir/${engineer_id}-bastion.pem"

    log_success "Infrastructure provisioned for $engineer_id!"
    log_info "Bastion IP: $bastion_ip"
    log_info "Primary node IP: $mgmt_ip"
    log_info "SSH key: $mgmt_key"
    log_info "Connect via: ./lab-connect.sh $engineer_id"
    echo ""

    log_info "Waiting for k0rdent + Envoy Gateway to be ready..."
    local ui_url
    ui_url=$(wait_for_gateway_url "$bastion_ip" "$mgmt_ip" "$mgmt_key" "$bastion_key") || true

    local ui_password
    ui_password=$(terraform output -raw ui_password 2>/dev/null || echo "unknown")

    echo ""
    echo "============================================"
    echo "  k0rdent UI"
    echo "  URL:       ${ui_url:-not yet available -- run: ./lab-connect.sh $engineer_id --ui-url}"
    echo "  Username:  admin"
    echo "  Password:  ${ui_password}"
    echo "============================================"
    echo ""
    if [[ -z "$ui_url" ]]; then
        log_warn "UI not ready yet -- get the URL later with: ./lab-connect.sh $engineer_id --ui-url"
    fi
    log_info "To retrieve the URL later: ./lab-connect.sh $engineer_id --ui-url"
}

# Default values
REGION=""
NODE_COUNT="1"
ENABLE_GPU="false"
ENABLE_METAL3="false"
ENABLE_KUBEVIRT="false"
DISABLE_GPU="false"
DISABLE_METAL3="false"
DISABLE_KUBEVIRT="false"
SSH_CIDRS=""
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
        --no-gpu)
            DISABLE_GPU="true"
            shift
            ;;
        --no-metal3)
            DISABLE_METAL3="true"
            shift
            ;;
        --no-kubevirt)
            DISABLE_KUBEVIRT="true"
            shift
            ;;
        --ssh-cidr)
            if [[ -n "$SSH_CIDRS" ]]; then
                SSH_CIDRS="${SSH_CIDRS},$2"
            else
                SSH_CIDRS="$2"
            fi
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
