# Operate from evidence

Lesson ID: AI-CON-07 · Before AI-LAB-08 · Revisit during the capstone.

## Build a timeline across layers

Start from the user's symptom and timestamp, not a favorite tuning flag. Trace desired-state reconciliation, admission, Pod placement, startup and model loading, and request execution. Correlate KOF/Prometheus observations with Pod events and application logs. DCGM can expose device memory, activity and power through a configured exporter, but check per-process attribution and sharing-mode limits; GPU activity alone proves neither useful work nor the cause of latency.

For distributed work, add rank startup, rendezvous, collective timings, transport logs and network errors; for serving, request rate, queueing, prefill/decode, cache occupancy and errors; for storage, bytes/time, loader wait and checkpoint intervals. Keep a short before/during/after window, and don't merge unsynchronized clocks into a false causal sequence.

## Diagnose with competing explanations

A slow response may be queueing, long prefill, repeated weight loading, throttling or an overloaded downstream retriever. Form two plausible hypotheses and pick a low-risk observation that separates them. A pending Pod may be a legitimate quota wait. A CUDA allocation error differs from a container OOMKilled event, so collect the termination reason and application error. A collective timeout may be a missing rank or a transport failure; verify participants before blaming bandwidth.

Change the smallest owned configuration that tests the hypothesis, recording the diff, expected observation and timeout. If the result doesn't support the hypothesis, restore and revise. Don't touch shared drivers, global scheduling or the network fabric as a shortcut; a learner namespace doesn't isolate cluster-wide operator changes.

## Close an incident

A fix is complete when the original user operation succeeds, the intended state survives reconciliation and temporary objects and permissions are gone. Keep a runbook: symptom, scope, hypotheses, evidence, minimal change, validation, rollback and prevention. Add one observable alert condition with a rationale, without inventing universal thresholds from a short lab.

Record GPU allocation time and retained resources, including volumes, load balancers and cloud nodes; deleting a client Pod doesn't release a GPU node. Keep management resources the next labs need, then follow the original lifecycle cleanup at the final authorized boundary. Keep credentials and private payloads out of evidence commits.

## Decision exercise

An interactive service slows while team B checkpoints. List observations that separate storage contention from admission policy or KV pressure, choose a reversible test and say which owner must approve a shared change. After recovery, calculate scoped GPU-hours and separate billable allocation from useful workload time. What would need an independent replay before you publish the runbook?

## Source bridge

Use [GPU troubleshooting](../labs/troubleshooting-gpu.md), [KOF](../labs/deploy-kof.md), [telemetry export](../labs/otel-telemetry-export.md), [API audit](../labs/api-audit-logging.md) and the [fault bank](../../../instructor/pedagogical-v2/fault-bank.md).
