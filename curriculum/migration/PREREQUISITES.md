# Prerequisites and lifecycle at the source baseline

Source: 05b142690db65b79b0a48339568bc5d9df7c8269. This is inspection of existing content, not runtime qualification. The [contract inventory](lab-contract-inventory.json) records source prerequisite/cleanup sections for all 42 labs. The [file inventory](source-inventory.json) supplies original and canonical paths.

## Required state transitions

| Sequence | Required state / transition | Retain until |
|---|---|---|
| 1.1 → 1.2 → 1.3 | Management, UI exploration, AWS identity and Credential | All selected labs complete |
| 1.4 → 1.5 | Production/RBAC foundations, then managed-cluster-01 | KOF, services, upgrade and audit acceptance |
| 1.6 → 1.7 | KOF 1.6.0 including child ingest; fleet services and HTTP route | 1.8 continuity and 1.9 audit checks |
| 1.8 → 1.9 | Management 1.3.1 → 1.3.2; retain child and KOF | Capture audit evidence before returning to teardown |
| 5.1 → 5.2 → 5.3 → 5.5 → 5.6 | Existing guided GPU path; check each hardware/runtime gate | Retain shared GPU cluster while continuing this chain |
| 5.1 → 5.3 | KAI 0.12.10 → explicit 0.14.0 transition; recheck queues/PodGroups | Exercises using this scheduler |
| 5.1 + 5.2 → 5.12 | Catalog/template familiarity and AWS Credential | Delete this lab's test clusters at its cleanup |
| 1.6 + 5.1 → 5.17 | KOF child ingest, DCGM and external receiver | Telemetry acceptance, restart and cleanup |
| 5.3 or 5.4 → 5.18 | Choose one scheduler; actual topology hardware for performance | Restore placement/topology configuration |
| 5.1 + 5.3 → 5.19 | Separate MIG hardware, provider Credential and quota | MIG-specific teardown |
| Specialized distributed path | Communication theory, actual RDMA/EFA/IB gates, two suitable workers, RWX checkpoints, operator CRDs | Checkpoint/transport evidence and cleanup |

Module folders are subject groupings, not execution order. Keep operations labs 1.4, 1.6, 1.8 and 1.9 in the initial prerequisite chain. The shorter first-response path is a P2/P4 derivative, not qualified here.

## Baseline compatibility preserved

- k0s v1.35.4+k0s.0; Enterprise 1.3.1 → 1.3.2 through lab 1.8.
- KOF 1.6.0; preserve the child's cert-manager CRD ownership.
- GPU Operator 25.3.0, Ubuntu 22.04 and documented k0s containerd paths. Preserve the recorded 25.10 toolkit/runc regression and separately gated TensorRT path (driver ≥575).
- KAI 0.12.10 in bootstrap; explicit 0.14.0 scheduler transition. vLLM example pin v0.14.0.
- The source core contract uses one g5.12xlarge worker with four A10G GPUs. This is not the future GPU-1 profile. Multi-node/gang sections require their documented additional capacity.
- AMIs, resource names, model/image/chart pins and configuration remain as sourced. Historical prices/support statements have not been refreshed.

## Discrepancies retained for later resolution

- The old foundation README and some early cleanup prose say teardown after 1.8; later 1.6/1.7/1.8/1.9 instructions retain the child through audit. Navigation follows the more specific audit dependency, then returns to existing teardown instructions.
- Labs 5.8 and 5.15 label 5.2 as vLLM (actual 5.5); lab 5.16 labels 5.14 as RDMA (actual 5.15). Its later Run:AI reference uses 5.11 (actual 5.4). Preserve text and flag these historical mismatches rather than silently changing procedures.
- Lab 5.6 says 5.1–5.5, while the contract makes licensed Run:AI 5.4 elective. The open-KAI path remains 5.1 → 5.2 → 5.3 → 5.5 → 5.6.
- Lab 5.3 lists 2+ GPU nodes; the common base has one four-GPU worker. A move cannot satisfy multi-worker gang tests. Keep those sections gated.
- The GPU setup guide's step numbering and general hardware suggestions remain historical. Lab-specific compatibility gates take precedence over generic advanced-instance suggestions.
- The original capstone spans the old broader program. Preserve it as a legacy capstone; the new assessment is P2/P5.

## Resource lifecycle

P0/P1 execute no provisioning or cleanup. For later lab use, retain management across the selected path and the foundation child through audit. Defer shared GPU teardown while dependent GPU labs continue; clean up exercise-local jobs/policies before the next experiment. Restore exclusive allocation after sharing before benchmarks. At final teardown follow each lab's existing procedure, keep provider credentials valid, and account for load balancers, disks and network resources as well as compute. No resources were provisioned or inspected remotely during inventory.
