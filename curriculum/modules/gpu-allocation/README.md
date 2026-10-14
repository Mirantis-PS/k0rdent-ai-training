# GPU allocation

Study scheduling, admission, sharing and hardware partitioning.

**P1 status:** source material relocated and navigation added. Lab procedures and their historical validation statements are retained; no live execution is claimed for this revision.

## Entry state and lifecycle

GPU bootstrap precedes KAI. Retain the explicit KAI version transition. Multi-worker gang tests need multiple nodes; MIG needs a separate compatible GPU. Use the [core learning path](../../learning-paths/core.md) and [prerequisite record](../../migration/PREREQUISITES.md); directory order does not define execution order.

## Preserved material

| Historical ID | Canonical document |
|---|---|
| 5.19 | [Lab 5.19 — Multi-Instance GPU (MIG) Partitioning](labs/mig-partitioning.md) |
| 5.3 | [Lab 5.3 - KAI Scheduler (Open-Source GPU Scheduling)](labs/kai-scheduler.md) |
| Reference | [5.1 GPU Scheduling for AI Workloads](theory/gpu-scheduling.md) |

## Remaining V2 work

P2/P3/P4: add bounded sharing/queue experiments, allocation-versus-admission explanations and a separately compatible DRA path. See the [coverage matrix](../../../docs/curriculum-v2/COVERAGE-MATRIX.md) for required evidence and phase gates.

[All modules](../../README.md) · [Original course index](../../references/original-course.md)
