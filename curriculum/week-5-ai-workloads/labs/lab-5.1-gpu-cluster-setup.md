# Lab 5.1 - GPU Cluster Setup

---

## Lab Navigation

| Track | Tier | Duration |
|-------|------|----------|
| Foundation | Required | 3.5 hours |

### Week 5 Learning Paths

```
FOUNDATION (Required)                              CHOOSE YOUR PATH
━━━━━━━━━━━━━━━━━━━━                              ━━━━━━━━━━━━━━━━
[5.1] ➔ 5.2 ➔ 5.3 ➔ 5.4 ➔ 5.5 ➔ 5.6 ➔ 5.7 ➔ 5.8  ──►  ML Platforms (5.9-5.10)
  ↑                                                       Compliance (5.11-5.12)
YOU ARE HERE                                              Advanced (5.13-5.16)
```

| Previous | Current | Next |
|----------|---------|------|
| [Week 5 Overview](../README.md) | **Lab 5.1 - GPU Cluster Setup** | [Lab 5.2 - Service Catalog](lab-5.2-service-catalog.md) |

---

## Table of Contents

- [Objective](#objective)
- [Prerequisites](#prerequisites)
- [Background: GPU Communication Architecture](#background-gpu-communication-architecture)
  - [Understanding GPU Interconnects](#understanding-gpu-interconnects)
  - [What is NCCL?](#what-is-nccl)
  - [Why NCCL Configuration Matters](#why-nccl-configuration-matters)
- [Why Advanced GPU Schedulers?](#why-advanced-gpu-schedulers)
  - [Scheduler Options](#scheduler-options)
- [Pre-Lab: Deploy GPU Cluster via k0rdent](#pre-lab-deploy-gpu-cluster-via-k0rdent-15-min--15-min-wait)
- [Tasks](#tasks)
  - [Task 1: Verify GPU Environment](#task-1-verify-gpu-environment-15-min)
  - [Task 2: Deploy KAI Scheduler](#task-2-deploy-kai-scheduler-45-min)
  - [Task 3: Configure Scheduler Queues](#task-3-configure-scheduler-queues-30-min)
  - [Task 4: Test Gang Scheduling](#task-4-test-gang-scheduling-30-min)
  - [Task 5: Test Priority Preemption](#task-5-test-priority-preemption-30-min)
  - [Task 6: Configure Fractional GPU Sharing](#task-6-configure-fractional-gpu-sharing-20-min)
  - [Task 7: Configure Enterprise NCCL Settings](#task-7-configure-enterprise-nccl-settings-30-min)
  - [Task 8: Monitor Scheduler Metrics](#task-8-monitor-scheduler-metrics-15-min)
- [Deliverables](#deliverables)
- [Verification Checklist](#verification-checklist)
- [Cleanup](#cleanup)
- [Troubleshooting](#troubleshooting)
- [Key Takeaways](#key-takeaways)
- [References](#references)
- [Next Lab](#next-lab)

**Duration:** 3.5 hours
**Type:** Hands-on Technical
**Environment:** GPU Lab
**Validation Status:** All commands verified on live infrastructure

## Objective

Deploy and configure an advanced GPU scheduler for AI workloads on Kubernetes, enabling features like gang scheduling, fractional GPU allocation, priority queues, and topology-aware NCCL optimization that the default Kubernetes scheduler lacks.

## Prerequisites

- k0rdent management cluster access (via `lab-connect.sh`)
- AWS credentials configured in the management cluster
- kubectl access with cluster-admin privileges
- Familiarity with k0rdent ClusterDeployment (from [Lab 1.5](../../week-1-foundations/labs/lab-1.5-provision-managed-cluster.md))

> **k0rdent context:** This lab deploys a GPU cluster using the same `ClusterDeployment` pattern students learned in Week 1 Lab 1.5. The only difference is using a GPU instance type (`g5.12xlarge`) for the worker node.

---

## Background: GPU Communication Architecture

### Understanding GPU Interconnects

Before deploying a GPU scheduler, it is essential to understand the hardware topology that influences scheduling decisions:

```
Multi-GPU Node Architecture (e.g., g5.12xlarge with 4x A10G):
┌─────────────────────────────────────────────────────────────────┐
│                        4-GPU Node                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│    ┌─────┐              ┌─────┐                                 │
│    │GPU 0│◄────PCIe────►│GPU 1│                                 │
│    └──┬──┘    (~12GB/s) └──┬──┘                                 │
│       │                     │                                    │
│    ┌──▼──┐              ┌──▼──┐                                 │
│    │GPU 2│◄────PCIe────►│GPU 3│                                 │
│    └─────┘              └─────┘                                 │
│                                                                 │
│    A10G GPUs connected via PCIe Host Bridge (PHB)              │
│    No NVLink on A10G — this is expected for inference GPUs     │
│                                                                 │
│    For NVLink (V100/A100/H100), bandwidth = 300-900 GB/s       │
└─────────────────────────────────────────────────────────────────┘
```

### What is NCCL?

**NVIDIA Collective Communications Library (NCCL)** is the standard for GPU-to-GPU communication in distributed AI workloads. It automatically detects and utilizes:
- **NVLink/NVSwitch** for intra-node communication (600-900 GB/s)
- **RDMA/InfiniBand/EFA** for inter-node communication (200-400 Gb/s)
- **PCIe** as fallback (~12 GB/s for A10G)

### Why NCCL Configuration Matters

| GPU Type | Interconnect | Expected Bus BW | Use Case |
|----------|-------------|-----------------|----------|
| A10G (g5) | PCIe | ~3 GB/s | Inference, small training |
| V100 (p3) | NVLink 2.0 | ~100 GB/s | Training |
| A100 (p4d) | NVSwitch | ~500 GB/s | Large-scale training |
| H100 (p5) | NVSwitch | ~800 GB/s | Frontier training |

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

---

## Pre-Lab: Deploy GPU Cluster via k0rdent (15 min + ~10 min wait)

The GPU cluster is deployed via k0rdent ClusterDeployment -- the same pattern from Week 1 Lab 1.5.

### Step 1: Verify Provider Readiness

From the management cluster (SSH via `lab-connect.sh`):

```bash
# Verify AWS credentials are configured (from Lab 1.3)
kubectl get credentials -n kcm-system
# Expected: aws-cluster-identity-cred   READY=true

# Verify CAPA and k0smotron providers are ready
# On a fresh cluster, providers take 1-2 minutes to initialize after boot
kubectl get management kcm -o jsonpath='{.status.components.cluster-api-provider-aws.success}'
# Expected: true

kubectl get management kcm -o jsonpath='{.status.components.cluster-api-provider-k0sproject-k0smotron.success}'
# Expected: true
```

> **If either returns empty or false:** Wait 30 seconds and check again. Providers must be fully initialized before creating a ClusterDeployment, or the request will be rejected by the admission webhook.

### Step 2: Create GPU ClusterDeployment

```bash
# Check available templates
kubectl get clustertemplates -n kcm-system | grep aws-standalone

# Template to use: aws-standalone-cp-1-0-26
```

Create the ClusterDeployment:

```yaml
# Save as gpu-cluster-deployment.yaml
apiVersion: k0rdent.mirantis.com/v1beta1
kind: ClusterDeployment
metadata:
  name: gpu-cluster
  namespace: kcm-system
  labels:
    environment: training
    gpu-enabled: "true"
spec:
  template: aws-standalone-cp-1-0-26
  credential: aws-cluster-identity-cred
  dryRun: false
  cleanupOnDeletion: true
  config:
    region: us-east-1
    controlPlaneNumber: 1
    controlPlane:
      amiID: ami-00de3875b03809ec5  # Ubuntu 22.04 (REQUIRED - Amazon Linux 2 not supported by GPU Operator)
      instanceType: t3.medium
      rootVolumeSize: 50
    workersNumber: 1
    worker:
      amiID: ami-00de3875b03809ec5  # Ubuntu 22.04
      instanceType: g5.12xlarge     # 4x NVIDIA A10G, 24GB each (~22 GiB usable after firmware reserve)
      rootVolumeSize: 200
    clusterIdentity:
      name: aws-cluster-identity
      namespace: kcm-system
    clusterLabels:
      environment: training
      gpu-enabled: "true"
```

> **Why Ubuntu 22.04?** The NVIDIA GPU Operator driver containers do not support Amazon Linux 2. You must use Ubuntu 22.04 AMIs for both control plane and worker nodes.

```bash
kubectl apply -f gpu-cluster-deployment.yaml

# Monitor deployment (~7-10 minutes; can be faster on warm cache)
kubectl get clusterdeployment gpu-cluster -n kcm-system -w
```

Wait for `READY: True` before proceeding.

> **AWS SSO users:** If you are using AWS SSO (Identity Center) credentials, your session token may expire during this wait (SSO sessions typically last 1–12 hours). If provisioning stalls, or if the CAPA controller logs show `RequestExpired` / `AuthFailure` errors on `awscluster/gpu-cluster`, refresh credentials from your local machine and push them into the management cluster:
>
> ```bash
> # From your LOCAL machine (not the management node):
> aws sso login --profile <your-profile>
> eval "$(aws configure export-credentials --format env --profile <your-profile>)"
> ./lab-infrastructure/scripts/lab-refresh-creds.sh <your-name>
> ```
>
> The script updates `aws-cluster-identity-secret` in `kcm-system` and restarts the `capa-controller-manager` deployment so it reloads the fresh STS token from environment. Reconciliation resumes within ~30 seconds.

### Step 3: Get GPU Cluster Kubeconfig

```bash
kubectl get secret gpu-cluster-kubeconfig -n kcm-system -o jsonpath='{.data.value}' | base64 -d > ~/.kube/gpu-cluster.conf
export KUBECONFIG=~/.kube/gpu-cluster.conf
kubectl get nodes -o wide
```

**Expected output:**
```
NAME                         STATUS   ROLES           AGE   VERSION       INTERNAL-IP    OS-IMAGE
gpu-cluster-cp-xxxxx         Ready    control-plane   14m   v1.32.8+k0s   10.0.x.x       Ubuntu 22.04.5 LTS
gpu-cluster-md-xxxxx-yyyyy   Ready    <none>          13m   v1.32.8+k0s   10.0.x.x       Ubuntu 22.04.5 LTS
```

### Step 4: Install GPU Operator

The GPU Operator installs NVIDIA drivers, container toolkit, and device plugin. k0s uses non-standard containerd paths that MUST be configured.

```bash
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
helm repo update

helm install gpu-operator nvidia/gpu-operator \
  --namespace gpu-operator \
  --create-namespace \
  --version v25.3.0 \
  --set driver.enabled=true \
  --set toolkit.enabled=true \
  --set toolkit.env[0].name=CONTAINERD_CONFIG \
  --set toolkit.env[0].value=/etc/k0s/containerd.d/nvidia.toml \
  --set toolkit.env[1].name=CONTAINERD_SOCKET \
  --set toolkit.env[1].value=/run/k0s/containerd.sock \
  --set toolkit.env[2].name=CONTAINERD_RUNTIME_CLASS \
  --set toolkit.env[2].value=nvidia \
  --set devicePlugin.enabled=true \
  --set dcgm.enabled=true \
  --set dcgmExporter.enabled=true \
  --wait --timeout 15m
```

> **k0s-specific:** k0s stores containerd config at `/etc/k0s/containerd.d/` and socket at `/run/k0s/containerd.sock`, NOT the standard paths (`/etc/containerd/` and `/run/containerd/containerd.sock`). Without these toolkit env vars, the toolkit crashes with `containerd.sock: no such file or directory`.

> **⚠️ Pin the version — `--version v25.3.0`, do NOT bump to 25.10.x.** On k0s ≥ 1.35 (containerd 1.7.30) the **25.10 toolkit has a regression**: it ignores `CONTAINERD_CONFIG=/etc/k0s/containerd.d/nvidia.toml` and writes its runtimes to `/etc/containerd/conf.d/99-nvidia.toml` instead. k0s merge-patches that drop-in **last** into `/run/k0s/containerd-cri.toml`, and its runtimes map **replaces** k0s's — dropping `runc` while `default_runtime_name = "runc"` survives, so the CRI plugin fails to load and the worker goes `NotReady` (`container runtime is down`). A reboot / `k0sworker` restart alone does not fix it. 25.3.0 (driver 570.124) honours the k0s path and comes up cleanly with no host edit. If you are forced onto ≥ 25.10, the workaround is to re-add a `runc` runtime to `/etc/containerd/conf.d/99-nvidia.toml` and `systemctl restart k0sworker` (reach the host via `aws ssm start-session --target <worker-instance-id>` — pods can't schedule while CRI is down):
>
> ```bash
> sudo tee -a /etc/containerd/conf.d/99-nvidia.toml >/dev/null <<'EOF'
>
> [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
>   runtime_type = "io.containerd.runc.v2"
>
>   [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
>     SystemdCgroup = false
> EOF
> sudo systemctl restart k0sworker
> ```

> **`helm install --wait` returns fast — but GPUs are NOT ready yet:** Helm considers the release "deployed" once its top-level resources (Deployments, DaemonSets) are *present*, which typically happens within ~60 seconds. But GPU Operator has a cascade: `nvidia-container-toolkit`, `nvidia-device-plugin`, `nvidia-dcgm`, and `nvidia-operator-validator` all have `initContainers` that **wait for `nvidia-driver-daemonset` to become Ready first**, and the driver daemonset compiles the NVIDIA kernel module against the running kernel (~2 minutes on A10G / Ubuntu 22.04). So `helm install` exits before GPUs are actually allocatable. **The real completion signal is `nvidia.com/gpu: 4` appearing on the worker** via the `kubectl get nodes` command in the next step — poll that, not helm exit status.

Wait ~3-5 minutes for NVIDIA driver compilation on the worker node, then verify:

```bash
kubectl get pods -n gpu-operator

kubectl get nodes -o custom-columns='NAME:.metadata.name,GPUs:.status.allocatable.nvidia\.com/gpu'
```

**Expected:** `nvidia.com/gpu: 4` on the worker node.

---

## Tasks

### Task 1: Verify GPU Environment (15 min)

1. **Check GPU Operator Status**
   ```bash
   # Verify GPU Operator pods (all should be Running or Completed)
   kubectl get pods -n gpu-operator

   # Check GPU node labels
   kubectl get nodes -l nvidia.com/gpu.present=true -o wide

   # Verify GPU resources
   kubectl get nodes -o custom-columns='NAME:.metadata.name,GPUs:.status.allocatable.nvidia\.com/gpu'
   ```

2. **Expected Output**
   ```
   NAME                         GPUs
   gpu-cluster-cp-xxxxx         <none>
   gpu-cluster-md-xxxxx-yyyyy   4
   ```

3. **Run a Quick GPU Test**
   ```bash
   kubectl run gpu-test --image=nvidia/cuda:12.2.0-base-ubuntu22.04 --restart=Never \
     --overrides='{"spec":{"containers":[{"name":"gpu-test","image":"nvidia/cuda:12.2.0-base-ubuntu22.04","command":["nvidia-smi"],"resources":{"limits":{"nvidia.com/gpu":"1"}}}]}}'

   # Wait for completion, then check logs
   kubectl logs gpu-test
   kubectl delete pod gpu-test
   ```

4. **Expected nvidia-smi Output**
   ```
   NVIDIA-SMI 570.124.06    Driver Version: 570.124.06    CUDA Version: 12.8
   NVIDIA A10G              24GB memory
   ```

   > **Note:** g5.12xlarge has 4x NVIDIA A10G GPUs connected via PCIe (PHB). There is NO NVLink on A10G -- this is expected and normal for inference-class GPUs. The GPU topology shows `PHB` (PCIe Host Bridge) connections between all GPUs.

### Task 2: Deploy KAI Scheduler (45 min)

1. **Install KAI Scheduler from NVIDIA OCI Registry**

   KAI Scheduler is published as an OCI Helm chart. Install directly from the GitHub Container Registry:

   ```bash
   # Create namespace
   kubectl create namespace kai-scheduler

   # Install KAI Scheduler (pin version for reproducibility)
   # IMPORTANT: The OCI path is ghcr.io/kai-scheduler/ (NOT ghcr.io/nvidia/)
   helm upgrade --install kai-scheduler \
     oci://ghcr.io/kai-scheduler/kai-scheduler/kai-scheduler \
     --version v0.12.10 \
     --namespace kai-scheduler \
     --wait
   ```

   > **Reference:** [KAI Scheduler GitHub](https://github.com/kai-scheduler/KAI-Scheduler)

2. **Verify Installation**
   ```bash
   kubectl get pods -n kai-scheduler
   ```

3. **Expected Pod Status**
   ```
   NAME                                    READY   STATUS    RESTARTS   AGE
   kai-scheduler-default-xxx               1/1     Running   0          2m
   binder-xxx                              1/1     Running   0          2m
   pod-grouper-xxx                         1/1     Running   0          2m
   podgroup-controller-xxx                 1/1     Running   0          2m
   queue-controller-xxx                    1/1     Running   0          2m
   admission-xxx                           1/1     Running   0          2m
   kai-operator-xxx                        1/1     Running   0          2m
   ```

### Task 3: Configure Scheduler Queues (30 min)

KAI Scheduler uses the `scheduling.run.ai/v2` API group (inherited from its Run:AI origins). Queue configuration has several critical requirements discovered during validation.

> **CRITICAL:** Queues MUST have:
> 1. `parentQueue: default-parent-queue` (leaf queues need a parent)
> 2. `limit: -1` for ALL resource types (gpu, cpu, memory) -- the default limit is `0`, which blocks all scheduling
> 3. The parent queue must also have `quota: -1` and `limit: -1` for all resources

1. **Configure the Parent Queue**

   > **Note:** KAI Scheduler v0.12.10 **auto-creates** `default-parent-queue` and a child `default-queue` during `helm install`, so they already exist before this step runs. The `kubectl apply` below **reconfigures** the existing parent queue with our explicit `quota: -1` / `limit: -1` values; you'll see a harmless warning `resource queues/default-parent-queue is missing the kubectl.kubernetes.io/last-applied-configuration annotation` — that's `kubectl` noting the object wasn't originally created declaratively. The patch is still applied correctly.

   ```bash
   cat <<EOF | kubectl apply -f -
   apiVersion: scheduling.run.ai/v2
   kind: Queue
   metadata:
     name: default-parent-queue
   spec:
     resources:
       gpu:
         quota: -1
         limit: -1
       cpu:
         quota: -1
         limit: -1
       memory:
         quota: -1
         limit: -1
   EOF
   ```

2. **Create Priority Classes**
   ```yaml
   # Save as priority-classes.yaml
   apiVersion: scheduling.k8s.io/v1
   kind: PriorityClass
   metadata:
     name: high-priority-gpu
   value: 1000000
   globalDefault: false
   description: "High priority GPU workloads"
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

3. **Create Resource Queues**

   ```yaml
   # Save as gpu-queues.yaml
   apiVersion: scheduling.run.ai/v2
   kind: Queue
   metadata:
     name: training-queue
   spec:
     parentQueue: default-parent-queue
     priority: 100
     resources:
       gpu:
         quota: 4
         limit: -1
       cpu:
         quota: 48000
         limit: -1
       memory:
         quota: 200000
         limit: -1
   ---
   apiVersion: scheduling.run.ai/v2
   kind: Queue
   metadata:
     name: inference-queue
   spec:
     parentQueue: default-parent-queue
     priority: 150
     resources:
       gpu:
         quota: 2
         limit: -1
       cpu:
         quota: 24000
         limit: -1
       memory:
         quota: 100000
         limit: -1
   ---
   apiVersion: scheduling.run.ai/v2
   kind: Queue
   metadata:
     name: dev-queue
   spec:
     parentQueue: default-parent-queue
     priority: 50
     resources:
       gpu:
         quota: 1
         limit: -1
       cpu:
         quota: 8000
         limit: -1
       memory:
         quota: 32000
         limit: -1
   ```

   ```bash
   kubectl apply -f gpu-queues.yaml
   ```

   > **Queue fields explained** (from [KAI Queue docs](https://github.com/kai-scheduler/KAI-Scheduler/blob/main/docs/queues/README.md)):
   > - `quota`: Guaranteed resource allocation (jobs within quota are protected from reclaim)
   > - `limit`: Hard cap (`-1` = unlimited, `0` = no resources allowed, which is the **DEFAULT**)
   > - `overQuotaWeight`: Relative weight for borrowing unused resources from other queues

4. **Verify Queues**
   ```bash
   kubectl get queues
   ```

   **Expected output (5 queues, not 4):**
   ```
   NAME                   PRIORITY   PARENT                 CHILDREN
   default-parent-queue                                     ["default-queue","training-queue","inference-queue","dev-queue"]
   default-queue                     default-parent-queue
   dev-queue              50         default-parent-queue
   inference-queue        150        default-parent-queue
   training-queue         100        default-parent-queue
   ```

   > **`default-queue` is auto-created by KAI Scheduler** (alongside `default-parent-queue`) as a catch-all for workloads that don't specify a `kai.scheduler/queue` label. It's safe to ignore for this lab — you should see **5 queues total**, including the auto-created `default-queue`.

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
                 nvidia-smi --query-gpu=name --format=csv,noheader
                 sleep 30
                 echo "Worker completed at $(date)"
             resources:
               limits:
                 nvidia.com/gpu: 1
               requests:
                 nvidia.com/gpu: 1
                 memory: 4Gi
                 cpu: "2"
   ```

   > **How it works (with a limitation):** KAI's PodGrouper creates PodGroups for the Job's pods. **In v0.12.10, each pod gets its own PodGroup** (`minMember: 1` each) — not a single Job-wide PodGroup with `minMember: 2` — so strictly speaking, each pod is scheduled independently, not as a true gang. The test above requests 2 GPUs of 4 available, which means there is **no resource pressure** to distinguish gang scheduling from independent scheduling; the test verifies only that both pods can run concurrently. For a **definitive** gang scheduling test, scale the Job to `parallelism: 5` (1 GPU each) on the 4-GPU worker and verify that **all 5 pods stay Pending together** — a true gang-aware scheduler will refuse to partially schedule, while a non-gang scheduler would schedule 4 and leave 1 stuck.

2. **Submit Gang Job**
   ```bash
   kubectl apply -f gang-test-job.yaml

   # Watch pod scheduling
   kubectl get pods -l job-name=gang-test -o wide -w
   ```

3. **Verify Gang Behavior**
   ```bash
   # Both pods should be scheduled simultaneously
   kubectl get pods -l job-name=gang-test -o wide

   # Check scheduler events
   kubectl get events --field-selector reason=Scheduled | grep gang-test
   ```

4. **Expected Behavior**
   - Both pods scheduled within seconds of each other (gang constraint)
   - Both pods land on the GPU worker node, each with 1 GPU
   - If insufficient GPUs available, both pods remain Pending (gang constraint)

5. **Clean Up**
   ```bash
   kubectl delete job gang-test
   ```

### Task 5: Test Priority Preemption (30 min)

This task demonstrates **KAI Scheduler's priority preemption**, which combines Kubernetes `PriorityClass` (preemption *order*) with KAI's own `kai.scheduler/preemptibility` label (preemption *eligibility*). Create low-priority workloads filling GPU capacity, then deploy high-priority to trigger preemption.

1. **Create Low Priority Workload**

   > **Why the `kai.scheduler/preemptibility: "preemptible"` label is required:** KAI v0.12.10 classifies any workload with K8s priority ≥ 100 as **non-preemptible by default** (source: [`preemptible.go`](https://github.com/NVIDIA/KAI-Scheduler/blob/v0.12.10/pkg/common/podgroup/preemptible.go)). Our `low-priority-gpu` PriorityClass has value 10000, so it must be explicitly marked preemptible — without this label, KAI refuses to evict it and the high-priority pod fails to schedule with `NonPreemptibleOverQuota`.

   ```yaml
   # Save as low-priority-workload.yaml
   apiVersion: apps/v1
   kind: Deployment
   metadata:
     name: low-priority-gpu
   spec:
     replicas: 4
     selector:
       matchLabels:
         app: low-priority-gpu
     template:
       metadata:
         labels:
           app: low-priority-gpu
           kai.scheduler/queue: training-queue
           kai.scheduler/preemptibility: "preemptible"
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
   ```

2. **Deploy Low Priority Workload**
   ```bash
   kubectl apply -f low-priority-workload.yaml

   # Wait for pods to fill all 4 GPUs
   kubectl get pods -l app=low-priority-gpu -w
   ```

3. **Create High Priority Workload**
   ```yaml
   # Save as high-priority-workload.yaml
   apiVersion: apps/v1
   kind: Deployment
   metadata:
     name: high-priority-gpu
   spec:
     replicas: 1
     selector:
       matchLabels:
         app: high-priority-gpu
     template:
       metadata:
         labels:
           app: high-priority-gpu
           kai.scheduler/queue: training-queue
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
   kubectl delete deployment low-priority-gpu high-priority-gpu
   ```

### Task 6: Configure Fractional GPU Sharing (20 min)

Time-slicing multiplies allocatable GPU resources by sharing physical GPUs across multiple pods.

1. **Create Time-Slicing ConfigMap**
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
   ```

2. **Patch ClusterPolicy**

   > **IMPORTANT:** Must include BOTH `name` AND `default` fields. The `default: "any"` tells the device plugin which key in the ConfigMap to use. Without it, time-slicing silently does nothing.

   > **Name the API group explicitly:** Use `clusterpolicies.nvidia.com/cluster-policy` (with the `.nvidia.com` suffix), not the bare `clusterpolicy/cluster-policy`. Kyverno — deployed as a default k0rdent Service on the `aws-standalone-cp` template — registers its own `clusterpolicies.kyverno.io` CRD, and `kubectl` picks Kyverno's by default (it sorts first in API discovery), failing with `NotFound: clusterpolicies.kyverno.io "cluster-policy"`. The explicit `.nvidia.com` suffix targets the NVIDIA GPU Operator CRD unambiguously.

   ```bash
   kubectl patch clusterpolicies.nvidia.com/cluster-policy \
     --type merge \
     --patch '{"spec": {"devicePlugin": {"config": {"name": "time-slicing-config", "default": "any"}}}}'
   ```

   > **Reference:** [GPU Operator Time-Slicing docs](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/gpu-sharing.html)

3. **Verify Fractional GPUs**

   Wait ~10-30 seconds for the device plugin to restart and re-register:

   ```bash
   kubectl get nodes -o custom-columns='NAME:.metadata.name,GPUs:.status.allocatable.nvidia\.com/gpu'
   ```

   **Expected:** 16 GPUs (4 physical x 4 replicas)

### Task 7: Configure Enterprise NCCL Settings (30 min)

Proper NCCL configuration is critical for multi-GPU workloads. This task creates a standardized configuration and validates GPU communication performance.

1. **Verify GPU Topology**

   Before configuring NCCL, understand your node's topology:

   ```bash
   kubectl run topo-test --image=nvidia/cuda:12.2.0-base-ubuntu22.04 --restart=Never \
     --overrides='{"spec":{"containers":[{"name":"topo","image":"nvidia/cuda:12.2.0-base-ubuntu22.04","command":["nvidia-smi","topo","-m"],"resources":{"limits":{"nvidia.com/gpu":"4"},"requests":{"nvidia.com/gpu":"4"}}}]}}'

   # Wait for completion
   kubectl logs topo-test
   kubectl delete pod topo-test
   ```

   **Expected output for g5.12xlarge (A10G):**
   ```
           GPU0    GPU1    GPU2    GPU3    CPU Affinity    NUMA Affinity
   GPU0     X      PHB     PHB     PHB     0-47            0
   GPU1    PHB      X      PHB     PHB     0-47            0
   GPU2    PHB     PHB      X      PHB     0-47            0
   GPU3    PHB     PHB     PHB      X      0-47            0
   ```

   **Legend:**
   - `PHB` = PCIe Host Bridge (~12 GB/s) -- this is what A10G uses
   - `NV#` = Number of NVLink connections (only on V100/A100/H100)
   - `SYS` = System/QPI connection

2. **Create NCCL Configuration ConfigMap**

   ```yaml
   # Save as nccl-enterprise-config.yaml
   apiVersion: v1
   kind: ConfigMap
   metadata:
     name: nccl-enterprise-config
   data:
     # ===== Core NCCL Settings =====
     # Debug level (WARN for production, INFO for troubleshooting)
     NCCL_DEBUG: "WARN"

     # ===== P2P (Peer-to-Peer) Configuration =====
     # Force NVLink usage for P2P communication
     NCCL_P2P_LEVEL: "NVL"

     # ===== RDMA/GPUDirect Configuration =====
     # Enable GPUDirect RDMA (valid: LOC, PIX, PXB, PHB, SYS)
     NCCL_NET_GDR_LEVEL: "SYS"

     # For InfiniBand
     NCCL_IB_DISABLE: "0"
     # Prefix match: "mlx5" matches all mlx5_* devices
     NCCL_IB_HCA: "mlx5"

     # ===== Performance Tuning =====
     # Buffer size for NCCL operations (default 4MB, increase for large models)
     NCCL_BUFFSIZE: "8388608"

     # Number of CUDA threads for NCCL kernels
     NCCL_NTHREADS: "512"

     # Socket threads for TCP fallback
     NCCL_SOCKET_NTHREADS: "4"
     NCCL_NSOCKS_PERTHREAD: "4"

     # ===== Algorithm Selection =====
     # Tree algorithm threshold (0 = always use tree, good for many nodes)
     NCCL_TREE_THRESHOLD: "0"

     # Minimum rings for ring algorithm
     NCCL_MIN_NRINGS: "4"

     # ===== CUDA Optimization =====
     # Max CUDA streams: 1 for Megatron Tensor/Sequence Parallelism
     # Do NOT set to 1 for FSDP workloads
     CUDA_DEVICE_MAX_CONNECTIONS: "1"
   ```

   ```bash
   kubectl apply -f nccl-enterprise-config.yaml
   ```

3. **Run NCCL All-Reduce Test**

   Use the PyTorch NGC container to build and run NCCL tests:

   ```yaml
   # Save as nccl-test.yaml
   apiVersion: v1
   kind: Pod
   metadata:
     name: nccl-config-test
   spec:
     restartPolicy: Never
     containers:
       - name: nccl-test
         image: nvcr.io/nvidia/pytorch:24.12-py3
         command: ["bash", "-c"]
         args:
           - |
             echo "=== NCCL Environment ==="
             env | grep -E "^NCCL|^CUDA" | sort

             echo "=== GPU Topology ==="
             nvidia-smi topo -m

             echo "=== Building NCCL Tests ==="
             apt-get update -qq && apt-get install -y -qq build-essential
             cd /tmp && git clone https://github.com/NVIDIA/nccl-tests.git
             cd nccl-tests && make MPI=0 CUDA_HOME=/usr/local/cuda NCCL_HOME=/usr/lib/x86_64-linux-gnu

             echo "=== Running All-Reduce ==="
             GPU_COUNT=$(nvidia-smi -L | wc -l)
             ./build/all_reduce_perf -b 1M -e 1G -f 2 -g $GPU_COUNT
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
   ```

   ```bash
   kubectl apply -f nccl-test.yaml

   # NCCL test takes ~8-10 minutes on first run (image pull ~4-5 min + build + benchmark).
   # Subsequent runs on the same worker skip the image pull and take ~3-4 minutes.
   kubectl logs -f nccl-config-test
   ```

   > **Why the first run is slow:** `nvcr.io/nvidia/pytorch:24.12-py3` is approximately 20 GB. Even over EC2's internal network, the initial pull takes 4-5 minutes and dominates wall-clock time. The pod will sit in `ContainerCreating` during this period; run `kubectl describe pod nccl-config-test` to confirm the current event is `Pulling image`. Once the image is cached on the worker's containerd store, any subsequent pod using the same image starts nearly instantly. **If the pod stays `Pending`/`ContainerCreating` for more than 10 minutes**, look for `ImagePullBackOff` or network issues in `kubectl describe`.

4. **Interpret NCCL Test Results**

   **Expected results for A10G (PCIe):**
   ```
   # Avg bus bandwidth    : 3.22401 GB/s
   ```

   This is PCIe bandwidth. For NVLink GPUs, expect significantly higher:

   | GPU Type | Interconnect | Expected Bus BW |
   |----------|-------------|-----------------|
   | A10G (g5) | PCIe | ~3 GB/s |
   | V100 (p3) | NVLink 2.0 | ~100 GB/s |
   | A100 (p4d) | NVSwitch | ~500 GB/s |
   | H100 (p5) | NVSwitch | ~800 GB/s |

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
   # The metrics service is kai-scheduler-default on port 8080
   kubectl port-forward -n kai-scheduler svc/kai-scheduler-default 8080:8080 &

   # Fetch metrics
   curl http://localhost:8080/metrics | grep kai_
   ```

2. **Key Metrics to Monitor**

   **Scheduling latency (how fast decisions happen):**
   ```
   # Per-action scheduling latency (allocate, preempt, reclaim, consolidation, stalegangeviction)
   kai_action_scheduling_latency_milliseconds

   # End-to-end scheduling latency (full scheduler loop time)
   kai_e2e_scheduling_latency_milliseconds

   # Per-plugin scheduling latency (predicates, priority, proportion, topology, gpupack, ...)
   kai_plugin_scheduling_latency_milliseconds

   # Per-task scheduling + bind latency histograms (_bucket, _count, _sum variants)
   kai_task_scheduling_latency_milliseconds
   kai_task_bind_latency_milliseconds
   ```

   **Queue resource accounting (who has what):**
   ```
   # Current resource usage per queue (training-queue, inference-queue, dev-queue, default-queue)
   kai_queue_gpu_usage
   kai_queue_cpu_usage
   kai_queue_memory_usage

   # Fair-share entitlement per queue (what each queue is entitled to under contention)
   kai_queue_fair_share_gpu
   kai_queue_fair_share_cpu_cores
   kai_queue_fair_share_memory_gb
   ```

   **Preemption and PodGroup activity (operational signals):**
   ```
   # Total preemption attempts across the scheduler's lifetime
   kai_total_preemption_attempts

   # PodGroups acted on or scheduled, labeled by action
   kai_podgroups_acted_on_by_action
   kai_podgroups_scheduled_by_action

   # Scheduling scenarios filtered or simulated during the decision loop
   kai_scenarios_filtered_by_action
   kai_scenarios_simulation_by_action
   ```

   > **Why `kai_total_preemption_attempts` is the cleanest Task 5 verification signal:** After running Task 5 (priority preemption) with the preemptibility label in place, this counter should be `>= 1`. It's a stronger verification than relying on timing or event observation — if the high-priority pod scheduled onto a free GPU without actually preempting anyone, the counter stays at `0`. Use `curl http://localhost:8080/metrics | grep '^kai_total_preemption_attempts'` after Task 5 to confirm.

3. **Stop Port Forward**
   ```bash
   kill %1
   ```

---

## Deliverables

### Basic Deliverables
- [ ] **Screenshot** of KAI scheduler pods running
- [ ] **Queue configuration** YAML files (parent queue + 3 leaf queues)
- [ ] **Gang scheduling test results** showing both pods scheduled together
- [ ] **Preemption demo** showing high priority preempting low priority
- [ ] **Scheduler metrics output** from `/metrics` endpoint

### NCCL Configuration Deliverables
- [ ] **GPU topology output** (`nvidia-smi topo -m`)
- [ ] **NCCL enterprise ConfigMap** deployed
- [ ] **NCCL test results** showing all-reduce bandwidth
- [ ] **Bus bandwidth measurement** (~3 GB/s for A10G PCIe)
- [ ] **Documentation** of NCCL settings for your environment

## Verification Checklist

### Scheduler
- [ ] KAI scheduler deployed and running (7 pods)
- [ ] Parent queue created with `limit: -1`
- [ ] Priority classes created (high, normal, low)
- [ ] Resource queues configured with `parentQueue` and `limit: -1`
- [ ] Gang scheduling working correctly (both pods start simultaneously)
- [ ] Priority preemption functioning
- [ ] Scheduler metrics accessible

### NCCL/GPU Communication
- [ ] GPU topology verified (`PHB` connections for A10G)
- [ ] NCCL ConfigMap applied correctly
- [ ] NCCL all-reduce test completed
- [ ] Bus bandwidth ~3 GB/s for A10G (PCIe)
- [ ] Time-slicing enabled (4 physical GPUs -> 16 allocatable)

---

## Cleanup

```bash
# Delete test pods and workloads
kubectl delete job gang-test 2>/dev/null
kubectl delete pod nccl-config-test gpu-test topo-test 2>/dev/null
kubectl delete deploy low-priority-gpu high-priority-gpu 2>/dev/null

# To revert time-slicing (restore 4 physical GPUs):
kubectl patch clusterpolicies.nvidia.com/cluster-policy \
  --type merge \
  --patch '{"spec": {"devicePlugin": {"config": {"name": "", "default": ""}}}}'

# To destroy the entire GPU cluster:
# From management cluster:
export KUBECONFIG=~/.kube/config  # Switch back to mgmt cluster
kubectl delete clusterdeployment gpu-cluster -n kcm-system
# Wait for CAPI to clean up EC2 instances (~5 min)
```

> **If deletion stalls:** If `kubectl get clusterdeployment gpu-cluster` stays in a `Deleting` state for more than 5 minutes, your STS session token likely expired during the lab — the CAPA controller cannot call AWS APIs to terminate instances with expired credentials. Refresh them with `./lab-infrastructure/scripts/lab-refresh-creds.sh <your-name>` and deletion will resume within ~30 seconds. **Do NOT force-remove finalizers** (`kubectl patch ... metadata.finalizers=null`) — that would orphan the underlying AWS resources (EC2 instances, VPCs, NAT gateways, load balancers) and continue billing indefinitely with no controller left to clean them up.

---

## Troubleshooting

### GPU Operator Pods Crashing

**Toolkit pods crash with `containerd.sock: no such file or directory`:**
```bash
# This means k0s containerd paths are not configured
# Reinstall GPU Operator with toolkit env vars (see Pre-Lab Step 3)
helm upgrade gpu-operator nvidia/gpu-operator \
  --namespace gpu-operator \
  --set toolkit.env[0].name=CONTAINERD_CONFIG \
  --set toolkit.env[0].value=/etc/k0s/containerd.d/nvidia.toml \
  --set toolkit.env[1].name=CONTAINERD_SOCKET \
  --set toolkit.env[1].value=/run/k0s/containerd.sock \
  --set toolkit.env[2].name=CONTAINERD_RUNTIME_CLASS \
  --set toolkit.env[2].value=nvidia
```

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

### Pods Stuck Pending with KAI Scheduler

**Verify schedulerName field:**
```bash
kubectl get pod <pod-name> -o jsonpath='{.spec.schedulerName}'
# Must be: kai-scheduler
```

**Check queue limits are not 0:**
```bash
kubectl get queues -o yaml | grep -A3 limit
# All limits should be -1 (unlimited), NOT 0
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

### Time-Slicing Not Taking Effect

**Verify ClusterPolicy patch includes both fields:**
```bash
kubectl get clusterpolicies.nvidia.com cluster-policy -o jsonpath='{.spec.devicePlugin.config}'
# Must show: {"default":"any","name":"time-slicing-config"}
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

**Verify KAI preemptibility on the victim workload** (see Task 5 note):

If you see `NonPreemptibleOverQuota` events on the high-priority pod, KAI has classified the low-priority workload as non-preemptible. KAI's preemptibility model is orthogonal to Kubernetes `PriorityClass` — workloads with priority >= 100 default to non-preemptible unless explicitly labeled otherwise. Inspect the PodGroup:
```bash
kubectl get podgroups -o jsonpath='{range .items[*]}{.metadata.name}  preemptibility={.spec.preemptibility}{"\n"}{end}'
# Preemptible: spec.preemptibility = "preemptible"
# Non-preemptible (default for priority >= 100): spec.preemptibility = "non-preemptible" or empty
```

If the low-priority workload's PodGroup is non-preemptible, add `kai.scheduler/preemptibility: "preemptible"` to its pod template labels and re-apply:
```yaml
template:
  metadata:
    labels:
      kai.scheduler/preemptibility: "preemptible"
```

### Normal Transients (Not Failures)

These messages and states appear during healthy lab execution and do NOT indicate problems. They're listed here so you recognize them when they happen instead of treating them as failures.

**`NetworkPluginNotReady` on the CP Machine during Pre-Lab Step 2:**

```
Node.Ready: container runtime network not ready: NetworkReady=false
reason:NetworkPluginNotReady message:Network plugin returns error
```

Appears for ~30-60 seconds while the CNI (Calico, in the `aws-standalone-cp-1-0-26` template) initializes on a freshly booted control plane VM. Clears automatically once `calico-node` pods become Ready.

**`ServiceSetEnsureProfileFailed` warning event right after `kubectl apply -f gpu-cluster-deployment.yaml`:**

```
Failed to ensure Profile for ServiceSet gpu-cluster: ...
Operation cannot be fulfilled on profiles.config.projectsveltos.io "gpu-cluster":
the object has been modified; please apply your changes to the latest version and try again
```

Optimistic-concurrency race between reconciling controllers — two paths had stale versions of the same Profile object and one lost. The next reconcile (within milliseconds) emits `ServiceSetEnsureProfileSuccess` and the warning self-heals. Ignore a single occurrence; investigate only if it repeats more than 5 times.

**`nvidia-dcgm-exporter` restarts 1-3 times during Pre-Lab Step 4 GPU Operator install:**

The DCGM exporter sometimes starts before `nvidia-dcgm` is fully ready, hits a connection-refused error, crashes, gets restarted by kubelet, and eventually succeeds once DCGM is up. A `RESTARTS` count of 1-3 on this pod in `kubectl get pods -n gpu-operator` is normal. If restarts climb past 5, investigate with `kubectl logs -n gpu-operator <dcgm-exporter-pod> --previous`.

**`nvidia.com/gpu.replicas` label lag after time-slicing patch (Task 6):**

After applying the time-slicing ConfigMap, `kubectl get nodes -o custom-columns='NAME:.metadata.name,GPUs:.status.allocatable.nvidia\.com/gpu'` shows the new count (16) within ~10-30 seconds, but the node label `nvidia.com/gpu.replicas` may still show `1` for up to 60 seconds. GPU Feature Discovery refreshes labels on its own cadence. **Trust the allocatable count for the real state**, not the node labels.

**Kubernetes client/server version skew warning when running `kubectl` on the management node:**

```
Warning: version difference between client (1.35) and server (1.32)
exceeds the supported minor version skew of +/-1
```

The management cluster ships a newer `kubectl` than the managed `gpu-cluster`'s k0s version. This is a warning only — all Lab 5.1 commands (get, apply, patch, logs, exec, describe, port-forward) work correctly despite the skew. Kubernetes guarantees only `+/-1` minor version compatibility, but in practice most operations are stable across wider skews.

---

## Key Takeaways

### GPU Scheduling
1. **Default Kubernetes scheduler lacks GPU-aware features** needed for AI/ML workloads
2. **Gang scheduling prevents partial job starts** that waste resources in distributed training
3. **Priority classes and queues enable fair resource sharing** across teams
4. **KAI Queue resources MUST have explicit `limit: -1`** -- the default limit of 0 blocks all scheduling
5. **Fractional GPU sharing via time-slicing** multiplies allocatable GPUs (4 physical -> 16 virtual)

### NCCL and GPU Communication
6. **A10G (g5 instances) use PCIe only** -- ~3 GB/s bus bandwidth
7. **For NVLink bandwidth (100-800 GB/s)**, use V100/A100/H100 instances (p3/p4d/p5)
8. **NCCL environment variables control communication paths** -- test before production
9. **Always verify GPU topology** with `nvidia-smi topo -m` before deploying multi-GPU workloads

### k0rdent Integration
10. **GPU clusters are deployed via the same ClusterDeployment pattern** as Week 1
11. **Ubuntu 22.04 AMI is REQUIRED** -- GPU Operator driver containers don't support Amazon Linux 2
12. **k0s containerd paths** (`/etc/k0s/containerd.d/`, `/run/k0s/containerd.sock`) must be configured in GPU Operator toolkit env vars

---

## References

### NVIDIA
- [KAI Scheduler GitHub](https://github.com/kai-scheduler/KAI-Scheduler)
- [KAI Scheduler Queue Configuration](https://github.com/kai-scheduler/KAI-Scheduler/blob/main/docs/queues/README.md)
- [NVIDIA GPU Operator Documentation](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/)
- [GPU Operator Time-Slicing](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/gpu-sharing.html)
- [NCCL Environment Variables](https://docs.nvidia.com/deeplearning/nccl/user-guide/docs/env.html)
- [NCCL Tests GitHub](https://github.com/NVIDIA/nccl-tests)

### k0rdent
- [k0rdent Documentation](https://docs.k0rdent.io/)

### Kubernetes
- [Priority and Preemption](https://kubernetes.io/docs/concepts/scheduling-eviction/pod-priority-preemption/)

---

## Next Lab

Proceed to [Lab 5.2 - Service Catalog Blueprints](lab-5.2-service-catalog.md)
