# AI-LAB-03 — Two teams and a queue

**Status:** educational draft; no GPU execution claimed. **Profile:** GPU-1 serial baseline; GPU-2 for concurrent whole-device proof. **Guidance:** medium; source steps and diagnostic choices.

## Prerequisites and input state

AI-LAB-02 saved serving state. Source5.3 KAI version transition already completed or separately scheduled through its original procedure. Instructor owns queue-level changes and supplies two learner queues plus a short finite GPU job. No concurrent Run:ai/Kueue installation.

## Objectives and problem

Let team B use idle capacity without silently promising team A isolation or latency. Locate waits in admission, placement or application startup, and justify a sharing policy.

## Concept capsule

Read [Admission and isolation](../lessons/admission-and-isolation.md). Sketch the stages for a job before reading its events.

## Hypothesis

Predict what happens when two whole-device jobs request one GPU in total supply. Separately predict what borrowing and higher priority should do under the approved queue policy; name a condition that would falsify the prediction.

## Procedure and checkpoints

1. Pause team A’s serving allocation through its owning desired state and confirm device release. Save that revision for restoration. Read the source 5.3 queue hierarchy and submit-job sections with the instructor; adapt only learner names and approved resource counts. Use finite jobs with activeDeadlineSeconds and a recorded maximum duration.
2. Inventory actual allocatable devices, queue quotas/borrowing, priority and placement constraints. Submit team A’s finite job, then team B’s. On GPU-1 expect serialized whole-device work, not concurrent execution. Record submission, admission, placement, start and finish timestamps plus the source of each timestamp.
3. Explain whether team B is waiting for quota or placement. Let the first job finish naturally; show whether the second progresses. Test borrowing/priority only in the approved isolated queue configuration, recording before/after policy and events. Do not infer preemption from a priority number alone.
4. Review the source time-slicing/fractional and MIG examples. Fill a comparison matrix of capacity advertisement, memory isolation, fairness, licensing/hardware and observability. A live sharing comparison requires an isolated qualified mode; otherwise mark it analytical. Do not reconfigure the shared GPU Operator.
5. Draw a DRA DeviceClass → ResourceClaimTemplate/ResourceClaim → allocation → Pod path using Kubernetes1.35 semantics. Compare KAI scheduling, Kueue/MultiKueue admission/dispatch and optional Run:ai ownership. Document which is installed, which is merely considered and which product support remains unknown.
6. For GPU-2 only, add a two-worker gang candidate from the preserved source: observe all required resources admitted together or an explicit wait. A one-GPU failed admission is not evidence of successful gang execution.

## Interpretation

Which queue guarantee matters for an online service versus an interruptible experiment? Does borrowing reserve future capacity? What prevents two processes from consuming each other’s memory? Explain why more advertised time slices do not increase physical GPU capacity.

## Bounded incident or tradeoff

Instructor adds an impossible node selector to a copy of the finite learner job. Limit it to two minutes, inspect Pod events, then restore the selector in the owned job template and resubmit the disposable job. Explain why raising quota cannot fix this failure.

## Declarative delivery

Commit-ready policy proposal with resource ownership, nominal quotas, borrowing/priority rationale, placement and rejection/recovery behavior. Apply only approved existing schemas; product-native policy remains P3-gated.

## Restoration and cleanup

Delete only named learner jobs after collecting logs, restore the prior queue policy if changed, and restore team A’s service through its owner. Confirm first response and no leftover pending jobs. Keep no shared scheduler changes.

## Evidence and acceptance

Timeline for both jobs, queue/placement diagnosis, sharing comparison, DRA diagram and restored endpoint. Separate GPU-1 serialization, optional concurrent/gang proof and unexecuted sharing modes.

## Provenance and instructor route

Derived from [Lab 5.3](kai-scheduler.md), [Lab 5.19](mig-partitioning.md), [Lab 5.1 Tasks 2–6](../../gpu-systems/labs/gpu-cluster-setup.md) and the preserved [licensed orchestration elective](../../../extensions/licensed-orchestration/labs/runai-gpu-orchestration.md).

[Evidence contract](../../../references/pedagogy/evidence-contract.md) · [Learner path](../../../learning-paths/pedagogical-v2.md) · [Instructor solutions](../../../instructor/pedagogical-v2/solutions.md#ai-lab-03)
