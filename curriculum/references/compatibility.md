# Compatibility and lifecycle notes

The [course guide](../README.md) sets the order. These notes resolve historical cross-references in the supporting labs; they don't certify a new hardware or product combination.

## Required transitions

- Keep management for the whole course, and finish production/RBAC configuration before provisioning the first child cluster.
- Keep the child cluster and KOF through services, management upgrade and API audit. Capture audit evidence before child teardown, even where older text suggests stopping after the upgrade.
- The management sequence upgrades Enterprise 1.3.1 to 1.3.2. KOF stays at 1.6.0 with its documented child ingest and cert-manager ownership.
- GPU bootstrap uses GPU Operator 25.3.0, Ubuntu 22.04, k0s 1.35.4+k0s.0 and the documented k0s containerd paths. Changing an example's version doesn't fix the recorded 25.10 toolkit/runc issue. TensorRT has its own driver ≥575 gate.
- KAI moves from 0.12.10 in GPU setup to 0.14.0 in the scheduler lab; recheck queues and PodGroups afterwards. The source vLLM pin is v0.14.0.
- The baseline is one g5.12xlarge worker with four A10G GPUs. Multi-worker gang and distributed sections need more capacity, MIG needs different compatible hardware, and a single-GPU adaptation still needs qualification.

## Historical lab-number corrections

| Reference you may encounter | Correct destination |
|---|---|
| Labs 5.8 and 5.15 refer to 5.2 as vLLM | [vLLM inference, 5.5](../modules/inference-and-data/labs/vllm-inference.md); 5.2 is the service catalog. |
| Training lab refers to RDMA as 5.14 | [RDMA, 5.15](../modules/distributed-ai/labs/rdma-multi-cloud.md). |
| Training lab refers to Run:ai as 5.11 | [Run:ai, 5.4](../extensions/licensed-orchestration/labs/runai-gpu-orchestration.md). |
| Troubleshooting lists all 5.1–5.5 as prerequisites | Run:ai is elective; the KAI route uses 5.1→5.2→5.3→5.5→5.6. |
| Legacy capstone assumes the original broader program | Use [Customer handover](../modules/capstone/labs/customer-handover.md) for the current course. |

## Between exercises

Keep shared GPU resources only while dependent exercises continue. Remove exercise-local jobs and restore queue and sharing configuration before the next experiment, since benchmarks need a known allocation baseline. Use one documented scheduler path. At final cleanup, keep provider credentials valid and account for nodes, volumes, load balancers and networking, not only Pods.

For hardware and access requirements see the [GPU contract](../modules/gpu-systems/resources/lab-contract.md); for missing product sources, GPU qualification and the evidence needed for runtime credit, see the [execution contract](pedagogy/evidence-contract.md).
