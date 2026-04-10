# Lab 5.5 - Deploy vLLM Inference Service

---

## Lab Navigation

| Track | Tier | Duration |
|-------|------|----------|
| Foundation | Required | 4 hours |

### Week 5 Learning Paths

```
FOUNDATION (Required)                              CHOOSE YOUR PATH
━━━━━━━━━━━━━━━━━━━━                              ━━━━━━━━━━━━━━━━
5.1 ➔ 5.2 ➔ 5.3 ➔ 5.4 ➔ [5.5] ➔ 5.6 ➔ 5.7 ➔ 5.8  ──►  ML Platforms (5.9-5.10)
                           ↑                              Compliance (5.11-5.12)
                      YOU ARE HERE                        Advanced (5.13-5.16)
```

| Previous | Current | Next |
|----------|---------|------|
| [Lab 5.4 - Run:ai GPU Orchestration](lab-5.4-runai-gpu-orchestration.md) | **Lab 5.5 - vLLM Inference** | [Lab 5.6 - Troubleshooting GPU](lab-5.6-troubleshooting-gpu.md) |

---

## Table of Contents

- [Objective](#objective)
- [Prerequisites](#prerequisites)
- [Lab Environment](#lab-environment)
- [Background: LLM Inference Architecture](#background-llm-inference-architecture)
  - [Why LLM Inference Is Challenging](#why-llm-inference-is-challenging)
  - [Memory Breakdown for LLM Inference](#memory-breakdown-for-llm-inference)
  - [Parallelism Strategies](#parallelism-strategies)
  - [NVLink and GPU Topology](#nvlink-and-gpu-topology)
  - [Quantization Overview](#quantization-overview)
- [Tasks](#tasks)
  - [Task 1: Prepare Model Access](#task-1-prepare-model-access-15-min)
  - [Task 2: Deploy vLLM Server](#task-2-deploy-vllm-server-45-min)
  - [Task 3: Create Service and Ingress](#task-3-create-service-and-ingress-20-min)
  - [Task 4: Test Inference Endpoint](#task-4-test-inference-endpoint-30-min)
  - [Task 5: Monitor GPU Utilization](#task-5-monitor-gpu-utilization-20-min)
  - [Task 6: Configure Horizontal Scaling](#task-6-configure-horizontal-scaling-20-min)
- [Advanced Tasks: Enterprise-Grade Optimizations](#advanced-tasks-enterprise-grade-optimizations)
  - [Task 7: Tensor Parallelism Deep-Dive](#task-7-tensor-parallelism-deep-dive-45-min)
  - [Task 8: Quantization Strategies](#task-8-quantization-strategies-45-min)
  - [Task 9: Performance Benchmarking](#task-9-performance-benchmarking-30-min)
- [k0rdent Enterprise Integration](#k0rdent-enterprise-integration)
- [Deliverables](#deliverables)
- [Verification Checklist](#verification-checklist)
- [Troubleshooting](#troubleshooting)
- [Key Takeaways](#key-takeaways)
- [References](#references)
- [Next Lab](#next-lab)

**Duration:** 4 hours (includes advanced topics)
**Type:** Hands-on Technical
**Environment:** GPU Lab

## Objective

Deploy a production-ready LLM inference service using vLLM on Kubernetes with proper resource management, monitoring, and enterprise-grade optimizations including tensor parallelism, quantization, and NVLink-aware multi-GPU inference.

## Prerequisites

- Completed Lab 5.1 (GPU Cluster Setup)
- Kubernetes cluster with GPU nodes
- At least 1 GPU with 24GB+ VRAM (A100 recommended)
- For Advanced Tasks: 4-8 GPUs with NVLink (p4d.24xlarge or ND A100 v4)
- Hugging Face account (for model access)

## Lab Environment

**Cluster Requirements:**
- 1+ GPU nodes with NVIDIA A100 or equivalent
- GPU Operator installed
- Network access to Hugging Face

**Model:** Llama-2-7B-chat (or Mistral-7B as alternative)

---

## Background: LLM Inference Architecture

Understanding how LLMs are served at scale requires knowledge of the underlying parallelism strategies and memory optimizations. This section provides the theoretical foundation for the hands-on tasks.

### Why LLM Inference Is Challenging

Large Language Models present unique serving challenges:

| Challenge | Impact | Solution |
|-----------|--------|----------|
| **Model Size** | Llama-2-70B requires ~140GB in FP16 | Multi-GPU tensor parallelism |
| **KV Cache Growth** | Memory grows linearly with sequence length | PagedAttention, KV cache quantization |
| **Latency Requirements** | Real-time applications need <100ms TTFT | GPU optimization, batching |
| **Throughput** | High request volumes require efficiency | Continuous batching |

### Memory Breakdown for LLM Inference

For a Llama-2-70B model with 4096 context length:

```
┌─────────────────────────────────────────────────────────────────┐
│                     GPU Memory Layout (Llama-2-70B, FP16)       │
├─────────────────────────────────────────────────────────────────┤
│  Model Weights (FP16)           │  ~140 GB                      │
│  ├─ FFN (gate+up+down, SwiGLU)  │  ~112.7 GB (80% of model)    │
│  ├─ Attention (QKV+O, 8 KV GQA) │   ~24.2 GB                   │
│  ├─ Embeddings (input + lm_head) │    ~1.0 GB                   │
│  └─ RMSNorm layers               │    ~0.003 GB                 │
├─────────────────────────────────────────────────────────────────┤
│  KV Cache (per batch, FP16)     │  ~320 MB per 1K tokens        │
│  ├─ Keys: 80 layers × 8 heads   │    160 MB                     │
│  └─ Values: 80 layers × 8 heads │    160 MB                     │
├─────────────────────────────────────────────────────────────────┤
│  Activation Memory              │  ~2-4 GB (varies with batch)  │
├─────────────────────────────────────────────────────────────────┤
│  CUDA/NCCL Overhead             │  ~2-3 GB                      │
└─────────────────────────────────────────────────────────────────┘

Note: FFN dominates because SwiGLU uses 3 projection matrices
(gate, up, down) each 8192×28672. GQA (8 KV heads vs 64 attention
heads) dramatically reduces attention parameters vs standard MHA.
KV cache per token: 2 × 80 × 8 × 128 × 2 bytes = 320 KB.
```

### Parallelism Strategies

vLLM supports three parallelism strategies for scaling inference across GPUs:

#### 1. Tensor Parallelism (TP)
Splits individual layers across GPUs. Each GPU holds a portion of every layer.

```
Single Layer with Tensor Parallelism (TP=4):

                    Input Tokens
                         │
         ┌───────────────┼───────────────┐
         │               │               │
    ┌────▼────┐    ┌────▼────┐    ┌────▼────┐    ┌────▼────┐
    │  GPU 0  │    │  GPU 1  │    │  GPU 2  │    │  GPU 3  │
    │ 1/4 QKV │    │ 1/4 QKV │    │ 1/4 QKV │    │ 1/4 QKV │
    │ 1/4 MLP │    │ 1/4 MLP │    │ 1/4 MLP │    │ 1/4 MLP │
    └────┬────┘    └────┬────┘    └────┬────┘    └────┬────┘
         │               │               │               │
         └───────────────┴───────┬───────┴───────────────┘
                                 │
                    All-Reduce (NVLink)
                                 │
                          Output Tokens
```

**When to use:** When model fits in combined GPU memory of a single node.
- **Requires:** NVLink for efficient all-reduce operations
- **Latency:** Low (single-node communication)
- **Bandwidth:** 600-900 GB/s (NVLink 3.0/4.0)

#### 2. Pipeline Parallelism (PP)
Splits model layers sequentially across GPUs. Each GPU holds a subset of layers.

```
Pipeline Parallelism (PP=4):

   Input → [GPU 0: Layers 0-19] → [GPU 1: Layers 20-39] →
           [GPU 2: Layers 40-59] → [GPU 3: Layers 60-79] → Output
```

**When to use:** When model exceeds single-node memory.
- **Requires:** Can work over PCIe or network
- **Latency:** Higher (sequential pipeline stages)
- **Best for:** Very large models across multiple nodes

#### 3. Combined TP + PP
For massive models that need both strategies:

```bash
# 8 GPUs total: TP=4, PP=2
# Each pipeline stage uses 4 GPUs with tensor parallelism
vllm serve meta-llama/Llama-2-70b-chat-hf \
     --tensor-parallel-size 4 \
     --pipeline-parallel-size 2
```

### NVLink and GPU Topology

NVLink provides high-bandwidth GPU-to-GPU communication critical for tensor parallelism.

| GPU Generation | NVLink Version | Bidirectional Bandwidth |
|----------------|----------------|------------------------|
| V100 (p3) | NVLink 2.0 | 300 GB/s |
| A100 (p4d) | NVLink 3.0 | 600 GB/s |
| H100 (p5) | NVLink 4.0 | 900 GB/s |

**Why NVLink Matters for TP:**
- All-reduce operations happen at every transformer layer
- With 80 layers, a single forward pass requires ~160 all-reduce operations
- PCIe bandwidth (64 GB/s) would create severe bottlenecks

### Quantization Overview

Quantization reduces model precision to decrease memory usage and increase throughput:

| Precision | Bits/Param | Memory (70B) | Relative Speed | Quality Loss |
|-----------|-----------|--------------|----------------|--------------|
| FP32 | 32 | 280 GB | 1x (baseline) | None |
| FP16/BF16 | 16 | 140 GB | 2x | Negligible |
| FP8 | 8 | 70 GB | 2.5-3x | Minimal |
| INT8 | 8 | 70 GB | 2-2.5x | Low |
| INT4 (AWQ) | 4 | 35 GB | 3-4x | Low-Medium |

**Key Quantization Methods:**

1. **FP8 (Float8):** Native W8A8 on H100+ Tensor Cores (Hopper/Ada Lovelace, CC ≥ 8.9)
   - E4M3 format for weights, E5M2 format for activations
   - Weight-only FP8 (W8A16) available on A100 via Marlin kernels (memory savings, not full throughput)
   - Best quality/performance ratio on natively supported hardware

2. **AWQ (Activation-aware Weight Quantization):**
   - INT4 weights with FP16 activations
   - Preserves important weight channels based on activation statistics
   - Lightweight calibration (small sample set, no backpropagation — generalizes better than GPTQ)

3. **GPTQ:**
   - One-shot INT4 quantization with Hessian-based weight reconstruction
   - Requires calibration dataset (can overfit to calibration data)
   - Generally lower quality retention than AWQ, but faster inference kernels on NVIDIA GPUs

---

## Tasks

### Task 1: Prepare Model Access (15 min)

1. **Create Hugging Face Token Secret**
   ```bash
   # Get token from https://huggingface.co/settings/tokens
   # Accept Llama-2 license at https://huggingface.co/meta-llama/Llama-2-7b-chat-hf

   kubectl create namespace vllm-inference

   kubectl create secret generic hf-token \
     --from-literal=token=<your-hf-token> \
     -n vllm-inference
   ```

2. **Create Model Cache PVC**
   ```yaml
   # Save as model-cache-pvc.yaml
   apiVersion: v1
   kind: PersistentVolumeClaim
   metadata:
     name: model-cache
     namespace: vllm-inference
   spec:
     accessModes:
       - ReadWriteOnce
     resources:
       requests:
         storage: 50Gi
     # Uses the cluster's default StorageClass (ebs-csi-default-sc on CAPA clusters from Lab 5.1)
   ```

   ```bash
   kubectl apply -f model-cache-pvc.yaml
   ```

### Task 2: Deploy vLLM Server (45 min)

1. **Create vLLM Deployment**
   ```yaml
   # Save as vllm-deployment.yaml
   apiVersion: apps/v1
   kind: Deployment
   metadata:
     name: vllm-llama2
     namespace: vllm-inference
     labels:
       app: vllm-llama2
   spec:
     replicas: 1
     selector:
       matchLabels:
         app: vllm-llama2
     template:
       metadata:
         labels:
           app: vllm-llama2
       spec:
         containers:
           - name: vllm
             image: vllm/vllm-openai:v0.11.2
             args:
               - --model
               - meta-llama/Llama-2-7b-chat-hf
               - --tensor-parallel-size
               - "1"
               - --max-model-len
               - "4096"
               - --gpu-memory-utilization
               - "0.9"
               - --host
               - "0.0.0.0"
               - --port
               - "8000"
             ports:
               - containerPort: 8000
                 name: http
             env:
               - name: HF_TOKEN
                 valueFrom:
                   secretKeyRef:
                     name: hf-token
                     key: token
               - name: HF_HOME
                 value: /root/.cache/huggingface
             resources:
               limits:
                 nvidia.com/gpu: 1
               requests:
                 nvidia.com/gpu: 1
                 memory: 32Gi
                 cpu: "4"
             volumeMounts:
               - name: model-cache
                 mountPath: /root/.cache/huggingface
               - name: shm
                 mountPath: /dev/shm
             livenessProbe:
               httpGet:
                 path: /health
                 port: 8000
               initialDelaySeconds: 300
               periodSeconds: 30
               failureThreshold: 10
             readinessProbe:
               httpGet:
                 path: /health
                 port: 8000
               initialDelaySeconds: 60
               periodSeconds: 10
               failureThreshold: 30
         volumes:
           - name: model-cache
             persistentVolumeClaim:
               claimName: model-cache
           - name: shm
             emptyDir:
               medium: Memory
               sizeLimit: 16Gi
         tolerations:
           - key: nvidia.com/gpu
             operator: Exists
             effect: NoSchedule
   ```

2. **Apply Deployment**
   ```bash
   kubectl apply -f vllm-deployment.yaml

   # Watch deployment progress
   kubectl get pods -n vllm-inference -w

   # Check logs for model loading progress
   kubectl logs -f deployment/vllm-llama2 -n vllm-inference
   ```

3. **Expected Log Output**
   ```
   INFO:     Started server process [1]
   INFO:     Waiting for application startup.
   INFO:     Loading model meta-llama/Llama-2-7b-chat-hf...
   INFO:     Model loaded in 45.23 seconds.
   INFO:     Application startup complete.
   INFO:     Uvicorn running on http://0.0.0.0:8000
   ```

### Task 3: Create Service and Ingress (20 min)

1. **Create ClusterIP Service**
   ```yaml
   # Save as vllm-service.yaml
   apiVersion: v1
   kind: Service
   metadata:
     name: vllm-llama2
     namespace: vllm-inference
     labels:
       app: vllm-llama2
   spec:
     type: ClusterIP
     ports:
       - port: 8000
         targetPort: 8000
         protocol: TCP
         name: http
     selector:
       app: vllm-llama2
   ```

2. **Create Ingress (Optional)**
   ```yaml
   # Save as vllm-ingress.yaml
   apiVersion: networking.k8s.io/v1
   kind: Ingress
   metadata:
     name: vllm-llama2
     namespace: vllm-inference
     annotations:
       nginx.ingress.kubernetes.io/proxy-body-size: "100m"
       nginx.ingress.kubernetes.io/proxy-read-timeout: "600"
   spec:
     ingressClassName: nginx
     rules:
       - host: llama2.example.com
         http:
           paths:
             - path: /
               pathType: Prefix
               backend:
                 service:
                   name: vllm-llama2
                   port:
                     number: 8000
   ```

3. **Apply Service**
   ```bash
   kubectl apply -f vllm-service.yaml
   # kubectl apply -f vllm-ingress.yaml  # If using ingress
   ```

### Task 4: Test Inference Endpoint (30 min)

1. **Port Forward for Testing**
   ```bash
   kubectl port-forward svc/vllm-llama2 8000:8000 -n vllm-inference &
   ```

2. **Test Health Endpoint**
   ```bash
   curl -v http://localhost:8000/health
   # Expected: HTTP/1.1 200 OK with empty body (healthy)
   # HTTP 503 indicates engine not ready or unhealthy
   ```

3. **List Available Models**
   ```bash
   curl http://localhost:8000/v1/models | jq .

   # Expected response:
   # {
   #   "object": "list",
   #   "data": [
   #     {
   #       "id": "meta-llama/Llama-2-7b-chat-hf",
   #       "object": "model",
   #       ...
   #     }
   #   ]
   # }
   ```

4. **Test Chat Completion**
   ```bash
   curl http://localhost:8000/v1/chat/completions \
     -H "Content-Type: application/json" \
     -d '{
       "model": "meta-llama/Llama-2-7b-chat-hf",
       "messages": [
         {"role": "system", "content": "You are a helpful assistant."},
         {"role": "user", "content": "What is Kubernetes?"}
       ],
       "max_tokens": 200,
       "temperature": 0.7
     }' | jq .
   ```

5. **Test Streaming Response**
   ```bash
   curl http://localhost:8000/v1/chat/completions \
     -H "Content-Type: application/json" \
     -d '{
       "model": "meta-llama/Llama-2-7b-chat-hf",
       "messages": [
         {"role": "user", "content": "Write a haiku about containers"}
       ],
       "stream": true
     }'
   ```

6. **Benchmark with Multiple Requests**
   ```bash
   # Simple load test
   for i in {1..10}; do
     time curl -s http://localhost:8000/v1/chat/completions \
       -H "Content-Type: application/json" \
       -d '{
         "model": "meta-llama/Llama-2-7b-chat-hf",
         "messages": [{"role": "user", "content": "Hello!"}],
         "max_tokens": 50
       }' > /dev/null
   done
   ```

### Task 5: Monitor GPU Utilization (20 min)

1. **Watch GPU Usage**
   ```bash
   # In a separate terminal, exec into the pod
   kubectl exec -it deployment/vllm-llama2 -n vllm-inference -- nvidia-smi -l 1
   ```

2. **Check Memory Usage**
   ```bash
   kubectl exec -it deployment/vllm-llama2 -n vllm-inference -- nvidia-smi --query-gpu=memory.used,memory.total --format=csv
   ```

3. **View vLLM Metrics**
   ```bash
   curl http://localhost:8000/metrics

   # Key metrics to observe (V1 names, vLLM v0.11+):
   # - vllm:num_requests_running     — currently processing
   # - vllm:num_requests_waiting     — queued for processing
   # - vllm:kv_cache_usage_perc      — KV cache utilization (renamed from gpu_cache_usage_perc in V1)
   # - vllm:cpu_cache_usage_perc     — CPU offload cache usage
   ```

4. **Create Prometheus ServiceMonitor (Optional)**
   ```yaml
   apiVersion: monitoring.coreos.com/v1
   kind: ServiceMonitor
   metadata:
     name: vllm-llama2
     namespace: vllm-inference
   spec:
     selector:
       matchLabels:
         app: vllm-llama2
     endpoints:
       - port: http
         path: /metrics
         interval: 30s
   ```

### Task 6: Configure Horizontal Scaling (20 min)

1. **Create HPA (if multiple GPUs available)**
   ```yaml
   # Save as vllm-hpa.yaml
   apiVersion: autoscaling/v2
   kind: HorizontalPodAutoscaler
   metadata:
     name: vllm-llama2
     namespace: vllm-inference
   spec:
     scaleTargetRef:
       apiVersion: apps/v1
       kind: Deployment
       name: vllm-llama2
     minReplicas: 1
     maxReplicas: 4
     metrics:
       - type: Pods
         pods:
           metric:
             name: vllm_num_requests_waiting
           target:
             type: AverageValue
             averageValue: "10"
   ```

2. **Alternative: Manual Scaling**
   ```bash
   # Scale to 2 replicas (requires 2 GPUs)
   kubectl scale deployment vllm-llama2 --replicas=2 -n vllm-inference
   ```

---

## Advanced Tasks: Enterprise-Grade Optimizations

The following tasks require multi-GPU infrastructure (p4d.24xlarge/ND A100 v4 with 8 GPUs).

### Task 7: Tensor Parallelism Deep-Dive (45 min)

**Objective:** Deploy large models across multiple GPUs using tensor parallelism with NVLink optimization.

1. **Verify GPU Topology**

   Before configuring tensor parallelism, understand your GPU interconnect topology:

   ```bash
   # Check NVLink topology from a GPU pod
   kubectl exec -it deployment/vllm-llama2 -n vllm-inference -- nvidia-smi topo -m
   ```

   **Expected output for p4d.24xlarge (8x A100 with NVSwitch):**
   ```
           GPU0  GPU1  GPU2  GPU3  GPU4  GPU5  GPU6  GPU7
   GPU0     X    NV12  NV12  NV12  NV12  NV12  NV12  NV12
   GPU1    NV12   X    NV12  NV12  NV12  NV12  NV12  NV12
   GPU2    NV12  NV12   X    NV12  NV12  NV12  NV12  NV12
   ...
   Legend: NV# = NVLink connections, SYS = PCIe
   ```

   **Key insight:** `NV12` indicates 12 NVLink connections (full NVSwitch mesh). This enables efficient all-reduce operations for tensor parallelism.

2. **Check NVLink Bandwidth**
   ```bash
   kubectl exec -it deployment/vllm-llama2 -n vllm-inference -- nvidia-smi nvlink -s
   ```

3. **Deploy Llama-2-70B with Tensor Parallelism**

   ```yaml
   # Save as vllm-70b-tp8.yaml
   apiVersion: apps/v1
   kind: Deployment
   metadata:
     name: vllm-llama70b
     namespace: vllm-inference
   spec:
     replicas: 1
     selector:
       matchLabels:
         app: vllm-llama70b
     template:
       metadata:
         labels:
           app: vllm-llama70b
       spec:
         containers:
           - name: vllm
             image: vllm/vllm-openai:v0.11.2
             args:
               - --model
               - meta-llama/Llama-2-70b-chat-hf
               # Tensor parallelism across 8 GPUs
               - --tensor-parallel-size
               - "8"
               # vLLM auto-selects the distributed backend for tensor parallelism
               - --max-model-len
               - "4096"
               - --gpu-memory-utilization
               - "0.85"
               - --host
               - "0.0.0.0"
               - --port
               - "8000"
               # Enable prefix caching for repeated prompts
               - --enable-prefix-caching
             ports:
               - containerPort: 8000
             env:
               - name: HF_TOKEN
                 valueFrom:
                   secretKeyRef:
                     name: hf-token
                     key: token
               - name: HF_HOME
                 value: /root/.cache/huggingface
               # NCCL optimizations for NVLink
               - name: NCCL_DEBUG
                 value: "INFO"
               - name: NCCL_P2P_LEVEL
                 value: "NVL"  # Use NVLink for P2P
               - name: CUDA_DEVICE_MAX_CONNECTIONS
                 value: "12"
             resources:
               limits:
                 nvidia.com/gpu: 8
               requests:
                 nvidia.com/gpu: 8
                 memory: 256Gi
                 cpu: "32"
             volumeMounts:
               - name: model-cache
                 mountPath: /root/.cache/huggingface
               - name: shm
                 mountPath: /dev/shm
         volumes:
           - name: model-cache
             persistentVolumeClaim:
               claimName: model-cache
           - name: shm
             emptyDir:
               medium: Memory
               sizeLimit: 64Gi
         tolerations:
           - key: nvidia.com/gpu
             operator: Exists
             effect: NoSchedule
   ---
   apiVersion: v1
   kind: Service
   metadata:
     name: vllm-llama70b
     namespace: vllm-inference
   spec:
     selector:
       app: vllm-llama70b
     ports:
       - port: 8000
         targetPort: 8000
   ```

4. **Deploy and Verify**
   ```bash
   kubectl apply -f vllm-70b-tp8.yaml

   # Watch startup - model loading takes 3-5 minutes
   kubectl logs -f deployment/vllm-llama70b -n vllm-inference

   # Look for successful initialization:
   # "INFO: Initializing distributed environment with tensor parallelism size 8"
   # "INFO: Model meta-llama/Llama-2-70b-chat-hf loaded successfully"
   ```

5. **Monitor GPU Utilization Across All GPUs**
   ```bash
   # Watch all 8 GPUs
   kubectl exec -it deployment/vllm-llama70b -n vllm-inference -- \
     nvidia-smi --query-gpu=index,memory.used,memory.total,utilization.gpu \
     --format=csv -l 2
   ```

   **Expected:** `nvidia-smi` will show ~55-68 GB used per GPU. vLLM pre-allocates memory at startup for KV cache blocks based on `--gpu-memory-utilization` (0.85 × 80 GB = ~68 GB on A100-80GB). The 70B model weights contribute ~17.5 GB per GPU (140 GB / 8 GPUs), with the remainder reserved for KV cache and NCCL communication buffers.

6. **Benchmark Tensor Parallelism Performance**
   ```bash
   # Port forward
   kubectl port-forward svc/vllm-llama70b 8001:8000 -n vllm-inference &

   # Run inference benchmark
   python -c "
   import requests
   import time

   url = 'http://localhost:8001/v1/chat/completions'
   headers = {'Content-Type': 'application/json'}

   # Test different batch sizes
   for batch in [1, 4, 8, 16]:
       start = time.time()
       for _ in range(batch):
           resp = requests.post(url, headers=headers, json={
               'model': 'meta-llama/Llama-2-70b-chat-hf',
               'messages': [{'role': 'user', 'content': 'Hello, how are you?'}],
               'max_tokens': 100
           })
       elapsed = time.time() - start
       print(f'Batch {batch}: {elapsed:.2f}s total, {elapsed/batch:.2f}s per request')
   "
   ```

### Task 8: Quantization Strategies (45 min)

**Objective:** Deploy quantized models to reduce memory usage and increase throughput.

1. **Understanding Quantization Trade-offs**

   | Method | Memory Reduction | Speed Gain | Quality Impact | GPU Requirements |
   |--------|-----------------|------------|----------------|------------------|
   | FP8 (W8A8) | 2x | 1.5-2x | <1% perplexity | H100+ native; A100 W8A16 only |
   | INT8 SQ | 2x | 1.3-1.5x | 1-2% perplexity | Any |
   | AWQ INT4 | 4x | 2-3x | 2-5% perplexity | Any |

2. **Deploy FP8 Quantized Model (H100 recommended; A100 W8A16 only)**

   FP8 W8A8 uses native Tensor Core support on H100+ (Hopper/Ada Lovelace) for minimal quality loss. On A100, vLLM falls back to weight-only FP8 (W8A16) via Marlin kernels — this provides memory savings but not the full throughput benefit of native FP8 compute:

   ```yaml
   # Save as vllm-fp8.yaml
   apiVersion: apps/v1
   kind: Deployment
   metadata:
     name: vllm-llama70b-fp8
     namespace: vllm-inference
   spec:
     replicas: 1
     selector:
       matchLabels:
         app: vllm-llama70b-fp8
     template:
       metadata:
         labels:
           app: vllm-llama70b-fp8
       spec:
         containers:
           - name: vllm
             image: vllm/vllm-openai:v0.11.2
             args:
               - --model
               - meta-llama/Llama-2-70b-chat-hf
               - --tensor-parallel-size
               - "4"  # FP8 reduces memory, so fewer GPUs needed
               - --quantization
               - "fp8"  # Enable FP8 quantization
               - --kv-cache-dtype
               - "fp8"  # Also quantize KV cache
               - --max-model-len
               - "8192"  # Can use longer context with FP8
               - --gpu-memory-utilization
               - "0.9"
             resources:
               limits:
                 nvidia.com/gpu: 4
               requests:
                 nvidia.com/gpu: 4
                 memory: 128Gi
             # ... (rest of container spec same as above)
         # ... (volumes, tolerations same as above)
   ```

3. **Deploy AWQ INT4 Quantized Model**

   AWQ provides 4x memory reduction with reasonable quality:

   ```yaml
   # Save as vllm-awq.yaml
   apiVersion: apps/v1
   kind: Deployment
   metadata:
     name: vllm-llama70b-awq
     namespace: vllm-inference
   spec:
     replicas: 1
     selector:
       matchLabels:
         app: vllm-llama70b-awq
     template:
       metadata:
         labels:
           app: vllm-llama70b-awq
       spec:
         containers:
           - name: vllm
             image: vllm/vllm-openai:v0.11.2
             args:
               - --model
               # Use pre-quantized AWQ model from HuggingFace
               # Note: TheBloke community quantizations are legacy (last updated Jan 2024).
               # For newer models, look for official quantized variants or use vLLM's
               # built-in quantization with --quantization awq on the original model.
               - TheBloke/Llama-2-70B-Chat-AWQ
               - --tensor-parallel-size
               - "2"  # AWQ needs even fewer GPUs
               - --quantization
               - "awq"
               - --max-model-len
               - "4096"
               - --gpu-memory-utilization
               - "0.9"
             resources:
               limits:
                 nvidia.com/gpu: 2
               requests:
                 nvidia.com/gpu: 2
                 memory: 64Gi
             # ... (rest of container spec)
   ```

4. **Compare Quantization Methods**

   Deploy all three configurations and set up port-forwards for each:

   ```bash
   # Set up port-forwards for each deployment (run each in background)
   kubectl port-forward svc/vllm-llama70b 8001:8000 -n vllm-inference &
   kubectl port-forward svc/vllm-fp8 8002:8000 -n vllm-inference &
   kubectl port-forward svc/vllm-awq 8003:8000 -n vllm-inference &
   ```

   Then run the comparison benchmark:

   ```bash
   python -c "
   import requests
   import time

   configs = [
       ('FP16 (TP=8)', 'http://localhost:8001/v1/chat/completions', 'meta-llama/Llama-2-70b-chat-hf'),
       ('FP8 (TP=4)', 'http://localhost:8002/v1/chat/completions', 'meta-llama/Llama-2-70b-chat-hf'),
       ('AWQ (TP=2)', 'http://localhost:8003/v1/chat/completions', 'TheBloke/Llama-2-70B-Chat-AWQ'),
   ]

   prompt = 'Explain the concept of quantization in neural networks in 3 sentences.'

   for name, url, model in configs:
       try:
           start = time.time()
           resp = requests.post(url, json={
               'model': model,
               'messages': [{'role': 'user', 'content': prompt}],
               'max_tokens': 200
           }, timeout=60)
           elapsed = time.time() - start
           tokens = resp.json()['usage']['completion_tokens']
           print(f'{name}: {elapsed:.2f}s, {tokens/elapsed:.1f} tok/s')
       except Exception as e:
           print(f'{name}: Error - {e}')
   "
   ```

   **Expected results (approximate):**
   ```
   FP16 (TP=8): 4.5s, 44 tok/s
   FP8 (TP=4):  3.2s, 62 tok/s   # ~40% faster
   AWQ (TP=2):  2.8s, 71 tok/s   # ~60% faster
   ```

5. **KV Cache Quantization**

   Even without model quantization, KV cache quantization can double batch size:

   ```yaml
   args:
     - --model
     - meta-llama/Llama-2-70b-chat-hf
     - --tensor-parallel-size
     - "8"
     # Keep model in FP16 but quantize KV cache
     - --kv-cache-dtype
     - "fp8"  # Also available: fp8_e4m3, fp8_e5m2 (int8 is NOT supported for KV cache)
   ```

   **Impact:** KV cache memory reduced by 50%, enabling larger batches or longer contexts.

### Task 9: Performance Benchmarking (30 min)

**Objective:** Establish baseline metrics for production planning.

1. **Run vLLM Built-in Benchmark**

   vLLM v0.11+ includes a built-in benchmarking CLI (the legacy `benchmark_serving.py` script is deprecated):

   ```bash
   # Install vLLM CLI if not already available
   pip install vllm

   # Check available benchmark flags (CLI evolves between versions)
   vllm bench serve --help

   # Run serving benchmark against the running vLLM server
   vllm bench serve \
     --backend openai-chat \
     --model meta-llama/Llama-2-70b-chat-hf \
     --base-url http://localhost:8001 \
     --endpoint /v1/chat/completions \
     --num-prompts 100 \
     --dataset-name random \
     --random-output-len 256
   ```

   > **Note:** The benchmark CLI flags may differ between vLLM releases. Always run `vllm bench serve --help` first to verify the exact flags available in your installed version.

2. **Key Metrics to Capture**

   | Metric | Definition | Target |
   |--------|------------|--------|
   | **TTFT** | Time to first token | <500ms |
   | **TPOT** | Time per output token | <50ms |
   | **Throughput** | Tokens/second | >1000 tok/s |
   | **GPU Utilization** | Compute utilization | >80% |

3. **Document Results**

   Create a performance report:

   ```markdown
   ## Performance Benchmark Results

   **Configuration:**
   - Model: Llama-2-70B
   - Quantization: [FP16/FP8/AWQ]
   - Tensor Parallelism: [1/2/4/8]
   - GPUs: [count] x [type]

   **Results:**
   | Metric | Value |
   |--------|-------|
   | TTFT (p50) | XXX ms |
   | TTFT (p99) | XXX ms |
   | Throughput | XXX tok/s |
   | GPU Memory | XXX GB |
   | GPU Util | XX% |
   ```

## k0rdent Enterprise Integration

In a k0rdent-managed environment, inference workloads benefit from the Service Catalog model. While the tasks above deploy vLLM as raw Kubernetes manifests (valuable for understanding the mechanics), production deployments use k0rdent's **KServe** ServiceTemplate for managed inference.

### KServe via k0rdent Service Catalog

The k0rdent catalog includes [KServe v0.15.0](https://catalog.k0rdent.io/latest/apps/kserve/), which natively supports vLLM as a serving runtime. Deploy it to your GPU cluster via MultiClusterService:

```yaml
apiVersion: k0rdent.mirantis.com/v1beta1
kind: MultiClusterService
metadata:
  name: inference-platform
  namespace: kcm-system
spec:
  clusterSelector:
    matchLabels:
      workload-type: inference
  serviceSpec:
    services:
      # KServe CRDs (install first)
      - template: kserve-crd-0-15-0
        name: kserve-crd
        namespace: kserve
      # KServe controller
      - template: kserve-0-15-0
        name: kserve
        namespace: kserve
        values: |
          kserve:
            controller:
              deploymentMode: RawDeployment
      # cert-manager dependency
      - template: cert-manager-1-18-2
        name: cert-manager
        namespace: cert-manager
```

### vLLM as KServe InferenceService

Once KServe is deployed, vLLM runs as a **ServingRuntime** + **InferenceService**, gaining autoscaling, canary deployments, and standardized APIs:

```yaml
apiVersion: serving.kserve.io/v1alpha1
kind: ServingRuntime
metadata:
  name: vllm-runtime
  namespace: vllm-inference
spec:
  supportedModelFormats:
    - name: vllm
      version: "1"
      autoSelect: true
  containers:
    - name: kserve-container
      image: vllm/vllm-openai:v0.11.2
      args:
        - --port
        - "8080"
        - --gpu-memory-utilization
        - "0.9"
      ports:
        - containerPort: 8080
          name: http
          protocol: TCP
      env:
        - name: HF_TOKEN
          valueFrom:
            secretKeyRef:
              name: hf-token
              key: token
        - name: HF_HOME
          value: /root/.cache/huggingface
      resources:
        limits:
          nvidia.com/gpu: 1
      livenessProbe:
        httpGet:
          path: /health
          port: 8080
        initialDelaySeconds: 300
        periodSeconds: 30
        failureThreshold: 10
      readinessProbe:
        httpGet:
          path: /health
          port: 8080
        initialDelaySeconds: 60
        periodSeconds: 10
        failureThreshold: 30
---
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: llama2-7b
  namespace: vllm-inference
spec:
  predictor:
    model:
      modelFormat:
        name: vllm
      runtime: vllm-runtime
      storageUri: "hf://meta-llama/Llama-2-7b-chat-hf"
      resources:
        limits:
          nvidia.com/gpu: 1
```

### Additional Catalog Resources for Inference

| ServiceTemplate | Version | Purpose |
|----------------|---------|---------|
| `lws` (LeaderWorkerSet) | 0.7.0 | Multi-node distributed inference (pipeline parallelism across nodes) |
| `kuberay` | 1.3.2 | Ray Serve + vLLM backend for advanced serving patterns |
| `ollama` | 1.40.0 | Simpler LLM inference (good for development/testing) |
| `nvidia` (GPU Operator) | 25.10.0 | GPU enablement (required — see [Lab Setup README](README.md)) |

> **Note:** There is no standalone `vllm` ServiceTemplate in the k0rdent catalog. The recommended production path is KServe + vLLM ServingRuntime. For direct vLLM deployment, use the raw Kubernetes manifests from this lab or create a [BYO ServiceTemplate](https://docs.k0rdent.io/latest/reference/template/template-byo/).

---

## Deliverables

### Basic Tasks (Required)
- [ ] **Screenshot** of successful chat completion response
- [ ] **GPU utilization screenshot** during inference
- [ ] **Metrics output** from `/metrics` endpoint
- [ ] **Deployment YAML** with your configuration notes
- [ ] **Performance results** from benchmark test

### Advanced Tasks (Multi-GPU Infrastructure)
- [ ] **NVLink topology output** from `nvidia-smi topo -m`
- [ ] **70B model deployment** with tensor parallelism working
- [ ] **Quantization comparison table** showing FP16 vs FP8 vs AWQ performance
- [ ] **Performance benchmark report** with TTFT, throughput, and GPU utilization
- [ ] **Recommendation document** for production deployment configuration

## Verification Checklist

### Basic
- [ ] vLLM pod running and healthy
- [ ] Model loaded successfully
- [ ] Health endpoint responding
- [ ] Chat completions working
- [ ] Streaming responses working
- [ ] GPU utilization visible
- [ ] Metrics endpoint accessible

### Advanced
- [ ] NVLink topology verified (NV# in topo output)
- [ ] Tensor parallelism functioning across multiple GPUs
- [ ] NCCL using NVLink (check NCCL_DEBUG output)
- [ ] Quantized model deployed and responding
- [ ] Performance benchmarks documented

## Troubleshooting

### Pod Stuck in Pending

**Check GPU availability:**
```bash
kubectl describe nodes | grep -A5 "Allocatable:"
kubectl get pods -n vllm-inference -o wide
```

**Check events:**
```bash
kubectl describe pod -l app=vllm-llama2 -n vllm-inference
```

### Model Loading Fails

**Check Hugging Face token:**
```bash
kubectl logs deployment/vllm-llama2 -n vllm-inference | grep -i error
```

**Common errors:**
- "401 Unauthorized" - Token invalid or missing
- "403 Forbidden" - Need to accept model license on HF
- "Out of memory" - Reduce `--gpu-memory-utilization` or use smaller model

### OOM (Out of Memory)

**Reduce memory usage:**
```bash
# In deployment args:
- --gpu-memory-utilization
- "0.8"  # Reduce from 0.9
- --max-model-len
- "2048"  # Reduce context length
```

### Slow Inference

**Check if model is on GPU:**
```bash
kubectl exec deployment/vllm-llama2 -n vllm-inference -- nvidia-smi
# GPU utilization should spike during inference
```

**Verify tensor parallelism:**
```bash
# For multi-GPU setup, increase tensor-parallel-size
- --tensor-parallel-size
- "2"  # Use 2 GPUs
```

## Key Takeaways

### Basic Concepts
1. **vLLM provides OpenAI-compatible API** making integration easy
2. **Model caching with PVC** speeds up subsequent deployments
3. **GPU memory utilization** should be tuned based on model size
4. **Shared memory (shm)** is required for efficient tensor operations
5. **Health/readiness probes** must account for model loading time
6. **Always pin vLLM versions** in production (current: v0.11.2)
7. **vLLM V1 architecture** (v0.11+) provides significant performance improvements

### Advanced Concepts
8. **Tensor parallelism** splits layers across GPUs, requiring NVLink for efficient all-reduce
9. **Pipeline parallelism** splits layers sequentially, useful for cross-node deployment
10. **NVLink bandwidth** (600-900 GB/s) is critical for tensor parallelism performance - PCIe (64 GB/s) creates severe bottlenecks
11. **FP8 quantization** provides best quality/performance trade-off — native W8A8 on H100+, weight-only W8A16 on A100 via Marlin kernels
12. **AWQ INT4** enables 4x memory reduction with acceptable quality loss
13. **KV cache quantization** can double batch size without model quantization
14. **NCCL environment variables** (NCCL_P2P_LEVEL=NVL) ensure NVLink utilization

### Production Recommendations
| Model Size | Recommended Config | GPUs Needed |
|------------|-------------------|-------------|
| 7B | Single GPU, FP16 | 1x A100-40GB |
| 13B | Single GPU, FP16 or FP8 | 1x A100-80GB |
| 70B | TP=4 with FP8, or TP=2 with AWQ | 2-4x A100 |
| 70B (best quality) | TP=8 with FP16 | 8x A100 |

---

## References

### Official Documentation
- [vLLM Documentation](https://docs.vllm.ai/)
- [vLLM Parallelism and Scaling](https://docs.vllm.ai/en/latest/serving/parallelism_scaling/)
- [vLLM Quantization](https://docs.vllm.ai/en/latest/quantization/)
- [vLLM FP8 Quantization](https://docs.vllm.ai/en/latest/features/quantization/fp8/) — W8A8 (H100+) vs W8A16 (A100) explained
- [vLLM KServe Integration](https://docs.vllm.ai/en/latest/deployment/integrations/kserve/)
- [vLLM Benchmarking CLI](https://docs.vllm.ai/en/latest/cli/bench/serve/)
- [NVIDIA GPU Operator](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/)

### k0rdent Enterprise
- [k0rdent Service Catalog](https://catalog.k0rdent.io/)
- [KServe in k0rdent Catalog](https://catalog.k0rdent.io/latest/apps/kserve/)
- [k0rdent Documentation - Services](https://docs.k0rdent.io/latest/user/services/)
- [k0rdent Documentation - BYO Templates](https://docs.k0rdent.io/latest/reference/template/template-byo/)

### NVLink and NCCL
- [NVIDIA NVLink Technology](https://www.nvidia.com/en-us/data-center/nvlink/)
- [NCCL Documentation](https://docs.nvidia.com/deeplearning/nccl/user-guide/docs/)

### Quantization Research
- [AWQ: Activation-aware Weight Quantization (MIT-HAN-Lab)](https://arxiv.org/abs/2306.00978)
- [GPTQ: Accurate Post-Training Quantization](https://arxiv.org/abs/2210.17323)
- [FP8 Formats for Deep Learning (NVIDIA)](https://arxiv.org/abs/2209.05433)

---

## Next Lab

Proceed to [Lab 5.6 - Troubleshooting GPU Scheduling](lab-5.6-troubleshooting-gpu.md)
