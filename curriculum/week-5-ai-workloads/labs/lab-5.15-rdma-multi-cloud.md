# Lab 5.15 - Multi-Cloud RDMA Deep Dive: AWS EFA vs Azure InfiniBand

---

## Lab Navigation

| Track | Tier | Duration |
|-------|------|----------|
| Advanced | Optional | 4 hours |

### Week 5 Learning Paths

```
FOUNDATION (Completed)                        ADVANCED
━━━━━━━━━━━━━━━━━━━━━━                       ━━━━━━━━
5.1 ➔ 5.2 ➔ ... ➔ 5.8 ✓                     5.13 TensorRT-LLM
                                                  ↓
                                              5.14 Slurm
                                                  ↓
                                             YOU ARE HERE
                                                  ↓
                                             [5.15] RDMA Multi-Cloud
                                                  ↓
                                              5.16 Distributed Training
```

| Previous | Current | Next |
|----------|---------|------|
| [Lab 5.14 - Slurm on Kubernetes](lab-5.14-slurm-operator-hpc.md) | **Lab 5.15 - RDMA Multi-Cloud** | [Lab 5.16 - Distributed Training](lab-5.16-distributed-training.md) |

---

## Table of Contents

- [Objective](#objective)
- [Prerequisites](#prerequisites)
- [Background: High-Speed GPU Interconnects](#background-high-speed-gpu-interconnects)
- [Part 1: Understanding RDMA Technologies](#part-1-understanding-rdma-technologies)
- [Part 2: k0rdent Multi-Cloud GPU Infrastructure](#part-2-k0rdent-multi-cloud-gpu-infrastructure)
- [Part 3: AWS EFA Configuration](#part-3-aws-efa-configuration)
- [Part 4: Azure InfiniBand Configuration](#part-4-azure-infiniband-configuration)
- [Part 5: Multi-Cloud Performance Comparison](#part-5-multi-cloud-performance-comparison)

---

**Duration:** 4 hours
**Type:** Hands-on Technical (Advanced)
**Environment:** AWS p4d.24xlarge or Azure ND A100 v4

## Objective

Understand and configure Remote Direct Memory Access (RDMA) for GPU-accelerated AI workloads across AWS and Azure cloud platforms. This lab uses k0rdent's multi-cloud capabilities — ClusterDeployment, ServiceTemplate, and MultiClusterService — to deploy GPU networking infrastructure on both EFA (AWS) and InfiniBand (Azure) clusters from a single management plane.

## Prerequisites

- Completed Lab 5.2 (vLLM Inference Service)
- Completed Lab 5.3 (GPU Communication) recommended
- Access to either:
  - AWS: p4d.24xlarge instances with EFA enabled
  - Azure: ND A100 v4 or ND H100 v5 VMSS with InfiniBand
- NVIDIA GPU Operator deployed (via k0rdent catalog `gpu-operator-25-10-0`)
- Basic understanding of Kubernetes networking

---

## Background: High-Speed GPU Interconnects

### Why RDMA Matters for AI Workloads

Traditional TCP/IP networking creates significant overhead for GPU-to-GPU communication:

```
Traditional Networking (Without RDMA):
┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐
│  GPU 1  │───>│   CPU   │───>│  NIC    │───>│  NIC    │───>│  GPU 2  │
│ (Node A)│    │ Memory  │    │(Node A) │    │(Node B) │    │(Node B) │
└─────────┘    └─────────┘    └─────────┘    └─────────┘    └─────────┘
      │              │              │              │              │
      └──── Copy ────┴──── Copy ────┴──── TX/RX ──┴──── Copy ────┘

                    Latency: ~50-100+ microseconds
                    Throughput: Limited by PCIe and CPU
```

RDMA eliminates CPU involvement entirely:

```
With RDMA + GPUDirect:
┌─────────┐                                        ┌─────────┐
│  GPU 1  │────────── GPUDirect RDMA ─────────────>│  GPU 2  │
│ (Node A)│          (NIC bypasses CPU)            │(Node B) │
└─────────┘                                        └─────────┘
      │                                                  │
      └──────────── Direct memory transfer ──────────────┘

                    Latency: ~2-5 microseconds
                    Throughput: Up to 3200 Gbps (H100)
```

### The Impact on Distributed Training

In distributed training, GPUs must synchronize gradients after each batch using collective operations like **all-reduce**. Network bandwidth directly determines how fast this synchronization completes:

| Network Type | Relative Speed | Practical Impact |
|--------------|----------------|------------------|
| Standard TCP (1 Gbps) | Baseline | Unusable for large models |
| TCP (100 Gbps) | ~100x faster | Still bottlenecked by CPU copies |
| EFA/RDMA (400 Gbps) | ~400x faster | Practical for multi-node training |
| InfiniBand (3200 Gbps) | ~3200x faster | Near-optimal for large-scale training |

**Key Insight:** The difference between standard networking and RDMA can be the difference between a training run taking weeks vs days.

---

## Part 1: Understanding RDMA Technologies

### Task 1: RDMA Fundamentals (15 min)

**Remote Direct Memory Access (RDMA)** is a technology that enables:
- Direct memory-to-memory transfers between machines
- Bypassing the operating system kernel
- CPU-free data movement
- Sub-microsecond to low-microsecond latencies

#### RDMA Protocol Comparison

| Protocol | Full Name | Hardware | Use Case |
|----------|-----------|----------|----------|
| **InfiniBand** | Native InfiniBand | Mellanox/NVIDIA HCAs | HPC, AI training (on-prem, Azure) |
| **RoCE** | RDMA over Converged Ethernet | Mellanox/NVIDIA NICs | Data centers with lossless Ethernet |
| **iWARP** | Internet Wide Area RDMA Protocol | Various NICs | Longer distances, lossy networks |
| **EFA** | Elastic Fabric Adapter | AWS custom | AWS-specific RDMA (SRD protocol) |

#### AWS EFA vs Azure InfiniBand

| Feature | AWS EFA | Azure InfiniBand |
|---------|---------|------------------|
| **Technology Base** | Scalable Reliable Datagram (SRD) over Ethernet | True InfiniBand (NVIDIA ConnectX) |
| **Protocol** | Libfabric (SRD) | Native IB verbs |
| **Max Bandwidth** | 3,200 Gbps (P5, 32 NICs) | 3,200 Gbps (ND H100 v5, 8x 400G) |
| **GPUDirect Support** | Yes (via nvidia-peermem) | Yes (via nvidia-peermem) |
| **Standards Compliant** | AWS-specific (SRD) | Full InfiniBand standard |
| **On-Prem Equivalent** | No direct equivalent | Same as NVIDIA DGX |
| **NCCL Transport** | Via aws-ofi-nccl plugin | Native IB transport |

**Why This Matters:**

- **AWS EFA:** Great for cloud-native workloads, excellent AWS integration, but skills don't transfer to on-premises InfiniBand
- **Azure InfiniBand:** Industry-standard technology, skills transfer to NVIDIA DGX, Supermicro, and other HPC systems

---

## Part 2: k0rdent Multi-Cloud GPU Infrastructure

### Task 2: Provision GPU Clusters via k0rdent (30 min)

k0rdent's core value for RDMA workloads is managing GPU clusters across cloud providers from a single management plane. Each provider requires different infrastructure (EFA vs InfiniBand), but k0rdent abstracts the provisioning.

1. **Review AWS GPU ClusterDeployment**

   The AWS cluster uses p4d/p5 instances with EFA enabled:
   ```yaml
   apiVersion: k0rdent.mirantis.com/v1beta1
   kind: ClusterDeployment
   metadata:
     name: aws-gpu-cluster
     namespace: gpu-training
     labels:
       workload-type: gpu-training
       cloud-provider: aws
       rdma-type: efa
   spec:
     template: aws-standalone-cp-0-1-0
     credential: aws-cluster-identity-cred
     config:
       region: us-west-2
       controlPlane:
         instanceType: m5.xlarge
       worker:
         instanceType: p4d.24xlarge
       workersNumber: 2
       # EFA requires a placement group for lowest latency
       # Configured via the ClusterTemplate Helm chart values
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
             driver:
               rdma:
                 enabled: true
                 useHostMofed: false
   ```

2. **Review Azure GPU ClusterDeployment**

   The Azure cluster uses ND-series VMs with InfiniBand:
   ```yaml
   apiVersion: k0rdent.mirantis.com/v1beta1
   kind: ClusterDeployment
   metadata:
     name: azure-gpu-cluster
     namespace: gpu-training
     labels:
       workload-type: gpu-training
       cloud-provider: azure
       rdma-type: infiniband
   spec:
     template: azure-standalone-cp-0-1-0
     credential: azure-cluster-identity-cred
     config:
       location: westus2
       subscriptionID: "<subscription-id>"
       controlPlane:
         vmSize: Standard_D4s_v3
       worker:
         vmSize: Standard_ND96isr_H100_v5  # 'r' suffix = RDMA-capable
       workersNumber: 2
       # InfiniBand requires single_placement_group = true in VMSS
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
             driver:
               rdma:
                 enabled: true
                 useHostMofed: true  # Azure pre-installs MOFED drivers
   ```

3. **Deploy the Network Operator via MultiClusterService**

   The NVIDIA Network Operator manages RDMA device plugins across all GPU clusters:
   ```yaml
   apiVersion: k0rdent.mirantis.com/v1beta1
   kind: MultiClusterService
   metadata:
     name: network-operator
     namespace: kcm-system
   spec:
     clusterSelector:
       matchLabels:
         workload-type: gpu-training
     serviceSpec:
       services:
         - template: nvidia-network-operator-25-10-0
           name: network-operator
           namespace: nvidia-network-operator
           values: |
             nfd:
               enabled: false
             ofedDriver:
               deploy: false
             rdmaSharedDevicePlugin:
               deploy: true
             secondaryNetwork:
               deploy: false
   ```

   ```bash
   # Apply from the management cluster
   kubectl apply -f aws-gpu-cluster.yaml
   kubectl apply -f azure-gpu-cluster.yaml
   kubectl apply -f network-operator-mcs.yaml

   # Monitor provisioning
   kubectl get clusterdeployments -n gpu-training -w
   ```

---

## Part 3: AWS EFA Configuration

### Task 3: Verify EFA Prerequisites (20 min)

AWS EFA provides RDMA capabilities through the **Scalable Reliable Datagram (SRD)** protocol:

```
AWS EFA Architecture:
┌─────────────────────────────────────────────────────────────────┐
│                    AWS EFA Network Fabric                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────────────┐         ┌──────────────────┐              │
│  │   P4d Node 1     │         │   P4d Node 2     │              │
│  │  ┌────────────┐  │  EFA    │  ┌────────────┐  │              │
│  │  │ 8x A100    │  │  400    │  │ 8x A100    │  │              │
│  │  │ NVSwitch   │  │  Gbps   │  │ NVSwitch   │  │              │
│  │  └─────┬──────┘  │<------->│  └─────┬──────┘  │              │
│  │        │         │         │        │         │              │
│  │  ┌─────▼──────┐  │         │  ┌─────▼──────┐  │              │
│  │  │ 4x EFA    │  │         │  │ 4x EFA    │  │              │
│  │  │ Interfaces │  │         │  │ Interfaces │  │              │
│  │  └────────────┘  │         │  └────────────┘  │              │
│  └──────────────────┘         └──────────────────┘              │
│                                                                 │
│  P5 instances: 32x EFA interfaces (3,200 Gbps total)           │
└─────────────────────────────────────────────────────────────────┘
```

**Instance EFA Specifications:**

| Instance | GPUs | EFA Interfaces | Total Bandwidth |
|----------|------|---------------|-----------------|
| p4d.24xlarge | 8x A100 | 4 | 400 Gbps |
| p5.48xlarge | 8x H100 | 32 | 3,200 Gbps |

1. **Switch to the AWS GPU cluster context**
   ```bash
   # Get kubeconfig from k0rdent
   kubectl get secret -n gpu-training aws-gpu-cluster-kubeconfig \
     -o jsonpath='{.data.value}' | base64 -d > /tmp/aws-gpu.kubeconfig
   export KUBECONFIG=/tmp/aws-gpu.kubeconfig
   ```

2. **Verify EFA on Worker Nodes**

   SSH into a GPU worker node:
   ```bash
   # Verify instance type
   curl -s http://169.254.169.254/latest/meta-data/instance-type
   # Expected: p4d.24xlarge or p5.48xlarge

   # Check EFA device
   fi_info -p efa
   # Should show EFA provider information

   # Check EFA module loaded
   lsmod | grep efa
   # Expected: efa module loaded

   # Verify placement group
   curl -s http://169.254.169.254/latest/meta-data/placement/group-name
   ```

### Task 4: Deploy AWS EFA Device Plugin (20 min)

The EFA device plugin exposes EFA interfaces as Kubernetes resources.

1. **Install via Helm (recommended)**
   ```bash
   helm repo add eks https://aws.github.io/eks-charts
   helm repo update

   helm install aws-efa-k8s-device-plugin eks/aws-efa-k8s-device-plugin \
     --namespace kube-system \
     --set tolerations[0].key=nvidia.com/gpu \
     --set tolerations[0].operator=Exists \
     --set tolerations[0].effect=NoSchedule
   ```

2. **Verify EFA Resources Available**
   ```bash
   # Check that EFA devices are registered
   kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.allocatable.vpc\.amazonaws\.com/efa}{"\n"}{end}'

   # Expected output:
   # gpu-worker-1    4    (for p4d)
   # gpu-worker-2    4
   ```

### Task 5: Test EFA with NCCL (30 min)

1. **Create NCCL Test Pod**
   ```yaml
   # Save as nccl-test-efa.yaml
   apiVersion: v1
   kind: Pod
   metadata:
     name: nccl-test-efa
     namespace: default
   spec:
     restartPolicy: Never
     containers:
       - name: nccl-test
         image: nvcr.io/nvidia/pytorch:24.12-py3
         command: ["sleep", "infinity"]
         env:
           # NCCL configuration for EFA
           - name: NCCL_DEBUG
             value: "INFO"
           - name: NCCL_DEBUG_SUBSYS
             value: "INIT,NET"
           - name: FI_PROVIDER
             value: "efa"
           - name: FI_EFA_USE_DEVICE_RDMA
             value: "1"
           - name: NCCL_NET_GDR_LEVEL
             value: "SYS"
           - name: LD_LIBRARY_PATH
             value: "/opt/amazon/efa/lib:/usr/local/lib:$LD_LIBRARY_PATH"
         resources:
           limits:
             nvidia.com/gpu: 8
             vpc.amazonaws.com/efa: 4
           requests:
             nvidia.com/gpu: 8
             vpc.amazonaws.com/efa: 4
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
           sizeLimit: 64Gi
     tolerations:
       - key: nvidia.com/gpu
         operator: Exists
         effect: NoSchedule
   ```

   ```bash
   kubectl apply -f nccl-test-efa.yaml
   kubectl wait --for=condition=Ready pod/nccl-test-efa --timeout=300s
   ```

2. **Run NCCL All-Reduce Test**
   ```bash
   kubectl exec -it nccl-test-efa -- bash

   # Single-node 8-GPU all-reduce benchmark
   cd /opt/nccl-tests/build
   ./all_reduce_perf -b 1M -e 1G -f 2 -g 8

   # Expected output columns:
   #   size    count   type  redop   time   algbw  busbw  error
   #
   # For 8x A100 with NVSwitch, expect:
   #   ~200-230 GB/s busbw for large messages (≥256MB)
   #   This is the realistic NVSwitch all-reduce bandwidth.
   ```

3. **Interpret NCCL Output**

   | Column | Meaning |
   |--------|---------|
   | size | Message size in bytes |
   | time | Time in milliseconds |
   | algbw | Algorithm bandwidth (GB/s) — data_size / time |
   | busbw | Bus bandwidth (GB/s) — accounts for the ring/tree algorithm factor |

   **Expected Performance (8x A100 with NVSwitch):**
   - Bus bandwidth: ~200-230 GB/s for large messages (≥256MB)
   - This confirms NVLink is being used within the node

   > **Note:** The A100 NVLink spec is 600 GB/s bidirectional per GPU. The all-reduce busbw reflects the effective unidirectional throughput after accounting for the collective algorithm overhead, which is why ~200-230 GB/s is the expected realistic value.

4. **Verify EFA Transport in Logs**
   ```bash
   # Look for EFA transport in NCCL debug output
   # Expected: "NCCL INFO NET/AWS-EFA" or "NCCL INFO NET/OFI"
   # If you see "NCCL INFO NET/Socket" — EFA is NOT being used (TCP fallback)
   ```

---

## Part 4: Azure InfiniBand Configuration

### Task 6: Understand Azure InfiniBand Architecture (15 min)

Azure provides **true InfiniBand** networking on ND-series VMs:

```
Azure InfiniBand Architecture:
┌─────────────────────────────────────────────────────────────────┐
│              Azure InfiniBand Fabric (Quantum-2)                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────────────────────────────────────────────────┐       │
│  │           Virtual Machine Scale Set (VMSS)           │       │
│  │         single_placement_group = true                │       │
│  └──────────────────────────────────────────────────────┘       │
│                           │                                     │
│       ┌───────────────────┼───────────────────┐                 │
│       │                   │                   │                 │
│  ┌────▼─────┐       ┌─────▼────┐       ┌─────▼────┐             │
│  │ND H100 #1│<─IB──>│ND H100 #2│<─IB──>│ND H100 #3│             │
│  │8x H100   │ 3.2Tb │8x H100   │  3.2Tb│8x H100   │             │
│  │NVSwitch  │       │NVSwitch  │       │NVSwitch  │             │
│  └──────────┘       └──────────┘       └──────────┘             │
│       │                   │                   │                 │
│       └───────────────────┴───────────────────┘                 │
│              GPUDirect RDMA (nvidia-peermem)                    │
└─────────────────────────────────────────────────────────────────┘
```

**Azure ND H100 v5 InfiniBand Configuration:**
- 8x 400 Gb/s InfiniBand ports (3.2 Tb/s total per VM)
- NVIDIA Quantum-2 InfiniBand switches
- Same technology as on-premises NVIDIA DGX SuperPOD
- Requires VMSS with `single_placement_group = true`

### Task 7: Verify Azure InfiniBand Prerequisites (20 min)

1. **Switch to the Azure GPU cluster context**
   ```bash
   kubectl get secret -n gpu-training azure-gpu-cluster-kubeconfig \
     -o jsonpath='{.data.value}' | base64 -d > /tmp/azure-gpu.kubeconfig
   export KUBECONFIG=/tmp/azure-gpu.kubeconfig
   ```

2. **Verify VM is RDMA-Capable**

   SSH into an Azure GPU worker node:
   ```bash
   # Check VM size (must have 'r' suffix for RDMA)
   curl -H "Metadata:true" \
     "http://169.254.169.254/metadata/instance/compute/vmSize?api-version=2021-02-01&format=text"
   # Expected: Standard_ND96isr_H100_v5 (note the 'r')
   ```

3. **Verify InfiniBand Hardware**
   ```bash
   # Check InfiniBand HCA (Host Channel Adapter)
   ibstat

   # Expected output:
   # CA 'mlx5_0'
   #   CA type: MT4123
   #   Number of ports: 1
   #   Port 1:
   #     State: Active
   #     Physical state: LinkUp
   #     Rate: 400 Gb/s

   # Check all InfiniBand devices
   ibv_devinfo

   # Show InfiniBand port status
   ibstatus
   ```

4. **Verify MOFED Driver**
   ```bash
   # Check MOFED (Mellanox OpenFabrics Enterprise Distribution) version
   ofed_info -s
   # Expected: MLNX_OFED_LINUX-5.x.x.x or MLNX_OFED_LINUX-24.x

   # Verify IB kernel modules
   lsmod | grep mlx5
   # Should show: mlx5_core, mlx5_ib
   ```

### Task 8: Configure Network Operator for InfiniBand (30 min)

For Azure InfiniBand, the Network Operator needs RDMA device plugin configuration via a values file (the `--set` flag does not support the JSON config structure).

1. **Create Network Operator Values for Azure**
   ```yaml
   # Save as network-operator-azure-values.yaml
   nfd:
     enabled: false
   ofedDriver:
     deploy: false       # Azure pre-installs MOFED
   rdmaSharedDevicePlugin:
     deploy: true
   sriovDevicePlugin:
     deploy: false
   secondaryNetwork:
     deploy: false
   deployCR: true
   nicClusterPolicy:
     rdmaSharedDevicePlugin:
       config: |
         {
           "configList": [{
             "resourceName": "rdma_shared_device_ib",
             "rdmaHcaMax": 8,
             "selectors": {
               "ifNames": ["ib0", "ib1", "ib2", "ib3", "ib4", "ib5", "ib6", "ib7"]
             }
           }]
         }
   ```

   > **Note:** The `rdmaSharedDevicePlugin.config` is a JSON string that configures the [k8s-rdma-shared-dev-plugin](https://github.com/Mellanox/k8s-rdma-shared-dev-plugin). The `rdmaHcaMax` value sets the maximum number of RDMA HCA devices a single pod can request. The `selectors.ifNames` lists the InfiniBand interface names.

2. **Install Network Operator with Azure Values**

   If not already deployed via the MultiClusterService in Task 2, install directly:
   ```bash
   helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
   helm repo update

   helm install network-operator nvidia/network-operator \
     --version v25.10.0 \
     --namespace nvidia-network-operator \
     --create-namespace \
     -f network-operator-azure-values.yaml
   ```

3. **Verify InfiniBand Resources in Kubernetes**
   ```bash
   kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.allocatable.rdma/rdma_shared_device_ib}{"\n"}{end}'

   # Expected:
   # gpu-worker-1    8
   # gpu-worker-2    8
   ```

### Task 9: Test InfiniBand with NCCL (30 min)

1. **Create NCCL Test Pod for InfiniBand**
   ```yaml
   # Save as nccl-test-ib.yaml
   apiVersion: v1
   kind: Pod
   metadata:
     name: nccl-test-ib
     namespace: default
   spec:
     restartPolicy: Never
     containers:
       - name: nccl-test
         image: nvcr.io/nvidia/pytorch:24.12-py3
         command: ["sleep", "infinity"]
         env:
           # NCCL configuration for InfiniBand
           - name: NCCL_DEBUG
             value: "INFO"
           - name: NCCL_DEBUG_SUBSYS
             value: "INIT,NET"
           - name: NCCL_IB_DISABLE
             value: "0"
           - name: NCCL_NET_GDR_LEVEL
             value: "SYS"
           - name: NCCL_IB_HCA
             value: "mlx5"
         resources:
           limits:
             nvidia.com/gpu: 8
             rdma/rdma_shared_device_ib: 8
           requests:
             nvidia.com/gpu: 8
             rdma/rdma_shared_device_ib: 8
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
           sizeLimit: 64Gi
     tolerations:
       - key: nvidia.com/gpu
         operator: Exists
         effect: NoSchedule
   ```

   > **Note:** We omit `NCCL_IB_GID_INDEX` and let NCCL auto-detect (default behavior since NCCL 2.21+). If you encounter issues, set `NCCL_IB_GID_INDEX=3` for RoCE v2 or verify with `show_gids`.

   ```bash
   kubectl apply -f nccl-test-ib.yaml
   kubectl wait --for=condition=Ready pod/nccl-test-ib --timeout=300s
   ```

2. **Run InfiniBand Bandwidth Test**
   ```bash
   kubectl exec -it nccl-test-ib -- bash

   # Test raw InfiniBand bandwidth (between two nodes)
   # On node 1:
   ib_write_bw --all --report_gbits

   # On node 2 (separate terminal):
   ib_write_bw --all --report_gbits <node1-ib-ip>

   # Expected: ~390-400 Gb/s per port
   ```

3. **Run NCCL All-Reduce Test**
   ```bash
   cd /opt/nccl-tests/build

   # Single-node 8-GPU test
   ./all_reduce_perf -b 1M -e 1G -f 2 -g 8

   # For 8x A100 (ND A100 v4): expect ~200-230 GB/s busbw
   # For 8x H100 (ND H100 v5): expect ~400-470 GB/s busbw

   # Verify IB transport in NCCL output:
   # "NCCL INFO NET/IB : Using [0]mlx5_0:1/IB"
   # This confirms InfiniBand is being used
   ```

---

## Part 5: Multi-Cloud Performance Comparison

### Task 10: Benchmark Comparison (30 min)

Create identical benchmarks on both platforms to compare performance.

1. **Create Benchmark Script**
   ```bash
   # Save as benchmark-rdma.sh
   #!/bin/bash
   set -e

   echo "=== RDMA Benchmark Results ==="
   echo "Platform: $(hostname)"
   echo "Date: $(date)"
   echo ""

   # GPU Topology
   echo "=== GPU Topology ==="
   nvidia-smi topo -m
   echo ""

   # NCCL All-Reduce (varying message sizes)
   echo "=== NCCL All-Reduce Benchmark ==="
   cd /opt/nccl-tests/build
   ./all_reduce_perf -b 1M -e 4G -f 2 -g 8 -n 100 -w 10
   ```

2. **Expected Results**

   Single-node intra-node bandwidth depends on NVLink (same hardware on both platforms):

   | Test | AWS EFA (P4d, 8x A100) | Azure IB (ND A100 v4) | Notes |
   |------|------------------------|----------------------|-------|
   | Single-node all-reduce busbw | ~200-230 GB/s | ~200-230 GB/s | NVSwitch-limited, equal |
   | Cross-node latency (small msg) | ~5-10 us | ~2-5 us | IB lower latency |
   | GPUDirect RDMA | Supported | Supported | Both via nvidia-peermem |

   > **Important:** Single-node all-reduce performance is determined by NVLink/NVSwitch, not the inter-node network. EFA and InfiniBand only affect **cross-node** (multi-node) communication. Expect identical single-node numbers on both platforms when using the same GPU hardware.

3. **Document Your Results**

   Create a comparison table for your deployment:

   ```markdown
   ## RDMA Performance Comparison

   | Metric | AWS EFA | Azure InfiniBand | Winner |
   |--------|---------|------------------|--------|
   | Single-node busbw (8 GPU) | ___GB/s | ___GB/s | Tie (NVLink) |
   | Multi-node busbw (16 GPU) | ___GB/s | ___GB/s | ___ |
   | Small message latency | ___us | ___us | ___ |
   ```

---

## Part 6: k0rdent Multi-Cloud Workload Deployment

### Task 11: Deploy vLLM via MultiClusterService (30 min)

This task demonstrates k0rdent's ability to deploy the same application workload across both cloud providers using a single MultiClusterService declaration.

1. **Create a Custom ServiceTemplate for vLLM**

   First, install the ServiceTemplate from the management cluster:
   ```yaml
   # Save as vllm-inference-template.yaml
   apiVersion: k0rdent.mirantis.com/v1beta1
   kind: ServiceTemplate
   metadata:
     name: vllm-inference-0-1-0
     namespace: kcm-system
   spec:
     helm:
       chartRef:
         kind: HelmChart
         name: vllm-inference
         namespace: kcm-system
   ```

   > **Note:** In a production setup, you would package the vLLM deployment as a Helm chart in your chart repository. For this lab, we demonstrate the pattern using a standard Kubernetes Deployment.

2. **Deploy vLLM Across Both Clouds**

   Use MultiClusterService to target all GPU training clusters:
   ```yaml
   # Save as vllm-multi-cloud-mcs.yaml
   apiVersion: k0rdent.mirantis.com/v1beta1
   kind: MultiClusterService
   metadata:
     name: vllm-inference
     namespace: kcm-system
   spec:
     clusterSelector:
       matchLabels:
         workload-type: gpu-training
     serviceSpec:
       services:
         - template: vllm-inference-0-1-0
           name: vllm-llama
           namespace: ai-inference
           values: |
             model: meta-llama/Llama-2-70b-chat-hf
             tensorParallelSize: 8
             maxModelLen: 4096
   ```

   Alternatively, deploy a platform-agnostic manifest directly on each cluster:
   ```yaml
   # Save as vllm-deployment.yaml
   apiVersion: apps/v1
   kind: Deployment
   metadata:
     name: vllm-llama-70b
     namespace: ai-inference
   spec:
     replicas: 1
     selector:
       matchLabels:
         app: vllm-llama
     template:
       metadata:
         labels:
           app: vllm-llama
       spec:
         containers:
           - name: vllm
             image: vllm/vllm-openai:v0.7.3
             args:
               - --model
               - meta-llama/Llama-2-70b-chat-hf
               - --tensor-parallel-size
               - "8"
               - --max-model-len
               - "4096"
             env:
               # NCCL auto-detects the best transport (EFA or IB)
               - name: NCCL_P2P_LEVEL
                 value: "NVL"
             ports:
               - containerPort: 8000
             resources:
               limits:
                 nvidia.com/gpu: 8
               requests:
                 nvidia.com/gpu: 8
             volumeMounts:
               - name: shm
                 mountPath: /dev/shm
               - name: model-cache
                 mountPath: /root/.cache/huggingface
         volumes:
           - name: shm
             emptyDir:
               medium: Memory
               sizeLimit: 64Gi
           - name: model-cache
             persistentVolumeClaim:
               claimName: model-cache-pvc
         tolerations:
           - key: nvidia.com/gpu
             operator: Exists
             effect: NoSchedule
   ```

3. **Compare Inference Performance**
   ```bash
   # Test on AWS cluster
   export KUBECONFIG=/tmp/aws-gpu.kubeconfig
   SVC_IP=$(kubectl get svc -n ai-inference vllm-llama-70b -o jsonpath='{.spec.clusterIP}')
   curl -s -X POST http://${SVC_IP}:8000/v1/completions \
     -H "Content-Type: application/json" \
     -d '{
       "model": "meta-llama/Llama-2-70b-chat-hf",
       "prompt": "Explain the concept of RDMA in simple terms.",
       "max_tokens": 200
     }' | jq '.usage'

   # Repeat on Azure cluster
   export KUBECONFIG=/tmp/azure-gpu.kubeconfig
   # (same curl command)
   ```

### Task 12: NCCL Environment Variable Reference (15 min)

Document the key NCCL environment variables for both platforms:

```yaml
# ConfigMap for enterprise GPU workloads
apiVersion: v1
kind: ConfigMap
metadata:
  name: nccl-config
data:
  # ===== Common Settings =====
  NCCL_DEBUG: "INFO"             # Enable debugging (use WARN in production)
  NCCL_P2P_LEVEL: "NVL"          # Use NVLink for intra-node P2P
  NCCL_NET_GDR_LEVEL: "SYS"      # Enable GPUDirect RDMA system-wide

  # ===== AWS EFA Specific =====
  # FI_PROVIDER: "efa"             # Force EFA provider
  # FI_EFA_USE_DEVICE_RDMA: "1"    # Enable EFA RDMA (auto-detected on modern stacks)

  # ===== Azure InfiniBand Specific =====
  # NCCL_IB_DISABLE: "0"           # Ensure InfiniBand is enabled (default)
  # NCCL_IB_HCA: "mlx5"            # Use Mellanox/NVIDIA HCA
```

> **NCCL_NET_GDR_LEVEL values:** `LOC` (local GPU), `PIX` (same PCIe switch), `PXB` (same PCIe bus), `PHB` (same NUMA node), `SYS` (system-wide, crosses NUMA). Use `SYS` for GPUDirect RDMA across all topologies. Do **not** use numeric values — they are a legacy format.

---

## Deliverables

### Basic Deliverables (Either Platform)
- [ ] GPU cluster provisioned via k0rdent ClusterDeployment
- [ ] GPU Operator deployed with `driver.rdma.enabled=true`
- [ ] Network Operator deployed with RDMA shared device plugin
- [ ] EFA/InfiniBand driver verified and working on GPU nodes
- [ ] NCCL test showing ~200-230 GB/s intra-node busbw (8x A100) or ~400-470 GB/s (8x H100)
- [ ] NCCL debug output confirming correct transport (EFA or IB, not Socket/TCP)

### Advanced Deliverables (Both Platforms)
- [ ] Both AWS and Azure clusters managed from same k0rdent management cluster
- [ ] Network Operator deployed via MultiClusterService
- [ ] Side-by-side performance comparison table
- [ ] vLLM deployment running on both platforms
- [ ] Documentation of NCCL configuration differences between EFA and IB
- [ ] Platform selection recommendations for different workload types

---

## Verification Checklist

### AWS EFA
- [ ] `fi_info -p efa` shows EFA provider
- [ ] `vpc.amazonaws.com/efa` resource available in Kubernetes node allocatable
- [ ] NCCL logs show `NET/AWS-EFA` or `NET/OFI` transport
- [ ] All-reduce busbw ≥ 200 GB/s for 8x A100 (single-node, large messages)

### Azure InfiniBand
- [ ] `ibstat` shows Active state with 400 Gb/s rate
- [ ] `rdma/rdma_shared_device_ib` resource available in Kubernetes node allocatable
- [ ] NCCL logs show `NET/IB` transport
- [ ] All-reduce busbw ≥ 200 GB/s for 8x A100 (single-node, large messages)

### k0rdent Multi-Cloud
- [ ] Both ClusterDeployments show `Ready` status
- [ ] MultiClusterService deployed Network Operator to both clusters
- [ ] Same vLLM workload runs on both platforms
- [ ] NCCL auto-detects correct transport on each platform

---

## Troubleshooting

### EFA Not Detected (AWS)

```bash
# Check EFA driver
lsmod | grep efa
# If missing — the AMI may not include EFA drivers; check instance type supports EFA

# Check security group allows EFA traffic
# EFA requires a security group that allows ALL traffic from itself
aws ec2 describe-security-groups --group-ids <sg-id> \
  --query 'SecurityGroups[0].IpPermissions'
```

### InfiniBand Port Down (Azure)

```bash
# Check InfiniBand status
ibstat
# If "Physical state: Polling", check:

# 1. VMSS single_placement_group must be true
# 2. All VMs must be in same VMSS
# 3. VM size must have 'r' suffix (e.g., Standard_ND96isr_H100_v5)
# 4. InfiniBand driver extension installed:
az vmss extension list --resource-group <rg> --vmss-name <vmss>
```

### NCCL Falls Back to TCP

```bash
# Check NCCL debug output for:
# "NCCL INFO NET/Socket" — indicates TCP fallback

# For EFA — verify provider and RDMA:
export FI_PROVIDER=efa
export FI_EFA_USE_DEVICE_RDMA=1

# For InfiniBand — verify IB is enabled:
export NCCL_IB_DISABLE=0
export NCCL_IB_HCA=mlx5
```

### GPUDirect RDMA Not Working

```bash
# Verify nvidia-peermem module (loaded by GPU Operator when driver.rdma.enabled=true)
lsmod | grep nvidia_peermem

# If missing — check GPU Operator logs:
kubectl logs -n gpu-operator -l app=nvidia-driver-daemonset --tail=50

# Verify GPUDirect is used in NCCL output:
# Look for "GDR" in debug output when running nccl-tests
export NCCL_NET_GDR_LEVEL=SYS
```

---

## Key Takeaways

### Technology Comparison

| Aspect | AWS EFA | Azure InfiniBand | Recommendation |
|--------|---------|------------------|----------------|
| **Performance** | Excellent | Excellent | Tie for single-node; IB may edge on latency |
| **Standards** | AWS-specific (SRD) | Industry Standard (IB) | Azure for skill transfer |
| **Setup Complexity** | Medium (device plugin) | Medium (MOFED + device plugin) | Similar |
| **On-Prem Equivalent** | None | NVIDIA DGX | Azure for hybrid |
| **k0rdent Integration** | ClusterTemplate + EFA plugin | ClusterTemplate + Network Operator | Both via MultiClusterService |

### When to Use Each Platform

**Choose AWS EFA when:**
- Already invested in AWS ecosystem
- Cloud-only deployment (no on-prem)
- Want simpler EFA device plugin setup
- Cost optimization via spot instances

**Choose Azure InfiniBand when:**
- Need industry-standard RDMA skills
- Planning hybrid cloud/on-prem deployment
- Want same technology as NVIDIA DGX SuperPOD
- Already using Azure services

### k0rdent Multi-Cloud Value

This lab demonstrates k0rdent's core value for GPU infrastructure:
- **ClusterDeployment** abstracts cloud-specific provisioning (EFA vs IB)
- **MultiClusterService** deploys GPU and Network Operators identically across clouds
- **ServiceTemplate** enables portable application workloads
- **Label-based targeting** routes workloads to the right infrastructure
- **Single management plane** for heterogeneous GPU clusters

---

## References

### AWS
- [AWS EFA Documentation](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/efa.html)
- [EFA Kubernetes Device Plugin](https://github.com/aws/aws-efa-k8s-device-plugin)
- [aws-ofi-nccl Plugin](https://github.com/aws/aws-ofi-nccl)

### Azure
- [Azure InfiniBand Setup](https://learn.microsoft.com/en-us/azure/virtual-machines/setup-infiniband)
- [ND H100 v5 Series](https://learn.microsoft.com/en-us/azure/virtual-machines/sizes/gpu-accelerated/ndh100v5-series)
- [Azure HPC/AI with InfiniBand and Network Operator](https://techcommunity.microsoft.com/blog/azurehighperformancecomputingblog/running-tightly-coupled-hpcai-workloads-with-infiniband-using-nvidia-network-ope/4117209)

### NVIDIA
- [NCCL Environment Variables](https://docs.nvidia.com/deeplearning/nccl/user-guide/docs/env.html)
- [GPUDirect RDMA](https://docs.nvidia.com/cuda/gpudirect-rdma/index.html)
- [Network Operator Documentation](https://docs.nvidia.com/networking/display/kubernetes2570/)
- [GPU Operator RDMA Configuration](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/gpu-operator-rdma.html)

### k0rdent
- [k0rdent Documentation](https://docs.k0rdent.io/)
- [k0rdent Enterprise Documentation](https://docs.mirantis.com/k0rdent-enterprise/latest/)
- [k0rdent Partner Validated with NVIDIA GPU Operator](https://docs.nvidia.com/datacenter/cloud-native/partner-validated/latest/k0rdent.html)

---

## Next Lab

Proceed to [Lab 5.15 - Multi-Node Distributed Training](lab-5.16-distributed-training.md)
