# Lab 5.8: Cluster Templates for AI Workloads

---

## Lab Navigation

| Track | Tier | Duration |
|-------|------|----------|
| Compliance & Templates | Recommended | 2 hours |

### Week 5 Learning Paths

```
FOUNDATION (Required)                    YOU ARE HERE
━━━━━━━━━━━━━━━━━━━━                         ↓
5.1 ➔ 5.2 ➔ 5.3 ➔ 5.4 ➔ 5.5 ➔ 5.6      COMPLIANCE
                                        ━━━━━━━━━━━
                                        5.7 ➔ [5.8]
                                              ↓
                         ┌────────────────────┴────────────────────┐
                         ▼                                         ▼
                    ML PLATFORMS                              ADVANCED
                    ━━━━━━━━━━━━                              ━━━━━━━━
                    5.9 ➔ 5.10 ➔ 5.11 ➔ 5.12           5.13 ➔ 5.14 ➔ 5.15
```

| Previous | Current | Next |
|----------|---------|------|
| [Lab 5.7 - NVIDIA FIPS](lab-5.7-nvidia-fips.md) | **Lab 5.8 - Cluster Templates** | Choose: [Lab 5.9 - Kubeflow](lab-5.9-kubeflow-ml-platform.md) or [Lab 5.13 - TensorRT-LLM](lab-5.13-tensorrt-llm.md) |

---

## Overview

This lab teaches you to create and manage k0rdent ClusterTemplates optimized for AI workloads. You'll learn how k0rdent abstracts Cluster API complexity while providing GPU-specific configurations for development, training, and inference scenarios.

## Learning Objectives

By the end of this lab, you will be able to:

1. Understand k0rdent's ClusterTemplate abstraction over Cluster API
2. Create ClusterTemplates for different AI workload types
3. Deploy GPU-enabled clusters using ClusterDeployment
4. Configure multi-GPU node pools with proper topology
5. Implement cluster lifecycle management for AI teams

## Prerequisites

- Completed Lab 5.1 (GPU Scheduler Deployment)
- Completed Lab 5.7 (NVIDIA FIPS Configuration) - recommended
- Access to k0rdent management cluster
- AWS credentials configured

## Duration

2 hours

---

## Theory: k0rdent Cluster Abstraction

### k0rdent vs Cluster API

k0rdent provides a higher-level abstraction over Cluster API (CAPI), simplifying cluster provisioning while maintaining flexibility:

```
┌─────────────────────────────────────────────────────────────────┐
│                     k0rdent Abstraction Layer                   │
│  ┌─────────────────┐  ┌─────────────────┐  ┌────────────────┐  │
│  │ ClusterTemplate │  │ClusterDeployment│  │   Credential   │  │
│  │  (Reusable)     │  │  (Instance)     │  │  (Auth)        │  │
│  └────────┬────────┘  └────────┬────────┘  └───────┬────────┘  │
└───────────┼─────────────────────┼──────────────────┼───────────┘
            │                     │                  │
            ▼                     ▼                  ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Cluster API Layer                            │
│  ┌──────────────┐  ┌─────────────┐  ┌───────────────────────┐  │
│  │ ClusterClass │  │   Cluster   │  │ AWSClusterIdentity    │  │
│  │ + Templates  │  │ + Topology  │  │ + Secret              │  │
│  └──────────────┘  └─────────────┘  └───────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
            │                     │                  │
            ▼                     ▼                  ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Infrastructure (AWS/Azure/GCP)               │
│         EC2 Instances, VPCs, Security Groups, GPUs              │
└─────────────────────────────────────────────────────────────────┘
```

### Key Differences

| Aspect | Cluster API | k0rdent |
|--------|-------------|---------|
| Template definition | ClusterClass + 5-10 supporting resources | Single ClusterTemplate |
| Cluster creation | Cluster with topology variables | ClusterDeployment with config |
| Credential management | Manual Secret + Identity resources | Credential CRD with reference |
| Multi-tenancy | Manual namespace isolation | Built-in tenant support |
| GPU configuration | Raw machine templates | Parameterized GPU profiles |

### AI Workload Cluster Patterns

Different AI workloads require different cluster configurations:

| Workload Type | GPU Requirement | Instance Type | Key Features |
|---------------|-----------------|---------------|--------------|
| **Development** | 1 GPU per pod | g5.xlarge | Fast iteration, cost-effective |
| **Training** | 8 GPUs per node, multi-node | p4d.24xlarge | NVLink, high memory |
| **Inference** | 1-4 GPUs per node | g5.12xlarge | Low latency, high throughput |

---

## Hands-On Tasks

### Task 1: Explore Existing ClusterTemplates (20 min)

1. **List available ClusterTemplates**
   ```bash
   kubectl get clustertemplates -n kcm-system
   ```

2. **Examine a ClusterTemplate structure**
   ```bash
   kubectl get clustertemplate aws-standalone-cp -n kcm-system -o yaml
   ```

3. **Understand the template components**
   ```yaml
   apiVersion: k0rdent.mirantis.com/v1beta1
   kind: ClusterTemplate
   metadata:
     name: aws-standalone-cp
     namespace: kcm-system
   spec:
     # Provider configuration
     providers:
       infrastructure: aws
       bootstrap: k0s
       controlPlane: k0s

     # Helm chart that generates CAPI resources
     helm:
       chartRef:
         name: k0rdent-cluster-aws
         version: 0.2.0

     # Exposable parameters for customization
     parameters:
       - name: region
         type: string
         default: "us-west-2"
       - name: controlPlaneInstanceType
         type: string
         default: "t3.large"
       - name: workerInstanceType
         type: string
         default: "t3.medium"
       - name: workerReplicas
         type: integer
         default: 2
   ```

### Task 2: Create AI Development ClusterTemplate (30 min)

1. **Define the AI Development template**
   ```yaml
   # Save as ai-dev-template.yaml
   apiVersion: k0rdent.mirantis.com/v1beta1
   kind: ClusterTemplate
   metadata:
     name: ai-dev
     namespace: kcm-system
     labels:
       k0rdent.mirantis.com/workload-type: ai
       k0rdent.mirantis.com/ai-tier: development
   spec:
     providers:
       infrastructure: aws
       bootstrap: k0s
       controlPlane: k0s

     helm:
       chartRef:
         name: k0rdent-cluster-aws-gpu
         version: 0.2.0

     # Parameters exposed to cluster deployers
     parameters:
       # Region selection
       - name: region
         type: string
         default: "us-west-2"
         description: "AWS region for cluster deployment"

       # Control plane configuration
       - name: controlPlaneInstanceType
         type: string
         default: "t3.large"

       # GPU worker configuration
       - name: gpuInstanceType
         type: string
         default: "g5.xlarge"
         description: "GPU instance type (g5.xlarge = 1x A10G)"
         enum:
           - g5.xlarge    # 1x A10G, 24GB
           - g5.2xlarge   # 1x A10G, 24GB, more CPU
           - g5.4xlarge   # 1x A10G, 24GB, more CPU/RAM

       - name: gpuWorkerReplicas
         type: integer
         default: 1
         minimum: 1
         maximum: 4
         description: "Number of GPU worker nodes"

       # CPU worker configuration (optional)
       - name: cpuWorkerReplicas
         type: integer
         default: 0
         description: "Number of CPU-only worker nodes"

       - name: cpuInstanceType
         type: string
         default: "t3.large"

     # Default services to deploy
     services:
       - name: nvidia-gpu-operator
         version: "v25.3.0"
       - name: prometheus-stack
         version: "45.0.0"
   ```

2. **Apply the template**
   ```bash
   kubectl apply -f ai-dev-template.yaml

   # Verify creation
   kubectl get clustertemplate ai-dev -n kcm-system
   ```

3. **Inspect the generated template**
   ```bash
   kubectl describe clustertemplate ai-dev -n kcm-system
   ```

### Task 3: Create AI Training ClusterTemplate (30 min)

1. **Define the AI Training template**
   ```yaml
   # Save as ai-training-template.yaml
   apiVersion: k0rdent.mirantis.com/v1beta1
   kind: ClusterTemplate
   metadata:
     name: ai-training
     namespace: kcm-system
     labels:
       k0rdent.mirantis.com/workload-type: ai
       k0rdent.mirantis.com/ai-tier: training
   spec:
     providers:
       infrastructure: aws
       bootstrap: k0s
       controlPlane: k0s

     helm:
       chartRef:
         name: k0rdent-cluster-aws-gpu
         version: 0.2.0

     parameters:
       - name: region
         type: string
         default: "us-west-2"

       - name: controlPlaneInstanceType
         type: string
         default: "m5.xlarge"
         description: "Larger control plane for training clusters"

       # Multi-GPU training nodes
       - name: gpuInstanceType
         type: string
         default: "p4d.24xlarge"
         description: "Multi-GPU instance for distributed training"
         enum:
           - p3.8xlarge    # 4x V100, NVLink
           - p3.16xlarge   # 8x V100, NVLink
           - p4d.24xlarge  # 8x A100, NVLink/NVSwitch
           - p5.48xlarge   # 8x H100, NVLink/NVSwitch

       - name: gpuWorkerReplicas
         type: integer
         default: 2
         minimum: 1
         maximum: 16
         description: "Number of multi-GPU training nodes"

       # EFA for RDMA (training optimization)
       - name: enableEFA
         type: boolean
         default: true
         description: "Enable Elastic Fabric Adapter for NCCL"

       # Placement group for low-latency
       - name: usePlacementGroup
         type: boolean
         default: true
         description: "Use cluster placement group for GPU nodes"

       # Shared storage for checkpoints
       - name: sharedStorageSize
         type: string
         default: "1Ti"
         description: "FSx Lustre size for training data/checkpoints"

     services:
       - name: nvidia-gpu-operator
         version: "v25.3.0"
       - name: aws-efa-k8s-device-plugin
         version: "v0.5.0"
       - name: fsx-csi-driver
         version: "v1.9.0"
       - name: prometheus-stack
         version: "45.0.0"
   ```

2. **Apply and verify**
   ```bash
   kubectl apply -f ai-training-template.yaml
   kubectl get clustertemplate ai-training -n kcm-system -o yaml
   ```

### Task 4: Create AI Inference ClusterTemplate (20 min)

1. **Define the AI Inference template**
   ```yaml
   # Save as ai-inference-template.yaml
   apiVersion: k0rdent.mirantis.com/v1beta1
   kind: ClusterTemplate
   metadata:
     name: ai-inference
     namespace: kcm-system
     labels:
       k0rdent.mirantis.com/workload-type: ai
       k0rdent.mirantis.com/ai-tier: inference
   spec:
     providers:
       infrastructure: aws
       bootstrap: k0s
       controlPlane: k0s

     helm:
       chartRef:
         name: k0rdent-cluster-aws-gpu
         version: 0.2.0

     parameters:
       - name: region
         type: string
         default: "us-west-2"

       - name: controlPlaneInstanceType
         type: string
         default: "t3.large"

       # Inference-optimized GPU nodes
       - name: gpuInstanceType
         type: string
         default: "g5.12xlarge"
         description: "Inference-optimized instance"
         enum:
           - g5.xlarge     # 1x A10G - small models
           - g5.2xlarge    # 1x A10G - more CPU
           - g5.12xlarge   # 4x A10G - large models
           - inf2.xlarge   # 1x Inferentia2 - cost-optimized
           - inf2.8xlarge  # 1x Inferentia2 - high throughput

       - name: gpuWorkerReplicas
         type: integer
         default: 2
         minimum: 1
         maximum: 10

       # Autoscaling for inference
       - name: enableAutoscaling
         type: boolean
         default: true

       - name: minReplicas
         type: integer
         default: 2

       - name: maxReplicas
         type: integer
         default: 10

     services:
       - name: nvidia-gpu-operator
         version: "v25.3.0"
       - name: cluster-autoscaler
         version: "9.29.0"
       - name: prometheus-stack
         version: "45.0.0"
       - name: istio
         version: "1.20.0"
   ```

2. **Apply the template**
   ```bash
   kubectl apply -f ai-inference-template.yaml
   ```

### Task 5: Deploy a Cluster Using ClusterDeployment (20 min)

1. **Verify Credential exists**
   ```bash
   kubectl get credentials -n kcm-system
   ```

2. **Create a ClusterDeployment**
   ```yaml
   # Save as dev-cluster-deployment.yaml
   apiVersion: k0rdent.mirantis.com/v1beta1
   kind: ClusterDeployment
   metadata:
     name: ml-team-dev
     namespace: tenant-ml-team
   spec:
     # Reference the template
     template: ai-dev

     # Reference credentials
     credential: aws-creds

     # Override default parameters
     config:
       region: us-west-2
       gpuInstanceType: g5.xlarge
       gpuWorkerReplicas: 2
       cpuWorkerReplicas: 1

     # Cluster metadata
     clusterLabels:
       team: ml-research
       environment: development
       cost-center: ai-platform
   ```

3. **Deploy the cluster**
   ```bash
   # Create tenant namespace if needed
   kubectl create namespace tenant-ml-team --dry-run=client -o yaml | kubectl apply -f -

   # Apply the ClusterDeployment
   kubectl apply -f dev-cluster-deployment.yaml
   ```

4. **Monitor deployment progress**
   ```bash
   # Watch ClusterDeployment status
   kubectl get clusterdeployment ml-team-dev -n tenant-ml-team -w

   # Check underlying CAPI resources
   kubectl get clusters,machines -n tenant-ml-team

   # View detailed status
   kubectl describe clusterdeployment ml-team-dev -n tenant-ml-team
   ```

5. **Access the deployed cluster**
   ```bash
   # Get kubeconfig
   kubectl get secret ml-team-dev-kubeconfig -n tenant-ml-team -o jsonpath='{.data.value}' | base64 -d > ml-team-dev.kubeconfig

   # Verify GPU nodes
   KUBECONFIG=ml-team-dev.kubeconfig kubectl get nodes -l nvidia.com/gpu.present=true
   ```

---

## Verification Checklist

Before proceeding, verify you have completed:

- [ ] Listed and examined existing ClusterTemplates
- [ ] Created ai-dev ClusterTemplate with GPU parameters
- [ ] Created ai-training ClusterTemplate with EFA and multi-GPU support
- [ ] Created ai-inference ClusterTemplate with autoscaling
- [ ] Deployed a cluster using ClusterDeployment
- [ ] Accessed the deployed cluster and verified GPU nodes

## Troubleshooting

### ClusterTemplate Not Ready

```bash
# Check template status
kubectl describe clustertemplate <name> -n kcm-system

# Check k0rdent controller logs
kubectl logs -n kcm-system -l app=kcm-controller-manager --tail=100
```

### ClusterDeployment Stuck

```bash
# Check deployment status
kubectl describe clusterdeployment <name> -n <namespace>

# Check underlying Cluster resource
kubectl get cluster -n <namespace> -o yaml

# Check machine provisioning
kubectl get machines -n <namespace>

# Check AWS events in CAPA controller
kubectl logs -n kcm-system -l cluster.x-k8s.io/provider=infrastructure-aws --tail=100
```

### GPU Nodes Not Joining

```bash
# Check machine status
kubectl describe machine <machine-name> -n <namespace>

# Check cloud-init logs on the node (if accessible)
# Look for GPU driver installation failures

# Verify GPU operator is deployed
KUBECONFIG=<cluster>.kubeconfig kubectl get pods -n gpu-operator
```

---

## Key Takeaways

1. **k0rdent simplifies Cluster API** by providing ClusterTemplate abstraction
2. **ClusterTemplates are reusable** across multiple ClusterDeployments
3. **Parameters enable customization** without modifying templates
4. **Different AI workloads** require different cluster configurations
5. **Credentials are managed separately** from cluster definitions
6. **Multi-tenancy is built-in** via namespace isolation

---

## Next Steps

After completing this lab, you can proceed to:

**ML Platform Track** (Recommended):
- [Lab 5.9 - Kubeflow ML Platform](lab-5.9-kubeflow-ml-platform.md) - End-to-end ML workflows

**Advanced Optimization Track**:
- [Lab 5.13 - TensorRT-LLM Optimization](lab-5.13-tensorrt-llm.md) - Advanced inference

**Or return to:**
- [Week 5 Overview](../README.md) - See all available labs
