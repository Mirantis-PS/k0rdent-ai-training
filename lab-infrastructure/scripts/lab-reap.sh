#!/bin/bash
# k0rdent Training Lab Orphan Reaper
# Usage: ./lab-reap.sh [options]
#
# Finds training environments that are still billing after being abandoned.
#
# Why this exists: the TTLHours tag applied by the Terraform modules is
# informational only -- nothing enforces it and nothing terminates anything. The
# expensive leak is not the EC2 instance (students do stop those) but the NAT
# Gateway, which bills per hour it exists regardless of whether any instance is
# running. An environment whose instances are gone but whose VPC survives keeps
# costing roughly $32/month, indefinitely and invisibly.
#
# Two distinct failure modes are reported, because they need different actions:
#
#   orphaned - an available NAT Gateway with NO lab instance left in any state.
#              Structurally stranded: there is no node to SSH into, so
#              lab-destroy.sh's pre-destroy cleanup cannot run. Pure waste.
#   stale    - the environment still has instances (running or stopped) but is
#              far older than its TTLHours tag suggests. Stopped instances are
#              the documented way to pause, so this is not automatically wrong;
#              it just needs a human to confirm it is still wanted. NAT Gateway,
#              EIP and EBS bill the whole time regardless of instance state.
#
# Report-only by default. --delete is opt-in and refuses to touch an environment
# with a running instance unless --force is also given, because a long-running
# lab may be legitimate work in progress.

set -euo pipefail

PROJECT_TAG="k0rdent-training"

# A week is well past any legitimate pause between lab sessions, and far past the
# 8h TTLHours the modules tag by default, while staying loose enough not to
# nag someone mid-course.
DEFAULT_MAX_AGE_DAYS=7

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

log_info() { echo -e "${BLUE}[INFO]${NC} $1" >&2; }
log_success() { echo -e "${GREEN}[OK]${NC} $1" >&2; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1" >&2; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

usage() {
    cat <<EOF
k0rdent Training Lab Orphan Reaper

Finds training environments still billing after being abandoned -- chiefly NAT
Gateways left behind when an environment was partially torn down.

Usage: $0 [options]

Options:
  --region <region>     Region to scan (repeatable). Default: every enabled
                        region that actually contains ${PROJECT_TAG} resources.
  --owner <id>          Only report this owner (the engineer-id used at provision)
  --max-age-days <n>    Flag surviving environments older than this as stale.
                        Default: ${DEFAULT_MAX_AGE_DAYS}
  --json                Emit JSON instead of a human-readable report
  --delete              Delete the flagged environments found (NOT the default)
  --force               With --delete, also delete environments that have a
                        RUNNING instance. Use with care: a long-running lab may
                        be work in progress.
  --help                Show this help message

Statuses:
  orphaned  NAT gateway but no instances at all -- structurally stranded, since
            lab-destroy.sh needs a reachable node. Always pure waste.
  stale     Still has instances but older than --max-age-days. Stopping
            instances is the documented way to pause, so confirm with the owner
            before deleting. NAT/EIP/EBS bill regardless of instance state.
  active    Has a running instance and is within the age threshold.
  idle      Instances all stopped and within the age threshold.

Examples:
  $0                                  # scan everywhere, report only
  $0 --region eu-central-1            # scan one region
  $0 --owner john-doe --json          # machine-readable, single owner
  $0 --max-age-days 30                # only flag environments over a month old
  $0 --region us-west-2 --delete      # delete flagged envs in one region

Exit codes:
  0  scan completed, nothing flagged
  2  scan completed, environments flagged -- useful for CI/cron alerting
  1  an error occurred
EOF
    exit 1
}

# --- rough hourly rates, USD -------------------------------------------------
# Deliberately approximate and only used to size the problem. Rates vary by
# region; NAT and the instance types below follow the figures the curriculum
# already quotes (Lab 1.1 cost table, Lab 1.8 pause guidance).
NAT_HOURLY_USD="0.045"

# Only the instance types the labs actually provision. Anything else contributes
# 0 rather than a guess, and the report says the figures are estimates.
INSTANCE_HOURLY_USD='{
  "t3.medium":  0.042,
  "t3.large":   0.083,
  "t3.xlarge":  0.166,
  "t3.2xlarge": 0.333
}'

# --- AWS helpers -------------------------------------------------------------

# Regions that actually contain lab resources. One cheap VPC count per enabled
# region, so scanning "everywhere" stays fast instead of doing a deep scan of
# every region.
discover_regions() {
    local all region count found=()
    all=$(aws ec2 describe-regions --query 'Regions[].RegionName' --output text 2>/dev/null || true)
    if [[ -z "$all" ]]; then
        log_error "Could not list AWS regions. Check credentials and connectivity."
        exit 1
    fi
    for region in $all; do
        count=$(aws ec2 describe-vpcs --region "$region" \
            --filters "Name=tag:Project,Values=${PROJECT_TAG}" \
            --query 'length(Vpcs)' --output text 2>/dev/null || echo 0)
        if [[ "$count" != "0" && "$count" != "None" && -n "$count" ]]; then
            found+=("$region")
        fi
    done
    printf '%s\n' "${found[@]:-}"
}

# Collect every lab resource in one region as a single JSON document.
collect_region() {
    local region="$1"
    local instances nats eips vpcs volumes

    instances=$(aws ec2 describe-instances --region "$region" \
        --filters "Name=tag:Project,Values=${PROJECT_TAG}" \
                  "Name=instance-state-name,Values=pending,running,stopping,stopped" \
        --query 'Reservations[].Instances[].{id:InstanceId,type:InstanceType,state:State.Name,vpc:VpcId,launch:LaunchTime,owner:Tags[?Key==`Owner`]|[0].Value,ttl:Tags[?Key==`TTLHours`]|[0].Value}' \
        --output json 2>/dev/null || echo '[]')

    nats=$(aws ec2 describe-nat-gateways --region "$region" \
        --filter "Name=tag:Project,Values=${PROJECT_TAG}" \
                 "Name=state,Values=pending,available" \
        --query 'NatGateways[].{id:NatGatewayId,vpc:VpcId,created:CreateTime,owner:Tags[?Key==`Owner`]|[0].Value}' \
        --output json 2>/dev/null || echo '[]')

    eips=$(aws ec2 describe-addresses --region "$region" \
        --filters "Name=tag:Project,Values=${PROJECT_TAG}" \
        --query 'Addresses[].{ip:PublicIp,alloc:AllocationId,assoc:AssociationId,owner:Tags[?Key==`Owner`]|[0].Value}' \
        --output json 2>/dev/null || echo '[]')

    vpcs=$(aws ec2 describe-vpcs --region "$region" \
        --filters "Name=tag:Project,Values=${PROJECT_TAG}" \
        --query 'Vpcs[].{id:VpcId,cidr:CidrBlock,owner:Tags[?Key==`Owner`]|[0].Value}' \
        --output json 2>/dev/null || echo '[]')

    volumes=$(aws ec2 describe-volumes --region "$region" \
        --filters "Name=tag:Project,Values=${PROJECT_TAG}" \
        --query 'Volumes[].{id:VolumeId,size:Size,state:State,owner:Tags[?Key==`Owner`]|[0].Value}' \
        --output json 2>/dev/null || echo '[]')

    jq -n \
        --arg region "$region" \
        --argjson instances "$instances" \
        --argjson nats "$nats" \
        --argjson eips "$eips" \
        --argjson vpcs "$vpcs" \
        --argjson volumes "$volumes" \
        '{region: $region, instances: $instances, nats: $nats, eips: $eips, vpcs: $vpcs, volumes: $volumes}'
}

# Group one region's resources into per-owner environments and decide which are
# orphaned. An environment is orphaned when it has at least one available NAT
# gateway and no instance in running/stopped state.
analyse_region() {
    local region_json="$1" now="$2" nat_rate="$3" max_age="$4"

    jq --arg now "$now" --argjson natrate "$nat_rate" --argjson maxage "$max_age" \
       --argjson instrates "$INSTANCE_HOURLY_USD" '
        def owner_of: .owner // "unknown";
        # The AWS CLI renders timestamps as 2026-02-26T13:46:03+00:00 (and
        # sometimes with fractional seconds), neither of which jq
        # fromdateiso8601 accepts -- it wants a bare Z. Normalise both forms.
        def to_epoch($t): $t | sub("\\.[0-9]+"; "") | sub("\\+00:00$"; "Z") | fromdateiso8601;
        def age_days($t): (to_epoch($now) - to_epoch($t)) / 86400;

        .region as $region
        | [ (.instances[] | {kind:"instance", o:owner_of, v:.}),
            (.nats[]      | {kind:"nat",      o:owner_of, v:.}),
            (.eips[]      | {kind:"eip",      o:owner_of, v:.}),
            (.vpcs[]      | {kind:"vpc",      o:owner_of, v:.}),
            (.volumes[]   | {kind:"volume",   o:owner_of, v:.}) ]
        | group_by(.o)
        | map(
            (map(select(.kind=="instance") | .v)) as $inst
          | (map(select(.kind=="nat")      | .v)) as $nats
          | (map(select(.kind=="eip")      | .v)) as $eips
          | (map(select(.kind=="vpc")      | .v)) as $vpcs
          | (map(select(.kind=="volume")   | .v)) as $vols
          | ($inst | map(select(.state=="running" or .state=="stopped")) | length) as $live
          | {
              region: $region,
              owner: .[0].o,
              instances: $inst,
              nats: $nats,
              eips: $eips,
              vpcs: $vpcs,
              volumes: $vols,
              running: ($inst | map(select(.state=="running")) | length),
              live: $live,
              ttl_hours: ($inst | map(.ttl // empty) | first),
              orphaned: (($nats | length) > 0 and $live == 0),
              oldest_nat_age_days: (
                  if ($nats | length) > 0
                  then ($nats | map(age_days(.created)) | max | floor)
                  else null end
              ),
              nat_monthly_usd: (($nats | length) * $natrate * 24 * 30 | . * 100 | round / 100),
              # Only running instances bill for compute; stopped ones still bill
              # for their EBS volumes, which is not modelled here.
              instance_monthly_usd: (
                  $inst
                  | map(select(.state == "running")
                        | ($instrates[.type] // 0))
                  | add // 0
                  | . * 24 * 30 | . * 100 | round / 100
              )
            }
            | .monthly_usd = ((.nat_monthly_usd + .instance_monthly_usd) * 100 | round / 100)
            | .stale = ((.orphaned | not)
                        and ((.oldest_nat_age_days // 0) > $maxage))
            | .flagged = (.orphaned or .stale)
            | .status = (if .orphaned then "orphaned"
                         elif .stale then "stale"
                         elif .running > 0 then "active"
                         else "idle" end)
          )
    ' <<< "$region_json"
}

human_report() {
    local envs_json="$1"
    local total_orphans total_monthly

    total_orphans=$(jq '[.[] | select(.flagged)] | length' <<< "$envs_json")
    total_monthly=$(jq '[.[] | select(.flagged) | .monthly_usd] | add // 0 | . * 100 | round / 100' <<< "$envs_json")

    echo ""
    echo -e "${CYAN}==========================================${NC}"
    echo -e "${CYAN} k0rdent training lab scan${NC}"
    echo -e "${CYAN}==========================================${NC}"

    if [[ "$(jq 'length' <<< "$envs_json")" == "0" ]]; then
        echo ""
        echo "No ${PROJECT_TAG} resources found."
        return 0
    fi

    local row
    while IFS= read -r row; do
        local owner region status age nat_count inst_summary monthly
        owner=$(jq -r '.owner' <<< "$row")
        region=$(jq -r '.region' <<< "$row")
        status=$(jq -r '.status' <<< "$row")
        age=$(jq -r '.oldest_nat_age_days // "-"' <<< "$row")
        nat_count=$(jq -r '.nats | length' <<< "$row")
        monthly=$(jq -r '.monthly_usd' <<< "$row")
        inst_summary=$(jq -r 'if (.instances | length) == 0 then "none"
                              else ([.instances[] | "\(.type)/\(.state)"] | join(", ")) end' <<< "$row")

        echo ""
        case "$status" in
            orphaned) echo -e "  ${RED}ORPHANED${NC}  ${owner}  (${region})" ;;
            stale)    echo -e "  ${YELLOW}STALE${NC}     ${owner}  (${region})" ;;
            active)   echo -e "  ${GREEN}active${NC}    ${owner}  (${region})" ;;
            *)        echo -e "  ${CYAN}idle${NC}      ${owner}  (${region})" ;;
        esac
        echo "      instances:    ${inst_summary}"
        if [[ "$nat_count" == "0" ]]; then
            echo "      nat gateways: none  ~\$${monthly}/month"
        else
            echo "      nat gateways: ${nat_count} (oldest ${age} days) ~\$${monthly}/month"
        fi
        echo "      eips: $(jq -r '.eips | length' <<< "$row")   vpcs: $(jq -r '.vpcs | length' <<< "$row")   volumes: $(jq -r '.volumes | length' <<< "$row")"
        case "$status" in
            orphaned)
                echo -e "      ${RED}No instances left, but NAT gateway(s) still billing.${NC}"
                echo -e "      ${RED}lab-destroy.sh cannot reach a node here -- use --force, or --delete below.${NC}"
                ;;
            stale)
                echo -e "      ${YELLOW}Older than the ${MAX_AGE_DAYS}-day threshold. Confirm with the owner${NC}"
                echo -e "      ${YELLOW}before deleting -- stopped instances are a documented way to pause.${NC}"
                ;;
        esac
    done < <(jq -c '.[]' <<< "$envs_json")

    echo ""
    echo -e "${CYAN}------------------------------------------${NC}"
    if [[ "$total_orphans" == "0" ]]; then
        echo -e "  ${GREEN}Nothing flagged.${NC}"
    else
        echo -e "  ${RED}${total_orphans} environment(s) flagged, ~\$${total_monthly}/month.${NC}"
        echo ""
        echo "  Rates are rough estimates for sizing only, not a billing query."
        echo "  To clean up an environment you own, prefer:"
        echo "      ./lab-destroy.sh <owner> --region <region>"
        echo "  Or re-run this script with --delete to remove the AWS resources directly."
    fi
    echo ""
}

# Delete an orphaned environment's resources in dependency order.
delete_environment() {
    local env_json="$1"
    local owner region
    owner=$(jq -r '.owner' <<< "$env_json")
    region=$(jq -r '.region' <<< "$env_json")

    log_warn "Deleting environment ${owner} in ${region}..."

    local id
    while IFS= read -r id; do
        [[ -z "$id" ]] && continue
        log_info "  terminating instance $id"
        aws ec2 terminate-instances --region "$region" --instance-ids "$id" >/dev/null 2>&1 || \
            log_warn "  could not terminate $id"
    done < <(jq -r '.instances[].id' <<< "$env_json")

    while IFS= read -r id; do
        [[ -z "$id" ]] && continue
        log_info "  deleting nat gateway $id"
        aws ec2 delete-nat-gateway --region "$region" --nat-gateway-id "$id" >/dev/null 2>&1 || \
            log_warn "  could not delete $id"
    done < <(jq -r '.nats[].id' <<< "$env_json")

    while IFS= read -r id; do
        [[ -z "$id" ]] && continue
        log_info "  releasing eip $id"
        aws ec2 release-address --region "$region" --allocation-id "$id" >/dev/null 2>&1 || \
            log_warn "  could not release $id (may still be associated; retry after the NAT gateway is gone)"
    done < <(jq -r '.eips[] | select(.assoc == null) | .alloc' <<< "$env_json")

    log_warn "  VPC ${owner} left in place: subnet/IGW/route-table ordering is handled"
    log_warn "  correctly by 'terraform destroy'. Run lab-destroy.sh, or remove the VPC"
    log_warn "  in the console once the NAT gateway has finished deleting."
}

# --- argument parsing --------------------------------------------------------

REGIONS=()
OWNER_FILTER=""
OUTPUT_JSON="false"
DO_DELETE="false"
FORCE="false"
MAX_AGE_DAYS="$DEFAULT_MAX_AGE_DAYS"

while [[ $# -gt 0 ]]; do
    case $1 in
        --region)
            [[ -z "${2:-}" ]] && { log_error "--region needs a value"; usage; }
            REGIONS+=("$2")
            shift 2
            ;;
        --owner)
            [[ -z "${2:-}" ]] && { log_error "--owner needs a value"; usage; }
            OWNER_FILTER="$2"
            shift 2
            ;;
        --max-age-days)
            if [[ ! "${2:-}" =~ ^[0-9]+$ ]]; then
                log_error "--max-age-days needs a whole number of days"
                usage
            fi
            MAX_AGE_DAYS="$2"
            shift 2
            ;;
        --json)
            OUTPUT_JSON="true"
            shift
            ;;
        --delete)
            DO_DELETE="true"
            shift
            ;;
        --force)
            FORCE="true"
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

if ! command -v jq &> /dev/null; then
    log_error "jq is not installed but is required."
    exit 1
fi
if ! aws sts get-caller-identity >/dev/null 2>&1; then
    log_error "AWS credentials are not valid. Refresh them and retry."
    exit 1
fi

# --- scan --------------------------------------------------------------------

if [[ ${#REGIONS[@]} -eq 0 ]]; then
    log_info "Discovering regions containing ${PROJECT_TAG} resources..."
    while IFS= read -r r; do
        [[ -n "$r" ]] && REGIONS+=("$r")
    done < <(discover_regions)
    if [[ ${#REGIONS[@]} -eq 0 ]]; then
        log_success "No ${PROJECT_TAG} resources found in any enabled region."
        exit 0
    fi
    log_info "Scanning: ${REGIONS[*]}"
fi

NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
NAT_RATE="$NAT_HOURLY_USD"

ALL_ENVS="[]"
for region in "${REGIONS[@]}"; do
    region_data=$(collect_region "$region")
    region_envs=$(analyse_region "$region_data" "$NOW" "$NAT_RATE" "$MAX_AGE_DAYS")
    ALL_ENVS=$(jq -n --argjson a "$ALL_ENVS" --argjson b "$region_envs" '$a + $b')
done

if [[ -n "$OWNER_FILTER" ]]; then
    ALL_ENVS=$(jq --arg o "$OWNER_FILTER" '[.[] | select(.owner == $o)]' <<< "$ALL_ENVS")
fi

# Sort orphans first, then by age.
ALL_ENVS=$(jq 'sort_by([(if .orphaned then 0 elif .stale then 1 else 2 end), -(.oldest_nat_age_days // 0)])' <<< "$ALL_ENVS")

FLAGGED_COUNT=$(jq '[.[] | select(.flagged)] | length' <<< "$ALL_ENVS")

# --- output / delete ---------------------------------------------------------

if [[ "$DO_DELETE" == "true" ]]; then
    if [[ "$FLAGGED_COUNT" == "0" ]]; then
        log_success "Nothing to delete: no orphaned environments found."
        exit 0
    fi

    skipped=0
    while IFS= read -r env; do
        running=$(jq -r '.running' <<< "$env")
        owner=$(jq -r '.owner' <<< "$env")
        if [[ "$running" != "0" && "$FORCE" != "true" ]]; then
            log_warn "Skipping ${owner}: has ${running} RUNNING instance(s). Pass --force to delete anyway."
            skipped=$((skipped + 1))
            continue
        fi
        delete_environment "$env"
    done < <(jq -c '.[] | select(.flagged)' <<< "$ALL_ENVS")

    [[ "$skipped" -gt 0 ]] && log_warn "${skipped} environment(s) skipped -- re-run with --force to include them."
    log_success "Delete pass complete. Re-run this script to confirm."
    exit 0
fi

if [[ "$OUTPUT_JSON" == "true" ]]; then
    jq -n --arg now "$NOW" --argjson envs "$ALL_ENVS" \
        '{scanned_at: $now,
          flagged_count: ([$envs[] | select(.flagged)] | length),
          orphaned_count: ([$envs[] | select(.orphaned)] | length),
          stale_count: ([$envs[] | select(.stale)] | length),
          estimated_monthly_flagged_usd:
              ([$envs[] | select(.flagged) | .monthly_usd] | add // 0),
          environments: $envs}'
else
    human_report "$ALL_ENVS"
fi

# Exit 2 signals "orphans found" so cron/CI can alert without parsing output.
[[ "$FLAGGED_COUNT" != "0" ]] && exit 2
exit 0
