#!/bin/bash
# k0rdent Training Lab Status Script (Per-Student Model)
# Usage: ./lab-status.sh <your-name> [options]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/../config"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Respect NO_COLOR and non-TTY output (piped logs, CI, screen readers)
if [[ -n "${NO_COLOR:-}" || ! -t 1 ]]; then
    RED="" GREEN="" YELLOW="" BLUE="" CYAN="" NC=""
fi

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

usage() {
    cat <<EOF
k0rdent Training Lab Status Script (Per-Student)

Usage: $0 <your-name> [options]

Arguments:
  <your-name>                 Your unique identifier (same as used in lab-provision.sh)

Options:
  --region <region>           AWS region (auto-detected from saved config)
  --json                      Output in JSON format
  --help                      Show this help message

Examples:
  $0 john-doe
  $0 john-doe --json

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

check_instance_status() {
    local instance_id="$1"
    aws ec2 describe-instances --region "$REGION" \
        --instance-ids "$instance_id" \
        --query 'Reservations[0].Instances[0].State.Name' \
        --output text 2>/dev/null || echo "unknown"
}

show_status() {
    local engineer_id="$1"
    local bucket
    bucket=$(get_student_bucket "$engineer_id")

    echo ""
    echo "=========================================="
    echo " Lab Status: $engineer_id"
    echo " Region: $REGION"
    echo " Bucket: $bucket"
    echo "=========================================="
    echo ""

    # Check if bucket exists
    if ! aws s3api head-bucket --bucket "$bucket" 2>/dev/null; then
        log_warn "No student bucket found. Environment not provisioned."
        return 0
    fi

    # Check if state exists
    local state_content
    state_content=$(aws s3 cp "s3://${bucket}/terraform.tfstate" - 2>/dev/null || echo "")
    if [[ -z "$state_content" ]]; then
        log_warn "No Terraform state found. Environment not provisioned."
        return 0
    fi

    # Bastion
    local bastion_ip
    bastion_ip=$(echo "$state_content" | jq -r '.outputs.bastion_public_ip.value // empty')
    if [[ -n "$bastion_ip" ]]; then
        echo -e "${GREEN}Bastion:${NC} $bastion_ip"
    fi

    # VPC
    local vpc_id
    vpc_id=$(echo "$state_content" | jq -r '.outputs.vpc_id.value // empty')
    if [[ -n "$vpc_id" ]]; then
        echo -e "${CYAN}VPC:${NC} $vpc_id"
    fi

    # NAT Gateway
    local nat_ip
    nat_ip=$(echo "$state_content" | jq -r '.outputs.nat_gateway_ip.value // empty')
    if [[ -n "$nat_ip" ]]; then
        echo -e "${CYAN}NAT Gateway:${NC} $nat_ip"
    fi

    echo ""

    # k0rdent management cluster
    local primary_ip
    primary_ip=$(echo "$state_content" | jq -r '.outputs.primary_node_private_ip.value // empty')
    if [[ -n "$primary_ip" ]]; then
        echo -e "${GREEN}k0rdent Management Cluster${NC}"

        local node_ids
        node_ids=$(echo "$state_content" | jq -r '.outputs.mgmt_node_ids.value // [] | .[]' 2>/dev/null)
        for node_id in $node_ids; do
            local status
            status=$(check_instance_status "$node_id")
            case $status in
                running)  echo -e "  ${GREEN}$node_id${NC}: running" ;;
                stopped)  echo -e "  ${YELLOW}$node_id${NC}: stopped" ;;
                *)        echo -e "  ${RED}$node_id${NC}: $status" ;;
            esac
        done

        echo -e "  ${CYAN}Primary IP:${NC} $primary_ip"

        # The UI URL is assigned at runtime by the Envoy Gateway LB, not
        # stored in Terraform state -- point at the script that retrieves it.
        echo -e "  ${CYAN}UI URL:${NC} run ./lab-connect.sh $engineer_id --ui-url"
    fi

    echo ""

    # Optional: GPU lab
    local gpu_ip
    gpu_ip=$(echo "$state_content" | jq -r '.outputs.shared_gpu_private_ip.value // empty')
    if [[ -n "$gpu_ip" && "$gpu_ip" != "null" ]]; then
        echo -e "${GREEN}GPU Lab:${NC} $gpu_ip"
    fi

    # Optional: Metal3
    local metal3_ip
    metal3_ip=$(echo "$state_content" | jq -r '.outputs.metal3_controller_ip.value // empty')
    if [[ -n "$metal3_ip" && "$metal3_ip" != "null" ]]; then
        echo -e "${GREEN}Metal3:${NC} $metal3_ip"
    fi

    # Optional: KubeVirt
    local kubevirt_ip
    kubevirt_ip=$(echo "$state_content" | jq -r '.outputs.kubevirt_controller_ip.value // empty')
    if [[ -n "$kubevirt_ip" && "$kubevirt_ip" != "null" ]]; then
        echo -e "${GREEN}KubeVirt:${NC} $kubevirt_ip"
    fi

    echo ""
    echo "Connect: ./lab-connect.sh $engineer_id"
    echo ""
}

show_status_json() {
    local engineer_id="$1"
    local bucket
    bucket=$(get_student_bucket "$engineer_id")

    local state_content
    state_content=$(aws s3 cp "s3://${bucket}/terraform.tfstate" - 2>/dev/null || echo "{}")

    echo "$state_content" | jq '{
        engineer_id: "'"$engineer_id"'",
        region: "'"$REGION"'",
        bucket: "'"$bucket"'",
        bastion_ip: (.outputs.bastion_public_ip.value // null),
        vpc_id: (.outputs.vpc_id.value // null),
        primary_node_ip: (.outputs.primary_node_private_ip.value // null),
        mgmt_node_ids: (.outputs.mgmt_node_ids.value // []),
        gpu_ip: (.outputs.shared_gpu_private_ip.value // null),
        metal3_ip: (.outputs.metal3_controller_ip.value // null),
        kubevirt_ip: (.outputs.kubevirt_controller_ip.value // null)
    }' 2>/dev/null || echo '{"error": "No state found"}'
}

# Load config if exists
if [[ -f "$CONFIG_DIR/lab-config.env" ]]; then
    source "$CONFIG_DIR/lab-config.env"
fi

# Default values
REGION=""
JSON_OUTPUT="false"
IDENTIFIER=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --region)
            REGION="$2"
            shift 2
            ;;
        --json)
            JSON_OUTPUT="true"
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

# jq is required to parse the Terraform state
command -v jq &> /dev/null || { log_error "jq is required but not installed. Install: brew install jq (macOS) or sudo apt-get install -y jq (Ubuntu)"; exit 1; }

# Execute
if [[ "$JSON_OUTPUT" == "true" ]]; then
    show_status_json "$IDENTIFIER"
else
    show_status "$IDENTIFIER"
fi
