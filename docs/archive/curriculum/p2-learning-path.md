# P2 learner path: deliver and operate a shared AI service

**Complete educational draft; runtime qualification and independent pilot pending.** This additive path derives from the preserved [source course](original-course.md). It changes scaffolding and assessment without deleting original labs or claiming a cheaper profile is already validated. Read the [evidence contract](../../../curriculum/references/pedagogy/evidence-contract.md) first.

## Continuous scenario and starting state

Team A operates a private interactive assistant. Team B runs experiments, batch processing and occasional training. You must explain demand, share scarce GPUs, package a repeatable service and diagnose a new incident. Keep one decision log throughout; revise it when measurements contradict your initial choices.

Complete or demonstrate the equivalent entry state from the [source core path](../../../curriculum/README.md): management bootstrap/provider/production configuration, workload cluster, KOF, multicluster service basics, management upgrade and audit in the documented order. Keep management resources for later work. For GPU work follow source 5.1→5.2→5.3, preserving the KAI transition, then select source 5.5 serving steps. Source5.4 Run:ai is elective. The new GPU-1 route is gated until qualified; do not silently substitute a one-GPU node into a four-GPU manifest. With no access, complete the analytical portions and record blocked runtime checkpoints.

## Sequence and state transitions

| Order | Lab and concept capsule | Input → retained output | Profile and guidance |
|---|---|---|---|
| 1 | [AI-LAB-01 First private response](../../../curriculum/modules/platform-bootstrap/labs/first-private-response.md) | Qualified baseline → private endpoint and ownership map | GPU-1 candidate; guided commands |
| 2 | [AI-LAB-02 Memory and concurrency](../../../curriculum/modules/gpu-systems/labs/memory-concurrency.md) | Endpoint → bounded configuration and budget | GPU-1; guided experiment |
| 3 | [AI-LAB-03 Two teams and a queue](../../../curriculum/modules/gpu-allocation/labs/two-team-queue.md) | Saved serving state → queue policy, restored endpoint | GPU-1 serialization; GPU-2 extension; guided diagnosis |
| 4 | [AI-LAB-04 Two-worker proof](../../../curriculum/modules/distributed-ai/labs/two-worker-proof.md) | Serving paused through owner → real NCCL/DDP evidence, restored baseline | GPU-2 mandatory runtime proof; bounded candidate fixture |
| 5 | [AI-LAB-05 Storage and cache](../../../curriculum/modules/inference-and-data/labs/storage-cache.md) | Restored endpoint → separated startup/KV data paths | GPU-1; learner chooses controls |
| 6 | [AI-LAB-06 Performance decision](../../../curriculum/modules/inference-and-data/labs/performance-decision.md) | Frozen workload → measured recommendation | GPU-1; protocol supplied, decision independent |
| 7 | [AI-LAB-07 Declarative release](../../../curriculum/modules/ai-service-delivery/labs/declarative-release.md) | Known-good service → reusable revision and rollback proof | CPU review + GPU-1 execution; P3 interface gate |
| 8 | [AI-LAB-08 Diagnose and restore](../../../curriculum/modules/operations/labs/diagnose-restore.md) | Owned baseline → incident runbook and recovery | GPU-1; instructor injects one bounded fault |
| 9 | [AI-CAP-01 Customer handover](../../../curriculum/modules/capstone/labs/customer-handover.md) | New requirements/incident → independently reviewable service evidence | GPU-1 plus linked GPU-2 evidence; no recipe |

Read each linked capsule just before its lab, then predict, manipulate, observe, explain and restore. Optional specialized exercises retain all original material and prerequisites; interpreting captures is not a hardware endorsement. A GPU-2 interruption does not block writing the GPU-1 storage, performance, release and incident protocols, but core completion must retain the missing distributed proof.

## Completion and feedback

Submit the common evidence packet plus each lab's specific artifacts. The instructor uses [solutions](../../../curriculum/instructor/pedagogical-v2/solutions.md), [fault bank](../../../curriculum/instructor/pedagogical-v2/fault-bank.md) and [rubric](../../../curriculum/instructor/pedagogical-v2/rubric.md); learners should attempt interpretation before opening them. Log active, reading, waiting and assistance time. The intended 70–80% active share and reduced assistance are pilot hypotheses, not measured results. There is no invented course duration.

Finish with the original teardown procedure only after all evidence and required audit work are saved. Inventory management/workload clusters, GPU nodes, volumes, load balancers and retained caches; assign an owner and expiry to anything intentionally kept. No push, PR, paid execution or product-source assumption is part of completing this draft.
