# Lab 5.8 - Cluster Templates for AI Workloads

**Duration:** 2.5 hours
**Type:** Hands-on Technical
**Environment:** GPU Lab

## Objective

Design and deploy reusable Kubernetes cluster templates optimized for AI/ML workloads, including GPU configurations, storage classes, and pre-installed AI tooling.

## Prerequisites

- Completed Lab 5.1 (GPU Scheduler deployed)
- Understanding of Cluster API concepts
- Familiarity with Helm and Kubernetes manifests

## Background

### What are Cluster Templates?

Cluster Templates define reusable configurations for Kubernetes clusters, including:
- Node specifications (CPU, memory, GPU)
- Network configuration
- Pre-installed addons (GPU Operator, monitoring, etc.)
- Storage classes and persistent volumes
- Security policies and RBAC

### Template Categories for AI Workloads

| Template | Use Case | GPUs | Typical Size |
|----------|----------|------|--------------|
| **ai-dev** | Development/experimentation | 1-2 | Small |
| **ai-training** | Model training | 4-8 | Medium-Large |
| **ai-inference** | Production serving | 1-4 | Medium |
| **ai-hpc** | Distributed training | 8+ | Large |

## Lab Environment

**Requirements:**
- Management cluster with Cluster API
- Access to GPU node pools
- Storage provisioner (CSI driver)

## Tasks

### Task 1: Understand Cluster Template Structure (20 min)

1. **Review ClusterClass CRD**
   ```bash
   # Check if ClusterClass is available
   kubectl api-resources | grep clusterclass

   # View existing cluster classes
   kubectl get clusterclass -A
   ```

2. **Examine Template Components**
   ```yaml
   # ClusterClass structure overview
   # - Infrastructure templates (nodes, networks)
   # - Control plane templates
   # - Machine deployment templates
   # - Variables for customization
   # - Patches for modifications
   ```

3. **List Available Machine Templates**
   ```bash
   # For cloud provider (AWS example)
   kubectl get awsmachinetemplates -A

   # For bare metal
   kubectl get metal3machinetemplates -A
   ```

### Task 2: Create AI Development Cluster Template (35 min)

1. **Define ClusterClass for AI Dev**
   ```yaml
   # Save as ai-dev-clusterclass.yaml
   apiVersion: cluster.x-k8s.io/v1beta1
   kind: ClusterClass
   metadata:
     name: ai-dev
     namespace: default
   spec:
     controlPlane:
       ref:
         apiVersion: controlplane.cluster.x-k8s.io/v1beta1
         kind: KubeadmControlPlaneTemplate
         name: ai-dev-control-plane
       machineInfrastructure:
         ref:
           apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
           kind: AWSMachineTemplate
           name: ai-dev-control-plane-machine

     infrastructure:
       ref:
         apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
         kind: AWSClusterTemplate
         name: ai-dev-cluster

     workers:
       machineDeployments:
         - class: cpu-worker
           template:
             bootstrap:
               ref:
                 apiVersion: bootstrap.cluster.x-k8s.io/v1beta1
                 kind: KubeadmConfigTemplate
                 name: ai-dev-worker-bootstrap
             infrastructure:
               ref:
                 apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
                 kind: AWSMachineTemplate
                 name: ai-dev-cpu-worker

         - class: gpu-worker
           template:
             bootstrap:
               ref:
                 apiVersion: bootstrap.cluster.x-k8s.io/v1beta1
                 kind: KubeadmConfigTemplate
                 name: ai-dev-gpu-worker-bootstrap
             infrastructure:
               ref:
                 apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
                 kind: AWSMachineTemplate
                 name: ai-dev-gpu-worker

     variables:
       - name: gpuType
         required: false
         schema:
           openAPIV3Schema:
             type: string
             default: "nvidia-a10g"
             enum:
               - nvidia-t4
               - nvidia-a10g
               - nvidia-a100
               - nvidia-h100

       - name: gpuCount
         required: false
         schema:
           openAPIV3Schema:
             type: integer
             default: 1
             minimum: 1
             maximum: 8

       - name: enableMonitoring
         required: false
         schema:
           openAPIV3Schema:
             type: boolean
             default: true

       - name: storageClass
         required: false
         schema:
           openAPIV3Schema:
             type: string
             default: "gp3"

     patches:
       - name: gpu-node-labels
         definitions:
           - selector:
               apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
               kind: AWSMachineTemplate
               matchResources:
                 machineDeploymentClass:
                   names:
                     - gpu-worker
             jsonPatches:
               - op: add
                 path: /spec/template/spec/additionalTags
                 valueFrom:
                   template: |
                     k0rdent.io/gpu-type: {{ .gpuType }}
                     k0rdent.io/gpu-count: "{{ .gpuCount }}"
   ```

2. **Create GPU Worker Machine Template**
   ```yaml
   # Save as ai-dev-gpu-worker-template.yaml
   apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
   kind: AWSMachineTemplate
   metadata:
     name: ai-dev-gpu-worker
     namespace: default
   spec:
     template:
       spec:
         instanceType: g5.xlarge  # NVIDIA A10G
         ami:
           id: ami-0abcdef1234567890  # GPU-optimized AMI
         additionalSecurityGroups:
           - id: sg-gpu-workloads
         rootVolume:
           size: 200
           type: gp3
           iops: 3000
           throughput: 125
         additionalTags:
           node-role: gpu-worker
           gpu-enabled: "true"
   ```

3. **Create Bootstrap Configuration with GPU Support**
   ```yaml
   # Save as ai-dev-gpu-bootstrap.yaml
   apiVersion: bootstrap.cluster.x-k8s.io/v1beta1
   kind: KubeadmConfigTemplate
   metadata:
     name: ai-dev-gpu-worker-bootstrap
     namespace: default
   spec:
     template:
       spec:
         joinConfiguration:
           nodeRegistration:
             kubeletExtraArgs:
               feature-gates: "DevicePlugins=true"
             taints:
               - key: nvidia.com/gpu
                 value: "true"
                 effect: NoSchedule
         preKubeadmCommands:
           - |
             # Install NVIDIA drivers
             apt-get update
             apt-get install -y nvidia-driver-570 nvidia-container-toolkit

             # Configure containerd for NVIDIA
             nvidia-ctk runtime configure --runtime=containerd
             systemctl restart containerd
         files:
           - path: /etc/modules-load.d/nvidia.conf
             content: |
               nvidia
               nvidia_uvm
             owner: root:root
             permissions: "0644"
   ```

4. **Apply Templates**
   ```bash
   kubectl apply -f ai-dev-clusterclass.yaml
   kubectl apply -f ai-dev-gpu-worker-template.yaml
   kubectl apply -f ai-dev-gpu-bootstrap.yaml
   ```

### Task 3: Create AI Training Cluster Template (35 min)

1. **Define Multi-GPU Training Template**
   ```yaml
   # Save as ai-training-clusterclass.yaml
   apiVersion: cluster.x-k8s.io/v1beta1
   kind: ClusterClass
   metadata:
     name: ai-training
     namespace: default
   spec:
     controlPlane:
       ref:
         apiVersion: controlplane.cluster.x-k8s.io/v1beta1
         kind: KubeadmControlPlaneTemplate
         name: ai-training-control-plane
       machineInfrastructure:
         ref:
           apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
           kind: AWSMachineTemplate
           name: ai-training-control-plane-machine

     infrastructure:
       ref:
         apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
         kind: AWSClusterTemplate
         name: ai-training-cluster

     workers:
       machineDeployments:
         - class: multi-gpu-worker
           template:
             bootstrap:
               ref:
                 apiVersion: bootstrap.cluster.x-k8s.io/v1beta1
                 kind: KubeadmConfigTemplate
                 name: ai-training-multigpu-bootstrap
             infrastructure:
               ref:
                 apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
                 kind: AWSMachineTemplate
                 name: ai-training-multigpu-worker

     variables:
       - name: instanceType
         required: true
         schema:
           openAPIV3Schema:
             type: string
             enum:
               - p4d.24xlarge   # 8x A100
               - p5.48xlarge    # 8x H100

       - name: workerCount
         required: false
         schema:
           openAPIV3Schema:
             type: integer
             default: 2
             minimum: 1
             maximum: 16

       - name: enableEFA
         required: false
         schema:
           openAPIV3Schema:
             type: boolean
             default: true
             description: "Enable Elastic Fabric Adapter for distributed training"

       - name: enableNVLink
         required: false
         schema:
           openAPIV3Schema:
             type: boolean
             default: true

     patches:
       - name: efa-configuration
         enabledIf: "{{ .enableEFA }}"
         definitions:
           - selector:
               apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
               kind: AWSMachineTemplate
               matchResources:
                 machineDeploymentClass:
                   names:
                     - multi-gpu-worker
             jsonPatches:
               - op: add
                 path: /spec/template/spec/networkInterfaces
                 value:
                   - deviceIndex: 1
                     networkInterfaceType: efa
   ```

2. **Create Multi-GPU Worker Template**
   ```yaml
   # Save as ai-training-multigpu-template.yaml
   apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
   kind: AWSMachineTemplate
   metadata:
     name: ai-training-multigpu-worker
     namespace: default
   spec:
     template:
       spec:
         instanceType: p4d.24xlarge
         ami:
           id: ami-nvidia-dl-base  # NVIDIA Deep Learning AMI
         rootVolume:
           size: 500
           type: gp3
           iops: 16000
           throughput: 1000
         additionalSecurityGroups:
           - id: sg-gpu-training
         placementGroupName: ml-training-pg
         placementGroupPartition: 1
         additionalTags:
           nvidia.com/gpu-count: "8"
           nvidia.com/gpu-product: "NVIDIA-A100-SXM4-40GB"
           k0rdent.io/workload-type: "training"
   ```

3. **Apply Training Templates**
   ```bash
   kubectl apply -f ai-training-clusterclass.yaml
   kubectl apply -f ai-training-multigpu-template.yaml
   ```

### Task 4: Create AI Inference Cluster Template (30 min)

1. **Define Inference-Optimized Template**
   ```yaml
   # Save as ai-inference-clusterclass.yaml
   apiVersion: cluster.x-k8s.io/v1beta1
   kind: ClusterClass
   metadata:
     name: ai-inference
     namespace: default
   spec:
     controlPlane:
       ref:
         apiVersion: controlplane.cluster.x-k8s.io/v1beta1
         kind: KubeadmControlPlaneTemplate
         name: ai-inference-control-plane
       machineInfrastructure:
         ref:
           apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
           kind: AWSMachineTemplate
           name: ai-inference-control-plane-machine

     infrastructure:
       ref:
         apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
         kind: AWSClusterTemplate
         name: ai-inference-cluster

     workers:
       machineDeployments:
         - class: inference-worker
           template:
             bootstrap:
               ref:
                 apiVersion: bootstrap.cluster.x-k8s.io/v1beta1
                 kind: KubeadmConfigTemplate
                 name: ai-inference-worker-bootstrap
             infrastructure:
               ref:
                 apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
                 kind: AWSMachineTemplate
                 name: ai-inference-worker

     variables:
       - name: gpuType
         required: true
         schema:
           openAPIV3Schema:
             type: string
             enum:
               - nvidia-t4      # Cost-effective inference
               - nvidia-l4      # Balanced performance
               - nvidia-a10g    # High throughput
               - nvidia-h100    # Maximum performance

       - name: enableAutoscaling
         required: false
         schema:
           openAPIV3Schema:
             type: boolean
             default: true

       - name: minReplicas
         required: false
         schema:
           openAPIV3Schema:
             type: integer
             default: 2
             minimum: 1

       - name: maxReplicas
         required: false
         schema:
           openAPIV3Schema:
             type: integer
             default: 10
             maximum: 50

       - name: modelServingFramework
         required: false
         schema:
           openAPIV3Schema:
             type: string
             default: "vllm"
             enum:
               - vllm
               - triton
               - tgi
   ```

2. **Create Inference Worker Template**
   ```yaml
   # Save as ai-inference-worker-template.yaml
   apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
   kind: AWSMachineTemplate
   metadata:
     name: ai-inference-worker
     namespace: default
   spec:
     template:
       spec:
         instanceType: g5.2xlarge
         ami:
           id: ami-inference-optimized
         rootVolume:
           size: 100
           type: gp3
         additionalTags:
           k0rdent.io/workload-type: "inference"
           k0rdent.io/scaling-enabled: "true"
   ```

### Task 5: Deploy Cluster from Template (25 min)

1. **Create AI Dev Cluster Instance**
   ```yaml
   # Save as techcorp-ai-dev.yaml
   apiVersion: cluster.x-k8s.io/v1beta1
   kind: Cluster
   metadata:
     name: techcorp-ai-dev
     namespace: tenant-techcorp
   spec:
     topology:
       class: ai-dev
       version: v1.32.4
       controlPlane:
         replicas: 3
       workers:
         machineDeployments:
           - class: cpu-worker
             name: cpu-pool
             replicas: 2
           - class: gpu-worker
             name: gpu-pool
             replicas: 2
       variables:
         - name: gpuType
           value: nvidia-a10g
         - name: gpuCount
           value: 1
         - name: enableMonitoring
           value: true
         - name: storageClass
           value: gp3
   ```

2. **Apply and Monitor**
   ```bash
   kubectl apply -f techcorp-ai-dev.yaml

   # Watch cluster provisioning
   kubectl get clusters -n tenant-techcorp -w

   # Check machine deployments
   kubectl get machinedeployments -n tenant-techcorp

   # View detailed status
   clusterctl describe cluster techcorp-ai-dev -n tenant-techcorp
   ```

3. **Get Kubeconfig for New Cluster**
   ```bash
   clusterctl get kubeconfig techcorp-ai-dev -n tenant-techcorp > techcorp-ai-dev.kubeconfig

   export KUBECONFIG=techcorp-ai-dev.kubeconfig
   kubectl get nodes
   ```

### Task 6: Verify Template-Based Deployment (15 min)

1. **Verify GPU Nodes**
   ```bash
   kubectl get nodes -l node-role=gpu-worker

   kubectl describe nodes -l node-role=gpu-worker | grep -A10 "Allocatable:"
   ```

2. **Test GPU Workload**
   ```bash
   cat <<EOF | kubectl apply -f -
   apiVersion: v1
   kind: Pod
   metadata:
     name: template-gpu-test
   spec:
     restartPolicy: Never
     containers:
       - name: cuda-test
         image: nvcr.io/nvidia/cuda:12.6.0-base-ubuntu22.04
         command: ["nvidia-smi"]
         resources:
           limits:
             nvidia.com/gpu: 1
   EOF

   kubectl wait --for=condition=Completed pod/template-gpu-test --timeout=120s
   kubectl logs template-gpu-test
   ```

3. **Verify Pre-installed Addons**
   ```bash
   # Check GPU Operator (should be pre-installed)
   kubectl get pods -n gpu-operator

   # Check monitoring stack
   kubectl get pods -n monitoring
   ```

## Deliverables

- [ ] **ClusterClass definitions** for ai-dev, ai-training, ai-inference
- [ ] **Machine templates** for GPU workers
- [ ] **Working cluster** deployed from template
- [ ] **GPU verification** output from deployed cluster
- [ ] **Documentation** of template variables and their effects

## Verification Checklist

- [ ] All ClusterClass resources created
- [ ] Machine templates applied
- [ ] Cluster provisioned from template
- [ ] GPU nodes labeled correctly
- [ ] GPU workloads scheduled successfully
- [ ] Addons deployed automatically

## Troubleshooting

### Cluster Fails to Provision

**Check ClusterClass:**
```bash
kubectl describe clusterclass ai-dev
kubectl get events --field-selector involvedObject.name=techcorp-ai-dev
```

### GPU Nodes Not Ready

**Check machine status:**
```bash
kubectl get machines -n tenant-techcorp
kubectl describe machine <machine-name> -n tenant-techcorp
```

### Bootstrap Fails

**Check bootstrap config:**
```bash
kubectl logs -n capi-system -l control-plane=controller-manager
```

## Key Takeaways

1. **ClusterClass enables reusable templates** for consistent cluster deployments
2. **Variables allow customization** without modifying base templates
3. **Patches apply conditional configurations** based on variable values
4. **Bootstrap configs** handle GPU driver installation during node provisioning
5. **Machine templates** define hardware specifications per workload type

## Next Lab

Proceed to [Lab 5.9 - Kubeflow ML Platform](lab-5.9-kubeflow.md)
