# AI-LAB-03: Two teams and a queue

> **Course step 15 of 21.** [Previous step](../../gpu-systems/labs/memory-concurrency.md) · [Course checklist](../../../README.md) · [Next step](../../distributed-ai/labs/two-worker-proof.md)

**Status:** [draft](../../../README.md#check-runtime-readiness) · **Profile:** GPU-1 serial baseline; GPU-2 for concurrent whole-device proof · **Guidance:** medium, source steps plus your diagnostic choices

## Prerequisites and input state

- AI-LAB-02 saved serving state.
- [5.3](kai-scheduler.md) KAI transition done or scheduled.
- Two learner queues and a short finite GPU job from the instructor, who owns queue changes.

No concurrent Run:ai or Kueue.

## Objectives and problem

Let team B use idle capacity without silently promising team A isolation or latency. Locate waits in admission, placement or startup, and justify a sharing policy.

## Concept capsule

Read [Admission and isolation](../lessons/admission-and-isolation.md) and sketch a job's stages before reading its events.

## Hypothesis

Predict what two whole-device jobs do with one GPU, then what borrowing and higher priority do under the approved policy, and what would prove you wrong.

## Procedure and checkpoints

1. Pause team A's serving through its owning desired state, confirm the device is free and save that revision. With the instructor, adapt the source 5.3 queue and submit-job sections (learner names and approved counts only). Use finite jobs with activeDeadlineSeconds and a recorded maximum duration.
2. Inventory allocatable devices, quotas, borrowing, priority and placement constraints. Submit team A's job, then team B's; on GPU-1 expect serialized whole-device work. Record submission, admission, placement, start and finish times and their sources.
3. Decide whether team B waits on quota or placement; let the first job finish and see whether the second starts. Test borrowing and priority only in the approved isolated configuration, capturing policy and events before and after; a priority number alone doesn't prove preemption.
4. Compare the time-slicing and fractional examples in [5.1](../../gpu-systems/labs/gpu-cluster-setup.md) and the MIG examples in [5.19](mig-partitioning.md) on capacity advertisement, memory isolation, fairness, licensing/hardware and observability. Without an isolated qualified mode the comparison is analytical; don't reconfigure the shared GPU Operator.
5. Draw DeviceClass → ResourceClaimTemplate/ResourceClaim → allocation → Pod with Kubernetes 1.35 semantics. Compare KAI scheduling, Kueue/MultiKueue admission and optional [Run:ai](../../../extensions/licensed-orchestration/labs/runai-gpu-orchestration.md) ownership: installed, only considered, or support unknown.
6. GPU-2 only: run a two-worker gang job from the preserved source and observe joint admission or an explicit wait. A failed one-GPU admission doesn't prove gang execution.

## Interpretation

- Which queue guarantee matters for an online service, and which for an interruptible experiment?
- Does borrowing reserve future capacity?
- What stops two processes consuming each other's memory?
- Why don't more advertised time slices add physical capacity?

## Bounded incident or tradeoff

The instructor adds an impossible node selector to a copy of your job. Within two minutes, read the Pod events, restore the selector in the owned template and resubmit. Why can't more quota fix this?

## Declarative delivery

A commit-ready policy proposal: ownership, nominal quotas, borrowing and priority rationale, placement, rejection and recovery. Apply only approved existing schemas; product-native policy waits on P3.

## Restoration and cleanup

After saving logs, delete only your named jobs, restore any changed queue policy and restore team A's service through its owner. Confirm the first response, no pending learner jobs and no shared scheduler changes.

## Evidence and acceptance

- Both jobs' timeline and the queue/placement diagnosis.
- Sharing matrix and DRA diagram.
- Restored endpoint.

Label GPU-1 serialization, optional concurrent or gang proof and unexecuted sharing modes separately.

## Provenance and instructor route

[Evidence contract](../../../references/pedagogy/evidence-contract.md) · [Instructor solutions](../../../instructor/pedagogical-v2/solutions.md#ai-lab-03)
