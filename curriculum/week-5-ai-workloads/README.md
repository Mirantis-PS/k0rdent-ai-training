# Week 5: AI Workloads & Service Catalog

**Estimated content volume:** ~50 hours total (5.25 hours theory / ~45 hours labs if all tracks are attempted)
**Recommended guided path:** ~15-21 hours depending on which elective track is chosen
**Focus:** GPU scheduling, model serving, ML platforms, AI tools, service catalog
**Lab Ratio:** ~90% hands-on if all labs are counted

## Prerequisites

- Completion of Week 4 (Kubernetes as a Service)
- Working k0rdent management cluster with GPU provider configured
- Familiarity with Kubernetes scheduling, Helm, and GPU resource types

## Infrastructure Notes

GPU clusters for Week 5 labs are deployed via **ClusterDeployment** using the
`aws-standalone-cp-1-0-20` template -- the same pattern used in Week 1.

| Parameter | Value |
|-----------|-------|
| Instance type | **g5.12xlarge** (4x NVIDIA A10G GPUs, 22 GiB each on AWS) |
| OS | **Ubuntu 22.04** (required; Amazon Linux 2 is not supported) |
| Deployment pattern | ClusterDeployment (aws-standalone-cp-1-0-20) |

> **Note:** AWS still lists `p3.8xlarge` as a previous-generation instance type,
> but Week 5 defaults to `g5.12xlarge` for better current availability and to
> align the labs with A10G-based GPU clusters.

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

## Theory Content (5.25 hours)

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

## Lab Exercises (~45 hours across all tracks)

All lab files are in the [labs/](labs/) directory.

| Lab | Title | Track | Duration | File |
|-----|-------|-------|----------|------|
| 5.1 | GPU Cluster Setup | Foundation | 3.5h | [lab-5.1-gpu-cluster-setup.md](labs/lab-5.1-gpu-cluster-setup.md) |
| 5.2 | Service Catalog | Foundation | 2h | [lab-5.2-service-catalog.md](labs/lab-5.2-service-catalog.md) |
| 5.3 | KAI Scheduler | Foundation | 2.5h | [lab-5.3-kai-scheduler.md](labs/lab-5.3-kai-scheduler.md) |
| 5.4 | Run:AI Orchestration | Foundation | 3h | [lab-5.4-runai-gpu-orchestration.md](labs/lab-5.4-runai-gpu-orchestration.md) |
| 5.5 | vLLM Inference | Foundation | 4h | [lab-5.5-vllm-inference.md](labs/lab-5.5-vllm-inference.md) |
| 5.6 | Troubleshooting GPU | Foundation | 2h | [lab-5.6-troubleshooting-gpu.md](labs/lab-5.6-troubleshooting-gpu.md) |
| 5.7 | Jupyter Notebooks | Foundation | 1.5h | [lab-5.7-jupyter-notebooks.md](labs/lab-5.7-jupyter-notebooks.md) |
| 5.8 | Vector Database | Foundation | 2h | [lab-5.8-vector-database.md](labs/lab-5.8-vector-database.md) |
| 5.9 | Kubeflow ML Platform | ML Platforms | 3h | [lab-5.9-kubeflow-ml-platform.md](labs/lab-5.9-kubeflow-ml-platform.md) |
| 5.10 | MLflow Experiment Tracking | ML Platforms | 2.5h | [lab-5.10-mlflow-experiment-tracking.md](labs/lab-5.10-mlflow-experiment-tracking.md) |
| 5.11 | NVIDIA FIPS Configuration | Compliance | 2h | [lab-5.11-nvidia-fips.md](labs/lab-5.11-nvidia-fips.md) |
| 5.12 | Cluster Templates for AI | Compliance | 2h | [lab-5.12-cluster-templates.md](labs/lab-5.12-cluster-templates.md) |
| 5.13 | TensorRT-LLM Optimization | Advanced | 3.5h | [lab-5.13-tensorrt-llm.md](labs/lab-5.13-tensorrt-llm.md) |
| 5.14 | Slurm Operator for HPC | Advanced | 3h | [lab-5.14-slurm-operator-hpc.md](labs/lab-5.14-slurm-operator-hpc.md) |
| 5.15 | RDMA Multi-Cloud | Advanced | 4h | [lab-5.15-rdma-multi-cloud.md](labs/lab-5.15-rdma-multi-cloud.md) |
| 5.16 | Distributed Training | Advanced | 4.5h | [lab-5.16-distributed-training.md](labs/lab-5.16-distributed-training.md) |

### Key Software References

| Component | Version / Path | Notes |
|-----------|---------------|-------|
| vLLM | Validated example pin: `v0.14.0` | Lab examples use a pinned image; verify newer upstream releases before production rollout |
| KAI Scheduler | `oci://ghcr.io/kai-scheduler/kai-scheduler/kai-scheduler` (`v0.14.0`) | OCI Helm chart |
| NVIDIA GPU Operator | Validated example pin: `v25.10.0` | Installed via Helm with k0s containerd env vars |
| Kubeflow | Mixed component pins in Lab 5.9 | Pipelines, Training Operator, Katib, and Notebooks are installed separately |
| MLflow | k0rdent template `mlflow-1-8-1` | Current catalog example is chart `1.8.1`, app version `3.7.0` |

> **GPU Operator on k0s:** The GPU Operator must be installed via Helm with
> k0s-specific containerd socket and runtime class environment variables.
> See Lab 5.1 for the exact Helm values.

---

## Theory-to-Lab Mapping

| Theory Section | Primary Labs |
|---------------|-------------|
| 5.1 GPU Scheduling | Lab 5.1, Lab 5.3 (KAI), Lab 5.4 (Run:AI), Lab 5.6 |
| 5.2 LLM Inference Architecture | Lab 5.5 (vLLM), Lab 5.13 (TensorRT-LLM) |
| 5.3 GPU Communication | Lab 5.15 (RDMA) |
| 5.4 Distributed Training | Lab 5.16 (Distributed Training) |
| 5.5 ML Platforms | Lab 5.9 (Kubeflow), Lab 5.10 (MLflow) |

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
