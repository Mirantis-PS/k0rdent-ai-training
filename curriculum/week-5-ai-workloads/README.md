# Week 5: AI Workloads & Service Catalog

**Duration:** 21 hours (2.5 hours theory / 18 hours labs)
**Focus:** GPU scheduling, model serving, ML platforms, AI tools, service catalog
**Lab Ratio:** ~86% hands-on

## Prerequisites

- Completion of Week 4 (Kubernetes as a Service)
- Working k0rdent management cluster with GPU provider configured
- Familiarity with Kubernetes scheduling, Helm, and GPU resource types

## Infrastructure Notes

GPU clusters for Week 5 labs are deployed via **ClusterDeployment** using the
`aws-standalone-cp-1-0-20` template -- the same pattern used in Week 1.

| Parameter | Value |
|-----------|-------|
| Instance type | **g5.12xlarge** (4x NVIDIA A10G GPUs) |
| OS | **Ubuntu 22.04** (required; Amazon Linux 2 is not supported) |
| Deployment pattern | ClusterDeployment (aws-standalone-cp-1-0-20) |

> **Note:** The `p3.8xlarge` instance type referenced in some older materials has
> been decommissioned. Always use `g5.12xlarge` for Week 5 labs.

---

## Table of Contents

1. [Learning Objectives](#learning-objectives)
2. [Theory Content](#theory-content)
3. [Lab Exercises](#lab-exercises)
4. [Theory-to-Lab Mapping](#theory-to-lab-mapping)
5. [Assessment](#assessment)

---

## Learning Objectives

By the end of this week, engineers will be able to:

- [ ] Deploy and configure GPU schedulers (KAI Scheduler)
- [ ] Serve LLM models with vLLM on Kubernetes
- [ ] Deploy AI tools from service catalog (Vector DBs, Jupyter, etc.)
- [ ] Configure automatic Ingress and network policies for services
- [ ] Wire platform-managed secrets and certificates
- [ ] Export resource metrics for metering
- [ ] Configure NVIDIA GPU Operator with FIPS 140-3 compliance
- [ ] Create reusable ClusterClass templates for AI workloads
- [ ] Deploy Kubeflow for ML pipelines and distributed training
- [ ] Set up MLflow for experiment tracking and model registry
- [ ] Configure fractional GPU sharing and gang scheduling
- [ ] Deploy Slurm on Kubernetes for HPC workloads
- [ ] Optimize inference with TensorRT-LLM
- [ ] Configure RDMA/RoCE for multi-cloud GPU networking
- [ ] Run distributed training across multiple GPU nodes

---

## Theory Content (2.5 hours)

Theory files are in the [theory/](theory/) directory.

### 5.1 GPU Scheduling (1.5 hours)

**File:** [theory/5.1-gpu-scheduling.md](theory/5.1-gpu-scheduling.md)

Topics:
- Kubernetes default scheduler limitations for GPUs
- KAI Scheduler capabilities (open-source Run:AI)
- Gang scheduling for distributed training
- Preemption and priority queues
- Fractional GPU allocation
- GPU topology awareness

### 5.2 LLM Inference Architecture (1 hour)

**File:** [theory/5.2-llm-inference-architecture.md](theory/5.2-llm-inference-architecture.md)

Topics:
- Inference serving patterns
- vLLM architecture and PagedAttention
- Triton Inference Server overview
- Model gateway and routing patterns
- Scaling strategies for inference

### 5.3 GPU Communication

**File:** [theory/5.3-gpu-communication.md](theory/5.3-gpu-communication.md)

### 5.4 Distributed Training

**File:** [theory/5.4-distributed-training.md](theory/5.4-distributed-training.md)

### 5.5 ML Platforms

**File:** [theory/5.5-ml-platforms.md](theory/5.5-ml-platforms.md)

---

## Lab Exercises (18 hours)

All lab files are in the [labs/](labs/) directory.

| Lab | Title | Duration | File |
|-----|-------|----------|------|
| 5.1 | GPU Scheduler Deployment | 3h | [lab-5.1-gpu-scheduler.md](labs/lab-5.1-gpu-scheduler.md) |
| 5.2 | vLLM Inference Service | 2.5h | [lab-5.2-vllm-inference.md](labs/lab-5.2-vllm-inference.md) |
| 5.3 | Vector Database Deployment | 2h | [lab-5.3-vector-database.md](labs/lab-5.3-vector-database.md) |
| 5.4 | Jupyter Notebook Stack | 1.5h | [lab-5.4-jupyter-notebooks.md](labs/lab-5.4-jupyter-notebooks.md) |
| 5.5 | Service Catalog Blueprints | 2h | [lab-5.5-service-catalog.md](labs/lab-5.5-service-catalog.md) |
| 5.6 | Troubleshooting GPU Scheduling | 2h | [lab-5.6-troubleshooting-gpu.md](labs/lab-5.6-troubleshooting-gpu.md) |
| 5.7 | NVIDIA FIPS 140-3 Configuration | 2h | [lab-5.7-nvidia-fips.md](labs/lab-5.7-nvidia-fips.md) |
| 5.8 | Cluster Templates for AI Workloads | 2h | [lab-5.8-cluster-templates.md](labs/lab-5.8-cluster-templates.md) |
| 5.9 | Kubeflow ML Platform | 3h | [lab-5.9-kubeflow-ml-platform.md](labs/lab-5.9-kubeflow-ml-platform.md) |
| 5.10 | MLflow Experiment Tracking | 2.5h | [lab-5.10-mlflow-experiment-tracking.md](labs/lab-5.10-mlflow-experiment-tracking.md) |
| 5.11 | Run:AI GPU Orchestration | 3h | [lab-5.11-runai-gpu-orchestration.md](labs/lab-5.11-runai-gpu-orchestration.md) |
| 5.12 | Slurm Operator for HPC | 3h | [lab-5.12-slurm-operator-hpc.md](labs/lab-5.12-slurm-operator-hpc.md) |
| 5.13 | TensorRT-LLM Optimization | - | [lab-5.13-tensorrt-llm.md](labs/lab-5.13-tensorrt-llm.md) |
| 5.14 | RDMA Multi-Cloud Networking | - | [lab-5.14-rdma-multi-cloud.md](labs/lab-5.14-rdma-multi-cloud.md) |
| 5.15 | Distributed Training | - | [lab-5.15-distributed-training.md](labs/lab-5.15-distributed-training.md) |
| 5.16 | KAI Scheduler | - | [lab-5.16-kai-scheduler.md](labs/lab-5.16-kai-scheduler.md) |

### Key Software References

| Component | Version / Path | Notes |
|-----------|---------------|-------|
| vLLM | v0.11.2 | Pin `vllm/vllm-openai:v0.11.2` in production |
| KAI Scheduler | `oci://ghcr.io/kai-scheduler/kai-scheduler/kai-scheduler` | OCI Helm chart |
| NVIDIA GPU Operator | v25.10.0 | Installed via Helm with k0s containerd env vars |
| Kubeflow | Latest stable | Pipelines, Training Operator, Katib |
| MLflow | Latest stable | Tracking server + model registry |

> **GPU Operator on k0s:** The GPU Operator must be installed via Helm with
> k0s-specific containerd socket and runtime class environment variables.
> See Lab 5.1 for the exact Helm values.

---

## Theory-to-Lab Mapping

| Theory Section | Primary Labs |
|---------------|-------------|
| 5.1 GPU Scheduling | Lab 5.1, Lab 5.6, Lab 5.11, Lab 5.16 |
| 5.2 LLM Inference Architecture | Lab 5.2, Lab 5.13 |
| 5.3 GPU Communication | Lab 5.14 |
| 5.4 Distributed Training | Lab 5.15 |
| 5.5 ML Platforms | Lab 5.9, Lab 5.10 |

---

## Assessment

**Quiz Topics:**
- GPU scheduler features (KAI Scheduler, fractional GPUs, gang scheduling)
- Priority preemption and queue management
- vLLM deployment, configuration, and PagedAttention
- Service catalog usage and blueprint customization
- FIPS 140-3 compliance requirements for GPU Operator
- ClusterClass templates for AI workloads
- Kubeflow components (Pipelines, Training Operator, Katib)
- MLflow tracking and model registry
- Slurm on Kubernetes concepts
- RDMA/RoCE networking for distributed training
- TensorRT-LLM optimization techniques
- Troubleshooting patterns for GPU workloads

**Passing Score:** 80%

---

## Full Curriculum

This file covers Week 5 only. The complete 6-week curriculum document is at
[`curriculum/k0rdent-ai-infrastructure-training-curriculum.md`](../k0rdent-ai-infrastructure-training-curriculum.md)
(referenced from the top-level README).

> **TODO:** The full curriculum file does not yet exist at that path. The content
> that was previously in this README (the entire 1497-line, 6-week curriculum)
> needs to be moved to `curriculum/k0rdent-ai-infrastructure-training-curriculum.md`.
> See the top-level [README.md](../../README.md) line 112 which links to it.
