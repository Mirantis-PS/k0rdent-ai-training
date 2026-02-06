#!/bin/bash
# k0rdent Training Lab Status Script
# Usage: ./lab-status.sh [lab-type] [identifier]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$SCRIPT_DIR/../terraform"
CONFIG_DIR="$SCRIPT_DIR/../config"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

usage() {
    cat <<EOF
k0rdent Training Lab Status Script

Usage: $0 [command] [options]

Commands:
  all                         Show status of all environments
  shared                      Show shared infrastructure status
  metal3 <engineer-id>        Show Metal3 dev environment status
  kubevirt <engineer-id>      Show KubeVirt lab status
  gpu <session-id>            Show GPU lab status
  list                        List all provisioned environments

Options:
  --region <region>           AWS region (or set AWS_REGION env var)
  --json                      Output in JSON format
  --help                      Show this help message

Examples:
  $0 all
  $0 metal3 engineer-01
  $0 list
  $0 gpu cohort-2024-q1 --json

EOF
    exit 1
}

get_tfstate_bucket() {
    local account_id
    account_id=$(aws sts get-caller-identity --query Account --output text)
    echo "k0rdent-training-tfstate-${account_id}"
}

check_instance_status() {
    local instance_id="$1"
    local status

    status=$(aws ec2 describe-instances \
        --instance-ids "$instance_id" \
        --query 'Reservations[0].Instances[0].State.Name' \
        --output text 2>/dev/null || echo "unknown")

    echo "$status"
}

show_shared_status() {
    log_info "Shared Infrastructure Status"
    echo "================================"

    local env_dir="$TERRAFORM_DIR/environments/shared"
    local tfstate_bucket
    tfstate_bucket=$(get_tfstate_bucket)

    cd "$env_dir" 2>/dev/null || {
        log_error "Shared infrastructure not found"
        return 1
    }

    terraform init -backend-config="bucket=${tfstate_bucket}" \
        -backend-config="key=shared/terraform.tfstate" \
        -backend-config="region=${REGION}" &>/dev/null || true

    if terraform output vpc_id &>/dev/null; then
        echo -e "${GREEN}Status:${NC} Provisioned"
        echo -e "${CYAN}VPC ID:${NC} $(terraform output -raw vpc_id)"
        echo -e "${CYAN}NAT Gateway IP:${NC} $(terraform output -raw nat_gateway_ip)"
        echo -e "${CYAN}TFState Bucket:${NC} $(terraform output -raw tfstate_bucket)"
        echo -e "${CYAN}Artifacts Bucket:${NC} $(terraform output -raw artifacts_bucket)"
        echo -e "${CYAN}Images Bucket:${NC} $(terraform output -raw images_bucket)"
    else
        echo -e "${YELLOW}Status:${NC} Not provisioned"
    fi
    echo ""
}

show_metal3_status() {
    local engineer_id="$1"
    log_info "Metal3 Dev Environment Status - $engineer_id"
    echo "================================================"

    local env_dir="$TERRAFORM_DIR/environments/metal3-dev"
    local tfstate_bucket
    tfstate_bucket=$(get_tfstate_bucket)

    cd "$env_dir" 2>/dev/null || {
        log_error "Metal3 environment directory not found"
        return 1
    }

    terraform init -backend-config="bucket=${tfstate_bucket}" \
        -backend-config="key=metal3-dev/${engineer_id}/terraform.tfstate" \
        -backend-config="region=${REGION}" &>/dev/null || true

    if terraform output controller_instance_id &>/dev/null; then
        local instance_id
        instance_id=$(terraform output -raw controller_instance_id)
        local status
        status=$(check_instance_status "$instance_id")

        case $status in
            running)
                echo -e "${GREEN}Status:${NC} Running"
                ;;
            stopped)
                echo -e "${YELLOW}Status:${NC} Stopped"
                ;;
            *)
                echo -e "${RED}Status:${NC} $status"
                ;;
        esac

        echo -e "${CYAN}Instance ID:${NC} $instance_id"
        echo -e "${CYAN}Private IP:${NC} $(terraform output -raw controller_private_ip)"
        echo ""

        local connection_info
        connection_info=$(terraform output -json connection_info 2>/dev/null || echo "{}")
        echo -e "${CYAN}k0s Version:${NC} $(echo "$connection_info" | jq -r '.k0s_version // "N/A"')"
        echo -e "${CYAN}Metal3 Version:${NC} $(echo "$connection_info" | jq -r '.metal3_version // "N/A"')"
    else
        echo -e "${YELLOW}Status:${NC} Not provisioned"
    fi
    echo ""
}

show_kubevirt_status() {
    local engineer_id="$1"
    log_info "KubeVirt Lab Status - $engineer_id"
    echo "========================================"

    local env_dir="$TERRAFORM_DIR/environments/kubevirt-lab"
    local tfstate_bucket
    tfstate_bucket=$(get_tfstate_bucket)

    cd "$env_dir" 2>/dev/null || {
        log_error "KubeVirt environment directory not found"
        return 1
    }

    terraform init -backend-config="bucket=${tfstate_bucket}" \
        -backend-config="key=kubevirt-lab/${engineer_id}/terraform.tfstate" \
        -backend-config="region=${REGION}" &>/dev/null || true

    if terraform output controller_instance_id &>/dev/null; then
        local instance_id
        instance_id=$(terraform output -raw controller_instance_id)
        local status
        status=$(check_instance_status "$instance_id")

        case $status in
            running)
                echo -e "${GREEN}Status:${NC} Running"
                ;;
            stopped)
                echo -e "${YELLOW}Status:${NC} Stopped"
                ;;
            *)
                echo -e "${RED}Status:${NC} $status"
                ;;
        esac

        echo -e "${CYAN}Controller ID:${NC} $instance_id"
        echo -e "${CYAN}Controller IP:${NC} $(terraform output -raw controller_private_ip)"

        local worker_ips
        worker_ips=$(terraform output -json worker_private_ips 2>/dev/null || echo "[]")
        echo -e "${CYAN}Worker IPs:${NC} $worker_ips"

        local connection_info
        connection_info=$(terraform output -json connection_info 2>/dev/null || echo "{}")
        echo -e "${CYAN}k0s Version:${NC} $(echo "$connection_info" | jq -r '.k0s_version // "N/A"')"
        echo -e "${CYAN}KubeVirt Version:${NC} $(echo "$connection_info" | jq -r '.kubevirt_version // "N/A"')"
    else
        echo -e "${YELLOW}Status:${NC} Not provisioned"
    fi
    echo ""
}

show_gpu_status() {
    local session_id="$1"
    log_info "GPU Lab Status - $session_id"
    echo "================================"

    local env_dir="$TERRAFORM_DIR/environments/gpu-lab"
    local tfstate_bucket
    tfstate_bucket=$(get_tfstate_bucket)

    cd "$env_dir" 2>/dev/null || {
        log_error "GPU lab environment directory not found"
        return 1
    }

    terraform init -backend-config="bucket=${tfstate_bucket}" \
        -backend-config="key=gpu-lab/${session_id}/terraform.tfstate" \
        -backend-config="region=${REGION}" &>/dev/null || true

    if terraform output gpu_info &>/dev/null; then
        local gpu_info
        gpu_info=$(terraform output -json gpu_info 2>/dev/null || echo "{}")

        local shared_enabled
        shared_enabled=$(echo "$gpu_info" | jq -r '.shared_enabled // false')

        if [[ "$shared_enabled" == "true" ]]; then
            local shared_ip
            shared_ip=$(terraform output -raw shared_gpu_private_ip 2>/dev/null || echo "N/A")

            if [[ -n "$shared_ip" ]] && [[ "$shared_ip" != "N/A" ]]; then
                echo -e "${GREEN}Shared GPU (4x V100):${NC} Active"
                echo -e "${CYAN}  Instance Type:${NC} $(echo "$gpu_info" | jq -r '.shared_type')"
                echo -e "${CYAN}  Private IP:${NC} $shared_ip"
            else
                echo -e "${YELLOW}Shared GPU:${NC} Not running"
            fi
        fi

        local advanced_enabled
        advanced_enabled=$(echo "$gpu_info" | jq -r '.advanced_enabled // false')

        if [[ "$advanced_enabled" == "true" ]]; then
            local advanced_ip
            advanced_ip=$(terraform output -raw advanced_gpu_private_ip 2>/dev/null || echo "N/A")

            if [[ -n "$advanced_ip" ]] && [[ "$advanced_ip" != "N/A" ]]; then
                echo -e "${GREEN}Advanced GPU (8x A100):${NC} Active"
                echo -e "${CYAN}  Instance Type:${NC} $(echo "$gpu_info" | jq -r '.advanced_type')"
                echo -e "${CYAN}  Private IP:${NC} $advanced_ip"
            fi
        fi

        local connection_info
        connection_info=$(terraform output -json connection_info 2>/dev/null || echo "{}")
        echo -e "${CYAN}Engineer Slots:${NC} $(echo "$connection_info" | jq -r '.engineer_slots // "N/A"')"
        echo -e "${CYAN}Spot Enabled:${NC} $(echo "$gpu_info" | jq -r '.spot_enabled // false')"
    else
        echo -e "${YELLOW}Status:${NC} Not provisioned"
    fi
    echo ""
}

list_environments() {
    log_info "Listing all provisioned environments..."
    echo ""

    local tfstate_bucket
    tfstate_bucket=$(get_tfstate_bucket)

    echo "Terraform State Bucket: $tfstate_bucket"
    echo ""

    # List all state files in S3
    echo "Provisioned Environments:"
    echo "========================="

    aws s3 ls "s3://${tfstate_bucket}/" --recursive 2>/dev/null | \
        grep "terraform.tfstate" | \
        awk '{print $4}' | \
        sed 's|/terraform.tfstate||' | \
        while read -r env; do
            echo "  - $env"
        done || echo "  (none found)"

    echo ""
}

# Load config if exists (created by lab-provision.sh)
if [[ -f "$CONFIG_DIR/lab-config.env" ]]; then
    source "$CONFIG_DIR/lab-config.env"
fi

# Default values - region resolved after arg parsing
REGION=""
JSON_OUTPUT="false"

# Parse arguments
COMMAND=""
IDENTIFIER=""

while [[ $# -gt 0 ]]; do
    case $1 in
        all|shared|metal3|kubevirt|gpu|list)
            COMMAND="$1"
            shift
            if [[ "$COMMAND" != "all" ]] && [[ "$COMMAND" != "shared" ]] && [[ "$COMMAND" != "list" ]]; then
                if [[ $# -gt 0 ]] && [[ ! "$1" =~ ^-- ]]; then
                    IDENTIFIER="$1"
                    shift
                fi
            fi
            ;;
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
        *)
            log_error "Unknown option: $1"
            usage
            ;;
    esac
done

[[ -z "$COMMAND" ]] && COMMAND="all"

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

case $COMMAND in
    all)
        show_shared_status
        list_environments
        ;;
    shared)
        show_shared_status
        ;;
    metal3)
        [[ -z "$IDENTIFIER" ]] && { log_error "Engineer ID required"; usage; }
        show_metal3_status "$IDENTIFIER"
        ;;
    kubevirt)
        [[ -z "$IDENTIFIER" ]] && { log_error "Engineer ID required"; usage; }
        show_kubevirt_status "$IDENTIFIER"
        ;;
    gpu)
        [[ -z "$IDENTIFIER" ]] && { log_error "Session ID required"; usage; }
        show_gpu_status "$IDENTIFIER"
        ;;
    list)
        list_environments
        ;;
esac
