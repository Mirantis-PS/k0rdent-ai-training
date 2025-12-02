# k0rdent AI Infrastructure Training Program Overview

## Program Summary

This training program prepares engineers to implement Mirantis k0rdent for customers, enabling them to build AI infrastructure products including:

- **BMaaS** - Bare Metal Hardware Rental/Utilization
- **VMaaS** - Virtual Machine Provisioning
- **KaaS** - Kubernetes Clusters as a Service
- **MaaS** - Models as a Service (Endpoints, API Keys, Per-token pricing)

## Target Audience

**Engineers** with:
- 2+ years Kubernetes experience
- Linux system administration skills
- Basic virtualization knowledge
- Infrastructure as Code experience (Terraform, Helm)

## Program Structure

| Attribute | Value |
|-----------|-------|
| **Duration** | 6 weeks |
| **Time Commitment** | ~15 hours/week |
| **Total Hours** | ~90 hours |
| **Format** | Self-paced online |
| **Lab Ratio** | 70% hands-on / 30% theory |

## Weekly Schedule

| Week | Topic | Focus Areas |
|------|-------|-------------|
| 1 | Foundations | k0rdent architecture, GPU hardware, BMC management |
| 2 | BMaaS | Metal3, Ironic, OS provisioning |
| 3 | VMaaS | KubeVirt, GPU passthrough, NVLink fabric |
| 4 | KaaS | Cluster API, GPU Operator, network stack |
| 5 | AI Workloads | GPU schedulers, model serving, service catalog |
| 6 | Multi-Tenancy | Isolation, RBAC, identity federation, capstone |

## Learning Path

```
Foundations → BMaaS → VMaaS → KaaS → AI Workloads → Multi-Tenancy
    │           │        │        │         │            │
    └───────────┴────────┴────────┴─────────┴────────────┘
                    Metal-to-Model Journey
```

## Outcomes

Upon completion, engineers will be able to:

1. Deploy k0rdent for customer environments
2. Provision bare metal servers via Redfish/Metal3
3. Create GPU-enabled VMs with NVLink connectivity
4. Manage Kubernetes clusters on bare metal and VMs
5. Deploy AI workloads from service catalog
6. Configure multi-tenant environments with proper isolation

## Assessment

- Weekly quizzes (80% passing required)
- Lab completion with verification
- Week 6 capstone project
- Overall 85% score required for completion

## Getting Started

1. Review [Prerequisites](prerequisites.md)
2. Set up [Lab Environment](../lab-environment/provisioning-guide.md)
3. Begin [Week 1: Foundations](../week-1-foundations/README.md)
