# AI-LAB-02 — Memory and concurrency

> **Course step 14 of 21.** [Previous step](../../platform-bootstrap/labs/first-private-response.md) · [Course checklist](../../../README.md) · [Next step](../../gpu-allocation/labs/two-team-queue.md)

**Status:** [draft](../../../README.md#check-runtime-readiness) · **Profile:** GPU-1 candidate · **Guidance:** high

## Prerequisites and input state

- AI-LAB-01 private endpoint and its saved desired state.
- Benchmark client matching vLLM 0.14.0.
- Instructor-approved maximum context, concurrency and allocation deadline.

Keep the driver, operator and model revision unchanged.

## Objectives and problem

Explain why weights that fit in GPU memory can still fail to serve. Set team A's serving envelope and tell device KV-cache pressure from host memory failure.

## Concept capsule

Read [Memory and topology](../lessons/memory-and-topology.md) and redo its example with your model's configuration. Then read the prefill/decode section of [data and performance](../../inference-and-data/lessons/data-and-service-performance.md).

## Hypothesis

Predict how longer inputs, then higher concurrency, change cache occupancy, TTFT and errors. If the runtime preallocates KV memory, which metric will show the pressure?

## Procedure and checkpoints

1. From the model configuration, record layers, KV heads, head dimension, cache dtype and context limit. Estimate weights, KV cache, workspace and headroom with their uncertainty; note host RAM separately.
2. Inventory GPUs and topology with the lab [5.1](gpu-cluster-setup.md) and [5.18](topograph-nvlink-topology.md) tools, and allocatable resources and events with Kubernetes. Trace operator → toolkit/runtime → device plugin → Pod. Don't change the allocator path.
3. Run the AI-LAB-06 benchmark (20 requests, one warmup, output 64, seed 7) three times per condition: input 128 at concurrency 1, input 512 at concurrency 1, then input 512 at concurrency 2 if the envelope allows. Change nothing else and record achieved lengths. This short diagnostic can't give stable tail latencies.
4. Per condition, save the client JSON, server errors, cache metrics, device memory and activity, and timestamps, then compare them with your estimate. Stop at the first failure or the time cap; don't chase an OOM.
5. Tabulate FP32, FP16, BF16, FP8, FP4 and integer quantization: proposed use, model/kernel/hardware evidence needed, quality check and verdict (supported, unknown or rejected). Run only the approved dtype. Draw the CPU, GPU memory and NIC/PCIe/NUMA paths, marking absent NVLink/NVSwitch.

## Interpretation

- Why can device memory stay flat while admission and latency change?
- Which metric separates a full KV pool from a weight-loading failure?
- Why doesn't lower precision double throughput?

## Bounded incident or tradeoff

Reject the instructor's impossible paper budget (for example, a KV cache larger than device memory) and propose a bounded context or concurrency limit. Live failure injection is optional: approved learner-only server, input-limit rejection only.

## Declarative delivery

Save a reviewed serving-configuration diff with your context and concurrency limits, through the mechanism that owns it. Apply no unqualified model or dtype change.

## Restoration and cleanup

Revert to the saved baseline through its owner, rerun the first-response check, stop the load client and note allocated resources. Keep the endpoint.

## Evidence and acceptance

- Memory budget in bytes and GiB, with one estimate-versus-measurement gap explained.
- Dtype table and topology/device chain.
- Raw results for every attempted condition, with before/after configuration.

Runtime acceptance needs measured data; arithmetic alone is [analytical](../../../README.md#check-runtime-readiness) completion.

## Provenance and instructor route

[Evidence contract](../../../references/pedagogy/evidence-contract.md) · [Instructor solutions](../../../instructor/pedagogical-v2/solutions.md#ai-lab-02)
