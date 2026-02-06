# Lab 5.9 - Kubeflow ML Platform

---

## Lab Navigation

| Track | Tier | Duration |
|-------|------|----------|
| ML Platforms | Recommended | 3 hours |

### Week 5 Learning Paths

```
FOUNDATION (Required)                         ML PLATFORMS
━━━━━━━━━━━━━━━━━━━━                         ━━━━━━━━━━━━
5.1 ➔ 5.2 ➔ 5.3 ➔ 5.4 ➔ 5.5 ➔ 5.6         YOU ARE HERE
                                                  ↓
                                             [5.9] Kubeflow
                                                  ↓
                                              5.10 MLflow
                                                  ↓
                                              5.11 Run:AI
                                                  ↓
                                              5.12 Slurm ➔ Week 6
```

| Previous | Current | Next |
|----------|---------|------|
| [Lab 5.6 - Troubleshooting](lab-5.6-troubleshooting-gpu.md) | **Lab 5.9 - Kubeflow** | [Lab 5.10 - MLflow](lab-5.10-mlflow-experiment-tracking.md) |

---

**Duration:** 3 hours
**Type:** Hands-on Technical
**Environment:** GPU Lab (k0rdent-managed workload cluster)

## Objective

Deploy and configure Kubeflow as a comprehensive ML platform on a k0rdent-managed GPU cluster. You'll install Kubeflow Pipelines, Training Operator, Katib, and Notebooks, then run GPU-accelerated ML workflows.

## Prerequisites

- Completed Lab 5.1 (GPU Scheduler deployed)
- Completed Lab 5.8 (Cluster Templates) - recommended
- k0rdent-managed workload cluster with GPU nodes (provisioned via ClusterDeployment)
- GPU Operator deployed via `serviceSpec` or `MultiClusterService`
- kubectl access to the workload cluster
- Python 3.9+ with pip

## Background

### What is Kubeflow?

Kubeflow is an open-source ML platform for Kubernetes that makes deploying ML workflows simple, portable, and scalable:

- **Kubeflow Pipelines (KFP)**: Orchestrate ML workflows as DAGs with artifact tracking
- **Training Operator**: Distributed training for PyTorch, TensorFlow, MPI (legacy v1 API)
- **Kubeflow Trainer v2**: Unified TrainJob API replacing framework-specific CRDs (new direction)
- **Katib**: Hyperparameter tuning and neural architecture search
- **Notebooks**: Jupyter notebook servers managed via CRDs

### Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    Kubeflow Dashboard                       │
├─────────────┬──────────────┬──────────────┬────────────────┤
│  Pipelines  │   Notebooks  │    Katib     │   Training     │
│   (KFP)     │   (CRD)      │   (HPO)     │   Operator     │
├─────────────┴──────────────┴──────────────┴────────────────┤
│              Kubernetes + cert-manager                      │
├─────────────────────────────────────────────────────────────┤
│          GPU Nodes (NVIDIA GPU Operator)                    │
└─────────────────────────────────────────────────────────────┘
```

### k0rdent Context

> **Important:** Kubeflow does **not** have a ServiceTemplate in the k0rdent catalog. It must be installed manually on the workload cluster. However, several k0rdent catalog services overlap with or complement Kubeflow sub-components:
>
> | Kubeflow Component | k0rdent Catalog Alternative |
> |--------------------|-----------------------------|
> | Kubeflow Notebooks | `jupyterhub-4-2-0` |
> | KServe (inference) | `kserve-v0-15-0` + `kserve-crd-v0-15-0` |
> | Training Operator | `kuberay-operator-1-3-2` (Ray Train) |
> | Katib (HPO) | KubeRay + Ray Tune |
> | Experiment Tracking | `mlflow-1-7-1` |
>
> This lab installs Kubeflow components directly. For catalog-native ML platforms, see [Lab 5.10 (MLflow)](lab-5.10-mlflow-experiment-tracking.md).

---

## Part 1: Prepare the Workload Cluster

### Task 1: Access the k0rdent-Managed Cluster (10 min)

This lab runs on a workload cluster provisioned via k0rdent `ClusterDeployment` (see [Lab 5.8](lab-5.8-cluster-templates.md)).

1. **Extract kubeconfig from the k0rdent management cluster**

   ```bash
   # On the management cluster
   kubectl get secret ml-dev-kubeconfig -n kcm-system \
     -o jsonpath='{.data.value}' | base64 -d > ml-dev.kubeconfig

   export KUBECONFIG=ml-dev.kubeconfig
   ```

2. **Verify cluster access and GPU availability**

   ```bash
   # Check nodes
   kubectl get nodes -o wide

   # Verify GPU resources
   kubectl get nodes -o custom-columns=\
   'NAME:.metadata.name,GPU:.status.allocatable.nvidia\.com/gpu'

   # Verify GPU Operator is running (deployed via serviceSpec)
   kubectl get pods -n gpu-operator --no-headers | head -5
   ```

3. **Verify cert-manager is present**

   cert-manager is required by several Kubeflow components. In a k0rdent-managed cluster, it should already be deployed as a beach-head service:

   ```bash
   kubectl get pods -n cert-manager
   ```

   If cert-manager is not present, install it:
   ```bash
   kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.16.2/cert-manager.yaml
   kubectl wait --for=condition=Ready pods --all -n cert-manager --timeout=300s
   ```

4. **Verify default StorageClass**

   ```bash
   kubectl get storageclass
   ```

   You should see a default StorageClass (marked with `(default)`). On AWS clusters provisioned via k0rdent, this is typically `gp2` or `gp3` backed by the EBS CSI driver. If no default exists:

   ```bash
   # Mark existing EBS StorageClass as default
   kubectl patch storageclass gp2 -p \
     '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
   ```

---

## Part 2: Deploy Kubeflow Pipelines

### Task 2: Install Kubeflow Pipelines (30 min)

1. **Set KFP version and deploy**

   ```bash
   export KFP_VERSION=2.15.2

   # Apply cluster-scoped resources (CRDs)
   kubectl apply -k "github.com/kubeflow/pipelines/manifests/kustomize/cluster-scoped-resources?ref=$KFP_VERSION"

   # Wait for CRDs to be established
   kubectl wait --for condition=established --timeout=60s crd/applications.app.k8s.io

   # Deploy Kubeflow Pipelines (standalone, platform-agnostic)
   kubectl apply -k "github.com/kubeflow/pipelines/manifests/kustomize/env/platform-agnostic?ref=$KFP_VERSION"
   ```

2. **Wait for all components**

   ```bash
   # Watch pods come up (takes 5-10 minutes)
   kubectl get pods -n kubeflow -w

   # Wait for readiness
   kubectl wait --for=condition=Ready pods --all -n kubeflow --timeout=600s
   ```

3. **Access the Pipelines UI**

   ```bash
   kubectl port-forward -n kubeflow svc/ml-pipeline-ui 8080:80 &
   echo "Kubeflow Pipelines UI: http://localhost:8080"
   ```

4. **Verify installation**

   ```bash
   # Check KFP API server
   kubectl get pods -n kubeflow -l app=ml-pipeline

   # Check API server logs
   kubectl logs -n kubeflow -l app=ml-pipeline -c ml-pipeline-api-server --tail=10
   ```

### Task 3: Create and Run a GPU Training Pipeline (40 min)

1. **Install the KFP Python SDK**

   ```bash
   pip install kfp==2.15.2

   # Verify
   python3 -c "import kfp; print(f'KFP Version: {kfp.__version__}')"
   ```

2. **Create a GPU training pipeline**

   ```python
   # Save as gpu_training_pipeline.py
   from kfp import dsl
   from kfp import compiler
   from kfp.dsl import Dataset, Input, Output, Model

   @dsl.component(
       base_image='python:3.11-slim',
       packages_to_install=['pandas==2.2.0', 'scikit-learn==1.4.0']
   )
   def create_dataset(output_dataset: Output[Dataset]):
       """Generate a synthetic classification dataset."""
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
       packages_to_install=['pandas==2.2.0', 'scikit-learn==1.4.0']
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

           model.eval()
           with torch.no_grad():
               val_outputs = model(X_val).squeeze()
               val_loss = criterion(val_outputs, y_val)
               accuracy = ((val_outputs > 0.5) == y_val).float().mean()

           if (epoch + 1) % 2 == 0:
               print(f"Epoch {epoch+1}/{epochs}, Loss: {loss:.4f}, Val Acc: {accuracy:.4f}")

       torch.save(model.state_dict(), model_output.path)
       print(f"Model saved to {model_output.path}")

   @dsl.component(base_image='python:3.11-slim')
   def report_model(model_path: Input[Model]) -> float:
       """Report model metadata."""
       import os
       model_size = os.path.getsize(model_path.path)
       print(f"Model size: {model_size} bytes")
       return 0.95

   @dsl.pipeline(
       name='gpu-training-pipeline',
       description='Pipeline that trains a PyTorch model on GPU'
   )
   def gpu_training_pipeline(epochs: int = 10, learning_rate: float = 0.001):
       create_dataset_task = create_dataset()

       train_task = train_model_gpu(
           input_dataset=create_dataset_task.outputs['output_dataset'],
           epochs=epochs,
           learning_rate=learning_rate
       )
       train_task.set_gpu_limit(1)

       report_task = report_model(
           model_path=train_task.outputs['model_output']
       )

   if __name__ == '__main__':
       compiler.Compiler().compile(
           pipeline_func=gpu_training_pipeline,
           package_path='gpu_training_pipeline.yaml'
       )
       print("Pipeline compiled to gpu_training_pipeline.yaml")
   ```

   > **Note:** The `pytorch/pytorch:2.1.0-cuda12.1-cudnn8-runtime` image is pinned for lab reproducibility. In production, use a more recent PyTorch image (2.5+ is recommended). Check [Docker Hub](https://hub.docker.com/r/pytorch/pytorch/tags) for current tags.

3. **Compile and submit the pipeline**

   ```bash
   # Compile
   python3 gpu_training_pipeline.py

   # Submit via SDK
   python3 << 'PYEOF'
   from kfp.client import Client

   client = Client(host='http://localhost:8080')

   experiment = client.create_experiment('gpu-training-experiments')

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
   PYEOF
   ```

4. **Monitor pipeline execution**

   ```bash
   # Watch pipeline pods
   kubectl get pods -n kubeflow -l pipeline/runid -w

   # Check logs of a running component
   kubectl logs -n kubeflow -l pipeline/runid -f --tail=20
   ```

   Open the Pipelines UI at http://localhost:8080 to see the DAG visualization with step statuses and artifact lineage.

---

## Part 3: Distributed Training with Training Operator

### Task 4: Install Training Operator and Run PyTorchJob (35 min)

The Training Operator manages distributed training jobs. It supports the legacy `PyTorchJob` API (`kubeflow.org/v1`) and the newer unified `TrainJob` API (`trainer.kubeflow.org/v1alpha1`). This lab uses PyTorchJob since it remains widely used.

> **Note:** Kubeflow Trainer v2 introduces TrainJob as a unified replacement for PyTorchJob, TFJob, and MPIJob. TrainJob uses `ClusterTrainingRuntime` for reusable training configurations and integrates natively with Kueue for job scheduling. For new projects, consider adopting TrainJob. See the [migration guide](https://www.kubeflow.org/docs/components/trainer/operator-guides/migration/).

1. **Install the Training Operator**

   ```bash
   kubectl apply -k "github.com/kubeflow/training-operator/manifests/overlays/standalone?ref=v1.8.1"

   # Wait for the operator
   kubectl wait --for=condition=Ready pods -n kubeflow \
     -l control-plane=kubeflow-training-operator --timeout=120s
   ```

2. **Create a distributed PyTorchJob**

   In a PyTorchJob, **all replicas (master and workers) run the same training code**. The Training Operator sets `MASTER_ADDR`, `MASTER_PORT`, `WORLD_SIZE`, and `RANK` environment variables. Each replica discovers its role via these variables.

   First, create a ConfigMap with the shared training script:

   ```yaml
   # Save as pytorch-training-script.yaml
   apiVersion: v1
   kind: ConfigMap
   metadata:
     name: mnist-training-script
     namespace: kubeflow
   data:
     train.py: |
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

       rank = dist.get_rank()
       world_size = dist.get_world_size()
       print(f"Rank {rank}/{world_size}, GPU: {torch.cuda.get_device_name(local_rank)}")

       # Simple CNN for MNIST
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

       # Load MNIST (each rank downloads independently)
       transform = transforms.Compose([
           transforms.ToTensor(),
           transforms.Normalize((0.1307,), (0.3081,))
       ])
       dataset = datasets.MNIST('./data', train=True, download=True, transform=transform)
       sampler = DistributedSampler(dataset, num_replicas=world_size, rank=rank)
       loader = DataLoader(dataset, batch_size=64, sampler=sampler)

       optimizer = torch.optim.Adam(model.parameters(), lr=0.001)

       for epoch in range(3):
           sampler.set_epoch(epoch)
           for batch_idx, (data, target) in enumerate(loader):
               data, target = data.to(device), target.to(device)
               optimizer.zero_grad()
               output = model(data)
               loss = F.nll_loss(output, target)
               loss.backward()
               optimizer.step()

               if batch_idx % 100 == 0 and rank == 0:
                   print(f"Epoch {epoch}, Batch {batch_idx}, Loss: {loss.item():.4f}")

       if rank == 0:
           print("Training completed!")
       dist.destroy_process_group()
   ```

   Then create the PyTorchJob that uses this shared script:

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
                 command: ["python", "/scripts/train.py"]
                 resources:
                   limits:
                     nvidia.com/gpu: 1
                 volumeMounts:
                   - name: training-script
                     mountPath: /scripts
             volumes:
               - name: training-script
                 configMap:
                   name: mnist-training-script
       Worker:
         replicas: 2
         restartPolicy: OnFailure
         template:
           spec:
             containers:
               - name: pytorch
                 image: pytorch/pytorch:2.1.0-cuda12.1-cudnn8-runtime
                 command: ["python", "/scripts/train.py"]
                 resources:
                   limits:
                     nvidia.com/gpu: 1
                 volumeMounts:
                   - name: training-script
                     mountPath: /scripts
             volumes:
               - name: training-script
                 configMap:
                   name: mnist-training-script
   ```

   > **Key pattern:** Both Master and Worker mount the **same ConfigMap** and run the **same script**. The Training Operator sets environment variables (`MASTER_ADDR`, `MASTER_PORT`, `WORLD_SIZE`, `RANK`) so each replica discovers its role. Only rank 0 (the master) prints progress and saves checkpoints. In production, you'd bake the training script into a container image.

3. **Submit and monitor**

   ```bash
   kubectl apply -f pytorch-training-script.yaml
   kubectl apply -f pytorch-distributed-job.yaml

   # Watch job status
   kubectl get pytorchjobs -n kubeflow -w

   # Check pods (1 master + 2 workers = 3 pods)
   kubectl get pods -n kubeflow -l training.kubeflow.org/job-name=pytorch-distributed-mnist

   # View master logs (rank 0 prints training progress)
   kubectl logs -n kubeflow \
     -l training.kubeflow.org/job-name=pytorch-distributed-mnist,training.kubeflow.org/replica-type=master -f
   ```

   Expected output:
   ```
   Rank 0/3, GPU: NVIDIA A10G
   Epoch 0, Batch 0, Loss: 2.3104
   Epoch 0, Batch 100, Loss: 0.1842
   ...
   Training completed!
   ```

4. **Verify distributed communication**

   ```bash
   # Check worker logs to confirm they joined the process group
   kubectl logs -n kubeflow \
     -l training.kubeflow.org/job-name=pytorch-distributed-mnist,training.kubeflow.org/replica-type=worker
   ```

   Workers should show their rank (1 and 2) and GPU name, confirming they participated in training.

---

## Part 4: Hyperparameter Tuning with Katib

### Task 5: Install Katib and Run an Experiment (30 min)

1. **Install Katib**

   ```bash
   kubectl apply -k "github.com/kubeflow/katib/manifests/v1beta1/installs/katib-standalone?ref=v0.18.0"

   # Wait for the Katib controller
   kubectl wait --for=condition=Ready pods -n kubeflow \
     -l katib.kubeflow.org/component=controller --timeout=300s
   ```

2. **Create a hyperparameter tuning experiment**

   This experiment tunes learning rate, batch size, and hidden layer size for a GPU-trained PyTorch model:

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
                       from sklearn.datasets import make_classification
                       from sklearn.model_selection import train_test_split
                       import os

                       lr = float(os.environ.get('learningRate', 0.001))
                       batch_size = int(os.environ.get('batchSize', 64))
                       hidden_size = int(os.environ.get('hiddenSize', 128))

                       device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
                       print(f"Device: {device}, lr={lr}, batch={batch_size}, hidden={hidden_size}")

                       # Generate data
                       X, y = make_classification(n_samples=5000, n_features=20, random_state=42)
                       X_train, X_val, y_train, y_val = train_test_split(X, y, test_size=0.2)

                       X_train = torch.FloatTensor(X_train).to(device)
                       y_train = torch.FloatTensor(y_train).to(device)
                       X_val = torch.FloatTensor(X_val).to(device)
                       y_val = torch.FloatTensor(y_val).to(device)

                       model = nn.Sequential(
                           nn.Linear(20, hidden_size),
                           nn.ReLU(),
                           nn.Dropout(0.2),
                           nn.Linear(hidden_size, hidden_size // 2),
                           nn.ReLU(),
                           nn.Linear(hidden_size // 2, 1),
                           nn.Sigmoid()
                       ).to(device)

                       criterion = nn.BCELoss()
                       optimizer = torch.optim.Adam(model.parameters(), lr=lr)

                       # Train with mini-batches
                       for epoch in range(20):
                           model.train()
                           for i in range(0, len(X_train), batch_size):
                               batch_X = X_train[i:i+batch_size]
                               batch_y = y_train[i:i+batch_size]
                               optimizer.zero_grad()
                               out = model(batch_X).squeeze()
                               loss = criterion(out, batch_y)
                               loss.backward()
                               optimizer.step()

                       # Print metrics in Katib stdout format (key=value)
                       model.eval()
                       with torch.no_grad():
                           val_out = model(X_val).squeeze()
                           val_loss = criterion(val_out, y_val).item()
                           accuracy = ((val_out > 0.5).float() == y_val).float().mean().item()

                       print(f"accuracy={accuracy:.4f}")
                       print(f"loss={val_loss:.4f}")
                   resources:
                     limits:
                       nvidia.com/gpu: 1
                     requests:
                       cpu: "1"
                       memory: 4Gi
               restartPolicy: Never
   ```

   > **Note:** Katib parses metrics from stdout using the `key=value` format by default (StdLog metrics collector). Each trial prints `accuracy=X.XXXX` and `loss=X.XXXX` which Katib records for optimization.

3. **Run and monitor the experiment**

   ```bash
   kubectl apply -f katib-experiment.yaml

   # Watch experiment progress
   kubectl get experiments -n kubeflow -w

   # Get detailed status
   kubectl describe experiment pytorch-hp-tuning -n kubeflow

   # List trials and their results
   kubectl get trials -n kubeflow -l katib.kubeflow.org/experiment=pytorch-hp-tuning
   ```

4. **View results**

   ```bash
   # Get optimal hyperparameters
   kubectl get experiment pytorch-hp-tuning -n kubeflow \
     -o jsonpath='{.status.currentOptimalTrial}' | python3 -m json.tool
   ```

   This shows the best trial's hyperparameters and corresponding accuracy.

5. **Access Katib UI** (optional)

   ```bash
   kubectl port-forward -n kubeflow svc/katib-ui 8081:80 &
   echo "Katib UI: http://localhost:8081/katib/"
   ```

---

## Part 5: Notebook Server

### Task 6: Deploy a GPU-Enabled Notebook (20 min)

Kubeflow manages Jupyter notebook servers via CRDs, providing per-user GPU-enabled environments.

1. **Install the Notebook Controller**

   ```bash
   kubectl apply -k "github.com/kubeflow/kubeflow/components/notebook-controller/config/overlays/kubeflow?ref=v1.9.0"

   kubectl wait --for=condition=Ready pods -n kubeflow \
     -l app=notebook-controller --timeout=120s
   ```

2. **Create a GPU notebook**

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

   > **Note:** The `kubeflownotebookswg/*` images are hosted on Docker Hub. Newer Kubeflow releases publish images to `ghcr.io/kubeflow/notebook-servers/`. Check the [Kubeflow container images docs](https://www.kubeflow.org/docs/components/notebooks/container-images/) for current image names.

3. **Deploy and access the notebook**

   ```bash
   kubectl apply -f gpu-notebook.yaml

   # Wait for the notebook pod
   kubectl get notebooks -n kubeflow -w

   # Port-forward to the notebook
   kubectl port-forward -n kubeflow svc/ml-workspace 8888:80 &
   echo "Notebook: http://localhost:8888"
   ```

4. **Verify GPU access inside the notebook**

   Open a terminal in the notebook and run:
   ```python
   import torch
   print(f"CUDA available: {torch.cuda.is_available()}")
   print(f"GPU: {torch.cuda.get_device_name(0)}")
   ```

---

## Cleanup

Remove Kubeflow components when done to free cluster resources:

```bash
# Delete workloads
kubectl delete notebook ml-workspace -n kubeflow
kubectl delete pvc ml-workspace-pvc -n kubeflow
kubectl delete experiment pytorch-hp-tuning -n kubeflow
kubectl delete pytorchjob pytorch-distributed-mnist -n kubeflow
kubectl delete configmap mnist-training-script -n kubeflow

# Remove Kubeflow components (reverse order of installation)
kubectl delete -k "github.com/kubeflow/kubeflow/components/notebook-controller/config/overlays/kubeflow?ref=v1.9.0"
kubectl delete -k "github.com/kubeflow/katib/manifests/v1beta1/installs/katib-standalone?ref=v0.18.0"
kubectl delete -k "github.com/kubeflow/training-operator/manifests/overlays/standalone?ref=v1.8.1"
kubectl delete -k "github.com/kubeflow/pipelines/manifests/kustomize/env/platform-agnostic?ref=2.15.2"
kubectl delete -k "github.com/kubeflow/pipelines/manifests/kustomize/cluster-scoped-resources?ref=2.15.2"

# Verify namespace is clean
kubectl get pods -n kubeflow
```

> **Note:** Kubeflow components consume significant resources (8+ vCPUs, 16+ GB RAM). Clean up promptly if the cluster is shared.

---

## Verification Checklist

- [ ] Accessed k0rdent-managed workload cluster via kubeconfig extraction
- [ ] Kubeflow Pipelines v2.15.2 deployed and UI accessible
- [ ] GPU training pipeline compiled, submitted, and completed
- [ ] Training Operator installed and PyTorchJob ran with 3 replicas (1 master + 2 workers)
- [ ] All replicas participated in distributed training (verified via worker logs)
- [ ] Katib hyperparameter tuning experiment completed with optimal trial results
- [ ] GPU notebook server running with CUDA access

## Troubleshooting

### Pipeline Pods Fail to Schedule

```bash
# Check GPU resource availability
kubectl describe nodes | grep -A5 "Allocated resources:"

# Verify GPU device plugin
kubectl get pods -n gpu-operator -l app=nvidia-device-plugin-daemonset
```

### PyTorchJob Workers Not Joining

```bash
# Check all replica pods
kubectl get pods -n kubeflow -l training.kubeflow.org/job-name=pytorch-distributed-mnist

# Check worker logs for NCCL errors
kubectl logs -n kubeflow <worker-pod-name>

# Verify NCCL can communicate (check for timeout errors)
kubectl describe pod <worker-pod-name> -n kubeflow
```

### Katib Trials Failing

```bash
# Check trial pod logs
kubectl logs -n kubeflow -l katib.kubeflow.org/experiment=pytorch-hp-tuning --tail=20

# Check metrics collector
kubectl describe trial <trial-name> -n kubeflow

# Verify Katib controller
kubectl logs -n kubeflow -l katib.kubeflow.org/component=controller --tail=20
```

### Notebook Not Starting

```bash
# Check notebook status
kubectl describe notebook ml-workspace -n kubeflow

# Check PVC binding
kubectl get pvc -n kubeflow

# Check pod events
kubectl describe pod ml-workspace-0 -n kubeflow
```

---

## Key Takeaways

1. **Kubeflow is not in the k0rdent catalog** - install manually on workload clusters, or use catalog-native alternatives (KubeRay, MLflow, KServe, JupyterHub)
2. **KFP v2 pipelines** use `@dsl.component` decorators with typed artifacts (`Dataset`, `Model`) and `set_gpu_limit()` for GPU access
3. **Distributed training** requires all replicas to run the same code - the Training Operator manages environment variables for process group initialization
4. **Kubeflow Trainer v2** (TrainJob) is the new unified API direction, replacing framework-specific CRDs like PyTorchJob
5. **Katib** automates hyperparameter tuning using stdout-based metric collection (`key=value` format)
6. **Notebook CRDs** provide managed, per-user GPU-enabled Jupyter environments

---

## Next Lab

Proceed to [Lab 5.10 - MLflow Experiment Tracking](lab-5.10-mlflow-experiment-tracking.md)
