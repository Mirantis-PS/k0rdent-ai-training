# Lab 5.12 - Slurm Operator for HPC

---

## Lab Navigation

| Track | Tier | Duration |
|-------|------|----------|
| ML Platforms | Optional | 3 hours |

### Week 5 Learning Paths

```
FOUNDATION (Required)                         ML PLATFORMS
━━━━━━━━━━━━━━━━━━━━                         ━━━━━━━━━━━━
5.1 ➔ 5.2 ➔ 5.3 ➔ 5.4 ➔ 5.5 ➔ 5.6          5.9 Kubeflow
                                                  ↓
                                              5.10 MLflow
                                                  ↓
                                              5.11 Run:AI
                                                  ↓
                                             YOU ARE HERE
                                                  ↓
                                             [5.12] Slurm
                                                  ↓
                                               Week 6
```

| Previous | Current | Next |
|----------|---------|------|
| [Lab 5.11 - Run:AI](lab-5.11-runai-gpu-orchestration.md) | **Lab 5.12 - Slurm** | [Week 6 - Multi-tenancy](../../week-6-multi-tenancy/README.md) |

---

**Duration:** 3 hours
**Type:** Hands-on Technical
**Environment:** GPU Lab

## Objective

Deploy and configure Slurm on Kubernetes using the Slinky Operator for HPC-style workload management, enabling traditional HPC users to submit jobs using familiar Slurm commands while leveraging Kubernetes infrastructure.

## Prerequisites

- Completed Lab 5.1 (GPU Scheduler deployed)
- Kubernetes cluster with 2+ GPU nodes
- NVIDIA GPU Operator v25.10.0 installed
- kubectl and helm installed
- Basic understanding of Slurm concepts (partitions, nodes, jobs)

## Background

### What is Slurm?

Slurm (Simple Linux Utility for Resource Management) is the dominant workload manager in HPC environments. It provides:
- **Job Scheduling**: FIFO, fair-share, and priority-based scheduling
- **Resource Management**: CPU, memory, GPU allocation
- **Accounting**: Track resource usage per user/project
- **Partitions**: Logical groupings of compute resources

### Slurm on Kubernetes Options

| Solution | Provider | Status | Use Case |
|----------|----------|--------|----------|
| **Slinky** | SchedMD | Official | Production HPC on K8s |
| **Soperator** | Nebius | Open Source | Managed Slurm clusters |
| **SUNK** | CoreWeave | Enterprise | Large-scale AI/HPC |

### Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster                            │
├─────────────────────────────────────────────────────────────────┤
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                  Slurm Control Plane                      │   │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────────────────┐   │   │
│  │  │ slurmctld│  │ slurmdbd │  │    slurm-operator    │   │   │
│  │  │ (Sched)  │  │  (DB)    │  │  (Reconciler)        │   │   │
│  │  └──────────┘  └──────────┘  └──────────────────────┘   │   │
│  └──────────────────────────────────────────────────────────┘   │
│                              ↓                                    │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                   Slurm Compute Nodes                     │   │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐               │   │
│  │  │ slurmd-0 │  │ slurmd-1 │  │ slurmd-2 │  ...          │   │
│  │  │ (GPU)    │  │ (GPU)    │  │ (GPU)    │               │   │
│  │  └──────────┘  └──────────┘  └──────────┘               │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

## Lab Environment

**Cluster Requirements:**
- Kubernetes 1.28+ with 2+ GPU nodes
- NVIDIA GPU Operator v25.10.0 installed
- 4+ GPUs total
- Shared storage (NFS or PVC)

## Tasks

### Task 1: Install Slinky Slurm Operator (30 min)

1. **Clone Slinky Repository**
   ```bash
   git clone https://github.com/SlinkyProject/slurm-operator.git
   cd slurm-operator
   ```

2. **Create Namespace**
   ```bash
   kubectl create namespace slurm-system
   ```

3. **Install CRDs**
   ```bash
   kubectl apply -f config/crd/bases/
   ```

4. **Deploy Slurm Operator**
   ```yaml
   # Save as slurm-operator-deployment.yaml
   apiVersion: apps/v1
   kind: Deployment
   metadata:
     name: slurm-operator
     namespace: slurm-system
   spec:
     replicas: 1
     selector:
       matchLabels:
         app: slurm-operator
     template:
       metadata:
         labels:
           app: slurm-operator
       spec:
         serviceAccountName: slurm-operator
         containers:
           - name: operator
             image: ghcr.io/slinkyproject/slurm-operator:latest
             command:
               - /manager
             args:
               - --leader-elect
             resources:
               limits:
                 cpu: 500m
                 memory: 256Mi
               requests:
                 cpu: 100m
                 memory: 128Mi
   ---
   apiVersion: v1
   kind: ServiceAccount
   metadata:
     name: slurm-operator
     namespace: slurm-system
   ---
   apiVersion: rbac.authorization.k8s.io/v1
   kind: ClusterRole
   metadata:
     name: slurm-operator
   rules:
     - apiGroups: [""]
       resources: ["pods", "services", "configmaps", "secrets", "persistentvolumeclaims"]
       verbs: ["*"]
     - apiGroups: ["apps"]
       resources: ["deployments", "statefulsets", "daemonsets"]
       verbs: ["*"]
     - apiGroups: ["slinky.slurm.net"]
       resources: ["*"]
       verbs: ["*"]
   ---
   apiVersion: rbac.authorization.k8s.io/v1
   kind: ClusterRoleBinding
   metadata:
     name: slurm-operator
   roleRef:
     apiGroup: rbac.authorization.k8s.io
     kind: ClusterRole
     name: slurm-operator
   subjects:
     - kind: ServiceAccount
       name: slurm-operator
       namespace: slurm-system
   ```

5. **Apply Operator**
   ```bash
   kubectl apply -f slurm-operator-deployment.yaml

   # Verify operator is running
   kubectl get pods -n slurm-system
   kubectl logs -n slurm-system -l app=slurm-operator --tail=20
   ```

### Task 2: Configure Shared Storage (15 min)

1. **Create NFS Storage for Slurm**
   ```yaml
   # Save as slurm-storage.yaml
   apiVersion: v1
   kind: PersistentVolumeClaim
   metadata:
     name: slurm-shared-storage
     namespace: slurm-system
   spec:
     accessModes:
       - ReadWriteMany
     resources:
       requests:
         storage: 100Gi
     storageClassName: nfs-client  # Adjust for your storage class
   ---
   apiVersion: v1
   kind: PersistentVolumeClaim
   metadata:
     name: slurm-state
     namespace: slurm-system
   spec:
     accessModes:
       - ReadWriteOnce
     resources:
       requests:
         storage: 10Gi
   ```

2. **Apply Storage**
   ```bash
   kubectl apply -f slurm-storage.yaml

   # If using local storage for testing, create a local PV
   cat <<EOF | kubectl apply -f -
   apiVersion: v1
   kind: PersistentVolume
   metadata:
     name: slurm-local-pv
   spec:
     capacity:
       storage: 100Gi
     accessModes:
       - ReadWriteMany
     hostPath:
       path: /var/slurm/shared
     storageClassName: manual
   EOF
   ```

### Task 3: Deploy Slurm Cluster (45 min)

1. **Create Slurm Configuration**
   ```yaml
   # Save as slurm-config.yaml
   apiVersion: v1
   kind: ConfigMap
   metadata:
     name: slurm-config
     namespace: slurm-system
   data:
     slurm.conf: |
       # Slurm Configuration
       ClusterName=k8s-hpc
       SlurmctldHost=slurmctld-0

       # Scheduling
       SchedulerType=sched/backfill
       SelectType=select/cons_tres
       SelectTypeParameters=CR_Core_Memory

       # Job Defaults
       DefMemPerCPU=4096
       MaxJobCount=10000
       MaxArraySize=1000

       # Logging
       SlurmctldLogFile=/var/log/slurm/slurmctld.log
       SlurmdLogFile=/var/log/slurm/slurmd.log

       # Accounting
       AccountingStorageType=accounting_storage/slurmdbd
       AccountingStorageHost=slurmdbd
       AccountingStoragePort=6819

       # GPU Configuration
       GresTypes=gpu

       # Partitions
       PartitionName=gpu Nodes=slurmd-[0-3] Default=YES MaxTime=INFINITE State=UP
       PartitionName=cpu Nodes=slurmd-[4-7] MaxTime=24:00:00 State=UP

       # Node Definitions (will be auto-populated by operator)
       NodeName=slurmd-[0-3] Gres=gpu:1 CPUs=8 RealMemory=32000 State=UNKNOWN
       NodeName=slurmd-[4-7] CPUs=8 RealMemory=32000 State=UNKNOWN

     gres.conf: |
       # GPU GRES Configuration
       NodeName=slurmd-[0-3] Name=gpu File=/dev/nvidia0

     cgroup.conf: |
       CgroupMountpoint=/sys/fs/cgroup
       CgroupPlugin=autodetect
       ConstrainCores=yes
       ConstrainDevices=yes
       ConstrainRAMSpace=yes
   ```

2. **Create Slurm Database Configuration**
   ```yaml
   # Save as slurmdbd-config.yaml
   apiVersion: v1
   kind: ConfigMap
   metadata:
     name: slurmdbd-config
     namespace: slurm-system
   data:
     slurmdbd.conf: |
       AuthType=auth/munge
       DbdHost=slurmdbd
       DbdPort=6819
       SlurmUser=slurm
       DebugLevel=verbose
       LogFile=/var/log/slurm/slurmdbd.log
       PidFile=/var/run/slurmdbd.pid
       StorageType=accounting_storage/mysql
       StorageHost=mysql
       StoragePort=3306
       StoragePass=slurm_password
       StorageUser=slurm
       StorageLoc=slurm_acct_db
   ```

3. **Deploy MySQL for Slurm Accounting**
   ```yaml
   # Save as mysql-deployment.yaml
   apiVersion: apps/v1
   kind: Deployment
   metadata:
     name: mysql
     namespace: slurm-system
   spec:
     replicas: 1
     selector:
       matchLabels:
         app: mysql
     template:
       metadata:
         labels:
           app: mysql
       spec:
         containers:
           - name: mysql
             image: mysql:8.0
             env:
               - name: MYSQL_ROOT_PASSWORD
                 value: "rootpassword"
               - name: MYSQL_DATABASE
                 value: "slurm_acct_db"
               - name: MYSQL_USER
                 value: "slurm"
               - name: MYSQL_PASSWORD
                 value: "slurm_password"
             ports:
               - containerPort: 3306
             volumeMounts:
               - name: mysql-data
                 mountPath: /var/lib/mysql
         volumes:
           - name: mysql-data
             emptyDir: {}
   ---
   apiVersion: v1
   kind: Service
   metadata:
     name: mysql
     namespace: slurm-system
   spec:
     selector:
       app: mysql
     ports:
       - port: 3306
         targetPort: 3306
   ```

4. **Deploy Slurm Control Plane**
   ```yaml
   # Save as slurm-control-plane.yaml
   apiVersion: apps/v1
   kind: StatefulSet
   metadata:
     name: slurmctld
     namespace: slurm-system
   spec:
     serviceName: slurmctld
     replicas: 1
     selector:
       matchLabels:
         app: slurmctld
     template:
       metadata:
         labels:
           app: slurmctld
       spec:
         containers:
           - name: slurmctld
             image: schedmd/slurm:24.05
             command: ["/usr/sbin/slurmctld", "-D", "-vvv"]
             ports:
               - containerPort: 6817
               - containerPort: 6818
             volumeMounts:
               - name: slurm-config
                 mountPath: /etc/slurm
               - name: munge-key
                 mountPath: /etc/munge
               - name: state
                 mountPath: /var/spool/slurmctld
               - name: logs
                 mountPath: /var/log/slurm
         volumes:
           - name: slurm-config
             configMap:
               name: slurm-config
           - name: munge-key
             secret:
               secretName: munge-key
           - name: state
             persistentVolumeClaim:
               claimName: slurm-state
           - name: logs
             emptyDir: {}
   ---
   apiVersion: v1
   kind: Service
   metadata:
     name: slurmctld
     namespace: slurm-system
   spec:
     selector:
       app: slurmctld
     ports:
       - name: slurmctld
         port: 6817
         targetPort: 6817
       - name: slurmd
         port: 6818
         targetPort: 6818
     clusterIP: None
   ---
   apiVersion: apps/v1
   kind: Deployment
   metadata:
     name: slurmdbd
     namespace: slurm-system
   spec:
     replicas: 1
     selector:
       matchLabels:
         app: slurmdbd
     template:
       metadata:
         labels:
           app: slurmdbd
       spec:
         containers:
           - name: slurmdbd
             image: schedmd/slurm:24.05
             command: ["/usr/sbin/slurmdbd", "-D", "-vvv"]
             ports:
               - containerPort: 6819
             volumeMounts:
               - name: slurmdbd-config
                 mountPath: /etc/slurm/slurmdbd.conf
                 subPath: slurmdbd.conf
               - name: munge-key
                 mountPath: /etc/munge
               - name: logs
                 mountPath: /var/log/slurm
         volumes:
           - name: slurmdbd-config
             configMap:
               name: slurmdbd-config
           - name: munge-key
             secret:
               secretName: munge-key
           - name: logs
             emptyDir: {}
   ---
   apiVersion: v1
   kind: Service
   metadata:
     name: slurmdbd
     namespace: slurm-system
   spec:
     selector:
       app: slurmdbd
     ports:
       - port: 6819
         targetPort: 6819
   ```

5. **Create Munge Key Secret**
   ```bash
   # Generate munge key
   dd if=/dev/urandom bs=1 count=1024 > munge.key

   # Create secret
   kubectl create secret generic munge-key \
     --from-file=munge.key=munge.key \
     -n slurm-system

   rm munge.key
   ```

6. **Deploy Slurm Compute Nodes (slurmd)**
   ```yaml
   # Save as slurmd-daemonset.yaml
   apiVersion: apps/v1
   kind: DaemonSet
   metadata:
     name: slurmd
     namespace: slurm-system
   spec:
     selector:
       matchLabels:
         app: slurmd
     template:
       metadata:
         labels:
           app: slurmd
       spec:
         nodeSelector:
           nvidia.com/gpu.present: "true"
         hostNetwork: true
         hostPID: true
         containers:
           - name: slurmd
             image: schedmd/slurm:24.05
             command: ["/usr/sbin/slurmd", "-D", "-vvv"]
             securityContext:
               privileged: true
             env:
               - name: SLURMD_NODENAME
                 valueFrom:
                   fieldRef:
                     fieldPath: spec.nodeName
             ports:
               - containerPort: 6818
             volumeMounts:
               - name: slurm-config
                 mountPath: /etc/slurm
               - name: munge-key
                 mountPath: /etc/munge
               - name: cgroup
                 mountPath: /sys/fs/cgroup
               - name: shared
                 mountPath: /shared
               - name: nvidia
                 mountPath: /dev/nvidia0
         volumes:
           - name: slurm-config
             configMap:
               name: slurm-config
           - name: munge-key
             secret:
               secretName: munge-key
           - name: cgroup
             hostPath:
               path: /sys/fs/cgroup
           - name: shared
             persistentVolumeClaim:
               claimName: slurm-shared-storage
           - name: nvidia
             hostPath:
               path: /dev/nvidia0
   ```

7. **Apply All Components**
   ```bash
   kubectl apply -f slurm-config.yaml
   kubectl apply -f slurmdbd-config.yaml
   kubectl apply -f mysql-deployment.yaml
   sleep 30  # Wait for MySQL
   kubectl apply -f slurm-control-plane.yaml
   sleep 30  # Wait for control plane
   kubectl apply -f slurmd-daemonset.yaml

   # Verify all components
   kubectl get pods -n slurm-system
   ```

### Task 4: Submit and Monitor Slurm Jobs (30 min)

1. **Create Slurm Client Pod**
   ```yaml
   # Save as slurm-client.yaml
   apiVersion: v1
   kind: Pod
   metadata:
     name: slurm-client
     namespace: slurm-system
   spec:
     containers:
       - name: client
         image: schedmd/slurm:24.05
         command: ["sleep", "infinity"]
         volumeMounts:
           - name: slurm-config
             mountPath: /etc/slurm
           - name: munge-key
             mountPath: /etc/munge
           - name: shared
             mountPath: /shared
     volumes:
       - name: slurm-config
         configMap:
           name: slurm-config
       - name: munge-key
         secret:
           secretName: munge-key
       - name: shared
         persistentVolumeClaim:
           claimName: slurm-shared-storage
   ```

2. **Access Slurm Client**
   ```bash
   kubectl apply -f slurm-client.yaml
   kubectl wait --for=condition=Ready pod/slurm-client -n slurm-system --timeout=120s

   # Exec into client
   kubectl exec -it -n slurm-system slurm-client -- bash
   ```

3. **Check Cluster Status (inside client pod)**
   ```bash
   # Check nodes
   sinfo

   # Expected output:
   # PARTITION AVAIL  TIMELIMIT  NODES  STATE NODELIST
   # gpu*      up     infinite      4   idle  slurmd-[0-3]
   # cpu       up    1-00:00:00     4   idle  slurmd-[4-7]

   # Detailed node info
   scontrol show nodes

   # Check partitions
   scontrol show partitions
   ```

4. **Submit a Simple Job**
   ```bash
   # Create job script
   cat > /shared/test-job.sh << 'EOF'
   #!/bin/bash
   #SBATCH --job-name=test-job
   #SBATCH --output=/shared/output-%j.txt
   #SBATCH --ntasks=1
   #SBATCH --cpus-per-task=2
   #SBATCH --mem=4G
   #SBATCH --time=00:10:00

   echo "Job started on $(hostname) at $(date)"
   echo "Working directory: $(pwd)"
   echo "CPU info:"
   lscpu | head -10
   sleep 30
   echo "Job completed at $(date)"
   EOF

   # Submit job
   sbatch /shared/test-job.sh

   # Check job status
   squeue
   ```

5. **Submit GPU Job**
   ```bash
   # Create GPU job script
   cat > /shared/gpu-job.sh << 'EOF'
   #!/bin/bash
   #SBATCH --job-name=gpu-test
   #SBATCH --output=/shared/gpu-output-%j.txt
   #SBATCH --partition=gpu
   #SBATCH --gres=gpu:1
   #SBATCH --ntasks=1
   #SBATCH --cpus-per-task=4
   #SBATCH --mem=16G
   #SBATCH --time=00:30:00

   echo "=== GPU Job Started ==="
   echo "Host: $(hostname)"
   echo "Date: $(date)"
   echo ""
   echo "=== GPU Information ==="
   nvidia-smi
   echo ""
   echo "=== Running CUDA Test ==="
   # Run a simple CUDA test if available
   python3 -c "import torch; print(f'CUDA available: {torch.cuda.is_available()}'); print(f'GPU: {torch.cuda.get_device_name(0)}' if torch.cuda.is_available() else 'No GPU')" 2>/dev/null || echo "PyTorch not installed"
   echo ""
   echo "=== Job Completed ==="
   EOF

   # Submit GPU job
   sbatch /shared/gpu-job.sh

   # Monitor
   squeue -l
   watch -n 2 squeue
   ```

6. **Submit Array Job**
   ```bash
   # Create array job
   cat > /shared/array-job.sh << 'EOF'
   #!/bin/bash
   #SBATCH --job-name=array-job
   #SBATCH --output=/shared/array-%A_%a.txt
   #SBATCH --array=1-10
   #SBATCH --ntasks=1
   #SBATCH --cpus-per-task=1
   #SBATCH --mem=1G
   #SBATCH --time=00:05:00

   echo "Array job: Task ID = $SLURM_ARRAY_TASK_ID"
   echo "Running on: $(hostname)"
   sleep $((SLURM_ARRAY_TASK_ID * 2))
   echo "Task $SLURM_ARRAY_TASK_ID completed"
   EOF

   # Submit
   sbatch /shared/array-job.sh

   # Watch array tasks
   squeue -r
   ```

### Task 5: Configure Slurm Accounting (20 min)

1. **Add Cluster to Accounting (inside client pod)**
   ```bash
   # Add cluster
   sacctmgr add cluster k8s-hpc

   # Create accounts
   sacctmgr add account research Description="Research Group"
   sacctmgr add account training Description="Training Jobs"
   sacctmgr add account production Description="Production Inference"

   # Add users
   sacctmgr add user researcher Account=research
   sacctmgr add user mleng Account=training
   sacctmgr add user inference Account=production

   # Set QOS (Quality of Service)
   sacctmgr add qos high Priority=100 MaxWall=48:00:00
   sacctmgr add qos normal Priority=50 MaxWall=24:00:00
   sacctmgr add qos low Priority=10 MaxWall=12:00:00

   # Associate QOS with accounts
   sacctmgr modify account research set qos=high
   sacctmgr modify account training set qos=normal
   sacctmgr modify account production set qos=high

   # Verify configuration
   sacctmgr show associations
   sacctmgr show qos
   ```

2. **View Job Accounting**
   ```bash
   # Show completed jobs
   sacct --starttime=2026-01-01 --format=JobID,JobName,Partition,State,Elapsed,MaxRSS

   # Show GPU usage
   sacct --starttime=2026-01-01 --format=JobID,JobName,AllocGRES,Elapsed,State

   # Usage report by account
   sreport cluster AccountUtilizationByUser start=2026-01-01
   ```

### Task 6: Integrate with Kubernetes Workloads (25 min)

1. **Create Slurm Job Submission Service**
   ```yaml
   # Save as slurm-submission-api.yaml
   apiVersion: v1
   kind: ConfigMap
   metadata:
     name: slurm-submission-script
     namespace: slurm-system
   data:
     submit.py: |
       #!/usr/bin/env python3
       from flask import Flask, request, jsonify
       import subprocess
       import os

       app = Flask(__name__)

       @app.route('/submit', methods=['POST'])
       def submit_job():
           data = request.json
           script_content = data.get('script', '')
           job_name = data.get('name', 'api-job')

           # Write script to shared storage
           script_path = f'/shared/jobs/{job_name}.sh'
           os.makedirs('/shared/jobs', exist_ok=True)

           with open(script_path, 'w') as f:
               f.write(script_content)

           # Submit job
           result = subprocess.run(
               ['sbatch', script_path],
               capture_output=True,
               text=True
           )

           if result.returncode == 0:
               job_id = result.stdout.strip().split()[-1]
               return jsonify({'status': 'submitted', 'job_id': job_id})
           else:
               return jsonify({'status': 'error', 'message': result.stderr}), 500

       @app.route('/status/<job_id>', methods=['GET'])
       def job_status(job_id):
           result = subprocess.run(
               ['squeue', '-j', job_id, '-o', '%T'],
               capture_output=True,
               text=True
           )

           if result.returncode == 0:
               lines = result.stdout.strip().split('\n')
               state = lines[1] if len(lines) > 1 else 'COMPLETED'
               return jsonify({'job_id': job_id, 'state': state})
           else:
               return jsonify({'job_id': job_id, 'state': 'UNKNOWN'})

       if __name__ == '__main__':
           app.run(host='0.0.0.0', port=8080)
   ---
   apiVersion: apps/v1
   kind: Deployment
   metadata:
     name: slurm-api
     namespace: slurm-system
   spec:
     replicas: 1
     selector:
       matchLabels:
         app: slurm-api
     template:
       metadata:
         labels:
           app: slurm-api
       spec:
         containers:
           - name: api
             image: python:3.11-slim
             command:
               - /bin/bash
               - -c
               - |
                 pip install flask
                 python /app/submit.py
             ports:
               - containerPort: 8080
             volumeMounts:
               - name: script
                 mountPath: /app
               - name: slurm-config
                 mountPath: /etc/slurm
               - name: munge-key
                 mountPath: /etc/munge
               - name: shared
                 mountPath: /shared
         volumes:
           - name: script
             configMap:
               name: slurm-submission-script
           - name: slurm-config
             configMap:
               name: slurm-config
           - name: munge-key
             secret:
               secretName: munge-key
           - name: shared
             persistentVolumeClaim:
               claimName: slurm-shared-storage
   ---
   apiVersion: v1
   kind: Service
   metadata:
     name: slurm-api
     namespace: slurm-system
   spec:
     selector:
       app: slurm-api
     ports:
       - port: 8080
         targetPort: 8080
   ```

2. **Test API Submission**
   ```bash
   kubectl apply -f slurm-submission-api.yaml

   # Port forward
   kubectl port-forward -n slurm-system svc/slurm-api 8080:8080 &

   # Submit job via API
   curl -X POST http://localhost:8080/submit \
     -H "Content-Type: application/json" \
     -d '{
       "name": "api-test-job",
       "script": "#!/bin/bash\n#SBATCH --job-name=api-test\n#SBATCH --output=/shared/api-output.txt\necho \"Submitted via API\"\nhostname\ndate"
     }'

   # Check status
   curl http://localhost:8080/status/<job_id>
   ```

## Deliverables

- [ ] **Screenshot** of `sinfo` showing cluster status
- [ ] **Job submission output** from sbatch command
- [ ] **GPU job output** showing nvidia-smi results
- [ ] **sacct output** showing job accounting
- [ ] **API test output** showing successful submission

## Verification Checklist

- [ ] Slurm control plane (slurmctld, slurmdbd) running
- [ ] Slurm compute nodes (slurmd) registered
- [ ] Basic job submission working
- [ ] GPU job scheduling functional
- [ ] Array jobs executing correctly
- [ ] Accounting database tracking jobs
- [ ] API submission service operational

## Troubleshooting

### Nodes Not Registering

**Check slurmd logs:**
```bash
kubectl logs -n slurm-system -l app=slurmd --tail=50
```

**Verify munge authentication:**
```bash
kubectl exec -n slurm-system -it slurm-client -- munge -n | unmunge
```

### Jobs Stuck in Pending

**Check reason:**
```bash
squeue -l
scontrol show job <job_id>
```

**Common reasons:**
- `Resources` - No nodes available with required resources
- `Priority` - Other jobs have higher priority
- `Dependency` - Waiting for dependent job

### GPU Not Available in Jobs

**Check GRES configuration:**
```bash
scontrol show nodes | grep Gres
```

**Verify GPU device access:**
```bash
kubectl exec -n slurm-system -it <slurmd-pod> -- ls -la /dev/nvidia*
```

### Database Connection Issues

**Check slurmdbd logs:**
```bash
kubectl logs -n slurm-system -l app=slurmdbd --tail=50
```

**Test MySQL connection:**
```bash
kubectl exec -n slurm-system -it deployment/mysql -- mysql -u slurm -pslurm_password slurm_acct_db -e "SHOW TABLES;"
```

## Key Takeaways

1. **Slurm on Kubernetes** enables HPC users to use familiar tools on cloud-native infrastructure
2. **Slinky Operator** manages Slurm components as Kubernetes resources
3. **GRES configuration** is essential for GPU job scheduling
4. **Accounting database** enables usage tracking and fair-share scheduling
5. **Shared storage** is required for job scripts and output files
6. **API integration** allows programmatic job submission from applications

## References

- [Slurm Documentation](https://slurm.schedmd.com/documentation.html)
- [Slinky Project](https://github.com/SlinkyProject/slurm-operator)
- [SchedMD Kubernetes Guide](https://slurm.schedmd.com/kubernetes.html)

## Next Steps

You have completed all AI Workload labs! Return to the main curriculum for Week 6: Multi-tenancy.
