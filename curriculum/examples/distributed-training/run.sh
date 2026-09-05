#!/bin/bash
set -euo pipefail
export RANK=${OMPI_COMM_WORLD_RANK:?MPI rank is required}
export LOCAL_RANK=${OMPI_COMM_WORLD_LOCAL_RANK:?MPI local rank is required}
export WORLD_SIZE=${OMPI_COMM_WORLD_SIZE:?MPI size is required}
: "${MASTER_ADDR:?launcher must set rendezvous host}"
export MASTER_PORT=${MASTER_PORT:-29500}
exec "$@"
