# Core learning path

This P1 path provides navigation through the existing labs. It preserves their prerequisite chain and runtime settings; it does not implement the shorter first-response or affordable GPU variants planned for P2–P4. Read each lab before provisioning and retain its hardware/access gates. Existing validation notes describe historical observations, not an execution of this revision.

## Prepare

Read the [infrastructure prerequisites](../overview/prerequisites.md), [architecture theory](../modules/platform-bootstrap/theory/k0rdent-architecture.md), and [prerequisite and compatibility record](../migration/PREREQUISITES.md). Workstation commands start in the repository root unless a lab explicitly changes directory or connects to a remote host. Moving the document does not change the command working directory.

## Establish management and workload state

| Order | Lab | Required handoff |
|---|---|---|
| 1 | [Lab 1.1](../modules/platform-bootstrap/labs/provision-k0rdent.md) — provision management | Preserve this management cluster throughout the selected course. |
| 2 | [Lab 1.2](../modules/platform-bootstrap/labs/explore-k0rdent-ui.md) — explore UI | Read [components](../modules/platform-bootstrap/theory/k0rdent-components.md); inspect management resources. |
| 3 | [Lab 1.3](../modules/platform-bootstrap/labs/configure-aws-provider.md) — configure AWS provider | Read [providers](../modules/platform-bootstrap/theory/infrastructure-providers.md); establish identity and Credential. |
| 4 | [Lab 1.4](../modules/operations/labs/production-configuration.md) — production configuration | Complete the security/RBAC foundations before managed-cluster provisioning. |
| 5 | [Lab 1.5](../modules/platform-bootstrap/labs/provision-managed-cluster.md) — managed cluster | Retain managed-cluster-01 for KOF, services, upgrade and audit. |
| 6 | [Lab 1.6](../modules/operations/labs/deploy-kof.md) — KOF | Complete child ingest, retain KOF 1.6.0 and the child cluster. |
| 7 | [Lab 1.7](../modules/ai-service-delivery/labs/multicluster-services.md) — multi-cluster services | Keep the route, service baseline and child for continuity checks. |
| 8 | [Lab 1.8](../modules/operations/labs/upgrade-k0rdent.md) — upgrade | Apply the source management 1.3.1 → 1.3.2 transition. Defer final teardown until audit. |
| 9 | [Lab 1.9](../modules/operations/labs/api-audit-logging.md) — API audit | Capture audit evidence before returning to foundation cleanup. Retain management for GPU labs. |

The operations folder contains steps 4, 6, 8 and 9; its position in a module list is not a reason to postpone them. The original README’s older teardown-after-1.8 wording is superseded for this navigation by the later lab-specific audit dependency. Use the [foundation assessment](../references/assessments/foundations-quiz.md) after this chain.

## Follow the preserved GPU path

Read the [GPU lab contract](../modules/gpu-systems/resources/lab-contract.md) before choosing hardware. The existing baseline is one g5.12xlarge worker with four A10G GPUs, not the future one-GPU profile. Some sections require more nodes or specialized hardware. Do not count skipped gated sections as executed.

| Order | Lab | Required handoff |
|---|---|---|
| 10 | [Lab 5.1](../modules/gpu-systems/labs/gpu-cluster-setup.md) — GPU bootstrap | Preserve GPU Operator 25.3.0, Ubuntu 22.04 and k0s runtime paths. Retain shared GPU cluster for the following labs. |
| 11 | [Lab 5.2](../modules/ai-service-delivery/labs/service-catalog.md) — service catalog | Keep management/workload contexts explicit; clean up only the exercise-local resources. |
| 12 | [Lab 5.3](../modules/gpu-allocation/labs/kai-scheduler.md) — KAI scheduler | Explicitly transition KAI 0.12.10 → 0.14.0 and recheck queues/PodGroups. Multi-worker tests need the stated extra nodes. |
| 13 | [Lab 5.5](../modules/inference-and-data/labs/vllm-inference.md) — vLLM inference | Preserve source replica/GPU counts and advanced-section gates; do not reinterpret this as a qualified one-GPU lab. |
| 14 | [Lab 5.6](../modules/operations/labs/troubleshooting-gpu.md) — troubleshooting | Use the existing bounded scenarios, record evidence and restore the environment. |

Read [GPU scheduling](../modules/gpu-allocation/theory/gpu-scheduling.md) before allocation exercises and [inference architecture](../modules/inference-and-data/theory/llm-inference-architecture.md) before serving. The contract makes [Lab 5.4](../extensions/licensed-orchestration/labs/runai-gpu-orchestration.md) Run:AI a licensed alternative, not an additional required scheduler. Do not install competing orchestration stacks just to satisfy old numbering shorthand.

Keep the GPU cluster while progressing between dependent exercises, but remove exercise-local workloads and restore sharing/allocation state as each lab directs. Follow the lab-specific final teardown when stopping the GPU path; management remains needed for other selected labs. Review the [AI-workload assessment](../references/assessments/ai-workloads-quiz.md), distinguishing core questions from specialized topics.

## Select follow-on work by prerequisites

| Area | Existing source | Gate / interpretation |
|---|---|---|
| Reusable delivery | [Lab 5.12](../modules/ai-service-delivery/labs/cluster-templates.md) | Requires GPU bootstrap; catalog recommended. Clean up its test clusters. |
| Telemetry | [Lab 5.17](../modules/operations/labs/otel-telemetry-export.md) | KOF child ingest, DCGM, trusted receiver/access and timestamps. |
| Distributed AI | [Lab 5.15](../modules/distributed-ai/labs/rdma-multi-cloud.md) then [Lab 5.16](../modules/distributed-ai/labs/distributed-training.md) | Read [communication](../modules/distributed-ai/theory/gpu-communication.md) and [training](../modules/distributed-ai/theory/distributed-training.md). Original advanced hardware/storage/operator requirements remain. Historical prerequisite labels incorrectly call RDMA 5.14; actual source is 5.15. |
| Topology | [Lab 5.18](../modules/gpu-systems/labs/topograph-nvlink-topology.md) | Choose KAI or Run:AI. Optional secondary networking uses [Lab 4.4](../extensions/advanced-kubernetes/labs/cilium-multus.md); label simulation is not real NVLink performance proof. |
| MIG | [Lab 5.19](../modules/gpu-allocation/labs/mig-partitioning.md) | Requires compatible MIG hardware and 5.1/5.3; not available on the source A10G baseline. |
| Fleet operations | [Lab 6.2](../modules/operations/labs/breakfix-api.md), [Lab 6.3](../modules/operations/labs/capacity-fleet-apis.md), [Lab 6.4](../modules/operations/labs/sanitization-at-rest-crypto.md) | Retain original prerequisites and in-development status. |
| Original capstone | [Lab 6.6](../modules/capstone/labs/capstone.md) | Broader original-program prerequisites; not yet the new V2 assessment. |

[Optional extensions](../extensions/README.md) preserve bare metal, virtualization, advanced Kubernetes, licensed orchestration, ML platforms, compliance, advanced inference and HPC. They are not mandatory stages. Labs 5.8 and 5.15 have historical vLLM numbering mismatches: vLLM is 5.5, catalog is 5.2. Inspect the [discrepancy record](../migration/PREREQUISITES.md) before using those branches.

## Still to be implemented and qualified

P2 adds the first-response, memory/concurrency, sharing/queue, miniature two-worker, storage/cache and measured-performance experiences, instructor solutions, fault bank and new capstone. P3 supplies actual k0rdent AI product interfaces. P4 qualifies CPU/GPU-1/GPU-2 and specialized execution. P5 independently pilots the course and measures active time, cost and outcomes. See [all 40 coverage requirements](../../docs/curriculum-v2/COVERAGE-MATRIX.md).

## Finish or pause

Follow the existing per-lab restoration and cleanup instructions. Capture foundation audit before child teardown; retain management only when continuing dependent work. Final accounting includes compute, volumes, load balancers and networking. No provisioning, paid execution or cleanup has been performed as part of P0/P1.

[Curriculum modules](../README.md) · [All original content](../references/original-course.md)
