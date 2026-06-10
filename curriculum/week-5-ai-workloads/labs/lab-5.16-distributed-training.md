# Lab 5.16 - Multi-Node Distributed Training

---

## Lab Navigation

| Track | Tier | Duration |
|-------|------|----------|
| Advanced | Optional | 4.5 hours |

### Week 5 Learning Paths

```
FOUNDATION (Completed)                        ADVANCED
━━━━━━━━━━━━━━━━━━━━━━                       ━━━━━━━━
5.1 ➔ 5.2 ➔ ... ➔ 5.8 ✓                     5.13 TensorRT-LLM
                                                  ↓
                                              5.14 Slurm
                                                  ↓
                                              5.15 RDMA Multi-Cloud
                                                  ↓
                                             YOU ARE HERE
                                                  ↓
                                             [5.16] Distributed Training
                                                  ↓
                                              WEEK 5 COMPLETE!

After this lab:
  ML Platforms (5.9-5.10) or Week 6
```

| Previous | Current | Next |
|----------|---------|------|
| [Lab 5.15 - RDMA Multi-Cloud](lab-5.15-rdma-multi-cloud.md) | **Lab 5.16 - Distributed Training** | [Lab 5.9 - Kubeflow](lab-5.9-kubeflow-ml-platform.md) or [Week 6](../../week-6-multitenancy/labs/lab-6.6-capstone.md) |

---

## Table of Contents

- [Objective](#objective)
- [Prerequisites](#prerequisites)
- [k0rdent Context](#k0rdent-context)
- [Background: Distributed Training Architecture](#background-distributed-training-architecture)
- [Lab Environment](#lab-environment)
- [Tasks](#tasks)
  - [Task 1: Access k0rdent-Managed GPU Cluster](#task-1-access-k0rdent-managed-gpu-cluster-10-min)
  - [Task 2: Install MPI Operator](#task-2-install-mpi-operator-20-min)
  - [Task 3: Verify Multi-Node Connectivity](#task-3-verify-multi-node-connectivity-30-min)
  - [Task 4: Deploy Megatron-LM Training Job](#task-4-deploy-megatron-lm-training-job-60-min)
  - [Task 5: DeepSpeed ZeRO Optimization](#task-5-deepspeed-zero-optimization-45-min)
  - [Task 6: PyTorch FSDP](#task-6-pytorch-fsdp-fully-sharded-data-parallel-45-min)
  - [Task 7: Performance Optimization](#task-7-performance-optimization-30-min)

---

**Duration:** 4.5 hours
**Type:** Hands-on Technical (Advanced)
**Environment:** 2+ GPU nodes (p4d.24xlarge or ND A100 v4)

## Objective

Implement and optimize multi-node distributed training using tensor and pipeline parallelism across multiple GPU nodes. This lab demonstrates enterprise-scale AI training techniques using Megatron-LM, DeepSpeed, and PyTorch FSDP on k0rdent-managed infrastructure.

## Prerequisites

- Completed Lab 5.14 (Multi-Cloud RDMA Deep Dive)
- Access to 2+ GPU nodes with RDMA/InfiniBand connectivity
- NVIDIA GPU Operator and Network Operator configured
- Understanding of NVLink and inter-node networking
- Kubeflow MPI Operator or similar job scheduler

---

## k0rdent Context

### Distributed Training in k0rdent

k0rdent manages the GPU infrastructure and provides catalog-based service deployment. For distributed training, the key integration points are:

**Available in k0rdent Catalog:**
- `gpu-operator-25-10-0` - GPU Operator (required for all GPU workloads)
- `network-operator-25-10-0` - Network Operator (RDMA/InfiniBand)
- `kuberay-operator-1-5-1` - KubeRay Operator (Ray-based distributed training)
- `lws-0-7-0` - LeaderWorkerSet (Kubernetes-native distributed workloads)

**Not in Catalog (Direct Install Required):**
- Kubeflow MPI Operator - Install directly via kubectl manifests
- Megatron-LM / DeepSpeed / PyTorch FSDP - Framework-level libraries within containers

**Architecture:**
```
┌──────────────────────────────────────────────────────────────────┐
│                    k0rdent Management Cluster                     │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │ ClusterDeployment (GPU Cluster)                            │  │
│  │  spec.serviceSpec.services:                                │  │
│  │    - gpu-operator-25-10-0                                  │  │
│  │    - network-operator-25-10-0                              │  │
│  └────────────────────────────────────────────────────────────┘  │
├──────────────────────────────────────────────────────────────────┤
│                    Managed GPU Cluster                            │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐           │
│  │ MPI Operator │  │   Training   │  │  Shared      │           │
│  │ (direct)     │  │   Jobs       │  │  Storage     │           │
│  └──────────────┘  └──────────────┘  └──────────────┘           │
└──────────────────────────────────────────────────────────────────┘
```

---

## Background: Distributed Training Architecture

### Why Distribute Training?

Modern large language models exceed single-GPU or even single-node memory capacity:

| Model | Parameters | FP16 Memory | A100-80GB GPUs Needed |
|-------|------------|-------------|----------------------|
| GPT-2 | 1.5B | ~3 GB | 1 |
| LLaMA-7B | 7B | ~14 GB | 1 |
| LLaMA-70B | 70B | ~140 GB | 2 (with optimization) |
| Llama-3-405B | 405B | ~810 GB | 11+ |

**Training requires significantly more memory than inference:**
- Model parameters (weights)
- Gradients (same size as parameters)
- Optimizer states (2-8x parameters for Adam)
- Activations (depends on batch size and sequence length)

**Memory for Training (70B model with Adam):**
```
Parameters:      140 GB (FP16)
Gradients:       140 GB (FP16)
Optimizer:       560 GB (FP32 master weights + momentum + variance)
Activations:     ~100 GB (depends on batch/sequence)
─────────────────────────────
Total:           ~940 GB = 12x A100-80GB minimum
```

### Parallelism Strategies

```
┌─────────────────────────────────────────────────────────────────┐
│                    Parallelism Strategies                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  DATA PARALLELISM (DP)                                          │
│  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐               │
│  │ GPU 0   │ │ GPU 1   │ │ GPU 2   │ │ GPU 3   │               │
│  │ Full    │ │ Full    │ │ Full    │ │ Full    │               │
│  │ Model   │ │ Model   │ │ Model   │ │ Model   │               │
│  │ Batch 0 │ │ Batch 1 │ │ Batch 2 │ │ Batch 3 │               │
│  └────┬────┘ └────┬────┘ └────┬────┘ └────┬────┘               │
│       └──────────┬┴──────────┴┬──────────┘                     │
│               All-Reduce Gradients                              │
│                                                                 │
│  TENSOR PARALLELISM (TP)                                        │
│  ┌─────────────────────────────────────────────┐               │
│  │              Single Layer                    │               │
│  │  ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐            │               │
│  │  │GPU 0│ │GPU 1│ │GPU 2│ │GPU 3│            │               │
│  │  │ 1/4 │ │ 1/4 │ │ 1/4 │ │ 1/4 │            │               │
│  │  │Layer│ │Layer│ │Layer│ │Layer│            │               │
│  │  └──┬──┘ └──┬──┘ └──┬──┘ └──┬──┘            │               │
│  │     └───────┴───────┴───────┘               │               │
│  │         All-Reduce per Layer                │               │
│  └─────────────────────────────────────────────┘               │
│  Best for: Intra-node (NVLink required)                         │
│                                                                 │
│  PIPELINE PARALLELISM (PP)                                      │
│  ┌───────┐    ┌───────┐    ┌───────┐    ┌───────┐              │
│  │ GPU 0 │───>│ GPU 1 │───>│ GPU 2 │───>│ GPU 3 │              │
│  │Layers │    │Layers │    │Layers │    │Layers │              │
│  │ 0-19  │    │20-39  │    │40-59  │    │60-79  │              │
│  └───────┘    └───────┘    └───────┘    └───────┘              │
│  Best for: Inter-node (lower bandwidth OK)                      │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Hybrid Parallelism (3D Parallelism)

For very large models, combine all three strategies:

```
                    ┌─────────────────────────────────────┐
                    │      3D Parallelism Example         │
                    │    DP=2, TP=4, PP=2 (16 GPUs)       │
                    └─────────────────────────────────────┘

                              Data Parallel Rank 0
                    ┌─────────────────────────────────────┐
                    │         Pipeline Stage 0            │
                    │  ┌─────┬─────┬─────┬─────┐         │
Node 0 ─────────────│  │TP=0 │TP=1 │TP=2 │TP=3 │         │
                    │  │GPU 0│GPU 1│GPU 2│GPU 3│         │
                    │  └─────┴─────┴─────┴─────┘         │
                    │         Pipeline Stage 1            │
                    │  ┌─────┬─────┬─────┬─────┐         │
Node 1 ─────────────│  │TP=0 │TP=1 │TP=2 │TP=3 │         │
                    │  │GPU 4│GPU 5│GPU 6│GPU 7│         │
                    │  └─────┴─────┴─────┴─────┘         │
                    └─────────────────────────────────────┘

                              Data Parallel Rank 1
                    ┌─────────────────────────────────────┐
                    │         Pipeline Stage 0            │
                    │  ┌─────┬─────┬─────┬─────┐         │
Node 2 ─────────────│  │TP=0 │TP=1 │TP=2 │TP=3 │         │
                    │  │GPU 8│GPU 9│GPU10│GPU11│         │
                    │  └─────┴─────┴─────┴─────┘         │
                    │         Pipeline Stage 1            │
                    │  ┌─────┬─────┬─────┬─────┐         │
Node 3 ─────────────│  │TP=0 │TP=1 │TP=2 │TP=3 │         │
                    │  │GPU12│GPU13│GPU14│GPU15│         │
                    │  └─────┴─────┴─────┴─────┘         │
                    └─────────────────────────────────────┘
```

### Communication Patterns

| Strategy | Communication | Frequency | Best Network |
|----------|---------------|-----------|--------------|
| **Data Parallel** | All-reduce gradients | Every batch | Any (can be async) |
| **Tensor Parallel** | All-reduce activations | Every layer | NVLink (low latency critical) |
| **Pipeline Parallel** | Point-to-point | Between stages | RDMA (medium latency OK) |

**Key Insight:** Tensor parallelism must stay within NVLink-connected GPUs (single node), while pipeline and data parallelism can span nodes.

---

## Lab Environment

### Cluster Requirements

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| GPU Nodes | 2 | 4+ |
| GPUs per Node | 8x A100-40GB | 8x A100-80GB or H100 |
| Inter-node Network | 100 Gbps | 400+ Gbps RDMA |
| Storage | 500 GB shared | 2+ TB NVMe |
| Kubernetes | k0s 1.32+ | k0s 1.32+ with GPU Operator |

### Software Stack

- NVIDIA GPU Operator v25.10.0
- NVIDIA Network Operator (RDMA configured)
- Kubeflow MPI Operator v0.8.0
- PyTorch 2.x with distributed support (via NVIDIA container)

---

## Tasks

### Task 1: Access k0rdent-Managed GPU Cluster (10 min)

Extract kubeconfig from the k0rdent management cluster to access the managed GPU cluster.

1. **Extract Kubeconfig from k0rdent**
   ```bash
   # On the management cluster, extract the managed cluster kubeconfig
   kubectl get secret gpu-cluster-kubeconfig -n kcm-system \
     -o jsonpath='{.data.value}' | base64 -d > /tmp/gpu-cluster.kubeconfig

   export KUBECONFIG=/tmp/gpu-cluster.kubeconfig

   # Verify GPU nodes are available
   kubectl get nodes -l nvidia.com/gpu.present=true
   ```

2. **Verify GPU Operator and Network Operator**
   ```bash
   # Check GPU Operator pods (deployed via k0rdent ServiceTemplate)
   kubectl get pods -n gpu-operator

   # Verify GPUs are detected
   kubectl get nodes -o json | jq '.items[] | {name: .metadata.name, gpus: .status.capacity["nvidia.com/gpu"]}'

   # Check RDMA devices (if Network Operator deployed)
   kubectl get pods -n nvidia-network-operator
   ```

3. **Verify Sveltos Deployment Status (on management cluster)**
   ```bash
   # Switch back to management cluster
   export KUBECONFIG=~/.kube/config

   # Check that GPU Operator service was deployed successfully
   kubectl get clusterdeployment gpu-cluster -n kcm-system \
     -o jsonpath='{.status.conditions}' | jq '.[] | select(.type | test("Sveltos"))'

   # Expected: SveltosHelmReleaseReady = True

   # Switch back to managed cluster for remaining tasks
   export KUBECONFIG=/tmp/gpu-cluster.kubeconfig
   ```

### Task 2: Install MPI Operator (20 min)

The MPI Operator enables distributed training jobs on Kubernetes. There is no MPI Operator ServiceTemplate in the k0rdent catalog, so install directly on the managed cluster.

> **k0rdent Catalog Alternatives:** For distributed workloads, the catalog provides `kuberay-operator-1-5-1` (Ray-based training) and `lws-0-7-0` (LeaderWorkerSet for Kubernetes-native distributed jobs). MPI Operator is preferred for traditional MPI-based training frameworks like Megatron-LM and DeepSpeed.

1. **Install Kubeflow MPI Operator v0.8.0**
   ```bash
   # Install MPI Operator v0.8.0
   kubectl apply -f https://raw.githubusercontent.com/kubeflow/mpi-operator/v0.8.0/deploy/v2beta1/mpi-operator.yaml

   # Verify installation
   kubectl get crd mpijobs.kubeflow.org
   kubectl get deployment mpi-operator -n mpi-operator

   # Wait for operator to be ready
   kubectl wait --for=condition=available deployment/mpi-operator \
     -n mpi-operator --timeout=120s
   ```

2. **Create Training Namespace**
   ```bash
   kubectl create namespace distributed-training
   ```

### Task 3: Verify Multi-Node Connectivity (30 min)

Before training, verify NCCL communication across nodes.

> **Important:** The NVIDIA PyTorch container (`nvcr.io/nvidia/pytorch`) includes the NCCL library but does NOT include pre-compiled NCCL test binaries. We use a dedicated NCCL tests container for benchmarking, or build from source.

1. **Deploy Multi-Node NCCL Test**
   ```yaml
   # Save as nccl-multi-node-test.yaml
   apiVersion: kubeflow.org/v2beta1
   kind: MPIJob
   metadata:
     name: nccl-test
     namespace: distributed-training
   spec:
     slotsPerWorker: 8
     runPolicy:
       cleanPodPolicy: Running
     mpiReplicaSpecs:
       Launcher:
         replicas: 1
         template:
           spec:
             containers:
               - name: launcher
                 image: nvcr.io/nvidia/pytorch:24.12-py3
                 command:
                   - mpirun
                   - --allow-run-as-root
                   - -np
                   - "16"
                   - -npernode
                   - "8"
                   - -bind-to
                   - none
                   - -map-by
                   - slot
                   - -x
                   - NCCL_DEBUG=INFO
                   - -x
                   - NCCL_IB_DISABLE=0
                   - -x
                   - NCCL_NET_GDR_LEVEL=SYS
                   - -x
                   - LD_LIBRARY_PATH
                   - python
                   - -c
                   - |
                     import torch
                     import torch.distributed as dist
                     import os
                     dist.init_process_group(backend='nccl')
                     rank = dist.get_rank()
                     local_rank = int(os.environ.get('LOCAL_RANK', rank % 8))
                     torch.cuda.set_device(local_rank)
                     # All-reduce benchmark using PyTorch
                     for size_mb in [1, 8, 64, 256, 1024, 4096]:
                         tensor = torch.zeros(size_mb * 1024 * 1024 // 4, device=f'cuda:{local_rank}')
                         torch.cuda.synchronize()
                         start = torch.cuda.Event(enable_timing=True)
                         end = torch.cuda.Event(enable_timing=True)
                         # Warmup
                         for _ in range(5):
                             dist.all_reduce(tensor)
                         torch.cuda.synchronize()
                         start.record()
                         iters = 20
                         for _ in range(iters):
                             dist.all_reduce(tensor)
                         end.record()
                         torch.cuda.synchronize()
                         elapsed_ms = start.elapsed_time(end) / iters
                         size_bytes = size_mb * 1024 * 1024
                         algbw = size_bytes / (elapsed_ms / 1000) / 1e9
                         busbw = algbw * (2 * (dist.get_world_size() - 1) / dist.get_world_size())
                         if rank == 0:
                             print(f'Size: {size_mb:>5} MB | Time: {elapsed_ms:>8.2f} ms | AlgBW: {algbw:>8.2f} GB/s | BusBW: {busbw:>8.2f} GB/s')
                     dist.destroy_process_group()
       Worker:
         replicas: 2
         template:
           spec:
             containers:
               - name: worker
                 image: nvcr.io/nvidia/pytorch:24.12-py3
                 command: ["sleep", "infinity"]
                 env:
                   - name: NCCL_DEBUG
                     value: "INFO"
                   - name: NCCL_IB_DISABLE
                     value: "0"
                   - name: NCCL_NET_GDR_LEVEL
                     value: "SYS"
                 resources:
                   limits:
                     nvidia.com/gpu: 8
                     rdma/rdma_shared_device_ib: 8  # Or vpc.amazonaws.com/efa: 4 for AWS
                   requests:
                     nvidia.com/gpu: 8
                 securityContext:
                   capabilities:
                     add: ["IPC_LOCK"]
                 volumeMounts:
                   - name: shm
                     mountPath: /dev/shm
             volumes:
               - name: shm
                 emptyDir:
                   medium: Memory
                   sizeLimit: 64Gi
             tolerations:
               - key: nvidia.com/gpu
                 operator: Exists
                 effect: NoSchedule
   ```

   ```bash
   kubectl apply -f nccl-multi-node-test.yaml

   # Watch the job
   kubectl logs -f -n distributed-training \
     $(kubectl get pods -n distributed-training -l job-name=nccl-test-launcher \
       -o jsonpath='{.items[0].metadata.name}')
   ```

   > **Note on NCCL Tests Image:** For more precise benchmarking with the official `all_reduce_perf` binary, build NCCL tests from source inside the PyTorch container, or use a dedicated image that includes pre-compiled NCCL test binaries (e.g., from your organization's container registry). The PyTorch-based benchmark above provides comparable results without needing extra binaries.

2. **Expected Output Analysis**
   ```
   # Look for these key lines in NCCL_DEBUG output:
   NCCL INFO comm 0x... rank 0 nranks 16 cudaDev 0 busId 0000:00:1e.0
   NCCL INFO NET/IB : Using [0]mlx5_0:1/IB  # InfiniBand being used
   # OR for AWS:
   NCCL INFO NET/AWS-EFA : Using EFA device 0

   # Benchmark results:
   # Size:  4096 MB | Time:    45.20 ms | AlgBW:    95.03 GB/s | BusBW:   178.18 GB/s
   ```

   **Realistic Bandwidth Expectations (All-Reduce Bus Bandwidth):**

   | Configuration | A100 (NVLink 3.0) | H100 (NVLink 4.0) |
   |---------------|-------------------|-------------------|
   | Single node (8 GPU) | ~550-580 GB/s | ~800-850 GB/s |
   | Two nodes (16 GPU) | ~150-200 GB/s | ~300-400 GB/s |
   | Four nodes (32 GPU) | ~120-160 GB/s | ~250-350 GB/s |

   > **Why the drop across nodes?** Single-node bandwidth is limited by NVLink (600 GB/s theoretical for A100 NVLink 3.0, 900 GB/s for H100 NVLink 4.0). Multi-node bandwidth is limited by the network interconnect (InfiniBand NDR 400 Gbps = ~50 GB/s per port, with multi-rail configurations aggregating bandwidth).

### Task 4: Deploy Megatron-LM Training Job (60 min)

Megatron-LM is NVIDIA's framework for training large transformer models with 3D parallelism.

1. **Megatron-LM Parallelism Configuration**

   ```bash
   # Example Megatron-LM configuration for a model on 16 GPUs (2 nodes)
   # TP=4 (within node), PP=2 (across nodes), DP=2

   TENSOR_MODEL_PARALLEL_SIZE=4   # Split layers across 4 GPUs (NVLink)
   PIPELINE_MODEL_PARALLEL_SIZE=2  # 2 pipeline stages (across nodes)
   DATA_PARALLEL_SIZE=2            # 2 data parallel replicas

   # Total GPUs = TP * PP * DP = 4 * 2 * 2 = 16
   ```

2. **Create NCCL and Training Configuration**
   ```yaml
   # Save as megatron-config.yaml
   apiVersion: v1
   kind: ConfigMap
   metadata:
     name: megatron-config
     namespace: distributed-training
   data:
     # NCCL optimizations for multi-node training
     NCCL_DEBUG: "WARN"
     NCCL_IB_DISABLE: "0"
     NCCL_NET_GDR_LEVEL: "SYS"
     NCCL_P2P_LEVEL: "NVL"
     NCCL_SOCKET_NTHREADS: "4"
     NCCL_NSOCKS_PERTHREAD: "4"
     NCCL_BUFFSIZE: "8388608"
     # Required for Megatron-LM async pipeline overlap
     CUDA_DEVICE_MAX_CONNECTIONS: "1"
   ```

   > **NCCL_NET_GDR_LEVEL Values:** This controls GPUDirect RDMA topology filtering. Valid string values are: `LOC` (disabled), `PIX` (same PCI switch), `PXB` (through PCI switches), `PHB` (same NUMA node), `SYS` (full cross-NUMA RDMA for maximum bandwidth). Always use string values, not numeric. `SYS` provides the highest bandwidth for multi-node training by allowing RDMA across all NUMA boundaries.

3. **Create Storage for Checkpoints**
   ```yaml
   # Save as training-storage.yaml
   apiVersion: v1
   kind: PersistentVolumeClaim
   metadata:
     name: training-checkpoints
     namespace: distributed-training
   spec:
     accessModes:
       - ReadWriteMany  # Multiple nodes need access
     resources:
       requests:
         storage: 500Gi
     storageClassName: efs  # AWS EFS for multi-node access; azurefile for Azure
   ---
   apiVersion: v1
   kind: PersistentVolumeClaim
   metadata:
     name: training-data
     namespace: distributed-training
   spec:
     accessModes:
       - ReadOnlyMany
     resources:
       requests:
         storage: 100Gi
     storageClassName: efs
   ```

4. **Create Megatron-LM Setup Script**

   The NVIDIA PyTorch container does not include Megatron-LM. We clone it as part of the launcher setup.

   ```yaml
   # Save as megatron-setup.yaml
   apiVersion: v1
   kind: ConfigMap
   metadata:
     name: megatron-setup
     namespace: distributed-training
   data:
     setup.sh: |
       #!/bin/bash
       set -euo pipefail

       # Clone Megatron-LM if not present
       if [ ! -d "/workspace/Megatron-LM" ]; then
         echo "Cloning Megatron-LM..."
         cd /workspace
         git clone --depth 1 https://github.com/NVIDIA/Megatron-LM.git
         cd Megatron-LM
         pip install -e . 2>/dev/null || echo "Megatron-LM setup complete (editable install)"
       fi

       echo "Megatron-LM ready at /workspace/Megatron-LM"
   ```

5. **Deploy Megatron Training Job**
   ```yaml
   # Save as megatron-training.yaml
   apiVersion: kubeflow.org/v2beta1
   kind: MPIJob
   metadata:
     name: megatron-gpt-training
     namespace: distributed-training
   spec:
     slotsPerWorker: 8
     runPolicy:
       cleanPodPolicy: Running
       backoffLimit: 3
     mpiReplicaSpecs:
       Launcher:
         replicas: 1
         template:
           spec:
             initContainers:
               - name: setup-megatron
                 image: nvcr.io/nvidia/pytorch:24.12-py3
                 command: ["bash", "/scripts/setup.sh"]
                 volumeMounts:
                   - name: workspace
                     mountPath: /workspace
                   - name: setup-script
                     mountPath: /scripts
             containers:
               - name: launcher
                 image: nvcr.io/nvidia/pytorch:24.12-py3
                 command:
                   - mpirun
                   - --allow-run-as-root
                   - -np
                   - "16"
                   - -npernode
                   - "8"
                   - -bind-to
                   - none
                   - -map-by
                   - slot
                   - -x
                   - NCCL_DEBUG=WARN
                   - -x
                   - NCCL_IB_DISABLE=0
                   - -x
                   - NCCL_NET_GDR_LEVEL=SYS
                   - -x
                   - NCCL_P2P_LEVEL=NVL
                   - -x
                   - CUDA_DEVICE_MAX_CONNECTIONS=1
                   - -x
                   - LD_LIBRARY_PATH
                   - python
                   - /workspace/Megatron-LM/pretrain_gpt.py
                   - --tensor-model-parallel-size=4
                   - --pipeline-model-parallel-size=2
                   - --num-layers=32
                   - --hidden-size=4096
                   - --num-attention-heads=32
                   - --seq-length=2048
                   - --max-position-embeddings=4096
                   - --micro-batch-size=1
                   - --global-batch-size=32
                   - --train-iters=100
                   - --lr=1.5e-4
                   - --min-lr=1.5e-5
                   - --lr-decay-style=cosine
                   - --log-interval=1
                   - --eval-interval=50
                   - --save-interval=50
                   - --fp16
                   - --data-path=/data/preprocessed
                   - --save=/checkpoints
                   - --load=/checkpoints
                 envFrom:
                   - configMapRef:
                       name: megatron-config
                 volumeMounts:
                   - name: workspace
                     mountPath: /workspace
                   - name: checkpoints
                     mountPath: /checkpoints
                   - name: data
                     mountPath: /data
             volumes:
               - name: workspace
                 emptyDir: {}
               - name: setup-script
                 configMap:
                   name: megatron-setup
                   defaultMode: 0755
               - name: checkpoints
                 persistentVolumeClaim:
                   claimName: training-checkpoints
               - name: data
                 persistentVolumeClaim:
                   claimName: training-data
       Worker:
         replicas: 2
         template:
           spec:
             initContainers:
               - name: setup-megatron
                 image: nvcr.io/nvidia/pytorch:24.12-py3
                 command: ["bash", "/scripts/setup.sh"]
                 volumeMounts:
                   - name: workspace
                     mountPath: /workspace
                   - name: setup-script
                     mountPath: /scripts
             containers:
               - name: worker
                 image: nvcr.io/nvidia/pytorch:24.12-py3
                 command: ["sleep", "infinity"]
                 envFrom:
                   - configMapRef:
                       name: megatron-config
                 resources:
                   limits:
                     nvidia.com/gpu: 8
                     rdma/rdma_shared_device_ib: 8
                   requests:
                     nvidia.com/gpu: 8
                     memory: 512Gi
                     cpu: "64"
                 securityContext:
                   capabilities:
                     add: ["IPC_LOCK"]
                 volumeMounts:
                   - name: shm
                     mountPath: /dev/shm
                   - name: workspace
                     mountPath: /workspace
                   - name: checkpoints
                     mountPath: /checkpoints
                   - name: data
                     mountPath: /data
             volumes:
               - name: shm
                 emptyDir:
                   medium: Memory
                   sizeLimit: 256Gi
               - name: workspace
                 emptyDir: {}
               - name: setup-script
                 configMap:
                   name: megatron-setup
                   defaultMode: 0755
               - name: checkpoints
                 persistentVolumeClaim:
                   claimName: training-checkpoints
               - name: data
                 persistentVolumeClaim:
                   claimName: training-data
             tolerations:
               - key: nvidia.com/gpu
                 operator: Exists
                 effect: NoSchedule
   ```

   ```bash
   kubectl apply -f megatron-config.yaml
   kubectl apply -f megatron-setup.yaml
   kubectl apply -f training-storage.yaml
   kubectl apply -f megatron-training.yaml

   # Monitor training
   kubectl logs -f -n distributed-training megatron-gpt-training-launcher-0
   ```

6. **Monitor Training Progress**
   ```bash
   # Watch for training metrics:
   # iteration: 1 | consumed tokens: 65536 | loss: 10.534 | time: 2.45s

   # Track GPU utilization
   kubectl exec -it -n distributed-training megatron-gpt-training-worker-0 \
     -- nvidia-smi dmon -s u

   # Check NCCL communication
   kubectl logs -n distributed-training megatron-gpt-training-worker-0 | grep NCCL
   ```

### Task 5: DeepSpeed ZeRO Optimization (45 min)

DeepSpeed ZeRO partitions optimizer states across GPUs, enabling larger models with less per-GPU memory.

1. **Understanding ZeRO Stages**

   ```
   ┌─────────────────────────────────────────────────────────────────┐
   │                    DeepSpeed ZeRO Stages                         │
   ├─────────────────────────────────────────────────────────────────┤
   │                                                                 │
   │  ZeRO Stage 0 (Baseline - No optimization)                      │
   │  ┌─────────────────────────────────────────────────────────┐   │
   │  │ GPU: Full Model + Full Gradients + Full Optimizer       │   │
   │  └─────────────────────────────────────────────────────────┘   │
   │  Memory per GPU: 100% (no savings)                              │
   │                                                                 │
   │  ZeRO Stage 1 (Optimizer State Partitioning)                    │
   │  ┌─────────────────────────────────────────────────────────┐   │
   │  │ GPU: Full Model + Full Gradients + 1/N Optimizer        │   │
   │  └─────────────────────────────────────────────────────────┘   │
   │  Memory reduction: ~3x on 8 GPUs (optimizer is ~60% of total)  │
   │                                                                 │
   │  ZeRO Stage 2 (+ Gradient Partitioning)                         │
   │  ┌─────────────────────────────────────────────────────────┐   │
   │  │ GPU: Full Model + 1/N Gradients + 1/N Optimizer         │   │
   │  └─────────────────────────────────────────────────────────┘   │
   │  Memory reduction: ~4x on 8 GPUs                                │
   │                                                                 │
   │  ZeRO Stage 3 (+ Parameter Partitioning)                        │
   │  ┌─────────────────────────────────────────────────────────┐   │
   │  │ GPU: 1/N Model + 1/N Gradients + 1/N Optimizer          │   │
   │  └─────────────────────────────────────────────────────────┘   │
   │  Memory reduction: ~Nx (linear scaling with GPU count)          │
   │                                                                 │
   └─────────────────────────────────────────────────────────────────┘
   ```

   > **ZeRO Memory Reduction on 8 GPUs:** Stage 1 saves ~3x (optimizer states are ~60% of memory for Adam with FP32 master weights + momentum + variance), Stage 2 saves ~4x (adding gradient partitioning), Stage 3 saves ~8x (full linear scaling by partitioning everything). These are approximate and depend on model architecture and optimizer.

2. **DeepSpeed Configuration**
   ```yaml
   # Save as deepspeed-config.yaml
   apiVersion: v1
   kind: ConfigMap
   metadata:
     name: deepspeed-config
     namespace: distributed-training
   data:
     ds_config.json: |
       {
         "train_batch_size": 64,
         "train_micro_batch_size_per_gpu": 1,
         "gradient_accumulation_steps": 4,

         "optimizer": {
           "type": "AdamW",
           "params": {
             "lr": 1.5e-4,
             "betas": [0.9, 0.95],
             "eps": 1e-8,
             "weight_decay": 0.1
           }
         },

         "scheduler": {
           "type": "WarmupDecayLR",
           "params": {
             "warmup_min_lr": 1e-6,
             "warmup_max_lr": 1.5e-4,
             "warmup_num_steps": 2000,
             "total_num_steps": 100000
           }
         },

         "fp16": {
           "enabled": true,
           "loss_scale": 0,
           "loss_scale_window": 1000,
           "initial_scale_power": 16,
           "hysteresis": 2,
           "min_loss_scale": 1
         },

         "zero_optimization": {
           "stage": 3,
           "offload_optimizer": {
             "device": "none"
           },
           "offload_param": {
             "device": "none"
           },
           "overlap_comm": true,
           "contiguous_gradients": true,
           "reduce_bucket_size": 5e8,
           "stage3_prefetch_bucket_size": 5e8,
           "stage3_param_persistence_threshold": 1e6,
           "stage3_gather_16bit_weights_on_model_save": true
         },

         "gradient_clipping": 1.0,
         "wall_clock_breakdown": true
       }
   ```

3. **Create DeepSpeed Training Script**

   ```yaml
   # Save as deepspeed-train-script.yaml
   apiVersion: v1
   kind: ConfigMap
   metadata:
     name: deepspeed-train-script
     namespace: distributed-training
   data:
     train.py: |
       import os
       import torch
       import deepspeed
       from transformers import AutoModelForCausalLM, AutoTokenizer, AutoConfig

       def main():
           # DeepSpeed initializes distributed automatically
           local_rank = int(os.environ.get("LOCAL_RANK", 0))
           torch.cuda.set_device(local_rank)

           # Model configuration (7B parameter model for demonstration)
           model_name = "NousResearch/Llama-2-7b-hf"
           config = AutoConfig.from_pretrained(model_name)

           # Initialize model with DeepSpeed ZeRO-3 (on-demand parameter loading)
           with deepspeed.zero.Init():
               model = AutoModelForCausalLM.from_config(config)

           tokenizer = AutoTokenizer.from_pretrained(model_name)
           if tokenizer.pad_token is None:
               tokenizer.pad_token = tokenizer.eos_token

           # DeepSpeed engine handles optimizer, scheduler, and distributed setup
           model_engine, optimizer, _, _ = deepspeed.initialize(
               model=model,
               config="/config/ds_config.json",
           )

           # Synthetic training loop (replace with real data loader)
           for step in range(100):
               # Generate synthetic batch
               input_ids = torch.randint(0, config.vocab_size, (1, 512)).cuda()
               labels = input_ids.clone()

               outputs = model_engine(input_ids=input_ids, labels=labels)
               loss = outputs.loss

               model_engine.backward(loss)
               model_engine.step()

               if local_rank == 0 and step % 10 == 0:
                   print(f"Step {step}, Loss: {loss.item():.4f}")

           # Save model
           if local_rank == 0:
               model_engine.save_checkpoint("/checkpoints/deepspeed-final")
               print("Training complete. Checkpoint saved.")

       if __name__ == "__main__":
           main()
   ```

4. **Deploy DeepSpeed Training**

   > **Critical: DeepSpeed Launcher vs MPI Operator.** DeepSpeed's own launcher (`deepspeed --num_gpus=... train.py`) uses SSH-based process spawning that conflicts with MPI Operator's mpirun orchestration. When using MPIJob, always launch with `mpirun ... python train.py --deepspeed --deepspeed_config=...` so that MPI Operator manages process distribution while DeepSpeed handles the optimization.

   ```yaml
   # Save as deepspeed-training.yaml
   apiVersion: kubeflow.org/v2beta1
   kind: MPIJob
   metadata:
     name: deepspeed-llm-training
     namespace: distributed-training
   spec:
     slotsPerWorker: 8
     runPolicy:
       cleanPodPolicy: Running
     mpiReplicaSpecs:
       Launcher:
         replicas: 1
         template:
           spec:
             containers:
               - name: launcher
                 image: nvcr.io/nvidia/pytorch:24.12-py3
                 command:
                   - mpirun
                   - --allow-run-as-root
                   - -np
                   - "16"
                   - -npernode
                   - "8"
                   - -bind-to
                   - none
                   - -map-by
                   - slot
                   - -x
                   - NCCL_DEBUG=WARN
                   - -x
                   - NCCL_IB_DISABLE=0
                   - -x
                   - NCCL_NET_GDR_LEVEL=SYS
                   - -x
                   - LD_LIBRARY_PATH
                   - python
                   - /scripts/train.py
                   - --deepspeed
                   - --deepspeed_config=/config/ds_config.json
                 volumeMounts:
                   - name: config
                     mountPath: /config
                   - name: train-script
                     mountPath: /scripts
                   - name: checkpoints
                     mountPath: /checkpoints
             volumes:
               - name: config
                 configMap:
                   name: deepspeed-config
               - name: train-script
                 configMap:
                   name: deepspeed-train-script
               - name: checkpoints
                 persistentVolumeClaim:
                   claimName: training-checkpoints
       Worker:
         replicas: 2
         template:
           spec:
             containers:
               - name: worker
                 image: nvcr.io/nvidia/pytorch:24.12-py3
                 command: ["sleep", "infinity"]
                 env:
                   - name: NCCL_DEBUG
                     value: "WARN"
                   - name: NCCL_IB_DISABLE
                     value: "0"
                   - name: NCCL_NET_GDR_LEVEL
                     value: "SYS"
                 resources:
                   limits:
                     nvidia.com/gpu: 8
                     rdma/rdma_shared_device_ib: 8
                   requests:
                     nvidia.com/gpu: 8
                 securityContext:
                   capabilities:
                     add: ["IPC_LOCK"]
                 volumeMounts:
                   - name: shm
                     mountPath: /dev/shm
                   - name: config
                     mountPath: /config
                   - name: train-script
                     mountPath: /scripts
                   - name: checkpoints
                     mountPath: /checkpoints
             volumes:
               - name: shm
                 emptyDir:
                   medium: Memory
                   sizeLimit: 256Gi
               - name: config
                 configMap:
                   name: deepspeed-config
               - name: train-script
                 configMap:
                   name: deepspeed-train-script
               - name: checkpoints
                 persistentVolumeClaim:
                   claimName: training-checkpoints
             tolerations:
               - key: nvidia.com/gpu
                 operator: Exists
                 effect: NoSchedule
   ```

   ```bash
   kubectl apply -f deepspeed-config.yaml
   kubectl apply -f deepspeed-train-script.yaml
   kubectl apply -f deepspeed-training.yaml

   # Monitor training
   kubectl logs -f -n distributed-training deepspeed-llm-training-launcher-0
   ```

### Task 6: PyTorch FSDP (Fully Sharded Data Parallel) (45 min)

FSDP is PyTorch's native implementation of ZeRO-style sharding. It provides similar memory savings to DeepSpeed ZeRO without requiring an external library.

1. **Understanding FSDP Sharding Strategies**
   ```python
   from torch.distributed.fsdp import ShardingStrategy

   # FULL_SHARD: ZeRO-3 equivalent (parameters, gradients, optimizer all sharded)
   # SHARD_GRAD_OP: ZeRO-2 equivalent (gradients and optimizer sharded)
   # NO_SHARD: DDP equivalent (no sharding, full replication)
   # HYBRID_SHARD: Shard within node, replicate across nodes (best of both)
   ```

2. **Create FSDP Training Script**
   ```yaml
   # Save as fsdp-train-script.yaml
   apiVersion: v1
   kind: ConfigMap
   metadata:
     name: fsdp-train-script
     namespace: distributed-training
   data:
     fsdp_train.py: |
       import os
       import torch
       import torch.distributed as dist
       from torch.distributed.fsdp import FullyShardedDataParallel as FSDP
       from torch.distributed.fsdp import ShardingStrategy, MixedPrecision
       from transformers import AutoModelForCausalLM, AutoTokenizer, AutoConfig

       def setup_distributed():
           dist.init_process_group(backend="nccl")
           local_rank = int(os.environ["LOCAL_RANK"])
           torch.cuda.set_device(local_rank)
           return local_rank

       def main():
           local_rank = setup_distributed()
           rank = dist.get_rank()
           world_size = dist.get_world_size()

           if rank == 0:
               print(f"Starting FSDP training with {world_size} GPUs")

           # Mixed precision policy
           mp_policy = MixedPrecision(
               param_dtype=torch.float16,
               reduce_dtype=torch.float16,
               buffer_dtype=torch.float16,
           )

           # Load model
           model_name = "NousResearch/Llama-2-7b-hf"
           config = AutoConfig.from_pretrained(model_name)

           # Initialize on CPU first for FSDP to shard efficiently
           model = AutoModelForCausalLM.from_config(config)

           # Wrap with FSDP
           model = FSDP(
               model,
               sharding_strategy=ShardingStrategy.FULL_SHARD,
               mixed_precision=mp_policy,
               device_id=local_rank,
           )

           tokenizer = AutoTokenizer.from_pretrained(model_name)
           if tokenizer.pad_token is None:
               tokenizer.pad_token = tokenizer.eos_token

           # Training loop
           optimizer = torch.optim.AdamW(model.parameters(), lr=1e-5)

           for step in range(100):
               # Synthetic batch (replace with real data loader)
               input_ids = torch.randint(
                   0, config.vocab_size, (1, 512), device=f"cuda:{local_rank}"
               )
               labels = input_ids.clone()

               outputs = model(input_ids=input_ids, labels=labels)
               loss = outputs.loss
               loss.backward()
               optimizer.step()
               optimizer.zero_grad()

               if rank == 0 and step % 10 == 0:
                   print(f"Step {step}, Loss: {loss.item():.4f}")

           if rank == 0:
               print("FSDP training complete.")

           dist.destroy_process_group()

       if __name__ == "__main__":
           main()
   ```

3. **Deploy FSDP Training Job**
   ```yaml
   # Save as fsdp-training.yaml
   apiVersion: kubeflow.org/v2beta1
   kind: MPIJob
   metadata:
     name: fsdp-training
     namespace: distributed-training
   spec:
     slotsPerWorker: 8
     runPolicy:
       cleanPodPolicy: Running
     mpiReplicaSpecs:
       Launcher:
         replicas: 1
         template:
           spec:
             containers:
               - name: launcher
                 image: nvcr.io/nvidia/pytorch:24.12-py3
                 command:
                   - mpirun
                   - --allow-run-as-root
                   - -np
                   - "16"
                   - -npernode
                   - "8"
                   - -bind-to
                   - none
                   - -map-by
                   - slot
                   - -x
                   - NCCL_DEBUG=WARN
                   - -x
                   - NCCL_NET_GDR_LEVEL=SYS
                   - -x
                   - LD_LIBRARY_PATH
                   - python
                   - /scripts/fsdp_train.py
                 volumeMounts:
                   - name: train-script
                     mountPath: /scripts
       Worker:
         replicas: 2
         template:
           spec:
             containers:
               - name: worker
                 image: nvcr.io/nvidia/pytorch:24.12-py3
                 command: ["sleep", "infinity"]
                 env:
                   - name: NCCL_NET_GDR_LEVEL
                     value: "SYS"
                 resources:
                   limits:
                     nvidia.com/gpu: 8
                   requests:
                     nvidia.com/gpu: 8
                 securityContext:
                   capabilities:
                     add: ["IPC_LOCK"]
                 volumeMounts:
                   - name: shm
                     mountPath: /dev/shm
                   - name: train-script
                     mountPath: /scripts
             volumes:
               - name: shm
                 emptyDir:
                   medium: Memory
                   sizeLimit: 256Gi
               - name: train-script
                 configMap:
                   name: fsdp-train-script
             tolerations:
               - key: nvidia.com/gpu
                 operator: Exists
                 effect: NoSchedule
   ```

   ```bash
   kubectl apply -f fsdp-train-script.yaml
   kubectl apply -f fsdp-training.yaml

   # Monitor training
   kubectl logs -f -n distributed-training fsdp-training-launcher-0
   ```

4. **FSDP vs DeepSpeed Comparison**

   | Feature | PyTorch FSDP | DeepSpeed ZeRO |
   |---------|--------------|----------------|
   | **Native PyTorch** | Yes (torch.distributed.fsdp) | No (external library) |
   | **Memory Sharding** | FULL_SHARD = ZeRO-3 | ZeRO-1/2/3 + ZeRO-Infinity |
   | **CPU Offloading** | Yes (CPUOffload) | Yes (all stages) |
   | **NVMe Offloading** | No | Yes (ZeRO-Infinity) |
   | **Hybrid Sharding** | HYBRID_SHARD (intra-node) | ZeRO++ (hpZ) |
   | **Activation Checkpointing** | torch.utils.checkpoint | DeepSpeed checkpointing |
   | **Community** | Growing (PyTorch core) | Mature (Microsoft) |
   | **K8s Integration** | Any (torchrun/mpirun) | MPIJob or native launcher |

### Task 7: Performance Optimization (30 min)

1. **Optimized NCCL Configuration**
   ```yaml
   # Save as nccl-optimized-config.yaml
   apiVersion: v1
   kind: ConfigMap
   metadata:
     name: nccl-optimized-config
     namespace: distributed-training
   data:
     # Core NCCL settings
     NCCL_DEBUG: "WARN"              # Reduce logging overhead in production
     NCCL_IB_DISABLE: "0"            # Enable InfiniBand
     NCCL_NET_GDR_LEVEL: "SYS"       # Full GPUDirect RDMA across NUMA boundaries
     NCCL_P2P_LEVEL: "NVL"           # Use NVLink for P2P within node

     # Performance tuning
     NCCL_SOCKET_NTHREADS: "4"       # Socket threads for IB/TCP fallback
     NCCL_NSOCKS_PERTHREAD: "4"      # Sockets per thread
     NCCL_BUFFSIZE: "8388608"        # 8MB buffer (2x default, good for high-bandwidth)
     NCCL_NTHREADS: "512"            # CUDA threads for NCCL kernels

     # CUDA optimizations
     CUDA_DEVICE_MAX_CONNECTIONS: "1"  # Required for Megatron-LM async pipeline overlap

     # For AWS EFA (uncomment if using AWS)
     # FI_EFA_USE_DEVICE_RDMA: "1"
     # FI_PROVIDER: "efa"
     # FI_EFA_FORK_SAFE: "1"

     # For Azure InfiniBand (uncomment if using Azure)
     # NCCL_IB_HCA: "mlx5"
   ```

   > **Removed: NCCL_TREE_THRESHOLD.** This parameter controlled the threshold for switching between ring and tree algorithms. Modern NCCL versions (2.5+) automatically select the optimal algorithm based on message size and topology. Manual overrides are no longer recommended and may be silently ignored.

2. **Profile Training Performance**
   ```bash
   # Check which NCCL algorithm is being used
   # Set NCCL_DEBUG=INFO temporarily to see algorithm selection
   kubectl exec -it -n distributed-training <worker-pod> -- bash -c \
     "NCCL_DEBUG=INFO NCCL_DEBUG_SUBSYS=GRAPH,TUNING python -c '
   import torch, torch.distributed as dist, os
   dist.init_process_group(backend=\"nccl\")
   t = torch.zeros(1024*1024, device=\"cuda\")
   dist.all_reduce(t)
   dist.destroy_process_group()
   '"

   # Use NVIDIA Nsight Systems for detailed profiling
   # (Run inside a worker pod with nsys installed)
   nsys profile -t cuda,nvtx -o /checkpoints/training_profile python train.py
   ```

3. **Benchmark Different Parallelism Configurations**

   | Configuration | 16 GPU (2 nodes) | 32 GPU (4 nodes) | Best For |
   |---------------|------------------|------------------|----------|
   | TP=8, PP=1, DP=2 | NVLink limited | N/A | Small models, high throughput |
   | TP=4, PP=2, DP=2 | Best balance | Good | Models up to 70B |
   | TP=4, PP=4, DP=2 | N/A | Best for 4 nodes | Models > 70B |
   | TP=4, PP=2, DP=4 | N/A | High throughput | Training speed priority |

### Task 8: Checkpoint Management (20 min)

1. **Configure Distributed Checkpointing**
   ```python
   # Megatron-LM handles distributed checkpointing automatically
   # Checkpoints are sharded across tensor-parallel ranks

   # Key Megatron-LM checkpoint flags:
   # --save=/checkpoints           # Checkpoint directory
   # --load=/checkpoints           # Resume from checkpoint
   # --save-interval=500           # Save every N iterations
   # --no-load-optim               # Skip optimizer state on resume (fine-tuning)
   # --no-load-rng                 # Skip RNG state on resume
   ```

2. **DeepSpeed Checkpoint Management**
   ```python
   # DeepSpeed checkpoints are saved per-rank with ZeRO-3
   # Consolidate for inference:
   from deepspeed.utils.zero_to_fp32 import convert_zero_checkpoint_to_fp32_state_dict

   # Convert sharded ZeRO-3 checkpoint to single FP32 state dict
   convert_zero_checkpoint_to_fp32_state_dict(
       checkpoint_dir="/checkpoints/deepspeed-final",
       output_file="/checkpoints/model_fp32.bin"
   )
   ```

3. **Checkpoint Storage with Cloud Credentials**
   ```yaml
   # Save as checkpoint-credentials.yaml
   apiVersion: v1
   kind: Secret
   metadata:
     name: checkpoint-storage-creds
     namespace: distributed-training
   type: Opaque
   stringData:
     # For AWS S3 (use with s3fs-fuse or AWS SDK)
     AWS_ACCESS_KEY_ID: "<your-key>"
     AWS_SECRET_ACCESS_KEY: "<your-secret>"
     # For Azure Blob (use with blobfuse2)
     # AZURE_STORAGE_ACCOUNT: "<account>"
     # AZURE_STORAGE_ACCESS_KEY: "<key>"
   ```

---

## Deliverables

### Basic Deliverables
- [ ] k0rdent GPU cluster accessed via extracted kubeconfig
- [ ] MPI Operator v0.8.0 installed and functional
- [ ] Multi-node NCCL connectivity verified with bandwidth benchmark
- [ ] NCCL all-reduce bandwidth documented and compared to expectations

### Advanced Deliverables
- [ ] Megatron-LM training with 3D parallelism (TP=4, PP=2, DP=2)
- [ ] DeepSpeed ZeRO-3 training using mpirun launcher (not deepspeed launcher)
- [ ] PyTorch FSDP training with FULL_SHARD strategy
- [ ] Performance optimization with NCCL tuning applied
- [ ] Parallelism strategy comparison documented
- [ ] Checkpoint saving/loading verified

---

## Verification Checklist

- [ ] MPI Operator pods running in mpi-operator namespace
- [ ] Multi-node connectivity verified (NCCL benchmark shows expected bandwidth)
- [ ] Training job launches on all nodes (all workers show GPU activity)
- [ ] GPUs fully utilized (>90% during compute phases)
- [ ] NCCL using RDMA (IB or EFA visible in NCCL_DEBUG=INFO logs)
- [ ] Checkpoints saved to shared storage
- [ ] Training loss decreasing across iterations
- [ ] NCCL_NET_GDR_LEVEL=SYS confirmed in worker environment

---

## Troubleshooting

### Job Hangs at NCCL Initialization

```bash
# Check if all workers are running
kubectl get pods -n distributed-training

# Verify RDMA devices available on workers
kubectl exec -it -n distributed-training <worker-pod> -- ibstat  # Azure IB
kubectl exec -it -n distributed-training <worker-pod> -- fi_info -p efa  # AWS EFA

# Check for firewall issues
# Security group / NSG must allow all traffic between GPU nodes

# Enable verbose NCCL debugging
kubectl exec -it -n distributed-training <worker-pod> -- bash -c \
  "NCCL_DEBUG=INFO NCCL_DEBUG_SUBSYS=NET python -c '
import torch.distributed as dist
dist.init_process_group(backend=\"nccl\", timeout=datetime.timedelta(seconds=30))
'"
```

### DeepSpeed Launcher Conflicts with MPIJob

```bash
# WRONG: Using DeepSpeed's own launcher inside MPIJob
# deepspeed --num_gpus=16 --num_nodes=2 --hostfile=/etc/mpi/hostfile train.py
# This spawns duplicate processes (mpirun + deepspeed SSH both try to manage workers)

# CORRECT: Use mpirun to launch Python directly with DeepSpeed flags
# mpirun ... python train.py --deepspeed --deepspeed_config=/config/ds_config.json

# If you must use DeepSpeed launcher, use it OUTSIDE of MPIJob
# (e.g., with a regular Deployment or Job and SSH-based multi-node setup)
```

### Out of Memory (OOM) Errors

```bash
# Reduce micro-batch size
--micro-batch-size=1

# Enable gradient checkpointing (activation recomputation)
# Megatron-LM:
--recompute-activations
# DeepSpeed:
# "activation_checkpointing": {"partition_activations": true} in ds_config.json

# Use ZeRO-3 / FSDP FULL_SHARD to partition parameters
# Offload optimizer states to CPU if GPU memory is still insufficient
```

### Poor Scaling Efficiency

```bash
# Profile to identify whether bottleneck is compute or communication
nsys profile -t cuda,nvtx -o /tmp/profile python train.py

# Check if NCCL is selecting suboptimal algorithms
NCCL_DEBUG=INFO NCCL_DEBUG_SUBSYS=TUNING python train.py 2>&1 | grep "algorithm"

# Ensure tensor parallelism stays within NVLink-connected GPUs
# TP should NOT exceed GPUs per node (typically 8)

# Verify overlap_comm is effective (DeepSpeed)
# Check wall_clock_breakdown output for communication vs compute time
```

---

## Key Takeaways

### Parallelism Strategy Selection

| Scenario | Recommended Strategy |
|----------|---------------------|
| Model fits in 1 GPU | Data Parallel (DP) only |
| Model fits in 1 node | TP = num_gpus, DP for scaling |
| Model > 1 node | TP within node, PP across nodes |
| Very large model | 3D: TP (intra), PP (inter), DP (scale) |

### Communication Hierarchy

```
              Speed (Bandwidth)
                    ↑
    ┌───────────────┼───────────────┐
    │               │               │
    │   GPU Memory  │ ~3000 GB/s    │ ← Fastest (HBM3)
    │   (HBM)       │               │
    │               │               │
    ├───────────────┼───────────────┤
    │   NVLink 4.0  │ ~900 GB/s     │ ← Use for TP (H100)
    │   NVLink 3.0  │ ~600 GB/s     │ ← Use for TP (A100)
    │               │               │
    ├───────────────┼───────────────┤
    │   InfiniBand  │ ~400 GB/s     │ ← Use for PP (NDR 8x)
    │   (NDR)       │               │
    │               │               │
    ├───────────────┼───────────────┤
    │   PCIe 5.0    │ ~128 GB/s     │ ← Avoid for training
    │               │               │
    ├───────────────┼───────────────┤
    │   Ethernet    │ ~12.5 GB/s    │ ← Only for DP (async)
    │   (100 GbE)   │               │
    │               │               │
    └───────────────┴───────────────┘
```

---

## Cleanup

Remove all training resources when done:

```bash
# Delete training jobs
kubectl delete mpijob --all -n distributed-training

# Delete configurations
kubectl delete configmap megatron-config megatron-setup deepspeed-config \
  deepspeed-train-script fsdp-train-script nccl-optimized-config \
  -n distributed-training

# Delete storage (WARNING: deletes checkpoints)
kubectl delete pvc training-checkpoints training-data -n distributed-training

# Delete namespace
kubectl delete namespace distributed-training

# Optionally remove MPI Operator
kubectl delete -f https://raw.githubusercontent.com/kubeflow/mpi-operator/v0.8.0/deploy/v2beta1/mpi-operator.yaml
```

---

## References

### NVIDIA
- [Megatron-LM](https://github.com/NVIDIA/Megatron-LM) - NVIDIA's large model training framework
- [NCCL Documentation](https://docs.nvidia.com/deeplearning/nccl/) - Collective communication library
- [NCCL Environment Variables](https://docs.nvidia.com/deeplearning/nccl/user-guide/docs/env.html) - Configuration reference

### Microsoft
- [DeepSpeed](https://www.deepspeed.ai/) - Deep learning optimization library
- [DeepSpeed ZeRO](https://www.deepspeed.ai/tutorials/zero/) - Memory optimization tutorial

### PyTorch
- [FSDP Tutorial](https://pytorch.org/tutorials/intermediate/FSDP_tutorial.html) - Fully Sharded Data Parallel
- [Distributed Training](https://pytorch.org/docs/stable/distributed.html) - PyTorch distributed reference

### Kubeflow
- [MPI Operator v0.8.0](https://github.com/kubeflow/mpi-operator/releases/tag/v0.8.0) - Kubernetes MPI job scheduling

---

## Next Steps

After completing this lab, you have the knowledge to:
1. Design parallelism strategies for any model size
2. Configure enterprise distributed training on k0rdent infrastructure
3. Choose between Megatron-LM, DeepSpeed, and FSDP based on requirements
4. Optimize NCCL communication for multi-node training

**Recommended Path:**
- Lab 5.9 (Kubeflow ML Platform) for end-to-end MLOps pipelines
- Lab 5.11 (Run:AI GPU Orchestration) for enterprise GPU scheduling
- Week 6 (Multi-tenancy) for shared infrastructure patterns
