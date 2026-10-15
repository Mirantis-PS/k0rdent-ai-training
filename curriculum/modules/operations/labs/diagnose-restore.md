# AI-LAB-08: Diagnose and restore

> **Course step 20 of 21.** [Previous step](../../ai-service-delivery/labs/declarative-release.md) · [Course checklist](../../../README.md) · [Next step](../../capstone/labs/customer-handover.md)

**Status:** [draft](../../../README.md#check-runtime-readiness) · **Profile:** GPU-1 candidate; supplied evidence if unavailable · **Guidance:** low, symptom and boundaries only

## Prerequisites and input state

- AI-LAB-07 owned release and working evidence collection.
- An instructor-selected fault in a disposable learner scope, with the hidden change and its restoration recorded first.

No cluster-wide driver, fabric or scheduler faults.

## Objectives and problem

Resolve a customer symptom with competing hypotheses, a minimal owned change and verified recovery, and write a runbook another engineer can replay.

## Concept capsule

Read [Evidence-led operations](../lessons/evidence-led-operations.md) and prepare a timeline across management, admission, Pod, model, data and request layers.

## Hypothesis

Given the symptom, write two plausible causes and the cheapest observation that separates them. Predict each diagnostic result first, and revise the hypothesis instead of retrofitting it.

## Procedure and checkpoints

1. You receive the symptom, start time, tenant, desired behavior, scope and deadline; choose the first observations. Capture events, reconciliation and queue state, startup and request logs, and available [KOF](deploy-kof.md) and DCGM metrics with timestamps.
2. Find the earliest failing layer: pending workload, device or runtime setup, model load, device OOM, container OOMKilled, slow prefill, storage wait or missing rank. Rule out at least one alternative with evidence; [GPU troubleshooting](troubleshooting-gpu.md) and [telemetry export](otel-telemetry-export.md) can help.
3. Propose one minimal reversible change to the owning configuration and, after checking scope and prior revision, execute it only within the boundary. If it needs shared configuration, stop and escalate to the owner with evidence.
4. Verify the original user operation, not just Pod readiness. Compare workload, latency, errors and resources before and after, and confirm the fix persists after reconciliation.
5. Write the runbook, a prevention check, scoped GPU-hours and retained resources clearly enough for a partner to follow without the hidden fault note.

## Interpretation

- What disproved your first guess?
- Could another layer cause the same symptom?
- Why is your fix smaller than a cluster restart?
- Which alert would catch this without flagging legitimate queueing?

## Bounded incident or tradeoff

The instructor runs one unrehearsed [fault bank](../../../instructor/pedagogical-v2/fault-bank.md) entry with a restoration copy and timeout; you see only symptoms. Without a GPU, a labeled hypothetical case or sanitized real capture earns analysis credit only.

## Declarative delivery

Attach the minimal diff and prevention check to the AI-LAB-07 release with its owning controller and rollback point, and no leftover diagnostic permissions.

## Restoration and cleanup

The instructor confirms the original configuration, the removal of temporary jobs, permissions and forwards, and a responding service. Save logs first, record allocated GPUs with expiry and keep management for the capstone.

## Evidence and acceptance

- Incident timeline, competing hypotheses and distinguishing observations.
- Minimal fix and restored service.
- Runbook and cost/resource record.

Runtime recovery and analytical diagnosis score separately.

## Provenance and instructor route

[Evidence contract](../../../references/pedagogy/evidence-contract.md) · [Instructor solutions](../../../instructor/pedagogical-v2/solutions.md#ai-lab-08)
