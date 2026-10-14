# AI-LAB-08 — Diagnose and restore

> **Course step 20 of 21.** [Previous step](../../ai-service-delivery/labs/declarative-release.md) · [Course checklist](../../../README.md) · [Next step](../../capstone/labs/customer-handover.md). Follow this sequence when older lab-number references differ.


**Status:** educational draft; no GPU execution claimed. **Profile:** GPU-1 candidate; supplied evidence analysis if unavailable. **Guidance:** low; symptom and boundaries only.

## Prerequisites and input state

AI-LAB-07 known-good owned release, evidence collection available, instructor-selected fault in a disposable learner scope. Instructor records the hidden change and restoration before injecting it. No cluster-wide driver, fabric or scheduler fault.

## Objectives and problem

Resolve a customer symptom using competing hypotheses, a minimal owned change and verified recovery. Produce a runbook another engineer can replay.

## Concept capsule

Read [Evidence-led operations](../lessons/evidence-led-operations.md). Prepare a timeline with management, admission, Pod, model, data and request layers.

## Hypothesis

After receiving the symptom, write two plausible causes and the cheapest observation that distinguishes them. Predict the result before each diagnostic change; revise rather than retrofitting the hypothesis.

## Procedure and checkpoints

1. Instructor gives the symptom, start time, affected tenant, desired behavior, allowed scope and deadline. You choose the first observations. Capture baseline events, reconciliation state, queue status, startup/request logs and available KOF/DCGM metrics with timestamps.
2. Locate the earliest failing layer. Separate a pending workload, failed device/runtime setup, model-load failure, device OOM, container OOMKilled, slow prefill, storage wait and missing training rank. Eliminate at least one alternative explanation with evidence.
3. Propose one minimal reversible change to the owning configuration. Check its scope and prior revision; execute only within the supplied boundary. If shared configuration would be required, stop mutation and produce the exact owner escalation with evidence.
4. Verify the original user operation, not just Pod readiness. Compare before/after workload, latency/errors and resource state. Reconcile the desired state again or inspect its settled status to ensure the fix persists.
5. Write the runbook, prevention/check proposal, scoped GPU-hours and retained-resource inventory. A partner should be able to follow your evidence chain without the instructor’s hidden fault note.

## Interpretation

What disproved your first guess? Could the same symptom arise at another layer? Why is the chosen fix smaller than a restart of the entire cluster? Which alert would detect the problem without confusing legitimate queueing with failure?

## Bounded incident or tradeoff

The instructor chooses one [fault bank](../../../instructor/pedagogical-v2/fault-bank.md) entry not already rehearsed, keeps a restoration copy and enforces its timeout. Learners see symptoms, not the hidden change. With no GPU, use a clearly labeled hypothetical case or real sanitized capture; this earns analysis credit only.

## Declarative delivery

Attach the minimal configuration diff and prevention check to the AI-LAB-07 release. Identify the owning controller and rollback point. Do not bake transient diagnostic permissions into the release.

## Restoration and cleanup

Instructor confirms original configuration restored, temporary jobs/permissions/forwards removed and service response healthy. Save logs before deletion. Record still-allocated GPUs and expiration; preserve management for the capstone.

## Evidence and acceptance

Incident timeline, competing hypotheses, distinguishing observations, minimal fix, restored service, runbook and cost/resource record. Runtime recovery and analytical diagnosis are scored separately.

## Provenance and instructor route

Derived from [Lab 5.6](troubleshooting-gpu.md), [break/fix API](breakfix-api.md), [KOF](deploy-kof.md), [telemetry](otel-telemetry-export.md) and [audit](api-audit-logging.md).

[Evidence contract](../../../references/pedagogy/evidence-contract.md) · [Learner path](../../../README.md) · [Instructor solutions](../../../instructor/pedagogical-v2/solutions.md#ai-lab-08)
