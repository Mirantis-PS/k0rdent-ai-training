#!/bin/bash
set -euo pipefail
command -v ssh >/dev/null || { apt-get update -qq; apt-get install -y --no-install-recommends openssh-client; }
SSH_OPTIONS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5)
SSHOPTS="${SSH_OPTIONS[*]}"
while read -r host rest; do
  [[ -n $host && $host != \#* ]] || continue
  ready=false
  for ((attempt=1; attempt<=120; attempt++)); do
    if ssh -n "${SSH_OPTIONS[@]}" "$host" true 2>/dev/null; then ready=true; break; fi
    sleep 5
  done
  $ready || { echo "Worker SSH did not become ready: $host" >&2; exit 1; }
done < /etc/mpi/hostfile
MASTER_ADDR=$(awk 'NF && $1 !~ /^#/ {print $1; exit}' /etc/mpi/hostfile)
export MASTER_ADDR MASTER_PORT=29500
# Operator mounts SSH keys and the hostfile. These options apply to ephemeral lab workers.
exec mpirun --allow-run-as-root --hostfile /etc/mpi/hostfile \
  --mca plm_rsh_args "$SSHOPTS" -x MASTER_ADDR -x MASTER_PORT -x PATH -x LD_LIBRARY_PATH -x NCCL_IB_DISABLE=1 "$@"
