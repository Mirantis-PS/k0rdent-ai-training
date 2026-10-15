# AI-LAB-05: Storage and cache are different experiments

> **Course step 17 of 21.** [Previous step](../../distributed-ai/labs/two-worker-proof.md) · [Course checklist](../../../README.md) · [Next step](performance-decision.md)

**Status:** [draft](../../../README.md#check-runtime-readiness) · **Profile:** GPU-1 candidate; storage analysis on CPU · **Guidance:** medium-low, you choose the controls

## Prerequisites and input state

- Restored AI-LAB-01 service and approved storage paths.
- An isolated cache directory or volume and an immutable model revision from the instructor.

Never flush host page caches, delete a shared model cache or clear another tenant's KV state.

## Objectives and problem

Separate model loading, dataset feeding, checkpoint writes and KV/prefix reuse, then recommend storage for teams A and B from observed behavior.

## Concept capsule

Read the data-path and prefill/decode sections of [Data and service performance](../lessons/data-and-service-performance.md) and draw the four paths before measuring.

## Hypothesis

Predict which phases a warm weight-file cache shortens, which identical prompt prefixes shorten, and how you will tell a repeated file read from a reused KV prefix.

## Procedure and checkpoints

1. Tabulate the four data paths (weights, dataset, checkpoint, KV): origin, durability, access pattern, owner, cache, bottleneck metric, cleanup. Compare object, local NVMe, NFS/shared and parallel storage without deploying each.
2. Time a cold/warm startup pair on an instructor-approved disposable model cache: through the owning desired state, start the same image and model with the cache empty, then kept, timing scheduling, image pull, download, load and readiness separately and recording downloaded bytes. An empty model-file cache says nothing about the registry, OS cache or network. Run three pairs if the budget allows.
3. On a healthy warm server, compare two non-sensitive prompt sets of equal token length, one sharing identical token prefixes and one not, with suffix and output length, concurrency, model and tokenizer frozen. Isolate runs by approved restart or supported cache reset, and record cache eligibility and state, TTFT, output rate and errors. Don't assume the first request hits or that similar text shares tokens.
4. From the [5.16](../../distributed-ai/labs/distributed-training.md) checkpoint and data-loader sections, design an experiment recording loader wait, CPU activity, GPU idle and checkpoint bytes and time together; run it only on an approved isolated workload. Otherwise interpret this symptom: GPU idle rises during checkpoint writes as serving latency rises. Name another cause and a metric that separates them.
5. Choose which of artifact registry/MLflow, notebooks, vector index or Kubeflow the customer needs ([ML platform options](../../../extensions/ml-platforms/README.md)) and trace an immutable artifact to the served revision. Why doesn't a faster warm read prove GDS?

## Interpretation

- Which cache improved startup, which TTFT, and what confounders remain?
- Could prefix-aware routing raise the hit rate but unbalance queues?
- Why is a vector database not a KV cache?
- What does a shared storage outage affect once weights are loaded?

## Bounded incident or tradeoff

Set a nonexistent path in a disposable learner storage configuration, within the readiness deadline, observe the failure and restore the path. Without an isolated writable route, analyze it on the proposed diff.

## Declarative delivery

Record storage class and path references, artifact revision and cache lifecycle (eviction, refill, capacity, permissions, durable-data boundaries) in the owned service configuration. Product-managed storage claims wait on P3.

## Restoration and cleanup

Restore baseline storage and cache configuration and verify the first response. Delete only the disposable cache once its owner confirms nothing uses it; leave no unowned volumes and touch no shared artifacts or checkpoints.

## Evidence and acceptance

- Four-path table.
- Cold/warm definitions and timelines.
- Prefix comparison with the exact workload.
- Storage recommendation and restoration.

Label live startup and prefix observations apart from proposed loader, checkpoint and GDS experiments.

## Provenance and instructor route

[Evidence contract](../../../references/pedagogy/evidence-contract.md) · [Instructor solutions](../../../instructor/pedagogical-v2/solutions.md#ai-lab-05)
