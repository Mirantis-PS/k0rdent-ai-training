# Lab 5.6 - Troubleshooting GPU Scheduling

---

## Lab Navigation

| Track | Tier | Duration |
|-------|------|----------|
| Foundation | Required | 2 hours |

### Week 5 Learning Paths

```
FOUNDATION (Required)                              CHOOSE YOUR PATH
━━━━━━━━━━━━━━━━━━━━                              ━━━━━━━━━━━━━━━━
5.1 ➔ 5.2 ➔ 5.3 ➔ 5.4 ➔ 5.5 ➔ [5.6] ➔ 5.7 ➔ 5.8  ──►  ML Platforms (5.9-5.10)
                                 ↑                        Compliance (5.11-5.12)
                            YOU ARE HERE                  Advanced (5.13-5.16)
```

| Previous | Current | Next |
|----------|---------|------|
| [Lab 5.5 - vLLM Inference](lab-5.5-vllm-inference.md) | **Lab 5.6 - Troubleshooting** | [Lab 5.7 - Jupyter Notebooks](lab-5.7-jupyter-notebooks.md) |

---

## Table of Contents

- [Objective](#objective)
- [Prerequisites](#prerequisites)
- [k0rdent Context](#k0rdent-context)
  - [Diagnostic Tools Reference](#diagnostic-tools-reference)
- [Tasks](#tasks)
  - [Task 1: Access the k0rdent-Managed GPU Cluster](#task-1-access-the-k0rdent-managed-gpu-cluster-10-min)
  - [Scenario A: GPU Operator Component Failures](#scenario-a-gpu-operator-component-failures-30-min)
  - [Scenario B: Workloads Stuck Pending](#scenario-b-workloads-stuck-pending-25-min)
  - [Scenario C: vLLM Out-of-Memory Errors](#scenario-c-vllm-out-of-memory-errors-30-min)
  - [Scenario D: Health Check Failures During Rolling Update](#scenario-d-health-check-failures-during-rolling-update-25-min)
  - [Scenario E: GPU Hardware Faults](#scenario-e-gpu-hardware-faults-20-min)
- [Summary: Troubleshooting Flowchart](#summary-troubleshooting-flowchart)
- [Cleanup](#cleanup)
- [Verification Checklist](#verification-checklist)
- [Key Takeaways](#key-takeaways)
- [Next Steps - Choose Your Path](#next-steps---choose-your-path)

**Duration:** 2 hours
**Type:** Hands-on Technical
**Environment:** GPU Lab (k0rdent-managed workload cluster)

## Objective

Diagnose and resolve common GPU scheduling failures in AI/ML workloads on k0rdent-managed clusters. You will work through realistic failure scenarios covering GPU Operator component issues, pending pods, OOM errors, health check failures, and hardware faults.

## Prerequisites

- Completed Labs 5.1-5.5
- k0rdent management cluster with a GPU-enabled workload cluster provisioned via `ClusterDeployment`
- GPU Operator deployed via `gpu-operator-25-10-0` ServiceTemplate

> **Lab Hardware:** Students are running on **g5.12xlarge** instances with **4x NVIDIA A10G GPUs** (24 GB VRAM each), connected via PCIe (no NVLink). Keep the 24 GB per-GPU memory limit in mind when sizing models -- see Scenario C for OOM implications.

## k0rdent Context

On k0rdent-managed clusters, the GPU Operator is deployed via the `gpu-operator-25-10-0` ServiceTemplate (either through `ClusterDeployment.spec.serviceSpec` or `MultiClusterService`). Troubleshooting requires understanding the full stack:

```
┌──────────────────────────────────────────────────────────────┐
│                 k0rdent Management Cluster                    │
│  ┌────────────────────────────────────────────────────────┐  │
│  │  ClusterDeployment                                      │  │
│  │    └── serviceSpec:                                     │  │
│  │          └── gpu-operator-25-10-0 ServiceTemplate       │  │
│  │                └── Sveltos deploys Helm release ──────────── │
│  └────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────┘
          │
          ▼
┌──────────────────────────────────────────────────────────────┐
│                  Workload Cluster (k0s)                       │
│  ┌───────────────────┐  ┌──────────────────────────────────┐│
│  │  GPU Operator      │  │  GPU Operator Components          ││
│  │  (controller)      │  │  ├── nvidia-driver-daemonset      ││
│  │                    │  │  ├── nvidia-container-toolkit-ds   ││
│  │                    │  │  ├── nvidia-device-plugin-ds       ││
│  │                    │  │  ├── nvidia-dcgm-exporter          ││
│  │                    │  │  ├── gpu-feature-discovery          ││
│  │                    │  │  └── node-feature-discovery        ││
│  └───────────────────┘  └──────────────────────────────────┘│
│                                                               │
│  k0s-specific paths:                                         │
│  ├── /etc/k0s/containerd.d/nvidia.toml  (runtime config)    │
│  └── /run/k0s/containerd.sock           (socket)            │
└──────────────────────────────────────────────────────────────┘
```

### Diagnostic Tools Reference

| Tool | Purpose | Where to Run |
|------|---------|-------------|
| `kubectl describe pod` | Scheduling events and errors | Workload cluster |
| `kubectl logs` | Container logs and crash reasons | Workload cluster |
| `nvidia-smi` | GPU state, memory, processes | Inside GPU pod (via kubectl exec) |
| `dcgmi diag` | Deep GPU hardware diagnostics | DCGM pod |
| `dcgmi health` | GPU health monitoring | DCGM pod |
| `kubectl get clusterdeployment` | Service deployment status | Management cluster |

## Tasks

### Task 1: Access the k0rdent-Managed GPU Cluster (10 min)

1. **Extract kubeconfig from the management cluster**

   ```bash
   # On the k0rdent management cluster — find your GPU cluster name first
   kubectl get clusterdeployments -n kcm-system

   # Extract kubeconfig (replace <cluster-name> with your GPU cluster name, e.g., ml-gpu)
   kubectl get secret <cluster-name>-kubeconfig -n kcm-system \
     -o jsonpath='{.data.value}' | base64 -d > gpu-cluster.kubeconfig

   export KUBECONFIG=gpu-cluster.kubeconfig
   ```

2. **Verify GPU Operator service status on the management cluster**

   Before troubleshooting the workload cluster, check whether the GPU Operator was successfully deployed by Sveltos:

   ```bash
   # Switch back to management cluster temporarily
   unset KUBECONFIG

   # Check ClusterDeployment service conditions (replace <cluster-name>)
   kubectl get clusterdeployment <cluster-name> -n kcm-system \
     -o jsonpath='{.status.services}' | jq '.[].conditions'

   # Look for:
   # - type: Helm → status: "True", reason: Provisioned
   # - type: gpu-operator.gpu-operator/SveltosHelmReleaseReady → status: "True"
   ```

   If `SveltosHelmReleaseReady` shows `status: "False"`, the GPU Operator Helm release failed. Check the Sveltos logs on the management cluster:

   ```bash
   kubectl logs -n projectsveltos -l app=sveltos-manager --tail=50
   ```

3. **Switch to workload cluster and verify GPU nodes**

   ```bash
   export KUBECONFIG=ml-gpu.kubeconfig

   kubectl get nodes -o wide
   kubectl get nodes -o custom-columns='NAME:.metadata.name,GPUs:.status.allocatable.nvidia\.com/gpu'
   ```

---

### Scenario A: GPU Operator Component Failures (30 min)

The most common GPU issue on k0rdent-managed clusters is the GPU Operator not initializing correctly, typically due to k0s containerd path mismatches.

**Symptoms:**
- `nvidia-smi` fails inside pods ("command not found" or "no GPU detected")
- GPU Operator pods in `CrashLoopBackOff` or `Error` state
- Node shows `nvidia.com/gpu: 0` in allocatable resources

**Investigation Steps:**

1. **Check GPU Operator pod health**

   ```bash
   # Overview of all GPU Operator pods
   kubectl get pods -n gpu-operator

   # Check each component:
   # Driver (runs nvidia driver installer on each GPU node)
   kubectl get pods -n gpu-operator -l app=nvidia-driver-daemonset
   kubectl logs -n gpu-operator -l app=nvidia-driver-daemonset --tail=30

   # Container Toolkit (configures containerd nvidia runtime)
   kubectl get pods -n gpu-operator -l app=nvidia-container-toolkit-daemonset
   kubectl logs -n gpu-operator -l app=nvidia-container-toolkit-daemonset --tail=30

   # Device Plugin (advertises nvidia.com/gpu resources to kubelet)
   kubectl get pods -n gpu-operator -l app=nvidia-device-plugin-daemonset
   kubectl logs -n gpu-operator -l app=nvidia-device-plugin-daemonset --tail=30

   # GPU Feature Discovery (labels nodes with GPU properties)
   kubectl get pods -n gpu-operator -l app=gpu-feature-discovery
   ```

2. **Diagnose: Toolkit crash due to wrong containerd paths (k0s-specific)**

   This is the **#1 cause** of GPU Operator failures on k0rdent clusters. k0s uses non-standard containerd paths:

   ```bash
   # Check if toolkit logs show containerd path errors
   kubectl logs -n gpu-operator -l app=nvidia-container-toolkit-daemonset --tail=50 | \
     grep -i "containerd\|socket\|config\|error"

   # Common error: "failed to find containerd config" or "socket not found"
   ```

   **Root cause:** The GPU Operator ServiceTemplate values must include k0s containerd paths:

   ```yaml
   # These env vars MUST be set in the ServiceTemplate values
   toolkit:
     env:
       - name: CONTAINERD_CONFIG
         value: /etc/k0s/containerd.d/nvidia.toml    # NOT /etc/containerd/config.toml
       - name: CONTAINERD_SOCKET
         value: /run/k0s/containerd.sock              # NOT /run/containerd/containerd.sock
       - name: CONTAINERD_RUNTIME_CLASS
         value: nvidia
   ```

   **Fix:** Update the ClusterDeployment serviceSpec on the management cluster:

   ```bash
   # Switch to management cluster
   unset KUBECONFIG

   # Patch the ClusterDeployment to add correct toolkit env vars
   # (See Lab 5.8 for full ClusterDeployment serviceSpec syntax)
   kubectl edit clusterdeployment ml-gpu -n kcm-system
   # Add the toolkit.env values shown above
   ```

3. **Diagnose: Driver pod failures**

   ```bash
   export KUBECONFIG=ml-gpu.kubeconfig

   # Check driver pod status
   kubectl get pods -n gpu-operator -l app=nvidia-driver-daemonset -o wide

   # Check driver compilation logs (driver builds kernel module on each node)
   DRIVER_POD=$(kubectl get pods -n gpu-operator -l app=nvidia-driver-daemonset \
     -o jsonpath='{.items[0].metadata.name}')
   kubectl logs -n gpu-operator $DRIVER_POD --tail=100
   ```

   **Common driver issues:**
   - Kernel headers missing → driver compilation fails
   - Secure Boot enabled → unsigned kernel module rejected
   - Pre-existing NVIDIA driver → conflict with operator-managed driver

4. **Diagnose: Device Plugin shows 0 GPUs**

   ```bash
   # Check device plugin logs
   kubectl logs -n gpu-operator -l app=nvidia-device-plugin-daemonset --tail=30

   # Verify GPUs visible to the node
   # -A7 because Allocatable: is followed by cpu, ephemeral-storage, 2x hugepages, memory
   # before nvidia.com/gpu on k0s v1.32 / Ubuntu 22.04 nodes.
   kubectl describe nodes | grep -A7 "Allocatable:" | grep nvidia

   # Alternatively, a direct jsonpath avoids any grep-context drift:
   kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.allocatable.nvidia\.com/gpu}{"\n"}{end}'

   # If nvidia.com/gpu shows 0, the device plugin may need restart
   kubectl delete pods -n gpu-operator -l app=nvidia-device-plugin-daemonset
   ```

5. **Verify fix: test GPU access**

   ```bash
   kubectl run gpu-test --image=nvcr.io/nvidia/cuda:12.6.0-base-ubi9 \
     --restart=Never --rm -it \
     --overrides='{
       "spec": {
         "containers": [{"name": "gpu-test", "image": "nvcr.io/nvidia/cuda:12.6.0-base-ubi9", "resources": {"limits": {"nvidia.com/gpu": "1"}}}],
         "tolerations": [{"key": "nvidia.com/gpu", "operator": "Exists", "effect": "NoSchedule"}]
       }
     }' \
     -- nvidia-smi
   ```

6. **Verify the containerd config on the node**

   ```bash
   # Use kubectl debug to inspect the node filesystem (mounted at /host/)
   NODE_NAME=$(kubectl get nodes -l nvidia.com/gpu.present=true \
     -o jsonpath='{.items[0].metadata.name}')

   kubectl debug node/$NODE_NAME -it --image=busybox -- cat /host/etc/k0s/containerd.d/nvidia.toml
   ```

   **Expected content:**
   ```toml
   [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nvidia]
     privileged_without_host_devices = false
     runtime_type = "io.containerd.runc.v2"
   [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nvidia.options]
     BinaryName = "/usr/bin/nvidia-container-runtime"
   ```

---

### Scenario B: Workloads Stuck Pending (25 min)

**Symptoms:**
- GPU pods remain in `Pending` state indefinitely
- Other GPU workloads are running normally

**Setup: Saturate GPU capacity**

```bash
kubectl create namespace gpu-troubleshoot

cat << 'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: gpu-hog
  namespace: gpu-troubleshoot
spec:
  replicas: 10
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
          image: nvcr.io/nvidia/cuda:12.6.0-base-ubi9
          command: ["sh", "-c", "nvidia-smi && sleep infinity"]
          resources:
            limits:
              nvidia.com/gpu: 1
      tolerations:
        - key: nvidia.com/gpu
          operator: Exists
          effect: NoSchedule
EOF
```

**Investigation Steps:**

1. **Identify pending pods**

   ```bash
   kubectl get pods -n gpu-troubleshoot
   kubectl get pods -n gpu-troubleshoot --field-selector=status.phase=Pending
   ```

2. **Check scheduling failure reason**

   ```bash
   # Describe a pending pod to see Events
   PENDING_POD=$(kubectl get pods -n gpu-troubleshoot --field-selector=status.phase=Pending \
     -o jsonpath='{.items[0].metadata.name}')

   kubectl describe pod $PENDING_POD -n gpu-troubleshoot | tail -20

   # Look for:
   # 0/3 nodes are available: 3 Insufficient nvidia.com/gpu
   ```

3. **Check cluster-wide GPU allocation**

   ```bash
   # Total allocatable GPUs per node
   kubectl get nodes -o custom-columns='NAME:.metadata.name,GPUs:.status.allocatable.nvidia\.com/gpu'

   # Count pods currently consuming GPUs
   kubectl get pods -A -o jsonpath='{range .items[*]}{range .spec.containers[*]}{.resources.limits.nvidia\.com/gpu}{"\n"}{end}{end}' | grep -v '^$' | wc -l
   ```

4. **Check KAI Scheduler queue (if deployed)**

   ```bash
   # KAI Queues are cluster-scoped (NOT namespaced)
   kubectl get queues.scheduling.run.ai

   # Check queue resource allocation
   kubectl describe queue default
   ```

**Resolution Options:**

1. **Scale down competing workloads**
   ```bash
   kubectl scale deployment gpu-hog -n gpu-troubleshoot --replicas=2
   ```

2. **Use PriorityClass for preemption**
   ```yaml
   apiVersion: scheduling.k8s.io/v1
   kind: PriorityClass
   metadata:
     name: high-priority-gpu
   value: 1000000
   globalDefault: false
   description: "High priority for critical GPU workloads"
   ```

3. **Enable GPU sharing** (time-slicing or MIG - see Lab 5.1 Task 6)

**Cleanup:**
```bash
kubectl delete deployment gpu-hog -n gpu-troubleshoot
```

---

### Scenario C: vLLM Out-of-Memory Errors (30 min)

**Symptoms:**
- vLLM pod starts but crashes during model loading
- Logs show `CUDA out of memory` errors
- Pod enters `CrashLoopBackOff`

**Setup: Deploy vLLM with insufficient resources**

```bash
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
          image: vllm/vllm-openai:v0.14.0
          args:
            - --model
            - meta-llama/Llama-2-13b-chat-hf
            - --gpu-memory-utilization
            - "0.99"
            - --max-model-len
            - "8192"
          env:
            - name: HF_TOKEN
              valueFrom:
                secretKeyRef:
                  name: hf-token
                  key: token
                  optional: true
          resources:
            limits:
              nvidia.com/gpu: 1
            requests:
              memory: 16Gi
      tolerations:
        - key: nvidia.com/gpu
          operator: Exists
          effect: NoSchedule
EOF
```

**Investigation Steps:**

1. **Check crash status**

   ```bash
   kubectl get pods -n gpu-troubleshoot -l app=vllm-oom

   # Check restart count
   kubectl get pods -n gpu-troubleshoot -l app=vllm-oom \
     -o jsonpath='{.items[0].status.containerStatuses[0].restartCount}'
   ```

2. **Read crash logs**

   ```bash
   # View logs from the previous (crashed) container
   kubectl logs -n gpu-troubleshoot -l app=vllm-oom --previous | \
     grep -i "out of memory\|oom\|cuda error\|torch.cuda"

   # Expected errors:
   # torch.cuda.OutOfMemoryError: CUDA out of memory.
   # Tried to allocate X GiB (GPU 0; Y GiB total capacity; Z GiB already allocated)
   ```

3. **Estimate model memory requirements**

   ```
   Model memory estimation (fp16):
   ┌────────────────────────────────────────────────┐
   │ Memory = Parameters x 2 bytes x 1.2 (overhead) │
   │                                                  │
   │ Llama-2-7B:  7B  x 2 x 1.2 ≈ 17 GB            │
   │ Llama-2-13B: 13B x 2 x 1.2 ≈ 31 GB            │
   │ Llama-2-70B: 70B x 2 x 1.2 ≈ 168 GB           │
   │                                                  │
   │ + KV cache for context (depends on max_model_len)│
   │ 8192 context @ 13B ≈ 4-6 GB additional          │
   │                                                  │
   │ GPU Memory Required:                             │
   │ Llama-2-13B + 8K ctx ≈ 35-37 GB                 │
   │ ↳ A10G (24GB): FAILS ← our lab GPU               │
   │ ↳ A100-40GB:   tight (needs lower utilization)  │
   │ ↳ A100-80GB:   OK                               │
   └────────────────────────────────────────────────┘
   ```

**Resolution Options:**

1. **Reduce GPU memory utilization** (leave headroom for KV cache)
   ```yaml
   args:
     - --gpu-memory-utilization
     - "0.85"    # Leave 15% headroom (default is 0.9)
   ```

2. **Reduce context length** (smaller KV cache)
   ```yaml
   args:
     - --max-model-len
     - "2048"    # Reduce from 8192
   ```

3. **Use a smaller model**
   ```yaml
   args:
     - --model
     - meta-llama/Llama-2-7b-chat-hf    # 7B instead of 13B
   ```

4. **Use tensor parallelism** (split across multiple GPUs)
   ```yaml
   args:
     - --tensor-parallel-size
     - "2"
   resources:
     limits:
       nvidia.com/gpu: 2
   ```

5. **Use quantization** (reduce model precision)
   ```yaml
   args:
     - --quantization
     - awq    # 4-bit: reduces memory ~4x
   ```

**Cleanup:**
```bash
kubectl delete deployment vllm-oom-test -n gpu-troubleshoot
```

---

### Scenario D: Health Check Failures During Rolling Update (25 min)

**Symptoms:**
- New pods fail readiness probes during rolling update
- Model loading takes longer than probe timeout
- `kubectl rollout status` shows deployment stuck

**Setup: Deploy vLLM with aggressive health checks**

```bash
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
          image: vllm/vllm-openai:v0.14.0
          args:
            - --model
            - meta-llama/Llama-2-7b-chat-hf
          env:
            - name: HF_TOKEN
              valueFrom:
                secretKeyRef:
                  name: hf-token
                  key: token
                  optional: true
          readinessProbe:
            httpGet:
              path: /health
              port: 8000
            initialDelaySeconds: 10    # Too short!
            periodSeconds: 5
            failureThreshold: 3
          livenessProbe:
            httpGet:
              path: /health
              port: 8000
            initialDelaySeconds: 30    # Too short for model loading
            periodSeconds: 10
            failureThreshold: 3
          resources:
            limits:
              nvidia.com/gpu: 1
      tolerations:
        - key: nvidia.com/gpu
          operator: Exists
          effect: NoSchedule
EOF
```

**Investigation Steps:**

1. **Check rollout status**

   ```bash
   kubectl rollout status deployment/vllm-health-test -n gpu-troubleshoot --timeout=120s

   kubectl get pods -n gpu-troubleshoot -l app=vllm-health
   ```

2. **View probe failures in events**

   ```bash
   kubectl describe pod -n gpu-troubleshoot -l app=vllm-health | grep -A5 "Events:"

   # Expected:
   # Warning  Unhealthy  Readiness probe failed: Get "http://10.x.x.x:8000/health": connection refused
   # Warning  Unhealthy  Liveness probe failed: ...
   ```

3. **Estimate actual model loading time**

   ```bash
   # Watch logs during startup to find when model is ready
   kubectl logs -n gpu-troubleshoot -l app=vllm-health -f

   # Look for: "Application startup complete" or "Uvicorn running on"
   ```

   Typical loading times (with model cached on PVC):
   | Model | Cached | First Download |
   |-------|--------|---------------|
   | 7B | 30-60s | 3-10 min |
   | 13B | 1-2 min | 5-15 min |
   | 70B | 5-10 min | 15-30 min |

   > **Note:** vLLM's `/health` endpoint returns HTTP 200 with an empty body when the server is ready. Before model loading completes, the endpoint returns connection refused (server not started yet).

**Resolution: Use a startup probe**

The correct pattern for LLM workloads is a **startup probe** that handles the long initialization, combined with reasonable readiness/liveness probes for steady-state operation:

```yaml
containers:
  - name: vllm
    # Startup probe: handles long model loading phase
    # Liveness/readiness won't run until startup succeeds
    startupProbe:
      httpGet:
        path: /health
        port: 8000
      initialDelaySeconds: 30
      periodSeconds: 10
      failureThreshold: 60     # 30s + (10s x 60) = ~10.5 minutes max
      timeoutSeconds: 5

    # Readiness: fast checks once model is loaded
    readinessProbe:
      httpGet:
        path: /health
        port: 8000
      periodSeconds: 10
      failureThreshold: 3
      timeoutSeconds: 5

    # Liveness: detect stuck processes
    livenessProbe:
      httpGet:
        path: /health
        port: 8000
      periodSeconds: 30
      failureThreshold: 5
      timeoutSeconds: 10
```

**Additional optimization: pre-cache models on PVC**

```yaml
env:
  - name: HF_HOME
    value: /models
volumeMounts:
  - name: model-cache
    mountPath: /models
volumes:
  - name: model-cache
    persistentVolumeClaim:
      claimName: model-cache-pvc
```

Pre-populating the PVC with models reduces startup time from minutes to seconds, making probe tuning less critical.

**Cleanup:**
```bash
kubectl delete deployment vllm-health-test -n gpu-troubleshoot
```

---

### Scenario E: GPU Hardware Faults (20 min)

**Symptoms:**
- GPU workloads produce incorrect results or crash intermittently
- `nvidia-smi` shows ECC errors
- Node logs contain Xid error messages

**Investigation Steps:**

1. **Check for GPU errors via DCGM**

   ```bash
   # Find the DCGM pod
   DCGM_POD=$(kubectl get pods -n gpu-operator -l app=nvidia-dcgm \
     -o jsonpath='{.items[0].metadata.name}')

   # Discover GPUs
   kubectl exec -n gpu-operator $DCGM_POD -- dcgmi discovery -l

   # Run quick health check (Level 1)
   kubectl exec -n gpu-operator $DCGM_POD -- dcgmi diag -r 1

   # Run comprehensive diagnostic (Level 3 - takes longer)
   kubectl exec -n gpu-operator $DCGM_POD -- dcgmi diag -r 3
   ```

2. **Check DCGM Exporter metrics for errors**

   ```bash
   # Port-forward to DCGM exporter
   kubectl port-forward -n gpu-operator svc/nvidia-dcgm-exporter 9400:9400 &

   # Check for ECC errors
   curl -s http://localhost:9400/metrics | grep -E "DCGM_FI_DEV_ECC_SBE_VOL|DCGM_FI_DEV_ECC_DBE_VOL"

   # Check GPU temperature and power
   curl -s http://localhost:9400/metrics | grep -E "DCGM_FI_DEV_GPU_TEMP|DCGM_FI_DEV_POWER_USAGE"

   # Check for retired pages (indicator of failing memory)
   curl -s http://localhost:9400/metrics | grep "DCGM_FI_DEV_RETIRED_"

   kill %1 2>/dev/null
   ```

3. **Check Xid errors on the node**

   ```bash
   # Check dmesg for GPU errors via debug pod
   NODE_NAME=$(kubectl get nodes -l nvidia.com/gpu.present=true \
     -o jsonpath='{.items[0].metadata.name}')

   kubectl debug node/$NODE_NAME -it --image=ubuntu -- bash -c "dmesg | grep -i 'xid\|nvidia' | tail -20"
   ```

   Or query DCGM exporter metrics directly (if DCGM is deployed):

   ```bash
   # Query GPU metrics via the DCGM exporter (alternative to dmesg)
   kubectl port-forward -n gpu-operator svc/nvidia-dcgm-exporter 9400:9400 &
   curl -s http://localhost:9400/metrics | grep -E 'DCGM_FI_DEV_(XID_ERRORS|ECC|POWER)' | head -20
   kill %1 2>/dev/null
   ```

   **Common Xid error codes:**

   | Xid | Meaning | Action |
   |-----|---------|--------|
   | 13 | Graphics Engine fault | Usually application bug; check workload code |
   | 31 | MMU fault (illegal memory access) | Application bug or driver issue |
   | 45 | Preemptive channel removal | Informational; check if GPU was reset |
   | 48 | Double-bit ECC error (DBE) | **Hardware fault** - GPU memory failing |
   | 63 | ECC page retired successfully | Memory cells failing; monitor rate |
   | 64 | ECC page retirement failed | **Critical** - GPU needs replacement |
   | 79 | GPU fell off the bus | **Critical** - PCIe/hardware failure |

4. **Handle GPU hardware failures**

   If DCGM reports persistent ECC errors (Xid 48/63/64) or bus failures (Xid 79):

   ```bash
   # Cordon the node to prevent new workloads
   kubectl cordon <node-name>

   # Drain existing workloads (they'll reschedule to healthy nodes)
   kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data

   # On k0rdent: scale up the ClusterDeployment to add a replacement node
   # (on management cluster — replace <cluster-name> and set workersNumber to current+1)
   unset KUBECONFIG
   kubectl get clusterdeployment <cluster-name> -n kcm-system \
     -o jsonpath='{.spec.config.workersNumber}'  # Note current count
   kubectl patch clusterdeployment <cluster-name> -n kcm-system \
     --type merge -p '{"spec":{"config":{"workersNumber":<current+1>}}}'
   ```

---

## Summary: Troubleshooting Flowchart

```
nvidia-smi fails in pod?
    │
    ├── GPU Operator pods healthy?
    │   ├── NO → Check toolkit logs for containerd path errors
    │   │        └── Fix: Add k0s containerd paths to ServiceTemplate values
    │   │
    │   └── Driver pod crashing?
    │       └── Check: kernel headers, Secure Boot, pre-existing drivers
    │
    └── Device plugin shows 0 GPUs?
        └── Restart: kubectl delete pods -l app=nvidia-device-plugin-daemonset

Pod Pending?
    │
    ├── kubectl describe pod → "Insufficient nvidia.com/gpu"
    │   └── Scale down workloads OR enable GPU sharing (MIG/time-slicing)
    │
    └── All GPUs allocated
        └── Use PriorityClass preemption OR add GPU nodes via ClusterDeployment

Pod CrashLoopBackOff?
    │
    ├── kubectl logs --previous → "CUDA out of memory"
    │   └── Reduce --gpu-memory-utilization / --max-model-len / use quantization
    │
    └── kubectl describe pod → "probe failed"
        └── Add startupProbe with failureThreshold=60 + pre-cache models

GPU errors / wrong results?
    │
    ├── dcgmi diag -r 1 → FAIL
    │   └── Check Xid errors in dmesg
    │       ├── Xid 13/31: Application bug
    │       └── Xid 48/63/64/79: Hardware fault → cordon + drain + replace
    │
    └── DCGM ECC metrics rising
        └── Monitor rate; plan node replacement if persistent
```

## Cleanup

```bash
# Delete all troubleshooting resources
kubectl delete namespace gpu-troubleshoot --ignore-not-found

# Stop any port-forwards
kill %1 2>/dev/null
```

## Verification Checklist

- [ ] Accessed workload cluster via kubeconfig extraction from management cluster
- [ ] Checked GPU Operator service status on ClusterDeployment
- [ ] Diagnosed and resolved GPU Operator component failures (k0s containerd paths)
- [ ] Identified pending pod causes and applied resolution
- [ ] Diagnosed OOM errors with memory estimation
- [ ] Fixed health check timeouts using startup probes
- [ ] Ran DCGM diagnostics and interpreted Xid errors
- [ ] Applied node drain and ClusterDeployment scaling for hardware faults

## Key Takeaways

1. **k0s containerd paths are the #1 GPU Operator issue** on k0rdent clusters. Verify containerd config via `kubectl debug node/` or by checking the nvidia-container-toolkit pod logs.
2. **Check service deployment status** on the management cluster first (`SveltosHelmReleaseReady` condition) before debugging the workload cluster.
3. **GPU memory is the most common workload bottleneck** - estimate model requirements before deployment using the Parameters x 2 x 1.2 formula.
4. **Startup probes are essential for LLM workloads** - model loading can take minutes; liveness/readiness probes only activate after startup succeeds.
5. **DCGM diagnostics detect hardware faults** that aren't visible to Kubernetes - run `dcgmi diag -r 1` regularly.
6. **Scale GPU nodes via ClusterDeployment** on the management cluster rather than manually adding nodes.

## Next Steps - Choose Your Path

You have completed the **Foundation Track**! Choose your next learning path:

### ML Platforms Track (Recommended)
Build end-to-end ML workflows:
- [Lab 5.9 - Kubeflow ML Platform](lab-5.9-kubeflow-ml-platform.md) - Pipelines, training operators, Katib
- [Lab 5.10 - MLflow Experiment Tracking](lab-5.10-mlflow-experiment-tracking.md) - Model registry, artifacts
- [Lab 5.11 - Run:AI GPU Orchestration](lab-5.4-runai-gpu-orchestration.md) - Quotas, fractional GPU
- [Lab 5.12 - Slurm Operator for HPC](lab-5.14-slurm-operator-hpc.md) - Traditional HPC integration

### Compliance & Templates Track (If Required)
For regulated environments:
- [Lab 5.7 - FIPS Compliance](lab-5.11-nvidia-fips.md) - FIPS 140-2/3 compliance for GPU infrastructure
- [Lab 5.8 - Cluster Templates for AI](lab-5.12-cluster-templates.md) - k0rdent ClusterTemplates

### Advanced Optimization Track (Optional)
For maximum performance:
- [Lab 5.13 - TensorRT-LLM Optimization](lab-5.13-tensorrt-llm.md) - Advanced inference
- [Lab 5.14 - Multi-Cloud RDMA](lab-5.15-rdma-multi-cloud.md) - EFA vs InfiniBand
- [Lab 5.15 - Distributed Training](lab-5.16-distributed-training.md) - Multi-node training
