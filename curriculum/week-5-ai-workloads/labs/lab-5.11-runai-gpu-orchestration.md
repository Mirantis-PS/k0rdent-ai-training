# Lab 5.11 - Run:AI GPU Orchestration

---

## Lab Navigation

| Track | Tier | Duration |
|-------|------|----------|
| ML Platforms | Recommended | 3 hours |

### Week 5 Learning Paths

```
FOUNDATION (Required)                         ML PLATFORMS
━━━━━━━━━━━━━━━━━━━━                         ━━━━━━━━━━━━
5.1 ➔ 5.2 ➔ 5.3 ➔ 5.4 ➔ 5.5 ➔ 5.6          5.9 Kubeflow
                                                  ↓
                                              5.10 MLflow
                                                  ↓
                                             YOU ARE HERE
                                                  ↓
                                             [5.11] Run:AI
                                                  ↓
                                              5.12 Slurm ➔ Week 6
```

| Previous | Current | Next |
|----------|---------|------|
| [Lab 5.10 - MLflow](lab-5.10-mlflow-experiment-tracking.md) | **Lab 5.11 - Run:AI** | [Lab 5.12 - Slurm](lab-5.12-slurm-operator-hpc.md) |

---

**Duration:** 3 hours
**Type:** Hands-on Technical
**Environment:** GPU Lab

## Objective

Deploy and configure NVIDIA Run:AI (KAI Scheduler) for advanced GPU orchestration, including fractional GPU allocation, workload prioritization, quota management, and multi-tenant GPU sharing.

## Prerequisites

- Completed Lab 5.1 (GPU Scheduler deployed)
- Kubernetes cluster with 2+ GPU nodes
- NVIDIA GPU Operator v25.10.0 installed
- kubectl and helm installed
- Understanding of Kubernetes scheduling concepts

## Background

### What is Run:AI?

NVIDIA Run:AI is a Kubernetes-native AI orchestration platform that optimizes GPU utilization and enforces governance for AI/ML workloads. In 2025, NVIDIA open-sourced the Run:AI Scheduler (now called KAI Scheduler), making advanced GPU scheduling accessible to everyone.

**Key Features:**
- **Fractional GPUs**: Run multiple workloads on a single GPU
- **GPU Quotas**: Fair-share and guaranteed resource allocation
- **Workload Prioritization**: Training vs inference scheduling policies
- **Bin Packing**: Optimal GPU utilization across nodes
- **Gang Scheduling**: All-or-nothing scheduling for distributed training
- **Preemption**: Priority-based workload management

### Architecture Overview

```
┌────────────────────────────────────────────────────────────────┐
│                     Run:AI Control Plane                       │
├──────────────────────────────────────────────────────────────────┤
│  ┌──────────────┐  ┌──────────────┐  ┌───────────────────┐     │
│  │  Scheduler   │  │   Quotas &   │  │    Workload       │     │
│  │   (KAI)      │  │   Fairness   │  │    Management     │     │
│  └──────────────┘  └──────────────┘  └───────────────────┘     │
├──────────────────────────────────────────────────────────────────┤
│                    Kubernetes API Server                         │
├──────────────────────────────────────────────────────────────────┤
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐        │
│  │  GPU 0   │  │  GPU 1   │  │  GPU 2   │  │  GPU 3   │        │
│  │ (Frac)   │  │ (Frac)   │  │ (Full)   │  │ (Full)   │        │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘        │
└──────────────────────────────────────────────────────────────────┘
```

## Lab Environment

**Cluster Requirements:**
- Kubernetes 1.28+ with 2+ GPU nodes
- NVIDIA GPU Operator v25.10.0 installed
- 4+ GPUs total across nodes
- Helm 3.x installed

## Tasks

### Task 1: Install KAI Scheduler (Open-Source Run:AI) (30 min)

1. **Add Helm Repository**
   ```bash
   helm repo add runai https://run-ai.github.io/public-helm-charts
   helm repo update
   ```

2. **Create Namespace**
   ```bash
   kubectl create namespace runai-system
   ```

3. **Install KAI Scheduler**
   ```bash
   # Install the open-source KAI Scheduler
   helm install kai-scheduler runai/kai-scheduler \
     --namespace runai-system \
     --set scheduler.resources.requests.cpu=500m \
     --set scheduler.resources.requests.memory=512Mi \
     --wait
   ```

4. **Verify Installation**
   ```bash
   # Check scheduler pods
   kubectl get pods -n runai-system

   # Verify scheduler is running
   kubectl logs -n runai-system -l app=kai-scheduler --tail=20

   # Check scheduler configuration
   kubectl get configmap -n runai-system kai-scheduler-config -o yaml
   ```

5. **Label Nodes for GPU Scheduling**
   ```bash
   # Label GPU nodes
   kubectl get nodes -l nvidia.com/gpu.present=true -o name | \
     xargs -I {} kubectl label {} runai.node-type=gpu --overwrite
   ```

### Task 2: Configure GPU Quotas and Projects (25 min)

1. **Create Project (Tenant) CRDs**
   ```yaml
   # Save as runai-projects.yaml
   apiVersion: v1
   kind: Namespace
   metadata:
     name: team-training
     labels:
       runai/queue: training
   ---
   apiVersion: v1
   kind: Namespace
   metadata:
     name: team-inference
     labels:
       runai/queue: inference
   ---
   apiVersion: v1
   kind: Namespace
   metadata:
     name: team-research
     labels:
       runai/queue: research
   ```

2. **Apply Projects**
   ```bash
   kubectl apply -f runai-projects.yaml
   ```

3. **Create ResourceQuotas with GPU Limits**
   ```yaml
   # Save as gpu-quotas.yaml
   apiVersion: v1
   kind: ResourceQuota
   metadata:
     name: training-quota
     namespace: team-training
   spec:
     hard:
       requests.nvidia.com/gpu: "4"
       limits.nvidia.com/gpu: "4"
       requests.cpu: "16"
       limits.cpu: "32"
       requests.memory: 64Gi
       limits.memory: 128Gi
       pods: "20"
   ---
   apiVersion: v1
   kind: ResourceQuota
   metadata:
     name: inference-quota
     namespace: team-inference
   spec:
     hard:
       requests.nvidia.com/gpu: "2"
       limits.nvidia.com/gpu: "2"
       requests.cpu: "8"
       limits.cpu: "16"
       requests.memory: 32Gi
       limits.memory: 64Gi
       pods: "50"
   ---
   apiVersion: v1
   kind: ResourceQuota
   metadata:
     name: research-quota
     namespace: team-research
   spec:
     hard:
       requests.nvidia.com/gpu: "2"
       limits.nvidia.com/gpu: "2"
       requests.cpu: "8"
       limits.cpu: "16"
       requests.memory: 32Gi
       limits.memory: 64Gi
       pods: "10"
   ```

4. **Apply Quotas**
   ```bash
   kubectl apply -f gpu-quotas.yaml

   # Verify quotas
   kubectl get resourcequotas -A | grep -E "training|inference|research"
   ```

### Task 3: Configure Fractional GPU Sharing (30 min)

1. **Enable GPU Sharing with Time-Slicing**
   ```yaml
   # Save as gpu-sharing-config.yaml
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
           failRequestsGreaterThanOne: false
           resources:
             - name: nvidia.com/gpu
               replicas: 4
   ```

2. **Apply GPU Sharing Configuration**
   ```bash
   kubectl apply -f gpu-sharing-config.yaml

   # Patch GPU Operator to use time-slicing
   kubectl patch clusterpolicies.nvidia.com/cluster-policy \
     -n gpu-operator \
     --type merge \
     -p '{"spec": {"devicePlugin": {"config": {"name": "time-slicing-config", "default": "any"}}}}'

   # Wait for device plugin restart
   kubectl rollout status daemonset/nvidia-device-plugin-daemonset -n gpu-operator
   ```

3. **Verify GPU Replicas**
   ```bash
   # Check node capacity (should show 4x replicas per physical GPU)
   kubectl get nodes -o json | jq '.items[].status.allocatable | select(."nvidia.com/gpu" != null)'
   ```

4. **Test Fractional GPU Allocation**
   ```yaml
   # Save as fractional-gpu-test.yaml
   apiVersion: v1
   kind: Pod
   metadata:
     name: fractional-gpu-test-1
     namespace: team-research
   spec:
     schedulerName: kai-scheduler
     containers:
       - name: cuda-test
         image: nvcr.io/nvidia/cuda:12.6.0-base-ubi9
         command: ["nvidia-smi", "-l", "10"]
         resources:
           limits:
             nvidia.com/gpu: 1  # Gets 1/4 of physical GPU
   ---
   apiVersion: v1
   kind: Pod
   metadata:
     name: fractional-gpu-test-2
     namespace: team-research
   spec:
     schedulerName: kai-scheduler
     containers:
       - name: cuda-test
         image: nvcr.io/nvidia/cuda:12.6.0-base-ubi9
         command: ["nvidia-smi", "-l", "10"]
         resources:
           limits:
             nvidia.com/gpu: 1  # Gets 1/4 of physical GPU (same physical GPU)
   ```

5. **Deploy and Verify**
   ```bash
   kubectl apply -f fractional-gpu-test.yaml

   # Both pods should schedule on same physical GPU
   kubectl get pods -n team-research -o wide

   # Check GPU memory usage (shared)
   kubectl exec -n team-research fractional-gpu-test-1 -- nvidia-smi
   ```

### Task 4: Implement Priority-Based Scheduling (25 min)

1. **Create PriorityClasses**
   ```yaml
   # Save as priority-classes.yaml
   apiVersion: scheduling.k8s.io/v1
   kind: PriorityClass
   metadata:
     name: training-high
   value: 1000000
   globalDefault: false
   description: "High priority for training jobs"
   preemptionPolicy: PreemptLowerPriority
   ---
   apiVersion: scheduling.k8s.io/v1
   kind: PriorityClass
   metadata:
     name: training-normal
   value: 500000
   globalDefault: false
   description: "Normal priority for training jobs"
   preemptionPolicy: PreemptLowerPriority
   ---
   apiVersion: scheduling.k8s.io/v1
   kind: PriorityClass
   metadata:
     name: inference-critical
   value: 2000000
   globalDefault: false
   description: "Critical priority for inference (never preempted)"
   preemptionPolicy: Never
   ---
   apiVersion: scheduling.k8s.io/v1
   kind: PriorityClass
   metadata:
     name: research-low
   value: 100000
   globalDefault: true
   description: "Low priority for research/experimentation"
   preemptionPolicy: PreemptLowerPriority
   ```

2. **Apply PriorityClasses**
   ```bash
   kubectl apply -f priority-classes.yaml

   # Verify
   kubectl get priorityclasses
   ```

3. **Test Priority Preemption**
   ```yaml
   # Save as priority-test.yaml
   # First, fill GPU capacity with low-priority pods
   apiVersion: batch/v1
   kind: Job
   metadata:
     name: low-priority-job
     namespace: team-research
   spec:
     parallelism: 4
     template:
       spec:
         schedulerName: kai-scheduler
         priorityClassName: research-low
         containers:
           - name: gpu-hog
             image: nvcr.io/nvidia/cuda:12.6.0-base-ubi9
             command: ["sleep", "3600"]
             resources:
               limits:
                 nvidia.com/gpu: 1
         restartPolicy: Never
   ---
   # Then submit high-priority job that should preempt
   apiVersion: batch/v1
   kind: Job
   metadata:
     name: high-priority-job
     namespace: team-training
   spec:
     template:
       spec:
         schedulerName: kai-scheduler
         priorityClassName: training-high
         containers:
           - name: important-training
             image: nvcr.io/nvidia/cuda:12.6.0-base-ubi9
             command:
               - /bin/sh
               - -c
               - |
                 echo "High priority training started!"
                 nvidia-smi
                 sleep 60
                 echo "Training complete!"
             resources:
               limits:
                 nvidia.com/gpu: 2
         restartPolicy: Never
   ```

4. **Observe Preemption**
   ```bash
   # Apply low priority first
   kubectl apply -f priority-test.yaml

   # Watch for preemption events
   kubectl get events -n team-research --sort-by='.lastTimestamp' | tail -20
   kubectl get events -n team-training --sort-by='.lastTimestamp' | tail -20

   # Check pod status
   kubectl get pods -A -l job-name -o wide
   ```

### Task 5: Configure Gang Scheduling for Distributed Training (30 min)

1. **Install Volcano Scheduler (for Gang Scheduling)**
   ```bash
   # Volcano provides gang scheduling capabilities
   kubectl apply -f https://raw.githubusercontent.com/volcano-sh/volcano/release-1.9/installer/volcano-development.yaml

   # Wait for Volcano
   kubectl wait --for=condition=Ready pods -l app=volcano-scheduler -n volcano-system --timeout=300s
   ```

2. **Create Gang Scheduling Queue**
   ```yaml
   # Save as volcano-queue.yaml
   apiVersion: scheduling.volcano.sh/v1beta1
   kind: Queue
   metadata:
     name: training-queue
   spec:
     weight: 1
     reclaimable: true
     capability:
       cpu: 32
       memory: 128Gi
       nvidia.com/gpu: 8
   ```

3. **Create Distributed Training Job with Gang Scheduling**
   ```yaml
   # Save as gang-training-job.yaml
   apiVersion: batch.volcano.sh/v1alpha1
   kind: Job
   metadata:
     name: distributed-training
     namespace: team-training
   spec:
     schedulerName: volcano
     minAvailable: 4  # All 4 pods must be scheduled together
     queue: training-queue
     policies:
       - event: PodEvicted
         action: RestartJob
     plugins:
       env: []
       svc: []
     tasks:
       - replicas: 4
         name: worker
         template:
           spec:
             containers:
               - name: pytorch-worker
                 image: pytorch/pytorch:2.1.0-cuda12.1-cudnn8-runtime
                 command:
                   - python
                   - -c
                   - |
                     import torch
                     import torch.distributed as dist
                     import os

                     # Volcano sets these environment variables
                     world_size = int(os.environ.get('WORLD_SIZE', 4))
                     rank = int(os.environ.get('RANK', 0))
                     master_addr = os.environ.get('MASTER_ADDR', 'localhost')
                     master_port = os.environ.get('MASTER_PORT', '29500')

                     print(f"Worker {rank}/{world_size} starting...")
                     print(f"GPU: {torch.cuda.get_device_name(0)}")

                     # Initialize process group
                     dist.init_process_group(
                         backend='nccl',
                         init_method=f'tcp://{master_addr}:{master_port}',
                         world_size=world_size,
                         rank=rank
                     )

                     # Create tensor on GPU
                     device = torch.device('cuda:0')
                     tensor = torch.ones(1000, 1000, device=device) * rank

                     # All-reduce operation
                     dist.all_reduce(tensor, op=dist.ReduceOp.SUM)

                     if rank == 0:
                         expected_sum = sum(range(world_size))
                         print(f"All-reduce complete. Sum: {tensor[0,0].item()}, Expected: {expected_sum}")

                     dist.destroy_process_group()
                     print(f"Worker {rank} finished!")
                 resources:
                   limits:
                     nvidia.com/gpu: 1
             restartPolicy: OnFailure
   ```

4. **Submit and Monitor**
   ```bash
   kubectl apply -f volcano-queue.yaml
   kubectl apply -f gang-training-job.yaml

   # Watch for all pods to be scheduled together
   kubectl get pods -n team-training -l volcano.sh/job-name=distributed-training -w

   # Check job status
   kubectl get job.batch.volcano.sh -n team-training
   ```

### Task 6: Monitor GPU Utilization and Metrics (20 min)

1. **Check GPU Utilization**
   ```bash
   # Install DCGM exporter metrics (if not already via GPU Operator)
   kubectl get pods -n gpu-operator -l app=nvidia-dcgm-exporter

   # Port forward to access metrics
   kubectl port-forward -n gpu-operator svc/nvidia-dcgm-exporter 9400:9400 &

   # Fetch GPU metrics
   curl -s http://localhost:9400/metrics | grep -E "DCGM_FI_DEV_GPU_UTIL|DCGM_FI_DEV_MEM_COPY_UTIL"
   ```

2. **Create GPU Monitoring Dashboard (Prometheus/Grafana)**
   ```yaml
   # Save as gpu-servicemonitor.yaml
   apiVersion: monitoring.coreos.com/v1
   kind: ServiceMonitor
   metadata:
     name: dcgm-exporter
     namespace: gpu-operator
   spec:
     selector:
       matchLabels:
         app: nvidia-dcgm-exporter
     endpoints:
       - port: metrics
         interval: 15s
   ```

3. **Check Quota Usage**
   ```bash
   # View quota usage per namespace
   kubectl get resourcequotas -A -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name,USED_GPU:.status.used.limits\.nvidia\.com/gpu,HARD_GPU:.status.hard.limits\.nvidia\.com/gpu'
   ```

4. **Generate Usage Report**
   ```bash
   cat << 'EOF' > gpu-usage-report.sh
   #!/bin/bash
   echo "=== GPU Orchestration Usage Report ==="
   echo "Date: $(date)"
   echo ""
   echo "=== GPU Node Status ==="
   kubectl get nodes -l runai.node-type=gpu -o custom-columns='NODE:.metadata.name,GPUs:.status.allocatable.nvidia\.com/gpu,CPU:.status.allocatable.cpu,MEMORY:.status.allocatable.memory'
   echo ""
   echo "=== Quota Usage by Team ==="
   for ns in team-training team-inference team-research; do
     echo "--- $ns ---"
     kubectl get resourcequota -n $ns -o custom-columns='QUOTA:.metadata.name,GPU_USED:.status.used.limits\.nvidia\.com/gpu,GPU_LIMIT:.status.hard.limits\.nvidia\.com/gpu' 2>/dev/null || echo "No quota found"
   done
   echo ""
   echo "=== Running GPU Workloads ==="
   kubectl get pods -A -o json | jq -r '.items[] | select(.spec.containers[].resources.limits."nvidia.com/gpu" != null) | "\(.metadata.namespace)/\(.metadata.name): \(.spec.containers[0].resources.limits."nvidia.com/gpu") GPU(s)"'
   EOF
   chmod +x gpu-usage-report.sh
   ./gpu-usage-report.sh
   ```

## Deliverables

- [ ] **Screenshot** of KAI Scheduler running
- [ ] **Quota configuration** showing per-team GPU limits
- [ ] **Fractional GPU test output** showing shared GPU allocation
- [ ] **Priority preemption events** from kubectl get events
- [ ] **Gang scheduling job output** showing distributed training
- [ ] **GPU usage report** output

## Verification Checklist

- [ ] KAI Scheduler deployed and scheduling GPU workloads
- [ ] GPU quotas enforced per namespace/team
- [ ] Fractional GPU sharing working with time-slicing
- [ ] Priority-based preemption functioning
- [ ] Gang scheduling completing distributed jobs
- [ ] GPU metrics accessible for monitoring

## Troubleshooting

### Scheduler Not Assigning Pods

**Check scheduler logs:**
```bash
kubectl logs -n runai-system -l app=kai-scheduler --tail=50
```

**Verify scheduler is running:**
```bash
kubectl get pods -n runai-system -l app=kai-scheduler
```

### Fractional GPUs Not Working

**Check time-slicing configuration:**
```bash
kubectl get configmap time-slicing-config -n gpu-operator -o yaml
```

**Verify device plugin restarted:**
```bash
kubectl rollout status daemonset/nvidia-device-plugin-daemonset -n gpu-operator
```

### Gang Scheduling Pods Stuck

**Check Volcano scheduler:**
```bash
kubectl logs -n volcano-system -l app=volcano-scheduler --tail=50
```

**Verify queue capacity:**
```bash
kubectl get queue training-queue -o yaml
```

### Quota Exceeded Errors

**Check quota status:**
```bash
kubectl describe resourcequota -n <namespace>
```

**View pod events:**
```bash
kubectl get events -n <namespace> --sort-by='.lastTimestamp'
```

## Key Takeaways

1. **KAI Scheduler** (open-source Run:AI) provides advanced GPU scheduling beyond default Kubernetes
2. **Fractional GPUs** enable better utilization through time-slicing
3. **Priority classes** allow critical workloads to preempt less important ones
4. **Gang scheduling** ensures all pods for distributed training start together
5. **GPU quotas** enable fair multi-tenant resource sharing
6. **Monitoring** is essential for understanding GPU utilization patterns

## Next Lab

Proceed to [Lab 5.12 - Slurm Operator for HPC](lab-5.12-slurm-operator-hpc.md)
