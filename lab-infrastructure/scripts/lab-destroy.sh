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

# Respect NO_COLOR and non-TTY output (piped logs, CI, screen readers)
if [[ -n "${NO_COLOR:-}" || ! -t 1 ]]; then
    RED="" GREEN="" YELLOW="" BLUE="" NC=""
fi

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
  --auto-approve              Skip confirmation prompts (implies --force)
  --force                     Proceed past pre-destroy cleanup warnings without
                              prompting, but still confirm the destroy itself.
                              Needed when the management node is stopped or
                              terminated, so SSH-based cleanup cannot run.
  --delete-bucket             Also delete the student's S3 bucket
  --help                      Show this help message

Examples:
  $0 john-doe
  $0 john-doe --auto-approve
  $0 john-doe --auto-approve --delete-bucket
  $0 john-doe --force            # node already down; skip SSH cleanup gates

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

# Loud warning when pre-destroy cleanup cannot be performed or confirmed.
# Resources created OUTSIDE Terraform (managed-cluster VPCs from CAPA,
# CCM-created load balancers) would be orphaned and keep billing -- the warning
# is therefore ALWAYS printed in full, even when a flag lets us skip the prompt.
#
# The prompt itself is skipped under --force / --auto-approve. Without that,
# the common "my node is already stopped or terminated" case was unrecoverable:
# SSH cleanup fails, this gate is reached, and a non-interactive run hits EOF on
# `read` -- which looks identical to the user declining, so the script exited
# without destroying anything and the environment billed indefinitely.
confirm_orphan_risk() {
    local reason="$1"

    echo ""
    echo -e "${RED}============================================================${NC}"
    echo -e "${RED}WARNING: ${reason}.${NC}"
    echo -e "${RED}${NC}"
    echo -e "${RED}Managed clusters (ClusterDeployments) live in SEPARATE VPCs${NC}"
    echo -e "${RED}that Terraform does NOT manage. If any still exist, their${NC}"
    echo -e "${RED}EC2 instances, NAT gateways, and load balancers will be${NC}"
    echo -e "${RED}ORPHANED by this destroy and KEEP BILLING until you delete${NC}"
    echo -e "${RED}them manually in the AWS console.${NC}"
    echo -e "${RED}============================================================${NC}"
    echo ""

    if [[ "$FORCE" == "true" || "$AUTO_APPROVE" == "true" ]]; then
        local via="--force"
        [[ "$FORCE" == "true" ]] || via="--auto-approve"
        log_warn "Proceeding without prompting (${via}) -- verify in the AWS console afterwards"
        return 0
    fi

    # Not a terminal and no flag given: `read` would hit EOF immediately and be
    # indistinguishable from a decline. Fail loudly with the way out instead.
    if [[ ! -t 0 ]]; then
        log_error "Cannot prompt: stdin is not a terminal (piped, cron, or CI run)."
        log_error "Re-run interactively, or pass --force to proceed past this check."
        exit 1
    fi

    local reply=""
    read -r -p "Proceed with destroy anyway? (y/N): " reply || reply=""
    if [[ ! "$reply" =~ ^[Yy]$ ]]; then
        log_warn "Destruction cancelled. Fix the issue above, or re-run with --force."
        exit 1
    fi
    log_warn "Proceeding at your own risk -- check the AWS console for orphans afterwards"
}

# Ensure the SSH keys for the management node exist locally, retrieving them
# from the Terraform state if needed. Returns 1 if they cannot be obtained.
ensure_ssh_keys() {
    local engineer_id="$1"
    local bucket="$2"
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

    [[ -f "$mgmt_key" && -f "$bastion_key" ]]
}

# Delete managed clusters (ClusterDeployments) BEFORE destroying the
# management cluster. CAPA provisions each managed cluster into its own VPC
# that Terraform knows nothing about -- if the management node dies first,
# those VPCs (EC2, NAT, ELB, EBS) are orphaned and keep billing.
cleanup_managed_clusters() {
    local engineer_id="$1"
    local bucket="$2"

    log_info "Deleting managed clusters (MultiClusterServices + ClusterDeployments)..."

    local bastion_ip mgmt_ip
    bastion_ip=$(get_state_output "$bucket" "bastion_public_ip")
    mgmt_ip=$(get_state_output "$bucket" "primary_node_private_ip")

    if [[ -z "$bastion_ip" || -z "$mgmt_ip" ]]; then
        confirm_orphan_risk "Could not get bastion/management IPs from state -- managed clusters cannot be cleaned up"
        return 0
    fi

    if ! ensure_ssh_keys "$engineer_id" "$bucket"; then
        confirm_orphan_risk "SSH keys not available -- managed clusters cannot be cleaned up"
        return 0
    fi

    local mgmt_key="$CONFIG_DIR/keys/${engineer_id}-k0rdent.pem"
    local bastion_key="$CONFIG_DIR/keys/${engineer_id}-bastion.pem"
    local ssh_opts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=10"
    local proxy_cmd="ssh ${ssh_opts} -i ${bastion_key} -W %h:%p ec2-user@${bastion_ip}"

    log_info "This can take up to 15 minutes per managed cluster..."
    if ssh ${ssh_opts} -i "$mgmt_key" -o "ProxyCommand=${proxy_cmd}" ubuntu@"${mgmt_ip}" \
        'export KUBECONFIG=/home/ubuntu/.kube/config
         # MultiClusterServices first so KSM stops reconciling services
         if kubectl api-resources --api-group=k0rdent.mirantis.com 2>/dev/null | grep -q multiclusterservice; then
             kubectl delete multiclusterservice --all --timeout=120s 2>/dev/null || true
         fi
         # No ClusterDeployment CRD => nothing to clean up
         if ! kubectl api-resources --api-group=k0rdent.mirantis.com 2>/dev/null | grep -q clusterdeployment; then
             echo "No ClusterDeployment CRD found -- nothing to clean up"
             exit 0
         fi
         kubectl delete clusterdeployment --all -n kcm-system --wait=true --timeout=15m || true
         REMAINING=$(kubectl get clusterdeployment -n kcm-system --no-headers 2>/dev/null | wc -l)
         if [ "$REMAINING" -ne 0 ]; then
             echo "ERROR: $REMAINING ClusterDeployment(s) still present"
             exit 1
         fi
         echo "All ClusterDeployments deleted"'; then
        log_success "Managed cluster cleanup complete"
    else
        confirm_orphan_risk "Could not confirm deletion of all ClusterDeployments (SSH failed or deletion timed out)"
    fi
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
        confirm_orphan_risk "Could not get IPs from state -- CCM LoadBalancers cannot be cleaned up"
        return 0
    fi

    # Get SSH keys
    local mgmt_key="$CONFIG_DIR/keys/${engineer_id}-k0rdent.pem"
    local bastion_key="$CONFIG_DIR/keys/${engineer_id}-bastion.pem"

    if ! ensure_ssh_keys "$engineer_id" "$bucket"; then
        confirm_orphan_risk "SSH keys not available -- CCM LoadBalancers cannot be cleaned up"
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
         done' 2>/dev/null \
        || confirm_orphan_risk "Could not SSH to clean up CCM LoadBalancers (instance may already be down)"

    log_success "LoadBalancer cleanup complete"
}

# Sweep for orphan AWS resources that K8s didn't clean up (e.g. Classic ELBs
# from broken hosted-CP service.type=LoadBalancer, their auto-created
# k8s-elb-* security groups). Filtered strictly to the lab VPC.
cleanup_orphan_aws_resources() {
    local bucket="$1"

    local vpc_id
    vpc_id=$(get_state_output "$bucket" "vpc_id")
    if [[ -z "$vpc_id" ]]; then
        log_warn "No vpc_id in state. Skipping orphan AWS resource sweep."
        return 0
    fi

    log_info "Scanning $vpc_id for orphan Classic ELBs and k8s-elb security groups..."

    # Classic ELBs (ELBv1) — k0smotron's hosted-CP creates these via
    # service.type=LoadBalancer, and they orphan if the CP crashes before
    # the Service is reconciled-deleted.
    local orphan_lbs
    orphan_lbs=$(aws elb describe-load-balancers --region "$REGION" \
        --query "LoadBalancerDescriptions[?VPCId=='${vpc_id}'].LoadBalancerName" \
        --output text 2>/dev/null || true)

    local found_any=0
    if [[ -n "$orphan_lbs" && "$orphan_lbs" != "None" ]]; then
        found_any=1
        for lb in $orphan_lbs; do
            log_info "  Deleting orphan Classic ELB: $lb"
            aws elb delete-load-balancer --region "$REGION" --load-balancer-name "$lb" 2>&1 || true
        done
        # Brief wait for ENIs to release before subnet delete
        sleep 15
    fi

    # k8s-elb-* SGs left behind by deleted ELBs (AWS creates them automatically;
    # their orphan status blocks subnet deletion via DependencyViolation).
    local orphan_sgs
    orphan_sgs=$(aws ec2 describe-security-groups --region "$REGION" \
        --filters "Name=vpc-id,Values=${vpc_id}" "Name=group-name,Values=k8s-elb-*" \
        --query 'SecurityGroups[].GroupId' --output text 2>/dev/null || true)

    if [[ -n "$orphan_sgs" && "$orphan_sgs" != "None" ]]; then
        found_any=1
        for sg in $orphan_sgs; do
            log_info "  Deleting orphan k8s-elb SG: $sg"
            aws ec2 delete-security-group --region "$REGION" --group-id "$sg" 2>&1 || true
        done
    fi

    if [[ $found_any -eq 0 ]]; then
        log_info "  (no orphans found)"
    fi
}

# Delete a versioned S3 bucket. `aws s3 rb --force` does NOT handle object
# versions or delete markers; on a versioned bucket it leaves the bucket
# behind silently. This function explicitly clears versions + delete markers
# before removing the bucket itself.
delete_versioned_bucket() {
    local bucket="$1"

    log_info "Deleting student bucket: $bucket"

    # Remove current-version objects (best-effort)
    aws s3 rm "s3://${bucket}" --recursive --quiet 2>&1 || true

    # Versions + delete markers (no-op for non-versioned buckets)
    local versions_json count
    versions_json=$(aws s3api list-object-versions --bucket "$bucket" --output json 2>/dev/null || echo "{}")
    count=$(echo "$versions_json" | jq '((.Versions // []) + (.DeleteMarkers // [])) | length' 2>/dev/null || echo 0)

    if [[ "$count" -gt 0 ]]; then
        log_info "  Removing $count object versions / delete markers..."
        local payload="/tmp/lab-destroy-bucket-$$-versions.json"
        echo "$versions_json" \
            | jq '{Objects: ((.Versions // []) + (.DeleteMarkers // [])) | map({Key: .Key, VersionId: .VersionId})}' \
            > "$payload"
        # Note: delete-objects has a 1000-item limit; lab buckets stay well
        # below that. If a bucket exceeds 1000 versions, paginate here.
        aws s3api delete-objects --bucket "$bucket" --delete "file://${payload}" >/dev/null 2>&1 || true
        rm -f "$payload"
    fi

    if aws s3 rb "s3://${bucket}" 2>&1; then
        log_success "Bucket deleted"
    else
        log_warn "Bucket still has dependencies — may need manual cleanup"
    fi
}

destroy_lab() {
    local engineer_id="$1"
    local bucket
    bucket=$(get_student_bucket "$engineer_id")

    confirm_destroy "all lab resources for $engineer_id"

    local env_dir="$TERRAFORM_DIR/environments/student-lab"
    cd "$env_dir"

    log_info "Initializing Terraform..."
    if ! terraform init -reconfigure \
        -backend-config="bucket=${bucket}" \
        -backend-config="key=terraform.tfstate" \
        -backend-config="region=${REGION}" > /dev/null; then
        log_error "terraform init FAILED -- nothing was destroyed; resources may still be billing."
        log_error "Check the error above (wrong --region? bucket ${bucket} unreachable? expired AWS credentials?) and re-run."
        exit 1
    fi

    local state_list
    state_list=$(terraform state list 2>/dev/null || true)
    if [[ -z "$state_list" ]]; then
        log_warn "Terraform state for $engineer_id is empty -- nothing for Terraform to destroy."
        # Sanity check: state and reality can disagree (wrong region/bucket).
        # Look for live lab instances tagged for this student anyway.
        # NOTE: filter on Owner+Project -- modules override the provider's
        # Environment=student-lab default tag with Environment=lab at the
        # resource level, so Environment is NOT a reliable filter.
        local stray_instances
        stray_instances=$(aws ec2 describe-instances --region "$REGION" \
            --filters "Name=tag:Owner,Values=${engineer_id}" \
                      "Name=tag:Project,Values=k0rdent-training" \
                      "Name=instance-state-name,Values=pending,running,stopping,stopped" \
            --query 'Reservations[].Instances[].InstanceId' --output text 2>/dev/null || true)
        if [[ -n "$stray_instances" ]]; then
            log_error "BUT live EC2 instances tagged Owner=${engineer_id} exist in ${REGION}: ${stray_instances}"
            log_error "State and reality disagree (wrong --region or bucket?). These resources are STILL BILLING."
            log_error "Re-run with the region/identifier used at provision time, or delete them in the AWS console."
            exit 1
        fi
        log_info "AWS sanity check: no live lab instances found for ${engineer_id} in ${REGION}."
        return 0
    fi

    # Delete managed clusters FIRST (they live in separate, Terraform-unknown
    # VPCs), then CCM-provisioned LoadBalancers, then sweep any orphan AWS
    # resources (Classic ELBs / k8s-elb SGs) that broken hosted-CP services
    # leave behind and that would otherwise block VPC teardown, then the
    # infrastructure.
    cleanup_managed_clusters "$engineer_id" "$bucket"
    cleanup_load_balancers "$engineer_id" "$bucket"
    cleanup_orphan_aws_resources "$bucket"

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

    # Optionally delete the S3 bucket (handles versioned buckets + delete markers)
    if [[ "$DELETE_BUCKET" == "true" ]]; then
        delete_versioned_bucket "$bucket"
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
FORCE="false"
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
        --force)
            FORCE="true"
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

# jq is required to read connection details from the Terraform state
command -v jq &> /dev/null || { log_error "jq is required but not installed. Install: brew install jq (macOS) or sudo apt-get install -y jq (Ubuntu)"; exit 1; }

# Execute
destroy_lab "$IDENTIFIER"
