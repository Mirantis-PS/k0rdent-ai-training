#!/bin/bash
# k0rdent Training Lab - Refresh AWS Credentials
# Usage: Export your AWS creds, then run this script.
#
# From your LOCAL machine:
#   aws sso login --profile <your-profile>
#   eval "$(aws configure export-credentials --format env --profile <your-profile>)"
#   ./scripts/lab-refresh-creds.sh <your-name>

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
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

usage() {
    cat <<EOF
Refresh AWS credentials in k0rdent management cluster.

Usage: $0 <your-name>

Before running, export your fresh AWS credentials:
  aws sso login --profile <your-profile>
  eval "\$(aws configure export-credentials --format env --profile <your-profile>)"
  $0 <your-name>

This script will:
  1. Verify the credentials work
  2. SSH into the management node via bastion
  3. Update the aws-cluster-identity-secret
  4. Restart the CAPA controller to pick up new credentials
  5. Verify CAPA is healthy
EOF
    exit 1
}

# Parse args
[[ $# -eq 0 ]] && usage
IDENTIFIER="$1"

# Validate credentials are set
if [[ -z "${AWS_ACCESS_KEY_ID:-}" || -z "${AWS_SECRET_ACCESS_KEY:-}" ]]; then
    log_error "AWS credentials not set. Run:"
    echo "  aws sso login --profile <your-profile>"
    echo "  eval \"\$(aws configure export-credentials --format env --profile <your-profile>)\""
    exit 1
fi

# Verify credentials work
log_info "Verifying AWS credentials..."
if ! aws sts get-caller-identity &>/dev/null; then
    log_error "AWS credentials are invalid or expired. Re-run:"
    echo "  aws sso login --profile <your-profile>"
    echo "  eval \"\$(aws configure export-credentials --format env --profile <your-profile>)\""
    exit 1
fi
log_success "Credentials valid: $(aws sts get-caller-identity --query Arn --output text)"

# Load saved config or detect connection info
if [[ -f "$CONFIG_DIR/lab-config.env" ]]; then
    source "$CONFIG_DIR/lab-config.env"
fi

REGION="${LAB_REGION:-${AWS_REGION:-${AWS_DEFAULT_REGION:-}}}"
if [[ -z "$REGION" ]]; then
    REGION=$(aws configure get region 2>/dev/null || true)
fi
if [[ -z "$REGION" ]]; then
    log_error "Cannot determine AWS region. Set AWS_REGION or run lab-provision.sh first."
    exit 1
fi

# Get connection details
get_student_bucket() {
    local account_id
    account_id=$(aws sts get-caller-identity --query Account --output text)
    echo "k0rdent-lab-${IDENTIFIER}-${account_id}-${REGION}"
}

get_state_output() {
    local bucket="$1" output_name="$2"
    aws s3 cp "s3://${bucket}/terraform.tfstate" - 2>/dev/null \
        | jq -r ".outputs.${output_name}.value // empty" 2>/dev/null
}

BUCKET=$(get_student_bucket)
log_info "Using bucket: $BUCKET"

BASTION_IP=$(get_state_output "$BUCKET" "bastion_public_ip")
MGMT_IP=$(get_state_output "$BUCKET" "primary_node_private_ip")

if [[ -z "$BASTION_IP" || -z "$MGMT_IP" ]]; then
    log_error "Could not get bastion/mgmt IPs from Terraform state. Is the lab provisioned?"
    exit 1
fi

log_info "Bastion: $BASTION_IP | Management: $MGMT_IP"

# Get SSH keys
MGMT_KEY="$CONFIG_DIR/keys/${IDENTIFIER}-k0rdent.pem"
BASTION_KEY="$CONFIG_DIR/keys/${IDENTIFIER}-bastion.pem"

if [[ ! -f "$MGMT_KEY" || ! -f "$BASTION_KEY" ]]; then
    log_info "Retrieving SSH keys from state..."
    mkdir -p "$CONFIG_DIR/keys"

    ssh_key=$(get_state_output "$BUCKET" "ssh_private_key")
    bastion_key=$(get_state_output "$BUCKET" "bastion_ssh_private_key")

    if [[ -n "$ssh_key" ]]; then
        echo "$ssh_key" > "$MGMT_KEY" && chmod 600 "$MGMT_KEY"
    fi
    if [[ -n "$bastion_key" ]]; then
        echo "$bastion_key" > "$BASTION_KEY" && chmod 600 "$BASTION_KEY"
    fi
fi

if [[ ! -f "$MGMT_KEY" || ! -f "$BASTION_KEY" ]]; then
    log_error "SSH keys not available."
    exit 1
fi

# Build SSH command
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=15"
PROXY_CMD="ssh ${SSH_OPTS} -i ${BASTION_KEY} -W %h:%p ec2-user@${BASTION_IP}"

# Test SSH connectivity
log_info "Testing SSH connection..."
if ! ssh ${SSH_OPTS} -i "$MGMT_KEY" -o "ProxyCommand=${PROXY_CMD}" ubuntu@"${MGMT_IP}" "echo ok" &>/dev/null; then
    log_error "Cannot SSH to management node. Is the instance running?"
    exit 1
fi
log_success "SSH connection OK"

# Update credentials
log_info "Updating aws-cluster-identity-secret..."
ssh ${SSH_OPTS} -i "$MGMT_KEY" -o "ProxyCommand=${PROXY_CMD}" ubuntu@"${MGMT_IP}" \
    "kubectl delete secret aws-cluster-identity-secret -n kcm-system 2>/dev/null; \
     kubectl create secret generic aws-cluster-identity-secret -n kcm-system \
       --from-literal=AccessKeyID='${AWS_ACCESS_KEY_ID}' \
       --from-literal=SecretAccessKey='${AWS_SECRET_ACCESS_KEY}' \
       --from-literal=SessionToken='${AWS_SESSION_TOKEN:-}'"

log_success "Secret updated"

# Restart CAPA
log_info "Restarting CAPA controller..."
ssh ${SSH_OPTS} -i "$MGMT_KEY" -o "ProxyCommand=${PROXY_CMD}" ubuntu@"${MGMT_IP}" \
    "kubectl rollout restart deployment capa-controller-manager -n kcm-system 2>/dev/null && \
     kubectl rollout status deployment capa-controller-manager -n kcm-system --timeout=60s 2>/dev/null"

log_success "CAPA restarted"

# Verify CAPA is healthy by querying logs from the NEW pod BY NAME.
#
# The previous implementation used a label selector with --since=30s, which
# raced against the old (Terminating) pod's final error lines during the
# rollout window and produced false-positive "CAPA still has credential
# errors" messages when the refresh had actually succeeded. Querying the
# new pod by name avoids the race entirely — the new pod was created AFTER
# the Secret rotation, so by construction its logs cannot contain any
# pre-rotation RequestExpired / AuthFailure entries.
log_info "Verifying CAPA health (waiting 5s for new pod to stabilize)..."
sleep 5

NEW_POD=$(ssh ${SSH_OPTS} -i "$MGMT_KEY" -o "ProxyCommand=${PROXY_CMD}" ubuntu@"${MGMT_IP}" \
    "kubectl get pods -n kcm-system -l cluster.x-k8s.io/provider=infrastructure-aws -o jsonpath='{range .items[*]}{.metadata.creationTimestamp} {.metadata.name}{\"\n\"}{end}' 2>/dev/null | sort | tail -1 | awk '{print \$2}'")

if [[ -z "$NEW_POD" ]]; then
    log_warn "Could not identify new CAPA pod; skipping log verification (CAPA may still be healthy)"
    CAPA_STATUS=0
else
    CAPA_STATUS=$(ssh ${SSH_OPTS} -i "$MGMT_KEY" -o "ProxyCommand=${PROXY_CMD}" ubuntu@"${MGMT_IP}" \
        "kubectl logs -n kcm-system '$NEW_POD' 2>/dev/null | grep -c 'AuthFailure\|RequestExpired' || echo 0")
fi

if [[ "$CAPA_STATUS" == "0" ]]; then
    log_success "CAPA is healthy - no credential errors in new pod${NEW_POD:+ ($NEW_POD)}"
else
    log_error "CAPA still has credential errors${NEW_POD:+ in $NEW_POD}. Check: kubectl logs -n kcm-system ${NEW_POD:-<capa-pod>}"
fi

# Summary
echo ""
echo "============================================"
echo -e "  ${GREEN}Credentials refreshed${NC}"
echo "  Expires: when your SSO session ends"
echo "  Re-run:  $0 $IDENTIFIER"
echo "============================================"
