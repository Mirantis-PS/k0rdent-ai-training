# Lab 5.1 - GPU Scheduler Deployment

---

## Lab Navigation

| Track | Tier | Duration |
|-------|------|----------|
| Foundation | Required | 3.5 hours |

### Week 5 Learning Paths

```
YOU ARE HERE
     ↓
FOUNDATION (Required)                         CHOOSE YOUR PATH
━━━━━━━━━━━━━━━━━━━━                         ━━━━━━━━━━━━━━━━
[5.1] ➔ 5.2 ➔ 5.3 ➔ 5.4 ➔ 5.5 ➔ 5.6    ──►  ML Platforms (5.9-5.12)
                                              Compliance (5.7-5.8)
                                              Advanced (5.13-5.15)
```

| Previous | Current | Next |
|----------|---------|------|
| [Week 5 Overview](../README.md) | **Lab 5.1 - GPU Scheduler** | [Lab 5.2 - vLLM Inference](lab-5.2-vllm-inference.md) |

---

**Duration:** 3.5 hours
**Type:** Hands-on Technical
**Environment:** GPU Lab

## Objective

Deploy and configure an advanced GPU scheduler for AI workloads on Kubernetes, enabling features like gang scheduling, fractional GPU allocation, priority queues, and topology-aware NCCL optimization that the default Kubernetes scheduler lacks.

## Prerequisites

- k0rdent-managed cluster with GPU nodes provisioned via `ClusterDeployment` (from Week 4)
- NVIDIA GPU Operator deployed as a ServiceTemplate from the [k0rdent catalog](https://catalog.k0rdent.io/) (see [GPU Operator Setup](#gpu-operator-via-k0rdent) below)
- At least 2 GPU nodes for scheduling demonstrations
- kubectl access to the managed cluster with cluster-admin privileges

> **k0rdent context:** This lab runs on a managed GPU cluster. The GPU Operator should already be deployed via `ClusterDeployment.spec.serviceSpec` or `MultiClusterService`, following the same pattern as cert-manager and ingress-nginx in [Lab 1.7](../../week-1-foundations/labs/lab-1.7-multicluster-services.md).

---

## Background: GPU Communication Architecture

### Understanding GPU Interconnects

Before deploying a GPU scheduler, it's essential to understand the hardware topology that influences scheduling decisions:

```
Multi-GPU Node Architecture (e.g., p4d.24xlarge, ND A100 v4):
┌─────────────────────────────────────────────────────────────────┐
│                        8-GPU Node                                │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│    ┌─────┐   NVSwitch    ┌─────┐   NVSwitch    ┌─────┐         │
│    │GPU 0│◄─────┬───────►│GPU 1│◄─────┬───────►│GPU 2│         │
│    └──┬──┘      │        └──┬──┘      │        └──┬──┘         │
│       │    600 GB/s        │    600 GB/s        │              │
│    ┌──▼──┐      │        ┌──▼──┐      │        ┌──▼──┐         │
│    │GPU 3│◄─────┴───────►│GPU 4│◄─────┴───────►│GPU 5│         │
│    └──┬──┘               └──┬──┘               └──┬──┘         │
│       │                     │                     │             │
│    ┌──▼──┐               ┌──▼──┐               ┌──▼──┐         │
│    │GPU 6│◄─────────────►│GPU 7│               │ ... │         │
│    └─────┘   NVSwitch    └─────┘               └─────┘         │
│                                                                 │
│    All GPUs connected via NVSwitch at 600-900 GB/s             │
│    (vs PCIe at 64 GB/s - 10x difference!)                      │
└─────────────────────────────────────────────────────────────────┘
```

### What is NCCL?

**NVIDIA Collective Communications Library (NCCL)** is the standard for GPU-to-GPU communication in distributed AI workloads. It automatically detects and utilizes:
- **NVLink/NVSwitch** for intra-node communication (600-900 GB/s)
- **RDMA/InfiniBand/EFA** for inter-node communication (200-400 Gb/s)
- **PCIe** as fallback (64 GB/s - avoid for AI workloads)

### Why NCCL Configuration Matters

| Communication Type | Bandwidth | Latency | Use Case |
|-------------------|-----------|---------|----------|
| NVLink (A100) | 600 GB/s | <1 us | Tensor parallelism |
| NVSwitch (H100) | 900 GB/s | <1 us | All-reduce within node |
| InfiniBand | 400 Gb/s | ~2 us | Pipeline parallelism |
| EFA (AWS) | 400 Gb/s | ~5 us | Data parallelism |
| PCIe 5.0 | 64 GB/s | ~10 us | **Avoid for multi-GPU** |
| TCP/Ethernet | 12.5 GB/s | ~50 us | **Never use for AI** |

**Key Insight:** A topology-unaware scheduler might place GPUs across PCIe instead of NVLink, reducing performance by 10x.

---

## Why Advanced GPU Schedulers?

The default Kubernetes scheduler has limitations for AI/ML workloads:

| Limitation | Impact | Solution |
|------------|--------|----------|
| No gang scheduling | Distributed training jobs start partially | KAI/Run:AI gang scheduler |
| Whole GPU allocation only | Waste resources on small workloads | Fractional GPU sharing |
| No topology awareness | Suboptimal NVLink utilization | Topology-aware scheduling |
| Basic priority only | No fair-share queuing | Queue-based scheduling |
| No preemption control | Long jobs block short ones | Priority preemption |

### Scheduler Options

| Scheduler | Use Case | License |
|-----------|----------|---------|
| **KAI Scheduler** | NVIDIA open-source GPU scheduler | Apache 2.0 |
| **Run:AI** | KAI core + enterprise UI, analytics | NVIDIA Commercial |
| **Volcano** | Batch/HPC workloads | Apache 2.0 |

This lab uses **KAI Scheduler** as the open-source option.

## Lab Environment

**Cluster Requirements:**
- k0rdent-managed cluster with 2+ GPU nodes (k0s distribution)
- GPU Operator v25.10.0+ deployed via k0rdent ServiceTemplate
- kubectl access to the managed cluster

### GPU Operator via k0rdent

If the GPU Operator is not yet deployed on your managed cluster, install the ServiceTemplate and attach it:

```bash
# On the management cluster: Install GPU Operator ServiceTemplate from catalog
# Uses the kgst (k0rdent Generic Service Template) meta-chart
helm upgrade --install gpu-operator \
  oci://ghcr.io/k0rdent/catalog/charts/kgst \
  --set "chart=gpu-operator:25.10.0" \
  -n kcm-system

# Verify the ServiceTemplate is available (name format: gpu-operator-25-10-0)
kubectl get servicetemplate -n kcm-system | grep gpu-operator
```

Then attach it to your managed cluster via `MultiClusterService` or by patching your `ClusterDeployment`:

```yaml
# Save as gpu-multicluster-service.yaml
apiVersion: k0rdent.mirantis.com/v1beta1
kind: MultiClusterService
metadata:
  name: gpu-operator
  namespace: kcm-system
spec:
  clusterSelector:
    matchLabels:
      gpu-enabled: "true"
  serviceSpec:
    services:
    - template: gpu-operator-25-10-0
      name: gpu-operator
      namespace: gpu-operator
      values: |
        toolkit:
          env:
            - name: CONTAINERD_CONFIG
              value: /etc/k0s/containerd.d/nvidia.toml
            - name: CONTAINERD_SOCKET
              value: /run/k0s/containerd.sock
            - name: CONTAINERD_RUNTIME_CLASS
              value: nvidia
```

> **k0s-specific:** Because k0rdent uses k0s as its Kubernetes distribution, the containerd paths differ from standard installations. The toolkit environment variables above are required for GPU Operator to correctly configure the NVIDIA container runtime on k0s nodes. See [NVIDIA k0rdent Partner Validation](https://docs.nvidia.com/datacenter/cloud-native/partner-validated/latest/k0rdent.html) for details.

```bash
# Apply and verify (on management cluster)
kubectl apply -f gpu-multicluster-service.yaml

# Switch to managed cluster context and verify GPU Operator pods
kubectl get pods -n gpu-operator
```

## Tasks

### Task 1: Verify GPU Environment (15 min)

1. **Check GPU Operator Status**
   ```bash
   # Verify GPU Operator pods
   kubectl get pods -n gpu-operator

   # Check GPU node labels
   kubectl get nodes -l nvidia.com/gpu.present=true -o wide

   # Verify GPU resources
   kubectl describe nodes | grep -A5 "Allocatable:" | grep nvidia
   ```

2. **Verify GPU Availability**
   ```bash
   # List allocatable GPUs per node
   kubectl get nodes -o custom-columns=\
   'NAME:.metadata.name,GPUs:.status.allocatable.nvidia\.com/gpu'
   ```

3. **Expected Output**
   ```
   NAME           GPUs
   gpu-node-1     1
   gpu-node-2     1
   ```

### Task 2: Deploy KAI Scheduler (45 min)

1. **Install KAI Scheduler from NVIDIA OCI Registry**

   KAI Scheduler is published as an OCI Helm chart by NVIDIA. Install directly from the GitHub Container Registry:

   ```bash
   # Create namespace
   kubectl create namespace kai-scheduler

   # Install KAI Scheduler (pin version for reproducibility)
   helm upgrade --install kai-scheduler \
     oci://ghcr.io/nvidia/kai-scheduler/kai-scheduler \
     --version 0.12.11 \
     --namespace kai-scheduler \
     --wait
   ```

   > **Alternative:** You can also install from NVIDIA NGC:
   > ```bash
   > helm repo add nvidia-k8s https://helm.ngc.nvidia.com/nvidia/k8s
   > helm repo update
   > helm install kai-scheduler nvidia-k8s/kai-scheduler \
   >   --namespace kai-scheduler --wait
   > ```

2. **Verify Installation**
   ```bash
   # Check scheduler pods
   kubectl get pods -n kai-scheduler

   # View scheduler logs
   kubectl logs -n kai-scheduler -l app=kai-scheduler --tail=50
   ```

3. **Expected Pod Status**
   ```
   NAME                            READY   STATUS    RESTARTS   AGE
   kai-scheduler-6d8f9b7c4-xxxxx   1/1     Running   0          2m
   kai-scheduler-6d8f9b7c4-yyyyy   1/1     Running   0          2m
   ```

### Task 3: Configure Scheduler Queues (30 min)

1. **Create Priority Classes**
   ```yaml
   # Save as priority-classes.yaml
   apiVersion: scheduling.k8s.io/v1
   kind: PriorityClass
   metadata:
     name: high-priority-gpu
   value: 1000000
   globalDefault: false
   description: "High priority GPU workloads - preempts lower priority"
   preemptionPolicy: PreemptLowerPriority
   ---
   apiVersion: scheduling.k8s.io/v1
   kind: PriorityClass
   metadata:
     name: normal-priority-gpu
   value: 100000
   globalDefault: false
   description: "Normal priority GPU workloads"
   preemptionPolicy: PreemptLowerPriority
   ---
   apiVersion: scheduling.k8s.io/v1
   kind: PriorityClass
   metadata:
     name: low-priority-gpu
   value: 10000
   globalDefault: false
   description: "Low priority GPU workloads - can be preempted"
   preemptionPolicy: Never
   ```

   ```bash
   kubectl apply -f priority-classes.yaml
   ```

2. **Create Resource Queues**

   KAI Scheduler uses the `scheduling.run.ai/v2` API group (inherited from its Run:AI origins):

   ```yaml
   # Save as gpu-queues.yaml
   apiVersion: scheduling.run.ai/v2
   kind: Queue
   metadata:
     name: training-queue
   spec:
     resources:
       gpu:
         quota: 8
         overQuotaWeight: 50
     priority: 100
   ---
   apiVersion: scheduling.run.ai/v2
   kind: Queue
   metadata:
     name: inference-queue
   spec:
     resources:
       gpu:
         quota: 4
         overQuotaWeight: 30
     priority: 150  # Higher priority for latency-sensitive inference
   ---
   apiVersion: scheduling.run.ai/v2
   kind: Queue
   metadata:
     name: dev-queue
   spec:
     resources:
       gpu:
         quota: 2
         overQuotaWeight: 20
     priority: 50
   ```

   ```bash
   kubectl apply -f gpu-queues.yaml
   ```

   > **Queue fields explained:**
   > - `quota`: Maximum GPU allocation for the queue
   > - `overQuotaWeight`: Relative weight when borrowing unused GPUs from other queues (higher = more share)
   > - `priority`: Scheduling priority when queues compete for the same resources

3. **Verify Queues**
   ```bash
   kubectl get queues -n kai-scheduler
   ```

### Task 4: Test Gang Scheduling (30 min)

Gang scheduling ensures all pods in a job start together or none start, critical for distributed training.

1. **Create Gang Scheduling Test Job**

   KAI Scheduler automatically detects pods belonging to the same Job and applies gang scheduling -- all pods start together or none start. Queue assignment uses a **label** (not annotation):

   ```yaml
   # Save as gang-test-job.yaml
   apiVersion: batch/v1
   kind: Job
   metadata:
     name: gang-test
     namespace: default
   spec:
     completions: 2
     parallelism: 2
     template:
       metadata:
         labels:
           kai.scheduler/queue: training-queue
       spec:
         schedulerName: kai-scheduler
         restartPolicy: Never
         containers:
           - name: gpu-worker
             image: nvidia/cuda:12.2.0-base-ubuntu22.04
             command: ["sh", "-c"]
             args:
               - |
                 echo "Worker started at $(date)"
                 nvidia-smi
                 sleep 60
                 echo "Worker completed at $(date)"
             resources:
               limits:
                 nvidia.com/gpu: 1
               requests:
                 nvidia.com/gpu: 1
                 memory: 4Gi
                 cpu: "2"
         tolerations:
           - key: nvidia.com/gpu
             operator: Exists
             effect: NoSchedule
   ```

   > **How it works:** KAI's PodGrouper automatically groups the 2 pods (parallelism: 2) into a gang. Both must be schedulable before either starts. No manual gang annotations required.

2. **Submit Gang Job**
   ```bash
   kubectl apply -f gang-test-job.yaml

   # Watch pod scheduling
   kubectl get pods -l job-name=gang-test -w
   ```

3. **Verify Gang Behavior**
   ```bash
   # Both pods should be scheduled simultaneously
   kubectl get pods -l job-name=gang-test -o wide

   # Check scheduler events
   kubectl get events --field-selector reason=Scheduled | grep gang-test
   ```

4. **Expected Behavior**
   - Both pods scheduled within seconds of each other
   - If only 1 GPU available, both pods remain Pending (gang constraint)
   - Scheduler logs show gang scheduling decision

5. **Clean Up**
   ```bash
   kubectl delete job gang-test
   ```

### Task 5: Test Priority Preemption (30 min)

> **Note:** This task demonstrates Kubernetes-native `PriorityClass` preemption, which works with KAI Scheduler independently of queue assignment. The pods below intentionally omit `kai.scheduler/queue` labels to show that priority preemption is a Kubernetes built-in feature that KAI Scheduler honors.

1. **Create Low Priority Workload**
   ```yaml
   # Save as low-priority-workload.yaml
   apiVersion: apps/v1
   kind: Deployment
   metadata:
     name: low-priority-gpu-workload
     namespace: default
   spec:
     replicas: 2
     selector:
       matchLabels:
         app: low-priority-gpu
     template:
       metadata:
         labels:
           app: low-priority-gpu
       spec:
         schedulerName: kai-scheduler
         priorityClassName: low-priority-gpu
         containers:
           - name: gpu-hog
             image: nvidia/cuda:12.2.0-base-ubuntu22.04
             command: ["sh", "-c", "while true; do nvidia-smi; sleep 30; done"]
             resources:
               limits:
                 nvidia.com/gpu: 1
               requests:
                 nvidia.com/gpu: 1
                 memory: 4Gi
                 cpu: "1"
         tolerations:
           - key: nvidia.com/gpu
             operator: Exists
             effect: NoSchedule
   ```

2. **Deploy Low Priority Workload**
   ```bash
   kubectl apply -f low-priority-workload.yaml

   # Wait for pods to be running
   kubectl get pods -l app=low-priority-gpu -w
   ```

3. **Create High Priority Workload**
   ```yaml
   # Save as high-priority-workload.yaml
   apiVersion: apps/v1
   kind: Deployment
   metadata:
     name: high-priority-gpu-workload
     namespace: default
   spec:
     replicas: 1
     selector:
       matchLabels:
         app: high-priority-gpu
     template:
       metadata:
         labels:
           app: high-priority-gpu
       spec:
         schedulerName: kai-scheduler
         priorityClassName: high-priority-gpu
         containers:
           - name: important-workload
             image: nvidia/cuda:12.2.0-base-ubuntu22.04
             command: ["sh", "-c", "nvidia-smi && sleep 120"]
             resources:
               limits:
                 nvidia.com/gpu: 1
               requests:
                 nvidia.com/gpu: 1
                 memory: 4Gi
                 cpu: "1"
         tolerations:
           - key: nvidia.com/gpu
             operator: Exists
             effect: NoSchedule
   ```

4. **Submit High Priority and Observe Preemption**
   ```bash
   kubectl apply -f high-priority-workload.yaml

   # Watch preemption happen
   kubectl get pods -l 'app in (low-priority-gpu,high-priority-gpu)' -w

   # Check events for preemption
   kubectl get events --sort-by='.lastTimestamp' | grep -E "Preempted|Scheduled"
   ```

5. **Expected Behavior**
   - High priority pod preempts one of the low priority pods
   - Low priority pod moves to Pending state
   - High priority pod gets scheduled on freed GPU

6. **Clean Up**
   ```bash
   kubectl delete deployment low-priority-gpu-workload high-priority-gpu-workload
   ```

### Task 6: Configure Fractional GPU Sharing (Optional - 20 min)

If your cluster supports GPU time-slicing or MIG:

1. **Enable Time-Slicing in GPU Operator**
   ```yaml
   # Save as time-slicing-config.yaml
   apiVersion: v1
   kind: ConfigMap
   metadata:
     name: time-slicing-config
     namespace: gpu-operator
   data:
     any: |-
       version: v1
       sharing:
         timeSlicing:
           renameByDefault: false
           resources:
             - name: nvidia.com/gpu
               replicas: 4
   ```

   ```bash
   kubectl apply -f time-slicing-config.yaml

   # Update ClusterPolicy to use time-slicing
   kubectl patch clusterpolicy/cluster-policy \
     --type merge \
     --patch '{"spec": {"devicePlugin": {"config": {"name": "time-slicing-config"}}}}'
   ```

2. **Verify Fractional GPUs**
   ```bash
   # After GPU Operator reconciles (may take 2-3 minutes)
   kubectl describe nodes | grep -A5 "Allocatable:" | grep nvidia

   # Should show 4x the physical GPU count
   ```

### Task 7: Configure Enterprise NCCL Settings (30 min)

Proper NCCL configuration is critical for multi-GPU workloads. This task creates a standardized configuration for AI workloads.

1. **Verify GPU Topology**

   Before configuring NCCL, understand your node's topology:

   ```bash
   # SSH to a GPU node or exec into a GPU pod
   nvidia-smi topo -m
   ```

   **Expected output for 8-GPU NVSwitch node:**

   For **A100 nodes** (e.g., p4d.24xlarge, 12 NVLinks per GPU):
   ```
           GPU0  GPU1  GPU2  GPU3  GPU4  GPU5  GPU6  GPU7  NIC0  CPU
   GPU0     X    NV12  NV12  NV12  NV12  NV12  NV12  NV12  SYS   SYS
   GPU1    NV12   X    NV12  NV12  NV12  NV12  NV12  NV12  SYS   SYS
   ...
   ```

   For **H100 nodes** (e.g., p5.48xlarge, 18 NVLinks per GPU):
   ```
           GPU0  GPU1  GPU2  GPU3  GPU4  GPU5  GPU6  GPU7  NIC0  CPU
   GPU0     X    NV18  NV18  NV18  NV18  NV18  NV18  NV18  SYS   SYS
   GPU1    NV18   X    NV18  NV18  NV18  NV18  NV18  NV18  SYS   SYS
   ...
   ```

   **Legend:**
   - `NV#` = Number of NVLink connections (NV12 = A100 @ 600 GB/s, NV18 = H100 @ 900 GB/s)
   - `SYS` = System/PCIe connection (avoid for multi-GPU)
   - `PHB` = PCIe Host Bridge

2. **Create NCCL Configuration ConfigMap**

   ```yaml
   # Save as nccl-enterprise-config.yaml
   apiVersion: v1
   kind: ConfigMap
   metadata:
     name: nccl-enterprise-config
     namespace: default
   data:
     # ===== Core NCCL Settings =====
     # Debug level (WARN for production, INFO for troubleshooting)
     NCCL_DEBUG: "WARN"

     # Enable all debug subsystems when troubleshooting
     # NCCL_DEBUG_SUBSYS: "INIT,COLL,P2P,NET,GRAPH,TUNING"

     # ===== P2P (Peer-to-Peer) Configuration =====
     # Force NVLink usage for P2P communication
     NCCL_P2P_LEVEL: "NVL"

     # Disable P2P entirely (use only if NVLink causing issues)
     # NCCL_P2P_DISABLE: "0"

     # ===== RDMA/GPUDirect Configuration =====
     # Enable GPUDirect RDMA (valid: LOC, PIX, PXB, PHB, SYS)
     # SYS = allow GDR across any system path (maximum reach)
     NCCL_NET_GDR_LEVEL: "SYS"

     # For AWS EFA
     # FI_EFA_USE_DEVICE_RDMA: "1"
     # FI_PROVIDER: "efa"

     # For Azure InfiniBand
     NCCL_IB_DISABLE: "0"
     # Prefix match: "mlx5" matches all mlx5_* devices.
     # Use "=mlx5_0" for exact match of a single device.
     NCCL_IB_HCA: "mlx5"

     # ===== Performance Tuning =====
     # Buffer size for NCCL operations (default 4MB, increase for large models)
     NCCL_BUFFSIZE: "8388608"

     # Number of CUDA threads for NCCL kernels
     NCCL_NTHREADS: "512"

     # Socket threads for TCP fallback (not usually needed with RDMA)
     NCCL_SOCKET_NTHREADS: "4"
     NCCL_NSOCKS_PERTHREAD: "4"

     # ===== Algorithm Selection =====
     # Tree algorithm threshold (0 = always use tree, good for many nodes)
     NCCL_TREE_THRESHOLD: "0"

     # Minimum rings for ring algorithm (legacy; NCCL_MIN_CTAS in NCCL 2.18+)
     NCCL_MIN_NRINGS: "4"

     # ===== CUDA Optimization =====
     # Max CUDA streams: 1 for Megatron Tensor/Sequence Parallelism.
     # Do NOT set to 1 for FSDP workloads. Remove or increase for FSDP.
     CUDA_DEVICE_MAX_CONNECTIONS: "1"
   ```

   ```bash
   kubectl apply -f nccl-enterprise-config.yaml
   ```

3. **Create NCCL Test Deployment**

   Test the NCCL configuration with a multi-GPU workload:

   > **Note:** NCCL performance tests must be built from source or use a dedicated test image. The standard PyTorch NGC container does NOT include pre-built NCCL tests.

   ```yaml
   # Save as nccl-config-test.yaml
   apiVersion: v1
   kind: Pod
   metadata:
     name: nccl-config-test
     namespace: default
   spec:
     restartPolicy: Never
     containers:
       - name: nccl-test
         image: nvcr.io/nvidia/pytorch:24.12-py3
         command: ["bash", "-c"]
         args:
           - |
             echo "=== NCCL Environment Variables ==="
             env | grep -E "^NCCL|^FI_|^CUDA" | sort

             echo ""
             echo "=== GPU Topology ==="
             nvidia-smi topo -m

             echo ""
             echo "=== Building NCCL Tests ==="
             apt-get update && apt-get install -y build-essential
             cd /tmp
             git clone https://github.com/NVIDIA/nccl-tests.git
             cd nccl-tests
             make MPI=0 CUDA_HOME=/usr/local/cuda NCCL_HOME=/usr/lib/x86_64-linux-gnu
             echo "Build complete."

             echo ""
             echo "=== Running NCCL All-Reduce Test ==="
             GPU_COUNT=$(nvidia-smi -L | wc -l)
             echo "Detected $GPU_COUNT GPUs"
             ./build/all_reduce_perf -b 1M -e 1G -f 2 -g $GPU_COUNT

             echo ""
             echo "=== Test Complete ==="
         envFrom:
           - configMapRef:
               name: nccl-enterprise-config
         resources:
           limits:
             nvidia.com/gpu: 4
           requests:
             nvidia.com/gpu: 4
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
           sizeLimit: 16Gi
     tolerations:
       - key: nvidia.com/gpu
         operator: Exists
         effect: NoSchedule
   ```

   > **Tip:** For faster iteration, pre-build NCCL tests into a custom container image rather than building at runtime. See [NVIDIA nccl-tests](https://github.com/NVIDIA/nccl-tests) for Dockerfile examples.

   ```bash
   kubectl apply -f nccl-config-test.yaml

   # Watch the test
   kubectl logs -f nccl-config-test
   ```

4. **Interpret NCCL Test Results**

   Look for these indicators in the output:

   ```
   # Good - NVLink being used:
   NCCL INFO P2P using NVLINK

   # Good - High bus bandwidth (600+ GB/s for 4 GPUs):
   #       busbw: 650.23 GB/s

   # Bad - PCIe fallback:
   NCCL WARN P2P not available between GPU 0 and GPU 1

   # Bad - TCP fallback:
   NCCL INFO NET/Socket : Using [0]eth0
   ```

5. **NCCL Configuration for Different Scenarios**

   | Scenario | Key Settings |
   |----------|--------------|
   | **Single-node, NVLink** | `NCCL_P2P_LEVEL=NVL` |
   | **Multi-node, InfiniBand** | `NCCL_IB_DISABLE=0`, `NCCL_NET_GDR_LEVEL=SYS` |
   | **Multi-node, AWS EFA** | `FI_EFA_USE_DEVICE_RDMA=1`, `FI_PROVIDER=efa` |
   | **Debugging connectivity** | `NCCL_DEBUG=INFO`, `NCCL_DEBUG_SUBSYS=INIT,NET` |
   | **Maximum performance** | `NCCL_BUFFSIZE=8388608`, `NCCL_NTHREADS=512` |

6. **Clean Up Test Pod**
   ```bash
   kubectl delete pod nccl-config-test
   ```

### Task 8: Monitor Scheduler Metrics (15 min)

1. **Access Scheduler Metrics**
   ```bash
   # Port forward to scheduler metrics
   kubectl port-forward -n kai-scheduler svc/kai-scheduler-metrics 8080:8080 &

   # Fetch metrics
   curl http://localhost:8080/metrics | grep kai_
   ```

2. **Key Metrics to Monitor**
   ```
   # Scheduling latency
   kai_scheduling_duration_seconds_bucket

   # Queue depth
   kai_queue_pending_pods

   # Preemption counts
   kai_preemption_total

   # Gang scheduling success rate
   kai_gang_scheduling_success_total
   ```

3. **Create Scheduler Dashboard (Optional)**
   ```yaml
   # If Grafana is available, import dashboard
   # Metrics provide insight into:
   # - Scheduling latency distribution
   # - Queue utilization
   # - Preemption frequency
   # - GPU allocation efficiency
   ```

## Deliverables

### Basic Deliverables
- [ ] **Screenshot** of KAI scheduler pods running
- [ ] **Queue configuration** YAML files
- [ ] **Gang scheduling test results** showing both pods scheduled together
- [ ] **Preemption demo** showing high priority preempting low priority
- [ ] **Scheduler metrics output** from `/metrics` endpoint

### NCCL Configuration Deliverables
- [ ] **GPU topology output** (`nvidia-smi topo -m`)
- [ ] **NCCL enterprise ConfigMap** deployed
- [ ] **NCCL test results** showing NVLink utilization
- [ ] **Bus bandwidth measurement** (should be 500+ GB/s for 4 GPUs)
- [ ] **Documentation** of NCCL settings for your environment

## Verification Checklist

### Scheduler
- [ ] KAI scheduler deployed and running
- [ ] Priority classes created
- [ ] Resource queues configured
- [ ] Gang scheduling working correctly
- [ ] Priority preemption functioning
- [ ] Scheduler metrics accessible

### NCCL/GPU Communication
- [ ] GPU topology verified (NVLink connections visible)
- [ ] NCCL ConfigMap applied correctly
- [ ] NCCL test shows `P2P using NVLINK` (not PCIe)
- [ ] Bus bandwidth >500 GB/s (4 GPUs) or >800 GB/s (8 GPUs)
- [ ] No TCP fallback warnings in NCCL output

## Troubleshooting

### Scheduler Pods Not Starting

**Check RBAC permissions:**
```bash
kubectl get clusterrolebinding | grep kai
kubectl describe clusterrolebinding kai-scheduler
```

**Check scheduler logs:**
```bash
kubectl logs -n kai-scheduler -l app=kai-scheduler --previous
```

### Pods Not Using Custom Scheduler

**Verify schedulerName field:**
```bash
kubectl get pod <pod-name> -o jsonpath='{.spec.schedulerName}'
# Must be: kai-scheduler
```

### Gang Scheduling Not Working

**Verify queue label is set:**
```bash
kubectl get pod <pod-name> -o yaml | grep -A5 labels
# Must have kai.scheduler/queue: "<queue-name>"
```

**Check the PodGroup was created:**
```bash
kubectl get podgroups
# KAI auto-creates PodGroups for Jobs with parallelism > 1
```

**Check scheduler logs for gang decisions:**
```bash
kubectl logs -n kai-scheduler -l app=kai-scheduler | grep -i gang
```

### Preemption Not Happening

**Verify priority class assignment:**
```bash
kubectl get pod <pod-name> -o jsonpath='{.spec.priorityClassName}'
```

**Check preemption policy:**
```bash
kubectl get priorityclass high-priority-gpu -o yaml
# preemptionPolicy should be PreemptLowerPriority
```

## Key Takeaways

### GPU Scheduling
1. **Default Kubernetes scheduler lacks GPU-aware features** needed for AI/ML workloads
2. **Gang scheduling prevents partial job starts** that waste resources in distributed training
3. **Priority classes and queues enable fair resource sharing** across teams
4. **Preemption ensures critical workloads get resources** when needed
5. **Fractional GPU sharing** maximizes utilization for small workloads

### NCCL and GPU Communication
6. **NVLink provides 10x bandwidth over PCIe** - topology-aware scheduling is essential
7. **NCCL environment variables control GPU communication paths** - misconfiguration causes 10x performance loss
8. **Always verify GPU topology** before deploying multi-GPU workloads
9. **RDMA/GPUDirect configuration differs by platform** - AWS EFA vs Azure InfiniBand have different settings
10. **Test NCCL before production** - bus bandwidth should be 500+ GB/s for 4 GPUs

### Operations
11. **Always pin scheduler versions** in production for stability
12. **Monitor scheduler metrics** to understand resource utilization patterns
13. **Use NCCL_DEBUG=INFO** when troubleshooting communication issues

---

## References

### NVIDIA
- [KAI Scheduler GitHub](https://github.com/NVIDIA/KAI-Scheduler)
- [KAI Scheduler on NGC](https://catalog.ngc.nvidia.com/orgs/nvidia/teams/k8s/helm-charts/kai-scheduler)
- [NVIDIA Open Sources Run:AI Scheduler](https://developer.nvidia.com/blog/nvidia-open-sources-runai-scheduler-to-foster-community-collaboration/)
- [NCCL Environment Variables](https://docs.nvidia.com/deeplearning/nccl/user-guide/docs/env.html)
- [GPU Operator Documentation](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/)
- [GPU Operator - k0rdent Partner Validation](https://docs.nvidia.com/datacenter/cloud-native/partner-validated/latest/k0rdent.html)
- [NCCL Tests GitHub](https://github.com/NVIDIA/nccl-tests)

### k0rdent
- [k0rdent Service Catalog](https://catalog.k0rdent.io/)
- [k0rdent Documentation](https://docs.k0rdent.io/)
- [ServiceTemplate Reference](https://docs.k0rdent.io/latest/admin/ksm/ksm-service-templates/)

### Kubernetes
- [Volcano Scheduler](https://volcano.sh/)
- [Priority and Preemption](https://kubernetes.io/docs/concepts/scheduling-eviction/pod-priority-preemption/)

---

## Next Lab

Proceed to [Lab 5.2 - vLLM Inference Service](lab-5.2-vllm-inference.md)
