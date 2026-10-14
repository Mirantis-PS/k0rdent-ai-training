# Distributed AI

Study communication and training, with the original advanced labs retained.

**P1 status:** source material relocated and navigation added. Lab procedures and their historical validation statements are retained; no live execution is claimed for this revision.

## Entry state and lifecycle

The existing RDMA and training labs require specialized networking, multiple workers and their stated storage/operator prerequisites. The affordable two-worker path is not yet implemented. Use the [core learning path](../../learning-paths/core.md) and [prerequisite record](../../migration/PREREQUISITES.md); directory order does not define execution order.

## Preserved material

| Historical ID | Canonical document |
|---|---|
| 5.15 | [Lab 5.15 - Multi-Cloud RDMA Deep Dive: AWS EFA vs Azure InfiniBand](labs/rdma-multi-cloud.md) |
| 5.16 | [Lab 5.16 - Multi-Node Distributed Training](labs/distributed-training.md) |
| Reference | [5.3 GPU Communication and Interconnect Architecture](theory/gpu-communication.md) |
| Reference | [5.4 Distributed Training Patterns](theory/distributed-training.md) |

## Remaining V2 work

P2/P4: derive a real miniature two-worker NCCL/training path on ordinary networking and record actual transport. See the [coverage matrix](../../../docs/curriculum-v2/COVERAGE-MATRIX.md) for required evidence and phase gates.

[All modules](../../README.md) · [Original course index](../../references/original-course.md)
