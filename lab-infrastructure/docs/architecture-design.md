# k0rdent Training Lab Infrastructure - Architecture Design

**Version:** 1.1
**Date:** November 2025
**Status:** Draft for Review

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Requirements](#2-requirements)
3. [Architecture Overview](#3-architecture-overview)
4. [AWS Infrastructure Design](#4-aws-infrastructure-design)
5. [Environment Types](#5-environment-types)
6. [Networking Design](#6-networking-design)
7. [Automation & Provisioning](#7-automation--provisioning)
8. [Security Design](#8-security-design)
9. [Cost Management](#9-cost-management)
10. [Implementation Roadmap](#10-implementation-roadmap)
11. [Appendix](#appendix)

---

## 1. Executive Summary

### Purpose

This document defines the architecture for a self-service lab environment platform supporting the k0rdent AI Infrastructure Training curriculum. The platform enables engineers to provision on-demand cloud environments for hands-on labs.

### Scope

- **MVP Scope:** CLI-based provisioning via Terraform
- **Cloud Provider:** AWS (single region initially)
- **Environment Types:** 4 (Metal3 Dev, KubeVirt Lab, GPU Lab, Full Stack)
- **Target Users:** 5-15 engineers per training cohort

### Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Cloud Provider | AWS | GPU availability, team familiarity |
| IaC Tool | Terraform | Industry standard, good AWS support |
| Provisioning | CLI Scripts | MVP simplicity, fast iteration |
| Orchestration | Bash + Terraform | Minimal dependencies |

---

## 2. Requirements

### Functional Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| FR-1 | Provision 4 environment types on-demand | P0 |
| FR-2 | Automatic tool installation (kubectl, helm, etc.) | P0 |
| FR-3 | Pre-configured k0rdent/Metal3/KubeVirt | P0 |
| FR-4 | SSH access with generated keys | P0 |
| FR-5 | Kubeconfig generation for K8s environments | P0 |
| FR-6 | Environment status checking | P1 |
| FR-7 | Graceful teardown with state cleanup | P0 |
| FR-8 | TTL-based auto-termination | P1 |
| FR-9 | Cost tagging per engineer/environment | P1 |

### Non-Functional Requirements

| ID | Requirement | Target |
|----|-------------|--------|
| NFR-1 | Provisioning time (non-GPU) | < 15 minutes |
| NFR-2 | Provisioning time (GPU) | < 25 minutes |
| NFR-3 | Concurrent environments | Up to 15 |
| NFR-4 | Environment availability | 99% during business hours |
| NFR-5 | Cost visibility | Per-environment tracking |

### Constraints

- AWS account with GPU quota (P4d instances)
- VPC with sufficient IP space
- IAM permissions for EC2, VPC, S3
- Engineers have AWS CLI configured locally

---

## 3. Architecture Overview

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           Engineer Workstation                               │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │  CLI Tools                                                           │    │
│  │  ├── lab-provision.sh <type> [options]                              │    │
│  │  ├── lab-status.sh <env-id>                                         │    │
│  │  ├── lab-connect.sh <env-id>                                        │    │
│  │  └── lab-destroy.sh <env-id>                                        │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      │ Terraform Apply
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                              AWS Cloud                                       │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                         Shared Infrastructure                        │   │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐              │   │
│  │  │     VPC      │  │      S3      │  │   Route53    │              │   │
│  │  │  10.0.0.0/16 │  │ State/Images │  │  DNS (opt)   │              │   │
│  │  └──────────────┘  └──────────────┘  └──────────────┘              │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                      Lab Environments (per engineer)                 │   │
│  │                                                                      │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌───────────┐  │   │
│  │  │ Metal3 Dev  │  │KubeVirt Lab │  │  GPU Lab    │  │Full Stack │  │   │
│  │  │             │  │             │  │             │  │           │  │   │
│  │  │ 1x m5.2xl   │  │ 4x t3.xl    │  │ 1x p4d.24xl │  │ Multi     │  │   │
│  │  │ Nested Virt │  │ K8s Cluster │  │ 8x A100     │  │ Node+GPU  │  │   │
│  │  └─────────────┘  └─────────────┘  └─────────────┘  └───────────┘  │   │
│  │                                                                      │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Component Diagram

```
┌──────────────────────────────────────────────────────────────────────────┐
│                         Terraform Project Structure                       │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  terraform/                                                              │
│  ├── modules/                                                            │
│  │   ├── shared-infra/          # VPC, S3, IAM (deployed once)          │
│  │   ├── metal3-dev/            # Single VM environment                 │
│  │   ├── kubevirt-lab/          # Multi-node K8s cluster                │
│  │   ├── gpu-lab/               # GPU instance with K8s                 │
│  │   └── full-stack/            # k0rdent + workload clusters           │
│  │                                                                       │
│  ├── environments/                                                       │
│  │   ├── shared/                # Shared infra terraform                │
│  │   └── labs/                  # Per-engineer lab instances            │
│  │       └── <engineer>-<type>/ # Dynamic workspaces                    │
│  │                                                                       │
│  └── scripts/                                                            │
│      ├── lab-provision.sh                                                │
│      ├── lab-status.sh                                                   │
│      ├── lab-connect.sh                                                  │
│      └── lab-destroy.sh                                                  │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘
```

---

## 4. AWS Infrastructure Design

### 4.1 Shared Infrastructure

Deployed once, used by all lab environments.

#### VPC Design

```
VPC: 10.0.0.0/16 (65,536 IPs)
├── Public Subnets (for bastion/NAT)
│   ├── 10.0.1.0/24  (AZ-a) - 254 IPs
│   ├── 10.0.2.0/24  (AZ-b) - 254 IPs
│   └── 10.0.3.0/24  (AZ-c) - 254 IPs
│
├── Private Subnets (for lab instances)
│   ├── 10.0.10.0/22 (AZ-a) - 1,022 IPs
│   ├── 10.0.14.0/22 (AZ-b) - 1,022 IPs
│   └── 10.0.18.0/22 (AZ-c) - 1,022 IPs
│
└── GPU Subnets (for P4d instances - specific AZs)
    └── 10.0.100.0/24 (AZ with P4d capacity) - 254 IPs
```

#### S3 Buckets

| Bucket | Purpose | Lifecycle |
|--------|---------|-----------|
| `k0rdent-training-tfstate` | Terraform state files | Versioned, 90-day retention |
| `k0rdent-training-images` | OS images, ISOs | No expiration |
| `k0rdent-training-artifacts` | Lab outputs, logs | 30-day expiration |

#### IAM Design

```
IAM Roles:
├── k0rdent-lab-provisioner
│   └── Permissions: EC2, VPC, S3, Route53
│
├── k0rdent-lab-instance
│   └── Permissions: S3 read (images), CloudWatch logs
│
└── k0rdent-lab-admin
    └── Permissions: Full lab management (for instructors)
```

### 4.2 Instance Types by Environment

| Environment | Primary Instance | Alternative | vCPU | RAM | GPU |
|-------------|-----------------|-------------|------|-----|-----|
| Metal3 Dev | m5.2xlarge | m5.xlarge | 8 | 32GB | - |
| KubeVirt Lab | t3.xlarge (x4) | t3.large (x4) | 16 | 64GB | - |
| GPU Lab | p4d.24xlarge | p3.8xlarge | 96 | 1152GB | 8xA100 |
| Full Stack | Mixed | - | ~128 | ~512GB | 4xA100 |

### 4.3 AMI Strategy

| AMI Name | Base | Pre-installed | Size |
|----------|------|---------------|------|
| `k0rdent-base` | Ubuntu 22.04 | Docker, kubectl, helm | ~8GB |
| `k0rdent-metal3` | k0rdent-base | metal3-dev-env, libvirt | ~15GB |
| `k0rdent-gpu` | NVIDIA DL AMI | GPU drivers, CUDA | ~50GB |

---

## 5. Environment Types

### 5.1 Metal3 Dev Environment

**Purpose:** Weeks 1-2 (BMaaS labs)

```
┌─────────────────────────────────────────────────────────────────┐
│                     Metal3 Dev Environment                       │
│                                                                 │
│  AWS Instance: m5.2xlarge (8 vCPU, 32GB RAM)                   │
│  AMI: k0rdent-metal3                                            │
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │                    Ubuntu 22.04 Host                       │ │
│  │                                                            │ │
│  │  ┌─────────────────────────────────────────────────────┐  │ │
│  │  │  metal3-dev-env                                      │  │ │
│  │  │  ├── Management Cluster (minikube/kind)             │  │ │
│  │  │  │   ├── Bare Metal Operator                        │  │ │
│  │  │  │   ├── Ironic                                     │  │ │
│  │  │  │   └── CAPI Controllers                           │  │ │
│  │  │  │                                                   │  │ │
│  │  │  └── Virtual Bare Metal Hosts (libvirt VMs)         │  │ │
│  │  │      ├── node-1 (control plane)                     │  │ │
│  │  │      ├── node-2 (worker)                            │  │ │
│  │  │      └── node-3 (worker)                            │  │ │
│  │  └─────────────────────────────────────────────────────┘  │ │
│  │                                                            │ │
│  │  Tools: kubectl, helm, clusterctl, virtctl                │ │
│  └───────────────────────────────────────────────────────────┘ │
│                                                                 │
│  Network: Public IP + Security Group (SSH only)                │
│  Storage: 100GB gp3 root volume                                │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**Terraform Variables:**

```hcl
variable "metal3_dev" {
  type = object({
    instance_type     = string
    root_volume_size  = number
    enable_nested_virt = bool
    num_virtual_nodes = number
  })
  default = {
    instance_type     = "m5.2xlarge"
    root_volume_size  = 100
    enable_nested_virt = true
    num_virtual_nodes = 3
  }
}
```

**Bootstrap Steps:**
1. Launch EC2 with nested virtualization (metal instance or .metal for full support)
2. Install libvirt, QEMU, Docker
3. Clone and configure metal3-dev-env
4. Create virtual BMC endpoints (sushy-tools)
5. Initialize management cluster
6. Output SSH key and connection info

---

### 5.2 KubeVirt Lab Environment

**Purpose:** Week 3 (VMaaS - non-GPU portions)

```
┌─────────────────────────────────────────────────────────────────┐
│                    KubeVirt Lab Environment                      │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                   Kubernetes Cluster                     │   │
│  │                                                          │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐     │   │
│  │  │ Control     │  │   Worker    │  │   Worker    │     │   │
│  │  │ Plane       │  │   Node 1    │  │   Node 2    │     │   │
│  │  │             │  │             │  │             │     │   │
│  │  │ t3.xlarge   │  │ t3.xlarge   │  │ t3.xlarge   │     │   │
│  │  │ 4 vCPU      │  │ 4 vCPU      │  │ 4 vCPU      │     │   │
│  │  │ 16GB RAM    │  │ 16GB RAM    │  │ 16GB RAM    │     │   │
│  │  └─────────────┘  └─────────────┘  └─────────────┘     │   │
│  │                                                          │   │
│  │  Installed Components:                                   │   │
│  │  ├── KubeVirt Operator + CDI                            │   │
│  │  ├── Multus CNI                                         │   │
│  │  ├── Local Path Provisioner                             │   │
│  │  └── Sample VM images                                   │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  Bastion: t3.small (for kubectl access)                        │
│  Network: Private subnet + NAT Gateway                          │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**Kubernetes Distribution:** k0s

k0s is used for all Kubernetes clusters in the training environment:
- Single binary installation with zero dependencies
- Built-in etcd, CoreDNS, kube-proxy
- k0sctl for declarative cluster management
- Easy cluster upgrades
- Consistent with k0rdent platform

**Terraform Variables:**

```hcl
variable "kubevirt_lab" {
  type = object({
    controller_count    = number
    worker_count        = number
    controller_type     = string
    worker_type         = string
    k0s_version         = string
  })
  default = {
    controller_count    = 1
    worker_count        = 2
    controller_type     = "t3.xlarge"
    worker_type         = "t3.xlarge"
    k0s_version         = "v1.32.4+k0s.0"
  }
}
```

**k0s Cluster Bootstrap (via k0sctl):**

```yaml
# k0sctl.yaml template
apiVersion: k0sctl.k0sproject.io/v1beta1
kind: Cluster
metadata:
  name: kubevirt-lab
spec:
  k0s:
    version: v1.32.4+k0s.0
  hosts:
    - role: controller
      ssh:
        address: ${controller_ip}
        user: ubuntu
        keyPath: ${ssh_key_path}
    - role: worker
      ssh:
        address: ${worker_1_ip}
        user: ubuntu
        keyPath: ${ssh_key_path}
    - role: worker
      ssh:
        address: ${worker_2_ip}
        user: ubuntu
        keyPath: ${ssh_key_path}
```

---

### 5.3 GPU Lab Environment

**Purpose:** Weeks 3-5 (GPU passthrough, AI workloads)

**Note:** Uses p3.8xlarge (4x V100) for cost optimization. Lab 3.3 (8-GPU) uses a shared p4d session.

```
┌─────────────────────────────────────────────────────────────────┐
│                   GPU Lab Environment (Standard)                 │
│                                                                 │
│  AWS Instance: p3.8xlarge (shared, 3 engineers per instance)    │
│  ├── 32 vCPUs (Intel Xeon E5-2686 v4)                          │
│  ├── 244 GB RAM                                                 │
│  ├── 4x NVIDIA V100 16GB GPUs                                   │
│  ├── NVLink between GPU pairs                                   │
│  └── 10 Gbps networking                                        │
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │                  Single-Node Kubernetes                    │ │
│  │                                                            │ │
│  │  Pre-installed:                                            │ │
│  │  ├── NVIDIA GPU Operator                                   │ │
│  │  │   ├── nvidia-driver-daemonset                          │ │
│  │  │   ├── nvidia-container-toolkit                         │ │
│  │  │   ├── nvidia-device-plugin                             │ │
│  │  │   └── dcgm-exporter                                    │ │
│  │  │                                                         │ │
│  │  ├── KubeVirt (with GPU passthrough configured)           │ │
│  │  │                                                         │ │
│  │  └── Network Operator (for RDMA)                          │ │
│  │                                                            │ │
│  └───────────────────────────────────────────────────────────┘ │
│                                                                 │
│  IOMMU: Enabled (for GPU passthrough to VMs)                   │
│  Fabric Manager: Running (for NVLink topology)                 │
│                                                                 │
│  Network: Public IP (Elastic) + EFA endpoints                  │
│  Storage: 8TB NVMe local + 500GB EBS for images               │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**GPU Configuration:**

```
NVIDIA A100 GPU Topology on p4d.24xlarge:

    GPU0 ─── NVSwitch ─── GPU1
      │         │          │
      │    ┌────┴────┐     │
      │    │         │     │
    GPU2 ──┤ NVSwitch├── GPU3
      │    │         │     │
      │    └────┬────┘     │
      │         │          │
    GPU4 ─── NVSwitch ─── GPU5
      │         │          │
    GPU6 ─── NVSwitch ─── GPU7

All GPUs connected via NVSwitch with 600GB/s bandwidth
```

**Terraform Variables:**

```hcl
variable "gpu_lab" {
  type = object({
    instance_type        = string
    use_spot             = bool
    spot_max_price       = string
    root_volume_size     = number
    enable_efa           = bool
    enable_gpu_passthrough = bool
  })
  default = {
    instance_type        = "p4d.24xlarge"
    use_spot             = true
    spot_max_price       = "15.00"  # ~50% of on-demand
    root_volume_size     = 500
    enable_efa           = true
    enable_gpu_passthrough = true
  }
}
```

**Cost Optimization:**
- Use Spot Instances when available (~$10-15/hr vs $32.77 on-demand)
- Automatic fallback to on-demand if spot unavailable
- Instance Scheduler for auto-stop after 8 hours

---

### 5.4 Full Stack Environment

**Purpose:** Week 6 (Capstone)

```
┌─────────────────────────────────────────────────────────────────┐
│                   Full Stack Environment                         │
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │                k0rdent Management Cluster                  │ │
│  │                                                            │ │
│  │  3x t3.xlarge (HA control plane)                          │ │
│  │  ├── k0rdent Control Plane                                │ │
│  │  ├── Metal3 / KubeVirt providers                          │ │
│  │  └── Monitoring Stack                                      │ │
│  └───────────────────────────────────────────────────────────┘ │
│                            │                                    │
│                            │ Manages                            │
│                            ▼                                    │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │                   Tenant Infrastructure                    │ │
│  │                                                            │ │
│  │  GPU Nodes (for tenant workloads):                        │ │
│  │  └── 1x p4d.24xlarge (can provision tenant VMs/clusters)  │ │
│  │                                                            │ │
│  │  CPU Nodes (for tenant control planes):                   │ │
│  │  └── 2x t3.xlarge                                         │ │
│  │                                                            │ │
│  └───────────────────────────────────────────────────────────┘ │
│                                                                 │
│  Pre-configured:                                                │
│  ├── Sample tenant "techcorp-ai"                               │
│  ├── Network isolation                                         │
│  ├── Quotas configured                                         │
│  └── Service catalog populated                                 │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**Terraform Variables:**

```hcl
variable "full_stack" {
  type = object({
    management_nodes     = number
    management_type      = string
    gpu_nodes            = number
    gpu_type             = string
    cpu_worker_nodes     = number
    cpu_worker_type      = string
    k0rdent_version      = string
    pre_create_tenant    = bool
  })
  default = {
    management_nodes     = 3
    management_type      = "t3.xlarge"
    gpu_nodes            = 1
    gpu_type             = "p4d.24xlarge"
    cpu_worker_nodes     = 2
    cpu_worker_type      = "t3.xlarge"
    k0rdent_version      = "latest"
    pre_create_tenant    = true
  }
}
```

---

## 6. Networking Design

### 6.1 Network Topology

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              AWS VPC: 10.0.0.0/16                            │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  Public Subnets                                                      │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                 │   │
│  │  │ 10.0.1.0/24 │  │ 10.0.2.0/24 │  │ 10.0.3.0/24 │                 │   │
│  │  │    AZ-a     │  │    AZ-b     │  │    AZ-c     │                 │   │
│  │  │  NAT GW     │  │  NAT GW     │  │  NAT GW     │                 │   │
│  │  │  Bastion    │  │             │  │             │                 │   │
│  │  └─────────────┘  └─────────────┘  └─────────────┘                 │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                      │                                      │
│                                      │ NAT                                  │
│                                      ▼                                      │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  Private Subnets (Lab Instances)                                    │   │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐              │   │
│  │  │10.0.10.0/22  │  │10.0.14.0/22  │  │10.0.18.0/22  │              │   │
│  │  │    AZ-a      │  │    AZ-b      │  │    AZ-c      │              │   │
│  │  │              │  │              │  │              │              │   │
│  │  │ Metal3 Labs  │  │ KubeVirt     │  │ Full Stack   │              │   │
│  │  │ KubeVirt     │  │ Full Stack   │  │              │              │   │
│  │  └──────────────┘  └──────────────┘  └──────────────┘              │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  GPU Subnet (P4d capacity zone)                                     │   │
│  │  ┌────────────────────────────────────────────────────────────┐    │   │
│  │  │ 10.0.100.0/24                                               │    │   │
│  │  │ AZ-a (or whichever has P4d capacity)                       │    │   │
│  │  │                                                             │    │   │
│  │  │ GPU Lab instances                                          │    │   │
│  │  │ EFA-enabled                                                 │    │   │
│  │  └────────────────────────────────────────────────────────────┘    │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 6.2 Security Groups

| Security Group | Inbound | Outbound | Used By |
|----------------|---------|----------|---------|
| `sg-bastion` | 22 (SSH) from allowed IPs | All | Bastion host |
| `sg-lab-instance` | 22 from bastion SG | All | All lab instances |
| `sg-k8s-cluster` | 6443 from VPC, 22 from bastion | All | K8s clusters |
| `sg-gpu-lab` | 22 from bastion, EFA ports | All | GPU instances |

### 6.3 DNS (Optional)

If Route53 is available:
```
*.labs.k0rdent-training.internal → Private hosted zone
<engineer>-<type>.labs.k0rdent-training.internal
```

---

## 7. Automation & Provisioning

### 7.1 Provisioning Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         Provisioning Workflow                                │
│                                                                             │
│  Engineer                    Terraform                    AWS               │
│     │                           │                          │                │
│     │  lab-provision metal3     │                          │                │
│     │──────────────────────────►│                          │                │
│     │                           │                          │                │
│     │                           │  terraform init/plan     │                │
│     │                           │─────────────────────────►│                │
│     │                           │                          │                │
│     │                           │  Create EC2 instance     │                │
│     │                           │─────────────────────────►│                │
│     │                           │                          │                │
│     │                           │  cloud-init bootstrap    │                │
│     │                           │─────────────────────────►│                │
│     │                           │                          │                │
│     │                           │  Wait for ready signal   │                │
│     │                           │◄─────────────────────────│                │
│     │                           │                          │                │
│     │  SSH key + connection info│                          │                │
│     │◄──────────────────────────│                          │                │
│     │                           │                          │                │
│     │  lab-connect <env-id>     │                          │                │
│     │──────────────────────────►│                          │                │
│     │                           │                          │                │
│     │  SSH session established  │                          │                │
│     │◄─────────────────────────────────────────────────────│                │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 7.2 CLI Script Specifications

#### lab-provision.sh

```bash
#!/bin/bash
# Usage: lab-provision.sh <type> [options]
#
# Types: metal3-dev, kubevirt-lab, gpu-lab, full-stack
#
# Options:
#   --name <name>       Custom environment name (default: $USER-<type>)
#   --ttl <hours>       Time to live in hours (default: 8)
#   --spot              Use spot instances where applicable
#   --no-wait           Don't wait for environment to be ready
#
# Examples:
#   lab-provision.sh metal3-dev
#   lab-provision.sh gpu-lab --ttl 4 --spot
#   lab-provision.sh full-stack --name capstone-test
```

#### lab-status.sh

```bash
#!/bin/bash
# Usage: lab-status.sh [env-id]
#
# If no env-id provided, lists all environments for current user.
#
# Output:
#   ENV_ID          TYPE         STATUS    CREATED      TTL_REMAINING
#   john-metal3     metal3-dev   ready     2h ago       6h
#   john-gpu        gpu-lab      creating  5m ago       7h 55m
```

#### lab-connect.sh

```bash
#!/bin/bash
# Usage: lab-connect.sh <env-id> [--kubeconfig]
#
# Connects to lab environment via SSH.
# With --kubeconfig, downloads kubeconfig instead of SSH.
#
# Examples:
#   lab-connect.sh john-metal3           # SSH to environment
#   lab-connect.sh john-gpu --kubeconfig # Download kubeconfig
```

#### lab-destroy.sh

```bash
#!/bin/bash
# Usage: lab-destroy.sh <env-id> [--force]
#
# Destroys a lab environment.
# Without --force, prompts for confirmation.
#
# Examples:
#   lab-destroy.sh john-metal3
#   lab-destroy.sh john-gpu --force
```

### 7.3 Bootstrap Scripts (cloud-init)

Each environment type has a bootstrap script that runs via cloud-init:

```yaml
#cloud-config
# metal3-dev bootstrap

packages:
  - docker.io
  - qemu-kvm
  - libvirt-daemon-system
  - virtinst

runcmd:
  # Install kubectl, helm, clusterctl
  - curl -LO "https://dl.k8s.io/release/v1.32.4/bin/linux/amd64/kubectl"
  - install kubectl /usr/local/bin/

  # Clone and setup metal3-dev-env
  - git clone https://github.com/metal3-io/metal3-dev-env.git /opt/metal3-dev-env
  - cd /opt/metal3-dev-env && make

  # Signal ready
  - touch /var/lib/cloud/instance/lab-ready

write_files:
  - path: /etc/profile.d/lab-env.sh
    content: |
      export KUBECONFIG=/opt/metal3-dev-env/kubeconfig
      alias k=kubectl
```

### 7.4 TTL Enforcement

**Option A: AWS Instance Scheduler (Recommended)**
- Tag instances with `ttl-hours: 8`
- Lambda function checks hourly
- Terminates instances past TTL

**Option B: Instance User Data**
- Schedule shutdown in cloud-init
- `shutdown -h +480` (8 hours)
- Less reliable if instance reboots

**Implementation:**

```hcl
# Terraform tags for TTL
resource "aws_instance" "lab" {
  # ...
  tags = {
    Name        = "${var.engineer}-${var.env_type}"
    Environment = "training-lab"
    Engineer    = var.engineer
    EnvType     = var.env_type
    CreatedAt   = timestamp()
    TTLHours    = var.ttl_hours
    AutoStop    = "true"
  }
}
```

---

## 8. Security Design

### 8.1 Access Control

```
┌─────────────────────────────────────────────────────────────────┐
│                      Access Model                                │
│                                                                 │
│  Engineer Workstation                                           │
│  └── AWS CLI (configured with engineer credentials)            │
│      └── IAM User: engineer-<name>                             │
│          └── IAM Policy: k0rdent-lab-user                      │
│              ├── ec2:Describe*                                 │
│              ├── ec2:RunInstances (tagged resources only)      │
│              ├── ec2:TerminateInstances (own resources only)   │
│              └── s3:GetObject (images bucket)                  │
│                                                                 │
│  Lab Instance                                                   │
│  └── IAM Instance Role: k0rdent-lab-instance                   │
│      ├── s3:GetObject (artifacts)                              │
│      ├── cloudwatch:PutMetricData                              │
│      └── logs:CreateLogStream, PutLogEvents                    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 8.2 SSH Key Management

```
Per-Environment SSH Keys:
1. Terraform generates ED25519 key pair
2. Public key injected via cloud-init
3. Private key stored in Terraform state
4. lab-connect.sh retrieves from state
5. Keys deleted on environment destroy
```

### 8.3 Network Security

| Control | Implementation |
|---------|----------------|
| No public IPs on lab instances | Private subnets + NAT |
| SSH via bastion only | Security group rules |
| Egress filtering | NAT Gateway + optional NACL |
| GPU instance isolation | Dedicated subnet |

### 8.4 Secrets Management

| Secret | Storage | Access |
|--------|---------|--------|
| AWS credentials | Local AWS CLI config | Engineer only |
| SSH keys | Terraform state (encrypted S3) | lab-connect.sh |
| Kubeconfigs | Instance filesystem | lab-connect.sh |
| HuggingFace tokens | AWS Secrets Manager | Instance role |

---

## 9. Cost Management

### 9.1 Cost Estimates (Optimized Hybrid Model)

**Strategy:** Shared p3.8xlarge (4x V100) for most GPU labs + One p4d.24xlarge session for Lab 3.3

| Environment | Instance | Spot/hr | Sharing | Notes |
|-------------|----------|---------|---------|-------|
| Metal3 Dev | m5.2xlarge | $0.12 | Individual | Weeks 1-2 |
| KubeVirt Lab | 4x t3.xlarge | $0.20 | Individual | Week 3 (non-GPU) |
| GPU Lab | p3.8xlarge | $4.50 | 3 per instance | Weeks 3-5 |
| GPU Lab (3.3) | p4d.24xlarge | $15.00 | All 15 rotate | One 4hr session |
| Full Stack | Mixed | $6.00 | 3 per instance | Week 6 |

**Per Cohort Estimate (15 engineers, 6 weeks):**

| Component | Calculation | Cost |
|-----------|-------------|------|
| Metal3 Dev | 15 × 5 sessions × 3hr × $0.12 | $27 |
| KubeVirt Lab | 15 × 3 sessions × 3hr × $0.20 | $27 |
| GPU Lab (shared p3) | 5 instances × 12 days × 4hr × $4.50 | $1,080 |
| Lab 3.3 (p4d session) | 1 instance × 4hr × $15 | $60 |
| Full Stack (shared) | 5 instances × 2 sessions × 4hr × $6 | $240 |
| Infrastructure | NAT, S3, data transfer | $100 |
| **Subtotal** | | **$1,534** |
| Buffer (50%) | | $766 |
| **TOTAL PER COHORT** | | **~$2,300** |

### 9.2 Cost Controls

1. **Spot Instances:** Use for GPU labs (60-70% savings)
2. **TTL Enforcement:** Auto-terminate after 8 hours
3. **Right-sizing:** Start with minimum, scale if needed
4. **Cost Tagging:** Track by engineer and environment type
5. **Budget Alerts:** CloudWatch alarms at 50%, 80%, 100% of budget

### 9.3 Tagging Strategy

```hcl
locals {
  common_tags = {
    Project     = "k0rdent-training"
    Environment = "lab"
    ManagedBy   = "terraform"
  }

  lab_tags = {
    Engineer    = var.engineer
    EnvType     = var.env_type
    CostCenter  = "training-${var.cohort}"
    TTLHours    = var.ttl_hours
  }
}
```

---

## 10. Implementation Roadmap

### Phase 1: Foundation (Days 1-2)

- [ ] Set up Terraform project structure
- [ ] Create shared infrastructure module (VPC, S3, IAM)
- [ ] Deploy shared infrastructure
- [ ] Create base AMIs (k0rdent-base)
- [ ] Test basic EC2 provisioning

### Phase 2: Metal3 Dev Environment (Days 2-3)

- [ ] Create metal3-dev Terraform module
- [ ] Write cloud-init bootstrap script
- [ ] Create k0rdent-metal3 AMI
- [ ] Test end-to-end provisioning
- [ ] Write lab-provision.sh for metal3

### Phase 3: KubeVirt Lab Environment (Days 3-4)

- [ ] Create kubevirt-lab Terraform module
- [ ] Write k0s bootstrap scripts (k0sctl)
- [ ] Test multi-node cluster creation
- [ ] Install KubeVirt via bootstrap
- [ ] Write lab-provision.sh for kubevirt

### Phase 4: GPU Lab Environment (Days 4-5)

- [ ] Create gpu-lab Terraform module
- [ ] Configure spot instance handling
- [ ] Write GPU bootstrap (drivers, operator)
- [ ] Test GPU passthrough configuration
- [ ] Write lab-provision.sh for gpu

### Phase 5: Full Stack Environment (Days 5-6)

- [ ] Create full-stack Terraform module
- [ ] Write k0rdent installation scripts
- [ ] Configure pre-built tenant
- [ ] Test complete environment
- [ ] Write lab-provision.sh for full-stack

### Phase 6: CLI & Polish (Days 6-7)

- [ ] Complete all CLI scripts
- [ ] Implement TTL enforcement
- [ ] Add cost tagging
- [ ] Write documentation
- [ ] End-to-end testing all environments
- [ ] Create instructor guide

### Milestones

| Milestone | Target | Deliverable |
|-----------|--------|-------------|
| M1 | Day 2 | Shared infra deployed, base AMI ready |
| M2 | Day 3 | Metal3 Dev environment working |
| M3 | Day 4 | KubeVirt Lab environment working |
| M4 | Day 5 | GPU Lab environment working |
| M5 | Day 6 | Full Stack environment working |
| M6 | Day 7 | All CLI scripts complete, documentation done |

---

## Appendix

### A. Terraform Module Interface

```hcl
# modules/metal3-dev/variables.tf
variable "engineer" {
  description = "Engineer username"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "m5.2xlarge"
}

variable "ttl_hours" {
  description = "Time to live in hours"
  type        = number
  default     = 8
}

variable "vpc_id" {
  description = "VPC ID for deployment"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID for deployment"
  type        = string
}

# modules/metal3-dev/outputs.tf
output "instance_id" {
  value = aws_instance.metal3_dev.id
}

output "private_ip" {
  value = aws_instance.metal3_dev.private_ip
}

output "ssh_private_key" {
  value     = tls_private_key.ssh.private_key_pem
  sensitive = true
}
```

### B. Directory Structure

```
lab-infrastructure/
├── docs/
│   └── architecture-design.md     # This document
├── terraform/
│   ├── modules/
│   │   ├── shared-infra/
│   │   │   ├── main.tf
│   │   │   ├── vpc.tf
│   │   │   ├── s3.tf
│   │   │   ├── iam.tf
│   │   │   ├── variables.tf
│   │   │   └── outputs.tf
│   │   ├── metal3-dev/
│   │   │   ├── main.tf
│   │   │   ├── cloud-init.yaml
│   │   │   ├── variables.tf
│   │   │   └── outputs.tf
│   │   ├── kubevirt-lab/
│   │   ├── gpu-lab/
│   │   └── full-stack/
│   ├── environments/
│   │   ├── shared/
│   │   │   ├── main.tf
│   │   │   └── terraform.tfvars
│   │   └── labs/
│   │       └── main.tf            # Dynamic workspace config
│   └── scripts/
│       ├── lab-provision.sh
│       ├── lab-status.sh
│       ├── lab-connect.sh
│       └── lab-destroy.sh
├── packer/                        # AMI builds
│   ├── k0rdent-base.pkr.hcl
│   ├── k0rdent-metal3.pkr.hcl
│   └── k0rdent-gpu.pkr.hcl
└── README.md
```

### C. Prerequisites Checklist

Before implementation:

- [ ] AWS account with appropriate permissions
- [ ] P4d instance quota increased (default is 0)
- [ ] VPC CIDR approved (no conflicts)
- [ ] S3 bucket names available
- [ ] Engineers have AWS CLI configured
- [ ] Budget approved (~$12,500 per cohort)

---

## Review Questions

Before proceeding to implementation, please confirm:

1. **VPC CIDR:** Is 10.0.0.0/16 acceptable, or do you need different addressing?
2. **AWS Region:** Which region should we deploy to? (Consider P4d availability)
3. **Spot vs On-Demand:** Acceptable to use spot for GPU labs?
4. **SSH Access:** Bastion host approach OK, or prefer other method (SSM, etc.)?
5. **AMI Management:** Can we create custom AMIs in your account?
6. **Budget:** Is ~$12,500 per cohort acceptable for GPU time?

---

*Document prepared for architecture review. Please provide feedback before implementation begins.*
