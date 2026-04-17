# Lab 5.12: Cluster Templates for AI Workloads

---

## Lab Navigation

| Track | Tier | Duration |
|-------|------|----------|
| Compliance & Templates | Recommended | 2 hours |

### Week 5 Learning Paths

```
FOUNDATION (Completed)                        COMPLIANCE & TEMPLATES
━━━━━━━━━━━━━━━━━━━━━━                       ━━━━━━━━━━━━━━━━━━━━━━
5.1 ➔ 5.2 ➔ 5.3 ➔ 5.4 ➔ 5.5                5.11 FIPS
     ➔ 5.6 ➔ 5.7 ➔ 5.8 ✓                        ↓
                                             YOU ARE HERE
                                                  ↓
                                             [5.12] Cluster Templates
```

| Previous | Current | Next |
|----------|---------|------|
| [Lab 5.11 - NVIDIA FIPS](lab-5.11-nvidia-fips.md) | **Lab 5.12 - Cluster Templates** | Choose: [Lab 5.9 - Kubeflow](lab-5.9-kubeflow-ml-platform.md) or [Lab 5.13 - TensorRT-LLM](lab-5.13-tensorrt-llm.md) |

---

## Table of Contents

- [Overview](#overview)
- [Learning Objectives](#learning-objectives)
- [Prerequisites](#prerequisites)
- [Part 1: Understanding k0rdent Cluster Abstraction](#part-1-understanding-k0rdent-cluster-abstraction)
- [Part 2: Hands-On Tasks](#part-2-hands-on-tasks)
  - [Task 1: Explore Shipped ClusterTemplates](#task-1-explore-shipped-clustertemplates-15-min)
  - [Task 2: Discover Template Parameters via status.config](#task-2-discover-template-parameters-via-statusconfig-15-min)
  - [Task 3: Deploy an AI Development Cluster](#task-3-deploy-an-ai-development-cluster-25-min)
  - [Task 4: Deploy an AI Training Cluster](#task-4-deploy-an-ai-training-cluster-25-min)
  - [Task 5: Deploy AI Services via serviceSpec](#task-5-deploy-ai-services-via-servicespec-20-min)
  - [Task 6: Cluster Lifecycle Management](#task-6-cluster-lifecycle-management-20-min)
  - [Task 7: Understanding Custom ClusterTemplates](#task-7-understanding-custom-clustertemplates-15-min)
- [Cleanup](#cleanup)
- [Verification Checklist](#verification-checklist)
- [Troubleshooting](#troubleshooting)
- [Key Takeaways](#key-takeaways)
- [Next Steps](#next-steps)

## Overview

This lab teaches you to understand and use k0rdent ClusterTemplates for deploying GPU-enabled clusters for AI workloads. You'll explore the shipped templates, deploy clusters with different GPU configurations for development, training, and inference scenarios, and deploy AI services via `serviceSpec`.

## Learning Objectives

By the end of this lab, you will be able to:

1. Understand k0rdent's ClusterTemplate abstraction over Cluster API
2. Explore shipped ClusterTemplates and their parameters via `status.config`
3. Deploy GPU-enabled clusters using ClusterDeployment with different worker configurations
4. Deploy AI services (GPU Operator, monitoring) via `serviceSpec`
5. Manage cluster lifecycle (scaling, upgrading) for AI teams
6. Understand when and how to create custom ClusterTemplates

## Prerequisites

- Completed Lab 5.1 (GPU Scheduler Deployment)
- Completed Lab 5.2 (k0rdent Service Catalog) - recommended
- Access to k0rdent management cluster
- AWS credentials configured via Credential object

## Duration

2 hours

---

## Part 1: Understanding k0rdent Cluster Abstraction

### k0rdent vs Cluster API

k0rdent provides a higher-level abstraction over Cluster API (CAPI), simplifying cluster provisioning while maintaining flexibility:

```
┌─────────────────────────────────────────────────────────────────┐
│                     k0rdent Abstraction Layer                   │
│  ┌─────────────────┐  ┌─────────────────┐  ┌────────────────┐  │
│  │ ClusterTemplate │  │ClusterDeployment│  │   Credential   │  │
│  │  (Chart Wrapper)│  │  (Instance)     │  │  (Auth)        │  │
│  └────────┬────────┘  └────────┬────────┘  └───────┬────────┘  │
└───────────┼─────────────────────┼──────────────────┼───────────┘
            │                     │                  │
            ▼                     ▼                  ▼
┌─────────────────────────────────────────────────────────────────┐
│               Cluster API + Infrastructure Layer                │
│  ┌──────────────┐  ┌─────────────┐  ┌───────────────────────┐  │
│  │   Cluster    │  │  Machines   │  │ AWSClusterIdentity    │  │
│  │ + Topology   │  │ + Pools     │  │ + Secret              │  │
│  └──────────────┘  └─────────────┘  └───────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
            │                     │                  │
            ▼                     ▼                  ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Infrastructure (AWS/Azure/GCP)               │
│         EC2 Instances, VPCs, Security Groups, GPUs              │
└─────────────────────────────────────────────────────────────────┘
```

### How ClusterTemplates Work

A ClusterTemplate is a wrapper around a **Helm chart** that generates CAPI resources. The key insight is that parameters are **not defined on the template itself** - they come from the Helm chart's values and are automatically exposed in the template's `status.config` field after validation.

```
┌──────────────────────────────────────────────────────────────┐
│  ClusterTemplate                                             │
│  spec:                                                       │
│    helm.chartSpec → references a Helm chart in a repository  │
│    providers → list of required CAPI providers               │
│                                                              │
│  status:                                                     │
│    config → parameters extracted from chart (read-only)      │
│    valid → whether template passed validation                │
│    providers → resolved provider list                        │
└──────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────┐
│  ClusterDeployment                                           │
│  spec:                                                       │
│    template → references ClusterTemplate by name             │
│    credential → references Credential by name                │
│    config → overrides for status.config parameters           │
│    serviceSpec → services to deploy on the cluster           │
└──────────────────────────────────────────────────────────────┘
```

### Key Differences from Raw CAPI

| Aspect | Cluster API | k0rdent |
|--------|-------------|---------|
| Template definition | ClusterClass + MachineDeployments + supporting resources | Single ClusterTemplate wrapping a Helm chart |
| Cluster creation | Cluster with topology variables | ClusterDeployment with config overrides |
| Parameter discovery | Read ClusterClass variables manually | `status.config` auto-populated by controller |
| Credential management | Manual Secret + Identity resources | Credential CRD with simple reference |
| Service deployment | Manual Helm installs after cluster creation | `serviceSpec` deploys services automatically |
| Multi-tenancy | Manual namespace isolation | Built-in tenant support via namespaces |

### AI Workload Cluster Patterns

Different AI workloads require different cluster configurations. With k0rdent, you use the **same ClusterTemplate** but vary the `config` parameters:

| Workload Type | Worker Instance | Key Config | Use Case |
|---------------|-----------------|------------|----------|
| **Development** | g5.xlarge (1x A10G) | 1-2 workers, small control plane | Fast iteration, notebooks |
| **Training** | p4d.24xlarge (8x A100) | 2-16 workers, large control plane | Distributed training |
| **Inference** | g5.12xlarge (4x A10G) | 2-10 workers, autoscaling | Low latency serving |

---

## Part 2: Hands-On Tasks

### Task 1: Explore Shipped ClusterTemplates (15 min)

k0rdent ships pre-validated ClusterTemplates for each supported provider. These templates have versioned names.

1. **List available ClusterTemplates**

   ```bash
   kubectl get clustertemplates -n kcm-system
   ```

   Expected output on k0rdent Enterprise 1.2.x (template names include version suffixes — empirical 2026-04-17):
   ```
   NAMESPACE    NAME                              VALID
   kcm-system   adopted-cluster-1-0-1             true
   kcm-system   aws-eks-1-0-4                     true
   kcm-system   aws-hosted-cp-1-0-21              true
   kcm-system   aws-standalone-cp-1-0-20          true
   kcm-system   azure-aks-1-0-1                   true
   kcm-system   azure-hosted-cp-1-0-22            true
   kcm-system   azure-standalone-cp-1-0-19        true
   kcm-system   docker-hosted-cp-1-0-4            true
   kcm-system   gcp-gke-1-0-6                     true
   kcm-system   gcp-hosted-cp-1-0-19              true
   kcm-system   gcp-standalone-cp-1-0-17          true
   kcm-system   openstack-hosted-cp-1-0-12        true
   kcm-system   openstack-standalone-cp-1-0-21    true
   kcm-system   remote-cluster-1-0-18             true
   kcm-system   vsphere-hosted-cp-1-0-18          true
   kcm-system   vsphere-standalone-cp-1-0-17      true
   ```

   > **Note:** Version suffixes (e.g., `-1-0-20`) correspond to the chart version with dots replaced by dashes. Your environment may show different versions depending on the k0rdent release installed — always `kubectl get clustertemplate -n kcm-system` first and substitute the actual name your mgmt cluster carries into the rest of the lab. The 0.x template family from earlier k0rdent releases has been superseded by the 1.x family in k0rdent Enterprise 1.2.

2. **Examine the AWS standalone template**

   ```bash
   kubectl get clustertemplate aws-standalone-cp-1-0-20 -n kcm-system -o yaml
   ```

3. **Understand the real ClusterTemplate structure**

   The shipped `aws-standalone-cp` template looks like this:

   ```yaml
   apiVersion: k0rdent.mirantis.com/v1beta1
   kind: ClusterTemplate
   metadata:
     name: aws-standalone-cp-1-0-20
     namespace: kcm-system
   spec:
     # Helm chart that generates CAPI resources
     helm:
       chartSpec:
         chart: aws-standalone-cp
         interval: 10m0s
         reconcileStrategy: ChartVersion
         sourceRef:
           kind: HelmRepository
           name: kcm-templates        # internal k0rdent Enterprise template repo
         version: 1.0.20

     # Required CAPI providers (flat string array)
     providers:
     - bootstrap-k0smotron
     - control-plane-k0smotron
     - infrastructure-aws

     # Provider contract versions
     providerContracts:
       bootstrap-k0smotron: v1beta1
       control-plane-k0smotron: v1beta1
       infrastructure-aws: v1beta2
   ```

   > **Key insight:** The `spec` only references a Helm chart and declares required providers. There is no `parameters` or `services` field - parameters come from the chart's values and appear in `status.config`.

### Task 2: Discover Template Parameters via status.config (15 min)

After the k0rdent controller validates a ClusterTemplate, it populates `status.config` with all available parameters and their defaults. This is how you discover what can be customized.

1. **View the available parameters**

   ```bash
   kubectl get clustertemplate aws-standalone-cp-1-0-20 -n kcm-system \
     -o jsonpath='{.status.config}' | python3 -m json.tool
   ```

   Output shows all configurable parameters:
   ```json
   {
     "bastion": {
       "allowedCIDRBlocks": [],
       "ami": "",
       "disableIngressRules": false,
       "enabled": false,
       "instanceType": "t2.micro"
     },
     "clusterIdentity": {
       "kind": "AWSClusterStaticIdentity",
       "name": ""
     },
     "clusterLabels": {},
     "clusterNetwork": {
       "pods": { "cidrBlocks": ["10.244.0.0/16"] },
       "services": { "cidrBlocks": ["10.96.0.0/12"] }
     },
     "controlPlane": {
       "amiID": "",
       "iamInstanceProfile": "control-plane.cluster-api-provider-aws.sigs.k8s.io",
       "instanceType": "",
       "rootVolumeSize": 8
     },
     "controlPlaneNumber": 3,
     "k0s": { "version": "v1.31.1+k0s.1" },
     "publicIP": false,
     "region": "",
     "sshKeyName": "",
     "worker": {
       "amiID": "",
       "iamInstanceProfile": "nodes.cluster-api-provider-aws.sigs.k8s.io",
       "instanceType": "",
       "rootVolumeSize": 8
     },
     "workersNumber": 2
   }
   ```

2. **Identify GPU-relevant parameters**

   For AI workloads, the key parameters are:

   | Parameter | Description | AI Relevance |
   |-----------|-------------|--------------|
   | `worker.instanceType` | EC2 instance type for workers | Set to GPU instance (g5, p4d, p5) |
   | `workersNumber` | Number of worker nodes | Scale for distributed training |
   | `worker.rootVolumeSize` | Root disk size (GB) | Increase for model/data storage |
   | `controlPlane.instanceType` | Control plane instance type | Larger for training clusters |
   | `controlPlaneNumber` | Number of control plane nodes | 3 for production |
   | `region` | AWS region | Choose region with GPU capacity |
   | `clusterLabels` | Labels for the cluster | Used by MultiClusterService targeting |
   | `publicIP` | Assign public IPs | Required for external access |

   > **Important:** The standard `aws-standalone-cp` template provisions a single worker pool. All workers share the same instance type. For mixed GPU + CPU pools, you would need a custom ClusterTemplate with a chart that supports multiple MachineDeployments (covered in Task 6).

### Task 3: Deploy an AI Development Cluster (25 min)

Deploy a lightweight GPU cluster for ML development and experimentation.

> **💰 Cost warning:** Tasks 3-6 each provision a **real** CAPA workload cluster on AWS. `ml-dev` runs a g5.xlarge (~$1.00/h), `ml-training` targets p4d.24xlarge (~$32/h, check quota first), `ml-inference` uses g5.2xlarge (~$1.20/h). Spin them down at the end of each task via `kubectl delete clusterdeployment` or the sequence in Task 6. A full Tasks 3-6 run with default shapes costs roughly $5-10 of EC2.

> **Prerequisite — install the `gpu-operator-25-10-0` ServiceTemplate first** (not shipped by default in a fresh k0rdent install; you must pull it from the catalog once, then it is reusable for all Tasks 3-6):
>
> ```bash
> helm upgrade --install gpu-operator-template \
>   oci://ghcr.io/k0rdent/catalog/charts/kgst \
>   --set chart=gpu-operator:25.10.0 \
>   -n kcm-system --wait --timeout 5m
> kubectl wait servicetemplate gpu-operator-25-10-0 -n kcm-system \
>   --for=jsonpath='{.status.valid}'=true --timeout=120s
> ```
>
> Same pattern applies to `ingress-nginx-4-11-3` and `kyverno-3-2-6` referenced in Task 5 — install via `kgst` on first use, then reference from any subsequent ClusterDeployment `serviceSpec` or MCS.

1. **Verify your Credential exists**

   ```bash
   kubectl get credentials -n kcm-system
   ```

   You should see `aws-cluster-identity-cred` in the list. If not, refer to [Lab 1.3](../../week-1-foundations/labs/lab-1.3-configure-aws-provider.md).

2. **Create a development ClusterDeployment**

   ```yaml
   # Save as ai-dev-cluster.yaml
   apiVersion: k0rdent.mirantis.com/v1beta1
   kind: ClusterDeployment
   metadata:
     name: ml-dev
     namespace: kcm-system
   spec:
     template: aws-standalone-cp-1-0-20
     credential: aws-cluster-identity-cred
     config:
       region: us-west-2
       publicIP: true
       controlPlaneNumber: 1
       controlPlane:
         instanceType: t3.large
         rootVolumeSize: 50
       workersNumber: 1
       worker:
         instanceType: g5.xlarge    # 1x NVIDIA A10G, 24GB VRAM
         rootVolumeSize: 100        # Space for container images and models
       clusterLabels:
         k0rdent.mirantis.com/workload-type: ai
         environment: development
         team: ml-research
       sshKeyName: k0rdent-clusters
     # GPU Operator deployed automatically via serviceSpec
     serviceSpec:
       services:
         - template: gpu-operator-25-10-0
           name: gpu-operator
           namespace: gpu-operator
       priority: 100
   ```

   > **Note:** `sshKeyName` is optional. If omitted, CAPA creates instances without SSH keys -- k0rdent manages nodes via CAPI. Include it only if you need direct SSH access to GPU worker nodes for debugging. If included, the key must exist in the target region (see [Lab 1.3, Part 6](../../week-1-foundations/labs/lab-1.3-aws-infra.md)).

   > **k0rdent context:** The `serviceSpec` section deploys services to the workload cluster after provisioning. The GPU Operator ServiceTemplate (`gpu-operator-25-10-0`) is installed from the [k0rdent catalog](https://catalog.k0rdent.io/). This follows the same pattern as deploying ingress-nginx or kyverno from [Lab 1.7](../../week-1-foundations/labs/lab-1.7-multicluster-services.md).

3. **Apply the ClusterDeployment**

   ```bash
   kubectl apply -f ai-dev-cluster.yaml
   ```

4. **Monitor deployment progress**

   ```bash
   # Watch ClusterDeployment status
   kubectl get clusterdeployment ml-dev -n kcm-system -w

   # Check underlying CAPI resources
   kubectl get clusters,machines -n kcm-system -l cluster.x-k8s.io/cluster-name=ml-dev

   # View detailed status and conditions
   kubectl describe clusterdeployment ml-dev -n kcm-system
   ```

   Wait until the ClusterDeployment shows `Ready` status. This typically takes 10-15 minutes for AWS.

5. **Access the deployed cluster**

   ```bash
   # Extract kubeconfig from the generated secret
   kubectl get secret ml-dev-kubeconfig -n kcm-system \
     -o jsonpath='{.data.value}' | base64 -d > ml-dev.kubeconfig

   # Verify the cluster is accessible
   KUBECONFIG=ml-dev.kubeconfig kubectl get nodes

   # Verify GPU node is present
   KUBECONFIG=ml-dev.kubeconfig kubectl get nodes \
     -o custom-columns='NAME:.metadata.name,INSTANCE:.metadata.labels.node\.kubernetes\.io/instance-type,GPU:.status.allocatable.nvidia\.com/gpu'
   ```

   Expected output:
   ```
   NAME                          INSTANCE     GPU
   ml-dev-cp-0                   t3.large     <none>
   ml-dev-worker-0               g5.xlarge    1
   ```

6. **Verify GPU Operator is running**

   The GPU Operator should be deployed automatically via `serviceSpec`:

   ```bash
   KUBECONFIG=ml-dev.kubeconfig kubectl get pods -n gpu-operator
   ```

### Task 4: Deploy an AI Training Cluster (25 min)

Deploy a multi-GPU cluster for distributed training workloads.

1. **Create a training ClusterDeployment**

   ```yaml
   # Save as ai-training-cluster.yaml
   apiVersion: k0rdent.mirantis.com/v1beta1
   kind: ClusterDeployment
   metadata:
     name: ml-training
     namespace: kcm-system
   spec:
     template: aws-standalone-cp-1-0-20
     credential: aws-cluster-identity-cred
     config:
       region: us-west-2
       publicIP: true
       controlPlaneNumber: 3                  # HA control plane for long-running jobs
       controlPlane:
         instanceType: m5.xlarge              # Larger CP for training clusters
         rootVolumeSize: 100
       workersNumber: 2                       # 2x multi-GPU nodes
       worker:
         instanceType: p4d.24xlarge           # 8x A100 per node, NVLink/NVSwitch
         rootVolumeSize: 500                  # Space for datasets and checkpoints
       clusterLabels:
         k0rdent.mirantis.com/workload-type: ai
         environment: training
         team: ml-research
         gpu-tier: a100
       sshKeyName: k0rdent-clusters
     serviceSpec:
       services:
         - template: gpu-operator-25-10-0
           name: gpu-operator
           namespace: gpu-operator
           values: |
             driver:
               rdma:
                 enabled: true                # Enable nvidia-peermem for GPUDirect RDMA
       priority: 100
   ```

   > **Training clusters vs dev clusters:** Training clusters use multi-GPU instances (p4d.24xlarge = 8x A100 with NVLink/NVSwitch for fast inter-GPU communication), larger control planes (3 nodes for HA during long-running jobs), and larger root volumes for dataset staging. The GPU Operator is configured with RDMA support for high-bandwidth inter-node communication.

2. **Apply and monitor**

   ```bash
   kubectl apply -f ai-training-cluster.yaml

   # Monitor progress
   kubectl get clusterdeployment ml-training -n kcm-system -w
   ```

   > **Note:** p4d.24xlarge instances have limited availability. If provisioning fails with capacity errors, try a different region (us-east-1, us-east-2) or switch to p3.16xlarge (8x V100).

3. **Verify multi-GPU workers**

   ```bash
   kubectl get secret ml-training-kubeconfig -n kcm-system \
     -o jsonpath='{.data.value}' | base64 -d > ml-training.kubeconfig

   # Verify GPU count per node
   KUBECONFIG=ml-training.kubeconfig kubectl get nodes \
     -o custom-columns='NAME:.metadata.name,INSTANCE:.metadata.labels.node\.kubernetes\.io/instance-type,GPU:.status.allocatable.nvidia\.com/gpu'
   ```

   Expected output:
   ```
   NAME                             INSTANCE         GPU
   ml-training-cp-0                 m5.xlarge        <none>
   ml-training-cp-1                 m5.xlarge        <none>
   ml-training-cp-2                 m5.xlarge        <none>
   ml-training-worker-0             p4d.24xlarge     8
   ml-training-worker-1             p4d.24xlarge     8
   ```

   Total GPUs: 16x A100 (2 nodes x 8 GPUs).

### Task 5: Deploy AI Services via serviceSpec (20 min)

k0rdent's `serviceSpec` on ClusterDeployment automates post-provisioning service deployment. You can also use `MultiClusterService` to deploy services across multiple clusters at once.

1. **Update a cluster with additional services**

   Add monitoring to the training cluster by updating the ClusterDeployment:

   ```yaml
   # Save as ai-training-cluster-updated.yaml
   apiVersion: k0rdent.mirantis.com/v1beta1
   kind: ClusterDeployment
   metadata:
     name: ml-training
     namespace: kcm-system
   spec:
     template: aws-standalone-cp-1-0-20
     credential: aws-cluster-identity-cred
     config:
       region: us-west-2
       publicIP: true
       controlPlaneNumber: 3
       controlPlane:
         instanceType: m5.xlarge
         rootVolumeSize: 100
       workersNumber: 2
       worker:
         instanceType: p4d.24xlarge
         rootVolumeSize: 500
       clusterLabels:
         k0rdent.mirantis.com/workload-type: ai
         environment: training
         team: ml-research
         gpu-tier: a100
       sshKeyName: k0rdent-clusters
     serviceSpec:
       services:
         - template: gpu-operator-25-10-0
           name: gpu-operator
           namespace: gpu-operator
           values: |
             driver:
               rdma:
                 enabled: true
         - template: ingress-nginx-4-11-3
           name: ingress-nginx
           namespace: ingress-nginx
         - template: kyverno-3-2-6
           name: kyverno
           namespace: kyverno
       priority: 100
   ```

   ```bash
   kubectl apply -f ai-training-cluster-updated.yaml
   ```

2. **Deploy services across ALL AI clusters with MultiClusterService**

   For services that should be on every AI cluster, use `MultiClusterService` with label selectors:

   ```yaml
   # Save as ai-common-services.yaml
   apiVersion: k0rdent.mirantis.com/v1beta1
   kind: MultiClusterService
   metadata:
     name: ai-common-services
     namespace: kcm-system
   spec:
     clusterSelector:
       matchLabels:
         k0rdent.mirantis.com/workload-type: ai
     serviceSpec:
       services:
         - template: gpu-operator-25-10-0
           name: gpu-operator
           namespace: gpu-operator
         - template: ingress-nginx-4-11-3
           name: ingress-nginx
           namespace: ingress-nginx
       priority: 100
   ```

   ```bash
   kubectl apply -f ai-common-services.yaml
   ```

   > **k0rdent context:** `MultiClusterService` targets clusters by label. Since both `ml-dev` and `ml-training` have `k0rdent.mirantis.com/workload-type: ai` in their `clusterLabels`, both clusters receive the GPU Operator and ingress-nginx automatically. Any future cluster with that label will also receive these services. This is the same pattern used in [Lab 5.2](lab-5.2-service-catalog.md) for deploying services from the k0rdent catalog.

3. **Verify services deployed to training cluster**

   ```bash
   KUBECONFIG=ml-training.kubeconfig kubectl get pods -n gpu-operator
   KUBECONFIG=ml-training.kubeconfig kubectl get pods -n ingress-nginx
   ```

### Task 6: Cluster Lifecycle Management (20 min)

1. **Scale workers on the training cluster**

   To add more GPU nodes, update the `workersNumber` in the ClusterDeployment config:

   ```bash
   kubectl patch clusterdeployment ml-training -n kcm-system --type merge -p '
   spec:
     config:
       workersNumber: 4
   '
   ```

   Monitor the scaling:
   ```bash
   kubectl get machines -n kcm-system -l cluster.x-k8s.io/cluster-name=ml-training -w
   ```

   Two new p4d.24xlarge nodes will be provisioned, giving you 32 A100 GPUs total.

2. **Compare cluster configurations**

   ```bash
   # See all AI clusters and their configs
   kubectl get clusterdeployments -n kcm-system -o custom-columns=\
   'NAME:.metadata.name,TEMPLATE:.spec.template,WORKERS:.spec.config.workersNumber,INSTANCE:.spec.config.worker.instanceType'
   ```

   Expected output:
   ```
   NAME           TEMPLATE                    WORKERS   INSTANCE
   ml-dev         aws-standalone-cp-1-0-20     1         g5.xlarge
   ml-training    aws-standalone-cp-1-0-20     4         p4d.24xlarge
   ```

   Both clusters use the **same template** but with different configurations - this is k0rdent's approach to supporting diverse AI workloads without template proliferation.

3. **Scale down after training completes**

   ```bash
   kubectl patch clusterdeployment ml-training -n kcm-system --type merge -p '
   spec:
     config:
       workersNumber: 1
   '
   ```

   k0rdent will gracefully drain and terminate excess workers, saving significant GPU cost.

### Task 7: Understanding Custom ClusterTemplates (15 min)

The shipped `aws-standalone-cp` template supports a single worker pool. For advanced scenarios like mixed GPU + CPU pools, you need a custom ClusterTemplate backed by a custom Helm chart.

1. **When to create custom templates**

   | Scenario | Shipped Template | Custom Template Needed |
   |----------|-----------------|----------------------|
   | Single GPU worker pool | Yes | No |
   | Different instance types per pool | No | Yes |
   | GPU + CPU mixed pools | No | Yes |
   | EFA networking configuration | No | Yes |
   | Placement groups for GPU locality | No | Yes |
   | Custom AMIs with pre-installed drivers | No | Yes |

2. **Custom ClusterTemplate structure**

   A custom ClusterTemplate references a Helm chart you create and publish. The chart must generate valid CAPI resources (Cluster, MachineDeployments, etc.):

   ```yaml
   apiVersion: k0rdent.mirantis.com/v1beta1
   kind: ClusterTemplate
   metadata:
     name: aws-gpu-training-0-1-0
     namespace: kcm-system
   spec:
     helm:
       chartSpec:
         chart: aws-gpu-training
         interval: 10m0s
         reconcileStrategy: ChartVersion
         sourceRef:
           kind: HelmRepository
           name: my-org-charts       # Your org's chart repository
         version: 0.1.0

     # Required CAPI providers
     providers:
     - bootstrap-k0smotron
     - control-plane-k0smotron
     - infrastructure-aws

     providerContracts:
       bootstrap-k0smotron: v1beta1
       control-plane-k0smotron: v1beta1
       infrastructure-aws: v1beta2
   ```

   > **Important:** The ClusterTemplate `spec` is **immutable** after creation (`self == oldSelf` validation). To update a template, you create a new version (e.g., `aws-gpu-training-0-2-0`) rather than editing the existing one. This ensures running clusters are not affected by template changes.

3. **Custom chart features for AI workloads**

   A custom Helm chart for GPU training clusters would generate:

   ```
   Chart: aws-gpu-training
   ├── templates/
   │   ├── cluster.yaml           # CAPI Cluster resource
   │   ├── control-plane.yaml     # K0sControlPlane
   │   ├── gpu-workers.yaml       # MachineDeployment for GPU nodes
   │   ├── cpu-workers.yaml       # MachineDeployment for CPU nodes
   │   ├── placement-group.yaml   # AWS placement group for GPU locality
   │   └── efa-security-group.yaml # Security group rules for EFA
   └── values.yaml                # Parameters (become status.config)
   ```

   The chart's `values.yaml` defines parameters that k0rdent exposes via `status.config`:

   ```yaml
   # values.yaml for the custom chart
   region: ""
   controlPlaneNumber: 3
   controlPlane:
     instanceType: m5.xlarge

   # GPU worker pool
   gpuWorkers:
     instanceType: p4d.24xlarge
     count: 2
     rootVolumeSize: 500
     enableEFA: true
     usePlacementGroup: true

   # CPU worker pool (for data preprocessing, monitoring)
   cpuWorkers:
     instanceType: m5.2xlarge
     count: 2
     rootVolumeSize: 100
   ```

   After applying this ClusterTemplate, `status.config` would show these parameters, and users could override them in `ClusterDeployment.spec.config`.

4. **Using the custom template**

   ```yaml
   apiVersion: k0rdent.mirantis.com/v1beta1
   kind: ClusterDeployment
   metadata:
     name: ml-training-advanced
     namespace: kcm-system
   spec:
     template: aws-gpu-training-0-1-0      # Custom template
     credential: aws-cluster-identity-cred
     config:
       region: us-west-2
       gpuWorkers:
         instanceType: p5.48xlarge          # H100 instead of A100
         count: 4
         enableEFA: true
       cpuWorkers:
         count: 3
       clusterLabels:
         environment: training
         gpu-tier: h100
     serviceSpec:
       services:
         - template: gpu-operator-25-10-0
           name: gpu-operator
           namespace: gpu-operator
       priority: 100
   ```

   > **Note:** Creating custom CAPI Helm charts is an advanced topic typically handled by platform teams. The shipped templates cover most single-pool GPU scenarios. Custom templates are needed when your organization requires standardized multi-pool configurations that are deployed repeatedly.

---

## Cleanup

When you're done with the lab, delete the test clusters to avoid ongoing AWS charges:

```bash
# Delete ClusterDeployments (this destroys the underlying infrastructure)
kubectl delete clusterdeployment ml-dev -n kcm-system
kubectl delete clusterdeployment ml-training -n kcm-system

# Delete MultiClusterService
kubectl delete multiclusterservice ai-common-services -n kcm-system

# Monitor deletion
kubectl get clusterdeployments -n kcm-system -w
```

> **Warning:** Cluster deletion triggers infrastructure teardown (EC2 instances, VPCs, security groups). This is irreversible. Ensure any important data (model checkpoints, training logs) has been saved before deleting.

---

## Verification Checklist

Before proceeding, verify you have completed:

- [ ] Listed and examined shipped ClusterTemplates with versioned names
- [ ] Explored `status.config` to discover available parameters
- [ ] Deployed an AI development cluster with a single GPU worker (g5.xlarge)
- [ ] Deployed an AI training cluster with multi-GPU workers (p4d.24xlarge)
- [ ] Deployed GPU Operator and services via `serviceSpec`
- [ ] Deployed common services across AI clusters via `MultiClusterService`
- [ ] Scaled workers up and down on the training cluster
- [ ] Understand when custom ClusterTemplates are needed

## Troubleshooting

### ClusterTemplate Not Valid

```bash
# Check template status and validation errors
kubectl get clustertemplate <name> -n kcm-system -o jsonpath='{.status.validationError}'

# Check k0rdent controller logs
kubectl logs -n kcm-system -l app.kubernetes.io/name=kcm-controller-manager --tail=100
```

### ClusterDeployment Stuck Provisioning

```bash
# Check deployment status and conditions
kubectl describe clusterdeployment <name> -n kcm-system

# Check underlying CAPI Cluster resource
kubectl get cluster -n kcm-system -l cluster.x-k8s.io/cluster-name=<name> -o yaml

# Check machine provisioning status
kubectl get machines -n kcm-system -l cluster.x-k8s.io/cluster-name=<name>

# Check AWS CAPI provider logs for infrastructure errors
kubectl logs -n kcm-system -l cluster.x-k8s.io/provider=infrastructure-aws --tail=100
```

### GPU Nodes Not Reporting GPUs

```bash
# Verify GPU Operator pods are running on the workload cluster
KUBECONFIG=<cluster>.kubeconfig kubectl get pods -n gpu-operator

# Check GPU Operator logs for driver installation issues
KUBECONFIG=<cluster>.kubeconfig kubectl logs -n gpu-operator -l app=nvidia-driver-daemonset --tail=50

# Verify node labels
KUBECONFIG=<cluster>.kubeconfig kubectl get nodes -l nvidia.com/gpu.present=true
```

### Service Deployment Failures

```bash
# Check serviceSpec status on the ClusterDeployment
kubectl get clusterdeployment <name> -n kcm-system -o jsonpath='{.status.services}' | python3 -m json.tool

# Check that the ServiceTemplate exists
kubectl get servicetemplates -n kcm-system | grep gpu-operator

# If using MultiClusterService, check its status
kubectl describe multiclusterservice ai-common-services -n kcm-system
```

---

## Key Takeaways

1. **ClusterTemplates wrap Helm charts** that generate CAPI resources - parameters come from the chart, not the template
2. **`status.config` is your API reference** - it shows all available parameters after validation
3. **Same template, different configs** - dev, training, and inference clusters use the same template with different `spec.config` values
4. **`serviceSpec` automates Day-2 services** - GPU Operator, monitoring, and security tools deploy automatically
5. **`MultiClusterService` targets by labels** - deploy services across all AI clusters with `clusterLabels` matching
6. **ClusterTemplate spec is immutable** - create new versions instead of editing existing templates
7. **Custom templates are for advanced multi-pool scenarios** - shipped templates handle most single-pool GPU configurations

---

## Next Steps

After completing this lab, you can proceed to:

**ML Platform Track** (Recommended):
- [Lab 5.9 - Kubeflow ML Platform](lab-5.9-kubeflow-ml-platform.md) - End-to-end ML workflows

**Advanced Optimization Track**:
- [Lab 5.13 - TensorRT-LLM Optimization](lab-5.13-tensorrt-llm.md) - Advanced inference

**Or return to:**
- [Week 5 Overview](../README.md) - See all available labs
