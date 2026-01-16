# Lab 5.6 - Troubleshooting GPU Scheduling

---

## Lab Navigation

| Track | Tier | Duration |
|-------|------|----------|
| Foundation | Required | 2 hours |

### Week 5 Learning Paths

```
FOUNDATION (Required) ─ COMPLETE!             CHOOSE YOUR PATH
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━             ━━━━━━━━━━━━━━━━
5.1 ➔ 5.2 ➔ 5.3 ➔ 5.4 ➔ 5.5 ➔ [5.6]
                                ↑
                           YOU ARE HERE
                                │
         ┌──────────────────────┼──────────────────────┐
         ▼                      ▼                      ▼
    ML PLATFORMS           COMPLIANCE             ADVANCED
    (Recommended)        (If Required)           (Optional)
    ━━━━━━━━━━━━         ━━━━━━━━━━━━           ━━━━━━━━
    5.9 Kubeflow         5.7 FIPS               5.13 TensorRT-LLM
    5.10 MLflow          5.8 Templates          5.14 RDMA
    5.11 Run:AI                                 5.15 Distributed
    5.12 Slurm
```

| Previous | Current | Next (Choose One) |
|----------|---------|-------------------|
| [Lab 5.5 - Service Catalog](lab-5.5-service-catalog.md) | **Lab 5.6 - Troubleshooting** | [5.7 FIPS](lab-5.7-nvidia-fips.md) / [5.9 Kubeflow](lab-5.9-kubeflow-ml-platform.md) / [5.13 TensorRT](lab-5.13-tensorrt-llm.md) |

---

**Duration:** 2 hours
**Type:** Hands-on Technical
**Environment:** GPU Lab

## Objective

Diagnose and resolve common GPU scheduling failures in AI/ML workloads, including pending pods, memory issues, and health check failures during upgrades.

## Prerequisites

- Completed Labs 5.1-5.5
- Kubernetes cluster with GPU nodes
- NVIDIA GPU Operator installed
- Understanding of Kubernetes scheduling

## Background

### Common GPU Scheduling Issues

| Issue | Symptoms | Root Cause |
|-------|----------|------------|
| Pods pending | Indefinite Pending state | No available GPUs |
| OOM errors | Pod killed/restarted | GPU memory exhaustion |
| Fragmentation | GPUs allocated but unused | Poor bin-packing |
| Health check failures | Pods fail readiness | Model loading timeout |
| Driver issues | nvidia-smi fails | GPU Operator problems |

### Diagnostic Tools

| Tool | Purpose |
|------|---------|
| `kubectl describe` | Scheduling events and errors |
| `nvidia-smi` | GPU state and memory usage |
| `kubectl top` | Resource consumption |
| `dcgmi` | Deep GPU diagnostics |

## Scenario Exercises

### Scenario A: Workloads Stuck Pending (Queue Full) - 30 min

**Symptoms:**
- GPU pods remain in Pending state
- Other GPU workloads running normally

**Setup:**
```bash
# Create a namespace for troubleshooting
kubectl create namespace gpu-troubleshoot

# Deploy pods to consume all GPUs
cat << 'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: gpu-hog
  namespace: gpu-troubleshoot
spec:
  replicas: 10  # More than available GPUs
  selector:
    matchLabels:
      app: gpu-hog
  template:
    metadata:
      labels:
        app: gpu-hog
    spec:
      containers:
        - name: gpu-hog
          image: nvidia/cuda:12.2.0-base-ubuntu22.04
          command: ["sh", "-c", "nvidia-smi && sleep infinity"]
          resources:
            limits:
              nvidia.com/gpu: 1
            requests:
              nvidia.com/gpu: 1
      tolerations:
        - key: nvidia.com/gpu
          operator: Exists
          effect: NoSchedule
EOF
```

**Investigation Steps:**

1. **Check Pod Status**
   ```bash
   kubectl get pods -n gpu-troubleshoot

   # Look for Pending pods
   kubectl get pods -n gpu-troubleshoot --field-selector=status.phase=Pending
   ```

2. **Describe Pending Pod**
   ```bash
   kubectl describe pod -n gpu-troubleshoot -l app=gpu-hog | grep -A20 "Events:"

   # Look for:
   # - "Insufficient nvidia.com/gpu"
   # - "0/3 nodes are available"
   ```

3. **Check GPU Availability**
   ```bash
   # Total allocatable GPUs
   kubectl get nodes -o custom-columns='NAME:.metadata.name,GPUs:.status.allocatable.nvidia\.com/gpu'

   # Currently requested GPUs
   kubectl get pods -A -o json | jq '[.items[] | select(.spec.containers[].resources.limits."nvidia.com/gpu" != null) | .spec.containers[].resources.limits."nvidia.com/gpu" | tonumber] | add'
   ```

4. **Check Queue Status (if using scheduler)**
   ```bash
   kubectl get queues -n kai-scheduler
   kubectl describe queue training-queue -n kai-scheduler
   ```

**Resolution Options:**

1. **Scale Down Other Workloads**
   ```bash
   kubectl scale deployment gpu-hog -n gpu-troubleshoot --replicas=2
   ```

2. **Use Priority and Preemption**
   ```yaml
   spec:
     priorityClassName: high-priority-gpu
   ```

3. **Enable Fractional GPU Sharing**
   ```bash
   # See Lab 5.1 Task 6 for time-slicing configuration
   ```

**Cleanup:**
```bash
kubectl delete deployment gpu-hog -n gpu-troubleshoot
```

---

### Scenario B: GPU Memory Fragmentation - 25 min

**Symptoms:**
- GPUs show as allocated but underutilized
- New workloads can't schedule despite available memory
- nvidia-smi shows gaps in GPU memory usage

**Setup:**
```bash
# Deploy multiple small workloads
cat << 'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: small-gpu-jobs
  namespace: gpu-troubleshoot
spec:
  replicas: 4
  selector:
    matchLabels:
      app: small-gpu
  template:
    metadata:
      labels:
        app: small-gpu
    spec:
      containers:
        - name: gpu-small
          image: nvidia/cuda:12.2.0-base-ubuntu22.04
          command: ["python3", "-c"]
          args:
            - |
              import torch
              # Allocate only 2GB of GPU memory
              x = torch.zeros(256, 1024, 1024, device='cuda')
              import time
              while True:
                  time.sleep(60)
          resources:
            limits:
              nvidia.com/gpu: 1
            requests:
              nvidia.com/gpu: 1
      tolerations:
        - key: nvidia.com/gpu
          operator: Exists
          effect: NoSchedule
EOF
```

**Investigation Steps:**

1. **Check GPU Memory Usage**
   ```bash
   # Get GPU node
   GPU_NODE=$(kubectl get nodes -l nvidia.com/gpu.present=true -o jsonpath='{.items[0].metadata.name}')

   # Check memory on GPU pods
   for pod in $(kubectl get pods -n gpu-troubleshoot -l app=small-gpu -o name); do
     echo "=== $pod ==="
     kubectl exec -n gpu-troubleshoot $pod -- nvidia-smi --query-gpu=memory.used,memory.total --format=csv
   done
   ```

2. **Calculate Fragmentation**
   ```bash
   # Total GPU memory on node
   TOTAL_MEM=$(kubectl exec -n gpu-troubleshoot deployment/small-gpu-jobs -- nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -1)

   # Used memory
   USED_MEM=$(kubectl exec -n gpu-troubleshoot deployment/small-gpu-jobs -- nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits | head -1)

   echo "Total: ${TOTAL_MEM}MB, Used: ${USED_MEM}MB"
   echo "Fragmentation: Each pod uses 1 GPU but only ~2GB of memory"
   ```

**Resolution Options:**

1. **Use MIG (Multi-Instance GPU)**
   ```yaml
   # For A100/H100 GPUs - partition into smaller instances
   resources:
     limits:
       nvidia.com/mig-1g.5gb: 1  # Use MIG slice instead of full GPU
   ```

2. **Enable Time-Slicing**
   ```yaml
   # GPU Operator time-slicing config
   sharing:
     timeSlicing:
       resources:
         - name: nvidia.com/gpu
           replicas: 4  # Share each GPU 4 ways
   ```

3. **Right-size Workloads**
   - Batch similar-sized workloads together
   - Use CUDA_VISIBLE_DEVICES for multi-process sharing

**Cleanup:**
```bash
kubectl delete deployment small-gpu-jobs -n gpu-troubleshoot
```

---

### Scenario C: vLLM OOM Errors - 30 min

**Symptoms:**
- vLLM pod starts but crashes during model loading
- Logs show CUDA out of memory errors
- Pod enters CrashLoopBackOff

**Setup:**
```bash
# Deploy vLLM with insufficient memory settings
cat << 'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: vllm-oom-test
  namespace: gpu-troubleshoot
spec:
  replicas: 1
  selector:
    matchLabels:
      app: vllm-oom
  template:
    metadata:
      labels:
        app: vllm-oom
    spec:
      containers:
        - name: vllm
          image: vllm/vllm-openai:v0.11.2
          args:
            - --model
            - meta-llama/Llama-2-13b-chat-hf  # Large model
            - --gpu-memory-utilization
            - "0.99"  # Too aggressive
            - --max-model-len
            - "8192"  # Large context
          env:
            - name: HUGGING_FACE_HUB_TOKEN
              valueFrom:
                secretKeyRef:
                  name: hf-token
                  key: token
                  optional: true
          resources:
            limits:
              nvidia.com/gpu: 1  # Single GPU may not be enough
            requests:
              nvidia.com/gpu: 1
              memory: 16Gi
      tolerations:
        - key: nvidia.com/gpu
          operator: Exists
          effect: NoSchedule
EOF
```

**Investigation Steps:**

1. **Check Pod Status**
   ```bash
   kubectl get pods -n gpu-troubleshoot -l app=vllm-oom

   # Check crash count
   kubectl get pods -n gpu-troubleshoot -l app=vllm-oom -o jsonpath='{.items[0].status.containerStatuses[0].restartCount}'
   ```

2. **View Logs for OOM**
   ```bash
   kubectl logs -n gpu-troubleshoot -l app=vllm-oom --previous | grep -i "out of memory\|oom\|cuda error"

   # Look for:
   # torch.cuda.OutOfMemoryError: CUDA out of memory
   # RuntimeError: CUDA error: out of memory
   ```

3. **Calculate Model Memory Requirements**
   ```bash
   # Rough estimation for LLM:
   # Memory ≈ Parameters × 2 bytes (for fp16) × 1.2 (overhead)
   # Llama-2-13B ≈ 13B × 2 × 1.2 ≈ 31.2 GB
   echo "Llama-2-13B requires ~32GB GPU memory"
   echo "A100-40GB might work, T4-16GB won't"
   ```

**Resolution Options:**

1. **Reduce Memory Utilization**
   ```yaml
   args:
     - --gpu-memory-utilization
     - "0.8"  # Leave 20% headroom
   ```

2. **Reduce Context Length**
   ```yaml
   args:
     - --max-model-len
     - "2048"  # Shorter context = less KV cache memory
   ```

3. **Use Smaller Model**
   ```yaml
   args:
     - --model
     - meta-llama/Llama-2-7b-chat-hf  # 7B instead of 13B
   ```

4. **Enable Tensor Parallelism (Multi-GPU)**
   ```yaml
   args:
     - --tensor-parallel-size
     - "2"  # Split across 2 GPUs
   resources:
     limits:
       nvidia.com/gpu: 2
   ```

5. **Use Quantization**
   ```yaml
   args:
     - --quantization
     - awq  # 4-bit quantization reduces memory by ~4x
   ```

**Cleanup:**
```bash
kubectl delete deployment vllm-oom-test -n gpu-troubleshoot
```

---

### Scenario D: Health Check Failures During Upgrade - 25 min

**Symptoms:**
- New pods fail readiness probes during rolling update
- Model loading takes longer than probe timeout
- Deployment rollout stuck

**Setup:**
```bash
# Deploy vLLM with aggressive health checks
cat << 'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: vllm-health-test
  namespace: gpu-troubleshoot
spec:
  replicas: 1
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 0
      maxSurge: 1
  selector:
    matchLabels:
      app: vllm-health
  template:
    metadata:
      labels:
        app: vllm-health
    spec:
      containers:
        - name: vllm
          image: vllm/vllm-openai:v0.11.2
          args:
            - --model
            - meta-llama/Llama-2-7b-chat-hf
          env:
            - name: HUGGING_FACE_HUB_TOKEN
              valueFrom:
                secretKeyRef:
                  name: hf-token
                  key: token
                  optional: true
          # Aggressive probes - will fail during model loading
          readinessProbe:
            httpGet:
              path: /health
              port: 8000
            initialDelaySeconds: 10  # Too short!
            periodSeconds: 5
            failureThreshold: 3
          livenessProbe:
            httpGet:
              path: /health
              port: 8000
            initialDelaySeconds: 30  # Too short for large models
            periodSeconds: 10
            failureThreshold: 3
          resources:
            limits:
              nvidia.com/gpu: 1
            requests:
              nvidia.com/gpu: 1
      tolerations:
        - key: nvidia.com/gpu
          operator: Exists
          effect: NoSchedule
EOF
```

**Investigation Steps:**

1. **Check Rollout Status**
   ```bash
   kubectl rollout status deployment/vllm-health-test -n gpu-troubleshoot

   # If stuck, check pods
   kubectl get pods -n gpu-troubleshoot -l app=vllm-health
   ```

2. **View Probe Failures**
   ```bash
   kubectl describe pod -n gpu-troubleshoot -l app=vllm-health | grep -A5 "Readiness\|Liveness"

   # Look for:
   # Warning  Unhealthy  Readiness probe failed: Get "http://...": connection refused
   ```

3. **Check Model Loading Time**
   ```bash
   # Watch logs during startup
   kubectl logs -n gpu-troubleshoot -l app=vllm-health -f

   # Time from start to "Application startup complete"
   ```

4. **Measure Actual Loading Time**
   ```bash
   # Typical loading times:
   # - 7B model, cached: 30-60 seconds
   # - 7B model, downloading: 3-10 minutes
   # - 13B model: 2-4 minutes
   # - 70B model: 10-20 minutes
   ```

**Resolution:**

1. **Increase Probe Timeouts**
   ```yaml
   readinessProbe:
     httpGet:
       path: /health
       port: 8000
     initialDelaySeconds: 120  # Allow time for download
     periodSeconds: 10
     failureThreshold: 30  # More retries
     timeoutSeconds: 5
   livenessProbe:
     httpGet:
       path: /health
       port: 8000
     initialDelaySeconds: 300  # Model loading can be slow
     periodSeconds: 30
     failureThreshold: 10
     timeoutSeconds: 10
   ```

2. **Use Startup Probe**
   ```yaml
   startupProbe:
     httpGet:
       path: /health
       port: 8000
     initialDelaySeconds: 30
     periodSeconds: 10
     failureThreshold: 60  # 10 minutes for initial startup
     timeoutSeconds: 5
   # Liveness/readiness only start after startup succeeds
   ```

3. **Pre-cache Models**
   ```yaml
   # Use PVC with pre-downloaded models
   volumeMounts:
     - name: model-cache
       mountPath: /root/.cache/huggingface
   volumes:
     - name: model-cache
       persistentVolumeClaim:
         claimName: model-cache-pvc  # Pre-populated with models
   ```

**Cleanup:**
```bash
kubectl delete deployment vllm-health-test -n gpu-troubleshoot
```

---

## Summary: Troubleshooting Flowchart

```
Pod Pending?
    │
    ├── Check: kubectl describe pod
    │   └── "Insufficient nvidia.com/gpu"
    │       └── Scale down other workloads OR enable time-slicing
    │
    └── Check: Node GPU availability
        └── All GPUs allocated
            └── Use priority/preemption OR add GPU nodes

Pod CrashLoopBackOff?
    │
    ├── Check: kubectl logs --previous
    │   └── "CUDA out of memory"
    │       └── Reduce memory utilization OR use smaller model
    │
    └── Check: kubectl describe pod
        └── "Liveness/Readiness probe failed"
            └── Increase probe timeouts OR add startup probe

GPU Not Detected?
    │
    ├── Check: nvidia-smi in pod
    │   └── Command not found
    │       └── Verify GPU Operator installation
    │
    └── Check: GPU Operator pods
        └── Driver pods not running
            └── Check node kernel compatibility
```

## Deliverables

- [ ] **Troubleshooting notes** for each scenario
- [ ] **Resolution commands** that worked
- [ ] **Screenshots** of error messages and fixes
- [ ] **Custom troubleshooting script** based on flowchart

## Verification Checklist

- [ ] Identified pending pod causes
- [ ] Diagnosed memory fragmentation
- [ ] Resolved OOM errors
- [ ] Fixed health check timeouts
- [ ] Created troubleshooting documentation

## Key Takeaways

1. **Always check `kubectl describe pod`** for scheduling failures
2. **GPU memory is the most common bottleneck** for AI workloads
3. **Model loading time varies greatly** - probe timeouts must account for this
4. **Time-slicing and MIG** help with GPU fragmentation
5. **PVCs for model caching** dramatically improve startup times
6. **Startup probes** are essential for ML workloads with long initialization
7. **Document common issues** for team knowledge sharing

## Next Steps - Choose Your Path

You have completed the **Foundation Track**! Choose your next learning path:

### ML Platforms Track (Recommended)
Build end-to-end ML workflows:
- [Lab 5.9 - Kubeflow ML Platform](lab-5.9-kubeflow-ml-platform.md) - Pipelines, training operators, Katib
- [Lab 5.10 - MLflow Experiment Tracking](lab-5.10-mlflow-experiment-tracking.md) - Model registry, artifacts
- [Lab 5.11 - Run:AI GPU Orchestration](lab-5.11-runai-gpu-orchestration.md) - Quotas, fractional GPU
- [Lab 5.12 - Slurm Operator for HPC](lab-5.12-slurm-operator-hpc.md) - Traditional HPC integration

### Compliance & Templates Track (If Required)
For regulated environments:
- [Lab 5.7 - NVIDIA FIPS Configuration](lab-5.7-nvidia-fips.md) - FIPS 140-2 compliance
- [Lab 5.8 - Cluster Templates for AI](lab-5.8-cluster-templates.md) - k0rdent ClusterTemplates

### Advanced Optimization Track (Optional)
For maximum performance:
- [Lab 5.13 - TensorRT-LLM Optimization](lab-5.13-tensorrt-llm.md) - Advanced inference
- [Lab 5.14 - Multi-Cloud RDMA](lab-5.14-rdma-multi-cloud.md) - EFA vs InfiniBand
- [Lab 5.15 - Distributed Training](lab-5.15-distributed-training.md) - Multi-node training
