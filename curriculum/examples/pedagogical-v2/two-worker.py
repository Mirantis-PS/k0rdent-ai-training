"""Candidate NCCL/DDP teaching fixture. Requires real CUDA GPUs; no CPU fallback.

Run via torchrun, one process per GPU. See AI-LAB-04 for environment gates.
API reviewed against PyTorch2.5.1; selected runtime/hardware not yet qualified.
"""
import argparse
import datetime
import json
import os
import time


def parse_args():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--steps", type=int, default=20)
    parser.add_argument("--global-batch", type=int, default=64)
    args = parser.parse_args()
    world = int(os.environ.get("WORLD_SIZE", "0"))
    if world not in (1, 2):
        parser.error("Use torchrun with WORLD_SIZE 1 (baseline) or 2 (proof)")
    if not 2 <= args.steps <= 100:
        parser.error("steps must be between 2 and 100")
    if args.global_batch < world or args.global_batch > 1024 or args.global_batch % world:
        parser.error("global-batch must be divisible by world size and between world size and 1024")
    return args, world


def main():
    args, world = parse_args()
    import torch
    import torch.distributed as dist
    from torch.nn.parallel import DistributedDataParallel as DDP

    if not torch.cuda.is_available():
        raise RuntimeError("A real CUDA GPU is required; CPU simulation is not accepted")
    local_rank = int(os.environ["LOCAL_RANK"])
    rank = int(os.environ["RANK"])
    torch.cuda.set_device(local_rank)
    device = torch.device("cuda", local_rank)
    dist.init_process_group("nccl", timeout=datetime.timedelta(seconds=90))
    try:
        value = torch.tensor([float(rank + 1)], device=device)
        dist.all_reduce(value)
        expected = world * (world + 1) / 2
        assert value.item() == expected, "AllReduce returned an incorrect sum"
        local = torch.tensor([float(rank + 1)], device=device)
        gathered = [torch.zeros_like(local) for _ in range(world)]
        dist.all_gather(gathered, local)
        assert [x.item() for x in gathered] == list(range(1, world + 1))
        broadcast = torch.tensor([7.0 if rank == 0 else 0.0], device=device)
        dist.broadcast(broadcast, src=0)
        assert broadcast.item() == 7.0
        reduced = torch.empty(1, device=device)
        dist.reduce_scatter_tensor(reduced, torch.ones(world, device=device) * (rank + 1))
        assert reduced.item() == expected

        # Same model and fixed global examples for both one- and two-worker runs.
        torch.manual_seed(7)
        model = torch.nn.Linear(16, 1).to(device)
        model = DDP(model, device_ids=[local_rank])
        optimizer = torch.optim.SGD(model.parameters(), lr=0.05)
        generator = torch.Generator().manual_seed(11)
        all_x = torch.randn(args.global_batch, 16, generator=generator)
        all_y = all_x.sum(dim=1, keepdim=True) * 0.1
        per_rank = args.global_batch // world
        start = rank * per_rank
        x = all_x[start:start + per_rank].to(device)
        y = all_y[start:start + per_rank].to(device)
        dist.barrier()
        torch.cuda.synchronize()
        began = time.perf_counter()
        losses = []
        for _ in range(args.steps):
            optimizer.zero_grad(set_to_none=True)
            loss = torch.nn.functional.mse_loss(model(x), y)
            loss.backward()
            optimizer.step()
            averaged = loss.detach().clone()
            dist.all_reduce(averaged)
            losses.append(averaged.item() / world)
        torch.cuda.synchronize()
        elapsed = torch.tensor([time.perf_counter() - began], device=device)
        dist.all_reduce(elapsed, op=dist.ReduceOp.MAX)
        parameters = torch.cat([p.detach().flatten() for p in model.parameters()])
        peers = [torch.empty_like(parameters) for _ in range(world)]
        dist.all_gather(peers, parameters)
        assert all(torch.allclose(parameters, p, rtol=1e-5, atol=1e-6) for p in peers)
        assert all(torch.isfinite(torch.tensor(losses))), "Non-finite loss"
        assert losses[-1] < losses[0], "Training did not reduce this synthetic loss"
        print(json.dumps({
            "rank": rank, "world_size": world, "backend": dist.get_backend(),
            "host": os.uname().nodename, "gpu": torch.cuda.get_device_name(local_rank),
            "torch": torch.__version__, "cuda": torch.version.cuda,
            "nccl": torch.cuda.nccl.version(), "collectives": "passed",
            "steps": args.steps, "global_batch": args.global_batch,
            "initial_loss": losses[0], "final_loss": losses[-1],
            "max_rank_elapsed_s": elapsed.item(),
            "examples_per_s": args.steps * args.global_batch / elapsed.item(),
            "synchronized_parameters": True,
            "measurement_scope": "synthetic training loop including per-step loss collective; excludes startup",
        }), flush=True)
    finally:
        dist.destroy_process_group()


if __name__ == "__main__":
    main()
