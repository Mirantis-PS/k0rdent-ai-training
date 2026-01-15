# Lab 5.15 - Multi-Node Distributed Training

**Duration:** 4.5 hours
**Type:** Hands-on Technical (Advanced)
**Environment:** 2+ GPU nodes (p4d.24xlarge or ND A100 v4)

## Objective

Implement and optimize multi-node distributed training using tensor and pipeline parallelism across multiple GPU nodes. This lab demonstrates enterprise-scale AI training techniques using Megatron-LM, DeepSpeed, and PyTorch FSDP.

## Prerequisites

- Completed Lab 5.14 (Multi-Cloud RDMA Deep Dive)
- Access to 2+ GPU nodes with RDMA/InfiniBand connectivity
- NVIDIA GPU Operator and Network Operator configured
- Understanding of NVLink and inter-node networking
- Kubeflow MPI Operator or similar job scheduler

---

## Background: Distributed Training Architecture

### Why Distribute Training?

Modern large language models exceed single-GPU or even single-node memory capacity:

| Model | Parameters | FP16 Memory | A100-80GB GPUs Needed |
|-------|------------|-------------|----------------------|
| GPT-2 | 1.5B | ~3 GB | 1 |
| LLaMA-7B | 7B | ~14 GB | 1 |
| LLaMA-70B | 70B | ~140 GB | 2 (with optimization) |
| GPT-4 (est.) | ~1.8T | ~3.6 TB | 45+ |
| Llama-3-405B | 405B | ~810 GB | 11+ |

**Training requires significantly more memory than inference:**
- Model parameters (weights)
- Gradients (same size as parameters)
- Optimizer states (2-8x parameters for Adam)
- Activations (depends on batch size)

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
                    │  │TP=0 │TP=1 │TP=2 │TP=3 │         │
Node 0 ─────────────│  │GPU 0│GPU 1│GPU 2│GPU 3│         │
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
- Kubeflow MPI Operator v0.4+
- PyTorch 2.x with distributed support

---

## Tasks

### Task 1: Install MPI Operator (20 min)

The MPI Operator enables distributed training jobs on Kubernetes.

1. **Install Kubeflow MPI Operator**
   ```bash
   kubectl apply -f https://raw.githubusercontent.com/kubeflow/mpi-operator/v0.4.0/deploy/v2beta1/mpi-operator.yaml

   # Verify installation
   kubectl get crd mpijobs.kubeflow.org
   kubectl get deployment mpi-operator -n mpi-operator
   ```

2. **Create Training Namespace**
   ```bash
   kubectl create namespace distributed-training
   ```

### Task 2: Verify Multi-Node Connectivity (30 min)

Before training, verify NCCL communication across nodes.

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
                   - NCCL_NET_GDR_LEVEL=5
                   - -x
                   - LD_LIBRARY_PATH
                   - /opt/nccl-tests/build/all_reduce_perf
                   - -b
                   - 1M
                   - -e
                   - 4G
                   - -f
                   - "2"
                   - -g
                   - "1"
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
                     value: "5"
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
   kubectl logs -f -n distributed-training $(kubectl get pods -n distributed-training -l job-name=nccl-test-launcher -o jsonpath='{.items[0].metadata.name}')
   ```

2. **Expected Output Analysis**
   ```
   # Look for these key lines:
   NCCL INFO comm 0x... rank 0 nranks 16 cudaDev 0 busId 0000:00:1e.0
   NCCL INFO NET/IB : Using [0]mlx5_0:1/IB  # InfiniBand being used
   # OR for AWS:
   NCCL INFO NET/AWS-EFA : Using EFA device 0

   # Performance results should show:
   #       size     time   algbw   busbw
   #   4294967296    45.2   95.03  178.18  # ~175 GB/s bus bandwidth for 16 GPUs
   ```

   **Bandwidth Expectations:**
   - Single node (8 GPU): ~880 GB/s (NVLink limited)
   - Two nodes (16 GPU): ~350-400 GB/s (network limited)
   - Four nodes (32 GPU): ~300-350 GB/s

### Task 3: Understanding Megatron-LM (30 min)

Megatron-LM is NVIDIA's framework for training large transformer models.

1. **Megatron-LM Parallelism Configuration**

   ```bash
   # Example Megatron-LM configuration for 70B model on 16 GPUs (2 nodes)
   # TP=4 (within node), PP=2 (across nodes), DP=2

   TENSOR_MODEL_PARALLEL_SIZE=4   # Split layers across 4 GPUs
   PIPELINE_MODEL_PARALLEL_SIZE=2  # 2 pipeline stages
   DATA_PARALLEL_SIZE=2            # 2 data parallel replicas

   # Total GPUs = TP * PP * DP = 4 * 2 * 2 = 16
   ```

2. **Create Megatron Training Configuration**
   ```yaml
   # Save as megatron-config.yaml
   apiVersion: v1
   kind: ConfigMap
   metadata:
     name: megatron-config
     namespace: distributed-training
   data:
     # Parallelism configuration
     TENSOR_MODEL_PARALLEL_SIZE: "4"
     PIPELINE_MODEL_PARALLEL_SIZE: "2"
     DATA_PARALLEL_SIZE: "2"

     # Training hyperparameters
     MICRO_BATCH_SIZE: "1"
     GLOBAL_BATCH_SIZE: "64"
     SEQ_LENGTH: "2048"
     MAX_POSITION_EMBEDDINGS: "4096"

     # Model architecture (70B-like)
     NUM_LAYERS: "80"
     HIDDEN_SIZE: "8192"
     NUM_ATTENTION_HEADS: "64"
     FFN_HIDDEN_SIZE: "28672"

     # Optimization
     FP16: "true"
     DISTRIBUTED_BACKEND: "nccl"

     # NCCL optimizations
     NCCL_DEBUG: "INFO"
     NCCL_IB_DISABLE: "0"
     NCCL_NET_GDR_LEVEL: "5"
     NCCL_P2P_LEVEL: "NVL"
   ```

### Task 4: Deploy Megatron-LM Training Job (60 min)

1. **Create Storage for Checkpoints**
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
     storageClassName: efs  # Or azurefile for Azure
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

2. **Deploy Megatron Training Job**
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
                   - NCCL_NET_GDR_LEVEL=5
                   - -x
                   - CUDA_DEVICE_MAX_CONNECTIONS=1
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
                   - name: checkpoints
                     mountPath: /checkpoints
                   - name: data
                     mountPath: /data
             volumes:
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
                   - name: checkpoints
                     mountPath: /checkpoints
                   - name: data
                     mountPath: /data
             volumes:
               - name: shm
                 emptyDir:
                   medium: Memory
                   sizeLimit: 256Gi
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
   kubectl apply -f training-storage.yaml
   kubectl apply -f megatron-training.yaml

   # Monitor training
   kubectl logs -f -n distributed-training megatron-gpt-training-launcher-0
   ```

3. **Monitor Training Progress**
   ```bash
   # Watch for training metrics:
   # iteration: 1 | consumed tokens: 65536 | loss: 10.534 | time: 2.45s

   # Track GPU utilization
   kubectl exec -it -n distributed-training megatron-gpt-training-worker-0 -- nvidia-smi dmon -s u

   # Check NCCL communication
   kubectl logs -n distributed-training megatron-gpt-training-worker-0 | grep NCCL
   ```

### Task 5: DeepSpeed ZeRO Optimization (45 min)

DeepSpeed ZeRO partitions optimizer states across GPUs, enabling larger models.

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
   │  Memory per GPU: ~75% (4x optimizer reduction)                  │
   │                                                                 │
   │  ZeRO Stage 2 (+ Gradient Partitioning)                         │
   │  ┌─────────────────────────────────────────────────────────┐   │
   │  │ GPU: Full Model + 1/N Gradients + 1/N Optimizer         │   │
   │  └─────────────────────────────────────────────────────────┘   │
   │  Memory per GPU: ~50% (gradient + optimizer reduction)          │
   │                                                                 │
   │  ZeRO Stage 3 (+ Parameter Partitioning)                        │
   │  ┌─────────────────────────────────────────────────────────┐   │
   │  │ GPU: 1/N Model + 1/N Gradients + 1/N Optimizer          │   │
   │  └─────────────────────────────────────────────────────────┘   │
   │  Memory per GPU: ~1/N (linear scaling with GPUs)                │
   │                                                                 │
   └─────────────────────────────────────────────────────────────────┘
   ```

2. **DeepSpeed Configuration**
   ```json
   // Save as ds_config.json
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

3. **Create DeepSpeed Training ConfigMap**
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
         "fp16": {
           "enabled": true
         },
         "zero_optimization": {
           "stage": 3,
           "overlap_comm": true,
           "contiguous_gradients": true,
           "reduce_bucket_size": 5e8
         },
         "gradient_clipping": 1.0
       }
   ```

4. **Deploy DeepSpeed Training**
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
                   - deepspeed
                   - --num_gpus=16
                   - --num_nodes=2
                   - --hostfile=/etc/mpi/hostfile
                   - train.py
                   - --deepspeed
                   - --deepspeed_config=/config/ds_config.json
                 volumeMounts:
                   - name: config
                     mountPath: /config
             volumes:
               - name: config
                 configMap:
                   name: deepspeed-config
       Worker:
         replicas: 2
         template:
           spec:
             containers:
               - name: worker
                 image: nvcr.io/nvidia/pytorch:24.12-py3
                 command: ["sleep", "infinity"]
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
             volumes:
               - name: shm
                 emptyDir:
                   medium: Memory
                   sizeLimit: 256Gi
               - name: config
                 configMap:
                   name: deepspeed-config
             tolerations:
               - key: nvidia.com/gpu
                 operator: Exists
                 effect: NoSchedule
   ```

### Task 6: PyTorch FSDP (Fully Sharded Data Parallel) (45 min)

FSDP is PyTorch's native implementation of ZeRO-style sharding.

1. **Understanding FSDP**
   ```python
   # FSDP Example Code
   from torch.distributed.fsdp import FullyShardedDataParallel as FSDP
   from torch.distributed.fsdp import ShardingStrategy

   # Sharding strategies:
   # FULL_SHARD: ZeRO-3 equivalent (all parameters sharded)
   # SHARD_GRAD_OP: ZeRO-2 equivalent (gradients and optimizer sharded)
   # NO_SHARD: DDP equivalent (no sharding)
   # HYBRID_SHARD: Shard within node, replicate across nodes

   model = FSDP(
       model,
       sharding_strategy=ShardingStrategy.FULL_SHARD,
       cpu_offload=None,  # Or CPUOffload(offload_params=True)
       auto_wrap_policy=transformer_auto_wrap_policy,
   )
   ```

2. **FSDP Training Script**
   ```python
   # Save as fsdp_train.py
   import os
   import torch
   import torch.distributed as dist
   from torch.distributed.fsdp import FullyShardedDataParallel as FSDP
   from torch.distributed.fsdp import ShardingStrategy, MixedPrecision
   from transformers import AutoModelForCausalLM, AutoTokenizer

   def setup_distributed():
       dist.init_process_group(backend="nccl")
       local_rank = int(os.environ["LOCAL_RANK"])
       torch.cuda.set_device(local_rank)
       return local_rank

   def main():
       local_rank = setup_distributed()

       # Mixed precision policy
       mp_policy = MixedPrecision(
           param_dtype=torch.float16,
           reduce_dtype=torch.float16,
           buffer_dtype=torch.float16,
       )

       # Load model
       model = AutoModelForCausalLM.from_pretrained(
           "meta-llama/Llama-2-7b-hf",
           torch_dtype=torch.float16,
       )

       # Wrap with FSDP
       model = FSDP(
           model,
           sharding_strategy=ShardingStrategy.FULL_SHARD,
           mixed_precision=mp_policy,
           device_id=local_rank,
       )

       # Training loop
       optimizer = torch.optim.AdamW(model.parameters(), lr=1e-5)

       for step in range(100):
           # Your training code here
           loss = model(input_ids).loss
           loss.backward()
           optimizer.step()
           optimizer.zero_grad()

           if local_rank == 0 and step % 10 == 0:
               print(f"Step {step}, Loss: {loss.item()}")

   if __name__ == "__main__":
       main()
   ```

3. **FSDP vs DeepSpeed Comparison**

   | Feature | PyTorch FSDP | DeepSpeed ZeRO |
   |---------|--------------|----------------|
   | **Native PyTorch** | Yes | No (wrapper) |
   | **Ease of use** | Moderate | Easy |
   | **CPU Offloading** | Yes | Yes |
   | **NVMe Offloading** | Limited | Yes (ZeRO-Infinity) |
   | **Megatron Integration** | Manual | Native |
   | **Community Support** | Growing | Mature |

### Task 7: Performance Optimization (30 min)

1. **Optimize NCCL Configuration**
   ```yaml
   # Environment variables for maximum performance
   apiVersion: v1
   kind: ConfigMap
   metadata:
     name: nccl-optimized-config
     namespace: distributed-training
   data:
     # Core NCCL settings
     NCCL_DEBUG: "WARN"              # Reduce logging overhead in production
     NCCL_IB_DISABLE: "0"            # Enable InfiniBand
     NCCL_NET_GDR_LEVEL: "5"         # Full GPUDirect RDMA
     NCCL_P2P_LEVEL: "NVL"           # Use NVLink for P2P

     # Performance tuning
     NCCL_SOCKET_NTHREADS: "4"       # Socket threads
     NCCL_NSOCKS_PERTHREAD: "4"      # Sockets per thread
     NCCL_BUFFSIZE: "8388608"        # 8MB buffer size
     NCCL_NTHREADS: "512"            # CUDA threads

     # Tree vs Ring algorithms
     NCCL_TREE_THRESHOLD: "0"        # Use tree for all sizes (better for many nodes)

     # CUDA optimizations
     CUDA_DEVICE_MAX_CONNECTIONS: "1"  # Required for Megatron async

     # For AWS EFA
     # FI_EFA_USE_DEVICE_RDMA: "1"
     # FI_PROVIDER: "efa"
     # FI_EFA_FORK_SAFE: "1"
   ```

2. **Profile Training Performance**
   ```bash
   # Enable NCCL profiling
   export NCCL_DEBUG=INFO
   export NCCL_DEBUG_SUBSYS=GRAPH,TUNING

   # Use PyTorch profiler
   # In your training script:
   # with torch.profiler.profile() as prof:
   #     training_step()
   # print(prof.key_averages().table())

   # Use NVIDIA Nsight Systems
   nsys profile -t cuda,nvtx -o training_profile python train.py
   ```

3. **Benchmark Different Configurations**

   | Configuration | 16 GPU (2 nodes) | 32 GPU (4 nodes) |
   |---------------|------------------|------------------|
   | TP=8, PP=1, DP=2 | Good (NVLink bound) | N/A |
   | TP=4, PP=2, DP=2 | Best for 2 nodes | Good |
   | TP=4, PP=4, DP=2 | N/A | Best for 4 nodes |
   | TP=4, PP=2, DP=4 | N/A | Alternative |

### Task 8: Checkpoint Management (20 min)

1. **Configure Distributed Checkpointing**
   ```python
   # Megatron-LM checkpoint configuration
   # Checkpoints are automatically sharded across TP ranks

   # Save checkpoint
   save_checkpoint(
       iteration=step,
       model=model,
       optimizer=optimizer,
       lr_scheduler=scheduler,
   )

   # Load checkpoint
   load_checkpoint(
       model=model,
       optimizer=optimizer,
       lr_scheduler=scheduler,
   )
   ```

2. **Checkpoint Storage Configuration**
   ```yaml
   # For AWS S3
   apiVersion: v1
   kind: Secret
   metadata:
     name: s3-credentials
     namespace: distributed-training
   stringData:
     AWS_ACCESS_KEY_ID: "<key>"
     AWS_SECRET_ACCESS_KEY: "<secret>"
   ---
   # For Azure Blob
   apiVersion: v1
   kind: Secret
   metadata:
     name: azure-credentials
     namespace: distributed-training
   stringData:
     AZURE_STORAGE_CONNECTION_STRING: "<connection-string>"
   ```

---

## Deliverables

### Basic Deliverables
- [ ] MPI Operator installed and functional
- [ ] Multi-node NCCL test completed (16+ GPUs)
- [ ] NCCL all-reduce bandwidth documented
- [ ] Single training job completed successfully

### Advanced Deliverables
- [ ] Megatron-LM training with 3D parallelism
- [ ] DeepSpeed ZeRO-3 configuration working
- [ ] PyTorch FSDP training implemented
- [ ] Performance optimization documented
- [ ] Parallelism strategy comparison table
- [ ] Checkpoint saving/loading verified

---

## Verification Checklist

- [ ] MPI Operator pods running
- [ ] Multi-node connectivity verified (NCCL test passes)
- [ ] Training job launches on all nodes
- [ ] GPUs fully utilized (>90% during compute phases)
- [ ] NCCL using RDMA (IB or EFA in logs)
- [ ] Checkpoints saved successfully
- [ ] Training loss decreasing

---

## Troubleshooting

### Job Hangs at NCCL Initialization

```bash
# Check if all workers can communicate
kubectl exec -it worker-0 -- ping worker-1-hostname

# Verify RDMA devices available
kubectl exec -it worker-0 -- ibstat  # Azure
kubectl exec -it worker-0 -- fi_info -p efa  # AWS

# Check for firewall issues
# Security group / NSG must allow all traffic between nodes
```

### Out of Memory (OOM) Errors

```bash
# Reduce batch size
--micro-batch-size=1

# Enable gradient checkpointing
--checkpoint-activations

# Use ZeRO-3 / FSDP Full Shard
# Offload optimizer states to CPU if needed
```

### Poor Scaling Efficiency

```bash
# Check communication overlap
# Ensure NCCL is using tree algorithm for many nodes
export NCCL_TREE_THRESHOLD=0

# Profile to identify bottleneck
nsys profile python train.py
# Look for long NCCL calls
```

### Checkpoint Corruption

```bash
# Always use distributed checkpointing
# Verify checkpoint integrity before training resume
python -c "import torch; torch.load('checkpoint.pt')"

# Use checkpoint verification
--verify-checkpoint
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
    │   GPU Memory  │ ~3000 GB/s    │ ← Fastest
    │   (HBM3)      │               │
    │               │               │
    ├───────────────┼───────────────┤
    │   NVLink      │ ~900 GB/s     │ ← Use for TP
    │   (H100)      │               │
    │               │               │
    ├───────────────┼───────────────┤
    │   PCIe 5.0    │ ~128 GB/s     │ ← Avoid
    │               │               │
    │               │               │
    ├───────────────┼───────────────┤
    │   InfiniBand  │ ~400 GB/s     │ ← Use for PP
    │   (NDR)       │               │
    │               │               │
    ├───────────────┼───────────────┤
    │   Ethernet    │ ~12.5 GB/s    │ ← Only for DP
    │   (100 GbE)   │               │
    │               │               │
    └───────────────┴───────────────┘
```

### Training Time Estimation

For a 70B parameter model on 16 A100-80GB GPUs:
- Tokens per second: ~50,000 (with optimization)
- 1T tokens = ~5,500 GPU-hours = ~230 GPU-days = ~14 days on 16 GPUs

---

## References

### NVIDIA
- [Megatron-LM](https://github.com/NVIDIA/Megatron-LM)
- [NCCL Documentation](https://docs.nvidia.com/deeplearning/nccl/)
- [CUDA Multi-Process Service](https://docs.nvidia.com/cuda/mps/)

### Microsoft
- [DeepSpeed](https://www.deepspeed.ai/)
- [DeepSpeed ZeRO](https://www.deepspeed.ai/tutorials/zero/)
- [DeepSpeed Megatron](https://github.com/microsoft/Megatron-DeepSpeed)

### PyTorch
- [FSDP Tutorial](https://pytorch.org/tutorials/intermediate/FSDP_tutorial.html)
- [Distributed Training](https://pytorch.org/docs/stable/distributed.html)

### Kubeflow
- [MPI Operator](https://github.com/kubeflow/mpi-operator)

---

## Next Steps

After completing this lab, you have the knowledge to:
1. Design parallelism strategies for any model size
2. Configure enterprise distributed training infrastructure
3. Optimize training performance with NCCL tuning
4. Implement fault-tolerant checkpointing

**Recommended Path:**
- Lab 5.9 (Kubeflow ML Platform) for end-to-end MLOps
- Lab 5.11 (Run:AI GPU Orchestration) for enterprise scheduling
