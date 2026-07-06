# k0rdent AI Infrastructure Training Program Overview

## Executive Summary

This curriculum prepares engineers to implement Mirantis k0rdent for customers, enabling them to build AI infrastructure products including Bare Metal as a Service (BMaaS), Virtual Machines as a Service (VMaaS), Kubernetes as a Service (KaaS), and Models as a Service (MaaS).

> **Scope:** This training covers **k0rdent Enterprise** exclusively (Mirantis commercial distribution). Open-source k0rdent documentation (`docs.k0rdent.io`) may differ in features and CRD versions. **k0rdent AI** is introduced in Week 5.

> **Reference:** See [`mirantis-k0rdent-enterprise-reference.md`](../mirantis-k0rdent-enterprise-reference.md) for the canonical fact sheet (CRDs, KCM/KSM/KOF components, version pins, voice patterns) used throughout this curriculum.

## Program Structure

| Attribute | Value |
|-----------|-------|
| **Target Audience** | Engineers proficient in Kubernetes |
| **Format** | Self-paced online with cloud-based labs |
| **Duration** | 6 weeks (~15-25 scheduled hours/week; ~83-91 hours across the currently available weeks, ~98-106 once Week 4 ships — see each week's README for active vs scheduled breakdown) |
| **Lab Ratio** | 70% hands-on / 30% theory |
| **Cohort Size** | 5-15 engineers |
| **Primary Outcome** | Implement k0rdent for customer deployments |
| **Lab Environment** | Self-provisioned AWS instances (student's own account, via this repo's Terraform) |

## Products Covered

| Product | Week(s) | Description |
|---------|---------|-------------|
| **BMaaS** | 2 | Bare Metal Hardware Rental/Utilization |
| **VMaaS** | 3 | Virtual Machine Provisioning |
| **KaaS** | 4 *(in development)* | Bare Metal & Instance-based Kubernetes Clusters |
| **MaaS** | 5 | Models as a Service (Endpoints, API Keys, Per-token pricing) |
| **AI Tools** | 5-6 | Vector DBs, Notebooks, Gateways, Routers |

> **Note:** Week 4 (Kubernetes as a Service) is under development — Labs 4.1 (hosted control plane), 4.4 (Cilium + Multus), 4.9, and 4.10 are committed, with no README or schedule yet. Week 1 Labs 1.5 and 1.8 already cover much of the CAPI cluster lifecycle; Week 5's only hard Week 4 dependency is Lab 4.4 (required by Lab 5.18).

## Target Audience

**Engineers** with:
- 2+ years Kubernetes experience (deployments, services, storage, networking)
- Familiarity with Linux system administration
- Basic understanding of virtualization concepts
- Experience with Infrastructure as Code (Terraform >= 1.8.0, Helm)

## Software Versions

This curriculum is validated against the following component versions. Each week's README carries the authoritative version table for its labs — if a pin here disagrees with a week's table, the week's table wins.

| Component | Version | Notes |
|-----------|---------|-------|
| k0rdent Enterprise | 1.3.1 | Installed in Lab 1.1; upgraded to 1.3.2 in Lab 1.8 |
| k0s | v1.35.4+k0s.0 | Kubernetes 1.35 |
| KubeVirt | v1.6.3 | Aligns with K8s 1.32 |
| NVIDIA GPU Operator | v25.10.0 | Calendar versioning (YY.MM.PP) |
| Cluster API (clusterctl) | v1.12.4 | Auto-installed in Lab 1.1 |
| Metal3 CAPM3 | v1.8.0 | CNCF Incubating (Aug 2025) |
| Metal3 BMO | v0.8.0 | Baremetal Operator |
| Cilium | v1.18.4 | CNI |
| vLLM | v0.14.0 | Validated example pin (Week 5) |
| Terraform | >= 1.8.0 | IaC |

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

## Weekly Schedule

| Week | Topic | Duration | Focus Areas | README |
|------|-------|----------|-------------|--------|
| 1 | Foundations | ~15-17h active + 5.5h theory (~23-25h scheduled incl. waits) | k0rdent architecture, CAPI providers, RBAC, KOF observability, multi-cluster services | [week-1-foundations](../week-1-foundations/README.md) |
| 2 | BMaaS | 15h | Metal3, Ironic, OS provisioning, disk configuration | [week-2-bmaas](../week-2-bmaas/README.md) |
| 3 | VMaaS | 15h | KubeVirt, GPU passthrough, NVLink fabric, SR-IOV | [week-3-vmaas](../week-3-vmaas/README.md) |
| 4 | KaaS *(in development)* | ~15h (planned) | Cluster API, GPU Operator, hosted control planes (k0smotron), CNI/CSI for AI, autoscaling, day-2 ops | (no README yet) |
| 5 | AI Workloads | ~15-21h guided path (~50h if all elective tracks are attempted) | GPU schedulers, model serving, service catalog, ML platforms | [week-5-ai-workloads](../week-5-ai-workloads/README.md) |
| 6 | Multi-Tenancy | 15h | Isolation, RBAC, identity federation, capstone project | (no README yet) |

> Week 4 is under development — four labs exist (4.1, 4.4, 4.9, 4.10), but no README or schedule yet (see note above). Scheduled totals: ~83-91 hours across the available weeks; ~98-106 once Week 4 ships.

## Week 1 Learning Objectives

By the end of Week 1, engineers will be able to:

- Describe k0rdent Enterprise architecture (KCM, KSM, KOF) and its value proposition
- Deploy k0rdent Enterprise on a k0s Kubernetes cluster
- Navigate the k0rdent UI and understand key concepts (Management, ClusterDeployment, templates)
- Configure AWS infrastructure provider using Cluster API (CAPI)
- Set up credential management and RBAC for production readiness
- Provision managed clusters and deploy multi-cluster services (cert-manager, ingress-nginx, kyverno)
- Deploy KOF for observability and FinOps across the cluster fleet

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
- **Quiz:** 15-20 multiple choice/short answer questions (self-assessment; answer key included)
- **Duration:** 30-60 minutes (see each week's quiz header)
- **Target Score:** 80%
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

Quizzes ship with answer keys and are self-scored (see each week's quiz for its target).

- All weekly self-assessment quizzes at 80%+
- All labs completed with deliverables
- Capstone project passed (80%+)
- **Suggested completion bar: 85% overall (self-tracked)**

## Getting Started

1. Review [Prerequisites](prerequisites.md)
2. Follow the [Week 1: Foundations](../week-1-foundations/README.md) day-by-day schedule
3. Your first hands-on stop is [Lab 1.1: Provision k0rdent](../week-1-foundations/labs/lab-1.1-provision-k0rdent.md) (Day 1, after Theory 1.1)

## Resources

- [k0rdent Enterprise Documentation](https://docs.mirantis.com/k0rdent-enterprise/latest/)
- [Metal3 Documentation](https://metal3.io/documentation.html)
- [KubeVirt User Guide](https://kubevirt.io/user-guide/)
- [NVIDIA GPU Operator](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/)
- [Cluster API Book](https://cluster-api.sigs.k8s.io/)
- [vLLM Documentation](https://docs.vllm.ai/)

## Glossary

See the [full glossary](../appendix/glossary.md) for definitions of BMaaS, VMaaS, KaaS, MaaS, CAPI, NVLink, MIG, and other terms used throughout this curriculum.
