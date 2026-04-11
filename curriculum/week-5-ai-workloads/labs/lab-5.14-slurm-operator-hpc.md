# Lab 5.14 - Slurm on Kubernetes for HPC Workloads

---

## Lab Navigation

| Track | Tier | Duration |
|-------|------|----------|
| Advanced | Optional | 3 hours |

### Week 5 Learning Paths

```
FOUNDATION (Completed)                        ADVANCED
━━━━━━━━━━━━━━━━━━━━━━                       ━━━━━━━━
5.1 ➔ 5.2 ➔ ... ➔ 5.8 ✓                     5.13 TensorRT-LLM
                                                  ↓
                                             YOU ARE HERE
                                                  ↓
                                             [5.14] Slurm
                                                  ↓
                                              5.15 RDMA Multi-Cloud
                                                  ↓
                                              5.16 Distributed Training
```

| Previous | Current | Next |
|----------|---------|------|
| [Lab 5.13 - TensorRT-LLM](lab-5.13-tensorrt-llm.md) | **Lab 5.14 - Slurm on Kubernetes** | [Lab 5.15 - RDMA Multi-Cloud](lab-5.15-rdma-multi-cloud.md) |

---

## Table of Contents

- [Objective](#objective)
- [Prerequisites](#prerequisites)
- [Background](#background)
- [Tasks](#tasks)
  - [Task 1: Install the Slinky Operator](#task-1-install-the-slinky-operator-20-min)
  - [Task 2: Deploy a Slurm Cluster](#task-2-deploy-a-slurm-cluster-30-min)
  - [Task 3: Submit and Monitor Slurm Jobs](#task-3-submit-and-monitor-slurm-jobs-30-min)
  - [Task 4: Configure Slurm Accounting](#task-4-configure-slurm-accounting-20-min)
  - [Task 5: Explore the Slurm REST API](#task-5-explore-the-slurm-rest-api-20-min)
  - [Task 6: Scale the Slurm Cluster](#task-6-scale-the-slurm-cluster-15-min)
  - [Task 7: Compare with Kueue](#task-7-compare-with-kueue-15-min)
  - [Task 8: k0rdent Integration](#task-8-k0rdent-integration-15-min)
- [Troubleshooting](#troubleshooting)
- [Verification Checklist](#verification-checklist)

---

**Duration:** 3 hours
**Type:** Hands-on Technical
**Environment:** GPU Lab

## Objective

Deploy Slurm on Kubernetes using the Slinky Operator (v1.1.0) to enable HPC-style workload management on k0rdent-managed clusters. You will install the operator via Helm, deploy a Slurm cluster using Slinky CRDs (NodeSet, LoginSet, Accounting), submit jobs using standard Slurm commands (`sbatch`, `srun`, `squeue`), configure accounting, and explore the Slurm REST API.

## Prerequisites

- Completed Lab 5.1 (GPU Operator deployed via k0rdent catalog)
- Kubernetes 1.29+ cluster with 2+ GPU nodes (k0rdent-managed)
- NVIDIA GPU Operator v25.3+ installed
- `kubectl` and `helm` (v3.14+) installed
- cert-manager installed (required by Slinky operator)
- ReadWriteMany storage available (NFS, EFS, or similar)
- Basic understanding of Slurm concepts (partitions, nodes, jobs)

## Background

### What is Slurm?

Slurm (Simple Linux Utility for Resource Management) is the dominant workload manager in HPC, running on more than half of the TOP500 supercomputers. It provides:

- **Job Scheduling**: Backfill, fair-share, priority-based, and preemptive scheduling
- **Resource Management**: CPU, memory, GPU (GRES) allocation with cgroup enforcement
- **Accounting**: Track resource usage per user, account, and QOS
- **Partitions**: Logical groupings of compute resources with different policies
- **Array Jobs**: Submit thousands of parametric tasks in a single command

> **Industry note:** NVIDIA announced it acquired SchedMD on December 15, 2025, and said it would continue distributing Slurm as open-source, vendor-neutral software. This is useful context for understanding why Slurm appears alongside other NVIDIA-adjacent AI infrastructure tools in this week.

### Slurm on Kubernetes: The Landscape

There are three main approaches to running Slurm on Kubernetes, plus a Kubernetes-native alternative:

| Solution | Provider | Approach | k0rdent Catalog |
|----------|----------|----------|-----------------|
| **Slinky** | SchedMD | Official operator + bridge | No |
| **Soperator** | Nebius | `SlurmCluster` CRD | **Yes** (`helm-soperator-1-22-1`) |
| **SUNK** | CoreWeave | Commercial, Slurm-as-K8s-scheduler | No |
| **Kueue** | kubernetes-sigs | K8s-native job queueing (alternative) | No |

This lab uses the **Slinky Operator** — the official, first-party project from SchedMD. Task 8 covers the k0rdent catalog integration using the Nebius Soperator.

### Slinky Architecture

The Slinky project has four sub-projects:

```
┌──────────────────────────────────────────────────────────────────┐
│                     Slinky Project (SchedMD)                      │
├──────────────────────┬───────────────────────────────────────────┤
│  slurm-operator      │  Run Slurm ON Kubernetes                  │
│  (This lab)          │  Manages Slurm as K8s pods via CRDs       │
│                      │  CRDs: NodeSet, LoginSet, Accounting      │
├──────────────────────┼───────────────────────────────────────────┤
│  slurm-bridge        │  Run Slurm AS a K8s scheduler             │
│  (Advanced)          │  Translates K8s Jobs/Pods → Slurm allocs  │
│                      │  K8s pods scheduled by Slurm              │
├──────────────────────┼───────────────────────────────────────────┤
│  slurm-client        │  Golang client for Slurm REST API         │
├──────────────────────┼───────────────────────────────────────────┤
│  containers          │  Slurm container images                    │
└──────────────────────┴───────────────────────────────────────────┘
```

The **operator mode** (this lab) is the right approach for giving HPC users their familiar Slurm interface while running on Kubernetes infrastructure:

```
┌─────────────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster                             │
├─────────────────────────────────────────────────────────────────┤
│  namespace: slinky                                                │
│  ┌──────────────────────────────────────────────────────────┐    │
│  │              Slinky Operator (Helm chart)                  │    │
│  │  Watches: NodeSet, LoginSet, Accounting, RestAPI CRDs     │    │
│  └──────────────────────────────────────────────────────────┘    │
│                                                                    │
│  namespace: slurm                                                  │
│  ┌──────────────────────────────────────────────────────────┐    │
│  │                  Slurm Cluster (Helm chart)                │    │
│  │  ┌────────────┐  ┌────────────┐  ┌────────────────────┐  │    │
│  │  │ slurmctld  │  │  slurmdbd  │  │  slurmrestd        │  │    │
│  │  │ (scheduler)│  │ (accounting│  │  (REST API)        │  │    │
│  │  │            │  │  + MariaDB)│  │                    │  │    │
│  │  └────────────┘  └────────────┘  └────────────────────┘  │    │
│  │                                                            │    │
│  │  ┌────────────┐  ┌────────────┐                           │    │
│  │  │ LoginSet   │  │  NodeSet   │ (slurmd compute nodes)   │    │
│  │  │ (sbatch/   │  │ ┌────────┐ │                           │    │
│  │  │  srun)     │  │ │slurmd-0│ │ (GPU)                    │    │
│  │  └────────────┘  │ │slurmd-1│ │ (GPU)                    │    │
│  │                   │ │slurmd-2│ │ (GPU)                    │    │
│  │                   │ └────────┘ │                           │    │
│  │                   └────────────┘                           │    │
│  └──────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
```

### Kueue: The Kubernetes-Native Alternative

For teams that don't need Slurm compatibility, **Kueue** (v0.16.1, kubernetes-sigs) provides Kubernetes-native job queueing:

| | Slurm (via Slinky) | Kueue |
|---|---|---|
| **Users interact with** | `sbatch`, `srun`, `squeue` | `kubectl`, standard K8s Jobs |
| **Scheduling** | Slurm scheduler (backfill, fair-share) | kube-scheduler (Kueue controls admission) |
| **Quotas** | Slurm accounts + QOS | ClusterQueue + ResourceFlavor CRDs |
| **Best for** | HPC teams migrating to K8s | Cloud-native teams |
| **Gang scheduling** | Built-in | Suspend-based gang admission |

## Lab Environment

**Cluster Requirements:**
- Kubernetes 1.29+ with 2+ GPU nodes
- NVIDIA GPU Operator installed
- cert-manager installed
- ReadWriteMany StorageClass available
- 4+ GPUs total across nodes
- cgroup v2 enabled on nodes
- Helm 3.14+

## Tasks

### Task 1: Install the Slinky Operator (20 min)

The Slinky operator is installed via three OCI-based Helm charts: CRDs, operator, and slurm cluster.

1. **Verify Prerequisites**

   ```bash
   # cert-manager must be running (required by Slinky webhooks)
   kubectl get pods -n cert-manager
   # Expected: cert-manager, cert-manager-cainjector, cert-manager-webhook

   # GPU Operator must be running
   kubectl get pods -n gpu-operator -l app.kubernetes.io/managed-by=gpu-operator

   # Verify cgroup v2 on a node
   kubectl get nodes -o jsonpath='{.items[0].status.nodeInfo.containerRuntimeVersion}'
   ```

   > If cert-manager is not installed:
   > ```bash
   > kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.17.2/cert-manager.yaml
   > kubectl wait --for=condition=Available deployment --all -n cert-manager --timeout=120s
   > ```

2. **Install Slinky CRDs**

   ```bash
   helm install slurm-operator-crds \
     oci://ghcr.io/slinkyproject/charts/slurm-operator-crds
   ```

3. **Install the Slinky Operator**

   ```bash
   helm install slurm-operator \
     oci://ghcr.io/slinkyproject/charts/slurm-operator \
     --namespace slinky \
     --create-namespace \
     --version 1.1.0
   ```

4. **Verify the Operator**

   ```bash
   # Operator pod should be Running
   kubectl get pods -n slinky

   # Verify CRDs are installed
   kubectl get crds | grep slinky.slurm.net

   # Expected CRDs:
   #   nodesets.slinky.slurm.net
   #   loginsets.slinky.slurm.net
   #   accountings.slinky.slurm.net
   #   restapis.slinky.slurm.net
   #   tokens.slinky.slurm.net
   ```

### Task 2: Deploy a Slurm Cluster (30 min)

The Slinky `slurm` Helm chart deploys a complete Slurm cluster using the operator's CRDs. It provisions `slurmctld` (scheduler), `slurmdbd` (accounting daemon), compute nodes (via NodeSet), and login nodes (via LoginSet).

1. **Create the Slurm Namespace**

   ```bash
   kubectl create namespace slurm
   ```

2. **Prepare Shared Storage**

   Slurm requires ReadWriteMany storage for job scripts and output. Create the PVC:

   ```yaml
   # Save as slurm-storage.yaml
   apiVersion: v1
   kind: PersistentVolumeClaim
   metadata:
     name: slurm-shared
     namespace: slurm
   spec:
     accessModes:
       - ReadWriteMany
     resources:
       requests:
         storage: 50Gi
     # Adjust StorageClass for your environment:
     # AWS EKS: efs-sc (requires EFS CSI driver)
     # On-prem: nfs-client
     # storageClassName: efs-sc
   ```

   ```bash
   kubectl apply -f slurm-storage.yaml
   ```

3. **Install the Slurm Cluster**

   ```bash
   helm install slurm \
     oci://ghcr.io/slinkyproject/charts/slurm \
     --namespace slurm \
     --version 1.1.0 \
     --set "slurm.clusterName=k8s-hpc" \
     --set "slurm.compute.gpu=true"
   ```

   > **Note:** The `slurm` Helm chart creates `slurmctld`, `slurmdbd` (with an embedded MariaDB), munge secrets, Slurm configuration, NodeSet (compute nodes), and LoginSet (login nodes) automatically. You do NOT need to create these manually.

4. **Verify the Slurm Cluster Components**

   ```bash
   # Check all pods in the slurm namespace
   kubectl get pods -n slurm

   # Expected pods (names will vary):
   #   slurm-slurmctld-0           (StatefulSet — Slurm controller)
   #   slurm-slurmdbd-0            (StatefulSet — accounting daemon)
   #   slurm-mariadb-0             (StatefulSet — accounting database)
   #   slurm-compute-*             (NodeSet — compute nodes)
   #   slurm-login-*               (LoginSet — login/submit nodes)

   # Check the Slinky CRD resources
   kubectl get nodesets -n slurm
   kubectl get loginsets -n slurm
   kubectl get accountings -n slurm
   ```

5. **Verify Slurm Cluster Health**

   ```bash
   # Exec into a login node to run Slurm commands
   LOGIN_POD=$(kubectl get pods -n slurm -l slinky.slurm.net/set-type=login -o jsonpath='{.items[0].metadata.name}')

   # Check cluster info
   kubectl exec -n slurm ${LOGIN_POD} -- sinfo

   # Expected output:
   # PARTITION AVAIL  TIMELIMIT  NODES  STATE NODELIST
   # batch*    up     infinite      N   idle  slurm-compute-[0-N]

   # Detailed node status
   kubectl exec -n slurm ${LOGIN_POD} -- scontrol show nodes

   # Check partitions
   kubectl exec -n slurm ${LOGIN_POD} -- scontrol show partitions
   ```

### Task 3: Submit and Monitor Slurm Jobs (30 min)

Access the Slurm login node to submit jobs using standard HPC commands.

1. **Get an Interactive Shell on the Login Node**

   ```bash
   LOGIN_POD=$(kubectl get pods -n slurm -l slinky.slurm.net/set-type=login -o jsonpath='{.items[0].metadata.name}')

   kubectl exec -it -n slurm ${LOGIN_POD} -- bash
   ```

   All subsequent commands in this task run **inside the login pod**.

2. **Submit a Simple CPU Job**

   ```bash
   cat > /tmp/test-job.sh << 'JOBEOF'
   #!/bin/bash
   #SBATCH --job-name=hello-slurm
   #SBATCH --output=/tmp/hello-%j.txt
   #SBATCH --ntasks=1
   #SBATCH --cpus-per-task=2
   #SBATCH --mem=2G
   #SBATCH --time=00:05:00

   echo "=== Slurm Job Started ==="
   echo "Job ID: ${SLURM_JOB_ID}"
   echo "Host: $(hostname)"
   echo "Date: $(date)"
   echo "CPUs allocated: ${SLURM_CPUS_ON_NODE}"
   echo "Memory: ${SLURM_MEM_PER_NODE} MB"
   sleep 10
   echo "=== Job Completed ==="
   JOBEOF

   sbatch /tmp/test-job.sh

   # Monitor the job
   squeue
   ```

3. **Submit a GPU Job**

   ```bash
   cat > /tmp/gpu-job.sh << 'JOBEOF'
   #!/bin/bash
   #SBATCH --job-name=gpu-test
   #SBATCH --output=/tmp/gpu-%j.txt
   #SBATCH --gres=gpu:1
   #SBATCH --ntasks=1
   #SBATCH --cpus-per-task=4
   #SBATCH --mem=8G
   #SBATCH --time=00:10:00

   echo "=== GPU Job Started ==="
   echo "Job ID: ${SLURM_JOB_ID}"
   echo "Host: $(hostname)"
   echo "GPUs allocated: ${CUDA_VISIBLE_DEVICES}"
   echo ""
   echo "=== nvidia-smi Output ==="
   nvidia-smi
   echo ""
   echo "=== Job Completed ==="
   JOBEOF

   sbatch /tmp/gpu-job.sh

   # Watch the job progress
   squeue -l
   ```

4. **Submit an Array Job**

   Array jobs run the same script with different `$SLURM_ARRAY_TASK_ID` values — ideal for hyperparameter sweeps:

   ```bash
   cat > /tmp/array-job.sh << 'JOBEOF'
   #!/bin/bash
   #SBATCH --job-name=sweep
   #SBATCH --output=/tmp/sweep-%A_%a.txt
   #SBATCH --array=1-5
   #SBATCH --ntasks=1
   #SBATCH --cpus-per-task=1
   #SBATCH --mem=1G
   #SBATCH --time=00:05:00

   echo "Array task ${SLURM_ARRAY_TASK_ID} of job ${SLURM_ARRAY_JOB_ID}"
   echo "Running on: $(hostname)"

   # Simulate different hyperparameters per task
   LEARNING_RATES=(0.001 0.005 0.01 0.05 0.1)
   LR=${LEARNING_RATES[$((SLURM_ARRAY_TASK_ID - 1))]}
   echo "Learning rate: ${LR}"
   sleep $((SLURM_ARRAY_TASK_ID * 3))
   echo "Task ${SLURM_ARRAY_TASK_ID} completed"
   JOBEOF

   sbatch /tmp/array-job.sh

   # View array tasks
   squeue -r
   ```

5. **Run an Interactive GPU Session**

   ```bash
   # Request an interactive session with 1 GPU
   srun --gres=gpu:1 --pty bash

   # Inside the interactive session:
   nvidia-smi
   echo "Interactive session on $(hostname) with GPU"

   # Exit the interactive session
   exit
   ```

6. **Check Job Results**

   ```bash
   # View completed jobs
   sacct --format=JobID,JobName,Partition,State,Elapsed,AllocGRES,ExitCode

   # View output of a specific job
   cat /tmp/hello-*.txt
   cat /tmp/gpu-*.txt
   ```

7. **Exit the Login Pod**

   ```bash
   exit
   ```

### Task 4: Configure Slurm Accounting (20 min)

Slurm accounting tracks resource usage per user, account, and QOS (Quality of Service). The Slinky Helm chart deploys `slurmdbd` with MariaDB automatically.

1. **Access the Login Node**

   ```bash
   kubectl exec -it -n slurm ${LOGIN_POD} -- bash
   ```

2. **Create Accounts and Users**

   ```bash
   # Add the cluster to accounting (if not auto-registered)
   sacctmgr -i add cluster k8s-hpc 2>/dev/null || echo "Cluster already exists"

   # Create organizational accounts
   sacctmgr -i add account research Description="Research Team"
   sacctmgr -i add account training Description="ML Training Team"
   sacctmgr -i add account production Description="Production Inference"

   # Add users to accounts
   sacctmgr -i add user researcher Account=research
   sacctmgr -i add user mleng Account=training
   sacctmgr -i add user inference Account=production

   # Verify
   sacctmgr show associations format=Cluster,Account,User,QOS
   ```

3. **Configure Quality of Service (QOS)**

   ```bash
   # Create QOS tiers with different priorities and limits
   sacctmgr -i add qos high Priority=100 MaxWall=48:00:00 MaxTRESPerUser=gres/gpu=4
   sacctmgr -i add qos normal Priority=50 MaxWall=24:00:00 MaxTRESPerUser=gres/gpu=2
   sacctmgr -i add qos low Priority=10 MaxWall=12:00:00 MaxTRESPerUser=gres/gpu=1

   # Assign QOS to accounts
   sacctmgr -i modify account training set qos=high
   sacctmgr -i modify account research set qos=normal
   sacctmgr -i modify account production set qos=high

   # View QOS configuration
   sacctmgr show qos format=Name,Priority,MaxWall,MaxTRESPerUser
   ```

4. **View Usage Reports**

   ```bash
   # Show recent job history
   sacct --starttime=now-1hour \
     --format=JobID,JobName,User,Account,Partition,State,Elapsed,AllocGRES,MaxRSS

   # GPU usage report
   sacct --starttime=now-1hour \
     --format=JobID,JobName,AllocGRES,Elapsed,State

   # Usage summary by account
   sreport cluster AccountUtilizationByUser start=now-1day

   # Top GPU users
   sreport user TopUsage start=now-1day TopCount=5
   ```

5. **Exit the Login Pod**

   ```bash
   exit
   ```

### Task 5: Explore the Slurm REST API (20 min)

Slurm includes a built-in REST API component (`slurmrestd`) that provides programmatic access to job submission, monitoring, and cluster management. The Slinky Helm chart can deploy this as a RestAPI CRD resource.

1. **Check if slurmrestd is Deployed**

   ```bash
   kubectl get restapis -n slurm
   kubectl get pods -n slurm -l slinky.slurm.net/set-type=restapi
   ```

2. **Port-Forward to the REST API**

   ```bash
   # Find the slurmrestd service
   kubectl get svc -n slurm | grep rest

   # Port-forward (adjust service name as needed)
   kubectl port-forward -n slurm svc/slurm-restapi 6820:6820 &
   ```

3. **Query Cluster Status via REST API**

   ```bash
   # Get cluster info (OpenAPI 0.0.40+ endpoints)
   curl -s http://localhost:6820/slurm/v0.0.40/nodes | jq '.nodes[] | {name, state}'

   # Get partition info
   curl -s http://localhost:6820/slurm/v0.0.40/partitions | jq '.partitions[] | {name, state}'

   # List jobs
   curl -s http://localhost:6820/slurm/v0.0.40/jobs | jq '.jobs[] | {job_id, name, job_state}'
   ```

4. **Submit a Job via REST API**

   ```bash
   curl -s -X POST http://localhost:6820/slurm/v0.0.40/job/submit \
     -H "Content-Type: application/json" \
     -d '{
       "job": {
         "name": "rest-api-test",
         "ntasks": 1,
         "cpus_per_task": 1,
         "time_limit": {
           "number": 5,
           "set": true
         },
         "environment": ["PATH=/usr/bin:/bin"],
         "script": "#!/bin/bash\necho \"Submitted via REST API\"\nhostname\ndate"
       }
     }' | jq .

   # Kill port-forward
   kill %1 2>/dev/null
   ```

   > **Why slurmrestd instead of a custom Flask app?** Slurmrestd is the official Slurm REST API, maintained by SchedMD, with OpenAPI documentation, authentication support (JWT tokens), and full Slurm feature coverage. Never build a custom wrapper when the native API exists.

### Task 6: Scale the Slurm Cluster (15 min)

The Slinky operator manages compute node scaling through the NodeSet CRD.

1. **View Current NodeSet**

   ```bash
   kubectl get nodesets -n slurm -o wide

   # Inspect the NodeSet spec
   kubectl get nodeset -n slurm -o yaml | head -40
   ```

2. **Scale Compute Nodes**

   ```bash
   # Scale up to 4 compute nodes (adjust name to match your NodeSet)
   NODESET_NAME=$(kubectl get nodesets -n slurm -o jsonpath='{.items[0].metadata.name}')

   kubectl patch nodeset ${NODESET_NAME} -n slurm \
     --type merge \
     -p '{"spec":{"replicas":4}}'

   # Watch new nodes come up
   kubectl get pods -n slurm -l slinky.slurm.net/set-type=compute -w
   ```

3. **Verify Slurm Sees the New Nodes**

   ```bash
   kubectl exec -n slurm ${LOGIN_POD} -- sinfo

   # All nodes should show as idle
   kubectl exec -n slurm ${LOGIN_POD} -- scontrol show nodes
   ```

4. **Scale Down**

   ```bash
   # Scale back to 2 nodes (Slinky handles graceful drain)
   kubectl patch nodeset ${NODESET_NAME} -n slurm \
     --type merge \
     -p '{"spec":{"replicas":2}}'

   # The operator will drain jobs from removed nodes before termination
   kubectl get pods -n slurm -l slinky.slurm.net/set-type=compute -w
   ```

### Task 7: Compare with Kueue (15 min)

For teams that don't need Slurm compatibility, Kueue provides Kubernetes-native job queueing using standard K8s resources.

1. **Understand the Kueue Architecture**

   ```
   Kueue Architecture (Kubernetes-native):
   ┌─────────────────────────────────────────────┐
   │  ResourceFlavor      (defines GPU types)     │
   │  ClusterQueue        (cluster-wide quotas)   │
   │  LocalQueue          (namespace quotas)       │
   │  Workload            (internal admission)     │
   └────────────────────┬────────────────────────┘
                        │ admission control
   ┌────────────────────▼────────────────────────┐
   │  Standard K8s Jobs, PyTorchJob, RayJob       │
   │  (Kueue suspends/unsuspends via spec.suspend)│
   └────────────────────┬────────────────────────┘
                        │ scheduling
   ┌────────────────────▼────────────────────────┐
   │  Default kube-scheduler (NOT replaced)        │
   └──────────────────────────────────────────────┘
   ```

   Key difference: Kueue does NOT replace the Kubernetes scheduler. It controls **admission** — whether a Job is allowed to run — by toggling the Job's `spec.suspend` field. Once admitted, the standard kube-scheduler places pods on nodes.

2. **When to Use Each**

   | Scenario | Recommended |
   |----------|-------------|
   | HPC team migrating from bare-metal Slurm | **Slurm (Slinky)** |
   | Cloud-native ML platform | **Kueue** |
   | Existing Slurm job scripts to preserve | **Slurm (Slinky)** |
   | Multi-tenant K8s with GPU quotas | **Kueue** or **KAI Scheduler** |
   | Need `sbatch`, `srun`, `scancel` | **Slurm (Slinky)** |
   | Need Kubernetes-native RBAC | **Kueue** |

   > **Both can coexist:** Some organizations run Slurm (via slurm-bridge) alongside Kueue — Slurm handles HPC workloads while Kueue manages cloud-native ML jobs, sharing the same GPU cluster.

### Task 8: k0rdent Integration (15 min)

The k0rdent catalog includes the **Nebius Soperator** — an alternative Slurm operator with its own `SlurmCluster` CRD.

1. **Available k0rdent Catalog Templates**

   | ServiceTemplate | Version | Description |
   |----------------|---------|-------------|
   | `helm-soperator-1-22-1` | 1.22.1 | Nebius Slurm Operator |
   | `helm-slurm-cluster-1-22-1` | 1.22.1 | Slurm cluster instance (requires soperator) |

2. **Install the Soperator from k0rdent Catalog**

   ```bash
   # Install the operator ServiceTemplate
   helm upgrade --install soperator \
     oci://ghcr.io/k0rdent/catalog/charts/kgst \
     --set "chart=soperator:1.22.1" \
     -n kcm-system

   # Install the slurm-cluster ServiceTemplate
   helm upgrade --install slurm-cluster \
     oci://ghcr.io/k0rdent/catalog/charts/kgst \
     --set "chart=slurm-cluster:1.22.1" \
     -n kcm-system
   ```

3. **Deploy via MultiClusterService**

   ```yaml
   # Save as slurm-multicluster.yaml
   apiVersion: k0rdent.mirantis.com/v1beta1
   kind: MultiClusterService
   metadata:
     name: slurm-hpc
     namespace: kcm-system
   spec:
     clusterSelector:
       matchLabels:
         workload-type: hpc
     serviceSpec:
       services:
         - template: gpu-operator-25-10-0
           name: gpu-operator
           namespace: gpu-operator
         - template: helm-soperator-1-22-1
           name: soperator
           namespace: soperator-system
         - template: helm-slurm-cluster-1-22-1
           name: slurm-cluster
           namespace: slurm
           values: |
             clusterName: k8s-hpc
             compute:
               replicas: 4
               gpu: true
       priority: 100
   ```

   > **Slinky vs Soperator on k0rdent:** The Nebius Soperator is in the k0rdent catalog because it's open-source and packaged as a Helm chart. The Slinky operator could also be used (same OCI Helm charts) but would require creating a custom ServiceTemplate. For automated multi-cluster deployment, the catalog-native Soperator is more convenient.

## Deliverables

- [ ] **Output** of `kubectl get pods -n slurm` showing all Slurm components running
- [ ] **Output** of `sinfo` showing cluster partition and node status
- [ ] **Job submission output** from `sbatch` with job ID
- [ ] **GPU job output** showing `nvidia-smi` from within a Slurm job
- [ ] **`sacct` output** showing job accounting history
- [ ] **REST API query** output showing cluster status via `curl`

## Verification Checklist

- [ ] Slinky operator v1.1.0 deployed in `slinky` namespace
- [ ] Slurm cluster deployed via Helm chart (slurmctld, slurmdbd, compute, login)
- [ ] `sinfo` shows compute nodes in idle state
- [ ] CPU job submitted and completed via `sbatch`
- [ ] GPU job submitted and completed with GRES allocation
- [ ] Array job submitted and completed
- [ ] Accounting configured with accounts, users, and QOS
- [ ] Slurm REST API accessible and responding
- [ ] NodeSet scaling (up and down) working

## Troubleshooting

### Slinky Operator Not Starting

**Check cert-manager is running:**
```bash
kubectl get pods -n cert-manager
# All pods must be Running before Slinky can start
```

**Check operator logs:**
```bash
kubectl logs -n slinky -l app.kubernetes.io/name=slurm-operator --tail=50
```

### Compute Nodes Not Registering with slurmctld

**Check NodeSet status:**
```bash
kubectl get nodesets -n slurm -o yaml
kubectl get pods -n slurm -l slinky.slurm.net/set-type=compute
```

**Check slurmd logs on a compute pod:**
```bash
COMPUTE_POD=$(kubectl get pods -n slurm -l slinky.slurm.net/set-type=compute -o jsonpath='{.items[0].metadata.name}')
kubectl logs -n slurm ${COMPUTE_POD} --tail=50
```

**Verify munge authentication between nodes:**
```bash
kubectl exec -n slurm ${LOGIN_POD} -- munge -n | kubectl exec -i -n slurm ${COMPUTE_POD} -- unmunge
```

### Jobs Stuck in Pending

**Check the reason:**
```bash
kubectl exec -n slurm ${LOGIN_POD} -- squeue -l
kubectl exec -n slurm ${LOGIN_POD} -- scontrol show job <job_id>
```

**Common pending reasons:**
- `Resources` — Not enough CPUs/GPUs/memory available
- `Priority` — Lower-priority job waiting for higher-priority jobs
- `QOSMaxGRESPerUser` — User exceeded QOS GPU limit
- `ReqNodeNotAvail` — Requested nodes are down or draining

### GPU Not Available in Jobs

**Check GRES configuration:**
```bash
kubectl exec -n slurm ${LOGIN_POD} -- scontrol show nodes | grep -A5 Gres
```

**Verify GPU Operator is working on compute nodes:**
```bash
kubectl exec -n slurm ${COMPUTE_POD} -- nvidia-smi
```

### Accounting Database Issues

**Check slurmdbd logs:**
```bash
kubectl logs -n slurm -l app=slurmdbd --tail=50
```

**Check MariaDB is running:**
```bash
kubectl get pods -n slurm -l app=mariadb
kubectl exec -n slurm -it <mariadb-pod> -- mysql -u slurm -e "SHOW DATABASES;"
```

## Key Takeaways

1. **Slinky** (v1.1.0) is the official operator for running Slurm on Kubernetes, using CRDs (`NodeSet`, `LoginSet`, `Accounting`) to manage the cluster lifecycle
2. **Slurm on K8s** preserves the HPC user experience (`sbatch`, `srun`, `squeue`) while leveraging Kubernetes infrastructure management, autoscaling, and GPU Operator integration
3. **NVIDIA's December 15, 2025 acquisition of SchedMD** is relevant industry context, but platform decisions should still be based on current product documentation, support terms, and ecosystem fit
4. **slurmrestd** is the built-in Slurm REST API — always use it instead of building custom wrappers
5. **Kueue** (kubernetes-sigs) is the Kubernetes-native alternative for teams that don't need Slurm compatibility
6. **k0rdent catalog** provides the Nebius Soperator for automated Slurm deployment on managed clusters via MultiClusterService

## References

- [Slinky Official Documentation](https://slinky.schedmd.com/)
- [Slinky slurm-operator GitHub](https://github.com/SlinkyProject/slurm-operator)
- [Slinky slurm-bridge GitHub](https://github.com/SlinkyProject/slurm-bridge)
- [Slurm Documentation](https://slurm.schedmd.com/documentation.html)
- [Slurm 25.11 Release Notes](https://slurm.schedmd.com/release_notes.html)
- [NVIDIA Acquires SchedMD (Dec 15, 2025)](https://blogs.nvidia.com/blog/nvidia-acquires-schedmd/)
- [Running Slurm on Amazon EKS with Slinky (AWS Blog)](https://aws.amazon.com/blogs/containers/running-slurm-on-amazon-eks-with-slinky/)
- [Nebius Soperator GitHub](https://github.com/nebius/soperator)
- [k0rdent Catalog — Soperator](https://catalog.k0rdent.io/v1.5.0/apps/soperator/)
- [Kueue Documentation](https://kueue.sigs.k8s.io/)

## Next Steps

You have completed all AI Workload labs! Return to the main curriculum for Week 6: Multi-tenancy.
