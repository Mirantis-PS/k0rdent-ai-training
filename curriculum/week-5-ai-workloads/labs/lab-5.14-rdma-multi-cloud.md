# Lab 5.14 - Multi-Cloud RDMA Deep Dive: AWS EFA vs Azure InfiniBand

**Duration:** 4 hours
**Type:** Hands-on Technical (Advanced)
**Environment:** AWS p4d.24xlarge or Azure ND A100 v4

## Objective

Understand and configure Remote Direct Memory Access (RDMA) for GPU-accelerated AI workloads across AWS and Azure cloud platforms. This lab demonstrates k0rdent's multi-cloud capabilities by deploying identical GPU workloads on both EFA (AWS) and InfiniBand (Azure) infrastructure.

## Prerequisites

- Completed Lab 5.2 (vLLM Inference Service)
- Completed Lab 5.13 (TensorRT-LLM) recommended
- Access to either:
  - AWS: p4d.24xlarge instances with EFA enabled
  - Azure: ND A100 v4 or ND H100 v5 VMSS with InfiniBand
- NVIDIA GPU Operator and Network Operator installed
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

                    Latency: <2 microseconds
                    Throughput: Up to 3200 Gbps (H100)
```

### The Impact on Distributed Training

In distributed training, GPUs must synchronize gradients after each batch using collective operations like **all-reduce**. For a 70B parameter model:

| Network Type | All-Reduce Time | Total Training Impact |
|--------------|-----------------|----------------------|
| Standard TCP (1 Gbps) | ~56 seconds | Unusable |
| TCP (100 Gbps) | ~560 ms | Very slow |
| EFA/RDMA (400 Gbps) | ~140 ms | Acceptable |
| InfiniBand (3200 Gbps) | ~17.5 ms | Optimal |

**Key Insight:** The difference between standard networking and RDMA can be the difference between a training run taking weeks vs days.

---

## Part 1: Understanding RDMA Technologies

### 1.1 What is RDMA?

**Remote Direct Memory Access (RDMA)** is a technology that enables:
- Direct memory-to-memory transfers between machines
- Bypassing the operating system kernel
- CPU-free data movement
- Sub-microsecond latencies

### 1.2 RDMA Protocol Comparison

| Protocol | Full Name | Hardware | Use Case |
|----------|-----------|----------|----------|
| **InfiniBand** | Native InfiniBand | Mellanox HCAs | HPC, AI training (on-prem, Azure) |
| **RoCE** | RDMA over Converged Ethernet | Mellanox NICs | Data centers with lossless Ethernet |
| **iWARP** | Internet Wide Area RDMA Protocol | Various NICs | Longer distances, lossy networks |
| **EFA** | Elastic Fabric Adapter | AWS custom | AWS-specific RDMA implementation |

### 1.3 AWS EFA vs Azure InfiniBand

| Feature | AWS EFA | Azure InfiniBand |
|---------|---------|------------------|
| **Technology Base** | Proprietary over Ethernet | True InfiniBand (Mellanox) |
| **Protocol** | Libfabric (SRD) | Native IB verbs |
| **Max Bandwidth** | 3200 Gbps (P5, 32 NICs) | 3200 Gbps (ND H100 v5) |
| **GPUDirect Support** | Yes | Yes |
| **Standards Compliant** | Partial (AWS-specific) | Full InfiniBand standard |
| **On-Prem Equivalent** | No direct equivalent | Same as NVIDIA DGX |
| **NCCL Support** | Via AWS OFI plugin | Native |

**Why This Matters for Training:**

- **AWS EFA:** Great for cloud-native workloads, excellent AWS integration, but skills don't transfer to on-premises InfiniBand
- **Azure InfiniBand:** Industry-standard technology, skills transfer to NVIDIA DGX, Supermicro, and other HPC systems

---

## Part 2: AWS EFA Configuration

### Task 1: Understand EFA Architecture (15 min)

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
│  P5 instances: 32x EFA interfaces (3200 Gbps total)             │
└─────────────────────────────────────────────────────────────────┘
```

**P4d.24xlarge EFA Configuration:**
- 4x EFA interfaces (100 Gbps each = 400 Gbps total)
- Each EFA interface attached to a different subnet
- Requires placement group for lowest latency

**P5.48xlarge EFA Configuration:**
- 32x EFA interfaces (100 Gbps each = 3200 Gbps total)
- 8x H100 GPUs with NVSwitch
- State-of-the-art for AWS ML training

### Task 2: Verify EFA Prerequisites (20 min)

1. **Check Instance Type and EFA Interfaces**

   SSH into your GPU node:
   ```bash
   # Verify instance metadata
   curl -s http://169.254.169.254/latest/meta-data/instance-type
   # Expected: p4d.24xlarge or p5.48xlarge

   # List network interfaces
   ip link show
   # Look for: eth0, eth1, eth2, eth3 (EFA interfaces)

   # Check EFA device
   fi_info -p efa
   # Should show EFA provider information
   ```

2. **Verify Placement Group**
   ```bash
   # Check instance placement
   curl -s http://169.254.169.254/latest/meta-data/placement/group-name
   # Should show your cluster placement group name
   ```

3. **Verify EFA Driver**
   ```bash
   # Check EFA module loaded
   lsmod | grep efa
   # Expected: efa module loaded

   # Check EFA device files
   ls -la /dev/infiniband/
   # Should show uverbs devices
   ```

### Task 3: Install AWS EFA Kubernetes Device Plugin (30 min)

The EFA device plugin exposes EFA interfaces to Kubernetes pods.

1. **Deploy EFA Device Plugin**
   ```yaml
   # Save as efa-device-plugin.yaml
   apiVersion: apps/v1
   kind: DaemonSet
   metadata:
     name: aws-efa-k8s-device-plugin-daemonset
     namespace: kube-system
   spec:
     selector:
       matchLabels:
         name: aws-efa-k8s-device-plugin
     template:
       metadata:
         labels:
           name: aws-efa-k8s-device-plugin
       spec:
         tolerations:
           - key: nvidia.com/gpu
             operator: Exists
             effect: NoSchedule
         hostNetwork: true
         containers:
           - name: aws-efa-k8s-device-plugin
             image: 602401143452.dkr.ecr.us-west-2.amazonaws.com/eks/aws-efa-k8s-device-plugin:v0.5.4
             securityContext:
               allowPrivilegeEscalation: false
               capabilities:
                 drop: ["ALL"]
             volumeMounts:
               - name: device-plugin
                 mountPath: /var/lib/kubelet/device-plugins
         volumes:
           - name: device-plugin
             hostPath:
               path: /var/lib/kubelet/device-plugins
   ```

   ```bash
   kubectl apply -f efa-device-plugin.yaml

   # Verify deployment
   kubectl get daemonset -n kube-system aws-efa-k8s-device-plugin-daemonset
   ```

2. **Verify EFA Resource Available**
   ```bash
   kubectl describe node <gpu-node-name> | grep -A10 Allocatable

   # Expected output should include:
   # vpc.amazonaws.com/efa: 4    (for p4d)
   # vpc.amazonaws.com/efa: 32   (for p5)
   ```

### Task 4: Configure NVIDIA GPU Operator for RDMA (30 min)

1. **Update GPU Operator with RDMA Support**
   ```bash
   helm upgrade gpu-operator nvidia/gpu-operator \
     --namespace gpu-operator \
     --set driver.rdma.enabled=true \
     --set driver.rdma.useHostMofed=false
   ```

2. **Deploy NVIDIA Network Operator**
   ```bash
   helm install network-operator nvidia/network-operator \
     --namespace nvidia-network-operator \
     --create-namespace \
     --set nfd.enabled=false \
     --set ofedDriver.deploy=false \
     --set rdmaSharedDevicePlugin.deploy=true \
     --set secondaryNetwork.deploy=false
   ```

3. **Verify nvidia-peermem Module**

   The `nvidia-peermem` module enables GPUDirect RDMA:

   ```bash
   # Check on each GPU node
   kubectl exec -it <gpu-pod> -- bash
   lsmod | grep nvidia_peermem

   # If not loaded:
   modprobe nvidia-peermem
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
           - name: FI_EFA_USE_DEVICE_RDMA
             value: "1"
           - name: FI_PROVIDER
             value: "efa"
           - name: NCCL_NET_GDR_LEVEL
             value: "5"
           - name: LD_LIBRARY_PATH
             value: "/opt/amazon/efa/lib:$LD_LIBRARY_PATH"
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

   # Inside the pod - run all-reduce performance test
   cd /opt/nccl-tests/build

   # Single-node 8-GPU test
   ./all_reduce_perf -b 1M -e 1G -f 2 -g 8

   # Expected output (example):
   #                                             out-of-place                       in-place
   # size       count      type   redop    time   algbw   busbw  error     time   algbw   busbw  error
   # 1048576    262144     float    sum    0.08   12.47   21.82  0e+00    0.08   12.52   21.91  0e+00
   # 2097152    524288     float    sum    0.09   22.89   40.05  0e+00    0.09   22.95   40.16  0e+00
   # ...
   # 1073741824 268435456  float    sum    2.12  505.89  884.81  0e+00    2.11  508.23  889.40  0e+00
   ```

3. **Interpret NCCL Output**

   | Column | Meaning |
   |--------|---------|
   | size | Message size in bytes |
   | time | Time in milliseconds |
   | algbw | Algorithm bandwidth (GB/s) |
   | busbw | Bus bandwidth (GB/s) - actual NVLink usage |

   **Expected Performance (8x A100 with NVSwitch):**
   - Bus bandwidth: 800-900 GB/s for large messages
   - This confirms NVLink is being used within the node

---

## Part 3: Azure InfiniBand Configuration

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

1. **Verify VM is RDMA-Capable**

   SSH into your Azure GPU node:
   ```bash
   # Check VM size (must have 'r' suffix for RDMA)
   curl -H "Metadata:true" "http://169.254.169.254/metadata/instance/compute/vmSize?api-version=2021-02-01&format=text"
   # Expected: Standard_ND96isr_H100_v5 (note the 'r')
   ```

2. **Verify InfiniBand Hardware**
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
   #     Base lid: 123
   #     SM lid: 1

   # Check all InfiniBand devices
   ibv_devinfo
   ```

3. **Verify InfiniBand Network Connectivity**
   ```bash
   # Show InfiniBand ports and status
   ibstatus

   # Check InfiniBand fabric topology (shows connected nodes)
   iblinkinfo
   ```

### Task 8: Configure k0s with InfiniBand on Azure (45 min)

This task demonstrates k0rdent's capability to manage k0s clusters on Azure with InfiniBand.

1. **Review VMSS Configuration**

   Your Terraform should have configured:
   ```hcl
   resource "azurerm_orchestrated_virtual_machine_scale_set" "k0s_gpu" {
     # ...

     # CRITICAL for InfiniBand connectivity
     single_placement_group      = true
     platform_fault_domain_count = 1

     # InfiniBand driver extension
     extension {
       name                 = "InfiniBandDriverLinux"
       publisher            = "Microsoft.HpcCompute"
       type                 = "InfiniBandDriverLinux"
       type_handler_version = "1.2"
     }
   }
   ```

2. **Verify InfiniBand Driver Installation**
   ```bash
   # Check MOFED (Mellanox OpenFabrics Enterprise Distribution) version
   ofed_info -s
   # Expected: MLNX_OFED_LINUX-5.x.x.x

   # Verify IB modules loaded
   lsmod | grep mlx5
   # Should show: mlx5_core, mlx5_ib
   ```

3. **Install NVIDIA Network Operator for InfiniBand**
   ```bash
   helm install network-operator nvidia/network-operator \
     --namespace nvidia-network-operator \
     --create-namespace \
     --set nfd.enabled=false \
     --set ofedDriver.deploy=false \
     --set rdmaSharedDevicePlugin.deploy=true \
     --set rdmaSharedDevicePlugin.resources[0].name=rdma_shared_device_ib \
     --set rdmaSharedDevicePlugin.resources[0].rdmaHcaMax=8 \
     --set sriovDevicePlugin.deploy=false \
     --set secondaryNetwork.deploy=false \
     --set ibKubernetes.deploy=true
   ```

4. **Verify InfiniBand Resources in Kubernetes**
   ```bash
   kubectl describe node <gpu-node> | grep -A15 Allocatable

   # Expected:
   # nvidia.com/gpu:                8
   # rdma/rdma_shared_device_ib:    8
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
             value: "5"
           - name: NCCL_IB_HCA
             value: "mlx5"
           - name: NCCL_IB_GID_INDEX
             value: "3"
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

   ```bash
   kubectl apply -f nccl-test-ib.yaml
   kubectl wait --for=condition=Ready pod/nccl-test-ib --timeout=300s
   ```

2. **Run InfiniBand Bandwidth Test**
   ```bash
   kubectl exec -it nccl-test-ib -- bash

   # Test InfiniBand bandwidth to another node
   # On node 1:
   ib_write_bw --all --report_gbits

   # On node 2 (separate terminal):
   ib_write_bw --all --report_gbits <node1-ib-ip>

   # Expected: ~400 Gb/s per port
   ```

3. **Run NCCL All-Reduce Test**
   ```bash
   cd /opt/nccl-tests/build

   ./all_reduce_perf -b 1M -e 1G -f 2 -g 8

   # Check NCCL debug output for:
   # "NCCL INFO NET/IB : Using [0]mlx5_0:1/IB"
   # This confirms InfiniBand is being used
   ```

---

## Part 4: Multi-Cloud Performance Comparison

### Task 10: Benchmark Comparison (30 min)

Create identical benchmarks on both platforms to compare performance:

1. **Create Benchmark Script**
   ```bash
   # Save as benchmark-rdma.sh
   #!/bin/bash

   echo "=== RDMA Benchmark Results ==="
   echo "Platform: $(hostname)"
   echo "Date: $(date)"
   echo ""

   # GPU Topology
   echo "=== GPU Topology ==="
   nvidia-smi topo -m
   echo ""

   # NCCL All-Reduce (varying sizes)
   echo "=== NCCL All-Reduce Benchmark ==="
   cd /opt/nccl-tests/build
   ./all_reduce_perf -b 1M -e 4G -f 2 -g 8 -n 100 -w 10
   echo ""

   # Record key metrics
   echo "=== Summary Metrics ==="
   echo "Peak Bus Bandwidth (1GB message): $(./all_reduce_perf -b 1G -e 1G -g 8 -n 10 | tail -2 | head -1 | awk '{print $7}') GB/s"
   ```

2. **Run on Both Platforms**

   | Test | AWS EFA (P4d) | Azure IB (ND A100 v4) | Notes |
   |------|---------------|----------------------|-------|
   | Single-node all-reduce (8 GPU) | ~880 GB/s | ~880 GB/s | NVLink-limited, equal |
   | Cross-node all-reduce (16 GPU) | ~350 GB/s | ~380 GB/s | IB slightly faster |
   | Latency (small message) | ~5 us | ~2 us | IB lower latency |
   | GPUDirect efficiency | 90%+ | 95%+ | IB more efficient |

3. **Document Results**

   Create a comparison table for your deployment:

   ```markdown
   ## RDMA Performance Comparison

   | Metric | AWS EFA | Azure InfiniBand | Winner |
   |--------|---------|------------------|--------|
   | Single-node bandwidth | ___GB/s | ___GB/s | ___ |
   | Multi-node bandwidth | ___GB/s | ___GB/s | ___ |
   | Small message latency | ___us | ___us | ___ |
   | GPUDirect utilization | ___% | ___% | ___ |
   ```

---

## Part 5: k0rdent Multi-Cloud Deployment

### Task 11: Demonstrate k0rdent Portability (20 min)

This task demonstrates how the same vLLM workload runs identically on both platforms.

1. **Create Platform-Agnostic vLLM Deployment**
   ```yaml
   # Save as vllm-multi-cloud.yaml
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
             image: vllm/vllm-openai:latest
             args:
               - --model
               - meta-llama/Llama-2-70b-chat-hf
               - --tensor-parallel-size
               - "8"
               - --max-model-len
               - "4096"
             env:
               # Platform-agnostic NCCL configuration
               - name: NCCL_DEBUG
                 value: "INFO"
               # Let NCCL auto-detect best transport
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

2. **Deploy on Both Platforms**
   ```bash
   # AWS cluster
   kubectl config use-context k0rdent-aws-gpu
   kubectl apply -f vllm-multi-cloud.yaml

   # Azure cluster
   kubectl config use-context k0rdent-azure-gpu
   kubectl apply -f vllm-multi-cloud.yaml
   ```

3. **Compare Inference Performance**
   ```bash
   # Run identical benchmark on both
   curl -X POST http://<service-ip>:8000/v1/completions \
     -H "Content-Type: application/json" \
     -d '{
       "model": "meta-llama/Llama-2-70b-chat-hf",
       "prompt": "Explain the concept of RDMA in simple terms.",
       "max_tokens": 200
     }' | jq '.usage.total_time'
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
  NCCL_DEBUG: "INFO"           # Enable debugging
  NCCL_P2P_LEVEL: "NVL"        # Use NVLink for P2P
  NCCL_NET_GDR_LEVEL: "5"      # Enable GPUDirect RDMA

  # ===== AWS EFA Specific =====
  # FI_EFA_USE_DEVICE_RDMA: "1"  # Enable EFA RDMA
  # FI_PROVIDER: "efa"           # Use EFA provider
  # AWS_EFA_VERSION: "1.30.0"    # EFA version

  # ===== Azure InfiniBand Specific =====
  # NCCL_IB_DISABLE: "0"         # Enable InfiniBand
  # NCCL_IB_HCA: "mlx5"          # Use Mellanox HCA
  # NCCL_IB_GID_INDEX: "3"       # RoCE v2 GID index
```

---

## Deliverables

### Basic Deliverables (Either Platform)
- [ ] EFA/InfiniBand driver verified and working
- [ ] NCCL test showing 800+ GB/s intra-node bandwidth
- [ ] GPU Operator configured with RDMA enabled
- [ ] Network Operator deployed and functioning
- [ ] NCCL debug output showing correct transport (EFA or IB)

### Advanced Deliverables (Both Platforms)
- [ ] Side-by-side performance comparison table
- [ ] vLLM deployment running on both platforms
- [ ] Documentation of NCCL configuration differences
- [ ] Multi-node all-reduce benchmark results
- [ ] Platform selection recommendations for different workloads

---

## Verification Checklist

### AWS EFA
- [ ] `fi_info -p efa` shows EFA provider
- [ ] `vpc.amazonaws.com/efa` resource available in Kubernetes
- [ ] NCCL logs show `NET/AWS-EFA` transport
- [ ] All-reduce bandwidth > 800 GB/s (8 GPUs)

### Azure InfiniBand
- [ ] `ibstat` shows Active state
- [ ] `rdma/rdma_shared_device_ib` resource available
- [ ] NCCL logs show `NET/IB` transport
- [ ] All-reduce bandwidth > 800 GB/s (8 GPUs)

### k0rdent Multi-Cloud
- [ ] Same workload YAML deploys on both platforms
- [ ] Performance within 10% between platforms (single-node)
- [ ] NCCL auto-detects correct transport on each platform

---

## Troubleshooting

### EFA Not Detected (AWS)

```bash
# Check EFA driver
lsmod | grep efa
# If missing, install:
sudo yum install -y efa

# Check security group allows EFA traffic
aws ec2 describe-security-groups --group-ids <sg-id>
# Must allow all traffic within security group
```

### InfiniBand Port Down (Azure)

```bash
# Check InfiniBand status
ibstat
# If "Physical state: Polling", check:

# 1. VMSS single_placement_group must be true
# 2. All VMs must be in same VMSS
# 3. InfiniBand driver extension installed:
az vmss extension list --resource-group <rg> --vmss-name <vmss>
```

### NCCL Falls Back to TCP

```bash
# Check NCCL debug output for:
# "NCCL INFO NET/Socket" - indicates TCP fallback

# For EFA:
export FI_EFA_USE_DEVICE_RDMA=1
export FI_PROVIDER=efa

# For InfiniBand:
export NCCL_IB_DISABLE=0
export NCCL_IB_HCA=mlx5
```

### GPUDirect RDMA Not Working

```bash
# Verify nvidia-peermem module
lsmod | grep nvidia_peermem

# If missing:
modprobe nvidia-peermem

# Verify GPUDirect is used
export NCCL_NET_GDR_LEVEL=5
# Run NCCL test and look for "GDR" in debug output
```

---

## Key Takeaways

### Technology Comparison

| Aspect | AWS EFA | Azure InfiniBand | Recommendation |
|--------|---------|------------------|----------------|
| **Performance** | Excellent | Excellent | Tie |
| **Standards** | Proprietary | Industry Standard | Azure for skill transfer |
| **Setup Complexity** | Medium | Medium-High | AWS slightly easier |
| **On-Prem Equivalent** | None | NVIDIA DGX | Azure for hybrid |
| **Cost** | Similar | Similar | Check spot pricing |
| **Terraform** | Excellent | Good | AWS more mature |

### When to Use Each Platform

**Choose AWS EFA when:**
- Already invested in AWS ecosystem
- Need simpler Terraform automation
- Cloud-only deployment (no on-prem)
- Cost optimization is priority (spot pricing)

**Choose Azure InfiniBand when:**
- Need industry-standard RDMA skills
- Planning hybrid cloud/on-prem deployment
- Already using Azure services
- Want same technology as NVIDIA DGX

### k0rdent Multi-Cloud Value

This lab demonstrates k0rdent's core value proposition:
- **Same workloads** run on AWS or Azure
- **No vendor lock-in** - switch clouds as needed
- **Consistent experience** - same kubectl commands
- **Infrastructure flexibility** - best tool for each job

---

## References

### AWS
- [AWS EFA Documentation](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/efa.html)
- [EFA Kubernetes Device Plugin](https://github.com/aws/aws-efa-k8s-device-plugin)
- [AWS EFA Best Practices](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/efa-working-with.html)

### Azure
- [Azure InfiniBand Setup](https://learn.microsoft.com/en-us/azure/virtual-machines/setup-infiniband)
- [ND H100 v5 Series](https://learn.microsoft.com/en-us/azure/virtual-machines/sizes/gpu-accelerated/ndh100v5-series)
- [Azure HPC/AI with InfiniBand](https://techcommunity.microsoft.com/blog/azurehighperformancecomputingblog/running-tightly-coupled-hpcai-workloads-with-infiniband-using-nvidia-network-ope/4117209)

### NVIDIA
- [NCCL Environment Variables](https://docs.nvidia.com/deeplearning/nccl/user-guide/docs/env.html)
- [GPUDirect RDMA](https://docs.nvidia.com/cuda/gpudirect-rdma/index.html)
- [Network Operator](https://docs.nvidia.com/networking/display/cokan10/network+operator)

### k0rdent
- [k0s Project](https://k0sproject.io/)
- [k0rdent Documentation](https://docs.k0rdent.io/)

---

## Next Lab

Proceed to [Lab 5.15 - Multi-Node Distributed Training](lab-5.15-distributed-training.md)
