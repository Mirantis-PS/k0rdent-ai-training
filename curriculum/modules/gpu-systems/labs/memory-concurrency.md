# AI-LAB-02 — Memory and concurrency

> **Course step 14 of 21.** [Previous step](../../platform-bootstrap/labs/first-private-response.md) · [Course checklist](../../../README.md) · [Next step](../../gpu-allocation/labs/two-team-queue.md). Follow this sequence when older lab-number references differ.


**Status:** educational draft; no GPU execution claimed. **Profile:** GPU-1 candidate. **Guidance:** high; bounded matrix.

## Prerequisites and input state

AI-LAB-01 private endpoint and saved desired state; matching vLLM0.14.0 benchmark client; instructor-approved maximum context/concurrency and allocation deadline. No change to driver/operator/model revision.

## Objectives and problem

Explain why fitting model weights is insufficient. Establish a bounded serving envelope for team A and distinguish device cache pressure from host/container memory failure.

## Concept capsule

Read [Memory and topology](../lessons/memory-and-topology.md). Complete the hypothetical calculation, then replace every available term with the actual model’s configuration. Read only the prefill/decode section of [data and performance](../../inference-and-data/lessons/data-and-service-performance.md).

## Hypothesis

Predict the effect of increasing input length and concurrency separately on cache occupancy, TTFT and errors. State whether the runtime preallocates KV memory; predict which metric will expose pressure if total device memory stays flat.

## Procedure and checkpoints

1. Record model layers, KV heads, head dimension, cache dtype and configured context limit. Estimate weights, KV, runtime workspace and explicit uncertainty/headroom. Record host RAM separately. Do not assume model-name parameter count is exact.
2. Capture GPU inventory/topology through the approved tools in source 5.1/5.18, and allocatable resources/events through Kubernetes. Explain device publication from operator → toolkit/runtime → device plugin → Pod. If DRA is proposed, review class/claim/allocation on paper; do not switch allocator paths.
3. Use the AI-LAB-06 benchmark command with 20 requests, one warmup, output64 and fixed seed7 as a short diagnostic, not a statistically stable tail benchmark. Run input128 at concurrency1, then input512 at concurrency1, then input512 at concurrency2 only if within the approved envelope. Repeat each condition three times. Keep all other factors and cache policy fixed; capture achieved lengths.
4. For each condition, collect client result JSON, server errors/cache metrics, device memory/activity and timestamps. Confirm successful/failed request totals. Compare your estimate with configured cache capacity and observed pressure. Stop after the first failed condition or the time cap; do not hunt for a destructive OOM.
5. Build a compatibility decision table for FP32/FP16/BF16/FP8/FP4 and integer quantization: representation, proposed use, required model/kernel/hardware evidence, quality check, supported/unknown/rejected. Only the already approved dtype is executed. Add a diagram of CPU, GPU memory and local NIC/PCIe/NUMA paths; mark absent NVLink/NVSwitch honestly.

## Interpretation

Why can device memory remain nearly constant while admission/latency changes? Which metric differentiates a full KV pool from weight-loading failure? What would doubling GPUs change if you used replicas versus TP? Why does lower precision not automatically imply twice the throughput?

## Bounded incident or tradeoff

Before execution the instructor supplies an intentionally impossible budget on paper (for example KV alone exceeds available device memory). Reject it and propose a bounded context/concurrency change. Live failure injection is optional and restricted to an approved learner-only server; use explicit input-limit rejection rather than deliberate device exhaustion.

## Declarative delivery

Save a reviewed serving-configuration diff for the recommended context and concurrency limits, tied to the actual owning mechanism. Include support evidence and uncertainty; do not apply a model/dtype change without qualification.

## Restoration and cleanup

Return any approved serving changes to the saved baseline through its owner, perform the first-response check, stop the load client and record allocated resources. Keep the endpoint for subsequent work.

## Evidence and acceptance

Budget with bytes/GiB, compatibility table, topology/device chain, raw results for all attempted conditions, before/after configuration and explanation of at least one discrepancy. Runtime acceptance requires measured data; hypothetical arithmetic alone is analytical completion.

## Provenance and instructor route

Derived from [Lab 5.5 memory background/benchmarking](../../inference-and-data/labs/vllm-inference.md), [GPU setup](gpu-cluster-setup.md), [topology](topograph-nvlink-topology.md) and the supplied the original memory-workshop design (retained locally).

[Evidence contract](../../../references/pedagogy/evidence-contract.md) · [Learner path](../../../README.md) · [Instructor solutions](../../../instructor/pedagogical-v2/solutions.md#ai-lab-02)
