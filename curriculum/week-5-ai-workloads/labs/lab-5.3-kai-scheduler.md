# Lab 5.3 - KAI Scheduler (Open-Source GPU Scheduling)

---

## Lab Navigation

| Track | Tier | Duration |
|-------|------|----------|
| Foundation | Required | 2.5 hours |

### Week 5 Learning Paths

```
FOUNDATION (Required)                              CHOOSE YOUR PATH
━━━━━━━━━━━━━━━━━━━━                              ━━━━━━━━━━━━━━━━
5.1 ➔ 5.2 ➔ [5.3] ➔ 5.4 ➔ 5.5 ➔ 5.6 ➔ 5.7 ➔ 5.8  ──►  ML Platforms (5.9-5.10)
               ↑                                          Compliance (5.11-5.12)
          YOU ARE HERE                                    Advanced (5.13-5.16)
```

| Previous | Current | Next |
|----------|---------|------|
| [Lab 5.2 - Service Catalog](lab-5.2-service-catalog.md) | **Lab 5.3 - KAI Scheduler** | [Lab 5.4 - Run:ai GPU Orchestration](lab-5.4-runai-gpu-orchestration.md) |

---

## Table of Contents

- [Objective](#objective)
- [Prerequisites](#prerequisites)
- [Background](#background)
  - [What is KAI Scheduler?](#what-is-kai-scheduler)
  - [KAI vs Run:ai Comparison](#kai-vs-runai-comparison)
  - [Architecture](#architecture)
- [Lab Environment](#lab-environment)
- [Tasks](#tasks)
  - [Task 1: Install KAI Scheduler](#task-1-install-kai-scheduler-20-min)
  - [Task 2: Configure GPU Queue Hierarchy](#task-2-configure-gpu-queue-hierarchy-25-min)
  - [Task 3: Submit Workloads to Queues](#task-3-submit-workloads-to-queues-25-min)
  - [Task 4: Fractional GPU Sharing](#task-4-fractional-gpu-sharing-25-min)
  - [Task 5: Gang Scheduling for Distributed Training](#task-5-gang-scheduling-for-distributed-training-30-min)
  - [Task 6: Priority and Preemption](#task-6-priority-and-preemption-20-min)
  - [Task 7: Monitor KAI Metrics](#task-7-monitor-kai-metrics-15-min)
  - [Task 8: k0rdent Integration](#task-8-k0rdent-integration-15-min)
- [Deliverables](#deliverables)
- [Verification Checklist](#verification-checklist)
- [Troubleshooting](#troubleshooting)
- [Key Takeaways](#key-takeaways)
- [References](#references)
- [Related Labs](#related-labs)

**Duration:** 2.5 hours
**Type:** Hands-on Technical
**Environment:** GPU Lab

## Objective

Deploy the NVIDIA KAI Scheduler — the open-source GPU scheduling engine extracted from Run:ai — and configure GPU queues with quotas, fractional GPU sharing, gang scheduling for distributed training, and priority-based preemption. KAI provides advanced GPU scheduling without requiring a Run:ai commercial license.

## Prerequisites

- Completed Lab 5.1 (GPU Operator deployed via k0rdent catalog)
- Kubernetes cluster with 2+ GPU nodes (k0rdent-managed)
- NVIDIA GPU Operator v25.3+ installed
- `kubectl` and `helm` (v3.14+) installed
- Understanding of Kubernetes scheduling concepts

> **Run:ai vs KAI:** This lab covers the **open-source KAI Scheduler** (`v0.14.0` as of April 2026). For the full commercial platform with web UI, CLI, Departments/Projects, and memory-enforced fractional GPUs, see [Lab 5.4 - NVIDIA Run:ai](lab-5.4-runai-gpu-orchestration.md).

## Background

### What is KAI Scheduler?

In 2025, NVIDIA open-sourced the core scheduling engine from Run:ai as the **KAI Scheduler** (Kubernetes AI Scheduler). KAI is a Kubernetes-native scheduler that replaces the default `kube-scheduler` for AI workloads, providing:

- **Hierarchical GPU queues** with guaranteed quotas and over-quota borrowing
- **Gang scheduling** via automatic PodGroup creation (PodGrouper)
- **Fractional GPU** sharing via pod annotations (scheduling-level, no memory enforcement)
- **Bin packing** to consolidate workloads onto fewer nodes
- **Priority-based preemption** using standard Kubernetes PriorityClasses
- **Topology-aware placement** for distributed training

### KAI vs Run:ai Comparison

| Capability | KAI Scheduler | Run:ai Commercial |
|-----------|---------------|-------------------|
| GPU scheduling engine | Same core | Same core |
| Fractional GPU | Annotation-based (no memory enforcement) | Virtual address spaces (memory enforced) |
| Web UI / Dashboard | None | Yes |
| Organizational model | Queue hierarchy (CRDs) | Departments → Projects (UI/API) |
| CLI | None (use `kubectl`) | `runai` CLI |
| Multi-cluster | No | Yes |
| Inference autoscaling | No | Yes (Knative-based) |
| License | Apache 2.0 | NVIDIA Commercial |

### Architecture

```
┌────────────────────────────────────────────────────────────────┐
│                    KAI Scheduler Components                     │
│                    (namespace: kai-scheduler)                    │
├────────────────────────────────────────────────────────────────┤
│  ┌──────────┐  ┌────────────┐  ┌────────────┐  ┌───────────┐ │
│  │Scheduler │  │ PodGrouper │  │  Queue      │  │ Admission │ │
│  │(binpack/ │  │(auto-create│  │ Controller  │  │ Webhooks  │ │
│  │ spread)  │  │ PodGroups) │  │(quota mgmt) │  │           │ │
│  └──────────┘  └────────────┘  └────────────┘  └───────────┘ │
│  ┌──────────┐  ┌────────────┐  ┌────────────┐                │
│  │ Binder   │  │  Operator  │  │ Node Scale │                │
│  │(GPU res- │  │(lifecycle  │  │ Adjuster   │                │
│  │ ervation)│  │  mgmt)     │  │            │                │
│  └──────────┘  └────────────┘  └────────────┘                │
├────────────────────────────────────────────────────────────────┤
│                    Kubernetes API Server                        │
├────────────────────────────────────────────────────────────────┤
│  Queue CRDs (scheduling.run.ai/v2)                             │
│  ┌──────────────────┐     ┌──────────────────┐                │
│  │ parent-queue      │     │ PodGroup CRDs     │                │
│  │ ├── team-a-queue  │     │ (scheduling.run.  │                │
│  │ └── team-b-queue  │     │  ai/v2alpha2)     │                │
│  └──────────────────┘     └──────────────────┘                │
├────────────────────────────────────────────────────────────────┤
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐      │
│  │  GPU 0   │  │  GPU 1   │  │  GPU 2   │  │  GPU 3   │      │
│  │  Node A  │  │  Node A  │  │  Node B  │  │  Node B  │      │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘      │
└────────────────────────────────────────────────────────────────┘
```

**Key CRDs:**
- `Queue` (`scheduling.run.ai/v2`) — Cluster-scoped, hierarchical queue tree with GPU/CPU/memory quotas
- `PodGroup` (`scheduling.run.ai/v2alpha2`) — Namespaced, groups pods for gang scheduling
- `Topology` (`kai.scheduler/v1alpha1`) — Cluster-scoped, defines node topology hierarchy

## Lab Environment

**Cluster Requirements:**
- Kubernetes 1.28+ with 2+ GPU nodes
- NVIDIA GPU Operator installed
- 4+ GPUs total across nodes
- Helm 3.14+ installed

## Tasks

### Task 1: Install KAI Scheduler (20 min)

1. **Install KAI Scheduler from the OCI Registry**

   ```bash
   helm upgrade -i kai-scheduler \
     oci://ghcr.io/kai-scheduler/kai-scheduler/kai-scheduler \
     --namespace kai-scheduler \
     --create-namespace \
     --version v0.14.0
   ```

2. **Verify Installation**

   ```bash
   # All KAI components should be Running
   kubectl get pods -n kai-scheduler

   # Expected pods (KAI v0.14.0 drops the `kai-scheduler-` prefix on most components):
   #   kai-operator-*
   #   kai-scheduler-default-*
   #   pod-grouper-*
   #   podgroup-controller-*
   #   binder-*
   #   queue-controller-*
   #   admission-*

   # Verify the scheduler is ready
   kubectl get pods -n kai-scheduler -l app=kai-scheduler-default
   ```

   > **Note on naming:** The scheduler Deployment is named `kai-scheduler-default` (and can be extended with additional shards via the `SchedulingShard` CRD — see Task 7's metrics port-forward targets). The `nodescaleadjuster` component is not installed by default in v0.14.0; it is an optional cluster-autoscaler integration enabled via a separate Helm value.

3. **Check Default Queues**

   KAI automatically creates a default queue hierarchy:

   ```bash
   # List all queues
   kubectl get queues

   # Expected:
   # NAME                   AGE
   # default-parent-queue   1m
   # default-queue          1m

   # Inspect the default queue
   kubectl get queue default-queue -o yaml
   ```

4. **Verify CRDs**

   ```bash
   kubectl get crds | grep -E "scheduling.run.ai|kai.scheduler"

   # Expected CRDs (KAI v0.14.0 — 6 total):
   # queues.scheduling.run.ai
   # podgroups.scheduling.run.ai
   # bindrequests.scheduling.run.ai
   # configs.kai.scheduler
   # schedulingshards.kai.scheduler
   # topologies.kai.scheduler
   ```

   > **What the extra CRDs do:** `schedulingshards.kai.scheduler` defines named scheduler shards (each backed by a `kai-scheduler-<shard>` Deployment — the built-in shard is `default`), enabling multi-tenant scheduling with isolated scheduling policies per shard. `topologies.kai.scheduler` describes node topology hierarchies (rack → zone → region) that the scheduler consumes for topology-aware placement of distributed workloads (see Task 5).

### Task 2: Configure GPU Queue Hierarchy (25 min)

KAI uses a hierarchical queue tree where parent queues distribute resources among child queues. Only **leaf queues** (queues with no children) can have workloads submitted to them.

1. **Design Queue Hierarchy**

   ```
   cluster-root (parent)
   ├── training-queue (leaf) — 2 GPU quota, over-quota enabled
   ├── inference-queue (leaf) — 1 GPU quota, over-quota enabled
   └── research-queue (leaf) — 1 GPU quota, over-quota enabled
   ```

2. **Create the Queue Hierarchy**

   ```yaml
   # Save as kai-queues.yaml
   apiVersion: scheduling.run.ai/v2
   kind: Queue
   metadata:
     name: cluster-root
   spec:
     resources:
       gpu:
         quota: 4              # Sum of children's quotas (2+1+1)
         limit: -1             # Unlimited
         overQuotaWeight: 1
       cpu:
         quota: 32000          # Sum of children's quotas (16000+8000+8000)
         limit: -1
         overQuotaWeight: 1
       memory:
         quota: 128000         # Sum of children's quotas (64000+32000+32000)
         limit: -1
         overQuotaWeight: 1
   ---
   apiVersion: scheduling.run.ai/v2
   kind: Queue
   metadata:
     name: training-queue
   spec:
     parentQueue: cluster-root
     priority: 150            # Higher priority for over-quota allocation
     resources:
       gpu:
         quota: 2             # Guaranteed 2 GPUs
         limit: -1            # Can burst beyond quota
         overQuotaWeight: 2   # Gets 2x share of surplus GPUs
       cpu:
         quota: 16000         # 16 CPU cores (in millicores)
         limit: -1
         overQuotaWeight: 1
       memory:
         quota: 64000         # 64 GB (in MB)
         limit: -1
         overQuotaWeight: 1
   ---
   apiVersion: scheduling.run.ai/v2
   kind: Queue
   metadata:
     name: inference-queue
   spec:
     parentQueue: cluster-root
     priority: 200            # Highest priority (inference is critical)
     resources:
       gpu:
         quota: 1
         limit: 2             # Hard cap at 2 GPUs
         overQuotaWeight: 1
       cpu:
         quota: 8000
         limit: -1
         overQuotaWeight: 1
       memory:
         quota: 32000
         limit: -1
         overQuotaWeight: 1
   ---
   apiVersion: scheduling.run.ai/v2
   kind: Queue
   metadata:
     name: research-queue
   spec:
     parentQueue: cluster-root
     priority: 100            # Lower priority — yields over-quota to others first
     resources:
       gpu:
         quota: 1
         limit: -1
         overQuotaWeight: 1
       cpu:
         quota: 8000
         limit: -1
         overQuotaWeight: 1
       memory:
         quota: 32000
         limit: -1
         overQuotaWeight: 1
   ```

3. **Apply and Verify**

   ```bash
   kubectl apply -f kai-queues.yaml

   # List all queues
   kubectl get queues

   # Verify parent-child relationships
   kubectl get queue cluster-root -o jsonpath='{.status.childQueues}'
   # Expected: ["training-queue","inference-queue","research-queue"]

   # Check quota details
   kubectl get queue training-queue -o yaml
   ```

   > **Queue Quota Rules:**
   > - `quota: 2` = guaranteed 2 GPUs for this queue
   > - `limit: -1` = no cap on over-quota borrowing
   > - `limit: 2` = hard cap at 2 GPUs even with idle resources
   > - `overQuotaWeight: 2` = gets twice the share of surplus compared to weight=1
   > - **A parent queue's `quota` must be ≥ the sum of its children's `quota`** when any child will host non-preemptible workloads (K8s PriorityClass `value ≥ 100`). Non-preemptible workloads are *not allowed* to go over quota, and KAI enforces the limit at every ancestor level — if `cluster-root.quota.gpu = 0` you will see `NonPreemptibleOverQuota: Non-preemptible workload is over quota. ... cluster-root quota is 0 GPUs` when Task 6's `inference-critical` (value=125) tries to schedule, even though its own `inference-queue.quota` is 1. Leaf-queue quotas alone are not sufficient.

### Task 3: Submit Workloads to Queues (25 min)

Pods are assigned to queues via the label `kai.scheduler/queue` and must use `schedulerName: kai-scheduler`.

1. **Submit a GPU Workload to the Training Queue**

   ```yaml
   # Save as kai-training-pod.yaml
   apiVersion: v1
   kind: Pod
   metadata:
     name: training-job-1
     labels:
       kai.scheduler/queue: training-queue
   spec:
     schedulerName: kai-scheduler
     restartPolicy: Never
     containers:
       - name: cuda-train
         image: nvcr.io/nvidia/cuda:12.6.0-base-ubi9
         command:
           - bash
           - -c
           - |
             echo "Training job started on queue: training-queue"
             nvidia-smi
             echo "Simulating training for 120 seconds..."
             sleep 120
             echo "Training complete!"
         resources:
           limits:
             nvidia.com/gpu: "1"
   ```

   ```bash
   kubectl apply -f kai-training-pod.yaml

   # Check the pod is scheduled by KAI
   kubectl get pod training-job-1 -o wide

   # Check the PodGroup auto-created by PodGrouper
   kubectl get podgroups
   ```

2. **Submit a Batch Job to the Research Queue**

   ```yaml
   # Save as kai-research-job.yaml
   apiVersion: batch/v1
   kind: Job
   metadata:
     name: research-experiment
   spec:
     parallelism: 2
     completions: 2
     template:
       metadata:
         labels:
           kai.scheduler/queue: research-queue
       spec:
         schedulerName: kai-scheduler
         restartPolicy: OnFailure
         containers:
           - name: experiment
             image: nvcr.io/nvidia/cuda:12.6.0-base-ubi9
             command:
               - bash
               - -c
               - |
                 echo "Research experiment on GPU:"
                 nvidia-smi --query-gpu=name,memory.total --format=csv,noheader
                 sleep 60
             resources:
               limits:
                 nvidia.com/gpu: "1"
   ```

   ```bash
   kubectl apply -f kai-research-job.yaml

   # Watch pods get scheduled
   kubectl get pods -l job-name=research-experiment -w
   ```

3. **Observe Queue Allocation**

   ```bash
   # Check GPU allocation per queue
   kubectl get queues -o custom-columns='NAME:.metadata.name,GPU_QUOTA:.spec.resources.gpu.quota,GPU_ALLOCATED:.status.allocated.nvidia\.com/gpu'
   ```

### Task 4: Fractional GPU Sharing (25 min)

KAI supports fractional GPU allocation via pod annotations. Unlike Run:ai's commercial offering, KAI does **not enforce memory limits** — workloads must self-regulate their GPU memory usage.

1. **Enable GPU Sharing**

   GPU sharing must be enabled during installation. Upgrade the Helm release:

   ```bash
   helm upgrade kai-scheduler \
     oci://ghcr.io/kai-scheduler/kai-scheduler/kai-scheduler \
     --namespace kai-scheduler \
     --version v0.14.0 \
     --set "global.gpuSharing=true"

   # Wait for pods to restart
   kubectl rollout status deployment -n kai-scheduler -l app=kai-scheduler-default

   # REQUIRED: force a scheduler rollover so it picks up the new ServiceAccount
   # token (see explanation below).
   kubectl rollout restart deployment/kai-scheduler-default -n kai-scheduler
   kubectl rollout status deployment/kai-scheduler-default -n kai-scheduler --timeout=2m
   ```

   > **Why the scheduler must be explicitly restarted:** Enabling `global.gpuSharing=true` causes the KAI Helm chart to delete and recreate every ServiceAccount in the `kai-scheduler` namespace (admission, binder, pod-grouper, podgroup-controller, queue-controller, **scheduler**). For all components except the scheduler, the change also bumps the Deployment's pod-template spec, so the Deployment controller rolls the pod automatically and the new pod mounts a token tied to the new SA UID. The **scheduler's** pod template is *not* modified by the `gpuSharing` flag, so no rollover happens — yet its projected token now references a dead SA UID.
   >
   > The symptom is subtle: RBAC checks pass (`kubectl auth can-i update podgroups/status --as=system:serviceaccount:kai-scheduler:scheduler` returns `yes`), but the scheduler log fills with `ERROR status_updater/concurrency.go ... Failed to update pod group status <ns>/<pg-name>: Unauthorized`, and *every fractional pod stays in `Pending` forever* because its `PodGroup.status` can never be written. The explicit `kubectl rollout restart` above forces the pod to remount a valid token.

2. **Submit a Half-GPU Workload**

   ```yaml
   # Save as kai-fractional-1.yaml
   apiVersion: v1
   kind: Pod
   metadata:
     name: frac-gpu-1
     labels:
       kai.scheduler/queue: research-queue
     annotations:
       gpu-fraction: "0.5"
   spec:
     schedulerName: kai-scheduler
     restartPolicy: Never
     containers:
       - name: cuda-half
         image: nvcr.io/nvidia/cuda:12.6.0-base-ubi9
         command:
           - bash
           - -c
           - |
             echo "Pod frac-gpu-1: Allocated 50% of GPU"
             nvidia-smi
             sleep 120
   ```

3. **Submit a Second Half-GPU Workload**

   ```yaml
   # Save as kai-fractional-2.yaml
   apiVersion: v1
   kind: Pod
   metadata:
     name: frac-gpu-2
     labels:
       kai.scheduler/queue: research-queue
     annotations:
       gpu-fraction: "0.5"
   spec:
     schedulerName: kai-scheduler
     restartPolicy: Never
     containers:
       - name: cuda-half
         image: nvcr.io/nvidia/cuda:12.6.0-base-ubi9
         command:
           - bash
           - -c
           - |
             echo "Pod frac-gpu-2: Allocated 50% of GPU"
             nvidia-smi
             sleep 120
   ```

4. **Deploy and Verify Sharing**

   ```bash
   kubectl apply -f kai-fractional-1.yaml
   kubectl apply -f kai-fractional-2.yaml

   # Both pods should be Running on the same node/GPU
   kubectl get pods frac-gpu-1 frac-gpu-2 -o wide

   # Check resource reservation pods (KAI creates these to hold GPU slots)
   kubectl get pods -n kai-resource-reservation
   ```

5. **Request Fractional GPU by Memory Amount**

   You can also request GPU memory in MiB instead of a fraction:

   ```yaml
   # Save as kai-fractional-memory.yaml
   apiVersion: v1
   kind: Pod
   metadata:
     name: frac-gpu-memory
     labels:
       kai.scheduler/queue: research-queue
     annotations:
       gpu-memory: "4000"    # Request 4000 MiB of GPU memory
   spec:
     schedulerName: kai-scheduler
     restartPolicy: Never
     containers:
       - name: cuda-mem
         image: nvcr.io/nvidia/cuda:12.6.0-base-ubi9
         command: ["bash", "-c", "nvidia-smi && sleep 60"]
   ```

   ```bash
   kubectl apply -f kai-fractional-memory.yaml
   kubectl get pod frac-gpu-memory -o wide
   ```

   > **Warning:** KAI schedules fractional workloads but does **not enforce** memory limits. If a pod allocated 50% tries to use 100% of GPU memory, it will succeed until another pod on the same GPU runs out of memory. For memory-enforced fractions, use Run:ai commercial (Lab 5.4).

6. **Clean Up**

   ```bash
   kubectl delete pod frac-gpu-1 frac-gpu-2 frac-gpu-memory
   ```

### Task 5: Gang Scheduling for Distributed Training (30 min)

KAI's PodGrouper automatically detects distributed training workloads and creates PodGroup resources. All pods in a PodGroup are scheduled atomically — either all start or none start.

1. **Understand PodGrouper's Automatic Detection**

   PodGrouper works by traversing pod owner references to find the top-level workload:

   ```
   Pod → ReplicaSet → Deployment          → PodGroup (1 per Deployment)
   Pod → Job                              → PodGroup (1 per Job)
   Pod → PyTorchJob (Master/Worker)       → PodGroup (all replicas together)
   Pod → RayCluster (Head/Worker)         → PodGroup (all pods together)
   ```

   For Kubeflow training operators, PodGrouper sets `minMember` to the **total replica count** across all roles (master + workers), enforcing gang scheduling.

2. **Submit a Gang-Scheduled Job**

   Create a Kubernetes Job with parallelism requiring multiple pods:

   ```yaml
   # Save as kai-gang-job.yaml
   apiVersion: batch/v1
   kind: Job
   metadata:
     name: gang-training
   spec:
     parallelism: 4
     completions: 4
     template:
       metadata:
         labels:
           kai.scheduler/queue: training-queue
       spec:
         schedulerName: kai-scheduler
         restartPolicy: OnFailure
         containers:
           - name: gpu-worker
             image: nvcr.io/nvidia/cuda:12.6.0-base-ubi9
             command:
               - bash
               - -c
               - |
                 echo "Gang worker started: $(hostname)"
                 nvidia-smi --query-gpu=name --format=csv,noheader
                 sleep 60
                 echo "Worker complete: $(hostname)"
             resources:
               limits:
                 nvidia.com/gpu: "1"
   ```

   ```bash
   kubectl apply -f kai-gang-job.yaml

   # Watch all 4 pods get scheduled together
   kubectl get pods -l job-name=gang-training -w

   # Check the auto-created PodGroup
   kubectl get podgroups -o wide
   kubectl get podgroup -l job-name=gang-training -o yaml
   ```

3. **Submit a Kubeflow PyTorchJob (Advanced)**

   If the Kubeflow Training Operator is installed, KAI automatically gang-schedules PyTorchJobs:

   ```yaml
   # Save as kai-pytorchjob.yaml
   # Requires: Kubeflow Training Operator installed
   apiVersion: "kubeflow.org/v1"
   kind: PyTorchJob
   metadata:
     name: kai-pytorch-dist
   spec:
     pytorchReplicaSpecs:
       Master:
         replicas: 1
         restartPolicy: OnFailure
         template:
           metadata:
             labels:
               kai.scheduler/queue: training-queue
           spec:
             schedulerName: kai-scheduler
             containers:
               - name: pytorch
                 image: pytorch/pytorch:2.6.0-cuda12.6-cudnn9-runtime
                 command:
                   - python
                   - -c
                   - |
                     import torch
                     import torch.distributed as dist
                     import os
                     rank = int(os.environ.get('RANK', 0))
                     world_size = int(os.environ.get('WORLD_SIZE', 1))
                     dist.init_process_group(backend='nccl')
                     tensor = torch.ones(1000, device='cuda') * rank
                     dist.all_reduce(tensor)
                     if rank == 0:
                         print(f'All-reduce sum: {tensor[0].item()}, expected: {sum(range(world_size))}')
                     dist.destroy_process_group()
                 resources:
                   limits:
                     nvidia.com/gpu: "1"
       Worker:
         replicas: 3
         restartPolicy: OnFailure
         template:
           metadata:
             labels:
               kai.scheduler/queue: training-queue
           spec:
             schedulerName: kai-scheduler
             containers:
               - name: pytorch
                 image: pytorch/pytorch:2.6.0-cuda12.6-cudnn9-runtime
                 command:
                   - python
                   - -c
                   - |
                     import torch
                     import torch.distributed as dist
                     import os
                     rank = int(os.environ.get('RANK', 0))
                     world_size = int(os.environ.get('WORLD_SIZE', 1))
                     dist.init_process_group(backend='nccl')
                     tensor = torch.ones(1000, device='cuda') * rank
                     dist.all_reduce(tensor)
                     dist.destroy_process_group()
                 resources:
                   limits:
                     nvidia.com/gpu: "1"
   ```

   ```bash
   kubectl apply -f kai-pytorchjob.yaml

   # PodGrouper creates a PodGroup with minMember=4 (1 master + 3 workers)
   kubectl get podgroups

   # All 4 pods must be scheduled simultaneously
   kubectl get pods -l training.kubeflow.org/job-name=kai-pytorch-dist -w
   ```

4. **Clean Up**

   ```bash
   kubectl delete job gang-training
   kubectl delete pytorchjob kai-pytorch-dist 2>/dev/null
   ```

### Task 6: Priority and Preemption (20 min)

KAI uses standard Kubernetes PriorityClasses with a key rule: **value >= 100 is non-preemptible, < 100 is preemptible**.

1. **Create PriorityClasses**

   ```yaml
   # Save as kai-priorities.yaml
   apiVersion: scheduling.k8s.io/v1
   kind: PriorityClass
   metadata:
     name: kai-train
   value: 50
   globalDefault: false
   description: "Training workloads (preemptible, value < 100)"
   ---
   apiVersion: scheduling.k8s.io/v1
   kind: PriorityClass
   metadata:
     name: kai-build
   value: 100
   globalDefault: false
   description: "Interactive/build workloads (non-preemptible, value >= 100)"
   ---
   apiVersion: scheduling.k8s.io/v1
   kind: PriorityClass
   metadata:
     name: kai-inference
   value: 125
   globalDefault: false
   description: "Inference workloads (non-preemptible, highest priority)"
   ```

   ```bash
   kubectl apply -f kai-priorities.yaml
   kubectl get priorityclasses | grep kai
   ```

2. **Fill GPUs with Preemptible Training Workloads**

   ```yaml
   # Save as kai-preempt-low.yaml
   apiVersion: batch/v1
   kind: Job
   metadata:
     name: low-priority-fill
   spec:
     parallelism: 4
     template:
       metadata:
         labels:
           kai.scheduler/queue: research-queue
       spec:
         schedulerName: kai-scheduler
         priorityClassName: kai-train       # value=50, preemptible
         restartPolicy: Never
         containers:
           - name: gpu-hog
             image: nvcr.io/nvidia/cuda:12.6.0-base-ubi9
             command: ["sleep", "600"]
             resources:
               limits:
                 nvidia.com/gpu: "1"
   ```

   ```bash
   kubectl apply -f kai-preempt-low.yaml

   # Wait for all 4 pods to be Running (filling all GPUs)
   kubectl get pods -l job-name=low-priority-fill -w
   ```

3. **Submit a Non-Preemptible Inference Workload**

   ```yaml
   # Save as kai-preempt-high.yaml
   apiVersion: v1
   kind: Pod
   metadata:
     name: inference-critical
     labels:
       kai.scheduler/queue: inference-queue
   spec:
     schedulerName: kai-scheduler
     priorityClassName: kai-inference     # value=125, non-preemptible
     restartPolicy: Never
     containers:
       - name: inference
         image: nvcr.io/nvidia/cuda:12.6.0-base-ubi9
         command:
           - bash
           - -c
           - |
             echo "Inference workload running (preempted a training pod)"
             nvidia-smi
             sleep 60
         resources:
           limits:
             nvidia.com/gpu: "1"
   ```

   ```bash
   kubectl apply -f kai-preempt-high.yaml

   # The inference pod should preempt one of the training pods
   kubectl get pods -l job-name=low-priority-fill
   kubectl get pod inference-critical

   # Check events for preemption
   kubectl get events --sort-by='.lastTimestamp' | grep -i preempt
   ```

   > **Preemption Rule:** Non-preemptible workloads (value >= 100) cannot exceed their queue's quota. Preemptible workloads (value < 100) can use over-quota resources but will be evicted when quota owners need their resources back.

4. **Clean Up**

   ```bash
   kubectl delete job low-priority-fill
   kubectl delete pod inference-critical
   ```

### Task 7: Monitor KAI Metrics (15 min)

KAI exposes Prometheus metrics for queue utilization, scheduling latency, and preemption events.

1. **Check Available Metrics Endpoints**

   ```bash
   # KAI scheduler metrics (served by the default scheduler shard)
   kubectl port-forward -n kai-scheduler svc/kai-scheduler-default 8080:8080 &
   curl -s http://localhost:8080/metrics | head -50

   # Queue controller metrics
   kubectl port-forward -n kai-scheduler svc/queue-controller 8081:8080 &
   curl -s http://localhost:8081/metrics | grep queue_
   ```

   > **Service naming:** KAI v0.14.0 uses short service names without the `kai-scheduler-` prefix (e.g. `queue-controller`, `binder`, `admission`). The one exception is the scheduler itself, which is named `kai-scheduler-<shard>` — here `kai-scheduler-default` for the built-in shard. Verify with `kubectl get svc -n kai-scheduler` if you add custom `SchedulingShard` resources.

2. **Key Metrics to Monitor**

   ```bash
   # GPU allocation per queue
   curl -s http://localhost:8081/metrics | grep queue_allocated_gpus

   # GPU quota per queue
   curl -s http://localhost:8081/metrics | grep queue_deserved_gpus

   # Scheduling latency
   curl -s http://localhost:8080/metrics | grep e2e_scheduling_latency

   # Preemption events
   curl -s http://localhost:8080/metrics | grep total_preemption_attempts
   ```

3. **Generate a Status Report**

   ```bash
   echo "=== KAI Scheduler Status ==="
   echo ""
   echo "--- Queues ---"
   kubectl get queues -o custom-columns=\
   'NAME:.metadata.name,PARENT:.spec.parentQueue,GPU_QUOTA:.spec.resources.gpu.quota,GPU_LIMIT:.spec.resources.gpu.limit,PRIORITY:.spec.priority'
   echo ""
   echo "--- PodGroups ---"
   kubectl get podgroups -A -o custom-columns=\
   'NAMESPACE:.metadata.namespace,NAME:.metadata.name,PHASE:.status.phase,RUNNING:.status.running,PENDING:.status.pending'
   echo ""
   echo "--- GPU Nodes ---"
   kubectl get nodes -o json | jq -r '
     .items[] |
     select(.status.allocatable["nvidia.com/gpu"] != null) |
     "\(.metadata.name): \(.status.allocatable["nvidia.com/gpu"]) GPUs"
   '
   echo ""
   echo "--- KAI Pods ---"
   kubectl get pods -n kai-scheduler --no-headers | wc -l
   echo "components running"

   # Kill port-forwards
   kill %1 %2 2>/dev/null
   ```

### Task 8: k0rdent Integration (15 min)

KAI Scheduler is open-source and can be deployed on k0rdent-managed clusters. There is no KAI ServiceTemplate in the k0rdent catalog, but the Helm chart can be installed directly.

1. **Deploy KAI on a k0rdent-Managed Cluster**

   ```bash
   # Get kubeconfig for the k0rdent child cluster
   kubectl get secret -n kcm-system <cluster-name>-kubeconfig \
     -o jsonpath='{.data.value}' | base64 -d > /tmp/child-kubeconfig

   # Install KAI Scheduler on the child cluster
   KUBECONFIG=/tmp/child-kubeconfig \
   helm upgrade -i kai-scheduler \
     oci://ghcr.io/kai-scheduler/kai-scheduler/kai-scheduler \
     --namespace kai-scheduler \
     --create-namespace \
     --version v0.14.0

   # Verify
   KUBECONFIG=/tmp/child-kubeconfig \
   kubectl get pods -n kai-scheduler
   ```

2. **Combine with GPU Operator from k0rdent Catalog**

   KAI requires the NVIDIA GPU Operator. On k0rdent-managed clusters, deploy it via the catalog:

   ```bash
   # Install GPU Operator ServiceTemplate (on management cluster)
   helm upgrade --install gpu-operator \
     oci://ghcr.io/k0rdent/catalog/charts/kgst \
     --set "chart=gpu-operator:25.10.0" \
     -n kcm-system

   # Then install KAI directly on the child cluster (separate step)
   ```

   > **Note:** Since KAI is open-source and freely distributable, you could also create a custom k0rdent ServiceTemplate wrapping the KAI Helm chart for automated deployment across clusters. This would allow deploying KAI via MultiClusterService alongside the GPU Operator.

## Deliverables

- [ ] **Output** of `kubectl get pods -n kai-scheduler` showing all components running
- [ ] **Queue hierarchy** output showing parent and child queues with GPU quotas
- [ ] **PodGroup** output showing auto-created groups for gang-scheduled workloads
- [ ] **Fractional GPU** pods running on the same node via `gpu-fraction` annotation
- [ ] **Preemption events** showing priority-based workload eviction
- [ ] **Metrics output** showing queue GPU allocation

## Verification Checklist

- [ ] KAI Scheduler v0.14.0 deployed with all components running
- [ ] Queue hierarchy created: cluster-root → training/inference/research queues
- [ ] Workloads scheduled via `kai.scheduler/queue` label
- [ ] Fractional GPU sharing enabled and working (`global.gpuSharing=true`)
- [ ] Gang scheduling demonstrated (PodGroup auto-created, all-or-nothing)
- [ ] Priority preemption working (value >= 100 preempts value < 100)
- [ ] KAI Prometheus metrics accessible

## Troubleshooting

### Pods Not Being Scheduled by KAI

**Verify `schedulerName` is set:**
```bash
kubectl get pod <pod-name> -o jsonpath='{.spec.schedulerName}'
# Must be "kai-scheduler"
```

**Verify queue label exists:**
```bash
kubectl get pod <pod-name> -o jsonpath='{.metadata.labels.kai\.scheduler/queue}'
# Must match an existing leaf queue
```

**Check scheduler logs:**
```bash
kubectl logs -n kai-scheduler -l app=kai-scheduler-default --tail=50
```

### PodGroup Not Being Created

**Check PodGrouper logs:**
```bash
kubectl logs -n kai-scheduler -l app=pod-grouper --tail=50
```

**Verify the pod has an owner reference** (standalone pods without owners get individual PodGroups):
```bash
kubectl get pod <pod-name> -o jsonpath='{.metadata.ownerReferences}'
```

### Fractional GPU Not Working

**Verify GPU sharing is enabled:**
```bash
helm get values kai-scheduler -n kai-scheduler | grep gpuSharing
# Should show: true
```

**Check reservation pods:**
```bash
kubectl get pods -n kai-resource-reservation
# Reservation pods hold GPU slots for fractional workloads
```

### Workloads Submitted to Wrong Namespace

**Important:** Do NOT submit workloads to the `kai-scheduler` namespace. Use dedicated workload namespaces:
```bash
# Wrong:
kubectl apply -f workload.yaml -n kai-scheduler  # ← DON'T DO THIS

# Correct:
kubectl apply -f workload.yaml -n default
```

## Key Takeaways

1. **KAI Scheduler** is the open-source GPU scheduling engine from NVIDIA — the same core used in Run:ai commercial, but without the web UI, CLI, or memory-enforced fractions
2. **Queue hierarchy** (`scheduling.run.ai/v2`) provides guaranteed GPU quotas with over-quota borrowing, similar to Run:ai's Departments/Projects but managed via CRDs
3. **PodGrouper** automatically creates PodGroup resources by detecting workload types (PyTorchJob, RayCluster, etc.), enabling gang scheduling without manual configuration
4. **Fractional GPU** via annotations (`gpu-fraction`, `gpu-memory`) enables scheduling-level GPU sharing, but applications must self-regulate memory usage
5. **Priority preemption** follows a simple rule: PriorityClass value >= 100 is non-preemptible, < 100 is preemptible
6. **Bin packing** (default strategy) consolidates workloads onto fewer nodes, maximizing GPU utilization

## References

- [KAI Scheduler GitHub](https://github.com/kai-scheduler/KAI-Scheduler)
- [KAI Scheduler v0.14.0 Release](https://github.com/kai-scheduler/KAI-Scheduler/releases/tag/v0.14.0)
- [NVIDIA Blog: Open-Sourcing Run:ai Scheduler](https://developer.nvidia.com/blog/nvidia-open-sources-runai-scheduler-to-foster-community-collaboration/)
- [Queue CRD API Reference](https://github.com/kai-scheduler/KAI-Scheduler/tree/main/pkg/apis/scheduling)
- [PodGrouper Workload Plugins](https://github.com/kai-scheduler/KAI-Scheduler/tree/main/internal/podgrouper/podgrouper/plugins)

## Related Labs

- [Lab 5.4 - NVIDIA Run:ai (Commercial)](lab-5.4-runai-gpu-orchestration.md) — Full commercial platform with web UI, CLI, and memory-enforced fractions
- [Lab 5.1 - GPU Cluster Setup](lab-5.1-gpu-cluster-setup.md) — GPU Operator deployment and basic scheduling
