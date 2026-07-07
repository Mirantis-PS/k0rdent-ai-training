# Lab 3.3 - Create AI VM with 8-GPU Passthrough

**Duration:** 2.5 hours
**Type:** Hands-on Technical
**Environment:** GPU Lab (P4d.24xlarge or equivalent)

## Objective

Create a production-ready AI virtual machine with all 8 GPUs passed through, proper NUMA alignment, and verified NVLink connectivity.

## Prerequisites

- Completed Lab 3.1 (KubeVirt deployed)
- Completed Lab 3.2 (GPU Passthrough configured)
- GPU Lab environment provisioned
- IOMMU and VFIO already configured on host

## Lab Environment

**Cloud Instance:** AWS P4d.24xlarge
- 8x NVIDIA A100 40GB GPUs
- 96 vCPUs (2 sockets)
- 1152 GB RAM
- NVLink interconnect between all GPUs

**Pre-installed:**
- k0rdent management
- KubeVirt v1.6.3 operator
- GPU Operator v25.10.0
- NVIDIA drivers 570.x on host

## Tasks

### Task 1: Verify GPU Resources (15 min)

1. **Check Available GPU Resources**
   ```bash
   # View GPUs on node
   kubectl get nodes -o json | jq '.items[].status.allocatable | with_entries(select(.key | startswith("nvidia")))'

   # Expected output:
   # "nvidia.com/gpu": "8"
   ```

2. **Verify VFIO Binding**
   ```bash
   # SSH to worker node
   ssh worker-node-1

   # Check VFIO bindings
   ls -la /sys/bus/pci/drivers/vfio-pci/

   # Verify GPUs bound to VFIO
   lspci -nnk -d 10de: | grep -A2 "3D controller"
   ```

3. **Check IOMMU Groups**
   ```bash
   for d in /sys/kernel/iommu_groups/*/devices/*; do
     n=$(basename $(dirname $(dirname $d)))
     echo "Group $n: $(lspci -nns ${d##*/})"
   done | grep -i nvidia
   ```

### Task 2: Examine Host NUMA Topology (20 min)

1. **View NUMA Configuration**
   ```bash
   numactl --hardware

   # Expected output showing 2 NUMA nodes:
   # node 0 cpus: 0-47
   # node 1 cpus: 48-95
   # node 0 size: 576000 MB
   # node 1 size: 576000 MB
   ```

2. **Map GPUs to NUMA Nodes**
   ```bash
   for gpu in /sys/bus/pci/devices/*/numa_node; do
     pci=$(dirname $gpu)
     pci_addr=$(basename $pci)
     numa=$(cat $gpu)
     name=$(lspci -s $pci_addr | cut -d: -f3-)
     echo "PCI $pci_addr (NUMA $numa): $name"
   done | grep -i nvidia
   ```

3. **Document Topology**
   Create a diagram showing which GPUs are on which NUMA node:
   ```
   NUMA Node 0              NUMA Node 1
   ├── GPU 0                ├── GPU 4
   ├── GPU 1                ├── GPU 5
   ├── GPU 2                ├── GPU 6
   └── GPU 3                └── GPU 7
   ```

### Task 3: Create VirtualMachine CR (45 min)

1. **Create Namespace**
   ```bash
   kubectl create namespace ai-workloads
   ```

2. **Create VM Secret for SSH Key**
   ```bash
   # Generate SSH key if needed
   ssh-keygen -t ed25519 -f ai-vm-key -N ""

   # Create secret
   kubectl create secret generic ai-vm-ssh-key \
     --from-file=key=ai-vm-key.pub \
     -n ai-workloads
   ```

3. **Create Cloud-Init ConfigMap**
   ```bash
   cat <<EOF | kubectl apply -f -
   apiVersion: v1
   kind: ConfigMap
   metadata:
     name: ai-vm-cloudinit
     namespace: ai-workloads
   data:
     userdata: |
       #cloud-config
       users:
         - name: aiuser
           sudo: ALL=(ALL) NOPASSWD:ALL
           ssh_authorized_keys:
             - $(cat ai-vm-key.pub)
       packages:
         - nvidia-driver-570
         - nvidia-cuda-toolkit
       runcmd:
         - nvidia-smi
   EOF
   ```

4. **Create VirtualMachine with 8 GPUs**
   ```yaml
   # Save as ai-vm-8gpu.yaml
   apiVersion: kubevirt.io/v1
   kind: VirtualMachine
   metadata:
     name: ai-workstation-8gpu
     namespace: ai-workloads
   spec:
     running: true
     template:
       metadata:
         labels:
           kubevirt.io/vm: ai-workstation-8gpu
       spec:
         nodeSelector:
           nvidia.com/gpu.count: "8"
         domain:
           cpu:
             cores: 48
             sockets: 2
             threads: 1
             dedicatedCpuPlacement: true
             isolateEmulatorThread: true
             numa:
               guestMappingPassthrough: {}
           memory:
             guest: 512Gi
             hugepages:
               pageSize: 1Gi
           devices:
             disks:
               - name: rootdisk
                 disk:
                   bus: virtio
               - name: cloudinitdisk
                 disk:
                   bus: virtio
             gpus:
               - deviceName: nvidia.com/GA100_A100_PCIE_40GB
                 name: gpu0
               - deviceName: nvidia.com/GA100_A100_PCIE_40GB
                 name: gpu1
               - deviceName: nvidia.com/GA100_A100_PCIE_40GB
                 name: gpu2
               - deviceName: nvidia.com/GA100_A100_PCIE_40GB
                 name: gpu3
               - deviceName: nvidia.com/GA100_A100_PCIE_40GB
                 name: gpu4
               - deviceName: nvidia.com/GA100_A100_PCIE_40GB
                 name: gpu5
               - deviceName: nvidia.com/GA100_A100_PCIE_40GB
                 name: gpu6
               - deviceName: nvidia.com/GA100_A100_PCIE_40GB
                 name: gpu7
             interfaces:
               - name: default
                 masquerade: {}
           resources:
             requests:
               memory: 512Gi
         networks:
           - name: default
             pod: {}
         volumes:
           - name: rootdisk
             containerDisk:
               image: quay.io/containerdisks/ubuntu:22.04
           - name: cloudinitdisk
             cloudInitNoCloud:
               userDataConfigMap:
                 name: ai-vm-cloudinit
   ```

5. **Apply and Monitor**
   ```bash
   kubectl apply -f ai-vm-8gpu.yaml

   # Watch VM status
   kubectl get vms -n ai-workloads -w

   # Check VMI (running instance)
   kubectl get vmi -n ai-workloads
   ```

### Task 4: Access and Verify VM (30 min)

1. **Get VM Console Access**
   ```bash
   # Install virtctl if not present (use KubeVirt v1.6.3)
   # curl -L -o virtctl https://github.com/kubevirt/kubevirt/releases/download/v1.6.3/virtctl-v1.6.3-linux-amd64
   # chmod +x virtctl

   # Console access
   virtctl console ai-workstation-8gpu -n ai-workloads
   ```

2. **SSH Access**
   ```bash
   # Get VM IP
   kubectl get vmi ai-workstation-8gpu -n ai-workloads -o jsonpath='{.status.interfaces[0].ipAddress}'

   # SSH via virtctl
   virtctl ssh aiuser@ai-workstation-8gpu -n ai-workloads -i ai-vm-key
   ```

3. **Verify GPU Visibility**
   ```bash
   # Inside VM
   nvidia-smi

   # Expected: 8 GPUs listed
   # +-----------------------------------------------------------------------------+
   # | NVIDIA-SMI 570.xxx    Driver Version: 570.xxx    CUDA Version: 12.6        |
   # |-------------------------------+----------------------+----------------------+
   # | GPU  Name        Persistence-M| Bus-Id        Disp.A | Volatile Uncorr. ECC |
   # | Fan  Temp  Perf  Pwr:Usage/Cap|         Memory-Usage | GPU-Util  Compute M. |
   # |===============================+======================+======================|
   # |   0  NVIDIA A100-SXM...  On   | 00000000:00:06.0 Off |                    0 |
   # ... (8 GPUs total)
   ```

### Task 5: Verify NVLink Topology (30 min)

1. **Check NVLink Topology Matrix**
   ```bash
   # Inside VM
   nvidia-smi topo -m

   # Expected output showing NVLink connections:
   #         GPU0 GPU1 GPU2 GPU3 GPU4 GPU5 GPU6 GPU7
   # GPU0     X   NV4  NV4  NV4  NV4  NV4  NV4  NV4
   # GPU1    NV4   X   NV4  NV4  NV4  NV4  NV4  NV4
   # ...
   ```

2. **Check NVLink Status**
   ```bash
   # Get NVLink information for GPU 0
   nvidia-smi nvlink -s -i 0

   # Check all GPUs
   for i in {0..7}; do
     echo "=== GPU $i NVLink Status ==="
     nvidia-smi nvlink -s -i $i
   done
   ```

3. **Verify NVLink Bandwidth**
   ```bash
   # Run NVIDIA bandwidth test
   # First, install CUDA samples
   git clone https://github.com/NVIDIA/cuda-samples.git
   cd cuda-samples/Samples/5_Domain_Specific/p2pBandwidthLatencyTest
   make

   # Run test
   ./p2pBandwidthLatencyTest
   ```

### Task 6: Test Multi-GPU Performance (20 min)

1. **Run NCCL All-Reduce Test**
   ```bash
   # Install NCCL tests
   git clone https://github.com/NVIDIA/nccl-tests.git
   cd nccl-tests
   make MPI=1

   # Run all-reduce across 8 GPUs
   ./build/all_reduce_perf -b 8 -e 256M -f 2 -g 8

   # Expected: High bandwidth (>200 GB/s) via NVLink
   ```

2. **Verify GPU Memory**
   ```bash
   nvidia-smi --query-gpu=memory.total,memory.free --format=csv

   # Expected: ~40GB per GPU (A100 40GB)
   ```

3. **Run Simple PyTorch Test**
   ```bash
   # Install PyTorch
   pip install torch

   # Test multi-GPU
   python3 << 'EOF'
   import torch

   print(f"CUDA available: {torch.cuda.is_available()}")
   print(f"GPU count: {torch.cuda.device_count()}")

   for i in range(torch.cuda.device_count()):
       print(f"GPU {i}: {torch.cuda.get_device_name(i)}")

   # Test tensor on each GPU
   for i in range(torch.cuda.device_count()):
       x = torch.randn(1000, 1000, device=f'cuda:{i}')
       print(f"GPU {i}: Tensor allocated successfully")
   EOF
   ```

## Deliverables

- [ ] **Screenshot** of `nvidia-smi` showing all 8 GPUs
- [ ] **Output** of `nvidia-smi topo -m` showing NVLink topology matrix
- [ ] **NCCL test results** showing multi-GPU bandwidth
- [ ] **PyTorch verification** output
- [ ] **VirtualMachine YAML** with annotations explaining key configurations

## Verification Checklist

- [ ] VM created and running
- [ ] All 8 GPUs visible inside VM
- [ ] NUMA topology correctly passed through
- [ ] NVLink connections active between GPUs
- [ ] P2P bandwidth test shows high throughput
- [ ] Can allocate tensors on all GPUs

## Troubleshooting

### VM Fails to Start

**Check Events:**
```bash
kubectl describe vmi ai-workstation-8gpu -n ai-workloads
```

**Common Issues:**
- Not enough GPU resources: Check `kubectl describe node` for allocatable GPUs
- IOMMU group conflicts: Verify all GPUs in separate IOMMU groups
- Memory not available: Ensure hugepages configured

### GPUs Not Visible in VM

**Verify VFIO Binding:**
```bash
# On host
lspci -nnk -d 10de: | grep -A3 "NVIDIA"
# Should show "Kernel driver in use: vfio-pci"
```

**Check KubeVirt Configuration:**
```bash
kubectl get kubevirt -n kubevirt -o yaml | grep -A20 permittedDevices
```

### NVLink Not Working

**Check Fabric Manager:**
```bash
# On host
systemctl status nvidia-fabricmanager
journalctl -u nvidia-fabricmanager -n 50
```

**Verify NVSwitch:**
```bash
nvidia-smi nvlink -s
# Should show "Link State: Active"
```

### NUMA Misalignment

**Verify Host NUMA:**
```bash
numactl --hardware
```

**Check VM NUMA:**
```bash
# Inside VM
numactl --hardware
lscpu | grep NUMA
```

## Key Takeaways

1. **NUMA alignment is critical** for GPU performance - vCPUs and memory should be on same NUMA node as GPUs
2. **NVLink enables fast GPU-to-GPU communication** - verify it's active with `nvidia-smi topo`
3. **Dedicated CPU placement** prevents CPU contention from affecting GPU workloads
4. **Hugepages** reduce memory overhead and improve performance

## Next Lab

Proceed to Lab 3.4 - SR-IOV Networking (planned)
