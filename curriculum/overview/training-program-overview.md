# k0rdent AI Infrastructure Training Program Overview

## Executive Summary

This curriculum prepares engineers to implement Mirantis k0rdent for customers, enabling them to build AI infrastructure products including Bare Metal as a Service (BMaaS), Virtual Machines as a Service (VMaaS), Kubernetes as a Service (KaaS), and Models as a Service (MaaS).

## Program Structure

| Attribute | Value |
|-----------|-------|
| **Target Audience** | Engineers proficient in Kubernetes |
| **Format** | Self-paced online with cloud-based labs |
| **Duration** | 6 weeks (~15 hours/week, ~90 total hours) |
| **Lab Ratio** | 70% hands-on / 30% theory |
| **Cohort Size** | 5-15 engineers |
| **Primary Outcome** | Implement k0rdent for customer deployments |
| **Lab Environment** | On-demand cloud instances (central budget) |

## Products Covered

| Product | Week(s) | Description |
|---------|---------|-------------|
| **BMaaS** | 1-2 | Bare Metal Hardware Rental/Utilization |
| **VMaaS** | 3 | Virtual Machine Provisioning |
| **KaaS** | 4 | Bare Metal & Instance-based Kubernetes Clusters |
| **MaaS** | 5 | Models as a Service (Endpoints, API Keys, Per-token pricing) |
| **AI Tools** | 5-6 | Vector DBs, Notebooks, Gateways, Routers |

## Target Audience

**Engineers** with:
- 2+ years Kubernetes experience (deployments, services, storage, networking)
- Familiarity with Linux system administration
- Basic understanding of virtualization concepts
- Experience with Infrastructure as Code (Terraform >= 1.8.0, Helm)

## Software Versions

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

## Weekly Schedule

| Week | Topic | Duration | Focus Areas |
|------|-------|----------|-------------|
| 1 | Foundations | 15h | k0rdent architecture, GPU hardware landscape, BMC management |
| 2 | BMaaS | 15h | Metal3, Ironic, OS provisioning, disk configuration |
| 3 | VMaaS | 15h | KubeVirt, GPU passthrough, NVLink fabric, SR-IOV |
| 4 | KaaS | 15h | Cluster API, GPU Operator, hosted control planes |
| 5 | AI Workloads | 21h | GPU schedulers, model serving, service catalog, ML platforms |
| 6 | Multi-Tenancy | 15h | Isolation, RBAC, identity federation, capstone project |

## Week 1 Learning Objectives

By the end of Week 1, engineers will be able to:

- Describe k0rdent's architecture and the 5 core products it enables
- Identify NVIDIA GPU platforms (H100, H200, B100, B200, B300, GB200)
- Explain NVLink generations, NVSwitch topology, and HGX baseboard design
- Differentiate between Redfish and IPMI protocols
- Use Redfish API to query BMC endpoints and control server power state
- Diagnose common BMC registration and connectivity failures

## Outcomes

Upon completion, engineers will be able to:

1. Deploy k0rdent Enterprise for customer environments
2. Provision bare metal servers via Redfish/Metal3
3. Create GPU-enabled VMs with NVLink connectivity preserved
4. Manage Kubernetes clusters on bare metal and VMs
5. Deploy AI workloads (vLLM, Kubeflow, MLflow) from service catalog
6. Configure multi-tenant environments with proper isolation
7. Set up RBAC and integrate identity providers via OIDC/SAML
8. Generate usage metrics for billing and audit trails

## Assessment Framework

### Weekly Assessments

Each week includes:
- **Quiz:** 15-20 multiple choice/short answer questions
- **Duration:** 30 minutes
- **Passing Score:** 80%
- **Retakes:** Unlimited

### Progress Tracking

| Week | Quiz Weight | Lab Weight | Cumulative |
|------|-------------|------------|------------|
| 1 | 5% | 10% | 15% |
| 2 | 5% | 10% | 30% |
| 3 | 5% | 10% | 45% |
| 4 | 5% | 10% | 60% |
| 5 | 5% | 10% | 75% |
| 6 | 5% | 20% (Capstone) | 100% |

### Completion Requirements

- All weekly quizzes passed (80%+)
- All labs completed with deliverables
- Capstone project passed (80%+)
- **Minimum 85% overall score for certification**

## Getting Started

1. Review [Prerequisites](prerequisites.md)
2. Start [Lab 1.1: Provision k0rdent](../week-1-foundations/labs/lab-1.1-provision-k0rdent.md)
3. Continue [Week 1: Foundations](../week-1-foundations/README.md)

## Resources

- [k0rdent Enterprise Documentation](https://docs.mirantis.com/k0rdent-enterprise/latest/)
- [Metal3 Documentation](https://metal3.io/documentation.html)
- [KubeVirt User Guide](https://kubevirt.io/user-guide/)
- [NVIDIA GPU Operator](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/)
- [Cluster API Book](https://cluster-api.sigs.k8s.io/)
- [vLLM Documentation](https://docs.vllm.ai/)

## Glossary

See the [full glossary](../appendix/glossary.md) for definitions of BMaaS, VMaaS, KaaS, MaaS, CAPI, NVLink, MIG, and other terms used throughout this curriculum.
