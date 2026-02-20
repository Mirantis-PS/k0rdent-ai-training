# k0rdent AI Training Lab Infrastructure - Architecture Design

**Version:** 2.0
**Date:** December 2025
**Status:** Draft for Review

> **Note (February 2026):** The infrastructure has been refactored from a shared multi-tenant model to per-student isolation. The current implementation uses a single `environments/student-lab/` with feature flags (`--gpu`, `--metal3`, `--kubevirt`) instead of separate environments. Each student gets their own VPC, bastion, S3 bucket, and k0rdent cluster. See the [Lab Infrastructure README](../README.md) for current usage. The architectural concepts in this document (GitOps, progressive learning, weekly progression) remain valid.

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Requirements](#2-requirements)
3. [Architecture Overview](#3-architecture-overview)
4. [k0rdent Management Cluster](#4-k0rdent-management-cluster)
5. [Target Infrastructure by Week](#5-target-infrastructure-by-week)
6. [GitOps State Management](#6-gitops-state-management)
7. [AWS Infrastructure Design](#7-aws-infrastructure-design)
8. [Networking Design](#8-networking-design)
9. [Automation & Provisioning](#9-automation--provisioning)
10. [Security Design](#10-security-design)
11. [Cost Management](#11-cost-management)
12. [Implementation Roadmap](#12-implementation-roadmap)
13. [Appendix](#appendix)

---

## 1. Executive Summary

### Mission

Train engineers to confidently deploy **k0rdent AI** for customers in professional services engagements through hands-on lab experience that mirrors real deployments.

### Purpose

This document defines the architecture for a k0rdent AI training lab platform where engineers provision and manage actual k0rdent clusters, experiencing the full lifecycle of deployment, configuration, and workload management across bare metal, virtual machines, and Kubernetes.

### Scope

- **Training Focus:** k0rdent AI deployment for professional services
- **Cloud Provider:** AWS (single VPC, on-demand instances)
- **State Management:** GitOps via Flux CD with personal forks
- **Isolation:** Fully isolated per-engineer environments
- **Persistence:** Weekly state via declarative git configuration
- **Target Users:** 5-15 engineers per training cohort

### Key Architectural Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Management Cluster | 3-node k0s on EC2 per engineer | Mirrors production k0rdent deployments |
| Installation | Semi-automated scripts + manual final install | Engineers learn the process |
| Week Progression | Same cluster adds capabilities | Build expertise incrementally |
| CAPI Providers | Metal3 → KubeVirt → CAPA | Cover all k0rdent AI deployment targets |
| Networking | Single VPC subnet | Simplicity without sacrificing learning |
| State Persistence | GitOps (Flux CD) | Declarative rebuild, self-service recovery |
| Secrets | SOPS + age encrypted in git | Industry-standard GitOps pattern |
| Git Repos | Internal repo, personal forks | Controlled access, individual progress |
| Instance Pricing | On-demand | Reliability for training (no spot interruptions) |

---

## 2. Requirements

### Functional Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| FR-1 | Engineers provision their own k0rdent management cluster | P0 |
| FR-2 | Management cluster progressively adds providers (Metal3, KubeVirt, CAPA) | P0 |
| FR-3 | Engineers provision child clusters using k0rdent/CAPI | P0 |
| FR-4 | State persists within a week via GitOps | P0 |
| FR-5 | Self-service recovery from git history | P0 |
| FR-6 | Simulated bare metal environment for BMaaS labs | P0 |
| FR-7 | GPU-enabled child clusters for AI workloads | P0 |
| FR-8 | Full isolation between engineers | P1 |
| FR-9 | Rebuild environment in 15-20 minutes | P1 |

### Non-Functional Requirements

| ID | Requirement | Target |
|----|-------------|--------|
| NFR-1 | Environment rebuild time | < 20 minutes |
| NFR-2 | Concurrent engineer environments | Up to 15 |
| NFR-3 | Environment availability | 99% during business hours |
| NFR-4 | Weekly state retention | 100% via git |
| NFR-5 | Self-service recovery success | > 95% |

### Constraints

- AWS account with GPU quota (P3/P4d instances)
- Internal git repository with engineer access managed manually
- Engineers must have: AWS CLI, kubectl, git, SOPS/age configured
- SOPS + age keys distributed to engineers for secrets decryption

---

## 3. Architecture Overview

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           AWS Account (Shared VPC)                           │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │                    VPC: 10.0.0.0/16 (Single Subnet)                    │ │
│  │                                                                        │ │
│  │  ┌─────────────┐                                                       │ │
│  │  │   Bastion   │    Shared infrastructure (deployed once)              │ │
│  │  │  (shared)   │    - S3: Terraform state, images, artifacts           │ │
│  │  └──────┬──────┘    - IAM: CAPA credentials for child provisioning     │ │
│  │         │                                                               │ │
│  │         │                                                               │ │
│  │  ┌──────┴─────────────────────────────────────────────────────────────┐│ │
│  │  │              Per-Engineer Environment (Fully Isolated)              ││ │
│  │  │                                                                     ││ │
│  │  │  ┌─────────────────────────────────────────────────────────────┐   ││ │
│  │  │  │         k0rdent Management Cluster (3-node k0s)             │   ││ │
│  │  │  │         ┌─────────┐  ┌─────────┐  ┌─────────┐               │   ││ │
│  │  │  │         │ k0s-cp1 │  │ k0s-cp2 │  │ k0s-cp3 │               │   ││ │
│  │  │  │         │ t3.xl   │  │ t3.xl   │  │ t3.xl   │               │   ││ │
│  │  │  │         └────┬────┘  └────┬────┘  └────┬────┘               │   ││ │
│  │  │  │              └────────────┼────────────┘                    │   ││ │
│  │  │  │                           │                                 │   ││ │
│  │  │  │              ┌────────────┴────────────┐                    │   ││ │
│  │  │  │              │      k0rdent + Flux     │                    │   ││ │
│  │  │  │              │  ┌──────────────────┐   │                    │   ││ │
│  │  │  │              │  │ Providers:       │   │                    │   ││ │
│  │  │  │              │  │ • Metal3 (W2)    │   │                    │   ││ │
│  │  │  │              │  │ • KubeVirt (W3)  │   │                    │   ││ │
│  │  │  │              │  │ • CAPA (W4+)     │   │                    │   ││ │
│  │  │  │              │  └──────────────────┘   │                    │   ││ │
│  │  │  │              └─────────────────────────┘                    │   ││ │
│  │  │  └─────────────────────────────────────────────────────────────┘   ││ │
│  │  │                              │ Manages                              ││ │
│  │  │                              ▼                                      ││ │
│  │  │  ┌─────────────────────────────────────────────────────────────┐   ││ │
│  │  │  │              Target Infrastructure (varies by week)          │   ││ │
│  │  │  │                                                              │   ││ │
│  │  │  │  Week 2: Bare Metal Simulator (m5.2xlarge + libvirt)        │   ││ │
│  │  │  │          └── 3 simulated BM nodes + Virtual BMC              │   ││ │
│  │  │  │                                                              │   ││ │
│  │  │  │  Week 3: KubeVirt child cluster (provisioned by k0rdent)    │   ││ │
│  │  │  │          └── VMs running on KubeVirt                         │   ││ │
│  │  │  │                                                              │   ││ │
│  │  │  │  Week 4: AWS child clusters (provisioned via CAPA)          │   ││ │
│  │  │  │          └── EC2 instances managed by Cluster API            │   ││ │
│  │  │  │                                                              │   ││ │
│  │  │  │  Week 5: GPU-enabled child cluster (on shared GPU pool)     │   ││ │
│  │  │  │          └── AI workloads: vLLM, Run:AI, Kubeflow           │   ││ │
│  │  │  └─────────────────────────────────────────────────────────────┘   ││ │
│  │  └─────────────────────────────────────────────────────────────────────┘│ │
│  │                                                                        │ │
│  │  ┌────────────────────────────────────────────────────────────────────┐│ │
│  │  │               Shared GPU Pool (p3.8xlarge / p4d.24xlarge)          ││ │
│  │  │               k0rdent provisions child clusters here via CAPA      ││ │
│  │  └────────────────────────────────────────────────────────────────────┘│ │
│  └────────────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────┘

                    ┌─────────────────────────────────────┐
                    │    Internal Git Repository           │
                    │                                      │
                    │  k0rdent-lab-template (upstream)     │
                    │           │                          │
                    │           ▼ fork                     │
                    │  engineer-01/k0rdent-lab (personal)  │
                    │  ├── clusters/                       │
                    │  │   ├── management/                 │
                    │  │   ├── week2-bmaas/                │
                    │  │   ├── week3-vmaas/                │
                    │  │   ├── week4-kaas/                 │
                    │  │   └── week5-gpu/                  │
                    │  ├── infrastructure/                 │
                    │  └── flux-system/                    │
                    └─────────────────────────────────────┘
```

### Week-by-Week Progression

| Week | Management Cluster | Providers Added | Child Clusters Provisioned |
|------|-------------------|-----------------|---------------------------|
| 1 | Deploy 3-node k0s + k0rdent + Flux | Base k0rdent | None (setup week) |
| 2 | + | Metal3 + Ironic | BMaaS cluster on simulated bare metal |
| 3 | + | KubeVirt provider | VMaaS cluster on KubeVirt VMs |
| 4 | + | CAPA (AWS) provider | KaaS clusters on EC2 |
| 5 | + | (reuse CAPA) | GPU-enabled cluster on shared p3/p4d |
| 6 | Full stack | All providers | Multi-tenant capstone |

### Core Architectural Principles

1. **Engineers Own Their Clusters**: Each engineer provisions and manages their own k0rdent management cluster
2. **Progressive Learning**: Same cluster evolves, adding capabilities each week
3. **GitOps-First**: All cluster state is declarative and stored in git
4. **Production-Like**: Architecture mirrors real k0rdent AI deployments
5. **Self-Service Recovery**: Engineers can reset to any known-good state via git

---

## 4. k0rdent Management Cluster

### Cluster Specification

Each engineer's k0rdent management cluster consists of:

```
┌─────────────────────────────────────────────────────────────────┐
│                k0rdent Management Cluster                        │
│                                                                 │
│  3x t3.xlarge EC2 instances (on-demand)                         │
│  ├── 4 vCPU, 16GB RAM per node                                  │
│  └── 100GB gp3 root volume per node                             │
│                                                                 │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐             │
│  │   Node 1    │  │   Node 2    │  │   Node 3    │             │
│  │ controller  │  │ controller  │  │ controller  │             │
│  │ + worker    │  │ + worker    │  │ + worker    │             │
│  │ + etcd      │  │ + etcd      │  │ + etcd      │             │
│  └─────────────┘  └─────────────┘  └─────────────┘             │
│                                                                 │
│  Installed Components:                                          │
│  ├── k0s v1.32.4+k0s.0 (HA control plane)                      │
│  ├── k0rdent (cluster management)                               │
│  ├── Flux CD (GitOps controller)                                │
│  ├── cert-manager (certificates)                                │
│  └── SOPS/age integration (secrets decryption)                  │
│                                                                 │
│  Providers (added progressively):                               │
│  ├── Week 2: Metal3 + Ironic                                   │
│  ├── Week 3: KubeVirt (Cluster API provider)                   │
│  └── Week 4+: CAPA (Cluster API Provider for AWS)              │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Installation Flow

```
┌─────────────────────────────────────────────────────────────────┐
│              Management Cluster Installation Flow                │
│                                                                 │
│  Phase 1: Infrastructure (Automated)                            │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  lab-provision.sh mgmt <engineer-id>                     │   │
│  │  └── Terraform creates:                                  │   │
│  │      • 3x EC2 instances                                  │   │
│  │      • Security groups                                   │   │
│  │      • SSH keys                                          │   │
│  │      • cloud-init prepares nodes                         │   │
│  └─────────────────────────────────────────────────────────┘   │
│                            │                                    │
│                            ▼                                    │
│  Phase 2: k0s Cluster (Semi-Automated)                         │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Script generates k0sctl.yaml from Terraform outputs     │   │
│  │  Engineer runs: k0sctl apply --config k0sctl.yaml        │   │
│  │  └── Creates HA k0s cluster                              │   │
│  └─────────────────────────────────────────────────────────┘   │
│                            │                                    │
│                            ▼                                    │
│  Phase 3: k0rdent + Flux (Manual with Guidance)                │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Engineer follows lab instructions:                      │   │
│  │  1. Install Flux CD                                      │   │
│  │  2. Configure git repository connection                  │   │
│  │  3. Bootstrap k0rdent from their fork                    │   │
│  │  4. Verify Flux reconciliation                           │   │
│  └─────────────────────────────────────────────────────────┘   │
│                            │                                    │
│                            ▼                                    │
│  Phase 4: Provider Installation (Weekly, Manual)               │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Engineer commits provider manifests to git              │   │
│  │  Flux automatically reconciles:                          │   │
│  │  • Week 2: Metal3 + Ironic provider                     │   │
│  │  • Week 3: KubeVirt provider                            │   │
│  │  • Week 4: CAPA provider                                │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Terraform Variables

```hcl
variable "k0rdent_mgmt" {
  type = object({
    node_count        = number
    instance_type     = string
    root_volume_size  = number
    k0s_version       = string
    k0rdent_version   = string
  })
  default = {
    node_count        = 3
    instance_type     = "t3.xlarge"
    root_volume_size  = 100
    k0s_version       = "v1.32.4+k0s.0"
    k0rdent_version   = "latest"
  }
}
```

---

## 5. Target Infrastructure by Week

### 5.1 Week 2: Bare Metal Simulator (BMaaS)

**Purpose:** Simulate bare metal provisioning with Metal3 + Ironic

```
┌─────────────────────────────────────────────────────────────────┐
│                  Bare Metal Simulator                            │
│                                                                 │
│  AWS Instance: m5.2xlarge (8 vCPU, 32GB RAM)                    │
│  └── Nested virtualization enabled                              │
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │                    libvirt Host                            │ │
│  │                                                            │ │
│  │  Simulated Bare Metal Nodes (VMs):                        │ │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────┐                   │ │
│  │  │  bm-01  │  │  bm-02  │  │  bm-03  │                   │ │
│  │  │ 4vCPU   │  │ 4vCPU   │  │ 4vCPU   │                   │ │
│  │  │ 8GB RAM │  │ 8GB RAM │  │ 8GB RAM │                   │ │
│  │  │ 50GB    │  │ 50GB    │  │ 50GB    │                   │ │
│  │  └────┬────┘  └────┬────┘  └────┬────┘                   │ │
│  │       │            │            │                         │ │
│  │       └────────────┼────────────┘                         │ │
│  │                    │                                       │ │
│  │  ┌─────────────────┴─────────────────┐                    │ │
│  │  │       Virtual BMC (Sushy Tools)    │                    │ │
│  │  │  • Redfish API endpoints           │                    │ │
│  │  │  • Power management simulation     │                    │ │
│  │  │  • Boot device control             │                    │ │
│  │  └───────────────────────────────────┘                    │ │
│  │                    ▲                                       │ │
│  └────────────────────┼───────────────────────────────────────┘ │
│                       │                                         │
│  Network exposure:    │                                         │
│  └── Sushy API accessible from k0rdent management cluster      │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**k0rdent Workflow:**
1. Metal3 provider discovers simulated BMHs via Redfish
2. Engineer creates BareMetalHost resources in git
3. Flux reconciles, Metal3 provisions the nodes
4. Ironic handles PXE boot and OS installation
5. Cluster API creates Kubernetes cluster on provisioned nodes

**Terraform Variables:**

```hcl
variable "bare_metal_sim" {
  type = object({
    instance_type     = string
    root_volume_size  = number
    num_bm_nodes      = number
    bm_node_vcpu      = number
    bm_node_ram_gb    = number
    bm_node_disk_gb   = number
  })
  default = {
    instance_type     = "m5.2xlarge"
    root_volume_size  = 200
    num_bm_nodes      = 3
    bm_node_vcpu      = 4
    bm_node_ram_gb    = 8
    bm_node_disk_gb   = 50
  }
}
```

---

### 5.2 Week 3: KubeVirt Child Cluster (VMaaS)

**Purpose:** Provision Kubernetes clusters on VMs via KubeVirt

```
┌─────────────────────────────────────────────────────────────────┐
│                  KubeVirt Infrastructure                         │
│                                                                 │
│  Runs on: Management cluster nodes (or dedicated workers)       │
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │           KubeVirt-Provisioned Child Cluster               │ │
│  │                                                            │ │
│  │  ┌────────────────┐  ┌────────────────┐                   │ │
│  │  │ VM: cp-node    │  │ VM: worker-01  │                   │ │
│  │  │ Control Plane  │  │ Worker Node    │                   │ │
│  │  │ 4 vCPU, 8GB    │  │ 4 vCPU, 8GB    │                   │ │
│  │  └────────────────┘  └────────────────┘                   │ │
│  │                                                            │ │
│  │  Installed: k0s, CNI, CSI                                 │ │
│  │  Managed by: k0rdent via KubeVirt CAPI provider           │ │
│  └───────────────────────────────────────────────────────────┘ │
│                                                                 │
│  Components on Management Cluster:                              │
│  ├── KubeVirt Operator                                         │
│  ├── CDI (Containerized Data Importer)                         │
│  ├── KubeVirt CAPI Provider                                    │
│  └── VM images stored in PVCs                                  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**k0rdent Workflow:**
1. Engineer enables KubeVirt provider in git
2. Flux installs KubeVirt operator on management cluster
3. Engineer creates KubeVirtCluster resources in git
4. k0rdent provisions VMs and bootstraps Kubernetes
5. Child cluster kubeconfig available for workload deployment

---

### 5.3 Week 4: AWS Child Clusters (KaaS)

**Purpose:** Provision Kubernetes clusters on AWS via CAPA

```
┌─────────────────────────────────────────────────────────────────┐
│                  CAPA-Provisioned Clusters                       │
│                                                                 │
│  k0rdent Management Cluster                                     │
│  └── CAPA Provider (Cluster API Provider for AWS)              │
│      └── IAM credentials via SOPS-encrypted secrets            │
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │              Child Cluster: aws-cluster-01                 │ │
│  │                                                            │ │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐       │ │
│  │  │ EC2: cp-0   │  │ EC2: wk-0   │  │ EC2: wk-1   │       │ │
│  │  │ t3.large    │  │ t3.large    │  │ t3.large    │       │ │
│  │  │ Ctrl Plane  │  │ Worker      │  │ Worker      │       │ │
│  │  └─────────────┘  └─────────────┘  └─────────────┘       │ │
│  │                                                            │ │
│  │  Created in same VPC as management cluster                │ │
│  │  Security groups auto-configured by CAPA                  │ │
│  └───────────────────────────────────────────────────────────┘ │
│                                                                 │
│  Multiple clusters can be provisioned for multi-cluster labs   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**k0rdent Workflow:**
1. Engineer enables CAPA provider in git (Week 4)
2. AWS credentials stored as SOPS-encrypted secret
3. Engineer creates AWSCluster + related resources in git
4. Flux reconciles, CAPA provisions EC2 instances
5. k0s bootstrapped on instances via cloud-init
6. Child cluster registered with k0rdent

---

### 5.4 Week 5: GPU-Enabled Child Clusters (AI Workloads)

**Purpose:** Deploy k0rdent AI workloads on GPU infrastructure

```
┌─────────────────────────────────────────────────────────────────┐
│                  GPU Child Cluster                               │
│                                                                 │
│  Shared GPU Pool: p3.8xlarge (4x V100) or p4d.24xlarge (8x A100)│
│  └── Multiple engineers share pool via k0rdent scheduling      │
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │           GPU-Enabled Child Cluster                        │ │
│  │                                                            │ │
│  │  Provisioned by: k0rdent via CAPA                         │ │
│  │  Instance: Access to shared GPU pool                       │ │
│  │                                                            │ │
│  │  Pre-installed:                                            │ │
│  │  ├── NVIDIA GPU Operator (v25.10.0)                       │ │
│  │  │   ├── nvidia-driver-daemonset                          │ │
│  │  │   ├── nvidia-device-plugin                             │ │
│  │  │   └── dcgm-exporter                                    │ │
│  │  │                                                         │ │
│  │  └── AI Workload Components:                               │ │
│  │      ├── vLLM (v0.11.2) - LLM inference                   │ │
│  │      ├── Run:AI (v5.x) - GPU orchestration                │ │
│  │      ├── Kubeflow - ML platform                           │ │
│  │      └── MLflow - Experiment tracking                     │ │
│  │                                                            │ │
│  └───────────────────────────────────────────────────────────┘ │
│                                                                 │
│  This is the core "k0rdent AI" experience:                     │
│  └── Engineers learn to deploy AI infrastructure for customers │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**k0rdent AI Workflow:**
1. Engineer creates GPU cluster definition in git
2. k0rdent provisions cluster on shared GPU pool via CAPA
3. GPU Operator automatically configures drivers
4. Engineer deploys AI workloads (vLLM, Run:AI, etc.)
5. Experience mirrors customer k0rdent AI deployments

---

### 5.5 Week 6: Multi-Tenant Capstone

**Purpose:** Full k0rdent AI deployment with multi-tenancy

```
┌─────────────────────────────────────────────────────────────────┐
│                  Capstone Environment                            │
│                                                                 │
│  Management Cluster (fully configured from Weeks 1-5)           │
│  ├── All providers: Metal3, KubeVirt, CAPA                     │
│  ├── Service catalog populated                                  │
│  └── RBAC and tenant isolation configured                      │
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │                   Tenant: techcorp-ai                      │ │
│  │                                                            │ │
│  │  ├── Tenant namespace with RBAC                           │ │
│  │  ├── Resource quotas                                       │ │
│  │  ├── Network policies                                      │ │
│  │  └── Allocated clusters:                                   │ │
│  │      ├── dev-cluster (KubeVirt)                           │ │
│  │      ├── staging-cluster (AWS)                            │ │
│  │      └── prod-cluster (GPU-enabled)                       │ │
│  │                                                            │ │
│  └───────────────────────────────────────────────────────────┘ │
│                                                                 │
│  Engineers demonstrate:                                         │
│  ├── Tenant onboarding                                         │
│  ├── Cluster provisioning via service catalog                  │
│  ├── AI workload deployment                                    │
│  └── Monitoring and troubleshooting                            │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 6. GitOps State Management

### 6.1 Repository Structure

**Template Repository:** `k0rdent-lab-template` (internal, upstream)

Engineers fork this to create their personal repository.

```
k0rdent-lab-template/
├── README.md                           # Setup instructions
├── clusters/
│   ├── management/
│   │   ├── kustomization.yaml          # Flux kustomization
│   │   ├── k0rdent-config.yaml         # k0rdent base config
│   │   ├── flux-system/                # Flux components
│   │   │   ├── gotk-components.yaml
│   │   │   ├── gotk-sync.yaml
│   │   │   └── kustomization.yaml
│   │   └── infrastructure/
│   │       ├── cert-manager.yaml
│   │       └── sops-config.yaml
│   │
│   ├── week2-bmaas/
│   │   ├── kustomization.yaml
│   │   ├── providers/
│   │   │   ├── metal3-provider.yaml
│   │   │   └── ironic-config.yaml
│   │   └── clusters/
│   │       └── bm-cluster-01.yaml      # BareMetalHost + Cluster
│   │
│   ├── week3-vmaas/
│   │   ├── kustomization.yaml
│   │   ├── providers/
│   │   │   └── kubevirt-provider.yaml
│   │   └── clusters/
│   │       └── vm-cluster-01.yaml
│   │
│   ├── week4-kaas/
│   │   ├── kustomization.yaml
│   │   ├── providers/
│   │   │   └── capa-provider.yaml
│   │   └── clusters/
│   │       ├── aws-cluster-01.yaml
│   │       └── aws-cluster-02.yaml
│   │
│   └── week5-gpu/
│       ├── kustomization.yaml
│       ├── clusters/
│       │   └── gpu-cluster-01.yaml
│       └── workloads/
│           ├── vllm-deployment.yaml
│           ├── runai-config.yaml
│           └── kubeflow-profile.yaml
│
├── infrastructure/
│   ├── namespaces.yaml
│   ├── rbac.yaml
│   └── network-policies.yaml
│
├── secrets/                            # SOPS-encrypted
│   ├── .sops.yaml                      # SOPS configuration
│   ├── aws-credentials.yaml            # CAPA credentials (encrypted)
│   ├── git-credentials.yaml            # Flux git access (encrypted)
│   └── bmc-credentials.yaml            # Virtual BMC passwords (encrypted)
│
└── scripts/
    ├── setup-flux.sh                   # Flux bootstrap helper
    ├── setup-sops.sh                   # SOPS configuration
    └── verify-state.sh                 # State verification
```

### 6.2 Flux CD Configuration

```yaml
# clusters/management/flux-system/gotk-sync.yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: k0rdent-lab
  namespace: flux-system
spec:
  interval: 1m
  url: https://git.internal.company.com/${ENGINEER}/k0rdent-lab
  ref:
    branch: main
  secretRef:
    name: git-credentials
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: management
  namespace: flux-system
spec:
  interval: 5m
  path: ./clusters/management
  prune: true
  sourceRef:
    kind: GitRepository
    name: k0rdent-lab
  decryption:
    provider: sops
    secretRef:
      name: sops-age
```

### 6.3 SOPS + age Configuration

```yaml
# secrets/.sops.yaml
creation_rules:
  - path_regex: .*\.yaml$
    age: >-
      age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
    # Engineer's public key - private key stored locally
```

**Encrypted Secret Example:**

```yaml
# secrets/aws-credentials.yaml (encrypted)
apiVersion: v1
kind: Secret
metadata:
  name: aws-credentials
  namespace: capa-system
type: Opaque
stringData:
  AWS_ACCESS_KEY_ID: ENC[AES256_GCM,data:xxxxx,iv:xxxxx,tag:xxxxx]
  AWS_SECRET_ACCESS_KEY: ENC[AES256_GCM,data:xxxxx,iv:xxxxx,tag:xxxxx]
sops:
  age:
    - recipient: age1xxxxxxxxx
      enc: |
        -----BEGIN AGE ENCRYPTED FILE-----
        ...
        -----END AGE ENCRYPTED FILE-----
```

### 6.4 Session Rebuild Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                   Session Rebuild Flow (15-20 min)               │
│                                                                 │
│  1. Engineer runs: lab-provision.sh mgmt <engineer-id>          │
│     └── Terraform creates EC2 instances                         │
│     └── cloud-init prepares nodes (packages, config)            │
│                                                                 │
│  2. Script generates k0sctl.yaml from outputs                   │
│     └── Engineer runs: k0sctl apply                             │
│     └── k0s cluster created                                     │
│                                                                 │
│  3. Engineer bootstraps Flux:                                   │
│     └── flux bootstrap git \                                    │
│           --url=https://git.internal/engineer/k0rdent-lab \     │
│           --path=clusters/management                            │
│                                                                 │
│  4. Flux reconciles from git:                                   │
│     └── k0rdent installed                                       │
│     └── Providers installed (based on week progress)            │
│     └── Child clusters recreated                                │
│     └── Workloads deployed                                      │
│                                                                 │
│  5. Environment ready for labs                                  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 6.5 Self-Service Recovery

When an engineer breaks their cluster:

```bash
# Option 1: Reset to last known-good commit
git log --oneline                    # Find good commit
git reset --hard <commit-hash>
git push --force origin main

# Flux will reconcile to previous state

# Option 2: Full teardown and rebuild
lab-destroy.sh mgmt <engineer-id>
lab-provision.sh mgmt <engineer-id>
# Re-bootstrap Flux (state restored from git)
```

---

## 7. AWS Infrastructure Design

### 7.1 Shared Infrastructure

Deployed once, used by all engineer environments.

```
┌─────────────────────────────────────────────────────────────────┐
│                    Shared Infrastructure                         │
│                                                                 │
│  VPC: 10.0.0.0/16                                               │
│  ├── Single subnet: 10.0.0.0/20 (4,094 IPs)                    │
│  └── Internet Gateway + NAT (for private instances)             │
│                                                                 │
│  S3 Buckets (per-student, per-region):                           │
│  └── k0rdent-lab-<id>-<account>-<region> # State/artifacts      │
│                                                                 │
│  IAM:                                                           │
│  ├── k0rdent-lab-provisioner       # For Terraform             │
│  ├── k0rdent-lab-instance          # EC2 instance role         │
│  ├── k0rdent-capa-controller       # CAPA credentials          │
│  └── k0rdent-lab-admin             # Instructor access         │
│                                                                 │
│  Bastion Host:                                                  │
│  └── t3.micro, public IP, SSH access to all instances          │
│                                                                 │
│  Shared GPU Pool:                                               │
│  ├── p3.8xlarge (4x V100) - standard GPU labs                  │
│  └── p4d.24xlarge (8x A100) - advanced GPU sessions            │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 7.2 Instance Types

| Component | Instance Type | vCPU | RAM | GPU | On-Demand $/hr |
|-----------|--------------|------|-----|-----|----------------|
| Management cluster node | t3.xlarge | 4 | 16GB | - | $0.17 |
| Bare metal simulator | m5.2xlarge | 8 | 32GB | - | $0.38 |
| CAPA child node | t3.large | 2 | 8GB | - | $0.08 |
| GPU pool (standard) | p3.8xlarge | 32 | 244GB | 4x V100 | $12.24 |
| GPU pool (advanced) | p4d.24xlarge | 96 | 1152GB | 8x A100 | $32.77 |
| Bastion | t3.micro | 2 | 1GB | - | $0.01 |

### 7.3 Terraform Module Structure

```
terraform/
├── modules/
│   ├── networking/             # VPC, subnets, NAT, security groups
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   │
│   ├── iam/                    # IAM roles, policies, instance profiles
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   │
│   ├── bastion/                # SSH jump host
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   │
│   ├── k0rdent-mgmt/           # NEW: 3-node k0s management cluster
│   │   ├── main.tf
│   │   ├── k0sctl-template.tf
│   │   ├── templates/
│   │   │   └── mgmt-cloud-init.yaml
│   │   ├── variables.tf
│   │   └── outputs.tf
│   │
│   ├── bare-metal-sim/         # NEW: Enhanced for k0rdent integration
│   │   ├── main.tf
│   │   ├── templates/
│   │   │   └── bm-sim-cloud-init.yaml
│   │   ├── variables.tf
│   │   └── outputs.tf
│   │
│   └── gpu-pool/               # NEW: Shared GPU instances
│       ├── main.tf
│       ├── templates/
│       │   └── gpu-cloud-init.yaml
│       ├── variables.tf
│       └── outputs.tf
│
├── environments/
│   ├── shared/                 # Shared infrastructure
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── terraform.tfvars
│   │
│   └── engineer/               # Per-engineer environments
│       ├── main.tf             # Calls k0rdent-mgmt, bare-metal-sim
│       ├── variables.tf
│       └── backend.tf.tmpl     # Template for S3 backend config
│
└── config/                     # Local configs (gitignored)
    └── <engineer-id>.tfvars
```

---

## 8. Networking Design

### 8.1 Simplified Single-Subnet Topology

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              AWS VPC: 10.0.0.0/16                            │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                    Single Subnet: 10.0.0.0/20                        │   │
│  │                    (4,094 usable IPs)                                │   │
│  │                                                                      │   │
│  │  ┌──────────────┐                                                   │   │
│  │  │   Bastion    │ ◄── Public IP, SSH from allowed IPs               │   │
│  │  │  10.0.0.10   │                                                   │   │
│  │  └──────────────┘                                                   │   │
│  │         │                                                            │   │
│  │         │ SSH                                                        │   │
│  │         ▼                                                            │   │
│  │  ┌──────────────────────────────────────────────────────────────┐   │   │
│  │  │              Engineer: engineer-01                            │   │   │
│  │  │                                                               │   │   │
│  │  │  Management Cluster:                                          │   │   │
│  │  │  ├── 10.0.0.20 (k0s-cp1)                                     │   │   │
│  │  │  ├── 10.0.0.21 (k0s-cp2)                                     │   │   │
│  │  │  └── 10.0.0.22 (k0s-cp3)                                     │   │   │
│  │  │                                                               │   │   │
│  │  │  Bare Metal Simulator:                                        │   │   │
│  │  │  └── 10.0.0.30 (libvirt host, Sushy API)                     │   │   │
│  │  │                                                               │   │   │
│  │  │  CAPA Child Clusters:                                         │   │   │
│  │  │  └── 10.0.0.40-49 (dynamically allocated)                    │   │   │
│  │  │                                                               │   │   │
│  │  └──────────────────────────────────────────────────────────────┘   │   │
│  │                                                                      │   │
│  │  ┌──────────────────────────────────────────────────────────────┐   │   │
│  │  │              Shared GPU Pool                                  │   │   │
│  │  │  ├── 10.0.0.200 (p3.8xlarge)                                 │   │   │
│  │  │  └── 10.0.0.201 (p4d.24xlarge - when needed)                 │   │   │
│  │  └──────────────────────────────────────────────────────────────┘   │   │
│  │                                                                      │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  Internet Gateway + NAT for outbound traffic                                │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 8.2 Security Groups

| Security Group | Inbound Rules | Used By |
|----------------|---------------|---------|
| `sg-bastion` | 22/TCP from allowed IPs | Bastion host |
| `sg-k0rdent-mgmt` | 22/TCP from bastion, 6443/TCP from VPC, all from self | Management cluster |
| `sg-bare-metal-sim` | 22/TCP from bastion, 8000/TCP (Sushy) from mgmt, all from self | BM simulator |
| `sg-capa-child` | 22/TCP from bastion, 6443/TCP from VPC, all from self | CAPA-provisioned nodes |
| `sg-gpu-pool` | 22/TCP from bastion, 6443/TCP from VPC, all from self | GPU instances |

### 8.3 Communication Flows

```
┌─────────────────────────────────────────────────────────────────┐
│                    Communication Flows                           │
│                                                                 │
│  Engineer Workstation                                           │
│       │                                                         │
│       │ SSH (22)                                                │
│       ▼                                                         │
│  Bastion ────────────────────────────────────────────────────►  │
│       │          SSH to all instances                           │
│       │                                                         │
│  Management Cluster ◄─────────────────────────────────────────  │
│       │              Flux syncs from git                        │
│       │                                                         │
│       ├──► Bare Metal Simulator (Redfish API: 8000)            │
│       │    └── Metal3 manages simulated BMHs                    │
│       │                                                         │
│       ├──► KubeVirt VMs (internal)                              │
│       │    └── CAPI provisions VMs on management cluster        │
│       │                                                         │
│       ├──► CAPA Child Clusters (6443)                           │
│       │    └── CAPI provisions EC2 instances                    │
│       │                                                         │
│       └──► GPU Pool (6443)                                      │
│            └── CAPI provisions GPU clusters                     │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 9. Automation & Provisioning

### 9.1 Provisioning Scripts

#### lab-provision.sh

```bash
#!/bin/bash
# Usage: lab-provision.sh <component> <engineer-id> [options]
#
# Components:
#   shared          Provision shared infrastructure (admin only)
#   mgmt            Provision k0rdent management cluster
#   bm-sim          Provision bare metal simulator (Week 2)
#   gpu-pool        Provision shared GPU pool (admin only)
#   all             Provision mgmt + bm-sim for an engineer
#
# Options:
#   --auto-approve   Skip confirmation prompts
#   --plan-only      Show Terraform plan without applying
#   --region <r>     AWS region (default: us-east-1)
#
# Examples:
#   lab-provision.sh john-doe --region us-east-1 --auto-approve  # Base lab
#   lab-provision.sh john-doe --gpu                              # Add GPU support
#   lab-provision.sh john-doe --metal3 --kubevirt                # Add Metal3 + KubeVirt
```

**Outputs:**
- SSH private key (saved to `~/.k0rdent-lab/<engineer>/`)
- k0sctl.yaml configuration file
- Connection instructions

#### lab-connect.sh

```bash
#!/bin/bash
# Usage: lab-connect.sh <your-name> [options]
#
# Options:
#   --copy-kubeconfig   Download kubeconfig instead of SSH
#   --show-password     Show k0rdent UI password
#   --tunnel <L:R>      Create SSH tunnel
#
# Examples:
#   lab-connect.sh john-doe                      # SSH to management cluster
#   lab-connect.sh john-doe --copy-kubeconfig    # Download kubeconfig
#   lab-connect.sh john-doe --show-password      # Show UI password
```

#### lab-status.sh

```bash
#!/bin/bash
# Usage: lab-status.sh <your-name> [options]
#
# Examples:
#   lab-status.sh john-doe             # Check environment status
#   lab-status.sh john-doe --json      # JSON output for automation
```

#### lab-destroy.sh

```bash
#!/bin/bash
# Usage: lab-destroy.sh <your-name> [options]
#
# Examples:
#   lab-destroy.sh john-doe --auto-approve
#   lab-destroy.sh john-doe --auto-approve --delete-bucket
```

### 9.2 Cloud-Init Templates

#### Management Cluster Node (mgmt-cloud-init.yaml)

```yaml
#cloud-config
package_update: true
packages:
  - docker.io
  - curl
  - jq
  - git

write_files:
  - path: /etc/profile.d/k0rdent-lab.sh
    content: |
      export PATH=$PATH:/usr/local/bin
      alias k=kubectl

runcmd:
  # Install kubectl
  - curl -LO "https://dl.k8s.io/release/v1.32.4/bin/linux/amd64/kubectl"
  - install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

  # Install k0sctl
  - curl -sSLf https://get.k0s.sh | K0S_VERSION=${k0s_version} sh
  - curl -sSLf https://github.com/k0sproject/k0sctl/releases/download/v0.19.0/k0sctl-linux-amd64 -o /usr/local/bin/k0sctl
  - chmod +x /usr/local/bin/k0sctl

  # Install Helm
  - curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

  # Install Flux CLI
  - curl -s https://fluxcd.io/install.sh | bash

  # Install SOPS
  - curl -LO https://github.com/getsops/sops/releases/download/v3.9.0/sops-v3.9.0.linux.amd64
  - install -o root -g root -m 0755 sops-v3.9.0.linux.amd64 /usr/local/bin/sops

  # Install age
  - curl -LO https://github.com/FiloSottile/age/releases/download/v1.2.0/age-v1.2.0-linux-amd64.tar.gz
  - tar -xzf age-v1.2.0-linux-amd64.tar.gz
  - install -o root -g root -m 0755 age/age /usr/local/bin/age
  - install -o root -g root -m 0755 age/age-keygen /usr/local/bin/age-keygen

  # Signal ready
  - touch /var/lib/cloud/instance/lab-ready
```

#### Bare Metal Simulator (bm-sim-cloud-init.yaml)

```yaml
#cloud-config
package_update: true
packages:
  - docker.io
  - qemu-kvm
  - libvirt-daemon-system
  - libvirt-clients
  - virtinst
  - bridge-utils
  - python3-pip
  - python3-libvirt

write_files:
  - path: /etc/libvirt/qemu.conf
    append: true
    content: |
      user = "root"
      group = "root"
      security_driver = "none"

  - path: /opt/bm-sim/create-vms.sh
    permissions: '0755'
    content: |
      #!/bin/bash
      # Create simulated bare metal nodes
      for i in 1 2 3; do
        virt-install \
          --name bm-0$i \
          --ram ${bm_node_ram_mb} \
          --vcpus ${bm_node_vcpu} \
          --disk size=${bm_node_disk_gb},format=qcow2 \
          --os-variant ubuntu22.04 \
          --network bridge=virbr0 \
          --graphics none \
          --boot network,hd \
          --noautoconsole
      done

runcmd:
  # Enable nested virtualization
  - modprobe -r kvm_intel
  - modprobe kvm_intel nested=1

  # Start libvirt
  - systemctl enable --now libvirtd

  # Install sushy-tools (Virtual BMC)
  - pip3 install sushy-tools

  # Create network bridge for VMs
  - virsh net-define /opt/bm-sim/bm-network.xml
  - virsh net-start bm-network
  - virsh net-autostart bm-network

  # Start sushy-emulator (Redfish API)
  - nohup sushy-emulator --interface 0.0.0.0 --port 8000 &

  # Signal ready
  - touch /var/lib/cloud/instance/lab-ready
```

---

## 10. Security Design

### 10.1 Access Control

```
┌─────────────────────────────────────────────────────────────────┐
│                      Access Control Model                        │
│                                                                 │
│  Engineer Workstation                                           │
│  ├── AWS CLI (engineer credentials)                            │
│  │   └── IAM User: engineer-<name>                             │
│  │       └── Policy: k0rdent-lab-engineer                      │
│  │           ├── ec2:* (own resources via tags)                │
│  │           ├── s3:GetObject (images, artifacts)              │
│  │           └── s3:PutObject (state)                          │
│  │                                                              │
│  ├── Git credentials (for internal repo)                       │
│  │   └── Personal access token or SSH key                      │
│  │                                                              │
│  └── age private key (for SOPS decryption)                     │
│      └── Stored locally: ~/.config/sops/age/keys.txt           │
│                                                                 │
│  Lab Instances                                                  │
│  └── IAM Instance Role: k0rdent-lab-instance                   │
│      ├── s3:GetObject (images)                                 │
│      ├── cloudwatch:* (logs, metrics)                          │
│      └── ec2:* (for CAPA - child cluster provisioning)         │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 10.2 SSH Key Management

```
Per-Environment SSH Keys:
1. Terraform generates ED25519 key pair per engineer
2. Public key injected via cloud-init to all instances
3. Private key stored in Terraform state (encrypted S3)
4. lab-connect.sh retrieves from state for SSH
5. Keys deleted on environment destroy
```

### 10.3 Secrets Management with SOPS

```
┌─────────────────────────────────────────────────────────────────┐
│                    SOPS + age Workflow                           │
│                                                                 │
│  1. Admin generates age keypair for cohort                      │
│     └── age-keygen -o cohort-key.txt                           │
│                                                                 │
│  2. Public key added to .sops.yaml in template repo            │
│     └── Engineers can encrypt new secrets                       │
│                                                                 │
│  3. Private key distributed to engineers (secure channel)       │
│     └── Engineers can decrypt secrets locally                   │
│                                                                 │
│  4. Flux decrypts secrets at reconciliation time               │
│     └── SOPS provider configured in Kustomization              │
│                                                                 │
│  Secrets stored encrypted in git:                              │
│  ├── AWS credentials for CAPA                                  │
│  ├── Git credentials for Flux                                  │
│  ├── BMC passwords for Metal3                                  │
│  └── Any other sensitive configuration                         │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 10.4 Network Security

| Control | Implementation |
|---------|----------------|
| SSH via bastion only | Security group rules |
| API access via bastion | Port forwarding or kubectl proxy |
| Egress allowed | NAT Gateway for internet access |
| Inter-engineer isolation | Separate security groups per engineer |
| CAPA child isolation | Dedicated security groups |

---

## 11. Cost Management

### 11.1 Cost Estimates (On-Demand Pricing)

| Component | Instance | $/hr | Per Engineer | Notes |
|-----------|----------|------|--------------|-------|
| Management cluster | 3x t3.xlarge | $0.51 | Individual | 3 nodes × $0.17 |
| Bare metal simulator | m5.2xlarge | $0.38 | Individual | Week 2+ |
| CAPA child nodes | 3x t3.large | $0.24 | Individual | Week 4+ |
| GPU pool (standard) | p3.8xlarge | $12.24 | Shared (5 eng) | Week 5 |
| GPU pool (advanced) | p4d.24xlarge | $32.77 | Shared (all) | Special sessions |
| Bastion | t3.micro | $0.01 | Shared | Always on |

### 11.2 Weekly Cost Estimate (15 engineers)

| Week | Components Active | Hours/Eng | Cost |
|------|-------------------|-----------|------|
| 1 | Mgmt cluster only | 15 | 15 × 15 × $0.51 = $115 |
| 2 | Mgmt + BM simulator | 15 | 15 × 15 × $0.89 = $200 |
| 3 | Mgmt + BM sim + KubeVirt | 15 | 15 × 15 × $0.89 = $200 |
| 4 | Mgmt + BM sim + CAPA children | 15 | 15 × 15 × $1.13 = $254 |
| 5 | All + GPU pool (shared) | 15 | $254 + (3 × 15 × $12.24) = $805 |
| 6 | Full stack | 15 | ~$400 |

**Total 6-Week Estimate: ~$2,000** (excluding buffer)

### 11.3 Cost Controls

1. **On-Demand Only**: Reliable training environment (no spot interruptions)
2. **TTL Enforcement**: Auto-terminate after 8 hours via tags + Lambda
3. **Resource Tagging**: Per-engineer cost tracking
4. **Budget Alerts**: CloudWatch alarms at 50%, 80%, 100%
5. **Shared GPU Pool**: Multiple engineers share expensive GPU instances

### 11.4 Tagging Strategy

```hcl
locals {
  common_tags = {
    Project     = "k0rdent-ai-training"
    Environment = "lab"
    ManagedBy   = "terraform"
  }

  engineer_tags = {
    Engineer    = var.engineer_id
    CostCenter  = "training-${var.cohort_id}"
    TTLHours    = var.ttl_hours
    AutoStop    = "true"
    Week        = var.current_week
  }
}
```

---

## 12. Implementation Roadmap

### Phase 1: Foundation (Week 1)

- [ ] Update networking/iam modules with CAPA IAM roles
- [ ] Create k0rdent-mgmt Terraform module
- [ ] Write mgmt-cloud-init.yaml template
- [ ] Create k0rdent-lab-template git repository
- [ ] Set up SOPS + age configuration
- [ ] Test management cluster provisioning end-to-end

### Phase 2: Bare Metal Simulator (Week 1-2)

- [ ] Create bare-metal-sim Terraform module
- [ ] Write bm-sim-cloud-init.yaml with sushy-tools
- [ ] Configure Virtual BMC exposure to management cluster
- [ ] Create week2-bmaas cluster definitions in template repo
- [ ] Test Metal3 provisioning of simulated bare metal

### Phase 3: KubeVirt Integration (Week 2)

- [ ] Add KubeVirt provider manifests to template repo
- [ ] Create week3-vmaas cluster definitions
- [ ] Test KubeVirt VM provisioning from k0rdent
- [ ] Document KubeVirt child cluster workflow

### Phase 4: CAPA Integration (Week 2)

- [ ] Configure CAPA provider with SOPS-encrypted credentials
- [ ] Create week4-kaas cluster definitions
- [ ] Test CAPA provisioning of EC2-based clusters
- [ ] Document multi-cluster management workflow

### Phase 5: GPU Pool & AI Workloads (Week 3)

- [ ] Create gpu-pool Terraform module
- [ ] Create week5-gpu cluster and workload definitions
- [ ] Configure GPU Operator installation
- [ ] Test vLLM, Run:AI deployments
- [ ] Document k0rdent AI workload deployment

### Phase 6: Capstone & Polish (Week 3)

- [ ] Create week6 multi-tenant configuration
- [ ] Update all provisioning scripts
- [ ] Write comprehensive documentation
- [ ] End-to-end testing all weeks
- [ ] Create instructor guide

### Milestones

| Milestone | Target | Deliverable |
|-----------|--------|-------------|
| M1 | End Week 1 | Management cluster provisioning working |
| M2 | End Week 1 | Bare metal simulator integrated |
| M3 | End Week 2 | KubeVirt + CAPA providers working |
| M4 | End Week 2 | GPU pool accessible |
| M5 | End Week 3 | Full 6-week curriculum testable |
| M6 | End Week 3 | Documentation complete, ready for cohort |

---

## Appendix

### A. k0rdent-mgmt Terraform Module Interface

```hcl
# modules/k0rdent-mgmt/variables.tf
variable "engineer_id" {
  description = "Engineer identifier"
  type        = string
}

variable "node_count" {
  description = "Number of management cluster nodes"
  type        = number
  default     = 3
}

variable "instance_type" {
  description = "EC2 instance type for management nodes"
  type        = string
  default     = "t3.xlarge"
}

variable "k0s_version" {
  description = "k0s version to install"
  type        = string
  default     = "v1.32.4+k0s.0"
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID"
  type        = string
}

variable "bastion_sg_id" {
  description = "Bastion security group ID"
  type        = string
}

# modules/k0rdent-mgmt/outputs.tf
output "node_ips" {
  description = "Private IPs of management cluster nodes"
  value       = aws_instance.mgmt[*].private_ip
}

output "ssh_private_key" {
  description = "SSH private key for cluster access"
  value       = tls_private_key.ssh.private_key_pem
  sensitive   = true
}

output "k0sctl_config" {
  description = "Generated k0sctl configuration"
  value       = local.k0sctl_yaml
}
```

### B. k0rdent-lab-template Setup Instructions

```markdown
# k0rdent Lab Setup Guide

## Prerequisites

1. Fork this repository to your personal namespace
2. Install tools: kubectl, k0sctl, flux, sops, age
3. Obtain age private key from instructor
4. Configure AWS CLI with your credentials

## Initial Setup

1. Provision infrastructure:
   ```bash
   lab-provision.sh mgmt <your-engineer-id>
   ```

2. Create k0s cluster:
   ```bash
   k0sctl apply --config ~/.k0rdent-lab/<engineer-id>/k0sctl.yaml
   ```

3. Bootstrap Flux:
   ```bash
   export GITHUB_TOKEN=<your-token>
   flux bootstrap git \
     --url=https://git.internal/your-name/k0rdent-lab \
     --branch=main \
     --path=clusters/management
   ```

4. Verify:
   ```bash
   flux get all
   kubectl get pods -A
   ```

## Weekly Progression

- Week 1: Complete initial setup
- Week 2: Uncomment week2-bmaas in clusters/management/kustomization.yaml
- Week 3: Uncomment week3-vmaas
- Week 4: Uncomment week4-kaas
- Week 5: Uncomment week5-gpu
- Week 6: Full configuration for capstone

## Recovery

If you break your cluster:
```bash
git log --oneline
git reset --hard <good-commit>
git push --force origin main
# Flux will reconcile
```

For full rebuild:
```bash
lab-destroy.sh <engineer-id> --auto-approve
lab-provision.sh <engineer-id> --region <region> --auto-approve
# Re-bootstrap Flux
```
```

### C. Prerequisites Checklist

Before implementation:

- [ ] AWS account with appropriate permissions
- [ ] P3/P4d instance quota increased
- [ ] Internal git repository created
- [ ] Engineer list finalized
- [ ] SOPS age keys generated and distributed
- [ ] VPC CIDR approved (10.0.0.0/16)
- [ ] Budget approved (~$2,500 per cohort with buffer)

---

*Document version 2.0 - Updated for k0rdent AI training with GitOps state management*
