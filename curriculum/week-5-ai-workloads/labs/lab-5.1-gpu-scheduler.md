# Lab 5.1 - GPU Scheduler Deployment

**Duration:** 3.5 hours
**Type:** Hands-on Technical
**Environment:** GPU Lab

## Objective

Deploy and configure an advanced GPU scheduler for AI workloads on Kubernetes, enabling features like gang scheduling, fractional GPU allocation, priority queues, and topology-aware NCCL optimization that the default Kubernetes scheduler lacks.

## Prerequisites

- Kubernetes cluster with GPU nodes (from Week 4)
- NVIDIA GPU Operator installed and functional
- At least 2 GPU nodes for scheduling demonstrations
- kubectl access with cluster-admin privileges

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
| **KAI Scheduler** | Open-source, Kubernetes-native | Apache 2.0 |
| **Run:AI** | Enterprise features, GUI | Commercial |
| **Volcano** | Batch/HPC workloads | Apache 2.0 |

This lab uses **KAI Scheduler** as the open-source option.

## Lab Environment

**Cluster Requirements:**
- 2+ GPU nodes with NVIDIA GPUs
- GPU Operator v25.10.0+ installed
- Cluster API or direct kubectl access

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

1. **Add KAI Helm Repository**
   ```bash
   helm repo add kai https://project-codeflare.github.io/kai-scheduler
   helm repo update
   ```

2. **Create Scheduler Namespace**
   ```bash
   kubectl create namespace kai-scheduler
   ```

3. **Create Scheduler Configuration**
   ```yaml
   # Save as kai-values.yaml
   scheduler:
     replicaCount: 2
     resources:
       requests:
         cpu: 500m
         memory: 512Mi
       limits:
         cpu: 1000m
         memory: 1Gi

   # Enable gang scheduling
   gangScheduling:
     enabled: true

   # Enable GPU topology awareness
   topologyAwareness:
     enabled: true

   # Configure default queue
   queues:
     default:
       weight: 1
       priority: 100

   # Prometheus metrics
   metrics:
     enabled: true
     serviceMonitor:
       enabled: false  # Enable if Prometheus Operator installed
   ```

4. **Install KAI Scheduler**
   ```bash
   helm install kai-scheduler kai/kai-scheduler \
     --namespace kai-scheduler \
     --values kai-values.yaml \
     --wait
   ```

5. **Verify Installation**
   ```bash
   # Check scheduler pods
   kubectl get pods -n kai-scheduler

   # View scheduler logs
   kubectl logs -n kai-scheduler -l app=kai-scheduler --tail=50
   ```

6. **Expected Pod Status**
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
   ```yaml
   # Save as gpu-queues.yaml
   apiVersion: kai.io/v1alpha1
   kind: Queue
   metadata:
     name: training-queue
     namespace: kai-scheduler
   spec:
     weight: 50
     priority: 100
     resources:
       gpu:
         min: 1
         max: 8
       cpu:
         min: 4
         max: 64
       memory:
         min: 16Gi
         max: 256Gi
   ---
   apiVersion: kai.io/v1alpha1
   kind: Queue
   metadata:
     name: inference-queue
     namespace: kai-scheduler
   spec:
     weight: 30
     priority: 150  # Higher priority for latency-sensitive inference
     resources:
       gpu:
         min: 1
         max: 4
       cpu:
         min: 2
         max: 16
       memory:
         min: 8Gi
         max: 64Gi
   ---
   apiVersion: kai.io/v1alpha1
   kind: Queue
   metadata:
     name: dev-queue
     namespace: kai-scheduler
   spec:
     weight: 20
     priority: 50
     resources:
       gpu:
         min: 0
         max: 2
       cpu:
         min: 1
         max: 8
       memory:
         min: 4Gi
         max: 32Gi
   ```

   ```bash
   kubectl apply -f gpu-queues.yaml
   ```

3. **Verify Queues**
   ```bash
   kubectl get queues -n kai-scheduler
   ```

### Task 4: Test Gang Scheduling (30 min)

Gang scheduling ensures all pods in a job start together or none start, critical for distributed training.

1. **Create Gang Scheduling Test Job**
   ```yaml
   # Save as gang-test-job.yaml
   apiVersion: batch/v1
   kind: Job
   metadata:
     name: gang-test
     namespace: default
     annotations:
       kai.io/gang-scheduling: "true"
       kai.io/gang-size: "2"
       kai.io/queue: "training-queue"
   spec:
     completions: 2
     parallelism: 2
     template:
       metadata:
         annotations:
           kai.io/gang-scheduling: "true"
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
   ```
           GPU0  GPU1  GPU2  GPU3  GPU4  GPU5  GPU6  GPU7  NIC0  CPU
   GPU0     X    NV12  NV12  NV12  NV12  NV12  NV12  NV12  SYS   SYS
   GPU1    NV12   X    NV12  NV12  NV12  NV12  NV12  NV12  SYS   SYS
   ...
   ```

   **Legend:**
   - `NV#` = NVLink connection (NV12 = 12 NVLinks = NVSwitch full-mesh)
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
     # Enable GPUDirect RDMA (0=disable, 5=full)
     NCCL_NET_GDR_LEVEL: "5"

     # For AWS EFA
     # FI_EFA_USE_DEVICE_RDMA: "1"
     # FI_PROVIDER: "efa"

     # For Azure InfiniBand
     NCCL_IB_DISABLE: "0"
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

     # Minimum rings for ring algorithm
     NCCL_MIN_NRINGS: "4"

     # ===== CUDA Optimization =====
     # Max CUDA streams (1 for Megatron async, higher for other frameworks)
     CUDA_DEVICE_MAX_CONNECTIONS: "1"
   ```

   ```bash
   kubectl apply -f nccl-enterprise-config.yaml
   ```

3. **Create NCCL Test Deployment**

   Test the NCCL configuration with a multi-GPU workload:

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
             echo "=== Running NCCL All-Reduce Test ==="
             cd /opt/nccl-tests/build
             ./all_reduce_perf -b 1M -e 1G -f 2 -g 4

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
   | **Multi-node, InfiniBand** | `NCCL_IB_DISABLE=0`, `NCCL_NET_GDR_LEVEL=5` |
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

**Check gang annotations:**
```bash
kubectl get pod <pod-name> -o yaml | grep -A5 annotations
# Must have kai.io/gang-scheduling: "true"
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
- [NCCL Environment Variables](https://docs.nvidia.com/deeplearning/nccl/user-guide/docs/env.html)
- [GPU Operator Documentation](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/)
- [NCCL Tests GitHub](https://github.com/NVIDIA/nccl-tests)

### Kubernetes
- [KAI Scheduler](https://github.com/project-codeflare/kai-scheduler)
- [Volcano Scheduler](https://volcano.sh/)
- [Priority and Preemption](https://kubernetes.io/docs/concepts/scheduling-eviction/pod-priority-preemption/)

---

## Next Lab

Proceed to [Lab 5.2 - vLLM Inference Service](lab-5.2-vllm-inference.md)
