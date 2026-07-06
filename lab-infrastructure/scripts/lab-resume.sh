#!/bin/bash
# k0rdent Training Lab - Resume a paused environment
#
# Starts the stopped lab EC2 instances AND refreshes the AWS credentials in
# the management cluster. The refresh step is NOT optional after a long pause:
# environments configured with Lab 1.3's SSO option hold session credentials
# that expire in 1-12 hours, after which every ClusterDeployment fails with
# CAPA "AuthFailure" (found the hard way on 2026-07-03 — see
# docs/plans/2026-07-03-lab-4.4-validation.md).
#
# From your LOCAL machine:
#   aws sso login --profile <your-profile>
#   eval "$(aws configure export-credentials --format env --profile <your-profile>)"
#   ./scripts/lab-resume.sh <your-name>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

usage() {
    cat <<EOF
Resume a paused k0rdent training lab environment.

Usage: $0 <your-name> [options]

Arguments:
  <your-name>           Your unique identifier (same as used in lab-provision.sh)

Options:
  --region <region>     AWS region (defaults to LAB_REGION / AWS_REGION / aws configure)
  --skip-creds          Only start the instances; skip the credential refresh
                        (NOT recommended after a pause longer than a few hours)
  --help                Show this help message

Before running, export fresh AWS credentials:
  aws sso login --profile <your-profile>
  eval "\$(aws configure export-credentials --format env --profile <your-profile>)"

This script will:
  1. Find your stopped lab instances (mgmt node + bastion)
  2. Start them and wait until they are running
  3. Refresh aws-cluster-identity-secret via lab-refresh-creds.sh
  4. Print the connect command
EOF
    exit 1
}

# Parse arguments
REGION=""
SKIP_CREDS="false"
IDENTIFIER=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --region) REGION="$2"; shift 2 ;;
        --skip-creds) SKIP_CREDS="true"; shift ;;
        --help) usage ;;
        -*) log_error "Unknown option: $1"; usage ;;
        *) IDENTIFIER="$1"; shift ;;
    esac
done
[[ -z "$IDENTIFIER" ]] && usage

# Resolve region (same chain as lab-connect.sh)
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

command -v jq &> /dev/null || { log_error "jq is required but not installed. Install: brew install jq (macOS) or sudo apt-get install -y jq (Ubuntu)"; exit 1; }

# Credentials must already work for the AWS calls below
if ! aws sts get-caller-identity &>/dev/null; then
    log_error "AWS credentials not set or expired. Run:"
    echo "  aws sso login --profile <your-profile>"
    echo "  eval \"\$(aws configure export-credentials --format env --profile <your-profile>)\""
    exit 1
fi

# 1. Find the environment's instances (same tags lab-destroy.sh uses)
log_info "Looking up lab instances for '${IDENTIFIER}' in ${REGION}..."
INSTANCE_IDS=$(aws ec2 describe-instances --region "$REGION" \
    --filters "Name=tag:Owner,Values=${IDENTIFIER}" \
              "Name=tag:Project,Values=k0rdent-training" \
              "Name=instance-state-name,Values=stopped,stopping,running,pending" \
    --query 'Reservations[].Instances[].InstanceId' --output text)

if [[ -z "$INSTANCE_IDS" ]]; then
    log_error "No lab instances found for '${IDENTIFIER}' in ${REGION}."
    log_error "Is the environment provisioned? (./scripts/lab-provision.sh ${IDENTIFIER})"
    exit 1
fi
log_info "Found: ${INSTANCE_IDS//$'\t'/, }"

# 2. Start and wait
log_info "Starting instances..."
# shellcheck disable=SC2086
aws ec2 start-instances --region "$REGION" --instance-ids $INSTANCE_IDS >/dev/null
# shellcheck disable=SC2086
aws ec2 wait instance-running --region "$REGION" --instance-ids $INSTANCE_IDS
log_success "Instances running"

# Give sshd/k0s a moment before the refresh step SSHes in
log_info "Waiting 30s for SSH and k0s to come up..."
sleep 30

# 3. Refresh the management cluster's AWS credentials
if [[ "$SKIP_CREDS" == "true" ]]; then
    log_warn "Skipping credential refresh (--skip-creds)."
    log_warn "If ClusterDeployments fail with CAPA AuthFailure, run:"
    log_warn "  ./scripts/lab-refresh-creds.sh ${IDENTIFIER}"
else
    log_info "Refreshing management-cluster AWS credentials..."
    LAB_REGION="$REGION" "$SCRIPT_DIR/lab-refresh-creds.sh" "$IDENTIFIER"
fi

echo ""
log_success "Environment resumed."
echo "  Connect: ./scripts/lab-connect.sh ${IDENTIFIER}"
