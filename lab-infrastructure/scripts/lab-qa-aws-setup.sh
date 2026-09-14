#!/usr/bin/env bash
# Read-only AWS preflight. Saves profile selection, never access keys.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILE="${AWS_PROFILE:-default}"
REGION=""
PROMPT=true
while [[ $# -gt 0 ]]; do
    case "$1" in
        --profile|--region)
            [[ $# -ge 2 && -n "$2" && "$2" != --* ]] || { echo "Missing value for $1" >&2; exit 2; }
            if [[ "$1" == --profile ]]; then PROFILE="$2"; PROMPT=false; else REGION="$2"; fi
            shift 2 ;;
        -h|--help)
            echo "Usage: bash lab-qa-aws-setup.sh [--profile NAME] [--region REGION]"
            echo "Verifies an existing profile; writes config/qa-aws.env and qa-aws.fish. No provisioning."
            exit 0 ;;
        *) echo "Unknown argument: $1" >&2; exit 2 ;;
    esac
done
for tool in aws jq; do
    command -v "$tool" >/dev/null || { echo "Missing command: $tool" >&2; exit 1; }
done
[[ "$(aws --version 2>&1)" == aws-cli/2.* ]] || { echo "AWS CLI v2 required." >&2; exit 1; }
PROFILES="$(aws configure list-profiles)"
printf 'Available profiles:\n%s\n' "$PROFILES"
if [[ -t 0 && "$PROMPT" == true ]]; then
    read -r -p "Profile [$PROFILE]: " selection
    PROFILE="${selection:-$PROFILE}"
fi
FOUND=false
while IFS= read -r candidate; do
    [[ "$candidate" != "$PROFILE" ]] || FOUND=true
done <<< "$PROFILES"
[[ "$FOUND" == true && -n "$PROFILE" ]] || { echo "Unknown profile: $PROFILE" >&2; exit 1; }
aws_profile() {
    env -u AWS_ACCESS_KEY_ID -u AWS_SECRET_ACCESS_KEY -u AWS_SESSION_TOKEN \
        -u AWS_SECURITY_TOKEN -u AWS_DEFAULT_PROFILE \
        AWS_PROFILE="$PROFILE" AWS_PAGER="" AWS_CLI_AUTO_PROMPT=off AWS_MAX_ATTEMPTS=2 \
        aws --profile "$PROFILE" "$@"
}
if [[ -z "$REGION" ]]; then
    REGION="$(aws_profile configure get region 2>/dev/null || true)"
    if [[ -t 0 ]]; then
        read -r -p "Region [${REGION:-specify explicitly}]: " selection
        REGION="${selection:-$REGION}"
    fi
fi
[[ "$REGION" =~ ^[a-z]{2}(-[a-z]+)+-[0-9]+$ ]] || { echo "Supply a valid --region." >&2; exit 2; }
export AWS_REGION="$REGION" AWS_DEFAULT_REGION="$REGION"
printf '\nChecking %s in %s (read-only)...\n' "$PROFILE" "$REGION"
if ! IDENTITY="$(aws_profile sts get-caller-identity --region "$REGION" \
    --cli-connect-timeout 10 --cli-read-timeout 20 --output json)"; then
    echo "Identity check failed; no new configuration saved." >&2
    echo "Connection errors: check network/VPN/proxy or sandbox access." >&2
    echo "Expired SSO: use the command below, then rerun. Invalid keys: repair the profile locally." >&2
    printf '  aws sso login --profile %q\n' "$PROFILE" >&2
    exit 1
fi
ACCOUNT="$(printf '%s' "$IDENTITY" | jq -er '.Account | select(type == "string" and test("^[0-9]{12}$"))')"
ARN="$(printf '%s' "$IDENTITY" | jq -er '.Arn | select(type == "string" and length > 0)')"
printf 'Account: %s\nIdentity: %s\n' "$ACCOUNT" "$ARN"
if ! VPC_COUNT="$(aws_profile ec2 describe-vpcs --region "$REGION" \
    --cli-connect-timeout 10 --cli-read-timeout 20 --query 'length(Vpcs)' --output text)"; then
    echo "EC2 read check failed; check region access and permissions. No new configuration saved." >&2
    exit 1
fi
printf 'EC2 read access: PASS (%s existing VPCs)\n' "$VPC_COUNT"
umask 077
CONFIG_DIR="$SCRIPT_DIR/../config"
mkdir -p "$CONFIG_DIR"
CONFIG_FILE="$CONFIG_DIR/qa-aws.env"
TEMP_FILE="$(mktemp "$CONFIG_DIR/.qa-aws.env.XXXXXX")"
trap 'rm -f "$TEMP_FILE"' EXIT
{
    echo '# Local QA selection; no credentials. Clears inherited keys to select the profile.'
    echo 'unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_SECURITY_TOKEN AWS_DEFAULT_PROFILE'
    printf 'export AWS_PROFILE=%q\n' "$PROFILE"
    printf 'export AWS_REGION=%q\n' "$REGION"
    printf 'export AWS_DEFAULT_REGION=%q\n' "$REGION"
    printf 'export QA_AWS_ACCOUNT_ID=%q\n' "$ACCOUNT"
} > "$TEMP_FILE"
mv "$TEMP_FILE" "$CONFIG_FILE"

# Fish requires its own assignment/erase syntax and string escaping.
fish_quote() {
    local value="$1" i character
    printf "'"
    for ((i=0; i<${#value}; i++)); do
        character="${value:i:1}"
        case "$character" in
            "'"|\\) printf '\\%s' "$character" ;;
            *) printf '%s' "$character" ;;
        esac
    done
    printf "'"
}
FISH_FILE="$CONFIG_DIR/qa-aws.fish"
TEMP_FILE="$(mktemp "$CONFIG_DIR/.qa-aws.fish.XXXXXX")"
{
    echo '# Local QA selection for Fish; no credentials.'
    for variable in AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_SECURITY_TOKEN AWS_DEFAULT_PROFILE; do
        printf 'set -e %s\n' "$variable"
    done
    printf 'set -gx AWS_PROFILE %s\n' "$(fish_quote "$PROFILE")"
    printf 'set -gx AWS_REGION %s\n' "$(fish_quote "$REGION")"
    printf 'set -gx AWS_DEFAULT_REGION %s\n' "$(fish_quote "$REGION")"
    printf 'set -gx QA_AWS_ACCOUNT_ID %s\n' "$(fish_quote "$ACCOUNT")"
    echo 'true # Loading succeeds even when a credential variable was already absent.'
} > "$TEMP_FILE"
mv "$TEMP_FILE" "$FISH_FILE"
echo
echo "PASS: identity and EC2 read access verified. No resources created."
echo "Provisioning permissions, quotas and GPU capacity still need separate checks."
printf '\nBash/Zsh:\n  source %q\n' "$CONFIG_FILE"
printf '\nFish:\n  source %s\n' "$(fish_quote "$FISH_FILE")"
echo "Use this selection in the shell where you run the lab scripts."
echo "A failed rerun leaves any previously saved selection unchanged."
