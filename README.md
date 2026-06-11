# k0rdent AI Infrastructure Training

A comprehensive 6-week training program (~90 hours) for engineers to master k0rdent Enterprise, enabling them to build AI infrastructure products: **BMaaS**, **VMaaS**, **KaaS**, and **MaaS**.

## Quick Start (3 Steps)

```bash
# 1. Clone and enter the repository
git clone git@github.com:mgueye01/k0rdent-ai-training.git
cd k0rdent-ai-training

# 2. Configure AWS credentials
aws configure

# 3. Start Lab 1.1
# Follow: curriculum/week-1-foundations/labs/lab-1.1-provision-k0rdent.md
```

**That's it.** Lab 1.1 walks you through everything: provisioning, connecting, and verifying your k0rdent management cluster.

## Program Overview

| Attribute | Value |
|-----------|-------|
| **Target Audience** | Engineers proficient in Kubernetes |
| **Format** | Self-paced online with cloud-based labs |
| **Duration** | 6 weeks (~15 hours/week, ~90 total hours) |
| **Lab Ratio** | 70% hands-on / 30% theory |
| **Primary Outcome** | Implement k0rdent for customer deployments |

## Products Covered

| Product | Week(s) | Description |
|---------|---------|-------------|
| **BMaaS** | 1-2 | Bare Metal Hardware Rental/Utilization |
| **VMaaS** | 3 | Virtual Machine Provisioning |
| **KaaS** | 4 | Bare Metal & Instance-based Kubernetes Clusters |
| **MaaS** | 5 | Models as a Service (Endpoints, API Keys) |
| **AI Tools** | 5-6 | Vector DBs, Notebooks, Gateways, Routers |

## Learning Path

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

## Prerequisites

**Required Experience:**
- 2+ years Kubernetes experience (deployments, services, storage, networking)
- Familiarity with Linux system administration
- Basic understanding of virtualization concepts
- Experience with Infrastructure as Code (Terraform, Helm)

**Software Versions:**

| Component | Version | Notes |
|-----------|---------|-------|
| k0s | v1.35.4+k0s.0 | Kubernetes 1.35 |
| k0rdent Enterprise | v1.3.1 | Management platform (N-1; upgrade to v1.3.2 in Lab 1.8) |
| KubeVirt | v1.6.3 | VM workloads |
| NVIDIA GPU Operator | v25.10.0 | GPU management |
| Cluster API | v1.11 | API v1beta2 |
| Metal3 CAPM3 | v1.8.0 | Bare metal provider |
| Cilium | v1.18.4 | CNI |
| vLLM | v0.11.2 | LLM inference |
| Terraform | >= 1.8.0 | IaC |

**Tools to Install:**

| Tool | Version | Install |
|------|---------|---------|
| Terraform | >= 1.8.0 | [hashicorp.com](https://developer.hashicorp.com/terraform/install) |
| AWS CLI | v2 | [aws.amazon.com](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) |
| AWS credentials | configured | `aws configure` |

## Repository Structure

```
k0rdent-ai-training/
├── curriculum/                  # Training content
│   ├── week-1-foundations/     # START HERE → labs/lab-1.1-provision-k0rdent.md
│   ├── week-2-bmaas/           # Metal3, Ironic, bare metal provisioning
│   ├── week-3-vmaas/           # KubeVirt, GPU passthrough
│   ├── week-4-kaas/            # Cluster API, GPU operator
│   ├── week-5-ai-workloads/    # vLLM, Run:AI, service catalog
│   └── week-6-multitenancy/    # RBAC, tenancy, capstone project
└── lab-infrastructure/          # Terraform + scripts
    ├── scripts/                 # lab-provision.sh, lab-connect.sh, etc.
    ├── terraform/               # Infrastructure as Code
    └── docs/                    # Technical references
```

## Key Documents

| Document | Purpose |
|----------|---------|
| [Lab 1.1: Provision k0rdent](curriculum/week-1-foundations/labs/lab-1.1-provision-k0rdent.md) | **Start here** - First lab |
| [Week 1 Theory](curriculum/week-1-foundations/theory/) | Architecture, components, providers |
| [Lab Infrastructure Reference](lab-infrastructure/README.md) | Scripts, costs, technical details |
| [Troubleshooting Guide](lab-infrastructure/docs/troubleshooting.md) | Common issues and solutions |
| [Full Curriculum](curriculum/k0rdent-ai-infrastructure-training-curriculum.md) | Complete syllabus |

## What Gets Installed (Week 1)

When you complete Lab 1.1, you'll have:

- **k0s** - Lightweight Kubernetes distribution (v1.35.4)
- **k0rdent Enterprise** (v1.3.1)
  - **KCM** - Cluster Manager for multi-cluster management
  - **KSM** - State Manager for service installation
  - **KOF** - Observability & FinOps
- **Cluster API** - Kubernetes cluster provisioning
- **k0rdent UI** - Web interface for management

## Assessment

- Weekly quizzes (80% passing required)
- Lab completion with verification
- Week 6 capstone project
- Overall 85% score required for certification

## Support

- **Slack:** #k0rdent-training
- **Issues:** Create GitHub issue
- **Docs:** [docs.mirantis.com/k0rdent-enterprise](https://docs.mirantis.com/k0rdent-enterprise/latest/)

---

**Version:** 2.2 | **Last Updated:** January 2026
