# k0rdent AI Infrastructure Training

A comprehensive 6-week training program (~83-91 scheduled hours across the currently available weeks) for engineers to master k0rdent Enterprise, enabling them to build AI infrastructure products: **BMaaS**, **VMaaS**, **KaaS**, and **MaaS**.

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
| **Duration** | 6 weeks (~15-25 scheduled hours/week; ~83-91 hours across the currently available weeks — see each week's README for active vs scheduled breakdown) |
| **Lab Ratio** | 70% hands-on / 30% theory |
| **Primary Outcome** | Implement k0rdent for customer deployments |

## Products Covered

| Product | Week(s) | Description |
|---------|---------|-------------|
| **BMaaS** | 2 | Bare Metal Hardware Rental/Utilization |
| **VMaaS** | 3 | Virtual Machine Provisioning |
| **KaaS** | 4 *(in development)* | Bare Metal & Instance-based Kubernetes Clusters |
| **MaaS** | 5 | Models as a Service (Endpoints, API Keys) |
| **AI Tools** | 5-6 | Vector DBs, Notebooks, Gateways, Routers |

> **Note:** Week 4 (Kubernetes-as-a-Service) is under development and not yet included in this repository; Week 5 currently assumes its concepts. Week 1 Labs 1.5 and 1.8 already cover much of the CAPI cluster lifecycle in the meantime.

## Learning Path

```
Week 1          Week 2          Week 3          Week 4          Week 5          Week 6
┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐
│Foundations│──▶│  BMaaS  │──▶│  VMaaS  │──▶│  KaaS   │──▶│AI Workloads│──▶│Capstone │
│         │    │         │    │         │    │         │    │         │    │         │
│• k0rdent│    │• Metal3 │    │• KubeVirt│   │• CAPI   │    │• Run:AI │    │• Tenancy│
│• CAPI   │    │• Ironic │    │• GPU Pass│   │• GPU Op │    │• vLLM   │    │• RBAC   │
│• KOF    │    │• Provisi│    │• NVLink │    │• CNI/CSI│    │• Catalog│    │• Audit  │
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

See [Prerequisites](curriculum/overview/prerequisites.md) for the full account, budget, quota, and workstation requirements (AWS account with admin-level IAM, macOS/Linux or WSL2, ~$25-50 Week 1 budget).

**Software Versions** (each week's README carries the authoritative version table for its labs):

| Component | Version | Notes |
|-----------|---------|-------|
| k0s | v1.32.4+k0s.0 | Kubernetes 1.32 |
| k0rdent Enterprise | v1.2.2 | Management platform (N-1; upgrade to v1.2.3 in Lab 1.8) |
| KubeVirt | v1.6.3 | VM workloads |
| NVIDIA GPU Operator | v25.10.0 | GPU management |
| Cluster API (clusterctl) | v1.12.4 | Auto-installed in Lab 1.1 |
| Metal3 CAPM3 | v1.8.0 | Bare metal provider |
| Cilium | v1.18.4 | CNI |
| vLLM | v0.14.0 | Validated example pin (Week 5) |
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
│   ├── week-4-kaas/            # Cluster API, GPU operator (in development, not yet included)
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
| [Program Overview](curriculum/overview/training-program-overview.md) | Complete syllabus |

## What Gets Installed (Week 1)

When you complete Lab 1.1, you'll have:

- **k0s** - Lightweight Kubernetes distribution (v1.32.4)
- **k0rdent Enterprise** (v1.2.2)
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
