#!/bin/bash
# Regression: grep -c prints zero even when it exits 1; do not append another zero.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
COUNT_LINE=$(sed -n '/^    CAPA_STATUS=$(printf/p' "$ROOT/lab-infrastructure/scripts/lab-refresh-creds.sh")
[[ -n "$COUNT_LINE" ]] || { echo 'Missing credential count implementation'; exit 1; }
for scenario in clean auth expired; do
  case "$scenario" in
    clean) CAPA_LOGS='controller started'; expected=0 ;;
    auth) CAPA_LOGS='AuthFailure: invalid credentials'; expected=1 ;;
    expired) CAPA_LOGS=$'ExpiredTokenException: expired\nRequestExpired: expired'; expected=2 ;;
  esac
  eval "$COUNT_LINE"
  [[ "$CAPA_STATUS" == "$expected" ]] || { printf '%s: expected %s, got <%s>\n' "$scenario" "$expected" "$CAPA_STATUS"; exit 1; }
done
echo 'Credential log count regression checks passed'
