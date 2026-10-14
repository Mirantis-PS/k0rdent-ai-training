# AI-LAB-04 — Two-worker proof

> **Course step 16 of 21.** [Previous step](../../gpu-allocation/labs/two-team-queue.md) · [Course checklist](../../../README.md) · [Next step](../../inference-and-data/labs/storage-cache.md)

**Status:** [draft](../../../README.md#check-runtime-readiness) · **Profile:** two real single-GPU workers; two nodes for cross-node proof · **Guidance:** medium, fixed fixture; you explain the transport

## Prerequisites and input state

- AI-LAB-03 restored state saved.
- From the instructor: two isolated GPU workers with one visible GPU each, the same qualified PyTorch/CUDA/NCCL image, a private rendezvous address and port, and approved scheduling and network policy.

Without GPU access the runtime part is blocked; don't simulate it.

## Objectives and problem

Prove matching collectives and synchronized training on two real workers, and explain correctness, overhead and the actual transport without assuming RDMA.

## Concept capsule

Read [Communication before scale](../lessons/communication-and-parallelism.md). Calculate the four collectives' two-rank values before running, and map DP/TP/PP/EP, FSDP/ZeRO and framework roles to team B's needs.

## Hypothesis

Predict identical parameters across ranks and falling loss, and whether two workers beat one on this tiny fixed batch (a slowdown is fine). What would prove cross-node transport, and what would prove RDMA?

## Procedure and checkpoints

1. Pause serving through its owner and confirm capacity. Use the approved worker/job route from source [5.16](distributed-training.md) and the same checked-in [two-worker.py](../../../examples/pedagogical-v2/two-worker.py) in both containers, installing no MPI, DeepSpeed or Megatron. Record image digest, node/GPU identity and topology, and set a five-minute outer deadline; the process-group timeout doesn't bound rendezvous.
2. Run a one-GPU baseline with the same image and global batch, then the two-worker run, **inside the provisioned worker containers**. The instructor resolves the private MASTER_ADDR and port; open the network only between the two workers.

    ```bash
    # Single worker, from the repository root mounted in its container:
    torchrun --standalone --nnodes=1 --nproc-per-node=1 curriculum/examples/pedagogical-v2/two-worker.py --steps 20 --global-batch 64
    ```

    Run once on each worker, with NODE_RANK=0 on the first and 1 on the second:

    ```bash
    : "${MASTER_ADDR:?set private address reachable by both workers}"
    : "${MASTER_PORT:?set approved rendezvous port}"
    : "${NODE_RANK:?set 0 or 1}"
    NCCL_DEBUG=INFO torchrun --nnodes=2 --nproc-per-node=1 --node-rank="$NODE_RANK" --master-addr="$MASTER_ADDR" --master-port="$MASTER_PORT" curriculum/examples/pedagogical-v2/two-worker.py --steps 20 --global-batch 64
    ```

3. Collect both ranks' logs and JSON summaries and check world_size 2, backend NCCL, distinct hosts, one GPU per worker, passing collectives, finite falling loss and synchronized parameters.
4. Identify the NCCL transport and interface (TCP/socket or the qualified provider); success doesn't prove EFA, RDMA or NVLink. Repeat both runs three times and compare maximum-rank elapsed time. It includes tiny-model overhead and a per-step loss collective, excludes startup, and isn't a scaling benchmark.
5. On a drawn two-leaf/spine fabric where two workers share an oversubscribed uplink and another pair stays local, predict the effects of placement, ECMP, rails, congestion and RoCE ECN/PFC. Label it paper analysis, and use your transport evidence to say when DP, sharding or locality would help.

## Interpretation

- Why must collectives match in order and shape?
- What did DDP synchronize, and what stayed local?
- Why does a fixed global batch matter?
- Which FSDP/ZeRO memory terms differ from DDP?
- Would Ray or Kubeflow remove a network bottleneck?

## Bounded incident or tradeoff

On a disposable repeat, launch only rank 0 under the five-minute deadline and observe the missing-peer rendezvous (the 90-second process-group timeout doesn't apply before initialization). Then stop it and launch both ranks.

## Declarative delivery

Save the worker allocation and launch configuration, immutable image identity, fixture SHA and source ownership. A product-native distributed job schema waits on P3.

## Restoration and cleanup

Stop both launchers, remove your worker jobs through their owner and confirm both GPUs are free; then restore serving, rerun the first-response check and record retained nodes with expiry.

## Evidence and acceptance

- Both rank logs and actual node/device allocation.
- Collective values and parameter agreement.
- Baseline and two-worker timing.
- Transport identification and restored service.

Two GPUs on one host count as local-only evidence; CPU analysis can't pass the two-worker GPU checkpoint.

## Provenance and instructor route

[Evidence contract](../../../references/pedagogy/evidence-contract.md) · [Primary API sources](../../../references/pedagogy/sources.md) · [Instructor solutions](../../../instructor/pedagogical-v2/solutions.md#ai-lab-04)
