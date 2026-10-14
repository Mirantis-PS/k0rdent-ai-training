# AI-LAB-05 — Storage and cache are different experiments

**Status:** educational draft; no GPU execution claimed. **Profile:** GPU-1 candidate; storage analysis on CPU. **Guidance:** medium-low; learner chooses controls.

## Prerequisites and input state

Restored AI-LAB-01 service and approved storage paths. Instructor provides an isolated cache directory/volume and immutable model revision. Never flush host page caches, delete a shared model cache or clear another tenant’s KV state.

## Objectives and problem

Separate model loading, dataset feeding, checkpoint writes and inference KV/prefix reuse. Recommend storage for team A/B from observable behavior.

## Concept capsule

Read the data paths and prefill/decode sections of [Data and service performance](../lessons/data-and-service-performance.md). Draw four distinct paths before measuring.

## Hypothesis

Predict which phases a warm weight-file cache should shorten and which phases identical prompt prefixes might shorten. State how you will distinguish a repeated file read from a reused KV prefix.

## Procedure and checkpoints

1. Create a four-row data-path table: weights, dataset, checkpoint, KV. For each record origin, durability, access pattern, owner, cache, bottleneck metric and cleanup. Compare object storage, local NVMe, NFS/shared and parallel storage; do not deploy every option.
2. Design a cold/warm startup pair using an instructor-approved disposable model cache. Define cold precisely: empty dedicated model-file cache does not mean a cold registry, OS cache or network. Through the owning desired state, start the same image/model with the empty cache, capture scheduling/image-pull/download/load/readiness timestamps, then restart with retained cache. Record downloaded bytes when available and separate every phase. Repeat three pairs if within the budget; otherwise report sample limitation.
3. Return to a healthy warm server. Prepare two non-sensitive prompt sets with equal token lengths: repeated identical token prefixes versus unrelated prefixes. Freeze suffix/output length, concurrency, model and tokenizer. Run each against documented prefix-cache configuration; isolate runs through the approved learner server restart or supported cache reset. Record cache eligibility/state, TTFT, output rate and errors. Do not assume the first request hits cache or that similar text shares tokens.
4. Inspect the preserved training checkpoint/data-loader sections. Propose an experiment that records loader wait, CPU activity, GPU idle intervals and checkpoint bytes/time together. Use an isolated finite dataset/checkpoint workload only if approved. Without it, submit the plan and interpret the hypothetical symptom: GPU idle rises exactly during checkpoint writes while serving latency also rises. Name another possible cause and a discriminating metric.
5. Decide which registry/MLflow artifact metadata, notebook workspace, vector index or Kubeflow workflow the customer actually needs. Trace how an immutable artifact becomes the served revision. Explain why GDS requires its own supported path and is not proven by a faster warm read.

## Interpretation

Which cache improved startup versus TTFT? What confounders remained? Could prompt-prefix routing improve hit rate while worsening queue imbalance? Why is a vector database not a KV cache? What would a shared storage outage affect after weights are already loaded?

## Bounded incident or tradeoff

Set a nonexistent path only in a disposable learner cache/storage configuration, bounded by the readiness deadline. Observe mount/load failure and restore the approved path. If no isolated writable route exists, perform the failure analysis on the proposed diff instead of mutating shared storage.

## Declarative delivery

Document storage class/path references, artifact revision and cache lifecycle in the owned service configuration. Include eviction/refill, capacity, permissions and durable-data boundaries. Product-managed storage claims remain unresolved pending P3.

## Restoration and cleanup

Restore baseline storage/cache configuration and verify first response. Delete only the dedicated disposable cache after confirming its owner and that no workload references it. Retain no unowned volumes. Do not delete model artifacts or training checkpoints shared by others.

## Evidence and acceptance

Four-path table, cold/warm definitions and timelines, prefix comparison with exact workload, storage recommendation and restoration. Separate live startup/prefix observations from proposed loader/checkpoint/GDS experiments.

## Provenance and instructor route

Derived from [Lab 5.5](vllm-inference.md), [Lab 5.16 checkpoint tasks](../../distributed-ai/labs/distributed-training.md) and [ML platform sources](../../../extensions/ml-platforms/README.md).

[Evidence contract](../../../references/pedagogy/evidence-contract.md) · [Learner path](../../../learning-paths/pedagogical-v2.md) · [Instructor solutions](../../../instructor/pedagogical-v2/solutions.md#ai-lab-05)
