# AI-LAB-04 — Two-worker proof

> **Course step 16 of 21.** [Previous step](../../gpu-allocation/labs/two-team-queue.md) · [Course checklist](../../../README.md) · [Next step](../../inference-and-data/labs/storage-cache.md). Follow this sequence when older lab-number references differ.


**Status:** educational draft; no GPU execution claimed. **Profile:** two real single-GPU workers; cross-node proof uses two nodes. **Guidance:** medium; fixed fixture, learner explains transport.

## Prerequisites and input state

AI-LAB-03 restored state saved. Instructor provides two isolated GPU worker containers/nodes, one visible GPU each, identical qualified PyTorch/CUDA/NCCL image, private routable rendezvous address and port, and approved scheduling/network policy. No GPU access means runtime BLOCKED, not simulated completion.

## Objectives and problem

Prove matching collectives and synchronized training on two real workers before considering large frameworks. Explain correctness, overhead and actual transport without assuming RDMA.

## Concept capsule

Read [Communication before scale](../lessons/communication-and-parallelism.md). Calculate the four collectives’ expected two-rank values before running. Map DP/TP/PP/EP, FSDP/ZeRO and framework roles to team B’s needs.

## Hypothesis

Predict identical updated parameters across ranks and decreasing synthetic loss. Predict whether two workers will be faster for this tiny fixed global batch; a slowdown is acceptable. State what evidence would prove cross-node transport and what would specifically prove RDMA.

## Procedure and checkpoints

1. Pause serving allocations through their owner and confirm capacity. Use the existing approved GPU worker/job route from source 5.16; install no MPI/DeepSpeed/Megatron just for this fixture. Both containers must have the same checked-in [two-worker.py](../../../examples/pedagogical-v2/two-worker.py). Record image digest, node/GPU identity and topology. Set an outer job deadline of five minutes; the process-group timeout alone does not bound rendezvous.
2. Run a single-worker baseline on one GPU with the same image and global batch, then the two-worker run. The following commands run **inside the provisioned worker containers**, not on your laptop. The instructor resolves the private MASTER_ADDR and port before execution. Open network access only between the approved workers; do not expose rendezvous publicly.

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

3. Collect both ranks’ logs and JSON summaries. Check world_size 2, backend NCCL, different hosts for cross-node proof, one allocated GPU per worker, passing collective values, finite decreasing loss and synchronized parameters. Fixture output is generated evidence only when actually run; no sample pass log is supplied.
4. Inspect NCCL transport/interface evidence. Report TCP/socket or the actual qualified provider honestly. Success does not prove EFA/RDMA/NVLink. Repeat baseline and two-worker runs three times with identical inputs; compare maximum-rank elapsed time. This includes tiny-model overhead and a per-step loss collective, excludes startup, and is not a scalable training benchmark.
5. Analyze a drawn two-leaf/spine fabric: two workers share an oversubscribed uplink while a second pair stays local. Predict effects of placement, ECMP, rails, congestion and RoCE ECN/PFC. Mark this paper analysis separately from executed topology. Propose when DP, sharding or locality changes would help, using the actual transport evidence.

## Interpretation

Why must collectives match in order and shape? What did DDP synchronize, and what remained local? Why does fixed global batch matter? Which FSDP/ZeRO memory terms differ from DDP? Would adding Ray/Kubeflow remove a network bottleneck?

## Bounded incident or tradeoff

On a disposable repeat, launch only rank 0 with the five-minute outer deadline. Observe missing-peer/rendezvous behavior; do not expect the 90-second process-group timeout before initialization. Stop the incomplete job, then launch both ranks correctly. This is a missing-worker incident, not a bandwidth measurement.

## Declarative delivery

Save worker allocation/launch configuration, immutable image identity, fixture SHA and source ownership. A product-native distributed job schema remains P3-gated. Preserve the original source training examples and larger-framework routes.

## Restoration and cleanup

Stop both launchers, remove named learner worker jobs/containers through their owner, verify both GPUs released, then restore the private serving revision and first-response check. Record any retained nodes and expiry.

## Evidence and acceptance

Both rank logs, actual node/device allocation, collective values, parameter agreement, baseline/two-worker timing, transport identification and restored service. Local two-GPU evidence is labeled local only; CPU analysis cannot pass the required two-worker GPU checkpoint.

## Provenance and instructor route

Derived from [Lab 5.16](distributed-training.md), [Lab 5.15](rdma-multi-cloud.md) and [training theory](../theory/distributed-training.md). The miniature fixture deliberately reduces dependencies while retaining real NCCL and training. See [primary API sources](../../../references/pedagogy/sources.md).

[Evidence contract](../../../references/pedagogy/evidence-contract.md) · [Learner path](../../../README.md) · [Instructor solutions](../../../instructor/pedagogical-v2/solutions.md#ai-lab-04)
