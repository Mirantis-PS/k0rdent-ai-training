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
+------+-------+
       |
       v
+------------------+
| Management       |
| Cluster (k0s)   |
| KCM | KSM | KOF |
| CAPI providers   |
+--------+---------+
         |
         | ClusterDeployment
         | (aws-standalone-cp-1-0-20)
         v
+--------------------+     +--------------------+
| GPU Cluster CP     |     | GPU Worker Node    |
| (t3.medium)        |     | (g5.12xlarge)      |
| Ubuntu 22.04       |     | 4x NVIDIA A10G     |
| k0s control plane  |     | GPU Operator       |
+--------------------+     | Ubuntu 22.04       |
                           +--------------------+
```

### Two GPU Lab Options

| Configuration | Instance | GPUs | GPU Memory | Interconnect | Cost/hr (on-demand) | Best For |
|--------------|----------|------|------------|--------------|-------------------|----------|
| **Standard** | g5.12xlarge | 4x A10G | 24GB each | PCIe | ~$5.67 | Labs 5.1-5.12 |
| **Advanced** | p4d.24xlarge | 8x A100 | 40GB each | NVLink 3.0 (600 GB/s) | ~$32.77 | Labs 5.13-5.15, distributed training |

> **Cost reminder:** GPU instances are significantly more expensive than Week 1 infrastructure. Always destroy your GPU environment when not actively working. See [Cost Management](#cost-management) below.

---

## Prerequisites

Before starting Week 5 labs, you must have completed:

- [x] **Lab 1.1** - k0rdent management cluster provisioned and running
- [x] **Lab 1.3** - AWS infrastructure provider configured
- [x] **Lab 1.5** - Experience provisioning a managed cluster via `ClusterDeployment`
- [x] **Lab 1.7** - Understanding of `ServiceTemplate` and `MultiClusterService`

You will need:
- AWS credentials with EC2 GPU instance permissions (g5/p4d families)
- Your student lab environment provisioned (from Week 1)
- Your management cluster accessible via `lab-connect.sh`

---

## Step 1: Provision the GPU Lab Environment

You will create a GPU cluster as a `ClusterDeployment` on the management cluster -- the same pattern used in Week 1 Lab 1.5. No special `--gpu` flag is needed; the base lab infrastructure is all that is required.

### 1.1 Connect to the Management Cluster

```bash
cd lab-infrastructure
./scripts/lab-connect.sh <your-engineer-id>
```

### 1.2 Create the GPU ClusterDeployment

On the management cluster, apply the following manifest. This creates a standalone k0s cluster with a `g5.12xlarge` GPU worker node.

> **IMPORTANT:** You MUST use the Ubuntu 22.04 AMI (`ami-00de3875b03809ec5` for us-east-1). Amazon Linux 2 is NOT supported by the NVIDIA GPU Operator.

```yaml
# Save as gpu-cluster.yaml
apiVersion: k0rdent.mirantis.com/v1beta1
kind: ClusterDeployment
metadata:
  name: gpu-cluster
  namespace: kcm-system
spec:
  template: aws-standalone-cp-1-0-20
  credential: aws-credential
  config:
    clusterLabels: {}
    region: us-east-1
    controlPlane:
      instanceType: t3.medium
      amiID: ami-00de3875b03809ec5      # Ubuntu 22.04
    worker:
      instanceType: g5.12xlarge          # 4x NVIDIA A10G, 24GB each
      amiID: ami-00de3875b03809ec5       # Ubuntu 22.04
```

```bash
kubectl apply -f gpu-cluster.yaml
```

### Option B: Advanced GPU Instance (For distributed training labs)

For Labs 5.13-5.15 (RDMA, distributed training), change the worker instance type to `p4d.24xlarge` (8x A100, 40GB each) in the manifest above. All other settings remain the same.

### What Happens During Provisioning

The `ClusterDeployment` triggers the CAPI AWS provider to:

1. **VPC and Networking** - Creates VPC, subnets, and security groups in AWS
2. **Control Plane Node** - Launches a `t3.medium` instance and bootstraps k0s
3. **Worker Node** - Launches a `g5.12xlarge` instance and joins it to the cluster
4. **Cluster Ready** - kubeconfig secret is created in the management cluster

> **Wait time:** The full provisioning takes approximately 15 minutes. Monitor progress with:
> ```bash
> kubectl get clusterdeployment gpu-cluster -n kcm-system -w
> ```

---

## Step 2: Connect to the GPU Cluster

From the management cluster (connected via `lab-connect.sh`), extract the kubeconfig for your new GPU cluster:

```bash
# Extract the GPU cluster kubeconfig
kubectl get secret gpu-cluster-kubeconfig -n kcm-system \
  -o jsonpath='{.data.value}' | base64 -d > ~/.kube/gpu-cluster.conf

# Switch to the GPU cluster context
export KUBECONFIG=~/.kube/gpu-cluster.conf

# Verify connectivity
kubectl get nodes -o wide
```

You should see two nodes: the control plane (`t3.medium`) and the worker (`g5.12xlarge`).

---

## Step 3: Verify GPU Environment

Run through these checks to confirm your lab environment is ready. Ensure `KUBECONFIG` is set to the GPU cluster (see Step 2).

### 3.1 Verify NVIDIA Drivers and GPUs

After the GPU Operator is installed (Step 4), you can verify GPUs from inside a pod:

```bash
# Run nvidia-smi via a test pod
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

**Expected output (g5.12xlarge):**
```
+-----------------------------------------------------------------------------+
| NVIDIA-SMI 570.124.06    Driver Version: 570.124.06   CUDA Version: 12.8   |
|-------------------------------+----------------------+----------------------+
| GPU  Name        Persistence-M| Bus-Id        Disp.A | Volatile Uncorr. ECC |
|   0  NVIDIA A10G         On   | 00000000:00:1B.0 Off |                    0 |
|   1  NVIDIA A10G         On   | 00000000:00:1C.0 Off |                    0 |
|   2  NVIDIA A10G         On   | 00000000:00:1D.0 Off |                    0 |
|   3  NVIDIA A10G         On   | 00000000:00:1E.0 Off |                    0 |
+-------------------------------+----------------------+----------------------+
```

### 3.2 Check GPU Topology

```bash
# Verify GPU interconnect topology
nvidia-smi topo -m
```

- **A10G (g5.12xlarge):** Expect `PHB` (PCIe Host Bridge) connections between GPUs. A10G does NOT have NVLink.
- **A100 (p4d.24xlarge):** Expect `NV12` between all GPU pairs (full NVSwitch mesh).

### 3.3 Verify Kubernetes GPU Resources

```bash
# Confirm GPUs are allocatable on the worker node
kubectl get nodes -o custom-columns=\
'NAME:.metadata.name,GPUs:.status.allocatable.nvidia\.com/gpu'
```

**Expected:**
```
NAME                GPUs
gpu-cluster-md-...  4     # (or 8 for p4d.24xlarge)
```

### 3.4 Run a Quick GPU Test

```bash
# Run a simple CUDA test pod
kubectl run gpu-test \
  --image=nvidia/cuda:12.2.0-base-ubuntu22.04 \
  --restart=Never \
  --limits='nvidia.com/gpu=1' \
  --command -- nvidia-smi

# Check output (wait a few seconds for the pod to complete)
kubectl logs gpu-test

# Clean up
kubectl delete pod gpu-test
```

---

## Step 4: Deploy GPU Operator

With your `KUBECONFIG` pointing to the GPU cluster (see Step 2), install the NVIDIA GPU Operator via Helm. The k0s-specific containerd paths are required for the toolkit to function correctly.

```bash
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
helm repo update

helm install gpu-operator nvidia/gpu-operator \
  --namespace gpu-operator --create-namespace --version v25.3.0 \
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

Verify the operator pods are running:

```bash
kubectl get pods -n gpu-operator
```

All pods should reach `Running` or `Completed` status within a few minutes. The driver installation pod may take the longest as it compiles the kernel module on the worker node.

> **Why k0s-specific paths?** k0rdent uses k0s as its Kubernetes distribution. k0s stores the containerd configuration at `/etc/k0s/containerd.d/` and socket at `/run/k0s/containerd.sock`, unlike standard installations that use `/etc/containerd/` and `/run/containerd/containerd.sock`. The GPU Operator toolkit must be told where to write the NVIDIA runtime config. See [NVIDIA k0rdent Partner Validation](https://docs.nvidia.com/datacenter/cloud-native/partner-validated/latest/k0rdent.html) for details.

---

## Resuming Your Lab Environment

If your SSH session drops or you are returning another day:

```bash
# From your local machine
cd lab-infrastructure

# Reconnect to the management cluster
./scripts/lab-connect.sh <your-engineer-id>

# Re-extract the GPU cluster kubeconfig
kubectl get secret gpu-cluster-kubeconfig -n kcm-system \
  -o jsonpath='{.data.value}' | base64 -d > ~/.kube/gpu-cluster.conf
export KUBECONFIG=~/.kube/gpu-cluster.conf

# Verify GPU environment is still healthy
kubectl get nodes
kubectl get pods -n gpu-operator
```

> **Cluster lifecycle:** The GPU cluster persists as long as the `ClusterDeployment` resource exists on the management cluster. If you deleted the ClusterDeployment, re-apply the manifest from Step 1 and wait ~15 minutes for provisioning.

---

## Cost Management

GPU instances are the most expensive resources in this training:

| Instance | On-Demand | Daily (8 hrs) |
|----------|-----------|---------------|
| t3.medium (control plane) | $0.042/hr | ~$0.34 |
| g5.12xlarge (4x A10G) | $5.67/hr | ~$45.36 |
| p4d.24xlarge (8x A100) | $32.77/hr | ~$262.16 |

### Rules

1. **Delete the ClusterDeployment when not in use.** Do not leave GPU clusters running overnight.
   ```bash
   # On the management cluster
   kubectl delete clusterdeployment gpu-cluster -n kcm-system
   ```

2. **Use the standard GPU lab** (g5.12xlarge) for Labs 5.1-5.12. Only provision the advanced lab (p4d.24xlarge) for Labs 5.13-5.15.

### Check Running Resources

```bash
# On the management cluster -- verify if the GPU cluster is still running
kubectl get clusterdeployment -n kcm-system
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

**Advanced (Requires p4d.24xlarge worker)**

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

### ClusterDeployment Stuck in Provisioning

```bash
# Check the ClusterDeployment status
kubectl get clusterdeployment gpu-cluster -n kcm-system -o yaml | tail -30

# Check CAPA (Cluster API Provider AWS) controller logs
kubectl logs -n capa-system deployment/capa-controller-manager --tail=50

# Check if GPU capacity is available in your region
aws ec2 describe-instance-type-offerings \
  --location-type availability-zone \
  --filters "Name=instance-type,Values=g5.12xlarge" \
  --region $AWS_REGION
```

### GPU Operator Driver Pod in ImagePullBackOff

This typically happens when using an Amazon Linux 2 AMI. The NVIDIA GPU Operator requires Ubuntu 22.04. Verify your ClusterDeployment uses `ami-00de3875b03809ec5` (Ubuntu 22.04 for us-east-1).

```bash
# Check the driver pod status
kubectl get pods -n gpu-operator -l app=nvidia-driver-daemonset
kubectl describe pod -n gpu-operator -l app=nvidia-driver-daemonset
```

### nvidia-smi Shows No GPUs

```bash
# Check if the GPU Operator driver pod is running
kubectl get pods -n gpu-operator -l app=nvidia-driver-daemonset

# Check driver pod logs for errors
kubectl logs -n gpu-operator -l app=nvidia-driver-daemonset

# Verify the worker node has the GPU instance type
kubectl get nodes -o wide
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

### GPU Operator Pods Crashing

```bash
# Check GPU Operator pod status
kubectl get pods -n gpu-operator

# Common issue on k0s: wrong containerd paths
kubectl logs -n gpu-operator -l app=nvidia-container-toolkit-daemonset

# Fix: Ensure toolkit uses k0s paths (these should already be set if you
# followed the Helm install command in Step 4):
# /etc/k0s/containerd.d/nvidia.toml (NOT /etc/containerd/config.toml)
# /run/k0s/containerd.sock (NOT /run/containerd/containerd.sock)
```

---

## Cleanup

### After Each Lab Session

Delete the GPU ClusterDeployment to avoid unnecessary costs:

```bash
# On the management cluster
kubectl delete clusterdeployment gpu-cluster -n kcm-system
```

This triggers CAPI to tear down the worker node, control plane node, VPC, and all associated AWS resources.

### After Completing All Week 5 Labs

```bash
# Delete the GPU cluster (if still running)
kubectl delete clusterdeployment gpu-cluster -n kcm-system

# Optionally destroy your entire lab environment
./scripts/lab-destroy.sh <your-engineer-id> --auto-approve
```

---

## References

- [Lab Infrastructure README](../../../lab-infrastructure/README.md)
- [Week 1 Foundations](../../week-1-foundations/README.md)
- [Lab 1.7 - MultiClusterService](../../week-1-foundations/labs/lab-1.7-multicluster-services.md) (ServiceTemplate pattern)
- [k0rdent Service Catalog](https://catalog.k0rdent.io/)
- [NVIDIA GPU Operator - k0rdent Partner Validation](https://docs.nvidia.com/datacenter/cloud-native/partner-validated/latest/k0rdent.html)
- [NVIDIA GPU Operator Documentation](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/)
