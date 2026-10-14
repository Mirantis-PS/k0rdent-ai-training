# Communication before scale

Lesson ID: AI-CON-04. Read before AI-LAB-04; revisit in AI-LAB-06 and AI-CAP-01.

## What is divided?

Data parallelism replicates a model and partitions examples. DDP synchronizes gradients so replicas update consistently. Tensor parallelism divides tensor computations and exchanges intermediate results. Pipeline parallelism assigns model stages to devices and moves activations between stages; bubbles and microbatching matter. Expert parallelism distributes experts in a mixture-of-experts model, whose routing can produce uneven traffic. MoE activates selected experts; total parameters and active parameters are different capacity/performance questions.

FSDP shards training state across workers and materializes needed parameters around computation. ZeRO stages progressively partition optimizer state, gradients and parameters. DeepSpeed and Megatron provide implementations and larger training strategies; they are not prerequisites for understanding two-worker synchronization. Ray and Kubeflow help manage distributed applications/jobs but do not eliminate communication or memory requirements. Select the smallest mechanism that answers the customer's problem before selecting a framework.

## Reason about collectives

For two ranks holding scalars 1 and 2: AllReduce with sum leaves 3 on both; AllGather leaves the ordered values [1,2] on both; Broadcast from rank zero replaces recipients with the source's value. ReduceScatter first reduces matching elements and then distributes distinct segments. All ranks must participate in matching collectives with compatible shapes/types and order. A missing worker can stall the entire group. NCCL implements GPU collective communication, not a training scheduler.

## Transport and topology

TCP is a valid baseline. RDMA avoids parts of the conventional host data path on supported stacks. InfiniBand and RoCE are different network environments; EFA is an AWS device/software path whose actual provider must be verified. GPUDirect RDMA enables supported NIC/GPU transfers; it is distinct from GPUDirect Storage. Neither the word NCCL nor a completed AllReduce proves RDMA, NVLink or zero-copy use. Inspect actual logs and counters alongside topology.

In a leaf/spine fabric, oversubscription limits aggregate traffic between groups. ECMP distributes eligible flows across paths; it is not a promise that a single flow uses every path. Rails and GPU/NIC affinity influence which paths are available. On RoCE networks, ECN marks congestion and PFC pauses selected priorities; incorrect configuration can create loss or spreading stalls. Core learners interpret these mechanisms from a supplied topology and symptom set. They do not modify production switches or earn a fabric-operations endorsement without a specialized lab.

## Decision exercise

For a model that fits one device but needs more throughput, compare independent serving replicas with model sharding. For a model that cannot fit, explain why replicas do not solve capacity. Given two nodes with a slow oversubscribed uplink, predict which parallelism patterns are most sensitive, then name measurements that could falsify the prediction. Draw collective values for two ranks before running the miniature exercise. Small training may be slower on two GPUs; correctness and measured overhead are valid outcomes.

## Source bridge

Adapted from [communication](../theory/gpu-communication.md), [training theory](../theory/distributed-training.md), [distributed training lab](../labs/distributed-training.md) and [RDMA lab](../labs/rdma-multi-cloud.md). [Sources](../../../references/pedagogy/sources.md) separate documented API semantics from unqualified hardware combinations.
