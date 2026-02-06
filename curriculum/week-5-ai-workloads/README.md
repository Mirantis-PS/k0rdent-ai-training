# k0rdent AI Infrastructure Engineer Training Curriculum

**Version:** 1.0
**Last Updated:** November 2025
**Owner:** Mirantis AI Training Team

---

## Executive Summary

This curriculum prepares engineers to implement Mirantis k0rdent for customers, enabling them to build AI infrastructure products including Bare Metal as a Service (BMaaS), Virtual Machines as a Service (VMaaS), Kubernetes as a Service (KaaS), and Models as a Service (MaaS).

| Attribute | Value |
|-----------|-------|
| **Target Audience** | Engineers proficient in Kubernetes |
| **Format** | Self-paced online with cloud-based labs |
| **Duration** | 6 weeks (~15 hours/week, ~90 total hours) |
| **Lab Ratio** | 70% hands-on / 30% theory |
| **Cohort Size** | 5-15 engineers |
| **Primary Outcome** | Implement k0rdent for customer deployments |
| **Lab Environment** | On-demand cloud instances (central budget) |
| **Documentation** | Wiki/Confluence pages |

---

## Table of Contents

1. [Program Overview](#1-program-overview)
2. [Week 1: Foundations](#2-week-1-foundations)
3. [Week 2: Bare Metal as a Service](#3-week-2-bare-metal-as-a-service)
4. [Week 3: Virtual Machines as a Service](#4-week-3-virtual-machines-as-a-service)
5. [Week 4: Kubernetes as a Service](#5-week-4-kubernetes-as-a-service)
6. [Week 5: AI Workloads & Service Catalog](#6-week-5-ai-workloads--service-catalog)
7. [Week 6: Multi-Tenancy & Capstone](#7-week-6-multi-tenancy--capstone)
8. [Lab Environment Guide](#8-lab-environment-guide)
9. [Assessment Framework](#9-assessment-framework)
10. [Resources & References](#10-resources--references)

---

## 1. Program Overview

### 1.1 Learning Path

```
Week 1          Week 2          Week 3          Week 4          Week 5          Week 6
┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐
│Foundations│──▶│  BMaaS  │──▶│  VMaaS  │──▶│  KaaS   │──▶│AI Workloads│──▶│Capstone │
│         │    │         │    │         │    │         │    │         │    │         │
│• k0rdent│    │• Metal3 │    │• KubeVirt│   │• CAPI   │    │• Run:AI │    │• Tenancy│
│• GPU HW │    │• Ironic │    │• GPU Pass│   │• GPU Op │    │• vLLM   │    │• RBAC   │
│• BMC    │    │• Provisi│    │• NVLink │    │• CNI/CSI│    │• Catalog│    │• Audit  │
└─────────┘    └─────────┘    └─────────┘    └─────────┘    └─────────┘    └─────────┘
     │              │              │              │              │              │
     └──────────────┴──────────────┴──────────────┴──────────────┴──────────────┘
                              Metal-to-Model Journey
```

### 1.2 Prerequisites

Engineers should have:
- 2+ years Kubernetes experience (deployments, services, storage, networking)
- Familiarity with Linux system administration
- Basic understanding of virtualization concepts
- Experience with Infrastructure as Code (Terraform >= 1.8.0, Helm)

### 1.2.1 Software Versions

This curriculum is validated against the following component versions:

| Component | Version | Notes |
|-----------|---------|-------|
| k0s | v1.32.4+k0s.0 | Kubernetes 1.32 |
| KubeVirt | v1.6.3 | Aligns with K8s 1.32 |
| NVIDIA GPU Operator | v25.10.0 | Calendar versioning (YY.MM.PP) |
| Cluster API | v1.11 | API v1beta2 |
| Metal3 CAPM3 | v1.8.0 | CNCF Incubating (Aug 2025) |
| Metal3 BMO | v0.8.0 | Baremetal Operator |
| Cilium | v1.18.4 | CNI |
| vLLM | v0.11.2 | LLM inference |
| Terraform | >= 1.8.0 | IaC |

### 1.3 Products Covered

| Product | Week(s) | Description |
|---------|---------|-------------|
| **BMaaS** | 1-2 | Bare Metal Hardware Rental/Utilization |
| **VMaaS** | 3 | Virtual Machine Provisioning |
| **KaaS** | 4 | Bare Metal & Instance-based Kubernetes Clusters |
| **MaaS** | 5 | Models as a Service (Endpoints, API Keys) |
| **AI Tools** | 5-6 | Vector DBs, Notebooks, Gateways, Routers |

---

## 2. Week 1: Foundations

**Duration:** 15 hours
**Focus:** k0rdent architecture, GPU hardware landscape, out-of-band management

### 2.1 Learning Objectives

By the end of this week, engineers will be able to:

- [ ] Describe k0rdent's architecture and the 5 core products it enables
- [ ] Identify NVIDIA GPU platforms (H100, H200, B100, B200, B300, GB200)
- [ ] Explain NVLink generations, NVSwitch topology, and HGX baseboard design
- [ ] Differentiate between Redfish and IPMI protocols
- [ ] Use Redfish API to query BMC endpoints and control server power state
- [ ] Diagnose common BMC registration and connectivity failures

### 2.2 Theory Content (4.5 hours)

#### 2.2.1 k0rdent Architecture Deep Dive (2 hours)

**Topics:**
- k0rdent product positioning and market context
- Distributed Container Management Environment (DCME) architecture
- Control plane components and their interactions
- Provider Console vs Customer Console separation
- API-first design and extensibility model

**Key Concepts:**
- Declarative infrastructure management via Kubernetes CRDs
- Multi-cluster management patterns
- Tenant isolation architecture
- Service catalog and blueprint system

#### 2.2.2 NVIDIA GPU Hardware Landscape (2 hours)

**Topics:**
- GPU architecture evolution (Ampere → Hopper → Blackwell)
- HGX platform specifications:
  - H100/H200: 8 GPUs, NVLink 4.0, 900GB/s bidirectional
  - B100/B200/B300: 8 GPUs, NVLink 5.0, 1.8TB/s bidirectional
- GB200 NVL72 architecture (Grace CPU + Blackwell GPU superchip)
- NVSwitch generations and topology
- Memory hierarchy (HBM3e, unified memory)
- Power and cooling requirements

**Reference Material:**
| Platform | GPUs | NVLink BW | Memory | TDP |
|----------|------|-----------|--------|-----|
| HGX H100 | 8 | 900 GB/s | 80GB HBM3 | 700W |
| HGX H200 | 8 | 900 GB/s | 141GB HBM3e | 700W |
| HGX B200 | 8 | 1.8 TB/s | 192GB HBM3e | 1000W |
| GB200 NVL72 | 72 | 1.8 TB/s | 192GB each | 123.6kW |

#### 2.2.3 Out-of-Band Management (1.5 hours)

**Topics:**
- BMC (Baseboard Management Controller) fundamentals
- IPMI protocol (legacy) vs Redfish (modern)
- Redfish data model and REST API structure
- Authentication and security considerations
- Virtual media for remote OS installation
- PXE boot configuration via Redfish

**Redfish vs IPMI Comparison:**
| Feature | Redfish | IPMI |
|---------|---------|------|
| Protocol | HTTPS/REST | UDP/RCMP |
| Data Format | JSON | Binary |
| Security | TLS, modern auth | Basic auth, vulnerabilities |
| Scalability | Web-scale ready | Limited |
| Automation | Native REST APIs | Requires wrappers |

### 2.3 Lab Exercises (10 hours)

#### Lab 1.1 - Explore k0rdent Sandbox (3 hours)

**Objective:** Familiarize with k0rdent UI and API

**Prerequisites:** Access to k0rdent sandbox environment

**Tasks:**
1. Log into k0rdent Provider Console
2. Explore the dashboard and navigation structure
3. Review pre-configured tenants and their resource allocations
4. Access the API documentation and execute sample queries
5. Explore the Customer Console from a tenant perspective
6. Review audit logs for recent activities

**Deliverables:**
- Screenshot of Provider Console dashboard
- Sample API response from tenant list query
- Notes on UI/UX observations

#### Lab 1.2 - BMC Discovery with Redfish (4 hours)

**Objective:** Register and query bare metal hosts using Redfish API

**Prerequisites:** Lab environment with BMC-enabled hosts (virtual or physical)

**Tasks:**
1. Discover BMC endpoints on the network
2. Authenticate to BMC using Redfish
3. Query system information (`/redfish/v1/Systems/`)
4. Retrieve hardware inventory (CPUs, memory, storage, NICs)
5. Query power state and perform power cycle
6. Configure boot order for network boot
7. Mount virtual media ISO image

**Commands Reference:**
```bash
# Discover Redfish service root
curl -k -u admin:password https://<bmc-ip>/redfish/v1/

# Get system information
curl -k -u admin:password https://<bmc-ip>/redfish/v1/Systems/1

# Power cycle
curl -k -u admin:password -X POST \
  -H "Content-Type: application/json" \
  -d '{"ResetType": "ForceRestart"}' \
  https://<bmc-ip>/redfish/v1/Systems/1/Actions/ComputerSystem.Reset
```

**Deliverables:**
- JSON output of system hardware inventory
- Screenshot showing successful power cycle
- Boot order configuration changes

#### Lab 1.3 - Troubleshooting BMC Connectivity (2.5 hours)

**Objective:** Diagnose and resolve common BMC registration failures

**Prerequisites:** Completed Lab 1.2

**Scenario Exercises:**

**Scenario A: BMC Unreachable**
- Symptoms: Connection timeout to BMC endpoint
- Investigation: Network path, firewall rules, VLAN configuration
- Resolution: Identify and fix network/firewall issue

**Scenario B: Authentication Failure**
- Symptoms: 401 Unauthorized response
- Investigation: Credential validation, account lockout, certificate issues
- Resolution: Reset credentials or fix certificate chain

**Scenario C: Duplicate Host Detection**
- Symptoms: Host registration rejected as duplicate
- Investigation: Identify stable identifiers (serial number, UUID)
- Resolution: Resolve identity conflict

**Scenario D: Redfish/IPMI Fallback**
- Symptoms: Redfish not available on older hardware
- Investigation: Detect available protocols
- Resolution: Configure IPMI fallback

**Deliverables:**
- Troubleshooting decision tree for BMC issues
- Resolution documentation for each scenario

### 2.4 Assessment

**Quiz Topics:**
- k0rdent architecture components
- GPU platform identification
- NVLink/NVSwitch specifications
- Redfish API endpoints and operations
- BMC troubleshooting methodology

**Passing Score:** 80%

---

## 3. Week 2: Bare Metal as a Service

**Duration:** 15 hours
**Focus:** Metal3, Ironic, OS provisioning, disk configuration

### 3.1 Learning Objectives

By the end of this week, engineers will be able to:

- [ ] Deploy Metal3 operator and Ironic components on Kubernetes
- [ ] Create BareMetalHost custom resources with BMC credentials
- [ ] Execute full provisioning flow: Discovered → Provisioning → Installing → First-Boot → Ready
- [ ] Configure deterministic disk targeting in hardware RAID environments
- [ ] Set up software RAID during OS installation
- [ ] Diagnose stuck provisioning states and resolve common issues

### 3.2 Theory Content (3 hours)

#### 3.2.1 Metal3 & Ironic Architecture (2 hours)

**Topics:**
- Metal3 project overview and CNCF Incubating status (August 2025)
- Component architecture:
  - Bare Metal Operator (BMO)
  - Ironic (OpenStack bare metal provisioning)
  - Ironic Python Agent (IPA)
- BareMetalHost CRD specification
- Integration with Cluster API (CAPM3)
- Image management and OS deployment strategies

**Architecture Diagram:**
```
┌─────────────────────────────────────────────────────────────┐
│                   Management Cluster                         │
│                                                             │
│  ┌──────────────────┐    ┌──────────────────┐              │
│  │  Bare Metal      │    │  Cluster API     │              │
│  │  Operator (BMO)  │◄──►│  Provider Metal3 │              │
│  └────────┬─────────┘    └──────────────────┘              │
│           │                                                 │
│           ▼                                                 │
│  ┌──────────────────┐                                      │
│  │     Ironic       │                                      │
│  │  (Provisioning)  │                                      │
│  └────────┬─────────┘                                      │
│           │                                                 │
└───────────┼─────────────────────────────────────────────────┘
            │ BMC API (Redfish/IPMI)
            ▼
┌─────────────────────────────────────────────────────────────┐
│                    Bare Metal Host                          │
│                                                             │
│  ┌──────────────────┐                                      │
│  │  Ironic Python   │  ◄── Runs during provisioning        │
│  │  Agent (IPA)     │                                      │
│  └──────────────────┘                                      │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

#### 3.2.2 Provisioning State Machine (1 hour)

**Topics:**
- BareMetalHost state transitions
- Provisioning workflow detailed walkthrough
- Image catalog management
- Cloud-init and ignition for first-boot configuration
- Error states and recovery procedures

**State Machine:**
```
                    ┌──────────────┐
                    │  Registering │
                    └──────┬───────┘
                           │
                           ▼
┌──────────────┐    ┌──────────────┐
│   Available  │◄───│  Inspecting  │
└──────┬───────┘    └──────────────┘
       │
       │ Provision requested
       ▼
┌──────────────┐
│ Provisioning │
└──────┬───────┘
       │
       ▼
┌──────────────┐
│  Installing  │
└──────┬───────┘
       │
       ▼
┌──────────────┐
│  First-Boot  │
└──────┬───────┘
       │
       ▼
┌──────────────┐
│    Ready     │
└──────────────┘
```

### 3.3 Lab Exercises (11.5 hours)

#### Lab 2.1 - Metal3 Dev Environment Setup (3 hours)

**Objective:** Deploy a functional Metal3 development environment

**Prerequisites:** VM with nested virtualization enabled (16GB RAM, 8 vCPUs)

**Tasks:**
1. Clone metal3-dev-env repository
2. Configure environment variables for virtual bare metal
3. Run setup scripts to deploy:
   - Management cluster (minikube or kind)
   - Bare Metal Operator
   - Ironic and supporting services
4. Verify all pods are running
5. Access Ironic API and verify connectivity

**Commands:**
```bash
git clone https://github.com/metal3-io/metal3-dev-env.git
cd metal3-dev-env

# Configure for virtual environment
export EPHEMERAL_CLUSTER=minikube
export NUM_NODES=3

# Run setup
make

# Verify deployment
kubectl get pods -n baremetal-operator-system
kubectl get pods -n ironic-system
```

**Deliverables:**
- Screenshot of all Metal3 pods running
- Ironic API response showing conductor status

#### Lab 2.2 - BareMetalHost Registration (2.5 hours)

**Objective:** Register bare metal hosts and inspect hardware

**Prerequisites:** Completed Lab 2.1

**Tasks:**
1. Create BareMetalHost CR for each virtual node
2. Provide BMC credentials as Kubernetes Secret
3. Observe inspection process
4. Review discovered hardware inventory
5. Verify state transition to Available

**BareMetalHost Manifest:**
```yaml
apiVersion: metal3.io/v1alpha1
kind: BareMetalHost
metadata:
  name: node-1
  namespace: metal3
spec:
  online: true
  bootMACAddress: 00:5c:52:31:3a:9c
  bmc:
    address: redfish-virtualmedia://192.168.111.1:8000/redfish/v1/Systems/node-1
    credentialsName: node-1-bmc-secret
    disableCertificateVerification: true
```

**Deliverables:**
- BareMetalHost CR in Available state
- Hardware inventory showing CPU, memory, disk, NIC details

#### Lab 2.3 - OS Provisioning Flow (3 hours)

**Objective:** Provision operating system on bare metal hosts

**Prerequisites:** Completed Lab 2.2

**Tasks:**
1. Create image catalog entry for Ubuntu 22.04
2. Assign provisioning image to BareMetalHost
3. Trigger provisioning
4. Monitor state transitions: Provisioning → Installing → First-Boot → Ready
5. Access provisioned host via SSH
6. Verify OS installation and configuration

**Provisioning Manifest:**
```yaml
apiVersion: metal3.io/v1alpha1
kind: BareMetalHost
metadata:
  name: node-1
  namespace: metal3
spec:
  online: true
  bootMACAddress: 00:5c:52:31:3a:9c
  bmc:
    address: redfish-virtualmedia://192.168.111.1:8000/redfish/v1/Systems/node-1
    credentialsName: node-1-bmc-secret
  image:
    url: http://192.168.111.1/images/ubuntu-22.04.qcow2
    checksum: http://192.168.111.1/images/ubuntu-22.04.qcow2.md5sum
    checksumType: md5
    format: qcow2
  userData:
    name: node-1-user-data
    namespace: metal3
```

**Deliverables:**
- Timeline of state transitions with timestamps
- SSH session showing OS version and network configuration

#### Lab 2.4 - Disk Configuration (2 hours)

**Objective:** Configure deterministic disk targeting and RAID

**Prerequisites:** Completed Lab 2.3

**Tasks:**
1. Identify disk devices on multi-disk host
2. Configure root device hints for deterministic selection
3. Set up software RAID (RAID1) for OS installation
4. Test with hardware RAID controller present
5. Verify disk layout after provisioning

**Root Device Hints:**
```yaml
spec:
  rootDeviceHints:
    deviceName: /dev/sda
    # OR
    minSizeGigabytes: 100
    # OR
    wwn: "0x50014ee265e8d0b0"
    # OR
    rotational: false  # Select SSD
```

**Deliverables:**
- Disk configuration showing RAID setup
- lsblk output from provisioned host

#### Lab 2.5 - Troubleshooting Provisioning (2.5 hours)

**Objective:** Diagnose and resolve common provisioning failures

**Prerequisites:** Completed Labs 2.1-2.4

**Scenario Exercises:**

**Scenario A: Stuck in Provisioning State**
- Symptoms: Host doesn't progress past Provisioning
- Investigation: Check Ironic conductor logs, IPA logs, network boot
- Resolution: Fix DHCP/TFTP issues or image URL

**Scenario B: Network Boot Failure**
- Symptoms: Host powers on but doesn't PXE boot
- Investigation: Boot order, network configuration, DHCP scope
- Resolution: Configure BMC boot order, verify DHCP

**Scenario C: Disk Detection Failure**
- Symptoms: IPA cannot find target disk
- Investigation: Hardware RAID controller hiding disks, root device hints
- Resolution: Configure RAID controller or adjust hints

**Scenario D: First-Boot Cloud-Init Failure**
- Symptoms: OS installed but configuration incomplete
- Investigation: Cloud-init logs, user-data syntax
- Resolution: Fix user-data or network-data

**Deliverables:**
- Troubleshooting runbook for each scenario
- Log excerpts showing root cause identification

### 3.4 Assessment

**Quiz Topics:**
- Metal3/Ironic component roles
- BareMetalHost state machine
- Provisioning workflow steps
- Disk configuration options
- Common failure modes and resolutions

**Passing Score:** 80%

---

## 4. Week 3: Virtual Machines as a Service

**Duration:** 15 hours
**Focus:** KubeVirt, GPU passthrough, NUMA topology, NVLink fabric, SR-IOV networking

### 4.1 Learning Objectives

By the end of this week, engineers will be able to:

- [ ] Deploy KubeVirt with GPU Operator integration
- [ ] Configure IOMMU and VFIO for GPU passthrough
- [ ] Create VMs with NUMA-aligned CPU and memory pinning
- [ ] Pass through multiple GPUs with NVLink connectivity preserved
- [ ] Integrate NVIDIA Fabric Manager for NVSwitch topology control
- [ ] Configure SR-IOV networking for ConnectX/BlueField NICs
- [ ] Enable and verify GPUDirect RDMA and Storage paths
- [ ] Enforce device isolation between VMs

### 4.2 Theory Content (4.5 hours)

#### 4.2.1 KubeVirt Architecture (1.5 hours)

**Topics:**
- KubeVirt project overview
- VirtualMachine and VirtualMachineInstance CRDs
- virt-launcher pod architecture
- Integration with Kubernetes networking and storage
- Live migration capabilities and limitations
- KubeVirt operator deployment model

#### 4.2.2 GPU Virtualization Deep Dive (2 hours)

**Topics:**
- GPU virtualization options:
  - Full passthrough (VFIO-PCI)
  - vGPU (time-sliced virtualization)
  - MIG (hardware partitioning)
- IOMMU groups and PCIe topology
- VFIO driver binding process
- vGPU licensing and Fabric Manager requirements
- Performance comparison: passthrough vs vGPU vs MIG

**Comparison Table:**
| Feature | Passthrough | vGPU | MIG |
|---------|-------------|------|-----|
| Performance | 100% | 95-98% | 95-98% |
| GPU Sharing | No | Yes (time-slice) | Yes (partition) |
| Memory Isolation | Hardware | Software | Hardware |
| Migration | No | Yes | Limited |
| Supported GPUs | All | Select models | A100, H100, H200, B200, GB200 |

> **Note:** NVIDIA GPU Operator v25.10.0+ includes new MIG profiles for HGX B200 and HGX GB200.

#### 4.2.3 NUMA and Topology Alignment (1 hour)

**Topics:**
- NUMA architecture in multi-socket servers
- CPU, memory, and PCIe device locality
- vNUMA exposure to guest VMs
- CPU pinning strategies
- GPU-to-NUMA affinity optimization
- PCIe switch topology awareness

### 4.3 Lab Exercises (10 hours)

#### Lab 3.1 - KubeVirt Deployment (2 hours)

**Objective:** Deploy KubeVirt on k0rdent-managed cluster

**Tasks:**
1. Install KubeVirt operator
2. Configure KubeVirt CR with GPU support
3. Verify virt-controller and virt-handler pods
4. Create basic VM without GPU
5. Test VM lifecycle (start, stop, migrate)

#### Lab 3.2 - GPU Passthrough Configuration (3 hours)

**Objective:** Configure host for GPU passthrough

**Tasks:**
1. Verify IOMMU enabled in BIOS and kernel
2. Identify IOMMU groups for GPUs
3. Bind GPUs to VFIO-PCI driver
4. Configure KubeVirt permitted devices
5. Verify GPU available for passthrough

**Host Configuration:**
```bash
# Verify IOMMU enabled
dmesg | grep -i iommu

# Check IOMMU groups
for d in /sys/kernel/iommu_groups/*/devices/*; do
  n=$(basename $(dirname $(dirname $d)))
  echo "IOMMU Group $n: $(lspci -nns ${d##*/})"
done

# Bind GPU to VFIO
echo "10de 2330" > /sys/bus/pci/drivers/vfio-pci/new_id
```

#### Lab 3.3 - AI VM with 8-GPU Passthrough (2.5 hours)

**Objective:** Create production-ready AI VM with full GPU complement

**Tasks:**
1. Create VirtualMachine CR with 8 GPUs
2. Configure NUMA-aligned vCPU placement
3. Enable hugepages for memory
4. Verify NVLink topology inside VM
5. Run GPU benchmark

**VM Manifest Example:**
```yaml
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: ai-workstation
spec:
  running: true
  template:
    spec:
      domain:
        cpu:
          cores: 48
          sockets: 2
          threads: 1
          dedicatedCpuPlacement: true
          numa:
            guestMappingPassthrough: {}
        memory:
          guest: 512Gi
          hugepages:
            pageSize: 1Gi
        devices:
          gpus:
            - deviceName: nvidia.com/GA100_A100_PCIE_40GB
              name: gpu0
            # Repeat for gpu1-gpu7
```

**Verification:**
```bash
# Inside VM
nvidia-smi topo -m  # Verify NVLink topology
nvidia-smi nvlink -s  # NVLink status
```

#### Lab 3.4 - SR-IOV Networking (2 hours)

**Objective:** Configure high-performance networking with SR-IOV

**Tasks:**
1. Enable SR-IOV on ConnectX NIC
2. Create Virtual Functions
3. Configure SR-IOV network attachment definition
4. Attach VF to VM
5. Verify RDMA capability in VM

**SR-IOV Configuration:**
```yaml
apiVersion: sriovnetwork.openshift.io/v1
kind: SriovNetworkNodePolicy
metadata:
  name: mlnx-sriov
  namespace: sriov-network-operator
spec:
  nodeSelector:
    feature.node.kubernetes.io/network-sriov.capable: "true"
  resourceName: mlnx_sriov
  numVfs: 8
  nicSelector:
    vendor: "15b3"
    deviceID: "101d"
```

#### Lab 3.5 - Troubleshooting GPU Isolation (2.5 hours)

**Objective:** Diagnose and resolve GPU passthrough issues

**Scenario Exercises:**

**Scenario A: IOMMU Group Conflicts**
- GPUs in same IOMMU group as other devices
- Resolution: ACS override or hardware reconfiguration

**Scenario B: NUMA Misalignment**
- VM performance degradation
- Resolution: Verify and fix CPU/memory/GPU affinity

**Scenario C: NVLink Not Working**
- nvidia-smi shows GPUs but no NVLink
- Resolution: Check Fabric Manager, verify topology

**Scenario D: GPUDirect RDMA Failure**
- gdscheck fails
- Resolution: Verify nvidia-peermem, PCIe topology

### 4.4 Assessment

**Quiz Topics:**
- KubeVirt architecture
- GPU passthrough mechanisms
- NUMA topology concepts
- SR-IOV networking
- Troubleshooting methodology

**Passing Score:** 80%

---

## 5. Week 4: Kubernetes as a Service

**Duration:** 15 hours
**Focus:** Cluster API, GPU Operator, hosted control planes, network stack

### 5.1 Learning Objectives

By the end of this week, engineers will be able to:

- [ ] Deploy CAPI management cluster with Metal3 and KubeVirt providers
- [ ] Create, upgrade, and delete workload clusters via templates
- [ ] Manage GPU and CPU node pools with appropriate labels
- [ ] Install and configure NVIDIA GPU Operator with MIG support
- [ ] Deploy curated CNI, CSI, and Ingress controllers with policies
- [ ] Manage hosted control planes
- [ ] Generate tenant-scoped kubeconfig files

### 5.2 Theory Content (3 hours)

#### 5.2.1 Cluster API & CAPI Providers (1.5 hours)

**Topics:**
- Cluster API concepts and CRDs
- Provider architecture (infrastructure, bootstrap, control plane)
- Metal3 provider for bare metal
- KubeVirt provider for VMs
- Cluster templates and ClusterClass
- Upgrade strategies

#### 5.2.2 GPU Operator & Device Plugins (1.5 hours)

**Topics:**
- NVIDIA GPU Operator architecture
- Component stack (driver, toolkit, device plugin, DCGM)
- MIG configuration strategies
- Time-slicing configuration
- GPU Feature Discovery
- ClusterPolicy CRD

### 5.3 Lab Exercises (11.5 hours)

#### Lab 4.1 - Management Cluster Deployment (2.5 hours)

**Objective:** Deploy CAPI management cluster

**Tasks:**
1. Initialize management cluster
2. Install CAPI core components
3. Install Metal3 provider
4. Install KubeVirt provider
5. Verify provider health

#### Lab 4.2 - Workload Clusters on BMaaS (2.5 hours)

**Objective:** Create Kubernetes cluster on bare metal

**Tasks:**
1. Create cluster template for bare metal
2. Deploy control plane nodes
3. Deploy worker nodes with GPU labels
4. Verify cluster health
5. Access cluster via kubeconfig

#### Lab 4.3 - Workload Clusters on VMaaS (2.5 hours)

**Objective:** Create Kubernetes cluster on VMs

**Tasks:**
1. Create cluster template for KubeVirt
2. Deploy control plane VMs
3. Deploy GPU worker VMs
4. Configure GPU passthrough for workers
5. Verify cluster with GPU nodes

#### Lab 4.4 - GPU Operator Installation (2 hours)

**Objective:** Deploy and configure GPU Operator

**Tasks:**
1. Install GPU Operator via Helm
2. Configure ClusterPolicy
3. Enable MIG on supported nodes
4. Configure MIG profiles
5. Verify GPU scheduling

**MIG Configuration:**
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: mig-parted-config
data:
  config.yaml: |
    version: v1
    mig-configs:
      all-1g.10gb:
        - devices: all
          mig-enabled: true
          mig-devices:
            "1g.10gb": 7
```

#### Lab 4.5 - CNI/CSI/Ingress Configuration (2 hours)

**Objective:** Deploy network and storage stack

**Tasks:**
1. Deploy Cilium CNI with network policies
2. Configure CSI driver (local-path or cloud)
3. Deploy NGINX Ingress controller
4. Create sample network policies
5. Test east-west and north-south traffic

#### Lab 4.6 - Troubleshooting Cluster Bootstrap (2 hours)

**Objective:** Diagnose cluster provisioning failures

**Scenarios:**
- Control plane certificate issues
- Node join failures
- GPU Operator CrashLoopBackOff
- CNI pod network issues

### 5.4 Assessment

**Quiz Topics:**
- CAPI architecture
- Provider types and functions
- GPU Operator configuration
- MIG strategies
- Network policy basics

**Passing Score:** 80%

---

## 6. Week 5: AI Workloads & Service Catalog

**Duration:** 21 hours
**Focus:** GPU scheduling, model serving, ML platforms, AI tools, service catalog

### 6.1 Learning Objectives

By the end of this week, engineers will be able to:

- [ ] Deploy and configure GPU schedulers (Run:AI / KAI)
- [ ] Serve LLM models with vLLM on Kubernetes
- [ ] Deploy AI tools from service catalog (Vector DBs, Jupyter, etc.)
- [ ] Configure automatic Ingress and network policies for services
- [ ] Wire platform-managed secrets and certificates
- [ ] Export resource metrics for metering
- [ ] Configure NVIDIA GPU Operator with FIPS 140-2 compliance
- [ ] Create reusable ClusterClass templates for AI workloads
- [ ] Deploy Kubeflow for ML pipelines and distributed training
- [ ] Set up MLflow for experiment tracking and model registry
- [ ] Configure fractional GPU sharing and gang scheduling
- [ ] Deploy Slurm on Kubernetes for HPC workloads

### 6.2 Theory Content (2.5 hours)

#### 6.2.1 GPU Schedulers (1.5 hours)

**Topics:**
- Kubernetes default scheduler limitations for GPUs
- Run:AI / KAI Scheduler capabilities
- Gang scheduling for distributed training
- Preemption and priority queues
- Fractional GPU allocation
- GPU topology awareness

#### 6.2.2 Model Serving Architecture (1 hour)

**Topics:**
- Inference serving patterns
- vLLM architecture and PagedAttention
- Triton Inference Server overview
- Model gateway and routing patterns
- Scaling strategies for inference

### 6.3 Lab Exercises (18 hours)

#### Lab 5.1 - GPU Scheduler Deployment (3 hours)

**Objective:** Deploy advanced GPU scheduler

**Tasks:**
1. Install KAI Scheduler (or Run:AI)
2. Configure scheduler queues
3. Set up priority classes
4. Test gang scheduling
5. Verify preemption behavior

#### Lab 5.2 - vLLM Inference Service (2.5 hours)

**Objective:** Deploy LLM serving with vLLM

**Tasks:**
1. Deploy vLLM with model (Llama-2-7B or similar)
2. Configure resource requests
3. Set up readiness probes
4. Test inference endpoint
5. Monitor GPU utilization

**vLLM Deployment:**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: vllm-llama2
spec:
  replicas: 1
  template:
    spec:
      containers:
        - name: vllm
          # Pin specific version for production stability
          image: vllm/vllm-openai:v0.11.2
          args:
            - --model
            - meta-llama/Llama-2-7b-chat-hf
            - --tensor-parallel-size
            - "1"
          resources:
            limits:
              nvidia.com/gpu: 1
```

> **Note:** vLLM v0.11+ includes the V1 architecture with 1.7x speedup, zero-overhead prefix caching, and enhanced multimodal support. Always pin specific versions in production deployments.

#### Lab 5.3 - Vector Database Deployment (2 hours)

**Objective:** Deploy production vector database

**Tasks:**
1. Deploy Milvus or Weaviate from catalog
2. Configure persistent storage
3. Set up authentication
4. Load sample embeddings
5. Test similarity search

#### Lab 5.4 - Jupyter Notebook Stack (1.5 hours)

**Objective:** Deploy GPU-enabled Jupyter environment

**Tasks:**
1. Deploy JupyterHub with GPU support
2. Configure user authentication
3. Create GPU-enabled server profiles
4. Test notebook with PyTorch/TensorFlow
5. Configure persistent storage for notebooks

#### Lab 5.5 - Service Catalog Blueprints (2 hours)

**Objective:** Deploy services from catalog

**Tasks:**
1. Browse service catalog
2. Deploy service with default values
3. Customize blueprint inputs
4. Verify automatic Ingress creation
5. Check network policy enforcement
6. Review version pinning options

#### Lab 5.6 - Troubleshooting GPU Scheduling (2 hours)

**Objective:** Diagnose scheduling failures

**Scenarios:**
- Workloads stuck pending (queue full)
- GPU memory fragmentation
- vLLM OOM errors
- Health check failures during upgrade

#### Lab 5.7 - NVIDIA FIPS Configuration (2 hours)

**Objective:** Deploy GPU Operator with FIPS 140-2 compliance

**Tasks:**
1. Verify host FIPS mode enabled
2. Deploy GPU Operator with FIPS configuration
3. Verify FIPS driver installation
4. Configure FIPS-compliant container runtime
5. Test FIPS crypto restrictions
6. Set up DCGM monitoring with FIPS

**Documentation:** [Lab 5.7](labs/lab-5.7-nvidia-fips.md)

#### Lab 5.8 - Cluster Templates for AI Workloads (2 hours)

**Objective:** Create reusable ClusterClass templates for AI infrastructure

**Tasks:**
1. Understand ClusterClass architecture
2. Create AI-optimized ClusterClass templates
3. Configure GPU worker node templates
4. Deploy cluster from template
5. Verify GPU node pools

**Documentation:** [Lab 5.8](labs/lab-5.8-cluster-templates.md)

#### Lab 5.9 - Kubeflow ML Platform (3 hours)

**Objective:** Deploy comprehensive ML platform with Kubeflow

**Tasks:**
1. Prepare cluster for Kubeflow
2. Deploy Kubeflow Pipelines
3. Install KFP SDK and create GPU training pipeline
4. Deploy Training Operator for distributed training
5. Deploy Katib for hyperparameter tuning
6. Configure GPU-enabled notebook servers

**Documentation:** [Lab 5.9](labs/lab-5.9-kubeflow-ml-platform.md)

#### Lab 5.10 - MLflow Experiment Tracking (2.5 hours)

**Objective:** Deploy MLflow for ML lifecycle management

**Tasks:**
1. Deploy MinIO for artifact storage
2. Deploy PostgreSQL for backend store
3. Deploy MLflow Tracking Server
4. Configure client and log experiments
5. Create Kubernetes training job with MLflow integration
6. Register models and deploy for serving

**Documentation:** [Lab 5.10](labs/lab-5.10-mlflow-experiment-tracking.md)

#### Lab 5.11 - Run:AI GPU Orchestration (3 hours)

**Objective:** Deploy advanced GPU orchestration with KAI Scheduler

**Tasks:**
1. Install KAI Scheduler (open-source Run:AI)
2. Configure GPU quotas and projects
3. Configure fractional GPU sharing
4. Implement priority-based scheduling
5. Configure gang scheduling for distributed training
6. Monitor GPU utilization and metrics

**Documentation:** [Lab 5.11](labs/lab-5.11-runai-gpu-orchestration.md)

#### Lab 5.12 - Slurm Operator for HPC (3 hours)

**Objective:** Deploy Slurm on Kubernetes for HPC workloads

**Tasks:**
1. Install Slinky Slurm Operator
2. Configure shared storage
3. Deploy Slurm cluster (slurmctld, slurmdbd, slurmd)
4. Submit and monitor Slurm jobs
5. Configure Slurm accounting
6. Integrate with Kubernetes workloads

**Documentation:** [Lab 5.12](labs/lab-5.12-slurm-operator-hpc.md)

### 6.4 Assessment

**Quiz Topics:**
- GPU scheduler features (KAI, Run:AI, fractional GPUs)
- Gang scheduling and priority preemption
- vLLM deployment and configuration
- Service catalog usage
- FIPS 140-2 compliance requirements
- ClusterClass templates for AI workloads
- Kubeflow components (Pipelines, Training Operator, Katib)
- MLflow tracking and model registry
- Slurm on Kubernetes concepts
- Troubleshooting patterns

**Passing Score:** 80%

---

## 7. Week 6: Multi-Tenancy & Capstone

**Duration:** 15 hours
**Focus:** Tenant isolation, RBAC, identity federation, metering, capstone project

### 7.1 Learning Objectives

By the end of this week, engineers will be able to:

- [ ] Create isolated tenants with configurable states
- [ ] Provision tenant-scoped networks with egress policies
- [ ] Enforce hard resource quotas at tenant level
- [ ] Configure RBAC roles across Provider and Customer consoles
- [ ] Integrate external identity providers via OIDC/SAML
- [ ] Generate usage metrics for billing
- [ ] Produce and verify audit trails
- [ ] Complete end-to-end tenant onboarding (capstone)

### 7.2 Theory Content (2.5 hours)

#### 7.2.1 Multi-Tenant Architecture (1.5 hours)

**Topics:**
- Tenant as primary isolation construct
- Network isolation strategies
- Resource quota enforcement
- Catalog assignment per tenant
- Usage aggregation for billing
- Audit trail requirements

#### 7.2.2 Provider vs Customer Consoles (1 hour)

**Topics:**
- Provider Console capabilities
- Customer Console capabilities
- RBAC model:
  - Provider_Admin
  - Tenant_Admin
  - Tenant_User
- Permission boundaries
- API authentication and authorization

### 7.3 Lab Exercises (9 hours)

#### Lab 6.1 - Tenant Creation & Isolation (2 hours)

**Objective:** Create isolated tenant environment

**Tasks:**
1. Create tenant via Provider Console
2. Configure tenant network space
3. Set egress policies
4. Verify network isolation
5. Test tenant state transitions (Active/Suspended/Disabled)

#### Lab 6.2 - Resource Quotas (2 hours)

**Objective:** Configure and enforce quotas

**Tasks:**
1. Define GPU quotas by type
2. Set vCPU and RAM limits
3. Configure storage quotas
4. Test quota enforcement
5. Review quota utilization reports

#### Lab 6.3 - RBAC Configuration (2 hours)

**Objective:** Set up role-based access control

**Tasks:**
1. Create Provider_Admin users
2. Create Tenant_Admin for specific tenant
3. Create Tenant_Users
4. Test permission boundaries
5. Verify API authorization

#### Lab 6.4 - OIDC/SAML Integration (1.5 hours)

**Objective:** Configure federated identity

**Tasks:**
1. Configure OIDC provider connection
2. Map OIDC claims to roles
3. Test SSO login flow
4. Configure logout handling
5. Test with sample identity provider

#### Lab 6.5 - Metering & Audit Trails (1.5 hours)

**Objective:** Configure usage tracking and auditing

**Tasks:**
1. Review metering data collection
2. Export usage report for tenant
3. Query audit log API
4. Verify audit log immutability
5. Test audit log completeness

### 7.4 Capstone Project (3 hours)

**Objective:** Complete end-to-end tenant onboarding

**Scenario:**
A new customer (TechCorp) needs to be onboarded to k0rdent. They require:
- 4 H100 GPUs quota
- 256 vCPUs, 1TB RAM
- Isolated network with specific egress rules
- Kubernetes cluster for AI workloads
- vLLM deployment for their model
- Integration with their Okta identity provider

**Tasks:**
1. Create TechCorp tenant
2. Configure network and egress
3. Set resource quotas
4. Create Tenant_Admin user
5. Deploy Kubernetes cluster in tenant
6. Deploy vLLM from service catalog
7. Configure OIDC with Okta
8. Generate usage report
9. Review audit logs
10. Document the deployment

**Deliverables:**
- Tenant configuration documentation
- Network topology diagram
- Quota allocation summary
- RBAC role assignments
- Audit log excerpt
- Usage report sample

### 7.5 Final Assessment

**Components:**
- Week 6 Quiz (20%)
- Capstone Project Evaluation (80%)

**Capstone Evaluation Criteria:**
| Criterion | Points |
|-----------|--------|
| Tenant isolation correct | 20 |
| Network policies enforced | 15 |
| Quotas working | 15 |
| RBAC configured correctly | 15 |
| Cluster deployed successfully | 15 |
| AI workload running | 10 |
| Documentation complete | 10 |
| **Total** | **100** |

**Passing Score:** 80%

---

## 8. Lab Environment Guide

### 8.1 Environment Provisioning

Each engineer receives on-demand cloud environments provisioned via self-service portal.

**Environment Types:**

| Type | Use Case | Resources | Est. Cost/hr |
|------|----------|-----------|--------------|
| Metal3 Dev | Weeks 1-2 | 16GB RAM, 8 vCPU, nested virt | ~$1 |
| KubeVirt Lab | Week 3 | 4-node cluster, no GPU | ~$3 |
| GPU Lab | Weeks 3-5 | P4d.24xlarge (8x A100) | ~$32 |
| Full Stack | Week 6 | Multi-node + GPU | ~$50 |

### 8.2 Provisioning Steps

1. Navigate to Lab Portal (URL provided separately)
2. Authenticate via SSO
3. Select environment type
4. Click "Provision"
5. Wait for environment ready notification (5-15 minutes)
6. Access credentials via portal

### 8.3 Environment Lifecycle

- **Default TTL:** 8 hours
- **Extension:** Up to 24 hours via portal
- **Auto-teardown:** Environments destroyed automatically after TTL
- **State preservation:** Checkpoint/restore available for multi-day labs

### 8.4 Cost Management

- All lab costs covered by central training budget
- Engineers should tear down environments when not in use
- Unused environments auto-destroyed after TTL

---

## 9. Assessment Framework

### 9.1 Weekly Assessments

Each week includes:
- **Quiz:** 15-20 multiple choice/short answer questions
- **Duration:** 30 minutes
- **Passing Score:** 80%
- **Retakes:** Unlimited

### 9.2 Lab Completion

Labs include verification checkpoints:
- Automated validation scripts where possible
- Screenshot/output submission requirements
- Peer review for complex labs

### 9.3 Progress Tracking

| Week | Quiz Weight | Lab Weight | Cumulative |
|------|-------------|------------|------------|
| 1 | 5% | 10% | 15% |
| 2 | 5% | 10% | 30% |
| 3 | 5% | 10% | 45% |
| 4 | 5% | 10% | 60% |
| 5 | 5% | 10% | 75% |
| 6 | 5% | 20% (Capstone) | 100% |

### 9.4 Completion Requirements

- All weekly quizzes passed (80%+)
- All labs completed with deliverables
- Capstone project passed (80%+)
- Minimum 85% overall score for certification

---

## 10. Resources & References

### 10.1 Official Documentation

- [Mirantis k0rdent Documentation](https://docs.mirantis.com/k0rdent-enterprise/latest/)
- [Metal3 Documentation](https://metal3.io/documentation.html)
- [KubeVirt User Guide](https://kubevirt.io/user-guide/)
- [NVIDIA GPU Operator](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/)
- [Cluster API Book](https://cluster-api.sigs.k8s.io/)

### 10.2 NVIDIA Resources

- [NVIDIA Data Center Documentation](https://docs.nvidia.com/datacenter/)
- [GPU Operator with KubeVirt](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/gpu-operator-kubevirt.html)
- [GPUDirect RDMA Documentation](https://docs.nvidia.com/cuda/gpudirect-rdma/)
- [NVLink Technical Overview](https://www.nvidia.com/en-us/data-center/nvlink/)

### 10.3 Community Resources

- [Metal3 GitHub](https://github.com/metal3-io)
- [KubeVirt GitHub](https://github.com/kubevirt)
- [vLLM Documentation](https://docs.vllm.ai/)
- [KAI Scheduler GitHub](https://github.com/NVIDIA/KAI-Scheduler)

### 10.4 Additional Learning

- [CNCF Kubernetes Certifications](https://www.cncf.io/certification/)
- [NVIDIA AI Infrastructure Certification](https://www.nvidia.com/en-us/learn/certification/ai-infrastructure-operations-associate/)
- [Kubernetes Multi-tenancy Best Practices](https://kubernetes.io/docs/concepts/security/multi-tenancy/)

---

## Appendix A: Glossary

| Term | Definition |
|------|------------|
| **BMaaS** | Bare Metal as a Service |
| **VMaaS** | Virtual Machine as a Service |
| **KaaS** | Kubernetes as a Service |
| **MaaS** | Models as a Service |
| **BMC** | Baseboard Management Controller |
| **CAPI** | Cluster API |
| **CAPM3** | Cluster API Provider Metal3 |
| **DCME** | Distributed Container Management Environment |
| **GPUDirect** | NVIDIA technology for direct GPU memory access |
| **HGX** | NVIDIA high-performance GPU baseboard |
| **IOMMU** | Input/Output Memory Management Unit |
| **IPA** | Ironic Python Agent |
| **MIG** | Multi-Instance GPU |
| **NUMA** | Non-Uniform Memory Access |
| **NVLink** | NVIDIA high-speed GPU interconnect |
| **NVSwitch** | NVIDIA switch for NVLink fabric |
| **RDMA** | Remote Direct Memory Access |
| **SR-IOV** | Single Root I/O Virtualization |
| **VFIO** | Virtual Function I/O |
| **vGPU** | Virtual GPU |

---

## Appendix B: Command Reference

### Redfish Commands
```bash
# Get system info
curl -k -u admin:pass https://bmc/redfish/v1/Systems/1

# Power control
curl -k -u admin:pass -X POST -H "Content-Type: application/json" \
  -d '{"ResetType": "ForceRestart"}' \
  https://bmc/redfish/v1/Systems/1/Actions/ComputerSystem.Reset
```

### Metal3 Commands
```bash
# List bare metal hosts
kubectl get baremetalhosts -n metal3

# Watch provisioning progress
kubectl get bmh -n metal3 -w

# Get detailed status
kubectl describe bmh <name> -n metal3
```

### KubeVirt Commands
```bash
# List VMs
kubectl get vms

# Start VM
virtctl start <vm-name>

# Console access
virtctl console <vm-name>

# SSH to VM
virtctl ssh <vm-name>
```

### GPU Operator Commands
```bash
# Check GPU nodes
kubectl get nodes -l nvidia.com/gpu.present=true

# View GPU resources
kubectl describe node <node> | grep nvidia

# Check MIG configuration
kubectl get nodes -o json | jq '.items[].metadata.labels | with_entries(select(.key | startswith("nvidia.com/mig")))'
```

---

## Document Control

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | Nov 2025 | AI Training Team | Initial release |
| 1.1 | Nov 2025 | AI Training Team | Updated versions: k0s v1.32.4, KubeVirt v1.6.3, GPU Operator v25.10.0, vLLM v0.11.2, Terraform >= 1.8.0; Added Metal3 CNCF Incubating status |
| 1.2 | Nov 2025 | AI Training Team | Added Week 5 labs: Lab 5.7 NVIDIA FIPS, Lab 5.8 Cluster Templates, Lab 5.9 Kubeflow, Lab 5.10 MLflow, Lab 5.11 Run:AI/KAI GPU Orchestration, Lab 5.12 Slurm Operator |

---

*This curriculum was developed for Mirantis engineers to enable k0rdent AI infrastructure implementations.*
