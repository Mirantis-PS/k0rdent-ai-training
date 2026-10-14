# Communication before scale

Lesson ID: AI-CON-04 · Before AI-LAB-04 · Revisit in AI-LAB-06 and AI-CAP-01.

## What is divided?

Data parallelism replicates a model and splits the examples; DDP synchronizes gradients so replicas update consistently. Tensor parallelism splits tensor computations and exchanges intermediate results. Pipeline parallelism assigns model stages to devices and passes activations between them, so bubbles and microbatching matter. Expert parallelism spreads a mixture-of-experts model's experts, and its routing can make traffic uneven. MoE activates selected experts, so total and active parameters answer different capacity and performance questions.

FSDP shards training state across workers and materializes parameters around computation; ZeRO stages progressively partition optimizer state, gradients and parameters. DeepSpeed and Megatron implement larger training strategies but aren't needed to understand two-worker synchronization. Ray and Kubeflow manage distributed jobs without removing communication or memory requirements. Pick the smallest mechanism that solves the customer's problem before choosing a framework.

## Reason about collectives

For two ranks holding 1 and 2: AllReduce (sum) leaves 3 on both; AllGather leaves [1,2] on both; Broadcast from rank zero copies the source's value to the others. ReduceScatter reduces matching elements, then hands each rank a distinct segment. Every rank must join matching collectives with compatible shapes, types and order, so a missing worker can stall the whole group. NCCL implements GPU collectives; it isn't a training scheduler.

## Transport and topology

TCP is a valid baseline. RDMA bypasses parts of the host data path on supported stacks. InfiniBand and RoCE are different network environments; EFA is an AWS device and software path whose actual provider you must verify. GPUDirect RDMA enables supported NIC-to-GPU transfers and is distinct from GPUDirect Storage. Neither the word NCCL nor a completed AllReduce proves RDMA, NVLink or zero-copy; check logs and counters against topology.

In a leaf/spine fabric, oversubscription caps aggregate traffic between groups. ECMP spreads eligible flows across paths, but one flow doesn't use every path. Rails and GPU/NIC affinity shape which paths are available. On RoCE, ECN marks congestion and PFC pauses selected priorities, and misconfiguration can cause loss or spreading stalls. In the core course you interpret these mechanisms from a supplied topology and symptoms; changing switches, or earning a fabric-operations endorsement, needs a specialized lab.

## Decision exercise

For a model that fits one device but needs more throughput, compare independent serving replicas with sharding. For a model that doesn't fit, explain why replicas can't solve capacity. With two nodes on a slow oversubscribed uplink, predict which parallelism patterns suffer most and name measurements that could falsify that. Work out the two-rank collective values before the miniature exercise; small training may be slower on two GPUs, and correctness plus measured overhead are valid outcomes.

## Source bridge

Adapted from [communication](../theory/gpu-communication.md), [training theory](../theory/distributed-training.md), the [distributed training lab](../labs/distributed-training.md) and the [RDMA lab](../labs/rdma-multi-cloud.md). The [sources](../../../references/pedagogy/sources.md) separate documented API semantics from unqualified hardware combinations.
