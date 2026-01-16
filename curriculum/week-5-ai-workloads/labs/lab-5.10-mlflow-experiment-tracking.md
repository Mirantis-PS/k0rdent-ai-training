# Lab 5.10 - MLflow Experiment Tracking

---

## Lab Navigation

| Track | Tier | Duration |
|-------|------|----------|
| ML Platforms | Recommended | 2.5 hours |

### Week 5 Learning Paths

```
FOUNDATION (Required)                         ML PLATFORMS
━━━━━━━━━━━━━━━━━━━━                         ━━━━━━━━━━━━
5.1 ➔ 5.2 ➔ 5.3 ➔ 5.4 ➔ 5.5 ➔ 5.6          5.9 Kubeflow
                                                  ↓
                                             YOU ARE HERE
                                                  ↓
                                             [5.10] MLflow
                                                  ↓
                                              5.11 Run:AI
                                                  ↓
                                              5.12 Slurm ➔ Week 6
```

| Previous | Current | Next |
|----------|---------|------|
| [Lab 5.9 - Kubeflow](lab-5.9-kubeflow-ml-platform.md) | **Lab 5.10 - MLflow** | [Lab 5.11 - Run:AI](lab-5.11-runai-gpu-orchestration.md) |

---

**Duration:** 2.5 hours
**Type:** Hands-on Technical
**Environment:** GPU Lab

## Objective

Deploy MLflow as a centralized experiment tracking server on Kubernetes, configure artifact storage, and integrate it with GPU-based training workflows for comprehensive ML lifecycle management.

## Prerequisites

- Completed Lab 5.1 (GPU Scheduler deployed)
- Kubernetes cluster with GPU nodes
- PostgreSQL or SQLite for backend storage
- S3-compatible storage (MinIO) or persistent volume for artifacts
- Python 3.9+ with pip

## Background

### What is MLflow?

MLflow is an open-source platform for managing the end-to-end machine learning lifecycle. It provides four main components:

- **Tracking**: Record and query experiments (parameters, metrics, artifacts)
- **Projects**: Package ML code in a reusable, reproducible format
- **Models**: Deploy ML models to various serving platforms
- **Model Registry**: Centralized model store with versioning and staging

### Architecture Overview

```
┌──────────────────────────────────────────────────────────────┐
│                     MLflow UI (Port 5000)                    │
├──────────────────────────────────────────────────────────────┤
│                     MLflow Tracking Server                   │
├─────────────────────────┬────────────────────────────────────┤
│   Backend Store         │         Artifact Store             │
│   (PostgreSQL/SQLite)   │         (S3/MinIO/PVC)            │
└─────────────────────────┴────────────────────────────────────┘
                              ↑
                    ┌─────────┴─────────┐
                    │  Training Jobs    │
                    │  (GPU Workloads)  │
                    └───────────────────┘
```

## Lab Environment

**Cluster Requirements:**
- Kubernetes 1.28+ with GPU nodes
- NVIDIA GPU Operator v25.10.0 installed
- 4+ vCPUs, 8GB+ RAM for MLflow server
- 50GB storage for artifacts

## Tasks

### Task 1: Deploy MinIO for Artifact Storage (20 min)

1. **Create MinIO Namespace and Deployment**
   ```bash
   kubectl create namespace mlflow
   ```

2. **Deploy MinIO**
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
             env:
               - name: MINIO_ROOT_USER
                 value: "mlflow"
               - name: MINIO_ROOT_PASSWORD
                 value: "mlflow123"
             ports:
               - containerPort: 9000
                 name: api
               - containerPort: 9001
                 name: console
             volumeMounts:
               - name: data
                 mountPath: /data
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

3. **Apply and Create Bucket**
   ```bash
   kubectl apply -f minio-deployment.yaml

   # Wait for MinIO to be ready
   kubectl wait --for=condition=Ready pod -l app=minio -n mlflow --timeout=120s

   # Port forward to create bucket
   kubectl port-forward -n mlflow svc/minio 9000:9000 9001:9001 &
   sleep 5

   # Install mc (MinIO client) and create bucket
   curl -O https://dl.min.io/client/mc/release/linux-amd64/mc
   chmod +x mc
   sudo mv mc /usr/local/bin/

   # Configure mc
   mc alias set minio http://localhost:9000 mlflow mlflow123

   # Create MLflow bucket
   mc mb minio/mlflow-artifacts
   mc anonymous set download minio/mlflow-artifacts

   echo "MinIO bucket created: mlflow-artifacts"
   ```

### Task 2: Deploy PostgreSQL Backend Store (15 min)

1. **Deploy PostgreSQL**
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
             image: postgres:15-alpine
             env:
               - name: POSTGRES_USER
                 value: "mlflow"
               - name: POSTGRES_PASSWORD
                 value: "mlflow123"
               - name: POSTGRES_DB
                 value: "mlflow"
             ports:
               - containerPort: 5432
             volumeMounts:
               - name: data
                 mountPath: /var/lib/postgresql/data
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

2. **Apply PostgreSQL**
   ```bash
   kubectl apply -f postgres-deployment.yaml

   # Wait for PostgreSQL
   kubectl wait --for=condition=Ready pod -l app=postgres -n mlflow --timeout=120s
   ```

### Task 3: Deploy MLflow Tracking Server (25 min)

1. **Create MLflow ConfigMap**
   ```yaml
   # Save as mlflow-config.yaml
   apiVersion: v1
   kind: ConfigMap
   metadata:
     name: mlflow-config
     namespace: mlflow
   data:
     MLFLOW_S3_ENDPOINT_URL: "http://minio:9000"
     AWS_ACCESS_KEY_ID: "mlflow"
     AWS_SECRET_ACCESS_KEY: "mlflow123"
   ```

2. **Deploy MLflow Server**
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
             image: ghcr.io/mlflow/mlflow:v2.18.0
             command:
               - mlflow
               - server
               - --backend-store-uri
               - postgresql://mlflow:mlflow123@postgres:5432/mlflow
               - --artifacts-destination
               - s3://mlflow-artifacts
               - --host
               - "0.0.0.0"
               - --port
               - "5000"
             ports:
               - containerPort: 5000
             envFrom:
               - configMapRef:
                   name: mlflow-config
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
               initialDelaySeconds: 10
               periodSeconds: 5
             livenessProbe:
               httpGet:
                 path: /health
                 port: 5000
               initialDelaySeconds: 30
               periodSeconds: 10
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

3. **Apply and Verify**
   ```bash
   kubectl apply -f mlflow-config.yaml
   kubectl apply -f mlflow-deployment.yaml

   # Wait for MLflow server
   kubectl wait --for=condition=Ready pod -l app=mlflow-server -n mlflow --timeout=180s

   # Port forward to access UI
   kubectl port-forward -n mlflow svc/mlflow-server 5000:5000 &

   echo "MLflow UI: http://localhost:5000"
   ```

### Task 4: Configure Client and Log Experiments (30 min)

1. **Install MLflow Client**
   ```bash
   pip install mlflow==2.18.0 boto3 psycopg2-binary torch torchvision
   ```

2. **Create GPU Training Script with MLflow Integration**
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

   # Configure MLflow
   os.environ['MLFLOW_S3_ENDPOINT_URL'] = 'http://localhost:9000'
   os.environ['AWS_ACCESS_KEY_ID'] = 'mlflow'
   os.environ['AWS_SECRET_ACCESS_KEY'] = 'mlflow123'

   mlflow.set_tracking_uri('http://localhost:5000')
   mlflow.set_experiment('gpu-training-experiments')

   # Check GPU
   device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
   print(f"Training on: {device}")
   if torch.cuda.is_available():
       print(f"GPU: {torch.cuda.get_device_name(0)}")

   # Define model
   class CNN(nn.Module):
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

   def train_model(learning_rate=0.001, batch_size=64, epochs=5, hidden_size=128, dropout=0.2):
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

           # Load data
           transform = transforms.Compose([
               transforms.ToTensor(),
               transforms.Normalize((0.1307,), (0.3081,))
           ])

           train_dataset = datasets.MNIST('./data', train=True, download=True, transform=transform)
           test_dataset = datasets.MNIST('./data', train=False, transform=transform)

           train_loader = DataLoader(train_dataset, batch_size=batch_size, shuffle=True)
           test_loader = DataLoader(test_dataset, batch_size=batch_size)

           # Initialize model
           model = CNN(hidden_size=hidden_size, dropout=dropout).to(device)
           criterion = nn.CrossEntropyLoss()
           optimizer = optim.Adam(model.parameters(), lr=learning_rate)

           # Training loop
           for epoch in range(epochs):
               model.train()
               running_loss = 0.0
               correct = 0
               total = 0

               for batch_idx, (data, target) in enumerate(train_loader):
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

               # Log metrics per epoch
               mlflow.log_metric("train_loss", epoch_loss, step=epoch)
               mlflow.log_metric("train_accuracy", epoch_acc, step=epoch)

               print(f"Epoch {epoch+1}/{epochs}: Loss={epoch_loss:.4f}, Acc={epoch_acc:.4f}")

           # Evaluate
           model.eval()
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

           # Log final metrics
           mlflow.log_metric("test_loss", test_loss)
           mlflow.log_metric("test_accuracy", test_acc)

           print(f"\nTest Results: Loss={test_loss:.4f}, Acc={test_acc:.4f}")

           # Log model
           mlflow.pytorch.log_model(model, "model")

           # Log model summary as artifact
           model_summary = str(model)
           with open("model_summary.txt", "w") as f:
               f.write(model_summary)
           mlflow.log_artifact("model_summary.txt")

           return test_acc

   if __name__ == "__main__":
       # Run multiple experiments with different hyperparameters
       experiments = [
           {"learning_rate": 0.001, "batch_size": 64, "epochs": 3, "hidden_size": 128, "dropout": 0.2},
           {"learning_rate": 0.0005, "batch_size": 128, "epochs": 3, "hidden_size": 256, "dropout": 0.3},
           {"learning_rate": 0.002, "batch_size": 32, "epochs": 3, "hidden_size": 64, "dropout": 0.1},
       ]

       for i, params in enumerate(experiments):
           print(f"\n{'='*50}")
           print(f"Experiment {i+1}/{len(experiments)}")
           print(f"{'='*50}")
           train_model(**params)
   ```

3. **Run Training Script**
   ```bash
   python train_with_mlflow.py
   ```

4. **Verify Experiments in UI**
   - Open http://localhost:5000
   - Navigate to "gpu-training-experiments"
   - Compare runs, view metrics, download artifacts

### Task 5: Create Kubernetes Training Job with MLflow (30 min)

1. **Create Training Job**
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
             image: pytorch/pytorch:2.1.0-cuda12.1-cudnn8-runtime
             command:
               - /bin/bash
               - -c
               - |
                 pip install mlflow boto3 torchvision

                 python << 'PYEOF'
                 import mlflow
                 import mlflow.pytorch
                 import torch
                 import torch.nn as nn
                 import torch.optim as optim
                 from torchvision import datasets, transforms
                 from torch.utils.data import DataLoader
                 import os

                 # Configure MLflow
                 os.environ['MLFLOW_S3_ENDPOINT_URL'] = 'http://minio:9000'
                 os.environ['AWS_ACCESS_KEY_ID'] = 'mlflow'
                 os.environ['AWS_SECRET_ACCESS_KEY'] = 'mlflow123'

                 mlflow.set_tracking_uri('http://mlflow-server:5000')
                 mlflow.set_experiment('kubernetes-gpu-training')

                 device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
                 print(f"Training on: {device}")

                 with mlflow.start_run(run_name="k8s-gpu-run"):
                     mlflow.log_param("device", str(device))
                     mlflow.log_param("pod_name", os.environ.get("HOSTNAME", "unknown"))

                     if torch.cuda.is_available():
                         mlflow.log_param("gpu_name", torch.cuda.get_device_name(0))
                         mlflow.log_param("gpu_memory_gb", torch.cuda.get_device_properties(0).total_memory / 1e9)

                     # Simple model
                     class Net(nn.Module):
                         def __init__(self):
                             super().__init__()
                             self.fc1 = nn.Linear(784, 256)
                             self.fc2 = nn.Linear(256, 10)

                         def forward(self, x):
                             x = x.view(-1, 784)
                             x = torch.relu(self.fc1(x))
                             return self.fc2(x)

                     model = Net().to(device)

                     transform = transforms.Compose([transforms.ToTensor()])
                     train_data = datasets.MNIST('./data', train=True, download=True, transform=transform)
                     train_loader = DataLoader(train_data, batch_size=128, shuffle=True)

                     optimizer = optim.Adam(model.parameters(), lr=0.001)
                     criterion = nn.CrossEntropyLoss()

                     for epoch in range(5):
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
                         mlflow.log_metric("loss", avg_loss, step=epoch)
                         print(f"Epoch {epoch+1}: Loss = {avg_loss:.4f}")

                     mlflow.pytorch.log_model(model, "model")
                     print("Training complete! Model logged to MLflow.")
                 PYEOF
             env:
               - name: MLFLOW_TRACKING_URI
                 value: "http://mlflow-server:5000"
             resources:
               limits:
                 nvidia.com/gpu: 1
         restartPolicy: Never
     backoffLimit: 2
   ```

2. **Submit and Monitor Job**
   ```bash
   kubectl apply -f mlflow-training-job.yaml

   # Watch job progress
   kubectl get jobs -n mlflow -w

   # View logs
   kubectl logs -n mlflow -l job-name=mlflow-gpu-training -f
   ```

### Task 6: Model Registry and Deployment (25 min)

1. **Register Model**
   ```python
   # Save as register_model.py
   import mlflow
   from mlflow.tracking import MlflowClient
   import os

   os.environ['MLFLOW_S3_ENDPOINT_URL'] = 'http://localhost:9000'
   os.environ['AWS_ACCESS_KEY_ID'] = 'mlflow'
   os.environ['AWS_SECRET_ACCESS_KEY'] = 'mlflow123'

   mlflow.set_tracking_uri('http://localhost:5000')
   client = MlflowClient()

   # Get the best run from experiment
   experiment = client.get_experiment_by_name('gpu-training-experiments')
   runs = client.search_runs(
       experiment_ids=[experiment.experiment_id],
       order_by=["metrics.test_accuracy DESC"],
       max_results=1
   )

   if runs:
       best_run = runs[0]
       print(f"Best run: {best_run.info.run_id}")
       print(f"Test accuracy: {best_run.data.metrics.get('test_accuracy', 'N/A')}")

       # Register model
       model_uri = f"runs:/{best_run.info.run_id}/model"
       model_name = "mnist-classifier"

       # Create registered model if it doesn't exist
       try:
           client.create_registered_model(model_name)
       except:
           pass  # Model already exists

       # Register version
       mv = client.create_model_version(
           name=model_name,
           source=model_uri,
           run_id=best_run.info.run_id
       )

       print(f"Registered model version: {mv.version}")

       # Transition to Production
       client.transition_model_version_stage(
           name=model_name,
           version=mv.version,
           stage="Production"
       )

       print(f"Model {model_name} v{mv.version} promoted to Production")
   else:
       print("No runs found!")
   ```

2. **Run Registration**
   ```bash
   python register_model.py
   ```

3. **Create Model Serving Deployment**
   ```yaml
   # Save as mlflow-model-server.yaml
   apiVersion: apps/v1
   kind: Deployment
   metadata:
     name: mnist-model-server
     namespace: mlflow
   spec:
     replicas: 1
     selector:
       matchLabels:
         app: mnist-model-server
     template:
       metadata:
         labels:
           app: mnist-model-server
       spec:
         containers:
           - name: model-server
             image: ghcr.io/mlflow/mlflow:v2.18.0
             command:
               - mlflow
               - models
               - serve
               - --model-uri
               - models:/mnist-classifier/Production
               - --host
               - "0.0.0.0"
               - --port
               - "8080"
               - --no-conda
             env:
               - name: MLFLOW_TRACKING_URI
                 value: "http://mlflow-server:5000"
               - name: MLFLOW_S3_ENDPOINT_URL
                 value: "http://minio:9000"
               - name: AWS_ACCESS_KEY_ID
                 value: "mlflow"
               - name: AWS_SECRET_ACCESS_KEY
                 value: "mlflow123"
             ports:
               - containerPort: 8080
             resources:
               limits:
                 nvidia.com/gpu: 1
   ---
   apiVersion: v1
   kind: Service
   metadata:
     name: mnist-model-server
     namespace: mlflow
   spec:
     selector:
       app: mnist-model-server
     ports:
       - port: 8080
         targetPort: 8080
   ```

4. **Test Model Inference**
   ```bash
   kubectl apply -f mlflow-model-server.yaml

   # Wait for server
   kubectl wait --for=condition=Ready pod -l app=mnist-model-server -n mlflow --timeout=300s

   # Port forward
   kubectl port-forward -n mlflow svc/mnist-model-server 8080:8080 &

   # Test inference
   python << 'EOF'
   import requests
   import json
   import numpy as np

   # Generate sample input (28x28 image flattened)
   sample = np.random.randn(1, 1, 28, 28).tolist()

   response = requests.post(
       'http://localhost:8080/invocations',
       headers={'Content-Type': 'application/json'},
       data=json.dumps({"inputs": sample})
   )

   print(f"Status: {response.status_code}")
   print(f"Prediction: {response.json()}")
   EOF
   ```

## Deliverables

- [ ] **Screenshot** of MLflow UI showing multiple experiments
- [ ] **Training script** with MLflow integration
- [ ] **Kubernetes Job YAML** for GPU training
- [ ] **Model Registry screenshot** showing registered model
- [ ] **Inference test output** from deployed model

## Verification Checklist

- [ ] MLflow server deployed and accessible
- [ ] MinIO artifact store operational
- [ ] PostgreSQL backend store working
- [ ] Experiments logged with metrics and artifacts
- [ ] Model registered in Model Registry
- [ ] Model deployed for inference

## Troubleshooting

### MLflow Server Not Starting

**Check logs:**
```bash
kubectl logs -n mlflow -l app=mlflow-server
```

**Verify database connection:**
```bash
kubectl exec -n mlflow -it deployment/mlflow-server -- \
  python -c "import psycopg2; psycopg2.connect('postgresql://mlflow:mlflow123@postgres:5432/mlflow')"
```

### Artifacts Not Uploading

**Check MinIO connectivity:**
```bash
kubectl exec -n mlflow -it deployment/mlflow-server -- \
  curl http://minio:9000/minio/health/live
```

**Verify S3 credentials:**
```bash
kubectl get configmap mlflow-config -n mlflow -o yaml
```

### Model Serving Fails

**Check model download:**
```bash
kubectl logs -n mlflow -l app=mnist-model-server
```

**Verify model exists:**
```bash
curl http://localhost:5000/api/2.0/mlflow/registered-models/get?name=mnist-classifier
```

## Key Takeaways

1. **MLflow provides end-to-end ML lifecycle management** - tracking, models, registry
2. **Artifact storage** should be external (S3/MinIO) for scalability
3. **PostgreSQL backend** enables querying and concurrent access
4. **Model Registry** enables versioning, staging, and deployment workflows
5. **Integration with Kubernetes** enables scalable training and serving

## Next Lab

Proceed to [Lab 5.11 - Run:AI GPU Orchestration](lab-5.11-runai-gpu-orchestration.md)
