#!/bin/bash
set -euo pipefail
endpoint=${1:-http://localhost:49021}
output=${2:-topology-result.txt}
response=$(mktemp)
trap 'rm -f "$response"' EXIT
code=$(curl --silent --show-error --max-time 20 -o "$response" -w '%{http_code}' \
  -H 'Content-Type: application/json' -d '{"provider":{"name":"aws"},"engine":{"name":"k8s"}}' \
  "$endpoint/v1/generate")
[[ $code == 202 ]] || { cat "$response" >&2; echo "Generation HTTP $code" >&2; exit 1; }
# v0.5.0 returns the request UID as plain text, not a JSON object.
TOPOLOGY_REQUEST_UID=$(cat "$response")
[[ -n $TOPOLOGY_REQUEST_UID ]] || { echo 'Empty request UID' >&2; exit 1; }
for ((attempt=1; attempt<=60; attempt++)); do
  code=$(curl --silent --show-error --max-time 20 --get \
    --data-urlencode "uid=$TOPOLOGY_REQUEST_UID" -o "$response" -w '%{http_code}' "$endpoint/v1/topology")
  case "$code" in
    200) cp "$response" "$output"; echo "Topology complete: $output"; exit 0 ;;
    202) sleep 2 ;;
    *) cat "$response" >&2; echo "Topology HTTP $code" >&2; exit 1 ;;
  esac
done
echo 'Topology generation did not complete within the polling budget' >&2
exit 1
