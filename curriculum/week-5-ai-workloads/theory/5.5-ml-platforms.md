# 5.5 ML Platform Architecture

**Duration:** 45 minutes
**Type:** Theory / Reading

## Learning Objectives

By the end of this module, you will be able to:

- [ ] Describe the components of a modern ML platform
- [ ] Compare Kubeflow and MLflow architectures and use cases
- [ ] Explain experiment tracking, model registry, and pipeline concepts
- [ ] Understand how ML platforms integrate with Kubernetes
- [ ] Choose appropriate ML platform components for different scenarios

---

## 1. ML Platform Components

### 1.1 What is an ML Platform?

An ML platform provides the infrastructure and tools for the complete machine learning lifecycle:

```mermaid
flowchart TB
    subgraph "ML Lifecycle"
        DEV[Development] --> TRAIN[Training]
        TRAIN --> EVAL[Evaluation]
        EVAL --> REG[Model Registry]
        REG --> DEPLOY[Deployment]
        DEPLOY --> MONITOR[Monitoring]
        MONITOR -->|Retrain| TRAIN
    end

    subgraph "ML Platform Components"
        NB[Notebooks<br/>Kubeflow Notebook Controller]
        EXP[Experiment Tracking<br/>MLflow Tracking]
        PIPE[Pipelines<br/>Kubeflow Pipelines]
        TRAIN_OP[Trainer v2<br/>Kubeflow TrainJob]
        MR[Model Registry<br/>MLflow Registry]
        SERVE[Model Serving<br/>KServe, vLLM]
        HP[Hyperparameter Tuning<br/>Katib]
    end

    DEV --- NB
    TRAIN --- PIPE & TRAIN_OP
    EVAL --- EXP & HP
    REG --- MR
    DEPLOY --- SERVE
```

### 1.2 Core Platform Capabilities

| Capability | Purpose | Tools |
|------------|---------|-------|
| **Experiment Tracking** | Log params, metrics, artifacts | MLflow Tracking, W&B |
| **Pipeline Orchestration** | Define and run ML workflows | Kubeflow Pipelines, Airflow |
| **Distributed Training** | Scale training across GPUs/nodes | Kubeflow Training, Ray |
| **Hyperparameter Tuning** | Automated model optimization | Katib, Optuna |
| **Model Registry** | Version and manage models | MLflow Registry |
| **Model Serving** | Deploy models as APIs | KServe, vLLM, Triton |
| **Feature Store** | Manage ML features | Feast, Tecton |

---

## 2. Kubeflow Architecture

### 2.1 Kubeflow Overview

Kubeflow is a Kubernetes-native ML platform providing end-to-end ML capabilities:

```mermaid
flowchart TB
    subgraph "Kubeflow Components"
        subgraph "Development"
            NB[Kubeflow Notebooks<br/>Notebook Controller + VS Code]
        end

        subgraph "Training"
            TR[Trainer v2 / TrainJob<br/>PyTorch, TensorFlow, MPI]
            KT[Katib<br/>Hyperparameter Tuning]
        end

        subgraph "Pipelines"
            KFP[Kubeflow Pipelines<br/>Workflow Orchestration]
        end

        subgraph "Serving"
            KS[KServe<br/>Model Serving]
        end

        subgraph "Core"
            DASH[Central Dashboard]
            PROF[Profiles<br/>Multi-tenancy]
        end

        NB --> KFP
        KFP --> TR
        KFP --> KT
        TR --> KS
    end
```

### 2.2 Kubeflow Training Operators

Kubeflow provides specialized operators for different training frameworks. The **Kubeflow Trainer v2** (July 2025) introduced a unified `TrainJob` API that supersedes per-framework CRDs:

| API | Framework | Status |
|-----|-----------|--------|
| **TrainJob** (Trainer v2) | All frameworks via `runtimeRef` | **Current** — unified API |
| **PyTorchJob** | PyTorch | Legacy — superseded by TrainJob |
| **TFJob** | TensorFlow | Legacy — superseded by TrainJob |
| **MPIJob** | Horovod, MPI | Legacy — superseded by TrainJob |
| **XGBoostJob** | XGBoost | Legacy — superseded by TrainJob |
| **PaddleJob** | PaddlePaddle | Legacy — superseded by TrainJob |

**TrainJob Example (Kubeflow Trainer v2):**

```yaml
apiVersion: trainer.kubeflow.org/v1alpha1
kind: TrainJob
metadata:
  name: pytorch-distributed
spec:
  runtimeRef:
    name: torch-distributed    # References a ClusterTrainingRuntime
  trainer:
    image: pytorch/pytorch:2.10.0-cuda12.6-cudnn9-runtime
    command:
      - torchrun
      - train.py
    numNodes: 4                # Total nodes (replaces Master/Worker split)
    resourcesPerNode:
      requests:
        nvidia.com/gpu: 8
      limits:
        nvidia.com/gpu: 8
```

> **Note:** Trainer v2 uses `ClusterTrainingRuntime` resources to define framework-specific behavior (PyTorch DDP, DeepSpeed, MPI, etc.), decoupling the training job definition from framework configuration. The legacy per-framework APIs (`kubeflow.org/v1 PyTorchJob`, etc.) remain available for backward compatibility but are no longer the recommended path.

<details>
<summary>Legacy PyTorchJob Example (kubeflow.org/v1)</summary>

```yaml
apiVersion: kubeflow.org/v1
kind: PyTorchJob
metadata:
  name: pytorch-distributed
spec:
  pytorchReplicaSpecs:
    Master:
      replicas: 1
      template:
        spec:
          containers:
            - name: pytorch
              image: pytorch/pytorch:2.10.0-cuda12.6-cudnn9-runtime
              command:
                - torchrun
                - --nproc_per_node=8
                - train.py
              resources:
                limits:
                  nvidia.com/gpu: 8
    Worker:
      replicas: 3
      template:
        spec:
          containers:
            - name: pytorch
              image: pytorch/pytorch:2.10.0-cuda12.6-cudnn9-runtime
              command:
                - torchrun
                - --nproc_per_node=8
                - train.py
              resources:
                limits:
                  nvidia.com/gpu: 8
```

</details>

### 2.3 Kubeflow Pipelines

Kubeflow Pipelines (KFP) orchestrates ML workflows as DAGs:

```mermaid
flowchart LR
    subgraph "Example ML Pipeline"
        A[Load Data] --> B[Preprocess]
        B --> C[Train Model]
        B --> D[Validate Data]
        C --> E[Evaluate]
        D --> E
        E --> F{Accuracy > 0.9?}
        F -->|Yes| G[Register Model]
        F -->|No| H[Notify Team]
        G --> I[Deploy to Staging]
    end
```

**KFP Component Definition:**

```python
from kfp import dsl
from kfp.dsl import Dataset, Input, Output, Model

@dsl.component(
    packages_to_install=['pandas', 'scikit-learn']
)
def train_model(
    training_data: Input[Dataset],
    model: Output[Model],
    n_estimators: int = 100,
) -> float:
    import pandas as pd
    from sklearn.ensemble import RandomForestClassifier
    from sklearn.model_selection import cross_val_score
    import joblib  # Use joblib for sklearn models (safer than pickle)

    # Load data
    df = pd.read_csv(training_data.path)
    X, y = df.drop('target', axis=1), df['target']

    # Train model
    clf = RandomForestClassifier(n_estimators=n_estimators)
    clf.fit(X, y)

    # Evaluate
    accuracy = cross_val_score(clf, X, y, cv=5).mean()

    # Save model using joblib
    joblib.dump(clf, model.path)

    return accuracy


@dsl.pipeline(name='training-pipeline')
def training_pipeline(n_estimators: int = 100):
    load_data_task = load_data()
    train_task = train_model(
        training_data=load_data_task.outputs['dataset'],
        n_estimators=n_estimators
    )
```

### 2.4 Katib: Hyperparameter Tuning

Katib automates hyperparameter search on Kubernetes:

```mermaid
flowchart TB
    subgraph "Katib Architecture"
        EXP[Experiment<br/>Define search space]
        SUG[Suggestion<br/>Algorithm: Bayesian, Grid, Random]
        TRIAL[Trials<br/>Training runs]
        METRICS[Metrics Collector<br/>Scrape results]

        EXP --> SUG
        SUG --> TRIAL
        TRIAL --> METRICS
        METRICS --> SUG
    end
```

**Katib Experiment:**

```yaml
apiVersion: kubeflow.org/v1beta1
kind: Experiment
metadata:
  name: hyperparameter-tuning
spec:
  objective:
    type: maximize
    goal: 0.95
    objectiveMetricName: accuracy
  algorithm:
    algorithmName: bayesianoptimization
  parallelTrialCount: 4
  maxTrialCount: 20
  maxFailedTrialCount: 3
  parameters:
    - name: learning_rate
      parameterType: double
      feasibleSpace:
        min: "0.0001"
        max: "0.1"
    - name: batch_size
      parameterType: int
      feasibleSpace:
        min: "16"
        max: "128"
  trialTemplate:
    primaryContainerName: training
    trialParameters:
      - name: learningRate
        reference: learning_rate
      - name: batchSize
        reference: batch_size
    trialSpec:
      apiVersion: batch/v1
      kind: Job
      spec:
        template:
          spec:
            containers:
              - name: training
                image: my-training-image
                command:
                  - python
                  - train.py
                  - --lr=${trialParameters.learningRate}
                  - --batch-size=${trialParameters.batchSize}
```

---

## 3. MLflow Architecture

### 3.1 MLflow Overview

MLflow is a lightweight, open-source ML lifecycle platform:

```mermaid
flowchart TB
    subgraph "MLflow Components (v3.x)"
        TRACK[MLflow Tracking<br/>Experiments, Runs, Metrics]
        MODEL[MLflow Models<br/>Packaging Format]
        REG[MLflow Registry<br/>Model Aliases & Tags]
        GW[AI Gateway<br/>Unified LLM API Proxy]

        TRACK --> MODEL
        MODEL --> REG
        TRACK --> GW
    end
```

> **Note:** MLflow 3.x still documents MLflow Projects and AI Gateway / Gateway Server. Teams commonly pair the tracking server with those features instead of treating them as removed.

### 3.2 MLflow Tracking

Track experiments, parameters, metrics, and artifacts:

```python
import mlflow
from mlflow.models import infer_signature

# Set tracking URI (can be local, remote, or database)
mlflow.set_tracking_uri("http://mlflow-server:5000")
mlflow.set_experiment("llm-fine-tuning")

with mlflow.start_run(run_name="llama-7b-lora"):
    # Log parameters
    mlflow.log_params({
        "model": "meta-llama/Llama-2-7b",
        "learning_rate": 2e-5,
        "batch_size": 4,
        "lora_rank": 8,
        "epochs": 3
    })

    # Training loop
    for epoch in range(3):
        train_loss = train_epoch(model, train_loader)
        val_loss = evaluate(model, val_loader)

        # Log metrics
        mlflow.log_metrics({
            "train_loss": train_loss,
            "val_loss": val_loss,
        }, step=epoch)

    # Log model using MLflow's built-in model logging
    signature = infer_signature(sample_input, sample_output)
    mlflow.pytorch.log_model(
        model,
        "model",
        signature=signature,
        registered_model_name="llama-7b-finetuned"
    )

    # Log artifacts
    mlflow.log_artifact("training_config.yaml")
    mlflow.log_artifact("evaluation_results.json")
```

### 3.3 MLflow Model Registry

Version, tag, and manage models with aliases:

```mermaid
flowchart LR
    subgraph "Model Registry Workflow (MLflow 3.x)"
        V1[Version 1<br/>no alias]
        V2[Version 2<br/>@challenger]
        V3[Version 3<br/>@champion]
        V4[Version 4<br/>@candidate]

        V4 -->|Promote| V4_P["Version 4<br/>@champion"]
        V3 -->|Demote| V3_D["Version 3<br/>@previous"]
        V2 -->|Archive| V2_A["Version 2<br/>tag: archived"]
    end
```

> **Note:** MLflow 3.x emphasizes **model aliases** such as `@champion`, `@challenger`, and `@candidate`, but current MLflow docs still reference lifecycle stages for compatibility and migration scenarios.

**Model Registry Operations (MLflow 3.x):**

```python
from mlflow import MlflowClient

client = MlflowClient()

# Register a model version
result = client.create_model_version(
    name="llama-7b-finetuned",
    source="runs:/abc123/model",
    run_id="abc123"
)

# Assign alias for testing (replaces "transition to staging")
client.set_registered_model_alias(
    name="llama-7b-finetuned",
    alias="candidate",
    version=4
)

# Promote to production (replaces "transition to production")
client.set_registered_model_alias(
    name="llama-7b-finetuned",
    alias="champion",
    version=4
)

# Load production model using alias URI
model = mlflow.pytorch.load_model(
    "models:/llama-7b-finetuned@champion"
)

# Look up which version has an alias
version = client.get_model_version_by_alias(
    name="llama-7b-finetuned",
    alias="champion"
)
```

### 3.4 MLflow on Kubernetes

```yaml
# MLflow Tracking Server Deployment
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mlflow-server
spec:
  replicas: 1
  selector:
    matchLabels:
      app: mlflow
  template:
    metadata:
      labels:
        app: mlflow
    spec:
      containers:
        - name: mlflow
          image: ghcr.io/mlflow/mlflow:v3.9.0
          command:
            - mlflow
            - server
            - --host=0.0.0.0
            - --port=5000
            - --backend-store-uri=postgresql://mlflow:password@postgres:5432/mlflow
            - --default-artifact-root=s3://mlflow-artifacts/
          ports:
            - containerPort: 5000
          env:
            - name: AWS_ACCESS_KEY_ID
              valueFrom:
                secretKeyRef:
                  name: mlflow-s3
                  key: access-key
            - name: AWS_SECRET_ACCESS_KEY
              valueFrom:
                secretKeyRef:
                  name: mlflow-s3
                  key: secret-key
---
apiVersion: v1
kind: Service
metadata:
  name: mlflow-server
spec:
  selector:
    app: mlflow
  ports:
    - port: 5000
      targetPort: 5000
```

---

## 4. Kubeflow vs MLflow Comparison

### 4.1 Feature Comparison

| Feature | Kubeflow | MLflow |
|---------|----------|--------|
| **Experiment Tracking** | Basic (via Pipelines) | Comprehensive |
| **Pipeline Orchestration** | Kubeflow Pipelines | MLflow Projects / packaging, but not a DAG orchestrator like Kubeflow Pipelines |
| **Distributed Training** | Trainer v2 (TrainJob) | None (use externally) |
| **Hyperparameter Tuning** | Katib | None (integrate Optuna) |
| **Model Registry** | Model Registry v0.3.4 | MLflow Registry (alias-based) |
| **Model Serving** | KServe | MLflow Models + external |
| **LLM Gateway** | None | AI Gateway (built-in) |
| **Notebooks** | Notebook Controller (CRD) | None |
| **Kubernetes Native** | Yes (CRDs) | Deployable on K8s |
| **Complexity** | High | Low |
| **Multi-tenancy** | Profiles | Basic |

### 4.2 When to Use What

```mermaid
flowchart TB
    Q1{What's your primary need?}

    Q1 -->|Experiment Tracking| MLF[MLflow]
    Q1 -->|Pipeline Orchestration| Q2{Team size?}
    Q1 -->|Distributed Training| KF[Kubeflow]
    Q1 -->|Full Platform| Q3{Resources?}

    Q2 -->|Small team| MLF
    Q2 -->|Large team| KF

    Q3 -->|Limited| MLF[MLflow + TrainJob]
    Q3 -->|Abundant| BOTH[Kubeflow + MLflow]
```

### 4.3 Recommended Architecture

Most organizations benefit from combining both:

```mermaid
flowchart TB
    subgraph "Combined ML Platform"
        subgraph "Kubeflow"
            NB[Notebooks]
            TR[Trainer v2 / TrainJob]
            KT[Katib]
            KFP[Pipelines]
        end

        subgraph "MLflow"
            TRACK[Tracking Server]
            REG[Model Registry]
        end

        subgraph "Serving"
            VLLM[vLLM<br/>LLM Inference]
            KS[KServe<br/>Traditional ML]
        end

        NB --> KFP
        KFP --> TR
        TR --> TRACK
        TRACK --> REG
        REG --> VLLM
        REG --> KS
    end
```

---

## 5. Integration Patterns

### 5.1 MLflow in Kubeflow Pipelines

```python
from kfp import dsl

@dsl.component(packages_to_install=['mlflow'])
def train_with_mlflow(
    mlflow_tracking_uri: str,
    experiment_name: str,
) -> str:
    import mlflow

    mlflow.set_tracking_uri(mlflow_tracking_uri)
    mlflow.set_experiment(experiment_name)

    with mlflow.start_run() as run:
        # Training code here
        mlflow.log_params({"param1": "value1"})
        mlflow.log_metrics({"accuracy": 0.95})

        # Register model
        mlflow.pytorch.log_model(
            model, "model",
            registered_model_name="my-model"
        )

        return run.info.run_id


@dsl.pipeline(name='mlflow-integrated-pipeline')
def ml_pipeline():
    train_task = train_with_mlflow(
        mlflow_tracking_uri="http://mlflow-server:5000",
        experiment_name="kubeflow-training"
    )
```

### 5.2 Kubeflow Trainer with MLflow

```yaml
# Trainer v2 TrainJob with MLflow environment variables
apiVersion: trainer.kubeflow.org/v1alpha1
kind: TrainJob
metadata:
  name: mlflow-training
spec:
  runtimeRef:
    name: torch-distributed
  trainer:
    image: my-training-image
    command:
      - torchrun
      - train.py
    numNodes: 4
    env:
      - name: MLFLOW_TRACKING_URI
        value: "http://mlflow-server:5000"
      - name: MLFLOW_EXPERIMENT_NAME
        value: "distributed-training"
    resourcesPerNode:
      requests:
        nvidia.com/gpu: 8
      limits:
        nvidia.com/gpu: 8
```

---

## 6. Key Takeaways

### Platform Selection Guide

| Scenario | Recommendation |
|----------|----------------|
| Small team, quick start | MLflow standalone |
| Large team, Kubernetes | Kubeflow + MLflow |
| LLM/GenAI focused | MLflow + AI Gateway + vLLM |
| Strict multi-tenancy | Kubeflow Profiles |
| Experiment-heavy research | MLflow Tracking |
| Production ML operations | Kubeflow + MLflow on k0rdent |

### Integration Best Practices

1. **Use MLflow for tracking**: Even with Kubeflow, MLflow provides superior experiment tracking
2. **Kubeflow Trainer v2 for orchestration**: The unified TrainJob API simplifies multi-framework distributed training
3. **Centralize model registry with aliases**: MLflow Registry with `@champion`/`@challenger` aliases as single source of truth
4. **Separate concerns**: Training infrastructure (Kubeflow) vs ML lifecycle (MLflow)
5. **Use k0rdent ServiceTemplates**: Deploy ML platform components declaratively via MultiClusterService (see Section 7)

---

## 7. ML Platforms in k0rdent Enterprise

k0rdent Enterprise provides a curated catalog of ServiceTemplates that deploy ML platform components as managed services across clusters. This eliminates manual Helm chart management and enables consistent, declarative ML platform deployment.

### 7.1 Available ML Platform ServiceTemplates

| Component | ServiceTemplate | Purpose |
|-----------|----------------|---------|
| **MLflow** | `mlflow-1-8-1` | Experiment tracking and model registry |
| **JupyterHub** | `jupyterhub-4-3-2` | Multi-user notebook environment |
| **KServe** | `kserve-v0-15-0` + `kserve-crd-v0-15-0` | Serverless model serving |
| **KubeRay** | `kuberay-operator-1-5-1` | Ray cluster operator for distributed compute |
| **Ray Cluster** | `ray-cluster-1-5-1` | Pre-configured Ray cluster |
| **LeaderWorkerSet** | `lws-0-7-0` | Multi-host inference (e.g., vLLM multi-node) |
| **GPU Operator** | `gpu-operator-25-10-0` | NVIDIA GPU lifecycle management |
| **Milvus** | `milvus-5-0-14` | Vector database for embeddings |
| **Qdrant** | `qdrant-1-15-4` | Alternative vector database |
| **Ollama** | `ollama-1-40-0` | Local LLM inference |
| **Open WebUI** | `open-webui-8-12-3` | Chat interface for LLMs |
| **ClearML** | `clearml-serving-1-6-2` | ML experiment tracking alternative |

### 7.2 Deploying an ML Platform with MultiClusterService

Deploy a complete ML platform across GPU clusters using a single `MultiClusterService`:

```yaml
apiVersion: k0rdent.mirantis.com/v1beta1
kind: MultiClusterService
metadata:
  name: ml-platform
  namespace: kcm-system
spec:
  clusterSelector:
    matchLabels:
      workload-type: ml-training
  serviceSpec:
    services:
      # GPU infrastructure (deploy first)
      - template: gpu-operator-25-10-0
        name: gpu-operator
        namespace: gpu-operator
        priority: 100

      # Experiment tracking
      - template: mlflow-1-8-1
        name: mlflow
        namespace: mlflow

      # Model serving
      - template: kserve-crd-v0-15-0
        name: kserve-crd
        namespace: kserve
        priority: 90
      - template: kserve-v0-15-0
        name: kserve
        namespace: kserve

      # Distributed compute
      - template: kuberay-operator-1-5-1
        name: kuberay
        namespace: kuberay

      # Notebooks
      - template: jupyterhub-4-2-0
        name: jupyterhub
        namespace: jupyterhub
```

> **Architecture note:** ServiceTemplates are Kubernetes CRDs sourced from `ghcr.io/k0rdent/catalog/charts`. The `priority` field resolves competing ownership of the same release. Use MCS `spec.dependsOn` and readiness checks to order prerequisites such as GPU Operator before training frameworks. The `clusterSelector` ensures services deploy only to clusters with matching labels.

### 7.3 ML Platform Architecture on k0rdent

```mermaid
flowchart TB
    subgraph "k0rdent Management Cluster"
        MCS[MultiClusterService<br/>ml-platform]
        CAT[ServiceTemplate Catalog<br/>164+ templates]
    end

    subgraph "GPU Training Cluster"
        GPU[GPU Operator]
        MLFLOW[MLflow Tracking]
        KSERVE[KServe]
        RAY[KubeRay]
        JH[JupyterHub]
    end

    subgraph "Inference Cluster"
        GPU2[GPU Operator]
        KSERVE2[KServe]
        VLLM[vLLM ServingRuntime]
        LWS[LeaderWorkerSet]
    end

    MCS -->|Deploy via labels| GPU & MLFLOW & KSERVE & RAY & JH
    MCS -->|Deploy via labels| GPU2 & KSERVE2 & VLLM & LWS
    CAT -->|Provide charts| MCS
```

---

## References

- [Kubeflow Documentation](https://www.kubeflow.org/docs/)
- [Kubeflow Pipelines](https://www.kubeflow.org/docs/components/pipelines/)
- [Kubeflow Trainer v2 (TrainJob API)](https://www.kubeflow.org/docs/components/trainer/)
- [Kubeflow Training Operator (Legacy)](https://www.kubeflow.org/docs/components/training/)
- [Katib](https://www.kubeflow.org/docs/components/katib/)
- [MLflow Documentation](https://mlflow.org/docs/latest/index.html)
- [MLflow 3.0 Migration Guide](https://mlflow.org/docs/latest/getting-started/intro-quickstart/index.html)
- [MLflow Model Registry Aliases](https://mlflow.org/docs/latest/model-registry.html)
- [MLflow AI Gateway](https://mlflow.org/docs/latest/llms/deployments/index.html)
- [k0rdent Enterprise Documentation](https://docs.k0rdent.io/)
- [k0rdent ServiceTemplate Catalog](https://catalog.k0rdent.io/)
