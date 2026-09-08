#!/usr/bin/env bash
# Offline regression checks for preflight failures; never contacts AWS.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURE="$(mktemp -d)"
trap 'rm -rf "$FIXTURE"' EXIT
mkdir -p "$FIXTURE/scripts" "$FIXTURE/bin"
cp "$SCRIPT_DIR/../lab-provision.sh" "$FIXTURE/scripts/"
cat > "$FIXTURE/bin/terraform" <<'MOCK'
#!/bin/bash
echo 'Terraform v1.15.5'
MOCK
cat > "$FIXTURE/bin/aws" <<'MOCK'
#!/bin/bash
printf '%s\n' "$*" >> "$AWS_STUB_LOG"
printf '%s\n' "$AWS_STUB_ERROR" >&2
exit 255
MOCK
chmod +x "$FIXTURE/bin/"*
export PATH="$FIXTURE/bin:$PATH"
export AWS_STUB_LOG="$FIXTURE/aws-calls"
export NO_COLOR=1
failures=0
check_failure() {
    local expected="$1"
    export AWS_STUB_ERROR="$expected"
    : > "$AWS_STUB_LOG"
    if bash "$FIXTURE/scripts/lab-provision.sh" qa-test --region eu-west-1 --auto-approve > "$FIXTURE/output" 2>&1; then
        echo "FAIL: preflight unexpectedly succeeded"
        failures=$((failures + 1))
        return
    fi
    if ! grep -Fq "$expected" "$FIXTURE/output"; then
        echo "FAIL: underlying AWS error was suppressed"
        failures=$((failures + 1))
    fi
    if grep -Fq 'AWS credentials not configured' "$FIXTURE/output"; then
        echo "FAIL: all AWS errors were misclassified as missing credentials"
        failures=$((failures + 1))
    fi
    if [[ "$(wc -l < "$AWS_STUB_LOG" | tr -d ' ')" != 1 ]] ||
       ! grep -Fq 'sts get-caller-identity --region eu-west-1' "$AWS_STUB_LOG"; then
        echo "FAIL: expected only the selected-region STS check, no provisioning calls"
        failures=$((failures + 1))
    fi
}
check_failure 'Could not connect to the endpoint URL: "https://sts.eu-west-1.amazonaws.com/"'
check_failure 'An error occurred (ExpiredToken) when calling the GetCallerIdentity operation: token expired'
if bash "$FIXTURE/scripts/lab-provision.sh" --help >/dev/null 2>&1; then
    :
else
    echo "FAIL: --help should return success"
    failures=$((failures + 1))
fi
if bash "$FIXTURE/scripts/lab-provision.sh" >/dev/null 2>&1; then
    echo "FAIL: missing arguments should return failure"
    failures=$((failures + 1))
fi
[[ "$failures" == 0 ]] || exit 1
echo "PASS: AWS diagnostics preserved, selected region used, no provisioning after failure, help exit codes correct"
