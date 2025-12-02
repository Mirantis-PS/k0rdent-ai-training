# Lab 5.9 - Kubeflow ML Platform

**Duration:** 3 hours
**Type:** Hands-on Technical
**Environment:** GPU Lab

## Objective

Deploy and configure Kubeflow as a comprehensive ML platform for managing machine learning workflows, including pipelines, training operators, and model serving.

## Prerequisites

- Completed Lab 5.1 (GPU Scheduler deployed)
- Kubernetes cluster with GPU nodes (v1.28+)
- 50GB+ storage available
- kubectl and helm installed
- Python 3.9+ with pip

## Background

### What is Kubeflow?

Kubeflow is an open-source machine learning platform designed for Kubernetes that makes deploying ML workflows simple, portable, and scalable. It provides a unified platform for:

- **Kubeflow Pipelines**: Orchestrate ML workflows as DAGs
- **Training Operators**: Distributed training for TensorFlow, PyTorch, MPI
- **Katib**: Hyperparameter tuning and neural architecture search
- **KServe**: Model serving and inference
- **Notebooks**: Jupyter notebook servers for development

### Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    Kubeflow Dashboard                       │
├─────────────┬──────────────┬──────────────┬────────────────┤
│  Pipelines  │   Notebooks  │    Katib     │    KServe      │
├─────────────┴──────────────┴──────────────┴────────────────┤
│              Training Operators (PyTorch, TF, MPI)          │
├─────────────────────────────────────────────────────────────┤
│                    Kubernetes + Istio                       │
├─────────────────────────────────────────────────────────────┤
│                      GPU Nodes                              │
└─────────────────────────────────────────────────────────────┘
```

## Lab Environment

**Cluster Requirements:**
- Kubernetes 1.28+ with GPU nodes
- NVIDIA GPU Operator v25.10.0 installed
- 8+ vCPUs, 32GB+ RAM available for Kubeflow components
- Dynamic storage provisioning

## Tasks

### Task 1: Prepare Cluster for Kubeflow (20 min)

1. **Verify Cluster Resources**
   ```bash
   # Check node resources
   kubectl get nodes -o wide
   kubectl describe nodes | grep -A5 "Allocatable:"

   # Verify GPU availability
   kubectl get nodes -o=custom-columns='NAME:.metadata.name,GPUs:.status.allocatable.nvidia\.com/gpu'
   ```

2. **Install cert-manager (if not present)**
   ```bash
   kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.16.2/cert-manager.yaml

   # Wait for cert-manager to be ready
   kubectl wait --for=condition=Ready pods --all -n cert-manager --timeout=300s
   ```

3. **Create Storage Class**
   ```bash
   # Verify default storage class exists
   kubectl get storageclass

   # If no default, create one (example for local-path)
   cat <<EOF | kubectl apply -f -
   apiVersion: storage.k8s.io/v1
   kind: StorageClass
   metadata:
     name: kubeflow-storage
     annotations:
       storageclass.kubernetes.io/is-default-class: "true"
   provisioner: rancher.io/local-path
   reclaimPolicy: Delete
   volumeBindingMode: WaitForFirstConsumer
   EOF
   ```

### Task 2: Deploy Kubeflow Pipelines (45 min)

1. **Set Pipeline Version and Deploy**
   ```bash
   export PIPELINE_VERSION=2.3.0

   # Apply cluster-scoped resources
   kubectl apply -k "github.com/kubeflow/pipelines/manifests/kustomize/cluster-scoped-resources?ref=$PIPELINE_VERSION"

   # Wait for CRDs
   kubectl wait --for condition=established --timeout=60s crd/applications.app.k8s.io

   # Deploy Kubeflow Pipelines
   kubectl apply -k "github.com/kubeflow/pipelines/manifests/kustomize/env/platform-agnostic?ref=$PIPELINE_VERSION"
   ```

2. **Wait for Deployment**
   ```bash
   # Watch pods come up
   kubectl get pods -n kubeflow -w

   # Wait for all pods to be ready (this takes 5-10 minutes)
   kubectl wait --for=condition=Ready pods --all -n kubeflow --timeout=600s
   ```

3. **Access Kubeflow Pipelines UI**
   ```bash
   # Port forward the UI
   kubectl port-forward -n kubeflow svc/ml-pipeline-ui 8080:80 &

   # Access at http://localhost:8080
   echo "Kubeflow Pipelines UI: http://localhost:8080"
   ```

4. **Verify Installation**
   ```bash
   # Check all KFP components
   kubectl get pods -n kubeflow -l app=ml-pipeline

   # Check API server
   kubectl logs -n kubeflow -l app=ml-pipeline -c ml-pipeline-api-server --tail=20
   ```

### Task 3: Install KFP Python SDK and Create Pipeline (40 min)

1. **Install KFP SDK**
   ```bash
   pip install kfp==2.10.0

   # Verify installation
   python -c "import kfp; print(f'KFP Version: {kfp.__version__}')"
   ```

2. **Create a GPU Training Pipeline**
   ```python
   # Save as gpu_training_pipeline.py
   from kfp import dsl
   from kfp import compiler
   from kfp.dsl import Dataset, Input, Output, Model

   @dsl.component(
       base_image='python:3.11-slim',
       packages_to_install=['pandas==2.0.3', 'scikit-learn==1.3.0']
   )
   def create_dataset(output_dataset: Output[Dataset]):
       """Create training dataset."""
       import pandas as pd
       from sklearn.datasets import make_classification

       X, y = make_classification(
           n_samples=10000,
           n_features=20,
           n_informative=15,
           random_state=42
       )

       df = pd.DataFrame(X, columns=[f'feature_{i}' for i in range(20)])
       df['target'] = y
       df.to_csv(output_dataset.path, index=False)
       print(f"Dataset created with {len(df)} samples")

   @dsl.component(
       base_image='pytorch/pytorch:2.1.0-cuda12.1-cudnn8-runtime',
       packages_to_install=['pandas==2.0.3', 'scikit-learn==1.3.0']
   )
   def train_model_gpu(
       input_dataset: Input[Dataset],
       model_output: Output[Model],
       epochs: int = 10,
       learning_rate: float = 0.001
   ):
       """Train a PyTorch model on GPU."""
       import torch
       import torch.nn as nn
       import pandas as pd
       from sklearn.model_selection import train_test_split

       # Check GPU availability
       device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
       print(f"Training on device: {device}")
       if torch.cuda.is_available():
           print(f"GPU: {torch.cuda.get_device_name(0)}")

       # Load data
       df = pd.read_csv(input_dataset.path)
       X = df.drop('target', axis=1).values
       y = df['target'].values

       X_train, X_val, y_train, y_val = train_test_split(X, y, test_size=0.2)

       # Convert to tensors
       X_train = torch.FloatTensor(X_train).to(device)
       y_train = torch.FloatTensor(y_train).to(device)
       X_val = torch.FloatTensor(X_val).to(device)
       y_val = torch.FloatTensor(y_val).to(device)

       # Define model
       model = nn.Sequential(
           nn.Linear(20, 64),
           nn.ReLU(),
           nn.Dropout(0.2),
           nn.Linear(64, 32),
           nn.ReLU(),
           nn.Linear(32, 1),
           nn.Sigmoid()
       ).to(device)

       criterion = nn.BCELoss()
       optimizer = torch.optim.Adam(model.parameters(), lr=learning_rate)

       # Training loop
       for epoch in range(epochs):
           model.train()
           optimizer.zero_grad()
           outputs = model(X_train).squeeze()
           loss = criterion(outputs, y_train)
           loss.backward()
           optimizer.step()

           # Validation
           model.eval()
           with torch.no_grad():
               val_outputs = model(X_val).squeeze()
               val_loss = criterion(val_outputs, y_val)
               accuracy = ((val_outputs > 0.5) == y_val).float().mean()

           if (epoch + 1) % 2 == 0:
               print(f"Epoch {epoch+1}/{epochs}, Loss: {loss:.4f}, Val Acc: {accuracy:.4f}")

       # Save model
       torch.save(model.state_dict(), model_output.path)
       print(f"Model saved to {model_output.path}")

   @dsl.component(base_image='python:3.11-slim')
   def evaluate_model(model_path: Input[Model]) -> float:
       """Evaluate the trained model."""
       import os
       model_size = os.path.getsize(model_path.path)
       print(f"Model size: {model_size} bytes")
       # Return a dummy accuracy for demonstration
       return 0.95

   @dsl.pipeline(
       name='gpu-training-pipeline',
       description='A pipeline that trains a PyTorch model on GPU'
   )
   def gpu_training_pipeline(epochs: int = 10, learning_rate: float = 0.001):
       """GPU Training Pipeline."""
       create_dataset_task = create_dataset()

       train_task = train_model_gpu(
           input_dataset=create_dataset_task.outputs['output_dataset'],
           epochs=epochs,
           learning_rate=learning_rate
       )
       # Request GPU resource
       train_task.set_gpu_limit(1)

       evaluate_task = evaluate_model(
           model_path=train_task.outputs['model_output']
       )

   if __name__ == '__main__':
       # Compile pipeline
       compiler.Compiler().compile(
           pipeline_func=gpu_training_pipeline,
           package_path='gpu_training_pipeline.yaml'
       )
       print("Pipeline compiled to gpu_training_pipeline.yaml")
   ```

3. **Compile and Submit Pipeline**
   ```bash
   # Compile the pipeline
   python gpu_training_pipeline.py

   # Submit via SDK
   python << 'EOF'
   from kfp.client import Client

   client = Client(host='http://localhost:8080')

   # Create experiment
   experiment = client.create_experiment('gpu-training-experiments')

   # Submit run
   run = client.create_run_from_pipeline_package(
       'gpu_training_pipeline.yaml',
       arguments={
           'epochs': 10,
           'learning_rate': 0.001
       },
       experiment_name='gpu-training-experiments',
       run_name='gpu-training-run-1'
   )

   print(f"Run submitted: {run.run_id}")
   print(f"View at: http://localhost:8080/#/runs/details/{run.run_id}")
   EOF
   ```

4. **Monitor Pipeline Execution**
   ```bash
   # Watch pipeline pods
   kubectl get pods -n kubeflow -w

   # Check logs of running component
   kubectl logs -n kubeflow -l pipeline/runid -f
   ```

### Task 4: Deploy Training Operator for Distributed Training (30 min)

1. **Install Kubeflow Training Operator**
   ```bash
   kubectl apply -k "github.com/kubeflow/training-operator/manifests/overlays/standalone?ref=v1.8.1"

   # Wait for operator to be ready
   kubectl wait --for=condition=Ready pods -n kubeflow -l control-plane=kubeflow-training-operator --timeout=120s
   ```

2. **Create PyTorchJob for Distributed Training**
   ```yaml
   # Save as pytorch-distributed-job.yaml
   apiVersion: kubeflow.org/v1
   kind: PyTorchJob
   metadata:
     name: pytorch-distributed-mnist
     namespace: kubeflow
   spec:
     pytorchReplicaSpecs:
       Master:
         replicas: 1
         restartPolicy: OnFailure
         template:
           spec:
             containers:
               - name: pytorch
                 image: pytorch/pytorch:2.1.0-cuda12.1-cudnn8-runtime
                 command:
                   - python
                   - -c
                   - |
                     import torch
                     import torch.distributed as dist
                     import torch.nn as nn
                     import torch.nn.functional as F
                     from torch.utils.data import DataLoader, DistributedSampler
                     from torchvision import datasets, transforms
                     import os

                     # Initialize distributed training
                     dist.init_process_group(backend='nccl')
                     local_rank = int(os.environ.get('LOCAL_RANK', 0))
                     torch.cuda.set_device(local_rank)
                     device = torch.device(f'cuda:{local_rank}')

                     print(f"Rank: {dist.get_rank()}, World Size: {dist.get_world_size()}")
                     print(f"GPU: {torch.cuda.get_device_name(local_rank)}")

                     # Simple CNN
                     class Net(nn.Module):
                         def __init__(self):
                             super().__init__()
                             self.conv1 = nn.Conv2d(1, 32, 3)
                             self.conv2 = nn.Conv2d(32, 64, 3)
                             self.fc1 = nn.Linear(9216, 128)
                             self.fc2 = nn.Linear(128, 10)

                         def forward(self, x):
                             x = F.relu(self.conv1(x))
                             x = F.max_pool2d(F.relu(self.conv2(x)), 2)
                             x = x.view(-1, 9216)
                             x = F.relu(self.fc1(x))
                             return F.log_softmax(self.fc2(x), dim=1)

                     model = Net().to(device)
                     model = nn.parallel.DistributedDataParallel(model, device_ids=[local_rank])

                     # Load MNIST
                     transform = transforms.Compose([
                         transforms.ToTensor(),
                         transforms.Normalize((0.1307,), (0.3081,))
                     ])
                     dataset = datasets.MNIST('./data', train=True, download=True, transform=transform)
                     sampler = DistributedSampler(dataset)
                     loader = DataLoader(dataset, batch_size=64, sampler=sampler)

                     optimizer = torch.optim.Adam(model.parameters(), lr=0.001)

                     # Train for 3 epochs
                     for epoch in range(3):
                         sampler.set_epoch(epoch)
                         for batch_idx, (data, target) in enumerate(loader):
                             data, target = data.to(device), target.to(device)
                             optimizer.zero_grad()
                             output = model(data)
                             loss = F.nll_loss(output, target)
                             loss.backward()
                             optimizer.step()

                             if batch_idx % 100 == 0 and dist.get_rank() == 0:
                                 print(f"Epoch {epoch}, Batch {batch_idx}, Loss: {loss.item():.4f}")

                     if dist.get_rank() == 0:
                         print("Training completed!")
                     dist.destroy_process_group()
                 resources:
                   limits:
                     nvidia.com/gpu: 1
       Worker:
         replicas: 2
         restartPolicy: OnFailure
         template:
           spec:
             containers:
               - name: pytorch
                 image: pytorch/pytorch:2.1.0-cuda12.1-cudnn8-runtime
                 command:
                   - python
                   - -c
                   - |
                     # Same training code as Master
                     import torch
                     import torch.distributed as dist
                     import os

                     dist.init_process_group(backend='nccl')
                     print(f"Worker started - Rank: {dist.get_rank()}")

                     # Worker will run the same training loop
                     import time
                     time.sleep(300)  # Keep running for distributed sync
                 resources:
                   limits:
                     nvidia.com/gpu: 1
   ```

3. **Submit and Monitor PyTorchJob**
   ```bash
   kubectl apply -f pytorch-distributed-job.yaml

   # Watch job status
   kubectl get pytorchjobs -n kubeflow -w

   # Check pods
   kubectl get pods -n kubeflow -l training.kubeflow.org/job-name=pytorch-distributed-mnist

   # View master logs
   kubectl logs -n kubeflow -l training.kubeflow.org/job-name=pytorch-distributed-mnist,training.kubeflow.org/replica-type=master -f
   ```

### Task 5: Deploy Katib for Hyperparameter Tuning (25 min)

1. **Install Katib**
   ```bash
   kubectl apply -k "github.com/kubeflow/katib/manifests/v1beta1/installs/katib-standalone?ref=v0.17.0"

   # Wait for Katib controller
   kubectl wait --for=condition=Ready pods -n kubeflow -l katib.kubeflow.org/component=controller --timeout=300s
   ```

2. **Create Hyperparameter Tuning Experiment**
   ```yaml
   # Save as katib-experiment.yaml
   apiVersion: kubeflow.org/v1beta1
   kind: Experiment
   metadata:
     name: pytorch-hp-tuning
     namespace: kubeflow
   spec:
     objective:
       type: maximize
       goal: 0.99
       objectiveMetricName: accuracy
       additionalMetricNames:
         - loss
     algorithm:
       algorithmName: random
     parallelTrialCount: 2
     maxTrialCount: 6
     maxFailedTrialCount: 2
     parameters:
       - name: learning_rate
         parameterType: double
         feasibleSpace:
           min: "0.0001"
           max: "0.01"
       - name: batch_size
         parameterType: int
         feasibleSpace:
           min: "32"
           max: "128"
       - name: hidden_size
         parameterType: int
         feasibleSpace:
           min: "64"
           max: "256"
     trialTemplate:
       primaryContainerName: training-container
       trialParameters:
         - name: learningRate
           description: Learning rate
           reference: learning_rate
         - name: batchSize
           description: Batch size
           reference: batch_size
         - name: hiddenSize
           description: Hidden layer size
           reference: hidden_size
       trialSpec:
         apiVersion: batch/v1
         kind: Job
         spec:
           template:
             spec:
               containers:
                 - name: training-container
                   image: pytorch/pytorch:2.1.0-cuda12.1-cudnn8-runtime
                   command:
                     - python
                     - -c
                     - |
                       import torch
                       import torch.nn as nn
                       import os

                       lr = float(os.environ.get('learningRate', 0.001))
                       batch_size = int(os.environ.get('batchSize', 64))
                       hidden_size = int(os.environ.get('hiddenSize', 128))

                       print(f"Training with lr={lr}, batch_size={batch_size}, hidden_size={hidden_size}")

                       # Simple training simulation
                       import random
                       accuracy = 0.85 + random.random() * 0.1
                       loss = random.random() * 0.5

                       # Print metrics in Katib format
                       print(f"accuracy={accuracy:.4f}")
                       print(f"loss={loss:.4f}")
                   resources:
                     limits:
                       nvidia.com/gpu: 1
               restartPolicy: Never
   ```

3. **Run and Monitor Experiment**
   ```bash
   kubectl apply -f katib-experiment.yaml

   # Watch experiment status
   kubectl get experiments -n kubeflow -w

   # Get experiment details
   kubectl describe experiment pytorch-hp-tuning -n kubeflow

   # List trials
   kubectl get trials -n kubeflow -l katib.kubeflow.org/experiment=pytorch-hp-tuning
   ```

4. **Access Katib UI**
   ```bash
   kubectl port-forward -n kubeflow svc/katib-ui 8081:80 &
   echo "Katib UI: http://localhost:8081/katib/"
   ```

### Task 6: Configure Notebook Server (20 min)

1. **Install Notebook Controller**
   ```bash
   kubectl apply -k "github.com/kubeflow/kubeflow/components/notebook-controller/config/overlays/kubeflow?ref=v1.9.0"

   kubectl wait --for=condition=Ready pods -n kubeflow -l app=notebook-controller --timeout=120s
   ```

2. **Create GPU Notebook**
   ```yaml
   # Save as gpu-notebook.yaml
   apiVersion: kubeflow.org/v1
   kind: Notebook
   metadata:
     name: ml-workspace
     namespace: kubeflow
     labels:
       app: ml-workspace
   spec:
     template:
       spec:
         containers:
           - name: ml-workspace
             image: kubeflownotebookswg/jupyter-pytorch-cuda-full:v1.9.0
             resources:
               limits:
                 cpu: "4"
                 memory: 16Gi
                 nvidia.com/gpu: 1
               requests:
                 cpu: "2"
                 memory: 8Gi
             volumeMounts:
               - name: workspace
                 mountPath: /home/jovyan
         volumes:
           - name: workspace
             persistentVolumeClaim:
               claimName: ml-workspace-pvc
   ---
   apiVersion: v1
   kind: PersistentVolumeClaim
   metadata:
     name: ml-workspace-pvc
     namespace: kubeflow
   spec:
     accessModes:
       - ReadWriteOnce
     resources:
       requests:
         storage: 20Gi
   ```

3. **Deploy and Access Notebook**
   ```bash
   kubectl apply -f gpu-notebook.yaml

   # Wait for notebook to be ready
   kubectl get notebooks -n kubeflow -w

   # Port forward to notebook
   kubectl port-forward -n kubeflow svc/ml-workspace 8888:80 &
   echo "Notebook: http://localhost:8888"
   ```

## Deliverables

- [ ] **Screenshot** of Kubeflow Pipelines UI showing completed pipeline
- [ ] **Pipeline YAML** (`gpu_training_pipeline.yaml`) with GPU component
- [ ] **PyTorchJob output** showing distributed training across nodes
- [ ] **Katib experiment results** showing hyperparameter search
- [ ] **Notebook server** running with GPU access

## Verification Checklist

- [ ] Kubeflow Pipelines deployed and accessible
- [ ] GPU training pipeline executed successfully
- [ ] Training Operator managing distributed jobs
- [ ] Katib hyperparameter tuning completed
- [ ] Notebook server operational with GPU

## Troubleshooting

### Pipeline Pods Fail to Schedule

**Check GPU resources:**
```bash
kubectl describe node | grep -A10 "Allocated resources:"
```

**Verify GPU plugin:**
```bash
kubectl get pods -n gpu-operator -l app=nvidia-device-plugin-daemonset
```

### Training Operator Not Working

**Check operator logs:**
```bash
kubectl logs -n kubeflow deployment/training-operator
```

**Verify CRDs:**
```bash
kubectl get crds | grep kubeflow
```

### Katib Trials Failing

**Check trial pod logs:**
```bash
kubectl logs -n kubeflow -l katib.kubeflow.org/experiment=<experiment-name>
```

**Verify metrics collector:**
```bash
kubectl describe trial <trial-name> -n kubeflow
```

## Key Takeaways

1. **Kubeflow Pipelines** enables reproducible ML workflows with versioned artifacts
2. **Training Operators** simplify distributed training with PyTorch, TensorFlow, MPI
3. **Katib** automates hyperparameter tuning with multiple algorithms
4. **GPU resources** can be requested at both pipeline and job level
5. **Notebooks** provide interactive development with GPU access

## Next Lab

Proceed to [Lab 5.10 - MLflow Experiment Tracking](lab-5.10-mlflow-experiment-tracking.md)
