#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
if ! command -v /usr/sbin/sshd >/dev/null; then
  apt-get update -qq
  apt-get install -y --no-install-recommends openssh-server
fi
if [[ ${TRAINING_FRAMEWORK:-none} == megatron ]]; then
  pip install --no-cache-dir --break-system-packages -e /workspace/Megatron-LM
elif [[ ${TRAINING_FRAMEWORK:-none} == deepspeed ]]; then
  pip install --no-cache-dir --break-system-packages transformers==4.47.1 accelerate==1.2.1 deepspeed==0.16.2
elif [[ ${TRAINING_FRAMEWORK:-none} == fsdp ]]; then
  pip install --no-cache-dir --break-system-packages transformers==4.47.1
fi
mkdir -p /var/run/sshd
ssh-keygen -A
cat > /etc/ssh/sshd_mpi.conf <<'CONFIG'
Port 22
PermitRootLogin prohibit-password
PasswordAuthentication no
PubkeyAuthentication yes
StrictModes no
AuthorizedKeysFile /root/.ssh/authorized_keys
CONFIG
exec /usr/sbin/sshd -D -e -f /etc/ssh/sshd_mpi.conf
