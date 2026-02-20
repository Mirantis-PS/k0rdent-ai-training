# Week 5 Lab Environment Setup

**Estimated setup time:** 30-45 minutes (provisioning) + 15-20 minutes (GPU verification)

This guide walks you through provisioning and configuring the GPU lab environment used by all Week 5 labs. It builds on the k0rdent Enterprise foundations established in Week 1.

---

## Architecture Overview

Week 5 labs run on a dedicated GPU cluster managed by your k0rdent management cluster:

```
YOUR MACHINE
     |
     | SSH (lab-connect.sh)
     v
+--------------+
|   Bastion    |  (per-student, from Week 1)
|   Host       |
+------+-------+
       |
       +---------------------------+
       |                           |
       v                           v
+------------------+     +--------------------+
| Management       |     | GPU Lab Instance   |
| Cluster (k0s)   |     | (p3.8xlarge or     |
|                  |     |  p4d.24xlarge)     |
| KCM | KSM | KOF |     |                    |
| CAPI providers   |     | k0s + GPU Operator |
| ServiceTemplates |     | 4x V100 or 8x A100|
+--------+---------+     | NVIDIA drivers     |
         |               | CUDA 12.6          |
         |               | Engineer namespaces |
         | ClusterDeployment        |
         | + ServiceTemplates       |
         +------------>-------------+
```

### Two GPU Lab Options

| Configuration | Instance | GPUs | GPU Memory | NVLink | Cost/hr (spot) | Best For |
|--------------|----------|------|------------|--------|---------------|----------|
| **Standard** | p3.8xlarge | 4x V100 | 16GB each | NVLink 2.0 (300 GB/s) | ~$4.50 | Labs 5.1-5.6, inference, scheduling |
| **Advanced** | p4d.24xlarge | 8x A100 | 40GB each | NVLink 3.0 (600 GB/s) | ~$15.00 | Labs 5.13-5.15, distributed training, NCCL |

> **Cost reminder:** GPU instances are significantly more expensive than Week 1 infrastructure. Always destroy your GPU environment when not actively working. See [Cost Management](#cost-management) below.

---

## Prerequisites

Before starting Week 5 labs, you must have completed:

- [x] **Lab 1.1** - k0rdent management cluster provisioned and running
- [x] **Lab 1.3** - AWS infrastructure provider configured
- [x] **Lab 1.5** - Experience provisioning a managed cluster via `ClusterDeployment`
- [x] **Lab 1.7** - Understanding of `ServiceTemplate` and `MultiClusterService`

You will need:
- AWS credentials with EC2 GPU instance permissions (p3/p4d families)
- Your student lab environment provisioned (from Week 1)
- Your management cluster accessible via `lab-connect.sh`

---

## Step 1: Provision the GPU Lab Environment

### Option A: Standard GPU Instance (Recommended for most labs)

From your local machine, add GPU support to your student lab:

```bash
cd lab-infrastructure

# Add GPU lab to your environment (uses p3.8xlarge with 4x V100 by default)
./scripts/lab-provision.sh <your-engineer-id> --gpu

# Example:
./scripts/lab-provision.sh john-doe --gpu
```

### Option B: Advanced GPU Instance (For distributed training labs)

For Labs 5.13-5.15 (RDMA, distributed training), override the instance type in Terraform variables to use p4d.24xlarge with 8x A100. Provision with:

```bash
# Add GPU lab with advanced configuration
./scripts/lab-provision.sh <your-engineer-id> --gpu
```

### What Happens During Provisioning

The provisioning script automates:

1. **EC2 Instance Launch** - GPU instance in the dedicated GPU subnet
2. **NVIDIA Driver Installation** - v570 drivers via NVIDIA Deep Learning AMI
3. **k0s Cluster Bootstrap** - Single-node k0s v1.32.4+k0s.0 with GPU support
4. **GPU Operator Deployment** - v25.10.0 with k0s-specific containerd paths
5. **Multi-User Setup** - Isolated engineer namespaces with GPU quotas
6. **Model Storage** - 500GB+ EBS volume mounted for model weights

> **Wait time:** Cloud-init takes 10-15 minutes to complete all setup phases. You can monitor progress with `tail -f /var/log/k0rdent-init.log` once connected.

---

## Step 2: Connect to the GPU Lab

```bash
# Connect to the GPU lab instance (via bastion)
./scripts/lab-connect.sh <your-engineer-id>
```

Once connected, verify the environment is fully initialized:

```bash
# Check cloud-init completion
[ -f /opt/k0rdent-lab/.init-complete ] && echo "Setup complete" || echo "Still initializing..."

# If still initializing, watch progress:
tail -f /var/log/k0rdent-init.log
```

---

## Step 3: Verify GPU Environment

Run through these checks to confirm your lab environment is ready:

### 3.1 Verify NVIDIA Drivers and GPUs

```bash
# Check NVIDIA driver and GPU visibility
nvidia-smi
```

**Expected output (p3.8xlarge):**
```
+-----------------------------------------------------------------------------+
| NVIDIA-SMI 570.xx       Driver Version: 570.xx       CUDA Version: 12.6    |
|-------------------------------+----------------------+----------------------+
| GPU  Name        Persistence-M| Bus-Id        Disp.A | Volatile Uncorr. ECC |
|   0  Tesla V100-SXM2    On   | 00000000:00:1B.0 Off |                    0 |
|   1  Tesla V100-SXM2    On   | 00000000:00:1C.0 Off |                    0 |
|   2  Tesla V100-SXM2    On   | 00000000:00:1D.0 Off |                    0 |
|   3  Tesla V100-SXM2    On   | 00000000:00:1E.0 Off |                    0 |
+-------------------------------+----------------------+----------------------+
```

### 3.2 Check GPU Topology

```bash
# Verify NVLink connectivity between GPUs
nvidia-smi topo -m
```

Look for `NV#` entries (NVLink connections) vs `SYS`/`PHB` (PCIe, slower):
- **V100 (p3.8xlarge):** Expect `NV2` between some GPU pairs (NVLink 2.0)
- **A100 (p4d.24xlarge):** Expect `NV12` between all GPU pairs (full NVSwitch mesh)

### 3.3 Verify Kubernetes and GPU Operator

```bash
# Check k0s cluster is healthy
kubectl get nodes -o wide

# Verify GPU Operator pods are running
kubectl get pods -n gpu-operator

# Confirm GPUs are allocatable
kubectl get nodes -o custom-columns=\
'NAME:.metadata.name,GPUs:.status.allocatable.nvidia\.com/gpu'
```

**Expected:**
```
NAME           GPUs
gpu-lab-node   4     # (or 8 for p4d.24xlarge)
```

### 3.4 Verify Your Engineer Namespace

```bash
# Check your namespace and GPU quota
kubectl get namespace | grep engineer

# View your resource quota
kubectl describe resourcequota -n engineer-<your-id>
```

**Expected quota (per engineer on shared instance):**
```
Resource         Used  Hard
--------         ----  ----
nvidia.com/gpu   0     1
cpu              0     8
memory           0     32Gi
pods             0     10
```

### 3.5 Run a Quick GPU Test

```bash
# Run a simple CUDA test pod
kubectl run gpu-test \
  --image=nvidia/cuda:12.2.0-base-ubuntu22.04 \
  --restart=Never \
  --limits='nvidia.com/gpu=1' \
  --command -- nvidia-smi

# Check output
kubectl logs gpu-test

# Clean up
kubectl delete pod gpu-test
```

---

## Step 4: Deploy GPU Operator via k0rdent (Management Cluster)

> **Note:** If the GPU lab was provisioned via `lab-provision.sh`, the GPU Operator is already installed locally on the GPU instance. This step shows the **k0rdent-native approach** for production environments, where the GPU Operator is deployed as a ServiceTemplate from the management cluster.

On your **management cluster** (connect via `./scripts/lab-connect.sh <your-engineer-id>`):

### 4.1 Install GPU Operator ServiceTemplate

```bash
# Install the GPU Operator ServiceTemplate from the k0rdent catalog
helm install gpu-operator-service-template \
  oci://ghcr.io/k0rdent/catalog/charts/gpu-operator-service-template \
  --version 25.10.0 \
  -n kcm-system

# Verify
kubectl get servicetemplate -n kcm-system | grep gpu-operator
```

### 4.2 Deploy to GPU Clusters via MultiClusterService

This follows the same pattern you learned in [Lab 1.7](../../week-1-foundations/labs/lab-1.7-multicluster-services.md):

```yaml
# Save as gpu-operator-mcs.yaml
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

```bash
kubectl apply -f gpu-operator-mcs.yaml
```

> **Why k0s-specific paths?** k0rdent uses k0s as its Kubernetes distribution. k0s stores the containerd configuration at `/etc/k0s/containerd.d/` and socket at `/run/k0s/containerd.sock`, unlike standard installations that use `/etc/containerd/` and `/run/containerd/containerd.sock`. The GPU Operator toolkit must be told where to write the NVIDIA runtime config. See [NVIDIA k0rdent Partner Validation](https://docs.nvidia.com/datacenter/cloud-native/partner-validated/latest/k0rdent.html) for details.

---

## Resuming Your Lab Environment

If your SSH session drops or you're returning another day:

```bash
# From your local machine
cd lab-infrastructure

# Reconnect to your lab
./scripts/lab-connect.sh <your-engineer-id>

# Verify GPU environment is still healthy
nvidia-smi
kubectl get nodes
kubectl get pods -n gpu-operator
```

> **Instance lifecycle:** GPU lab instances may be terminated if using spot pricing. If your instance was terminated, re-provision with `./scripts/lab-provision.sh <your-engineer-id> --gpu`. Cloud-init will restore the full environment in 10-15 minutes.

---

## Cost Management

GPU instances are the most expensive resources in this training:

| Instance | On-Demand | Spot (~60% savings) | Daily (8 hrs) |
|----------|-----------|---------------------|---------------|
| p3.8xlarge (4x V100) | $12.24/hr | ~$4.50/hr | ~$36-98 |
| p4d.24xlarge (8x A100) | $32.77/hr | ~$15.00/hr | ~$120-262 |

### Rules

1. **Destroy when not in use.** Do not leave GPU instances running overnight.
   ```bash
   ./scripts/lab-destroy.sh <your-engineer-id> --auto-approve
   ```

2. **Use spot instances** (enabled by default). Accept occasional interruptions for 60% savings.

3. **Use the standard GPU lab** (p3.8xlarge) for Labs 5.1-5.12. Only provision the advanced lab (p4d.24xlarge) for Labs 5.13-5.15.

### Check Running Costs

```bash
# From your local machine
./scripts/lab-status.sh <your-engineer-id>
```

---

## Lab Navigation

### Foundation Track (Required)

Complete these labs in order:

| Lab | Title | Duration | Key Topics |
|-----|-------|----------|------------|
| [5.1](lab-5.1-gpu-scheduler.md) | GPU Scheduler Deployment | 3.5h | KAI Scheduler, gang scheduling, priority queues, NCCL |
| [5.2](lab-5.2-vllm-inference.md) | vLLM Inference Service | 2.5h | LLM serving, PagedAttention, GPU utilization |
| [5.3](lab-5.3-vector-database.md) | Vector Database Deployment | 2h | Milvus, embeddings, similarity search |
| [5.4](lab-5.4-jupyter-notebooks.md) | Jupyter Notebook Stack | 1.5h | JupyterHub, GPU server profiles |
| [5.5](lab-5.5-service-catalog.md) | Service Catalog Blueprints | 2h | k0rdent ServiceTemplates, catalog deployment |
| [5.6](lab-5.6-troubleshooting-gpu.md) | Troubleshooting GPU Scheduling | 2h | Diagnostics, GPU memory, OOM errors |

### Elective Tracks (Choose Your Path)

After completing the foundation track, choose one or more paths:

**Compliance & Templates**

| Lab | Title | Duration |
|-----|-------|----------|
| [5.7](lab-5.7-nvidia-fips.md) | NVIDIA FIPS Configuration | 2h |
| [5.8](lab-5.8-cluster-templates.md) | Cluster Templates for AI | 2h |

**ML Platforms**

| Lab | Title | Duration |
|-----|-------|----------|
| [5.9](lab-5.9-kubeflow-ml-platform.md) | Kubeflow ML Platform | 3h |
| [5.10](lab-5.10-mlflow-experiment-tracking.md) | MLflow Experiment Tracking | 2.5h |
| [5.11](lab-5.11-runai-gpu-orchestration.md) | Run:AI GPU Orchestration | 3h |
| [5.12](lab-5.12-slurm-operator-hpc.md) | Slurm Operator for HPC | 3h |

**Advanced (Requires p4d.24xlarge)**

| Lab | Title | Duration |
|-----|-------|----------|
| [5.13](lab-5.13-tensorrt-llm.md) | TensorRT-LLM Optimization | 3h |
| [5.14](lab-5.14-rdma-multi-cloud.md) | RDMA Multi-Cloud | 3h |
| [5.15](lab-5.15-distributed-training.md) | Distributed Training | 3h |

```
FOUNDATION (Required)                          CHOOSE YOUR PATH
━━━━━━━━━━━━━━━━━━━━                          ━━━━━━━━━━━━━━━━
5.1 ➔ 5.2 ➔ 5.3 ➔ 5.4 ➔ 5.5 ➔ 5.6    ──►  ML Platforms (5.9-5.12)
                                               Compliance (5.7-5.8)
                                               Advanced (5.13-5.15) ⚠ p4d required
```

---

## Troubleshooting

### GPU Instance Won't Provision

```bash
# Check if GPU capacity is available in your region
aws ec2 describe-instance-type-offerings \
  --location-type availability-zone \
  --filters "Name=instance-type,Values=p3.8xlarge" \
  --region $AWS_REGION

# If no capacity, try a different AZ or region
./scripts/lab-provision.sh <your-engineer-id> --gpu
```

### nvidia-smi Shows No GPUs

```bash
# Check if NVIDIA drivers are loaded
lsmod | grep nvidia

# If not, drivers may still be installing (check cloud-init)
tail -f /var/log/k0rdent-init.log

# Verify the instance actually has GPUs
lspci | grep -i nvidia
```

### GPU Operator Pods Crashing

```bash
# Check GPU Operator pod status
kubectl get pods -n gpu-operator

# Common issue on k0s: wrong containerd paths
kubectl logs -n gpu-operator -l app=nvidia-container-toolkit-daemonset

# Fix: Ensure toolkit uses k0s paths
# /etc/k0s/containerd.d/nvidia.toml (NOT /etc/containerd/config.toml)
# /run/k0s/containerd.sock (NOT /run/containerd/containerd.sock)
```

### Cannot Allocate GPUs to Pods

```bash
# Verify GPU resources are visible
kubectl describe node | grep -A5 "Allocatable:" | grep nvidia

# If nvidia.com/gpu shows 0, restart device plugin
kubectl delete pod -n gpu-operator -l app=nvidia-device-plugin-daemonset

# Check if another pod is consuming all GPUs
kubectl get pods --all-namespaces -o json | \
  jq '.items[] | select(.spec.containers[].resources.limits["nvidia.com/gpu"] != null) | {namespace: .metadata.namespace, name: .metadata.name, gpus: .spec.containers[].resources.limits["nvidia.com/gpu"]}'
```

### Session Recovery After Spot Interruption

```bash
# Check if instance was terminated
./scripts/lab-status.sh <your-engineer-id>

# If terminated, re-provision (cloud-init restores everything)
./scripts/lab-provision.sh <your-engineer-id> --gpu

# Wait for initialization, then reconnect
./scripts/lab-connect.sh <your-engineer-id>
```

---

## Cleanup

### After Each Lab Session

Destroy the GPU instance to avoid unnecessary costs:

```bash
# From your local machine
./scripts/lab-destroy.sh <your-engineer-id> --auto-approve
```

### After Completing All Week 5 Labs

```bash
# Destroy your entire lab environment
./scripts/lab-destroy.sh <your-engineer-id> --auto-approve

# To also remove the S3 state bucket:
# ./scripts/lab-destroy.sh <your-engineer-id> --auto-approve --delete-bucket
```

---

## References

- [Lab Infrastructure README](../../../lab-infrastructure/README.md)
- [Week 1 Foundations](../../week-1-foundations/README.md)
- [Lab 1.7 - MultiClusterService](../../week-1-foundations/labs/lab-1.7-multicluster-services.md) (ServiceTemplate pattern)
- [k0rdent Service Catalog](https://catalog.k0rdent.io/)
- [NVIDIA GPU Operator - k0rdent Partner Validation](https://docs.nvidia.com/datacenter/cloud-native/partner-validated/latest/k0rdent.html)
- [NVIDIA GPU Operator Documentation](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/)
