# Lab 5.10 - MLflow Experiment Tracking

---

## Lab Navigation

| Track | Tier | Duration |
|-------|------|----------|
| ML Platforms | Recommended | 2.5 hours |

### Week 5 Learning Paths

```
FOUNDATION (Completed)                        ML PLATFORMS
━━━━━━━━━━━━━━━━━━━━━━                       ━━━━━━━━━━━━
5.1 ➔ 5.2 ➔ 5.3 ➔ 5.4 ➔ 5.5                5.9 Kubeflow
     ➔ 5.6 ➔ 5.7 ➔ 5.8 ✓                        ↓
                                             YOU ARE HERE
                                                  ↓
                                             [5.10] MLflow
```

| Previous | Current | Next |
|----------|---------|------|
| [Lab 5.9 - Kubeflow](lab-5.9-kubeflow-ml-platform.md) | **Lab 5.10 - MLflow** | Choose: [Lab 5.11 - FIPS](lab-5.11-nvidia-fips.md) or [Lab 5.13 - TensorRT-LLM](lab-5.13-tensorrt-llm.md) |

---

**Duration:** 2.5 hours
**Type:** Hands-on Technical
**Environment:** GPU Lab

## Table of Contents

- [Objective](#objective)
- [Prerequisites](#prerequisites)
- [k0rdent Context](#k0rdent-context)
- [Lab Environment](#lab-environment)
- [Tasks](#tasks)
  - [Task 1: Access the k0rdent-Managed GPU Cluster](#task-1-access-the-k0rdent-managed-gpu-cluster-10-min)
  - [Task 2: Deploy MLflow via k0rdent ServiceTemplate](#task-2-deploy-mlflow-via-k0rdent-servicetemplate-20-min)
  - [Task 3: Manual MLflow Deployment](#task-3-manual-mlflow-deployment-30-min)
  - [Task 4: Configure Client and Log GPU Experiments](#task-4-configure-client-and-log-gpu-experiments-30-min)
  - [Task 5: Kubernetes Training Job with MLflow](#task-5-kubernetes-training-job-with-mlflow-30-min)
  - [Task 6: Model Registry with Aliases](#task-6-model-registry-with-aliases-25-min)
- [Deliverables](#deliverables)
- [Verification Checklist](#verification-checklist)
- [Troubleshooting](#troubleshooting)
- [Key Takeaways](#key-takeaways)
- [Next Lab](#next-lab)

## Objective

Deploy MLflow as a centralized experiment tracking server on a k0rdent-managed GPU cluster, configure artifact storage with MinIO, and integrate it with GPU-based training workflows using the modern MLflow 3.x API for ML lifecycle management.

## Prerequisites

- Completed Lab 5.1 (GPU Scheduler deployed)
- k0rdent Enterprise management cluster operational
- At least one k0rdent-managed GPU cluster deployed
- Python 3.10+ (required for MLflow 3.x)

## k0rdent Context

### MLflow in the k0rdent Ecosystem

The k0rdent catalog includes the `mlflow-1-7-1` ServiceTemplate, which deploys the MLflow community Helm chart (version 1.7.1). This provides a production-ready MLflow tracking server with PostgreSQL backend and S3-compatible artifact storage.

```
┌─────────────────────────────────────────────────────────────────────┐
│                   k0rdent Management Cluster                        │
│                                                                     │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐  │
│  │  ServiceTemplate │  │ MultiCluster     │  │ ClusterDeployment│  │
│  │  mlflow-1-7-1    │  │ Service          │  │ (GPU clusters)   │  │
│  └────────┬─────────┘  └────────┬─────────┘  └────────┬─────────┘  │
│           │                     │                      │            │
│           └─────────────────────┼──────────────────────┘            │
│                                 │ Sveltos                           │
│                                 ▼                                   │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │              Workload Cluster (GPU)                           │   │
│  │  ┌─────────────┐  ┌──────────┐  ┌───────────┐               │   │
│  │  │ MLflow      │  │ MinIO    │  │PostgreSQL │               │   │
│  │  │ Tracking    │  │ Artifacts│  │ Backend   │               │   │
│  │  │ Server      │  │ Store    │  │ Store     │               │   │
│  │  └──────┬──────┘  └──────────┘  └───────────┘               │   │
│  │         │                                                    │   │
│  │  ┌──────┴──────────────────────────────────────────┐         │   │
│  │  │          GPU Training Jobs                       │         │   │
│  │  │  ┌────────┐  ┌────────┐  ┌────────┐            │         │   │
│  │  │  │ Run 1  │  │ Run 2  │  │ Run N  │            │         │   │
│  │  │  └────────┘  └────────┘  └────────┘            │         │   │
│  │  └─────────────────────────────────────────────────┘         │   │
│  └──────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
```

### MLflow 3.x Migration Notes

MLflow 3.0 introduced significant breaking changes. This lab uses the current MLflow 3.x API:

| Feature | Old (MLflow 2.x) | Current (MLflow 3.x) |
|---------|-------------------|----------------------|
| Model stages | `transition_model_version_stage("Production")` | `set_registered_model_alias("champion", version)` |
| Model URI | `models:/name/Production` | `models:/name@champion` |
| Health check | `/api/2.0/mlflow/experiments/search` | `/health` |
| Python | 3.8+ | 3.10+ |
| Registry default | File store | SQLAlchemy store |

## Lab Environment

**Cluster Requirements:**
- Kubernetes 1.28+ with GPU nodes
- NVIDIA GPU Operator v25.10.0 installed
- StorageClass `ebs-gp3` available (AWS EBS)
- 4+ vCPUs, 8GB+ RAM for MLflow server
- 50GB storage for artifacts

## Tasks

### Task 1: Access the k0rdent-Managed GPU Cluster (10 min)

All operations in this lab target a workload cluster managed by k0rdent Enterprise. First, extract the kubeconfig from the management cluster.

1. **Identify your GPU cluster**
   ```bash
   # On the management cluster
   kubectl get clusterdeployments -n kcm-system
   ```

2. **Extract the workload cluster kubeconfig**
   ```bash
   export CLUSTER_NAME=gpu-cluster-01
   kubectl get secret ${CLUSTER_NAME}-kubeconfig \
     -n kcm-system \
     -o jsonpath='{.data.value}' | base64 -d > /tmp/${CLUSTER_NAME}.kubeconfig
   export KUBECONFIG=/tmp/${CLUSTER_NAME}.kubeconfig
   ```

3. **Verify GPU availability on the workload cluster**
   ```bash
   kubectl get nodes -l nvidia.com/gpu.present=true
   kubectl get pods -n gpu-operator -l app=nvidia-device-plugin-daemonset
   ```

### Task 2: Deploy MLflow via k0rdent ServiceTemplate (20 min)

The k0rdent catalog provides the `mlflow-1-7-1` ServiceTemplate for automated MLflow deployment. This is the recommended approach for k0rdent-managed environments.

1. **Install the MLflow ServiceTemplate from the catalog** (on the management cluster)
   ```bash
   # Switch to management cluster context
   export KUBECONFIG=~/.kube/config

   # Install the MLflow ServiceTemplate from the external catalog
   helm upgrade --install mlflow-template \
     oci://ghcr.io/k0rdent/catalog/charts/kgst \
     --set "chart=mlflow:1.7.1" \
     -n kcm-system
   ```

2. **Verify the ServiceTemplate is available**
   ```bash
   kubectl get servicetemplate mlflow-1-7-1 -n kcm-system
   ```

3. **Option A: Deploy via ClusterDeployment serviceSpec** (single cluster)

   If your GPU cluster's ClusterDeployment already exists, add MLflow to its service list:
   ```yaml
   # Save as mlflow-service-patch.yaml
   spec:
     serviceSpec:
       services:
         - template: mlflow-1-7-1
           name: mlflow
           namespace: mlflow
           values: |
             tracking:
               persistence:
                 enabled: true
                 storageClass: ebs-gp3
                 size: 10Gi
             minio:
               enabled: true
               persistence:
                 storageClass: ebs-gp3
                 size: 50Gi
             postgresql:
               enabled: true
               persistence:
                 storageClass: ebs-gp3
                 size: 10Gi
   ```

   ```bash
   kubectl patch clusterdeployment ${CLUSTER_NAME} \
     -n kcm-system \
     --type merge \
     --patch-file mlflow-service-patch.yaml
   ```

4. **Option B: Deploy via MultiClusterService** (multiple clusters)
   ```yaml
   # Save as mlflow-multicluster.yaml
   apiVersion: k0rdent.mirantis.com/v1beta1
   kind: MultiClusterService
   metadata:
     name: mlflow-tracking
     namespace: kcm-system
   spec:
     clusterSelector:
       matchLabels:
         k0rdent.mirantis.com/workload: ml-platform
     serviceSpec:
       services:
         - template: mlflow-1-7-1
           name: mlflow
           namespace: mlflow
           values: |
             tracking:
               persistence:
                 enabled: true
                 storageClass: ebs-gp3
                 size: 10Gi
             minio:
               enabled: true
               persistence:
                 storageClass: ebs-gp3
                 size: 50Gi
             postgresql:
               enabled: true
               persistence:
                 storageClass: ebs-gp3
                 size: 10Gi
   ```

   ```bash
   kubectl apply -f mlflow-multicluster.yaml
   ```

5. **Verify deployment via Sveltos** (on the management cluster)
   ```bash
   # Check the Sveltos condition
   kubectl get clusterdeployment ${CLUSTER_NAME} -n kcm-system \
     -o jsonpath='{.status.conditions[?(@.type=="SveltosHelmReleaseReady")]}' | jq .

   # Switch to workload cluster and verify pods
   export KUBECONFIG=/tmp/${CLUSTER_NAME}.kubeconfig
   kubectl get pods -n mlflow
   kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=mlflow -n mlflow --timeout=300s
   ```

> **Note:** If your environment does not have the MLflow ServiceTemplate available, or you need more control over the deployment, continue with Task 3 for a manual installation.

### Task 3: Manual MLflow Deployment (30 min)

This task deploys MLflow components manually. Skip this if you completed Task 2 successfully.

1. **Create namespace and secrets**
   ```bash
   export KUBECONFIG=/tmp/${CLUSTER_NAME}.kubeconfig
   kubectl create namespace mlflow
   ```

   ```yaml
   # Save as mlflow-secrets.yaml
   apiVersion: v1
   kind: Secret
   metadata:
     name: minio-credentials
     namespace: mlflow
   type: Opaque
   stringData:
     MINIO_ROOT_USER: "mlflow"
     MINIO_ROOT_PASSWORD: "mlflow-s3cr3t"
     AWS_ACCESS_KEY_ID: "mlflow"
     AWS_SECRET_ACCESS_KEY: "mlflow-s3cr3t"
   ---
   apiVersion: v1
   kind: Secret
   metadata:
     name: postgres-credentials
     namespace: mlflow
   type: Opaque
   stringData:
     POSTGRES_USER: "mlflow"
     POSTGRES_PASSWORD: "pg-s3cr3t"
     POSTGRES_DB: "mlflow"
     DATABASE_URL: "postgresql://mlflow:pg-s3cr3t@postgres:5432/mlflow"
   ```

   ```bash
   kubectl apply -f mlflow-secrets.yaml
   ```

2. **Deploy MinIO for artifact storage**
   ```yaml
   # Save as minio-deployment.yaml
   apiVersion: v1
   kind: PersistentVolumeClaim
   metadata:
     name: minio-pvc
     namespace: mlflow
   spec:
     accessModes:
       - ReadWriteOnce
     storageClassName: ebs-gp3
     resources:
       requests:
         storage: 50Gi
   ---
   apiVersion: apps/v1
   kind: Deployment
   metadata:
     name: minio
     namespace: mlflow
   spec:
     replicas: 1
     selector:
       matchLabels:
         app: minio
     template:
       metadata:
         labels:
           app: minio
       spec:
         containers:
           - name: minio
             image: minio/minio:RELEASE.2024-10-02T17-50-41Z
             args:
               - server
               - /data
               - --console-address
               - ":9001"
             envFrom:
               - secretRef:
                   name: minio-credentials
             ports:
               - containerPort: 9000
                 name: api
               - containerPort: 9001
                 name: console
             volumeMounts:
               - name: data
                 mountPath: /data
             readinessProbe:
               httpGet:
                 path: /minio/health/ready
                 port: 9000
               initialDelaySeconds: 10
               periodSeconds: 10
         volumes:
           - name: data
             persistentVolumeClaim:
               claimName: minio-pvc
   ---
   apiVersion: v1
   kind: Service
   metadata:
     name: minio
     namespace: mlflow
   spec:
     selector:
       app: minio
     ports:
       - name: api
         port: 9000
         targetPort: 9000
       - name: console
         port: 9001
         targetPort: 9001
   ```

   ```bash
   kubectl apply -f minio-deployment.yaml
   kubectl wait --for=condition=Ready pod -l app=minio -n mlflow --timeout=120s
   ```

3. **Create the MLflow artifacts bucket**
   ```bash
   # Port forward MinIO
   kubectl port-forward -n mlflow svc/minio 9000:9000 &
   MINIO_PF_PID=$!
   sleep 5

   # Install MinIO client and create bucket
   curl -O https://dl.min.io/client/mc/release/linux-amd64/mc
   chmod +x mc && sudo mv mc /usr/local/bin/

   mc alias set minio http://localhost:9000 mlflow mlflow-s3cr3t
   mc mb minio/mlflow-artifacts

   kill $MINIO_PF_PID
   echo "MinIO bucket created: mlflow-artifacts"
   ```

4. **Deploy PostgreSQL backend store**
   ```yaml
   # Save as postgres-deployment.yaml
   apiVersion: v1
   kind: PersistentVolumeClaim
   metadata:
     name: postgres-pvc
     namespace: mlflow
   spec:
     accessModes:
       - ReadWriteOnce
     storageClassName: ebs-gp3
     resources:
       requests:
         storage: 10Gi
   ---
   apiVersion: apps/v1
   kind: Deployment
   metadata:
     name: postgres
     namespace: mlflow
   spec:
     replicas: 1
     selector:
       matchLabels:
         app: postgres
     template:
       metadata:
         labels:
           app: postgres
       spec:
         containers:
           - name: postgres
             image: postgres:16-alpine
             envFrom:
               - secretRef:
                   name: postgres-credentials
             ports:
               - containerPort: 5432
             volumeMounts:
               - name: data
                 mountPath: /var/lib/postgresql/data
                 subPath: pgdata
             readinessProbe:
               exec:
                 command:
                   - pg_isready
                   - -U
                   - mlflow
               initialDelaySeconds: 10
               periodSeconds: 5
         volumes:
           - name: data
             persistentVolumeClaim:
               claimName: postgres-pvc
   ---
   apiVersion: v1
   kind: Service
   metadata:
     name: postgres
     namespace: mlflow
   spec:
     selector:
       app: postgres
     ports:
       - port: 5432
         targetPort: 5432
   ```

   ```bash
   kubectl apply -f postgres-deployment.yaml
   kubectl wait --for=condition=Ready pod -l app=postgres -n mlflow --timeout=120s
   ```

5. **Deploy MLflow Tracking Server**
   ```yaml
   # Save as mlflow-deployment.yaml
   apiVersion: apps/v1
   kind: Deployment
   metadata:
     name: mlflow-server
     namespace: mlflow
   spec:
     replicas: 1
     selector:
       matchLabels:
         app: mlflow-server
     template:
       metadata:
         labels:
           app: mlflow-server
       spec:
         containers:
           - name: mlflow
             image: ghcr.io/mlflow/mlflow:v3.1.0
             command:
               - mlflow
               - server
               - --backend-store-uri
               - $(DATABASE_URL)
               - --artifacts-destination
               - s3://mlflow-artifacts
               - --host
               - "0.0.0.0"
               - --port
               - "5000"
             env:
               - name: DATABASE_URL
                 valueFrom:
                   secretKeyRef:
                     name: postgres-credentials
                     key: DATABASE_URL
               - name: MLFLOW_S3_ENDPOINT_URL
                 value: "http://minio:9000"
               - name: AWS_ACCESS_KEY_ID
                 valueFrom:
                   secretKeyRef:
                     name: minio-credentials
                     key: AWS_ACCESS_KEY_ID
               - name: AWS_SECRET_ACCESS_KEY
                 valueFrom:
                   secretKeyRef:
                     name: minio-credentials
                     key: AWS_SECRET_ACCESS_KEY
             ports:
               - containerPort: 5000
             resources:
               requests:
                 cpu: "500m"
                 memory: 1Gi
               limits:
                 cpu: "2"
                 memory: 4Gi
             readinessProbe:
               httpGet:
                 path: /health
                 port: 5000
               initialDelaySeconds: 15
               periodSeconds: 10
             livenessProbe:
               httpGet:
                 path: /health
                 port: 5000
               initialDelaySeconds: 30
               periodSeconds: 15
   ---
   apiVersion: v1
   kind: Service
   metadata:
     name: mlflow-server
     namespace: mlflow
   spec:
     selector:
       app: mlflow-server
     ports:
       - port: 5000
         targetPort: 5000
   ```

   ```bash
   kubectl apply -f mlflow-deployment.yaml
   kubectl wait --for=condition=Ready pod -l app=mlflow-server -n mlflow --timeout=180s

   # Port forward to access UI
   kubectl port-forward -n mlflow svc/mlflow-server 5000:5000 &

   echo "MLflow UI: http://localhost:5000"
   ```

6. **Verify the deployment**
   ```bash
   # Check health endpoint
   curl -s http://localhost:5000/health
   # Should return HTTP 200

   # Check all pods
   kubectl get pods -n mlflow
   # Expected: minio, postgres, mlflow-server all Running
   ```

### Task 4: Configure Client and Log GPU Experiments (30 min)

1. **Install MLflow client**
   ```bash
   pip install 'mlflow>=3.1.0' boto3 psycopg2-binary torch torchvision
   ```

2. **Create GPU training script with MLflow integration**
   ```python
   # Save as train_with_mlflow.py
   import mlflow
   import mlflow.pytorch
   import torch
   import torch.nn as nn
   import torch.optim as optim
   from torchvision import datasets, transforms
   from torch.utils.data import DataLoader
   import os
   import time

   # Configure MLflow
   os.environ['MLFLOW_S3_ENDPOINT_URL'] = 'http://localhost:9000'
   os.environ['AWS_ACCESS_KEY_ID'] = 'mlflow'
   os.environ['AWS_SECRET_ACCESS_KEY'] = 'mlflow-s3cr3t'

   mlflow.set_tracking_uri('http://localhost:5000')
   mlflow.set_experiment('gpu-training-experiments')

   # Check GPU availability
   device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
   print(f"Training on: {device}")
   if torch.cuda.is_available():
       print(f"GPU: {torch.cuda.get_device_name(0)}")
       print(f"GPU Memory: {torch.cuda.get_device_properties(0).total_mem / 1e9:.1f} GB")


   class CNN(nn.Module):
       """Simple CNN for MNIST classification."""
       def __init__(self, hidden_size=128, dropout=0.2):
           super().__init__()
           self.conv1 = nn.Conv2d(1, 32, 3, padding=1)
           self.conv2 = nn.Conv2d(32, 64, 3, padding=1)
           self.pool = nn.MaxPool2d(2, 2)
           self.fc1 = nn.Linear(64 * 7 * 7, hidden_size)
           self.fc2 = nn.Linear(hidden_size, 10)
           self.dropout = nn.Dropout(dropout)

       def forward(self, x):
           x = self.pool(torch.relu(self.conv1(x)))
           x = self.pool(torch.relu(self.conv2(x)))
           x = x.view(-1, 64 * 7 * 7)
           x = self.dropout(torch.relu(self.fc1(x)))
           return self.fc2(x)


   def train_model(learning_rate=0.001, batch_size=64, epochs=5,
                    hidden_size=128, dropout=0.2):
       with mlflow.start_run():
           # Log parameters
           mlflow.log_param("learning_rate", learning_rate)
           mlflow.log_param("batch_size", batch_size)
           mlflow.log_param("epochs", epochs)
           mlflow.log_param("hidden_size", hidden_size)
           mlflow.log_param("dropout", dropout)
           mlflow.log_param("device", str(device))
           if torch.cuda.is_available():
               mlflow.log_param("gpu_name", torch.cuda.get_device_name(0))

           # Load MNIST data
           transform = transforms.Compose([
               transforms.ToTensor(),
               transforms.Normalize((0.1307,), (0.3081,))
           ])
           train_dataset = datasets.MNIST(
               './data', train=True, download=True, transform=transform
           )
           test_dataset = datasets.MNIST(
               './data', train=False, transform=transform
           )
           train_loader = DataLoader(
               train_dataset, batch_size=batch_size, shuffle=True
           )
           test_loader = DataLoader(test_dataset, batch_size=batch_size)

           # Initialize model and optimizer
           model = CNN(hidden_size=hidden_size, dropout=dropout).to(device)
           criterion = nn.CrossEntropyLoss()
           optimizer = optim.Adam(model.parameters(), lr=learning_rate)

           # Training loop
           start_time = time.time()
           for epoch in range(epochs):
               model.train()
               running_loss = 0.0
               correct = 0
               total = 0

               for data, target in train_loader:
                   data, target = data.to(device), target.to(device)
                   optimizer.zero_grad()
                   output = model(data)
                   loss = criterion(output, target)
                   loss.backward()
                   optimizer.step()

                   running_loss += loss.item()
                   _, predicted = output.max(1)
                   total += target.size(0)
                   correct += predicted.eq(target).sum().item()

               epoch_loss = running_loss / len(train_loader)
               epoch_acc = correct / total

               mlflow.log_metric("train_loss", epoch_loss, step=epoch)
               mlflow.log_metric("train_accuracy", epoch_acc, step=epoch)
               print(f"Epoch {epoch+1}/{epochs}: "
                     f"Loss={epoch_loss:.4f}, Acc={epoch_acc:.4f}")

           training_time = time.time() - start_time
           mlflow.log_metric("training_time_seconds", training_time)

           # Test evaluation
           model.eval()  # Use model.eval() instead of model.train(False)
           test_loss = 0
           correct = 0
           total = 0

           with torch.no_grad():
               for data, target in test_loader:
                   data, target = data.to(device), target.to(device)
                   output = model(data)
                   test_loss += criterion(output, target).item()
                   _, predicted = output.max(1)
                   total += target.size(0)
                   correct += predicted.eq(target).sum().item()

           test_loss /= len(test_loader)
           test_acc = correct / total

           mlflow.log_metric("test_loss", test_loss)
           mlflow.log_metric("test_accuracy", test_acc)

           print(f"\nTest: Loss={test_loss:.4f}, Acc={test_acc:.4f}")
           print(f"Training time: {training_time:.1f}s")

           # Log model artifact
           mlflow.pytorch.log_model(model, "model")

           return test_acc


   if __name__ == "__main__":
       # Run hyperparameter sweep
       experiments = [
           {"learning_rate": 0.001, "batch_size": 64,
            "epochs": 3, "hidden_size": 128, "dropout": 0.2},
           {"learning_rate": 0.0005, "batch_size": 128,
            "epochs": 3, "hidden_size": 256, "dropout": 0.3},
           {"learning_rate": 0.002, "batch_size": 32,
            "epochs": 3, "hidden_size": 64, "dropout": 0.1},
       ]

       for i, params in enumerate(experiments):
           print(f"\n{'='*50}")
           print(f"Experiment {i+1}/{len(experiments)}")
           print(f"{'='*50}")
           train_model(**params)
   ```

3. **Run the training script**
   ```bash
   python train_with_mlflow.py
   ```

4. **Verify experiments in the UI**
   - Open http://localhost:5000
   - Navigate to "gpu-training-experiments"
   - Compare runs side-by-side: select multiple runs and click "Compare"
   - View training curves under each run's Metrics tab
   - Download artifacts from the Artifacts tab

### Task 5: Kubernetes Training Job with MLflow (30 min)

1. **Create a ConfigMap with the training script**

   This approach keeps the training code in a ConfigMap mounted into the Job, making it easy to iterate without rebuilding images.

   ```yaml
   # Save as training-configmap.yaml
   apiVersion: v1
   kind: ConfigMap
   metadata:
     name: mlflow-training-script
     namespace: mlflow
   data:
     train.py: |
       import mlflow
       import mlflow.pytorch
       import torch
       import torch.nn as nn
       import torch.optim as optim
       from torchvision import datasets, transforms
       from torch.utils.data import DataLoader
       import os

       # MLflow configuration from environment
       mlflow.set_tracking_uri(os.environ['MLFLOW_TRACKING_URI'])
       mlflow.set_experiment('kubernetes-gpu-training')

       device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
       print(f"Training on: {device}")

       with mlflow.start_run(run_name=f"k8s-{os.environ.get('HOSTNAME', 'unknown')}"):
           mlflow.log_param("device", str(device))
           mlflow.log_param("pod_name", os.environ.get("HOSTNAME", "unknown"))

           if torch.cuda.is_available():
               mlflow.log_param("gpu_name", torch.cuda.get_device_name(0))
               gpu_mem = torch.cuda.get_device_properties(0).total_mem
               mlflow.log_param("gpu_memory_gb", f"{gpu_mem / 1e9:.1f}")

           class Net(nn.Module):
               def __init__(self):
                   super().__init__()
                   self.fc1 = nn.Linear(784, 256)
                   self.fc2 = nn.Linear(256, 128)
                   self.fc3 = nn.Linear(128, 10)

               def forward(self, x):
                   x = x.view(-1, 784)
                   x = torch.relu(self.fc1(x))
                   x = torch.relu(self.fc2(x))
                   return self.fc3(x)

           model = Net().to(device)
           transform = transforms.Compose([transforms.ToTensor()])
           train_data = datasets.MNIST(
               '/tmp/data', train=True, download=True, transform=transform
           )
           test_data = datasets.MNIST(
               '/tmp/data', train=False, transform=transform
           )
           train_loader = DataLoader(train_data, batch_size=128, shuffle=True)
           test_loader = DataLoader(test_data, batch_size=128)

           optimizer = optim.Adam(model.parameters(), lr=0.001)
           criterion = nn.CrossEntropyLoss()

           for epoch in range(5):
               model.train()
               total_loss = 0
               for data, target in train_loader:
                   data, target = data.to(device), target.to(device)
                   optimizer.zero_grad()
                   output = model(data)
                   loss = criterion(output, target)
                   loss.backward()
                   optimizer.step()
                   total_loss += loss.item()

               avg_loss = total_loss / len(train_loader)
               mlflow.log_metric("train_loss", avg_loss, step=epoch)
               print(f"Epoch {epoch+1}: Loss = {avg_loss:.4f}")

           # Test accuracy
           model.eval()  # Switch to evaluation mode
           correct = 0
           total = 0
           with torch.no_grad():
               for data, target in test_loader:
                   data, target = data.to(device), target.to(device)
                   output = model(data)
                   _, predicted = output.max(1)
                   total += target.size(0)
                   correct += predicted.eq(target).sum().item()

           test_acc = correct / total
           mlflow.log_metric("test_accuracy", test_acc)
           mlflow.pytorch.log_model(model, "model")
           print(f"Test accuracy: {test_acc:.4f}")
           print("Training complete! Model logged to MLflow.")
   ```

   ```bash
   kubectl apply -f training-configmap.yaml
   ```

2. **Create the training Job**
   ```yaml
   # Save as mlflow-training-job.yaml
   apiVersion: batch/v1
   kind: Job
   metadata:
     name: mlflow-gpu-training
     namespace: mlflow
   spec:
     template:
       spec:
         containers:
           - name: trainer
             image: nvcr.io/nvidia/pytorch:24.09-py3
             command: ["python", "/scripts/train.py"]
             env:
               - name: MLFLOW_TRACKING_URI
                 value: "http://mlflow-server:5000"
               - name: MLFLOW_S3_ENDPOINT_URL
                 value: "http://minio:9000"
               - name: AWS_ACCESS_KEY_ID
                 valueFrom:
                   secretKeyRef:
                     name: minio-credentials
                     key: AWS_ACCESS_KEY_ID
               - name: AWS_SECRET_ACCESS_KEY
                 valueFrom:
                   secretKeyRef:
                     name: minio-credentials
                     key: AWS_SECRET_ACCESS_KEY
             volumeMounts:
               - name: training-script
                 mountPath: /scripts
             resources:
               requests:
                 cpu: "2"
                 memory: 4Gi
               limits:
                 nvidia.com/gpu: 1
         volumes:
           - name: training-script
             configMap:
               name: mlflow-training-script
         restartPolicy: Never
     backoffLimit: 2
   ```

   ```bash
   kubectl apply -f mlflow-training-job.yaml
   ```

3. **Monitor the training Job**
   ```bash
   # Watch job progress
   kubectl get jobs -n mlflow -w

   # Stream logs
   kubectl logs -n mlflow -l job-name=mlflow-gpu-training -f

   # Check completion
   kubectl get job mlflow-gpu-training -n mlflow \
     -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}'
   ```

### Task 6: Model Registry with Aliases (25 min)

MLflow 3.x replaces the stage-based model promotion workflow (Staging/Production/Archived) with a flexible alias system. Aliases are arbitrary string labels that point to specific model versions.

1. **Create the model registration script**
   ```python
   # Save as register_model.py
   import mlflow
   from mlflow import MlflowClient
   import os

   os.environ['MLFLOW_S3_ENDPOINT_URL'] = 'http://localhost:9000'
   os.environ['AWS_ACCESS_KEY_ID'] = 'mlflow'
   os.environ['AWS_SECRET_ACCESS_KEY'] = 'mlflow-s3cr3t'

   mlflow.set_tracking_uri('http://localhost:5000')
   client = MlflowClient()

   # Find the best run from our experiment
   experiment = client.get_experiment_by_name('gpu-training-experiments')
   runs = client.search_runs(
       experiment_ids=[experiment.experiment_id],
       order_by=["metrics.test_accuracy DESC"],
       max_results=1
   )

   if runs:
       best_run = runs[0]
       run_id = best_run.info.run_id
       test_acc = best_run.data.metrics.get('test_accuracy', 'N/A')
       print(f"Best run: {run_id}")
       print(f"Test accuracy: {test_acc}")

       # Register the model
       model_name = "mnist-classifier"
       model_uri = f"runs:/{run_id}/model"

       # create_registered_model is idempotent if model already exists
       try:
           client.create_registered_model(model_name)
           print(f"Created registered model: {model_name}")
       except mlflow.exceptions.MlflowException:
           print(f"Registered model '{model_name}' already exists")

       # Create a new model version
       mv = client.create_model_version(
           name=model_name,
           source=model_uri,
           run_id=run_id
       )
       print(f"Registered version: {mv.version}")

       # --- MLflow 3.x: Use aliases instead of stages ---
       # Set the "champion" alias to point to this version
       client.set_registered_model_alias(
           name=model_name,
           alias="champion",
           version=mv.version
       )
       print(f"Set alias 'champion' -> version {mv.version}")

       # You can also set a "challenger" alias for A/B testing
       client.set_registered_model_alias(
           name=model_name,
           alias="latest-gpu",
           version=mv.version
       )
       print(f"Set alias 'latest-gpu' -> version {mv.version}")

       # Retrieve model by alias
       champion = client.get_model_version_by_alias(model_name, "champion")
       print(f"\nChampion model: version {champion.version}")
       print(f"  Source: {champion.source}")
       print(f"  Run ID: {champion.run_id}")
   else:
       print("No runs found! Run train_with_mlflow.py first.")
   ```

   ```bash
   python register_model.py
   ```

2. **Load model by alias**

   The modern MLflow 3.x URI format uses `@alias` instead of `/Stage`:

   ```python
   # Save as load_model.py
   import mlflow
   import torch
   import os

   os.environ['MLFLOW_S3_ENDPOINT_URL'] = 'http://localhost:9000'
   os.environ['AWS_ACCESS_KEY_ID'] = 'mlflow'
   os.environ['AWS_SECRET_ACCESS_KEY'] = 'mlflow-s3cr3t'

   mlflow.set_tracking_uri('http://localhost:5000')

   # Load model using alias-based URI (MLflow 3.x)
   model = mlflow.pytorch.load_model("models:/mnist-classifier@champion")
   print(f"Loaded champion model: {type(model).__name__}")

   # Test with sample input
   sample = torch.randn(1, 1, 28, 28)
   model.cpu()
   with torch.no_grad():
       output = model(sample)
       predicted = output.argmax(dim=1).item()
       print(f"Sample prediction: {predicted}")
       print(f"Output logits: {output[0].tolist()}")
   ```

   ```bash
   python load_model.py
   ```

3. **Verify in the MLflow UI**
   - Navigate to the Models tab in the MLflow UI
   - Click on "mnist-classifier"
   - Verify the aliases ("champion", "latest-gpu") are shown
   - Each alias links to the correct model version

## Deliverables

- [ ] **Screenshot** of MLflow UI showing multiple experiment runs with GPU metrics
- [ ] **Screenshot** of Model Registry showing registered model with aliases
- [ ] **Training script** (`train_with_mlflow.py`) with MLflow 3.x integration
- [ ] **Kubernetes Job YAML** for GPU training with Secret-based credentials
- [ ] **Model registration script** using `set_registered_model_alias()` (not stages)
- [ ] **Inference test output** from loading model via `models:/name@champion` URI

## Verification Checklist

- [ ] MLflow server deployed and healthy (`/health` returns 200)
- [ ] MinIO artifact store operational with `mlflow-artifacts` bucket
- [ ] PostgreSQL backend store accepting connections
- [ ] Experiments logged with metrics, parameters, and artifacts
- [ ] Model registered with alias-based promotion (not stage-based)
- [ ] Model loadable via `models:/mnist-classifier@champion` URI
- [ ] Credentials stored in Kubernetes Secrets (not ConfigMaps)

## Troubleshooting

### MLflow Server Not Starting

**Check logs:**
```bash
kubectl logs -n mlflow -l app=mlflow-server
```

**Verify database connection:**
```bash
kubectl exec -n mlflow deployment/mlflow-server -- \
  python -c "
import psycopg2
conn = psycopg2.connect('postgresql://mlflow:pg-s3cr3t@postgres:5432/mlflow')
print('Database connection: OK')
conn.close()
"
```

**Check health endpoint:**
```bash
# From inside the cluster
kubectl exec -n mlflow deployment/mlflow-server -- curl -s http://localhost:5000/health
```

### Artifacts Not Uploading

**Check MinIO connectivity:**
```bash
kubectl exec -n mlflow deployment/mlflow-server -- \
  curl -s http://minio:9000/minio/health/ready
```

**Verify S3 credentials are mounted from Secret:**
```bash
kubectl get secret minio-credentials -n mlflow -o jsonpath='{.data}' | \
  python3 -c "import sys,json,base64; d=json.load(sys.stdin); print({k:base64.b64decode(v).decode() for k,v in d.items()})"
```

### Training Job Fails

**Check pod events:**
```bash
kubectl describe job mlflow-gpu-training -n mlflow
kubectl get events -n mlflow --sort-by='.lastTimestamp' | tail -20
```

**Verify GPU access:**
```bash
kubectl exec -n mlflow -it $(kubectl get pod -n mlflow -l job-name=mlflow-gpu-training -o name | head -1) -- nvidia-smi
```

### Model Registry Errors

**If `transition_model_version_stage` fails:**
This method was removed in MLflow 3.x. Use the alias-based API:
```python
# Old (broken in MLflow 3.x):
# client.transition_model_version_stage(name, version, "Production")

# New (MLflow 3.x):
client.set_registered_model_alias(name, "champion", version)
```

**If `models:/name/Production` URI fails:**
The stage-based URI format is deprecated. Use the alias format:
```python
# Old (broken in MLflow 3.x):
# model = mlflow.pytorch.load_model("models:/mnist-classifier/Production")

# New (MLflow 3.x):
model = mlflow.pytorch.load_model("models:/mnist-classifier@champion")
```

## Key Takeaways

1. **k0rdent ServiceTemplate** (`mlflow-1-7-1`) provides one-command MLflow deployment across managed clusters
2. **MLflow 3.x aliases** replace the rigid four-stage model promotion with flexible, custom labels
3. **Kubernetes Secrets** (not ConfigMaps) should store database and S3 credentials
4. **The `/health` endpoint** is the correct readiness/liveness probe path for MLflow 3.x
5. **NVIDIA container images** (`nvcr.io/nvidia/pytorch`) provide pre-built GPU environments for training Jobs

## Next Lab

Choose your next elective track:

- **Compliance Track:** [Lab 5.11 - FIPS Compliance](lab-5.11-nvidia-fips.md)
- **Advanced Track:** [Lab 5.13 - TensorRT-LLM Optimization](lab-5.13-tensorrt-llm.md)
- **Or proceed to:** [Week 6 - Multi-tenancy](../../week-6-multi-tenancy/README.md)
