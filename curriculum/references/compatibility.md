# Compatibility and lifecycle notes

Use the [course guide](../README.md) for execution order. These notes resolve historical cross-references in the supporting labs; they do not certify a new hardware or product combination.

## Required transitions

- Retain management throughout the selected course. Complete production/RBAC configuration before provisioning the first child cluster.
- Keep the child cluster and KOF through services, management upgrade and API audit. Capture audit evidence before child teardown, even where older prose suggests stopping after the upgrade.
- The management sequence upgrades Enterprise 1.3.1 to 1.3.2. KOF remains 1.6.0 with its documented child ingest and cert-manager ownership.
- GPU bootstrap uses GPU Operator 25.3.0, Ubuntu 22.04 and the documented k0s containerd paths. The recorded 25.10 toolkit/runc issue is not resolved by changing a version in an example. TensorRT has a separate driver ≥575 compatibility gate.
- KAI changes explicitly from 0.12.10 in GPU setup to 0.14.0 in the scheduler lab. Recheck queues and PodGroups after that transition. The source vLLM pin is v0.14.0.
- The existing baseline is one g5.12xlarge worker with four A10G GPUs. Multi-worker gang/distributed sections require additional capacity; MIG needs different compatible hardware. A single-GPU adaptation still needs qualification.

## Historical lab-number corrections

| Reference you may encounter | Correct destination |
|---|---|
| Labs 5.8 and 5.15 refer to 5.2 as vLLM | [vLLM inference, 5.5](../modules/inference-and-data/labs/vllm-inference.md); 5.2 is the service catalog. |
| Training lab refers to RDMA as 5.14 | [RDMA, 5.15](../modules/distributed-ai/labs/rdma-multi-cloud.md). |
| Training lab refers to Run:ai as 5.11 | [Run:ai, 5.4](../extensions/licensed-orchestration/labs/runai-gpu-orchestration.md). |
| Troubleshooting lists all 5.1–5.5 as prerequisites | Run:ai is elective; the KAI route uses 5.1→5.2→5.3→5.5→5.6. |
| Legacy capstone assumes the original broader program | Use [Customer handover](../modules/capstone/labs/customer-handover.md) for the current course. |

## Between exercises

Keep shared GPU resources only while continuing dependent exercises. Remove exercise-local jobs and restore queue/sharing configuration before the next experiment; benchmarks need a known allocation baseline. Use one documented scheduler path. At final cleanup keep provider credentials valid and account for nodes, volumes, load balancers and networking, not only Pods.

For exact hardware/access requirements use the [GPU contract](../modules/gpu-systems/resources/lab-contract.md). For missing product sources, GPU qualification and the evidence required before runtime credit, use the [execution contract](pedagogy/evidence-contract.md).
