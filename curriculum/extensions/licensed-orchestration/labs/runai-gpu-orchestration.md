# Lab 5.4 - NVIDIA Run:ai GPU Orchestration

---

## Lab Navigation

| Track | Tier | Duration |
|-------|------|----------|
| Foundation | Required | 3 hours |

### Week 5 Learning Paths

```
FOUNDATION (Required)                              CHOOSE YOUR PATH
━━━━━━━━━━━━━━━━━━━━                              ━━━━━━━━━━━━━━━━
5.1 ➔ 5.2 ➔ 5.3 ➔ [5.4] ➔ 5.5 ➔ 5.6 ➔ 5.7 ➔ 5.8  ──►  ML Platforms (5.9-5.10)
                     ↑                                     Compliance (5.11-5.12)
                YOU ARE HERE                               Advanced (5.13-5.16)
```

| Previous | Current | Next |
|----------|---------|------|
| [Lab 5.3 - KAI Scheduler](lab-5.3-kai-scheduler.md) | **Lab 5.4 - NVIDIA Run:ai** | [Lab 5.5 - vLLM Inference](lab-5.5-vllm-inference.md) |

---

## Table of Contents

- [Objective](#objective)
- [Prerequisites](#prerequisites)
- [Background](#background)
  - [What is NVIDIA Run:ai?](#what-is-nvidia-runai)
  - [Run:ai vs KAI Scheduler](#runai-vs-kai-scheduler)
  - [Architecture](#architecture)
- [Lab Environment](#lab-environment)
- [Tasks](#tasks)
  - [Task 1: Deploy Run:ai Cluster Component](#task-1-deploy-runai-cluster-component-30-min)
  - [Task 2: Configure Departments and Projects](#task-2-configure-departments-and-projects-25-min)
  - [Task 3: Install and Configure the Run:ai CLI](#task-3-install-and-configure-the-runai-cli-15-min)
  - [Task 4: Submit Training Workloads](#task-4-submit-training-workloads-30-min)
  - [Task 5: Fractional GPU Allocation](#task-5-fractional-gpu-allocation-30-min)
  - [Task 6: Distributed Training with Gang Scheduling](#task-6-distributed-training-with-gang-scheduling-30-min)
  - [Task 7: Priority, Preemption, and Over-Quota](#task-7-priority-preemption-and-over-quota-20-min)
  - [Task 8: Explore the Run:ai Dashboard](#task-8-explore-the-runai-dashboard-15-min)
  - [Task 9: k0rdent Integration Patterns](#task-9-k0rdent-integration-patterns-15-min)
- [Deliverables](#deliverables)
- [Verification Checklist](#verification-checklist)
- [Troubleshooting](#troubleshooting)
- [Key Takeaways](#key-takeaways)
- [References](#references)
- [Next Lab](#next-lab)

**Duration:** 3 hours
**Type:** Hands-on Technical
**Environment:** GPU Lab

## Objective

Deploy and operate NVIDIA Run:ai for enterprise GPU orchestration on a k0rdent-managed cluster. You will connect a cluster to the Run:ai control plane, configure organizational structure (Departments and Projects), submit training and inference workloads via the `runai` CLI, use fractional GPU allocation with memory enforcement, and explore the Run:ai monitoring dashboard.

## Prerequisites

- Completed Lab 5.1 (GPU Operator deployed via k0rdent catalog)
- Kubernetes cluster with 2+ GPU nodes (k0rdent-managed)
- NVIDIA GPU Operator v25.3-25.10 installed
- `kubectl` and `helm` (v3.14+) installed
- A working ingress controller validated for your Run:ai release
- Run:ai control plane URL and admin credentials (provided by instructor)

> **Note:** This lab uses the NVIDIA Run:ai **commercial platform** (v2.24). Run:ai requires a license from NVIDIA. In a training environment, your instructor provides access to a shared Run:ai control plane. For the open-source KAI Scheduler alternative, see [Lab 5.3 - KAI Scheduler](lab-5.3-kai-scheduler.md).

## Background

### What is NVIDIA Run:ai?

NVIDIA Run:ai is an enterprise AI orchestration platform that sits on top of Kubernetes to optimize GPU utilization and enforce governance across teams and workloads. Unlike basic Kubernetes GPU scheduling (one-GPU-per-pod), Run:ai provides:

- **Fractional GPUs** with memory enforcement via separate virtual address spaces
- **Fair-share quotas** with automatic over-quota borrowing and preemption
- **Gang scheduling** built into the scheduler (no separate installation needed)
- **Topology-aware placement** for multi-node distributed training
- **Web dashboard** with real-time GPU utilization, quota tracking, and analytics
- **Workload types**: training (standard/distributed), workspace (interactive), inference (autoscaling)

### Run:ai vs KAI Scheduler

In 2025, NVIDIA open-sourced the core scheduling engine from Run:ai as the **KAI Scheduler**. The relationship:

| Capability | KAI Scheduler (Open-Source) | Run:ai (Commercial) |
|-----------|---------------------------|---------------------|
| GPU scheduling engine | Yes | Yes (same core) |
| Fractional GPU | Basic (time-slicing) | Memory-enforced virtual address spaces |
| Web UI / Dashboard | No | Yes |
| Departments & Projects | No | Yes |
| `runai` CLI | No | Yes |
| Multi-cluster management | No | Yes |
| Inference autoscaling | No | Yes (Knative-based) |
| RBAC & SSO integration | No | Yes |
| Support & SLA | Community | NVIDIA Enterprise |

### Architecture

Run:ai uses a **control plane + cluster** architecture:

```
┌─────────────────────────────────────────────────────────────────────┐
│                  Run:ai Control Plane (SaaS or Self-Hosted)         │
│  ┌────────────┐  ┌──────────────┐  ┌───────────┐  ┌─────────────┐ │
│  │  Web UI &  │  │ Scheduling   │  │  Quota &  │  │   API &     │ │
│  │ Dashboard  │  │   Policies   │  │ Fairness  │  │    Auth     │ │
│  └────────────┘  └──────────────┘  └───────────┘  └─────────────┘ │
└─────────────────────────────┬───────────────────────────────────────┘
                              │ HTTPS
            ┌─────────────────┼─────────────────┐
            ▼                 ▼                 ▼
┌───────────────────┐ ┌───────────────────┐ ┌───────────────────┐
│  Cluster A (Prod) │ │  Cluster B (Dev)  │ │  Cluster C (Res)  │
│ ┌───────────────┐ │ │ ┌───────────────┐ │ │ ┌───────────────┐ │
│ │ runai-cluster │ │ │ │ runai-cluster │ │ │ │ runai-cluster │ │
│ │  (Helm chart) │ │ │ │  (Helm chart) │ │ │ │  (Helm chart) │ │
│ ├───────────────┤ │ │ ├───────────────┤ │ │ ├───────────────┤ │
│ │  Run:ai       │ │ │ │  Run:ai       │ │ │ │  Run:ai       │ │
│ │  Scheduler    │ │ │ │  Scheduler    │ │ │ │  Scheduler    │ │
│ ├───────────────┤ │ │ ├───────────────┤ │ │ ├───────────────┤ │
│ │ GPU Operator  │ │ │ │ GPU Operator  │ │ │ │ GPU Operator  │ │
│ └───────────────┘ │ └───────────────┘ │ └───────────────┘ │
│  [GPU][GPU][GPU]  │  [GPU][GPU]       │  [GPU][GPU][GPU]  │
└───────────────────┘ └───────────────────┘ └───────────────────┘
```

The **control plane** can be NVIDIA-hosted (SaaS) or self-hosted in your own infrastructure. Each Kubernetes cluster runs the **runai-cluster** Helm chart, which deploys the Run:ai scheduler, fractional GPU components, and telemetry agents. The cluster component communicates back to the control plane over HTTPS.

## Lab Environment

**Provided by Instructor:**
- Run:ai control plane URL (e.g., `https://runai.training.example.com`)
- Admin username and password
- Cluster UID and client secret for cluster registration

**Cluster Requirements:**
- Kubernetes 1.33-1.35
- NVIDIA GPU Operator v25.3-25.10
- Ingress controller validated for your Run:ai release
- Default StorageClass configured
- Prometheus installed (for cluster metrics)
- 4+ GPUs across 2+ nodes

## Tasks

### Task 1: Deploy Run:ai Cluster Component (30 min)

The Run:ai control plane is already deployed (by your instructor or as SaaS). In this task, you connect your k0rdent-managed GPU cluster to the control plane by installing the **runai-cluster** Helm chart.

1. **Add the Run:ai Helm Repository**

   ```bash
   helm repo add runai \
     https://runai.jfrog.io/artifactory/api/helm/run-ai-charts \
     --force-update
   helm repo update
   ```

2. **Verify Prerequisites**

   Before installing, confirm the GPU Operator and ingress controller are running:

   ```bash
   # GPU Operator pods should be Running
   kubectl get pods -n gpu-operator -l app.kubernetes.io/managed-by=gpu-operator

   # A supported ingress controller should be Running
   kubectl get pods -A | grep -E 'ingress-nginx|haproxy'

   # Default StorageClass must exist
   kubectl get storageclass -o name

   # Prometheus must be installed
   kubectl get pods -A -l app.kubernetes.io/name=prometheus
   ```

3. **Install the Run:ai Cluster Component**

   Use the credentials provided by your instructor:

   ```bash
   # Set variables from instructor-provided values
   CONTROL_PLANE_URL="https://runai.training.example.com"
   CLIENT_SECRET="<provided-by-instructor>"
   CLUSTER_UID="<provided-by-instructor>"
   CLUSTER_FQDN="gpu-cluster.training.example.com"

   helm upgrade -i runai-cluster runai/runai-cluster \
     --namespace runai \
     --create-namespace \
     --set controlPlane.url=${CONTROL_PLANE_URL} \
     --set controlPlane.clientSecret=${CLIENT_SECRET} \
     --set cluster.uid=${CLUSTER_UID} \
     --set cluster.url=https://${CLUSTER_FQDN}
   ```

4. **Verify Installation**

   ```bash
   # All pods in the runai namespace should reach Running state
   kubectl get pods -n runai

   # Expected pods include:
   #   runai-scheduler-*
   #   runai-agent-*
   #   runai-cluster-sync-*
   #   runai-container-toolkit-*

   # Check the scheduler is registered
   kubectl get pods -n runai -l app=runai-scheduler

   # Verify the cluster appears in the control plane
   # (Check the Run:ai web UI under Infrastructure > Clusters)
   ```

5. **Verify GPU Visibility**

   ```bash
   # Run:ai should detect all GPUs through the GPU Operator
   kubectl get nodes -o json | \
     jq -r '.items[] | select(.status.allocatable["nvidia.com/gpu"] != null) |
     "\(.metadata.name): \(.status.allocatable["nvidia.com/gpu"]) GPUs"'
   ```

> **Troubleshooting:** If pods in `runai` namespace show `ImagePullBackOff`, verify network connectivity to `runai.jfrog.io`. For air-gapped environments, your instructor will provide a local registry mirror and you must set `global.image.registry` in the Helm values.

### Task 2: Configure Departments and Projects (25 min)

Run:ai organizes GPU resources hierarchically: **Departments** contain **Projects**, and Projects contain **Workloads**. GPU quotas flow from Departments down to Projects.

1. **Access the Run:ai Web UI**

   Open your browser and navigate to the control plane URL provided by your instructor:

   ```
   https://runai.training.example.com
   ```

   Log in with the admin credentials provided.

2. **Create a Department**

   In the Run:ai UI:
   - Navigate to **Organization > Departments**
   - Click **+ NEW DEPARTMENT**
   - Configure:
     - **Name:** `ai-training`
     - **GPU Quota:** `4` (guaranteed GPUs from the node pool)
     - **Over-quota:** Enabled (allows borrowing idle GPUs beyond the quota)
     - **Rank:** Medium (scheduling priority relative to other departments)

3. **Create Projects Within the Department**

   Projects are the scheduling unit — workloads run within a Project.

   Create three projects under the `ai-training` department:

   | Project | GPU Quota | Over-Quota | Purpose |
   |---------|-----------|------------|---------|
   | `training-prod` | 2 | Enabled | Production training jobs |
   | `inference-prod` | 1 | Enabled | Model serving |
   | `research-dev` | 1 | Enabled | Experimentation |

   For each project:
   - Navigate to **Organization > Projects**
   - Click **+ NEW PROJECT**
   - Select department `ai-training`
   - Set the GPU quota and enable over-quota
   - Click **CREATE**

4. **Verify Quota Configuration**

   In the UI, navigate to **Organization > Departments** and verify the `ai-training` department shows:
   - Total allocated quota: 4 GPUs
   - Three child projects with their respective quotas

   > **Understanding Over-Quota:** When over-quota is enabled, a project with a 1-GPU quota can use 2+ GPUs if other projects are idle. The moment the actual quota owner submits a workload, Run:ai automatically preempts the over-quota workloads to return resources. This maximizes GPU utilization while preserving fairness.

### Task 3: Install and Configure the Run:ai CLI (15 min)

The `runai` CLI lets you submit and manage workloads from the terminal.

1. **Download the CLI**

   The CLI binary is served from the Run:ai control plane:
   - In the Run:ai web UI, click the **Help (?)** icon in the top bar
   - Select **Researcher Command Line Interface**
   - Choose your cluster and operating system (Linux/macOS/Windows)
   - Copy and run the provided installer command

   For Linux, it typically looks like:

   ```bash
   # The exact URL is provided by the Run:ai UI
   wget https://runai.training.example.com/cli/linux -O runai
   chmod +x runai
   sudo mv runai /usr/local/bin/
   ```

2. **Authenticate and Configure**

   ```bash
   # Verify installation
   runai version

   # Authenticate with the control plane
   runai login

   # Set your default cluster
   runai cluster list
   runai cluster set <your-cluster-name>

   # Set your default project
   runai project list
   runai project set training-prod

   # Enable shell completion (bash)
   source <(runai completion bash)
   ```

3. **Verify CLI Connectivity**

   ```bash
   # List available projects (should show all 3 from Task 2)
   runai project list

   # List current workloads (should be empty)
   runai workload list
   ```

### Task 4: Submit Training Workloads (30 min)

Now submit GPU workloads using the `runai` CLI. Run:ai supports three workload types: **training** (batch), **workspace** (interactive), and **inference** (serving).

1. **Submit a Standard Training Job**

   ```bash
   runai training standard submit gpu-test \
     -p training-prod \
     -i nvcr.io/nvidia/cuda:12.6.0-base-ubi9 \
     -g 1 \
     --command -- bash -c "nvidia-smi && echo 'GPU test passed!' && sleep 30"
   ```

2. **Monitor the Workload**

   ```bash
   # List all workloads in the project
   runai workload list -p training-prod

   # Describe the workload (status, events, resource allocation)
   runai workload describe gpu-test -p training-prod

   # View logs
   kubectl logs -n runai-training-prod -l runai/workload=gpu-test
   ```

3. **Submit a PyTorch Training Job**

   ```bash
   runai training standard submit mnist-train \
     -p training-prod \
     -i pytorch/pytorch:2.6.0-cuda12.6-cudnn9-runtime \
     -g 1 \
     --cpu-core-request 4 \
     --cpu-memory-request 8G \
     --command -- python -c "
   import torch
   print(f'PyTorch {torch.__version__}')
   print(f'CUDA available: {torch.cuda.is_available()}')
   if torch.cuda.is_available():
       print(f'GPU: {torch.cuda.get_device_name(0)}')
       # Simple matmul benchmark
       x = torch.randn(4096, 4096, device='cuda')
       y = torch.randn(4096, 4096, device='cuda')
       torch.cuda.synchronize()
       import time
       start = time.time()
       for _ in range(100):
           z = torch.matmul(x, y)
       torch.cuda.synchronize()
       elapsed = time.time() - start
       print(f'100x matmul (4096x4096): {elapsed:.2f}s')
   "
   ```

4. **Submit an Interactive Workspace**

   Workspaces are interactive sessions (e.g., Jupyter notebooks) that persist until explicitly stopped:

   ```bash
   runai workspace submit jupyter-dev \
     -p research-dev \
     -i jupyter/scipy-notebook:latest \
     --gpu-devices-request 1 \
     --external-url container=8888 \
     --command -- start-notebook.sh \
       --NotebookApp.token=''
   ```

   After the workspace is running, the Run:ai UI will show a URL to access the Jupyter notebook.

5. **Clean Up Training Jobs**

   ```bash
   # Delete completed workloads
   runai workload delete gpu-test -p training-prod
   runai workload delete mnist-train -p training-prod
   ```

### Task 5: Fractional GPU Allocation (30 min)

Run:ai provides true fractional GPU allocation using **separate virtual address spaces** for GPU memory. This is fundamentally different from NVIDIA time-slicing (which just multiplexes access) or MIG (which physically partitions the GPU).

1. **Understanding Fractional GPU Modes**

   | Mode | Mechanism | Memory Isolation | Compute Isolation |
   |------|-----------|-----------------|-------------------|
   | Run:ai Fractions | Virtual address spaces | Yes (enforced) | No (shared) |
   | NVIDIA Time-Slicing | Context switching | No | No |
   | NVIDIA MIG | Hardware partitioning | Yes | Yes |

   > **Important:** Run:ai fractions and MIG **cannot coexist on the same node**. Choose one approach per node pool.

2. **Submit a Half-GPU Workload**

   ```bash
   # Request 50% of a GPU
   runai training standard submit frac-half \
     -p research-dev \
     -i nvcr.io/nvidia/cuda:12.6.0-base-ubi9 \
     --gpu-portion-request 0.5 \
     --command -- bash -c "
       echo 'Allocated 50% of GPU'
       nvidia-smi
       sleep 120
     "
   ```

3. **Submit a Second Workload on the Same GPU**

   ```bash
   # Request the other 50%
   runai training standard submit frac-other-half \
     -p research-dev \
     -i nvcr.io/nvidia/cuda:12.6.0-base-ubi9 \
     --gpu-portion-request 0.5 \
     --command -- bash -c "
       echo 'Allocated other 50% of GPU'
       nvidia-smi
       sleep 120
     "
   ```

4. **Verify Both Run on the Same Physical GPU**

   ```bash
   # Both workloads should be Running
   runai workload list -p research-dev

   # Check they share the same node and GPU
   kubectl get pods -n runai-research-dev -o wide
   ```

5. **Test GPU Memory Enforcement**

   Submit a workload that requests 25% but tries to allocate more memory than allowed:

   ```bash
   runai training standard submit frac-memory-test \
     -p research-dev \
     -i pytorch/pytorch:2.6.0-cuda12.6-cudnn9-runtime \
     --gpu-portion-request 0.25 \
     --command -- python -c "
   import torch
   print(f'Requesting 25% GPU fraction')
   # Try to allocate tensors until OOM
   tensors = []
   total_mb = 0
   try:
       while True:
           t = torch.zeros(256, 1024, 1024, device='cuda')  # ~1GB each
           tensors.append(t)
           total_mb += 1024
           print(f'Allocated {total_mb} MB on GPU')
   except RuntimeError as e:
       print(f'OOM at {total_mb} MB: {e}')
       print('Memory enforcement is working!')
   "
   ```

   The workload should hit an out-of-memory error at approximately 25% of the GPU's total memory, demonstrating that Run:ai enforces the fraction limit.

6. **Dynamic Fractions (Request vs Limit)**

   Dynamic fractions let a workload burst beyond its guaranteed allocation when resources are idle:

   ```bash
   # Request 25% guaranteed, burst up to 75% when available
   runai training standard submit frac-dynamic \
     -p research-dev \
     -i nvcr.io/nvidia/cuda:12.6.0-base-ubi9 \
     --gpu-portion-request 0.25 \
     --gpu-portion-limit 0.75 \
     --command -- bash -c "
       echo 'Dynamic fraction: 25% guaranteed, up to 75%'
       nvidia-smi
       sleep 180
     "
   ```

   > **How It Works:** The workload is guaranteed 25% of GPU memory. If no other workload uses the remaining GPU, it can burst up to 75%. When another workload claims its share, Run:ai's GPUOOMKiller terminates processes that exceed their guaranteed allocation.

7. **Clean Up**

   ```bash
   runai workload delete frac-half -p research-dev
   runai workload delete frac-other-half -p research-dev
   runai workload delete frac-memory-test -p research-dev
   runai workload delete frac-dynamic -p research-dev
   ```

### Task 6: Distributed Training with Gang Scheduling (30 min)

Run:ai provides **built-in gang scheduling** — all pods for a distributed training job are scheduled atomically (all-or-nothing). No separate scheduler (like Volcano) is needed.

1. **Submit a Distributed PyTorch Training Job**

   The `runai training pytorch submit` command handles distributed training with automatic environment variable injection (`MASTER_ADDR`, `MASTER_PORT`, `WORLD_SIZE`, `RANK`):

   ```bash
   runai training pytorch submit distributed-train \
     -p training-prod \
     -i pytorch/pytorch:2.6.0-cuda12.6-cudnn9-runtime \
     --workers 3 \
     -g 1 \
     --command -- python -c "
   import torch
   import torch.distributed as dist
   import os

   rank = int(os.environ['RANK'])
   world_size = int(os.environ['WORLD_SIZE'])
   master = os.environ['MASTER_ADDR']

   print(f'Worker {rank}/{world_size} starting (master={master})')
   print(f'GPU: {torch.cuda.get_device_name(0)}')

   dist.init_process_group(backend='nccl', rank=rank, world_size=world_size)

   # All-reduce test
   tensor = torch.ones(1000, device='cuda') * rank
   dist.all_reduce(tensor, op=dist.ReduceOp.SUM)
   expected = sum(range(world_size))

   if rank == 0:
       print(f'All-reduce result: {tensor[0].item()}, expected: {expected}')
       print('Distributed training connectivity verified!')

   dist.destroy_process_group()
   "
   ```

   This creates 4 pods (1 master + 3 workers), all gang-scheduled together.

2. **Observe Gang Scheduling Behavior**

   ```bash
   # Watch pods — all 4 should transition to Running simultaneously
   kubectl get pods -n runai-training-prod -l runai/workload=distributed-train -w

   # If insufficient GPUs, ALL pods stay Pending (none start partially)
   runai workload describe distributed-train -p training-prod
   ```

3. **Understand Topology-Aware Placement**

   Run:ai uses node labels to understand network topology and place distributed training pods close together for optimal NCCL performance:

   ```bash
   # Check what topology labels exist on your nodes
   kubectl get nodes -o json | jq -r '
     .items[] | "\(.metadata.name): region=\(.metadata.labels["topology.kubernetes.io/region"] // "none"), zone=\(.metadata.labels["topology.kubernetes.io/zone"] // "none")"
   '
   ```

   The Run:ai scheduler automatically prefers to place workers on the same rack/zone/region when possible. In the Run:ai UI under **Infrastructure > Topology**, administrators configure the label hierarchy.

4. **Clean Up**

   ```bash
   runai workload delete distributed-train -p training-prod
   ```

### Task 7: Priority, Preemption, and Over-Quota (20 min)

Run:ai's fair-share scheduling automatically manages priority and preemption based on project quotas.

1. **Observe Over-Quota Behavior**

   First, submit workloads that exceed the `research-dev` project's 1-GPU quota:

   ```bash
   # Submit 3 single-GPU jobs (quota is 1 GPU)
   for i in 1 2 3; do
     runai training standard submit over-quota-${i} \
       -p research-dev \
       -i nvcr.io/nvidia/cuda:12.6.0-base-ubi9 \
       -g 1 \
       --command -- sleep 300
   done
   ```

   ```bash
   # Check status — job 1 runs on quota, jobs 2-3 may run on over-quota
   # (if other projects are idle)
   runai workload list -p research-dev
   ```

2. **Trigger Preemption**

   Now submit a workload in `training-prod` (which has quota). Run:ai will preempt the over-quota workloads in `research-dev`:

   ```bash
   runai training standard submit preempt-test \
     -p training-prod \
     -i nvcr.io/nvidia/cuda:12.6.0-base-ubi9 \
     -g 2 \
     --command -- bash -c "echo 'Got my GPUs via preemption!' && nvidia-smi && sleep 120"
   ```

   ```bash
   # Watch research-dev over-quota jobs get preempted
   runai workload list -p research-dev
   runai workload list -p training-prod

   # View preemption events
   kubectl get events -n runai-research-dev --sort-by='.lastTimestamp' | \
     grep -i preempt
   ```

3. **Understand the Fair-Share Model**

   Run:ai's scheduling priority works as follows:

   ```
   Priority Order:
   1. In-quota workloads (guaranteed — never preempted by other projects)
   2. Over-quota workloads (borrowing idle GPUs — preemptible)
   3. Lower-ranked projects yield to higher-ranked projects

   Within a project:
   - FIFO ordering by default
   - Configurable scheduling rules in Run:ai UI (Settings > Scheduling Rules)
   ```

4. **Clean Up**

   ```bash
   for i in 1 2 3; do
     runai workload delete over-quota-${i} -p research-dev 2>/dev/null
   done
   runai workload delete preempt-test -p training-prod
   ```

### Task 8: Explore the Run:ai Dashboard (15 min)

The Run:ai web UI provides real-time visibility into GPU utilization, workload status, and quota consumption.

1. **Overview Dashboard**

   Navigate to the **Home / Overview** page in the Run:ai UI. Key widgets:

   | Widget | Shows |
   |--------|-------|
   | Ready Nodes | Number of healthy GPU nodes |
   | GPU Devices | Total GPUs in the cluster |
   | Allocated Resources | Currently consumed GPUs, CPUs, memory |
   | Workload Status | Running, pending, error counts |
   | Allocation Ratio | GPU utilization over time |

2. **Analytics Dashboard**

   Navigate to **Analytics** to see historical data:
   - **GPU Allocation** over time (per department/project)
   - **GPU Utilization** efficiency (allocated vs actually used)
   - **Pending Queue** analysis (how long workloads wait)
   - **Node Availability** (detect hardware failures)

3. **Project Quota View**

   Navigate to **Organization > Projects** and click on `training-prod`:
   - Current GPU usage vs quota
   - Over-quota consumption
   - Running and pending workload counts

4. **Generate a Usage Snapshot from CLI**

   ```bash
   echo "=== Run:ai Cluster Status ==="

   echo -e "\n--- Projects ---"
   runai project list

   echo -e "\n--- All Workloads ---"
   runai workload list -A

   echo -e "\n--- GPU Nodes ---"
   kubectl get nodes -o json | jq -r '
     .items[] |
     select(.status.allocatable["nvidia.com/gpu"] != null) |
     "\(.metadata.name): \(.status.allocatable["nvidia.com/gpu"]) GPUs, \(.status.allocatable.cpu) CPU, \(.status.allocatable.memory) RAM"
   '
   ```

### Task 9: k0rdent Integration Patterns (15 min)

Run:ai is a commercial product distributed through NVIDIA's registry, not through the k0rdent open-source catalog. Here are the patterns for deploying Run:ai on k0rdent-managed clusters.

1. **Understand the Integration Architecture**

   ```
   k0rdent Management Cluster
   ├── ClusterDeployment (provisions GPU cluster)
   │   └── serviceSpec:
   │       ├── gpu-operator-25-10-0  (from k0rdent catalog)
   │       └── [custom-runai-template] (if created)
   │
   Run:ai Control Plane (separate deployment)
   └── Cluster registration
       └── runai-cluster Helm chart → deployed on k0rdent child cluster
   ```

   Since there is no `runai` ServiceTemplate in the k0rdent catalog, you have two deployment options:

2. **Option A: Direct Helm Installation (Recommended for Training)**

   After k0rdent provisions a GPU cluster with the GPU Operator, install Run:ai directly:

   ```bash
   # 1. Get kubeconfig for the k0rdent-managed cluster
   kubectl get secret -n kcm-system <cluster-name>-kubeconfig \
     -o jsonpath='{.data.value}' | base64 -d > /tmp/child-kubeconfig

   # 2. Install Run:ai cluster component on the child cluster
   KUBECONFIG=/tmp/child-kubeconfig \
   helm upgrade -i runai-cluster runai/runai-cluster \
     --namespace runai \
     --create-namespace \
     --set controlPlane.url=${CONTROL_PLANE_URL} \
     --set controlPlane.clientSecret=${CLIENT_SECRET} \
     --set cluster.uid=${CLUSTER_UID} \
     --set cluster.url=https://${CLUSTER_FQDN}
   ```

3. **Option B: Custom ServiceTemplate (For Production Automation)**

   For repeatable deployments across multiple clusters, create a custom ServiceTemplate:

   ```yaml
   # This requires creating a HelmRepository source for the Run:ai chart
   # and packaging it as a k0rdent ServiceTemplate

   # Step 1: Create a Flux HelmRepository in the management cluster
   apiVersion: source.toolkit.fluxcd.io/v1
   kind: HelmRepository
   metadata:
     name: runai-charts
     namespace: kcm-system
   spec:
     interval: 10m
     url: https://runai.jfrog.io/artifactory/api/helm/run-ai-charts
     type: default
   ```

   > **Note:** Creating custom ServiceTemplates is an advanced topic. The Run:ai Helm chart requires cluster-specific values (`cluster.uid`, `controlPlane.clientSecret`) that must be provided per-deployment. Consult k0rdent documentation on custom ServiceTemplate authoring.

4. **Prerequisites from k0rdent Catalog**

   Regardless of how Run:ai is installed, these k0rdent catalog templates provide the prerequisites:

   ```bash
   # Install GPU Operator from k0rdent catalog (required by Run:ai)
   helm upgrade --install gpu-operator \
     oci://ghcr.io/k0rdent/catalog/charts/kgst \
     --set "chart=gpu-operator:25.10.0" \
     -n kcm-system

   # GPU Operator is deployed to the child cluster via MultiClusterService
   ```

## Deliverables

- [ ] **Screenshot** of Run:ai cluster connected in the web UI (Infrastructure > Clusters)
- [ ] **Screenshot** of Departments and Projects with GPU quotas configured
- [ ] **CLI output** of `runai workload list` showing completed training jobs
- [ ] **CLI output** demonstrating fractional GPU allocation (two 0.5 workloads on one GPU)
- [ ] **Screenshot** of Run:ai Overview dashboard showing GPU utilization
- [ ] **CLI output** showing over-quota preemption events

## Verification Checklist

- [ ] Run:ai cluster component deployed and connected to control plane
- [ ] Department `ai-training` created with 4-GPU quota
- [ ] Three projects created with appropriate quotas
- [ ] `runai` CLI authenticated and configured
- [ ] Standard training job submitted and completed successfully
- [ ] Fractional GPU workloads sharing a single physical GPU
- [ ] Distributed PyTorch training with gang scheduling completed
- [ ] Over-quota borrowing and preemption observed
- [ ] Run:ai dashboard showing GPU utilization metrics

## Troubleshooting

### Cluster Not Connecting to Control Plane

**Check cluster component pods:**
```bash
kubectl get pods -n runai
kubectl logs -n runai -l app=runai-agent --tail=50
```

**Verify network connectivity:**
```bash
# The cluster must reach the control plane over HTTPS
kubectl run curl-test --rm -it --image=curlimages/curl -- \
  curl -s -o /dev/null -w "%{http_code}" ${CONTROL_PLANE_URL}/health
```

**Check TLS certificate:**
```bash
# If using self-signed certs, you may need:
# --set global.customCA.enabled=true in the Helm install
kubectl get secret -n runai runai-ca-cert 2>/dev/null
```

### CLI Authentication Fails

**Re-authenticate:**
```bash
runai login
# If using service accounts (CI/CD):
runai login --access-key <KEY_ID> --access-secret <KEY_SECRET>
```

**Verify cluster is set:**
```bash
runai cluster list
runai cluster set <cluster-name>
```

### Fractional GPU Not Enforcing Memory Limits

**Check that the Run:ai container toolkit is running:**
```bash
kubectl get daemonset -n runai runai-container-toolkit-daemonset
kubectl get pods -n runai -l app=runai-container-toolkit
```

**Verify fractional GPU is not conflicting with MIG:**
```bash
# MIG and Run:ai fractions cannot coexist on the same node
nvidia-smi mig -lgi  # Should show no MIG instances on fraction nodes
```

### Gang Scheduling Pods Stay Pending

**Check GPU availability:**
```bash
# Distributed jobs need ALL GPUs available simultaneously
kubectl get nodes -o json | jq -r '
  .items[] |
  select(.status.allocatable["nvidia.com/gpu"] != null) |
  "\(.metadata.name): allocatable=\(.status.allocatable["nvidia.com/gpu"])"
'

# Check what is consuming GPUs
runai workload list -A
```

**Reduce worker count if insufficient GPUs:**
```bash
# For a 4-GPU cluster, use --workers 3 (1 master + 3 workers = 4 GPUs)
runai training pytorch submit test-gang \
  -p training-prod \
  -i pytorch/pytorch:2.6.0-cuda12.6-cudnn9-runtime \
  --workers 3 -g 1 \
  --command -- python -c "import torch.distributed as dist; print('OK')"
```

### Workloads Stuck in Pending (Quota Exceeded)

**Check project quota usage:**
```bash
runai project list
# Look at the Used/Quota columns
```

**Delete completed or failed workloads to free quota:**
```bash
runai workload list -p <project-name>
runai workload delete <workload-name> -p <project-name>
```

## Key Takeaways

1. **Run:ai** is an enterprise GPU orchestration platform with a **control plane + cluster** architecture that provides centralized management across multiple Kubernetes clusters
2. **Fractional GPUs** use separate virtual address spaces for memory enforcement — distinct from time-slicing (no isolation) and MIG (hardware partitioning)
3. **Fair-share quotas** with over-quota borrowing maximize GPU utilization while guaranteeing each team their minimum allocation
4. **Gang scheduling** is built into Run:ai — distributed training jobs are scheduled atomically without needing a separate scheduler like Volcano
5. **The `runai` CLI** provides a user-friendly interface for submitting training, workspace, and inference workloads without writing Kubernetes YAML
6. **k0rdent integration** works by deploying the GPU Operator via the k0rdent catalog and installing Run:ai's cluster component via Helm on the managed cluster

## References

- [NVIDIA Run:ai Documentation](https://run-ai-docs.nvidia.com/)
- [Run:ai v2.24 Release Notes](https://run-ai-docs.nvidia.com/self-hosted/getting-started/whats-new/whats-new-2-24)
- [Run:ai CLI Reference](https://run-ai-docs.nvidia.com/self-hosted/reference/cli/runai/runai)
- [Run:ai Cluster Prerequisites](https://run-ai-docs.nvidia.com/self-hosted/getting-started/installation/install-using-helm/system-requirements)
- [GPU Fractions](https://run-ai-docs.nvidia.com/self-hosted/platform-management/runai-scheduler/resource-optimization/fractions)
- [Dynamic GPU Fractions](https://run-ai-docs.nvidia.com/self-hosted/platform-management/runai-scheduler/resource-optimization/dynamic-fractions)

## Next Lab

Proceed to [Lab 5.5 - vLLM Inference Service](lab-5.5-vllm-inference.md)

For the open-source KAI Scheduler alternative to Run:ai, see [Lab 5.3 - KAI Scheduler](lab-5.3-kai-scheduler.md).
