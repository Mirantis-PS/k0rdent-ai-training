# Lab 5.13 - TensorRT-LLM Inference Optimization

---

## Lab Navigation

| Track | Tier | Duration |
|-------|------|----------|
| Advanced Optimization | Optional | 3.5 hours |

### Week 5 Learning Paths

```
FOUNDATION (Completed)                        ADVANCED OPTIMIZATION
━━━━━━━━━━━━━━━━━━━━━━                       ━━━━━━━━━━━━━━━━━━━━
5.1 ➔ 5.2 ➔ 5.3 ➔ 5.4 ➔ 5.5               YOU ARE HERE
     ➔ 5.6 ➔ 5.7 ➔ 5.8 ✓                        ↓
                                             [5.13] TensorRT-LLM
                                                  ↓
                                              5.14 Slurm
                                                  ↓
                                              5.15 Multi-Cloud RDMA
                                                  ↓
                                              5.16 Distributed Training
```

| Previous | Current | Next |
|----------|---------|------|
| [Lab 5.8 - Vector Database](lab-5.8-vector-database.md) | **Lab 5.13 - TensorRT-LLM** | [Lab 5.14 - Slurm on Kubernetes](lab-5.14-slurm-operator-hpc.md) |

---

## Table of Contents

- [Objective](#objective)
- [Prerequisites](#prerequisites)
- [k0rdent Context](#k0rdent-context)
- [Background: TensorRT-LLM Architecture](#background-tensorrt-llm-architecture)
- [Tasks](#tasks)
  - [Task 1: Access the k0rdent-Managed GPU Cluster](#task-1-access-the-k0rdent-managed-gpu-cluster-10-min)
  - [Task 2: Set Up TensorRT-LLM Environment](#task-2-set-up-tensorrt-llm-environment-25-min)
  - [Task 3: Download and Quantize Model](#task-3-download-and-quantize-model-45-min)
  - [Task 4: Build TensorRT Engine](#task-4-build-tensorrt-engine-45-min)
  - [Task 5: Quick Test with trtllm-serve](#task-5-quick-test-with-trtllm-serve-15-min)
  - [Task 6: Production Deployment with Triton Ensemble](#task-6-production-deployment-with-triton-ensemble-60-min)
  - [Task 7: Test Triton Inference](#task-7-test-triton-inference-20-min)
  - [Task 8: Performance Benchmarking](#task-8-performance-benchmarking-30-min)
- [Cleanup](#cleanup)
- [Deliverables](#deliverables)

---

**Duration:** 3.5 hours
**Type:** Hands-on Technical (Advanced)
**Environment:** GPU Lab (H100 recommended, A100 supported)

## Objective

Deploy and optimize LLM inference using NVIDIA TensorRT-LLM on a k0rdent-managed GPU cluster, demonstrating quantization techniques (INT4 AWQ, FP8, INT8 SmoothQuant), engine builds, Triton Inference Server integration with the ensemble model architecture, and the OpenAI-compatible serving API.

## Prerequisites

- Completed Lab 5.5 (vLLM Inference Service)
- k0rdent Enterprise management cluster operational
- At least one k0rdent-managed GPU cluster (A100 40GB+ minimum)
- NVIDIA GPU Operator **v25.10.0** installed — deliberately newer than the week's default v25.3.0 pin: the Triton `25.06-trtllm` container requires NVIDIA driver **≥575**, and v25.3.0 installs 570.124 while v25.10.0 installs 580.95 (validated on A10G). On k0s clusters v25.10.0 needs the containerd `runc` fix from the Lab 5.1 known-issue box (see also Troubleshooting below) before GPUs become allocatable. Alternatively, stay on v25.3.0 and override `driver.version` to a ≥575 driver image (untested)
- Basic understanding of model quantization from Lab 5.5

## k0rdent Context

### TensorRT-LLM in the k0rdent Ecosystem

The k0rdent catalog does **not** include a TensorRT-LLM or Triton ServiceTemplate. TensorRT-LLM is deployed manually on k0rdent-managed workload clusters. For production LLM serving with k0rdent catalog integration, the recommended path is KServe + vLLM (see Lab 5.5).

```
┌─────────────────────────────────────────────────────────────────────┐
│                   k0rdent Management Cluster                        │
│                                                                     │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐  │
│  │  ServiceTemplate │  │ ClusterDeployment│  │ Alternative:     │  │
│  │  gpu-operator-   │  │ (GPU clusters)   │  │ kserve-v0-15-0   │  │
│  │  25-10-0         │  │                  │  │ (catalog path)   │  │
│  └────────┬─────────┘  └────────┬─────────┘  └──────────────────┘  │
│           │                     │                                   │
│           └─────────────────────┘                                   │
│                     │ Sveltos                                       │
│                     ▼                                               │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │              Workload Cluster (GPU)                           │   │
│  │                                                              │   │
│  │  GPU Operator (via catalog)     TensorRT-LLM (manual)       │   │
│  │  ┌──────────────────┐          ┌──────────────────────┐     │   │
│  │  │ NVIDIA Drivers   │          │ Builder Pod          │     │   │
│  │  │ Device Plugin    │          │ (quantize + build)   │     │   │
│  │  │ Container Toolkit│          ├──────────────────────┤     │   │
│  │  └──────────────────┘          │ Triton Server        │     │   │
│  │                                │ (serve engines)      │     │   │
│  │                                └──────────────────────┘     │   │
│  └──────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
```

### When to Use TensorRT-LLM vs vLLM (via KServe)

| Scenario | Recommendation | k0rdent Path |
|----------|---------------|--------------|
| Rapid prototyping | vLLM | KServe ServiceTemplate from catalog |
| Frequent model updates | vLLM | KServe + ServingRuntime |
| Maximum inference throughput | TensorRT-LLM | Manual deploy on workload cluster |
| Fixed model, high traffic | TensorRT-LLM | Manual deploy + custom ServiceTemplate |
| Memory-constrained GPUs | TensorRT-LLM (INT4) | Manual deploy on workload cluster |
| FP8 quality-optimized (H100+) | TensorRT-LLM | Manual deploy on workload cluster |

## Background: TensorRT-LLM Architecture

### What is TensorRT-LLM?

TensorRT-LLM is NVIDIA's high-performance inference framework specifically optimized for large language models. Unlike vLLM which uses PyTorch, TensorRT-LLM compiles models into optimized CUDA kernels for maximum throughput.

```
┌─────────────────────────────────────────────────────────────────┐
│                    TensorRT-LLM Pipeline                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  HuggingFace Model    Quantization       TRT Engine    Serving  │
│  ┌─────────────┐     ┌───────────┐     ┌───────────┐  ┌──────┐ │
│  │ Llama-7B    │ --> │ INT4/INT8 │ --> │ .engine   │->│Triton│ │
│  │ (FP16)      │     │ FP8       │     │ file      │  │Server│ │
│  └─────────────┘     └───────────┘     └───────────┘  └──────┘ │
│       ~14GB              ~4-7GB          Optimized     Runtime  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Quantization Formats

| Format | Bits | Memory Savings | Speed Gain | Quality Impact | GPU Requirement |
|--------|------|---------------|------------|----------------|-----------------|
| FP16 (baseline) | 16 | 1x | 1x | None | Any NVIDIA GPU |
| INT8 SmoothQuant | 8 | ~2x | 1.5-2x | Low (<1%) | Ampere+ (A100, H100) |
| FP8 | 8 | ~2x | 2-2.5x | Minimal (<0.5%) | **Ada (SM89), Hopper and newer supported GPUs** |
| INT4 AWQ | 4 | ~4x | 2-3x | Low (1-3%) | Ampere+ (A100, H100) |
| INT4 GPTQ | 4 | ~4x | 2-3x | Low (1-3%) | Ampere+ (A100, H100) |

> **Important:** FP8 hardware is available on Ada (CC 8.9), Hopper (H100/H200), and newer supported architectures. A100 (Ampere, CC 8.0) does **not** have native FP8 hardware support.

---

## Lab Environment

**Cluster Requirements:**
- 1+ GPU nodes with NVIDIA A100 (40GB) or H100 for the full lab; a single 24GB Ampere GPU (e.g. AWS **g5.4xlarge**, 1× A10G) is sufficient for the 7B INT4-AWQ path validated here
- A default StorageClass for dynamic EBS provisioning. On k0rdent AWS clusters (`aws-standalone-cp`) this is **`ebs-csi-default-sc`** (the AWS EBS CSI driver's default), **not** `ebs-gp3`. Confirm with `kubectl get storageclass` and substitute the real name in the PVC below
- 200GB+ worker root volume for the ~21GB Triton image plus checkpoints and engines
- NVIDIA GPU Operator installed via k0rdent catalog
- Network access to NVIDIA NGC and HuggingFace. Both the `nvcr.io/nvidia/tritonserver` image and the `NousResearch/Llama-2-7b-chat-hf` model used here are **public** — no NGC login and no HuggingFace token are required

**Key Insight:** TensorRT-LLM engines are GPU-architecture specific. An engine built for A100 will NOT work on H100 and vice versa. Always build on the same GPU type you intend to serve on.

---

## Tasks

### Task 1: Access the k0rdent-Managed GPU Cluster (10 min)

1. **Identify your GPU cluster**
   ```bash
   # On the management cluster
   kubectl get clusterdeployments -n kcm-system
   ```

2. **Extract the workload cluster kubeconfig**
   ```bash
   export CLUSTER_NAME=gpu-cluster
   kubectl get secret ${CLUSTER_NAME}-kubeconfig \
     -n kcm-system \
     -o jsonpath='{.data.value}' | base64 -d > /tmp/${CLUSTER_NAME}.kubeconfig
   export KUBECONFIG=/tmp/${CLUSTER_NAME}.kubeconfig
   ```

3. **Verify GPU availability**
   ```bash
   kubectl get nodes -l nvidia.com/gpu.present=true
   kubectl get pods -n gpu-operator -l app=nvidia-device-plugin-daemonset

   # Check GPU type (important: engines are architecture-specific)
   kubectl get nodes -l nvidia.com/gpu.present=true \
     -o jsonpath='{.items[*].metadata.labels.nvidia\.com/gpu\.product}'
   ```

### Task 2: Set Up TensorRT-LLM Environment (25 min)

1. **Create namespace and storage**
   ```bash
   kubectl create namespace trt-llm
   ```

   ```yaml
   # Save as trt-llm-storage.yaml
   apiVersion: v1
   kind: PersistentVolumeClaim
   metadata:
     name: trt-llm-storage
     namespace: trt-llm
   spec:
     accessModes:
       - ReadWriteOnce
     storageClassName: ebs-csi-default-sc  # k0rdent AWS default; run `kubectl get storageclass` to confirm
     resources:
       requests:
         storage: 200Gi  # ample for a single 7B model + INT4 checkpoint + engine (a single 7B needs well under 100Gi; raise for larger models)
   ```

   > **StorageClass name:** k0rdent's `aws-standalone-cp` clusters ship the AWS EBS CSI driver with a default StorageClass named `ebs-csi-default-sc`, not `ebs-gp3`. Using a non-existent class leaves the PVC `Pending` forever. `kubectl get storageclass` shows the real name; the default is marked `(default)`.

   ```bash
   kubectl apply -f trt-llm-storage.yaml
   ```

2. **Create HuggingFace token Secret** (optional for this lab)
   ```bash
   kubectl create secret generic hf-token \
     --from-literal=token=<your-hf-token> \
     -n trt-llm
   ```

   > **Token not required for the model used here.** `NousResearch/Llama-2-7b-chat-hf` is an ungated public mirror, so the download in Task 3 works with no token. The `builder` pod still references this Secret via `secretKeyRef`, so create it with any placeholder value (e.g. `--from-literal=token=none`) to satisfy the pod spec, and omit `--token` from the `huggingface-cli download` call. A real token is only needed if you swap in a gated model (e.g. `meta-llama/*`).

3. **Deploy TensorRT-LLM builder pod**

   The Triton TRT-LLM image includes both the build tools and the serving runtime. Use the same image for building and serving to avoid version mismatches.

   ```yaml
   # Save as trt-llm-builder.yaml
   apiVersion: v1
   kind: Pod
   metadata:
     name: trt-llm-builder
     namespace: trt-llm
   spec:
     containers:
       - name: builder
         image: nvcr.io/nvidia/tritonserver:25.06-trtllm-python-py3
         command: ["sleep", "infinity"]
         env:
           - name: HF_TOKEN
             valueFrom:
               secretKeyRef:
                 name: hf-token
                 key: token
         resources:
           limits:
             nvidia.com/gpu: 1
           requests:
             nvidia.com/gpu: 1
             memory: 64Gi
             cpu: "16"
         volumeMounts:
           - name: storage
             mountPath: /workspace
           - name: shm
             mountPath: /dev/shm
     volumes:
       - name: storage
         persistentVolumeClaim:
           claimName: trt-llm-storage
       - name: shm
         emptyDir:
           medium: Memory
           sizeLimit: 32Gi
     tolerations:
       - key: nvidia.com/gpu
         operator: Exists
         effect: NoSchedule
   ```

   ```bash
   kubectl apply -f trt-llm-builder.yaml
   kubectl wait --for=condition=Ready pod/trt-llm-builder -n trt-llm --timeout=600s
   ```

### Task 3: Download and Quantize Model (45 min)

1. **Access the builder pod**
   ```bash
   kubectl exec -it trt-llm-builder -n trt-llm -- bash
   ```

2. **Download model from HuggingFace**
   ```bash
   cd /workspace

   # Clone TensorRT-LLM examples for quantization scripts.
   # Pin to v0.20.0 to match the TensorRT-LLM runtime bundled in the
   # tritonserver 25.06 container (Triton 25.06 = TensorRT-LLM release/0.20.0).
   # Cloning the default branch pulls example/template code that may not match
   # the installed runtime or the engine format.
   git clone --branch v0.20.0 https://github.com/NVIDIA/TensorRT-LLM.git
   cd TensorRT-LLM/examples

   # Download Llama-2-7B (use Llama-2-7b-chat-hf for a chat model).
   # NousResearch/Llama-2-7b-chat-hf is ungated, so no --token is needed.
   # (Add `--token $HF_TOKEN` only when pulling a gated repo.)
   huggingface-cli download NousResearch/Llama-2-7b-chat-hf \
     --local-dir /workspace/models/llama-2-7b-chat-hf

   echo "Model downloaded: $(du -sh /workspace/models/llama-2-7b-chat-hf)"
   ```

   > **`python` vs `python3`:** the `tritonserver:25.06-trtllm-python-py3` image ships `python3` but has **no `python` symlink**. Use `python3` for every script below (`quantize.py`, `fill_template.py`, the client scripts) — a bare `python` fails with `No such file or directory`.

3. **Quantize with INT4 AWQ**

   INT4 AWQ provides ~4x memory reduction with minimal quality loss. AWQ requires a small calibration dataset (lightweight, no backpropagation).

   ```bash
   python3 quantization/quantize.py \
     --model_dir /workspace/models/llama-2-7b-chat-hf \
     --output_dir /workspace/checkpoints/llama-2-7b-int4-awq \
     --dtype float16 \
     --qformat int4_awq \
     --awq_block_size 128 \
     --calib_size 32
   ```

   > On a 24GB A10G this produces `rank0.safetensors` (~4GB, down from ~13.5GB FP16) in a few minutes; peak VRAM stays well under 24GB. **Note:** `quantize.py` sometimes does not exit its process cleanly after the checkpoint is written (a ModelOpt quirk) — once `config.json` and `rank0.safetensors` exist in the output dir, the checkpoint is complete and you can `Ctrl-C` / proceed.

   **Understanding the parameters:**
   - `--qformat int4_awq`: 4-bit AWQ quantization
   - `--awq_block_size 128`: Granularity of quantization (smaller = better quality, larger = faster)
   - `--calib_size 32`: Number of calibration samples (AWQ uses lightweight calibration)

4. **Alternative: FP8 Quantization (H100/H200 only)**

   FP8 provides the best quality-to-compression ratio but requires supported Ada/Hopper-or-newer FP8 hardware and a compatible TensorRT-LLM model/backend.

   ```bash
   # ONLY run this on H100/H200 nodes
   python3 quantization/quantize.py \
     --model_dir /workspace/models/llama-2-7b-chat-hf \
     --output_dir /workspace/checkpoints/llama-2-7b-fp8 \
     --dtype float16 \
     --qformat fp8 \
     --kv_cache_dtype fp8
   ```

   > **Warning:** Running FP8 quantization on A100 will produce a checkpoint, but the resulting engine will not benefit from FP8 hardware acceleration since A100 lacks native FP8 compute units.

5. **Alternative: INT8 SmoothQuant**

   INT8 SmoothQuant works on both A100 and H100, providing ~2x memory reduction with broad compatibility.

   ```bash
   python3 quantization/quantize.py \
     --model_dir /workspace/models/llama-2-7b-chat-hf \
     --output_dir /workspace/checkpoints/llama-2-7b-int8-sq \
     --dtype float16 \
     --qformat int8_sq
   ```

### Task 4: Build TensorRT Engine (45 min)

The `trtllm-build` command compiles the quantized checkpoint into an optimized engine for your specific GPU architecture.

1. **Build engine from INT4 AWQ checkpoint**
   ```bash
   trtllm-build \
     --checkpoint_dir /workspace/checkpoints/llama-2-7b-int4-awq \
     --output_dir /workspace/engines/llama-2-7b-int4-awq/1-gpu \
     --gemm_plugin float16 \
     --max_batch_size 8 \
     --max_input_len 2048 \
     --max_seq_len 4096 \
     --max_num_tokens 8192

   # Takes 10-30 minutes for a 7B model
   ```

   **Key build parameters:**
   - `--max_batch_size`: Maximum concurrent requests in a batch
   - `--max_input_len`: Maximum prompt token length
   - `--max_seq_len`: Maximum total sequence (prompt + generation)
   - `--max_num_tokens`: Token budget per iteration (controls memory vs throughput)
   - `--gemm_plugin float16`: Use optimized matrix multiplication kernels

2. **Build multi-GPU engine** (for larger models)
   ```bash
   # For 70B model with tensor parallelism across 4 GPUs
   trtllm-build \
     --checkpoint_dir /workspace/checkpoints/llama-2-70b-int4-awq \
     --output_dir /workspace/engines/llama-2-70b-int4-awq/4-gpu \
     --tp_size 4 \
     --gemm_plugin float16 \
     --max_batch_size 4 \
     --max_input_len 2048 \
     --max_seq_len 4096
   ```

3. **Verify engine files**
   ```bash
   ls -la /workspace/engines/llama-2-7b-int4-awq/1-gpu/

   # Expected files:
   # - config.json          (model configuration)
   # - rank0.engine         (TensorRT engine binary)
   ```

### Task 5: Quick Test with trtllm-serve (15 min)

The `trtllm-serve` CLI provides the fastest way to test your engine. It wraps Triton with an OpenAI-compatible API.

1. **Start the serving server**
   ```bash
   # Inside the builder pod
   trtllm-serve \
     /workspace/engines/llama-2-7b-int4-awq/1-gpu \
     --tokenizer /workspace/models/llama-2-7b-chat-hf \
     --host 0.0.0.0 \
     --port 8000

   # Wait for: "Application startup complete"
   ```

   > **Model name = engine directory basename.** `trtllm-serve` registers the served model under the **last path component of the engine directory** — here `1-gpu` (from `.../1-gpu`), *not* `llama-2-7b-chat-hf`. Passing the wrong name returns HTTP 404. Confirm the exact id with `curl -s http://localhost:8000/v1/models`.

2. **Test with curl** (from another terminal)
   ```bash
   # The model id is "1-gpu" — the engine directory's basename (see note above).
   kubectl exec -it trt-llm-builder -n trt-llm -- \
     curl -s http://localhost:8000/v1/completions \
       -H "Content-Type: application/json" \
       -d '{
         "model": "1-gpu",
         "prompt": "What is Kubernetes? Explain in simple terms.",
         "max_tokens": 100,
         "temperature": 0.7
       }' | python3 -m json.tool
   ```

3. **Test with OpenAI Python client**
   ```bash
   kubectl exec -it trt-llm-builder -n trt-llm -- python3 -c "
   from openai import OpenAI
   client = OpenAI(api_key='unused', base_url='http://localhost:8000/v1')
   response = client.completions.create(
       model='1-gpu',  # engine directory basename, not the HF model name
       prompt='What is Kubernetes?',
       max_tokens=100
   )
   print(response.choices[0].text)
   "
   ```

4. **Stop trtllm-serve** (Ctrl+C) before proceeding to Task 6.

### Task 6: Production Deployment with Triton Ensemble (60 min)

For production, deploy Triton with the ensemble model architecture. This provides separate preprocessing (tokenization), inference, and postprocessing (de-tokenization) stages.

1. **Prepare the Triton model repository**

   The modern TRT-LLM Triton backend uses an ensemble of models:

   ```
   triton-models/
   ├── ensemble/                  # Orchestrates the pipeline
   │   └── config.pbtxt
   ├── preprocessing/             # String → token IDs
   │   ├── config.pbtxt
   │   └── 1/
   │       └── model.py
   ├── tensorrt_llm/              # Core TRT-LLM engine
   │   ├── config.pbtxt
   │   └── 1/
   │       ├── rank0.engine
   │       └── config.json
   └── postprocessing/            # Token IDs → string
       ├── config.pbtxt
       └── 1/
           └── model.py
   ```

   ```bash
   # Inside the builder pod
   # The Triton ensemble templates ship inside the TensorRT-LLM repo already
   # cloned in Task 3. As of v0.20.0 the standalone tensorrtllm_backend repo is
   # a thin wrapper whose tensorrt_llm/ is a git submodule; all_models/ and
   # tools/ now live under TensorRT-LLM/triton_backend/.
   cd /workspace/TensorRT-LLM

   # Copy the template model repository
   cp -r triton_backend/all_models/inflight_batcher_llm /workspace/triton-models

   # The template ships a 5th model, tensorrt_llm_bls (an alternative BLS
   # orchestrator). This lab uses the *ensemble* path, so remove bls — otherwise
   # its own unfilled ${logits_datatype} placeholder makes Triton (which defaults
   # to --exit-on-error=true) refuse to start the whole server.
   rm -rf /workspace/triton-models/tensorrt_llm_bls

   # Copy engine files into the model repository
   cp /workspace/engines/llama-2-7b-int4-awq/1-gpu/* \
     /workspace/triton-models/tensorrt_llm/1/
   ```

2. **Configure the model repository with fill_template.py**

   The `fill_template.py` script injects parameters into the template config files:

   ```bash
   # Fill preprocessing config
   python3 triton_backend/tools/fill_template.py -i /workspace/triton-models/preprocessing/config.pbtxt \
     "tokenizer_dir:/workspace/models/llama-2-7b-chat-hf,triton_max_batch_size:8,preprocessing_instance_count:1"

   # Fill tensorrt_llm config.
   # engine_dir is /models/tensorrt_llm/1 to match the Triton Deployment mount in
   # step 4 (the model repository is mounted at /models there). logits_datatype and
   # encoder_input_features_data_type are REQUIRED — they are proto data_type enums,
   # not tolerated string params, so an unfilled ${...} makes Triton's config parse fail.
   # decoupled_mode is False: Tasks 7-8 use the synchronous HTTP infer endpoint, which
   # returns HTTP 501 for decoupled models. Set it to True only if you switch the client
   # to gRPC streaming.
   python3 triton_backend/tools/fill_template.py -i /workspace/triton-models/tensorrt_llm/config.pbtxt \
     "triton_backend:tensorrtllm,triton_max_batch_size:8,decoupled_mode:False,engine_dir:/models/tensorrt_llm/1,batching_strategy:inflight_fused_batching,batch_scheduler_policy:max_utilization,kv_cache_free_gpu_mem_fraction:0.9,logits_datatype:TYPE_FP32,encoder_input_features_data_type:TYPE_FP16"

   # Fill postprocessing config
   python3 triton_backend/tools/fill_template.py -i /workspace/triton-models/postprocessing/config.pbtxt \
     "tokenizer_dir:/workspace/models/llama-2-7b-chat-hf,triton_max_batch_size:8,postprocessing_instance_count:1"

   # Fill ensemble config (logits_datatype required here too)
   python3 triton_backend/tools/fill_template.py -i /workspace/triton-models/ensemble/config.pbtxt \
     "triton_max_batch_size:8,logits_datatype:TYPE_FP32"

   # Sanity check: no proto data_type placeholders may remain, or Triton won't load.
   grep -rn 'data_type: ${' /workspace/triton-models/*/config.pbtxt && echo "FIX UNFILLED PLACEHOLDERS ABOVE" || echo "OK: no unfilled data_type placeholders"
   ```

   **Key configuration parameters:**
   - `batch_scheduler_policy`: `max_utilization` (greedy packing) or `guaranteed_no_evict` (default, no request pauses)
   - `kv_cache_free_gpu_mem_fraction`: Fraction of free GPU memory for KV cache (0.9 = 90%). On a 24GB A10G this makes Triton reserve ~20GB of VRAM up front — expected, not a leak.
   - `decoupled_mode`: streaming responses. Keep `False` for the synchronous client in Tasks 7-8 (decoupled models reject the HTTP `infer` endpoint with HTTP 501).
   - `logits_datatype` / `encoder_input_features_data_type`: proto tensor `data_type` enums the template leaves as `${...}`; they must be filled or Triton fails to parse the config.

3. **Exit the builder pod**
   ```bash
   exit
   ```

4. **Deploy Triton Server**
   ```yaml
   # Save as triton-trtllm.yaml
   apiVersion: apps/v1
   kind: Deployment
   metadata:
     name: triton-trtllm
     namespace: trt-llm
   spec:
     replicas: 1
     selector:
       matchLabels:
         app: triton-trtllm
     template:
       metadata:
         labels:
           app: triton-trtllm
       spec:
         containers:
           - name: triton
             image: nvcr.io/nvidia/tritonserver:25.06-trtllm-python-py3
             args:
               - tritonserver
               - --model-repository=/models
               - --http-port=8000
               - --grpc-port=8001
               - --metrics-port=8002
             ports:
               - containerPort: 8000
                 name: http
               - containerPort: 8001
                 name: grpc
               - containerPort: 8002
                 name: metrics
             resources:
               limits:
                 nvidia.com/gpu: 1
               requests:
                 nvidia.com/gpu: 1
                 memory: 32Gi
                 cpu: "8"
             volumeMounts:
               - name: storage
                 mountPath: /models
                 subPath: triton-models
               - name: model-storage
                 mountPath: /workspace/models
                 subPath: models
               - name: shm
                 mountPath: /dev/shm
             livenessProbe:
               httpGet:
                 path: /v2/health/live
                 port: 8000
               initialDelaySeconds: 120
               periodSeconds: 30
             readinessProbe:
               httpGet:
                 path: /v2/health/ready
                 port: 8000
               initialDelaySeconds: 60
               periodSeconds: 10
         volumes:
           - name: storage
             persistentVolumeClaim:
               claimName: trt-llm-storage
           - name: model-storage
             persistentVolumeClaim:
               claimName: trt-llm-storage
           - name: shm
             emptyDir:
               medium: Memory
               sizeLimit: 16Gi
         tolerations:
           - key: nvidia.com/gpu
             operator: Exists
             effect: NoSchedule
   ---
   apiVersion: v1
   kind: Service
   metadata:
     name: triton-trtllm
     namespace: trt-llm
   spec:
     selector:
       app: triton-trtllm
     ports:
       - name: http
         port: 8000
         targetPort: 8000
       - name: grpc
         port: 8001
         targetPort: 8001
       - name: metrics
         port: 8002
         targetPort: 8002
   ```

   ```bash
   kubectl apply -f triton-trtllm.yaml

   # Watch deployment (model loading takes a few minutes)
   kubectl logs -f deployment/triton-trtllm -n trt-llm

   # Wait for: "Started HTTPService at 0.0.0.0:8000"
   kubectl wait --for=condition=Ready pod -l app=triton-trtllm -n trt-llm --timeout=600s
   ```

### Task 7: Test Triton Inference (20 min)

1. **Port forward to Triton**
   ```bash
   kubectl port-forward svc/triton-trtllm 8000:8000 -n trt-llm &
   ```

2. **Check server health**
   ```bash
   # Health check returns HTTP 200 with empty body (no JSON)
   curl -s -o /dev/null -w "%{http_code}" http://localhost:8000/v2/health/ready
   # Expected: 200

   # List loaded models
   curl -s http://localhost:8000/v2/models | python3 -m json.tool
   ```

3. **Test with the ensemble endpoint using Triton client**
   ```bash
   pip install tritonclient[all] transformers
   ```

   ```python
   # Save as test_triton.py
   import tritonclient.http as httpclient
   import numpy as np
   import json

   client = httpclient.InferenceServerClient("localhost:8000")

   # Check which models are loaded
   models = client.get_model_repository_index()
   for model in models:
       print(f"  {model['name']}: {model.get('state', 'unknown')}")

   # Use the ensemble model for end-to-end inference
   # The ensemble handles tokenization and de-tokenization
   prompt = "What is machine learning? Explain briefly."

   inputs = [
       httpclient.InferInput("text_input", [1, 1], "BYTES"),
       httpclient.InferInput("max_tokens", [1, 1], "INT32"),
   ]

   inputs[0].set_data_from_numpy(
       np.array([[prompt]], dtype=object)
   )
   inputs[1].set_data_from_numpy(
       np.array([[100]], dtype=np.int32)
   )

   outputs = [httpclient.InferRequestedOutput("text_output")]

   result = client.infer("ensemble", inputs, outputs=outputs)
   generated = result.as_numpy("text_output")[0][0]
   if isinstance(generated, bytes):
       generated = generated.decode("utf-8")
   print(f"\nGenerated:\n{generated}")
   ```

   ```bash
   python test_triton.py
   ```

4. **Test with OpenAI-compatible API** (if Triton OpenAI frontend is enabled)
   ```python
   # Save as test_openai.py
   from openai import OpenAI

   client = OpenAI(
       api_key="unused",
       base_url="http://localhost:8000/v1"
   )

   response = client.completions.create(
       model="ensemble",
       prompt="What is Kubernetes? Explain in simple terms.",
       max_tokens=100,
       temperature=0.7
   )

   print(f"Response: {response.choices[0].text}")
   print(f"Usage: {response.usage.prompt_tokens} prompt, "
         f"{response.usage.completion_tokens} completion tokens")
   ```

   ```bash
   python test_openai.py
   ```

### Task 8: Performance Benchmarking (30 min)

1. **Benchmark with varying configurations**

   ```python
   # Save as benchmark_trtllm.py
   import tritonclient.http as httpclient
   import numpy as np
   import time
   import statistics

   client = httpclient.InferenceServerClient("localhost:8000")

   prompt = "Explain the concept of containerization in cloud computing."

   def run_inference(max_tokens=50):
       inputs = [
           httpclient.InferInput("text_input", [1, 1], "BYTES"),
           httpclient.InferInput("max_tokens", [1, 1], "INT32"),
       ]
       inputs[0].set_data_from_numpy(np.array([[prompt]], dtype=object))
       inputs[1].set_data_from_numpy(np.array([[max_tokens]], dtype=np.int32))
       outputs = [httpclient.InferRequestedOutput("text_output")]

       start = time.perf_counter()
       result = client.infer("ensemble", inputs, outputs=outputs)
       latency = time.perf_counter() - start
       return latency

   # Warm up
   for _ in range(3):
       run_inference()

   # Benchmark different output lengths
   print("=== TensorRT-LLM Inference Benchmark ===\n")
   for max_tokens in [50, 100, 200]:
       latencies = [run_inference(max_tokens) for _ in range(10)]
       avg = statistics.mean(latencies)
       p50 = statistics.median(latencies)
       p99 = sorted(latencies)[int(0.99 * len(latencies))]
       throughput = max_tokens / avg

       print(f"Max tokens: {max_tokens}")
       print(f"  Avg latency: {avg:.3f}s")
       print(f"  P50 latency: {p50:.3f}s")
       print(f"  P99 latency: {p99:.3f}s")
       print(f"  Throughput:  ~{throughput:.0f} tokens/s")
       print()
   ```

   ```bash
   python benchmark_trtllm.py
   ```

2. **Compare with your Lab 5.5 vLLM results**

   Run the same prompts against your vLLM deployment from Lab 5.5 and fill in:

   | Metric | vLLM (FP16) | TRT-LLM (INT4 AWQ) | Notes |
   |--------|-------------|--------------------|----|
   | Latency (50 tok) | ___s | ___s | Measure with same prompt |
   | Throughput | ___ tok/s | ___ tok/s | Single-request generation |
   | GPU Memory | ___GB | ___GB | `nvidia-smi` during inference |
   | Setup complexity | Low | High | Engine build required |

   > **Note:** Actual performance depends on GPU type, model, batch size, and sequence length. Do not compare numbers across different hardware.

   **Reference results — this lab validated on 1× NVIDIA A10G (24GB, g5.4xlarge), Llama-2-7B INT4-AWQ, single-stream via the Triton ensemble:**

   | max_tokens | avg latency | throughput |
   |-----------|-------------|-----------|
   | 50  | 0.43s | ~115 tok/s |
   | 100 | 0.87s | ~115 tok/s |
   | 200 | 1.74s | ~115 tok/s |

   INT4-AWQ checkpoint ~4GB (from ~13.5GB FP16). Engine build ~2 min. GPU memory in use ~20.8GB/23GB — dominated by the `kv_cache_free_gpu_mem_fraction:0.9` reservation, not the ~3.9GB engine. `trtllm-serve` gave the same ~114 tok/s, confirming the engine, not the serving layer, sets the ceiling. (These are A10G numbers; an A100/H100 will differ — do not compare across hardware.)

3. **Check Triton metrics**
   ```bash
   # Triton exposes Prometheus-compatible metrics
   curl -s http://localhost:8002/metrics | grep -E "^nv_inference|^nv_gpu"
   ```

## Cleanup

```bash
# Delete Triton deployment
kubectl delete deployment triton-trtllm -n trt-llm
kubectl delete svc triton-trtllm -n trt-llm

# Delete builder pod
kubectl delete pod trt-llm-builder -n trt-llm

# Delete storage (WARNING: deletes all engines and model data)
kubectl delete pvc trt-llm-storage -n trt-llm

# Delete secrets
kubectl delete secret hf-token -n trt-llm

# Delete namespace
kubectl delete namespace trt-llm
```

---

## Deliverables

- [ ] **Quantized checkpoint** created with INT4 AWQ (or FP8 on H100)
- [ ] **TensorRT engine** built and verified (`rank0.engine` exists)
- [ ] **Quick test** passed via `trtllm-serve` with OpenAI-compatible API
- [ ] **Triton ensemble deployment** running with preprocessing/postprocessing pipeline
- [ ] **Inference test** producing correct outputs via Triton client
- [ ] **Performance benchmark** table comparing TRT-LLM vs vLLM from Lab 5.5

## Verification Checklist

- [ ] k0rdent kubeconfig extracted and GPU cluster accessible
- [ ] TensorRT-LLM builder pod running with GPU access
- [ ] Model downloaded and quantized successfully
- [ ] TensorRT engine built without errors
- [ ] Engine produces correct inference via `trtllm-serve`
- [ ] Triton server deployed with ensemble model architecture
- [ ] Health check returns HTTP 200 (`/v2/health/ready`)
- [ ] Credentials stored in Kubernetes Secrets

## Troubleshooting

### GPU never becomes allocatable / GPU worker node goes `NotReady` after GPU Operator install

On k0s-based k0rdent clusters (k0s bundles containerd 1.7.x), the NVIDIA GPU Operator's container-toolkit can leave the node's containerd unable to serve CRI, so `nvidia.com/gpu` never appears and the node flips to `NotReady` with `container runtime is down, PLEG is not healthy`. Symptom in the containerd log: `failed to load plugin io.containerd.grpc.v1.cri ... no corresponding runtime configured in containerd.runtimes for default_runtime_name = "runc"`.

Cause: the toolkit writes the nvidia runtimes to `/etc/containerd/conf.d/99-nvidia.toml` and bridges it into k0s via a nested import; containerd merges that file **last**, and its `runtimes` map (nvidia only) drops k0s's `runc` entry while `default_runtime_name` stays `runc`. A plain `k0sworker`/containerd restart does **not** fix it — the merged config itself is wrong.

Fix (on the GPU worker node): add a `runc` runtime back to `/etc/containerd/conf.d/99-nvidia.toml` so the merged `runtimes` map keeps both `runc` and the nvidia runtimes, then `systemctl restart k0sworker`. Verify the merge with `containerd --config /etc/k0s/containerd.toml config dump | grep -A2 runtimes.runc`. This is a **cluster-setup** concern (see [Lab 5.1](lab-5.1-gpu-cluster-setup.md) / [Lab 5.12](lab-5.12-cluster-templates.md)); confirm `kubectl get nodes -l nvidia.com/gpu.present=true` shows `nvidia.com/gpu` allocatable **before** starting this lab.

### Quantization Fails

**Check GPU memory:**
```bash
nvidia-smi
# INT4 AWQ quantization of 7B model needs ~20GB VRAM
# Reduce calibration size if OOM:
# --calib_size 16
```

### Engine Build Out of Memory

**Reduce batch size and sequence length:**
```bash
trtllm-build ... \
  --max_batch_size 4 \
  --max_input_len 1024 \
  --max_seq_len 2048
```

### Triton Model Load Fails

**Check model repository structure:**
```bash
# Must have the ensemble directory structure:
ls /models/ensemble/config.pbtxt
ls /models/preprocessing/config.pbtxt
ls /models/tensorrt_llm/config.pbtxt
ls /models/tensorrt_llm/1/rank0.engine
ls /models/postprocessing/config.pbtxt
```

**Check Triton logs:**
```bash
kubectl logs deployment/triton-trtllm -n trt-llm | tail -50
```

### FP8 Engine Fails on A100

FP8 requires supported Ada (SM89), Hopper, or newer hardware. If you built an FP8 engine on H100 and try to run it on A100, it will fail. Rebuild with INT4 AWQ or INT8 SmoothQuant for A100 compatibility.

```bash
# Check GPU compute capability
nvidia-smi --query-gpu=compute_cap --format=csv,noheader
# H100 = 9.0, A100 = 8.0
# FP8 requires >= 8.9
```

---

## Key Takeaways

1. **TensorRT-LLM compiles models into architecture-specific engines** - providing maximum throughput but requiring a build step per GPU type
2. **FP8 is H100+ only** - for A100 clusters, use INT4 AWQ (best memory savings) or INT8 SmoothQuant (best compatibility)
3. **Modern Triton uses the ensemble model pattern** with separate preprocessing, inference, and postprocessing stages configured via `fill_template.py`
4. **`trtllm-serve`** provides a quick OpenAI-compatible API for testing; production uses Triton Inference Server directly
5. **No k0rdent catalog ServiceTemplate** exists for TensorRT-LLM; deploy manually on managed clusters (use KServe + vLLM from the catalog for simpler deployments)

### Performance Optimization Hierarchy

1. **First:** Choose appropriate quantization (INT4 AWQ for memory, FP8 for quality on H100)
2. **Second:** Tune engine build parameters (`max_batch_size`, `max_seq_len`, `max_num_tokens`)
3. **Third:** Configure batch scheduling policy (`max_utilization` for throughput, `guaranteed_no_evict` for predictability)
4. **Fourth:** Tune KV cache fraction (`kv_cache_free_gpu_mem_fraction`)
5. **Fifth:** Scale horizontally with multiple replicas if needed

---

## References

- [TensorRT-LLM GitHub Repository](https://github.com/NVIDIA/TensorRT-LLM)
- [TensorRT-LLM Documentation](https://nvidia.github.io/TensorRT-LLM/)
- [TensorRT-LLM Backend for Triton](https://github.com/triton-inference-server/tensorrtllm_backend)
- [Triton Inference Server Docs](https://docs.nvidia.com/deeplearning/triton-inference-server/)
- [TensorRT-LLM Quantization Guide](https://nvidia.github.io/TensorRT-LLM/blogs/quantization-in-TRT-LLM.html)

---

## Next Lab

Proceed to [Lab 5.14 - Slurm on Kubernetes](lab-5.14-slurm-operator-hpc.md)
