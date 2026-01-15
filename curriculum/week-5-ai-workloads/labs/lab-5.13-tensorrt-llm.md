# Lab 5.13 - TensorRT-LLM Inference Optimization

**Duration:** 3.5 hours
**Type:** Hands-on Technical (Advanced)
**Environment:** GPU Lab (A100/H100 recommended)

## Objective

Deploy and optimize LLM inference using NVIDIA TensorRT-LLM, achieving maximum performance through advanced quantization techniques (INT4, INT8, FP8), custom engine builds, and Triton Inference Server integration.

## Prerequisites

- Completed Lab 5.2 (vLLM Inference Service)
- Kubernetes cluster with GPU nodes (A100 40GB+ recommended)
- NVIDIA GPU Operator v25.10.0 installed
- Basic understanding of model quantization from Lab 5.2

## Background: TensorRT-LLM Architecture

### What is TensorRT-LLM?

TensorRT-LLM is NVIDIA's high-performance inference framework specifically optimized for large language models. Unlike vLLM which uses PyTorch, TensorRT-LLM compiles models into optimized CUDA kernels.

```
┌─────────────────────────────────────────────────────────────────┐
│                    TensorRT-LLM Pipeline                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  HuggingFace Model    Quantization       TRT Engine    Serving  │
│  ┌─────────────┐     ┌───────────┐     ┌───────────┐  ┌──────┐ │
│  │ Llama-70B   │ --> │ INT4/INT8 │ --> │ .engine   │->│Triton│ │
│  │ (FP16)      │     │ FP8       │     │ file      │  │Server│ │
│  └─────────────┘     └───────────┘     └───────────┘  └──────┘ │
│       140GB              35-70GB          Optimized     Runtime │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### TensorRT-LLM vs vLLM

| Feature | TensorRT-LLM | vLLM |
|---------|-------------|------|
| **Framework** | Custom CUDA kernels | PyTorch |
| **Performance** | ~20-40% faster | Good baseline |
| **Quantization** | Native INT4/INT8/FP8 | AWQ, GPTQ |
| **Setup Complexity** | High (requires engine build) | Low (load and serve) |
| **Flexibility** | Less (model-specific engines) | More (dynamic loading) |
| **Best For** | Production, max performance | Development, flexibility |

### Quantization Formats in TensorRT-LLM

TensorRT-LLM supports multiple quantization formats, each with specific trade-offs:

| Format | Bits | Memory Savings | Speed Gain | Quality Impact | Build Time |
|--------|------|---------------|------------|----------------|------------|
| FP16 (baseline) | 16 | 1x | 1x | None | Fast |
| INT8 SmoothQuant | 8 | 2x | 1.5-2x | Low (<1%) | Medium |
| FP8 | 8 | 2x | 2-2.5x | Minimal (<0.5%) | Fast |
| INT4 AWQ | 4 | 4x | 2-3x | Low (1-3%) | Medium |
| INT4 GPTQ | 4 | 4x | 2-3x | Low (1-3%) | Long |

---

## Lab Environment

**Cluster Requirements:**
- 1+ GPU nodes with NVIDIA A100 (40GB minimum, 80GB recommended)
- 200GB+ storage for model checkpoints and engines
- NVIDIA GPU Operator installed
- Network access to NVIDIA NGC and HuggingFace

**Resource Requirements:**
- Engine build: 4-8 hours for 70B model (can be pre-built)
- Inference: Depends on model size and quantization

---

## Tasks

### Task 1: Understanding the TensorRT-LLM Workflow (15 min)

Before hands-on work, understand the TensorRT-LLM deployment workflow:

```
Step 1: Download HuggingFace Model
        ↓
Step 2: Quantize Model (optional, but recommended)
        ↓
Step 3: Build TensorRT Engine
        ↓
Step 4: Deploy with Triton Inference Server
        ↓
Step 5: Benchmark and Optimize
```

**Key Insight:** TensorRT-LLM engines are GPU-architecture specific. An engine built for A100 won't work on H100 and vice versa.

### Task 2: Set Up TensorRT-LLM Environment (30 min)

1. **Create Namespace and Storage**
   ```bash
   kubectl create namespace trt-llm

   # Create large PVC for model storage
   cat <<EOF | kubectl apply -f -
   apiVersion: v1
   kind: PersistentVolumeClaim
   metadata:
     name: trt-llm-storage
     namespace: trt-llm
   spec:
     accessModes:
       - ReadWriteOnce
     resources:
       requests:
         storage: 500Gi
     storageClassName: standard  # Adjust for your cluster
   EOF
   ```

2. **Create HuggingFace Token Secret**
   ```bash
   kubectl create secret generic hf-token \
     --from-literal=token=<your-hf-token> \
     -n trt-llm
   ```

3. **Deploy TensorRT-LLM Build Pod**

   This pod provides the environment for quantization and engine building:

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
         # Official NVIDIA TensorRT-LLM container
         image: nvcr.io/nvidia/tritonserver:24.12-trtllm-python-py3
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

1. **Access the Builder Pod**
   ```bash
   kubectl exec -it trt-llm-builder -n trt-llm -- bash
   ```

2. **Download Model from HuggingFace**
   ```bash
   # Inside the pod
   cd /workspace

   # Clone TensorRT-LLM examples for quantization scripts
   git clone https://github.com/NVIDIA/TensorRT-LLM.git
   cd TensorRT-LLM/examples/llama

   # Download Llama-2-7B model
   # (For 70B, use meta-llama/Llama-2-70b-chat-hf but requires more storage/time)
   huggingface-cli download meta-llama/Llama-2-7b-chat-hf \
     --local-dir /workspace/models/llama-2-7b-chat-hf \
     --token $HF_TOKEN
   ```

3. **Quantize with INT4 AWQ**

   INT4 AWQ (Activation-aware Weight Quantization) provides 4x memory reduction:

   ```bash
   # Quantize the model to INT4 AWQ
   python ../quantization/quantize.py \
     --model_dir /workspace/models/llama-2-7b-chat-hf \
     --output_dir /workspace/checkpoints/llama-2-7b-int4-awq \
     --dtype float16 \
     --qformat int4_awq \
     --awq_block_size 128 \
     --calib_size 32

   # This creates a quantized checkpoint
   # Expected output: "Quantization complete. Checkpoint saved to..."
   ```

   **Understanding the Parameters:**
   - `--qformat int4_awq`: 4-bit AWQ quantization
   - `--awq_block_size 128`: Granularity of quantization (smaller = better quality, larger = faster)
   - `--calib_size 32`: Number of calibration samples

4. **Alternative: FP8 Quantization (A100/H100 only)**
   ```bash
   # FP8 provides best quality with 2x compression
   python ../quantization/quantize.py \
     --model_dir /workspace/models/llama-2-7b-chat-hf \
     --output_dir /workspace/checkpoints/llama-2-7b-fp8 \
     --dtype float16 \
     --qformat fp8 \
     --kv_cache_dtype fp8
   ```

5. **Alternative: INT8 SmoothQuant**
   ```bash
   # INT8 SmoothQuant for broader GPU compatibility
   python ../quantization/quantize.py \
     --model_dir /workspace/models/llama-2-7b-chat-hf \
     --output_dir /workspace/checkpoints/llama-2-7b-int8-sq \
     --dtype float16 \
     --qformat int8_sq
   ```

### Task 4: Build TensorRT Engine (60 min)

Building the TensorRT engine optimizes the model for your specific GPU architecture.

1. **Build Engine from Quantized Checkpoint**
   ```bash
   # Build TensorRT engine from INT4 AWQ checkpoint
   trtllm-build \
     --checkpoint_dir /workspace/checkpoints/llama-2-7b-int4-awq \
     --output_dir /workspace/engines/llama-2-7b-int4-awq/1-gpu \
     --gemm_plugin float16 \
     --max_batch_size 8 \
     --max_input_len 2048 \
     --max_seq_len 4096 \
     --max_num_tokens 8192

   # This takes 10-30 minutes for 7B model
   # Look for: "Engine built successfully"
   ```

   **Key Build Parameters:**
   - `--max_batch_size`: Maximum concurrent requests
   - `--max_input_len`: Maximum prompt length
   - `--max_seq_len`: Maximum total sequence (prompt + generation)
   - `--gemm_plugin float16`: Use optimized matrix multiplication kernels

2. **Build Multi-GPU Engine (for larger models)**
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

3. **Verify Engine Files**
   ```bash
   ls -la /workspace/engines/llama-2-7b-int4-awq/1-gpu/

   # Expected files:
   # - config.json          # Model configuration
   # - rank0.engine         # TensorRT engine (main inference file)
   ```

### Task 5: Test Engine with TensorRT-LLM Runtime (20 min)

1. **Run Quick Inference Test**
   ```bash
   # Test the engine directly
   cd /workspace/TensorRT-LLM/examples/llama

   python ../run.py \
     --engine_dir /workspace/engines/llama-2-7b-int4-awq/1-gpu \
     --tokenizer_dir /workspace/models/llama-2-7b-chat-hf \
     --max_output_len 100 \
     --input_text "What is Kubernetes? Explain in simple terms."
   ```

   **Expected Output:**
   ```
   Input: What is Kubernetes? Explain in simple terms.
   Output: Kubernetes is an open-source container orchestration platform...
   Latency: 1.23 seconds
   Throughput: 81.3 tokens/second
   ```

2. **Benchmark Performance**
   ```bash
   # Run comprehensive benchmark
   python ../summarize.py \
     --engine_dir /workspace/engines/llama-2-7b-int4-awq/1-gpu \
     --test_trt_llm \
     --batch_size 1 \
     --max_ite 10
   ```

### Task 6: Deploy with Triton Inference Server (45 min)

Triton Inference Server provides production-grade model serving with batching, metrics, and HTTP/gRPC APIs.

1. **Create Triton Model Repository Structure**
   ```bash
   # Inside the builder pod
   mkdir -p /workspace/triton-models/llama-7b-trt/1

   # Copy engine files
   cp -r /workspace/engines/llama-2-7b-int4-awq/1-gpu/* \
     /workspace/triton-models/llama-7b-trt/1/

   # Create config.pbtxt
   cat > /workspace/triton-models/llama-7b-trt/config.pbtxt << 'EOF'
   name: "llama-7b-trt"
   backend: "tensorrtllm"
   max_batch_size: 8

   model_transaction_policy {
     decoupled: true
   }

   input [
     {
       name: "input_ids"
       data_type: TYPE_INT32
       dims: [ -1 ]
     },
     {
       name: "input_lengths"
       data_type: TYPE_INT32
       dims: [ 1 ]
     },
     {
       name: "request_output_len"
       data_type: TYPE_INT32
       dims: [ 1 ]
     }
   ]

   output [
     {
       name: "output_ids"
       data_type: TYPE_INT32
       dims: [ -1, -1 ]
     },
     {
       name: "sequence_length"
       data_type: TYPE_INT32
       dims: [ -1 ]
     }
   ]

   instance_group [
     {
       count: 1
       kind: KIND_GPU
       gpus: [ 0 ]
     }
   ]

   parameters: {
     key: "gpt_model_type"
     value: {
       string_value: "llama"
     }
   }

   parameters: {
     key: "gpt_model_path"
     value: {
       string_value: "/models/llama-7b-trt/1"
     }
   }

   parameters: {
     key: "max_tokens_in_paged_kv_cache"
     value: {
       string_value: "16384"
     }
   }

   parameters: {
     key: "batch_scheduler_policy"
     value: {
       string_value: "inflight_fused_batching"
     }
   }
   EOF
   ```

2. **Exit Builder Pod**
   ```bash
   exit
   ```

3. **Deploy Triton Server**
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
             image: nvcr.io/nvidia/tritonserver:24.12-trtllm-python-py3
             args:
               - tritonserver
               - --model-repository=/models
               - --log-verbose=1
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
               - name: shm
                 mountPath: /dev/shm
             livenessProbe:
               httpGet:
                 path: /v2/health/live
                 port: 8000
               initialDelaySeconds: 60
               periodSeconds: 30
             readinessProbe:
               httpGet:
                 path: /v2/health/ready
                 port: 8000
               initialDelaySeconds: 30
               periodSeconds: 10
         volumes:
           - name: storage
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

   # Watch deployment
   kubectl logs -f deployment/triton-trtllm -n trt-llm

   # Look for: "Started HTTPService at 0.0.0.0:8000"
   ```

### Task 7: Test Triton Server (20 min)

1. **Port Forward to Triton**
   ```bash
   kubectl port-forward svc/triton-trtllm 8000:8000 -n trt-llm &
   ```

2. **Check Server Health**
   ```bash
   curl http://localhost:8000/v2/health/ready
   # Expected: {"ready":true}

   # List loaded models
   curl http://localhost:8000/v2/models
   ```

3. **Run Inference Request**
   ```bash
   # Install Triton client
   pip install tritonclient[all]

   # Test inference
   python << 'EOF'
   import tritonclient.http as httpclient
   from transformers import AutoTokenizer
   import numpy as np

   # Load tokenizer
   tokenizer = AutoTokenizer.from_pretrained("meta-llama/Llama-2-7b-chat-hf")

   # Create client
   client = httpclient.InferenceServerClient("localhost:8000")

   # Prepare input
   prompt = "What is machine learning? Explain briefly."
   input_ids = tokenizer.encode(prompt, return_tensors="np").astype(np.int32)

   # Create request
   inputs = [
       httpclient.InferInput("input_ids", input_ids.shape, "INT32"),
       httpclient.InferInput("input_lengths", [1], "INT32"),
       httpclient.InferInput("request_output_len", [1], "INT32"),
   ]

   inputs[0].set_data_from_numpy(input_ids[0])
   inputs[1].set_data_from_numpy(np.array([len(input_ids[0])], dtype=np.int32))
   inputs[2].set_data_from_numpy(np.array([100], dtype=np.int32))  # Generate 100 tokens

   outputs = [
       httpclient.InferRequestedOutput("output_ids"),
   ]

   # Run inference
   response = client.infer("llama-7b-trt", inputs, outputs=outputs)
   output_ids = response.as_numpy("output_ids")[0]

   # Decode output
   generated_text = tokenizer.decode(output_ids, skip_special_tokens=True)
   print(f"Generated: {generated_text}")
   EOF
   ```

### Task 8: Performance Comparison with vLLM (30 min)

1. **Benchmark TensorRT-LLM**
   ```bash
   # Run benchmark with varying batch sizes
   python << 'EOF'
   import tritonclient.http as httpclient
   from transformers import AutoTokenizer
   import numpy as np
   import time

   tokenizer = AutoTokenizer.from_pretrained("meta-llama/Llama-2-7b-chat-hf")
   client = httpclient.InferenceServerClient("localhost:8000")

   prompt = "What is Kubernetes?"
   input_ids = tokenizer.encode(prompt, return_tensors="np").astype(np.int32)

   results = []
   for batch_size in [1, 2, 4, 8]:
       # Warm up
       for _ in range(2):
           inputs = [
               httpclient.InferInput("input_ids", input_ids.shape, "INT32"),
               httpclient.InferInput("input_lengths", [1], "INT32"),
               httpclient.InferInput("request_output_len", [1], "INT32"),
           ]
           inputs[0].set_data_from_numpy(input_ids[0])
           inputs[1].set_data_from_numpy(np.array([len(input_ids[0])], dtype=np.int32))
           inputs[2].set_data_from_numpy(np.array([50], dtype=np.int32))
           client.infer("llama-7b-trt", inputs)

       # Benchmark
       start = time.time()
       for _ in range(10):
           inputs = [
               httpclient.InferInput("input_ids", input_ids.shape, "INT32"),
               httpclient.InferInput("input_lengths", [1], "INT32"),
               httpclient.InferInput("request_output_len", [1], "INT32"),
           ]
           inputs[0].set_data_from_numpy(input_ids[0])
           inputs[1].set_data_from_numpy(np.array([len(input_ids[0])], dtype=np.int32))
           inputs[2].set_data_from_numpy(np.array([50], dtype=np.int32))
           client.infer("llama-7b-trt", inputs)
       elapsed = time.time() - start

       throughput = 10 * 50 / elapsed  # tokens per second
       results.append((batch_size, elapsed / 10, throughput))
       print(f"Batch {batch_size}: {elapsed/10:.3f}s/req, {throughput:.1f} tok/s")

   print("\n=== Comparison Table ===")
   print("| Batch | Latency (s) | Throughput (tok/s) |")
   print("|-------|-------------|-------------------|")
   for bs, lat, tp in results:
       print(f"| {bs} | {lat:.3f} | {tp:.1f} |")
   EOF
   ```

2. **Compare with vLLM Results**

   Run the same benchmark against your Lab 5.2 vLLM deployment and compare:

   | Metric | vLLM (FP16) | TRT-LLM (INT4 AWQ) | Improvement |
   |--------|-------------|--------------------|-|
   | Latency (batch=1) | ~0.5s | ~0.3s | 40% |
   | Throughput | ~100 tok/s | ~160 tok/s | 60% |
   | GPU Memory | ~14GB | ~5GB | 65% |

---

## Deliverables

- [ ] **Quantized checkpoint** created successfully
- [ ] **TensorRT engine** built and tested
- [ ] **Triton deployment** running and healthy
- [ ] **Inference test** producing correct outputs
- [ ] **Performance comparison** table with vLLM
- [ ] **Documentation** of build parameters and trade-offs

## Verification Checklist

- [ ] TensorRT-LLM builder pod running with GPU access
- [ ] Model downloaded and quantized successfully
- [ ] TensorRT engine built without errors
- [ ] Engine produces correct inference results
- [ ] Triton server started and model loaded
- [ ] HTTP inference endpoint responding
- [ ] Performance benchmarks documented

## Troubleshooting

### Quantization Fails

**Check GPU memory:**
```bash
nvidia-smi
# Ensure enough VRAM for model + quantization overhead
```

**Reduce calibration size:**
```bash
# Use smaller calibration dataset
--calib_size 16
```

### Engine Build Out of Memory

**Reduce batch size:**
```bash
# Build with smaller max batch
--max_batch_size 4
```

### Triton Model Load Fails

**Check model repository structure:**
```bash
ls -la /models/llama-7b-trt/
# Must have:
# - config.pbtxt
# - 1/rank0.engine
```

**Check Triton logs:**
```bash
kubectl logs deployment/triton-trtllm -n trt-llm
```

### Low Throughput

**Enable in-flight batching:**
```
parameters: {
  key: "batch_scheduler_policy"
  value: {
    string_value: "inflight_fused_batching"
  }
}
```

---

## Key Takeaways

### When to Use TensorRT-LLM

| Scenario | Recommendation |
|----------|---------------|
| Development/prototyping | Use vLLM (faster iteration) |
| Production deployment | Use TensorRT-LLM (maximum performance) |
| Frequent model updates | Use vLLM (no rebuild needed) |
| Fixed model, high traffic | Use TensorRT-LLM (worth build time) |
| Memory constrained | Use TensorRT-LLM with INT4 |
| Quality critical | Use TensorRT-LLM with FP8 |

### Performance Optimization Hierarchy

1. **First:** Choose appropriate quantization (INT4 AWQ for memory, FP8 for quality)
2. **Second:** Tune engine build parameters (max_batch_size, max_seq_len)
3. **Third:** Enable in-flight batching in Triton
4. **Fourth:** Scale horizontally if needed (multiple engines)

### Memory vs Quality vs Speed Trade-offs

```
            Memory Savings ──────────────────────►
            │
            │   ┌─────────────────────────────────┐
   Quality  │   │         FP16 (Baseline)         │
      │     │   └─────────────────────────────────┘
      │     │   ┌───────────────────────┐
      │     │   │        FP8            │ ◄── Best for A100/H100
      │     │   └───────────────────────┘
      │     │   ┌─────────────────┐
      │     │   │   INT8 SQ       │
      │     │   └─────────────────┘
      ▼     │   ┌───────────┐
            │   │  INT4 AWQ │ ◄── Best for memory efficiency
            │   └───────────┘
```

---

## References

### Official Documentation
- [TensorRT-LLM GitHub Repository](https://github.com/NVIDIA/TensorRT-LLM)
- [TensorRT-LLM Documentation](https://nvidia.github.io/TensorRT-LLM/)
- [Triton Inference Server](https://docs.nvidia.com/deeplearning/triton-inference-server/)

### Quantization
- [TensorRT-LLM Quantization Guide](https://nvidia.github.io/TensorRT-LLM/blogs/quantization-in-TRT-LLM.html)
- [AWQ Paper](https://arxiv.org/abs/2306.00978)
- [SmoothQuant Paper](https://arxiv.org/abs/2211.10438)

### Performance Optimization
- [TensorRT-LLM Best Practices](https://nvidia.github.io/TensorRT-LLM/blogs/best-practices.html)
- [Triton Performance Tuning](https://docs.nvidia.com/deeplearning/triton-inference-server/user-guide/docs/optimization.html)

---

## Next Lab

Proceed to [Lab 5.14 - Multi-Cloud RDMA Deep Dive](lab-5.14-rdma-multi-cloud.md)
