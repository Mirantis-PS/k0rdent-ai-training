# Operate from evidence

Lesson ID: AI-CON-07. Read before AI-LAB-08; revisit during the capstone.

## Build a timeline across layers

Start with the user's symptom and timestamp, not a favorite tuning flag. Trace desired-state reconciliation, admission, Pod placement, startup/model loading and request execution. Correlate KOF/Prometheus observations with Pod events and application logs. DCGM can expose device memory, activity and power signals under a configured exporter; per-process attribution and sharing-mode limitations must be checked. GPU activity alone does not prove useful work or the cause of latency.

For distributed work add rank startup, rendezvous, collective timings, transport logs and network errors. For serving add request rate, queueing, prefill/decode, cache occupancy and errors. For storage add bytes/time, loader wait and checkpoint intervals. Preserve a short before/during/after window. Do not aggregate unsynchronized clocks into a false causal sequence.

## Diagnose with competing explanations

A slow response may be queueing, long prefill, repeated weight loading, throttling or an overloaded downstream retriever. Form two plausible hypotheses and select a low-risk observation that distinguishes them. A pending Pod may be a legitimate quota wait. A CUDA allocation error is different from a container OOMKilled event; collect the termination reason and application error. A collective timeout may be a missing rank or transport failure; verify participants before blaming bandwidth.

Change the smallest owned configuration that tests the hypothesis. Record the before/after diff, expected observation and timeout. If the test does not support the hypothesis, restore and revise it. Do not alter shared drivers, global scheduling or network fabric as a shortcut. A learner namespace limits some effects, but does not isolate cluster-wide operator changes.

## Close an incident

A fix is not complete until the original user operation succeeds, the intended state is durable under reconciliation, and temporary objects/permissions are removed. Keep a runbook: symptom, scope, hypotheses, evidence, minimal change, validation, rollback and prevention. Add one observable alert condition with a rationale; do not manufacture universal thresholds from a short lab.

Record GPU allocation time and retained resources, including volumes, load balancers and cloud nodes. Deleting a client Pod does not release a provisioned GPU node. Preserve management resources needed by subsequent labs, then follow the original lifecycle cleanup at the final authorized boundary. Keep credentials and private payloads out of evidence commits.

## Decision exercise

An interactive service slows while team B checkpoints. List observations that could separate storage contention from admission policy or KV pressure. Choose a reversible test and explain which owner must approve a shared change. After recovery, calculate scoped GPU-hours and distinguish billable allocation from useful workload time. Identify what would need an independent replay before publishing the runbook.

## Source bridge

Use [GPU troubleshooting](../labs/troubleshooting-gpu.md), [KOF](../labs/deploy-kof.md), [telemetry export](../labs/otel-telemetry-export.md), [API audit](../labs/api-audit-logging.md), and the [fault bank](../../../instructor/pedagogical-v2/fault-bank.md).
