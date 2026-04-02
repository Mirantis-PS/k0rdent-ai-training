# Lab 5.4 - Jupyter Notebook Stack

---

## Lab Navigation

| Track | Tier | Duration |
|-------|------|----------|
| Foundation | Required | 1.5 hours |

### Week 5 Learning Paths

```
FOUNDATION (Required)                         CHOOSE YOUR PATH
━━━━━━━━━━━━━━━━━━━━                         ━━━━━━━━━━━━━━━━
5.1 ➔ 5.2 ➔ 5.3 ➔ [5.4] ➔ 5.5 ➔ 5.6    ──►  ML Platforms (5.9-5.12)
                    ↑                         Compliance (5.7-5.8)
               YOU ARE HERE                   Advanced (5.13-5.15)
```

| Previous | Current | Next |
|----------|---------|------|
| [Lab 5.3 - Vector Database](lab-5.3-vector-database.md) | **Lab 5.4 - Jupyter Notebooks** | [Lab 5.5 - Service Catalog](lab-5.5-service-catalog.md) |

---

**Duration:** 1.5 hours
**Type:** Hands-on Technical
**Environment:** GPU Lab

## Objective

Deploy a GPU-enabled JupyterHub environment on Kubernetes, enabling data scientists and ML engineers to run interactive notebooks with access to GPU resources for model development and experimentation.

## Prerequisites

- Completed Labs 5.1-5.3
- Kubernetes cluster with GPU nodes
- NVIDIA GPU Operator installed
- Persistent storage available

## Background

### JupyterHub Architecture

JupyterHub provides multi-user Jupyter notebook environments:

```
                    ┌─────────────────┐
                    │   JupyterHub    │
                    │   (Proxy/Auth)  │
                    └────────┬────────┘
                             │
         ┌───────────────────┼───────────────────┐
         │                   │                   │
    ┌────▼────┐         ┌────▼────┐         ┌────▼────┐
    │ User A  │         │ User B  │         │ User C  │
    │ Notebook│         │ Notebook│         │ Notebook│
    │ (CPU)   │         │ (GPU)   │         │ (GPU)   │
    └─────────┘         └─────────┘         └─────────┘
```

> **Note:** JupyterHub is a standalone multi-user notebook server. Kubeflow provides an alternative **Notebook Controller** that uses a CRD-based approach (`kubeflow.org/v1 Notebook`) integrated with the Kubeflow platform. This lab teaches the standalone JupyterHub approach, which can also be deployed via k0rdent's `jupyterhub-4-2-0` ServiceTemplate (see Task 7).

### Server Profiles

| Profile | Resources | Use Case |
|---------|-----------|----------|
| CPU Small | 2 CPU, 4GB RAM | Data exploration |
| CPU Medium | 4 CPU, 16GB RAM | Data processing |
| GPU Standard | 4 CPU, 32GB RAM, 1 GPU | Model training |
| GPU Large | 8 CPU, 64GB RAM, 2 GPU | Large model training |

## Lab Environment

**Cluster Requirements:**
- 1+ GPU nodes
- Persistent storage class
- Ingress controller (optional)

## Tasks

### Task 1: Create Namespace and Storage (10 min)

1. **Create Namespace**
   ```bash
   kubectl create namespace jupyter
   ```

2. **Create Shared Storage PVC**
   ```yaml
   # Save as jupyter-shared-pvc.yaml
   apiVersion: v1
   kind: PersistentVolumeClaim
   metadata:
     name: jupyter-shared-data
     namespace: jupyter
   spec:
     accessModes:
       - ReadWriteOnce  # Use ReadWriteMany only if your StorageClass supports RWX (e.g., EFS, NFS)
     resources:
       requests:
         storage: 100Gi
     storageClassName: standard  # Adjust for your cluster (e.g., gp2/gp3 on EKS, default on AKS)
   ```

   ```bash
   kubectl apply -f jupyter-shared-pvc.yaml
   ```

### Task 2: Deploy JupyterHub (30 min)

1. **Add JupyterHub Helm Repository**
   ```bash
   helm repo add jupyterhub https://hub.jupyter.org/helm-chart/
   helm repo update
   ```

2. **Create JupyterHub Configuration**

   > **Note:** The Helm chart 4.x auto-generates the proxy secret token — no manual `openssl rand` step is needed.

   ```yaml
   # Save as jupyterhub-values.yaml
   proxy:
     service:
       type: ClusterIP

   hub:
     config:
       Authenticator:
         admin_users:
           - admin
         allowed_users:
           - mlops
           - datascientist
       DummyAuthenticator:
         password: "training123"
       JupyterHub:
         authenticator_class: dummy

     db:
       type: sqlite-pvc
       pvc:
         storageClassName: standard  # Adjust for your cluster
         storage: 1Gi

   singleuser:
     defaultUrl: "/lab"

     # GPU-enabled default image (from Quay.io — Docker Hub images are frozen)
     image:
       name: quay.io/jupyter/pytorch-notebook
       tag: cuda12-latest

     cpu:
       limit: 4
       guarantee: 1
     memory:
       limit: 16G
       guarantee: 4G

     storage:
       type: dynamic
       capacity: 10Gi
       dynamic:
         storageClass: standard  # Adjust for your cluster

     extraEnv:
       NVIDIA_VISIBLE_DEVICES: "all"
       NVIDIA_DRIVER_CAPABILITIES: "compute,utility"

     profileList:
       - display_name: "CPU - Small (2 CPU, 4GB)"
         description: "For data exploration and light processing"
         default: true
         kubespawner_override:
           cpu_limit: 2
           cpu_guarantee: 0.5
           mem_limit: "4G"
           mem_guarantee: "2G"
           image: "quay.io/jupyter/pytorch-notebook:latest"
           extra_resource_limits: {}

       - display_name: "CPU - Medium (4 CPU, 16GB)"
         description: "For data processing and analysis"
         kubespawner_override:
           cpu_limit: 4
           cpu_guarantee: 1
           mem_limit: "16G"
           mem_guarantee: "8G"
           image: "quay.io/jupyter/pytorch-notebook:latest"
           extra_resource_limits: {}

       - display_name: "GPU - Standard (1 GPU, 32GB RAM)"
         description: "For ML model training"
         kubespawner_override:
           cpu_limit: 4
           cpu_guarantee: 2
           mem_limit: "32G"
           mem_guarantee: "16G"
           image: "quay.io/jupyter/pytorch-notebook:cuda12-latest"
           extra_resource_limits:
             nvidia.com/gpu: "1"
           extra_resource_guarantees:
             nvidia.com/gpu: "1"
           tolerations:
             - key: "nvidia.com/gpu"
               operator: "Exists"
               effect: "NoSchedule"

       - display_name: "GPU - Large (2 GPU, 64GB RAM)"
         description: "For large model training"
         kubespawner_override:
           cpu_limit: 8
           cpu_guarantee: 4
           mem_limit: "64G"
           mem_guarantee: "32G"
           image: "quay.io/jupyter/pytorch-notebook:cuda12-latest"
           extra_resource_limits:
             nvidia.com/gpu: "2"
           extra_resource_guarantees:
             nvidia.com/gpu: "2"
           tolerations:
             - key: "nvidia.com/gpu"
               operator: "Exists"
               effect: "NoSchedule"

   scheduling:
     userScheduler:
       enabled: true
     userPlaceholder:
       enabled: false

   cull:
     enabled: true
     timeout: 3600  # Cull idle notebooks after 1 hour
     every: 300
   ```

   > **Image tags:** The Jupyter Docker Stacks publish images to `quay.io` (Docker Hub images are frozen since October 2023). Tags use the format `cuda12-latest`, `cuda12-<date>`, or `cuda12-<git-sha>` — PyTorch version is NOT included in the tag. For reproducible deployments, pin to a date tag like `cuda12-2026-02-09`. CPU profiles use `latest` (no CUDA) to avoid pulling the larger CUDA image for CPU-only work.

3. **Install JupyterHub**
   ```bash
   helm install jupyterhub jupyterhub/jupyterhub \
     --namespace jupyter \
     --version 4.2.0 \
     --values jupyterhub-values.yaml \
     --wait --timeout 10m
   ```

4. **Verify Deployment**
   ```bash
   kubectl get pods -n jupyter

   # Expected pods:
   # hub-xxx
   # proxy-xxx
   # user-scheduler-xxx (2 replicas)
   ```

### Task 3: Access JupyterHub (10 min)

1. **Port Forward to Hub**
   ```bash
   kubectl port-forward svc/proxy-public -n jupyter 8888:80 &
   ```

2. **Access JupyterHub**
   - Open browser: `http://localhost:8888`
   - Login with: `admin` / `training123`

3. **Select Server Profile**
   - Choose "GPU - Standard" profile
   - Click "Start"
   - Wait for notebook server to spawn

### Task 4: Test GPU Access in Notebook (20 min)

1. **Create New Notebook**
   - Click "File" > "New" > "Notebook"
   - Select "Python 3 (ipykernel)"

2. **Test GPU Detection**
   ```python
   # Cell 1: Check GPU availability
   import torch

   print(f"PyTorch version: {torch.__version__}")
   print(f"CUDA available: {torch.cuda.is_available()}")
   print(f"CUDA version: {torch.version.cuda}")
   print(f"GPU count: {torch.cuda.device_count()}")

   if torch.cuda.is_available():
       print(f"GPU name: {torch.cuda.get_device_name(0)}")
       print(f"GPU memory: {torch.cuda.get_device_properties(0).total_memory / 1e9:.1f} GB")
   ```

3. **Run Simple GPU Computation**
   ```python
   # Cell 2: GPU tensor operations
   import torch
   import time

   # Create tensors on GPU
   device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
   print(f"Using device: {device}")

   # Matrix multiplication benchmark
   size = 4096
   a = torch.randn(size, size, device=device)
   b = torch.randn(size, size, device=device)

   # Warmup
   _ = torch.mm(a, b)
   torch.cuda.synchronize()

   # Benchmark
   start = time.time()
   for _ in range(100):
       _ = torch.mm(a, b)
   torch.cuda.synchronize()
   elapsed = time.time() - start

   print(f"100 matrix multiplications ({size}x{size}): {elapsed:.2f}s")
   print(f"TFLOPS: {2 * size**3 * 100 / elapsed / 1e12:.2f}")
   ```

4. **Test ML Training**
   ```python
   # Cell 3: Simple neural network training
   import torch
   import torch.nn as nn
   import torch.optim as optim
   from torch.utils.data import DataLoader, TensorDataset

   # Create synthetic dataset
   X = torch.randn(10000, 100)
   y = torch.randint(0, 10, (10000,))
   dataset = TensorDataset(X, y)
   dataloader = DataLoader(dataset, batch_size=256, shuffle=True)

   # Simple model
   model = nn.Sequential(
       nn.Linear(100, 256),
       nn.ReLU(),
       nn.Linear(256, 128),
       nn.ReLU(),
       nn.Linear(128, 10)
   ).to(device)

   criterion = nn.CrossEntropyLoss()
   optimizer = optim.Adam(model.parameters())

   # Training loop
   model.train()
   for epoch in range(5):
       total_loss = 0
       for batch_X, batch_y in dataloader:
           batch_X, batch_y = batch_X.to(device), batch_y.to(device)

           optimizer.zero_grad()
           outputs = model(batch_X)
           loss = criterion(outputs, batch_y)
           loss.backward()
           optimizer.step()

           total_loss += loss.item()

       print(f"Epoch {epoch+1}: Loss = {total_loss/len(dataloader):.4f}")

   print("Training complete!")
   ```

### Task 5: Configure Persistent User Storage (15 min)

1. **Update JupyterHub for Shared Storage**
   ```yaml
   # Add to jupyterhub-values.yaml under singleuser:
   singleuser:
     storage:
       type: dynamic
       capacity: 10Gi
       extraVolumes:
         - name: shared-data
           persistentVolumeClaim:
             claimName: jupyter-shared-data
       extraVolumeMounts:
         - name: shared-data
           mountPath: /home/jovyan/shared
           readOnly: false
   ```

2. **Upgrade JupyterHub**
   ```bash
   helm upgrade jupyterhub jupyterhub/jupyterhub \
     --namespace jupyter \
     --version 4.2.0 \
     --values jupyterhub-values.yaml \
     --wait
   ```

3. **Test Shared Storage**
   - Stop and restart your notebook server
   - Navigate to `/home/jovyan/shared`
   - Create a file - it persists across server restarts

### Task 6: Monitor Resource Usage (10 min)

1. **Check User Pods**
   ```bash
   # List user notebook pods
   kubectl get pods -n jupyter -l component=singleuser-server

   # View resource usage
   kubectl top pods -n jupyter
   ```

2. **Check GPU Allocation**
   ```bash
   # View GPU usage in a user pod (replace POD_NAME with actual pod name)
   # First, get the pod name:
   kubectl get pods -n jupyter -l component=singleuser-server

   # Then exec into it (example: jupyter-admin becomes pod jupyter-admin)
   POD_NAME=$(kubectl get pods -n jupyter -l component=singleuser-server -o jsonpath='{.items[0].metadata.name}')
   kubectl exec -n jupyter $POD_NAME -- nvidia-smi
   ```

3. **View Hub Metrics**
   ```bash
   # Port forward to hub
   kubectl port-forward svc/hub -n jupyter 8081:8081 &

   # Access metrics
   curl http://localhost:8081/hub/metrics
   ```

### Task 7: Deploy via k0rdent Enterprise (15 min)

In a k0rdent-managed environment, JupyterHub can be deployed declaratively across clusters using the `jupyterhub-4-2-0` ServiceTemplate from the k0rdent catalog.

> **Note:** The `jupyterhub-4-2-0` ServiceTemplate may not be pre-installed in every k0rdent catalog. Run the verification command below first. If the template is not listed, skip the remainder of Task 7 -- it requires a catalog entry that your environment does not include.

1. **Verify ServiceTemplate Availability**
   ```bash
   # On the management cluster
   kubectl get servicetemplates -n kcm-system | grep jupyter
   # Expected: jupyterhub-4-2-0
   # If no results, skip the rest of Task 7
   ```

2. **Deploy JupyterHub via MultiClusterService**
   ```yaml
   # Save as jupyter-mcs.yaml
   apiVersion: k0rdent.mirantis.com/v1beta1
   kind: MultiClusterService
   metadata:
     name: jupyter-notebooks
     namespace: kcm-system
   spec:
     clusterSelector:
       matchLabels:
         workload-type: ml-training
     serviceSpec:
       services:
         - template: jupyterhub-4-2-0
           name: jupyterhub
           namespace: jupyter
   ```

   ```bash
   kubectl apply -f jupyter-mcs.yaml
   ```

3. **Verify Deployment**
   ```bash
   # Check MultiClusterService status
   kubectl get multiclusterservice jupyter-notebooks -n kcm-system

   # On the target cluster, verify JupyterHub pods
   kubectl get pods -n jupyter
   ```

> **When to use which approach:** Use the manual Helm deployment (Tasks 2-6) for customized single-cluster setups with fine-grained profile control. Use the k0rdent `MultiClusterService` approach for consistent, declarative deployment across multiple GPU clusters where the ServiceTemplate's default configuration is sufficient.

---

## Optional: Ingress Configuration

```yaml
# Save as jupyter-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: jupyterhub
  namespace: jupyter
  annotations:
    nginx.ingress.kubernetes.io/proxy-body-size: "0"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "3600"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "3600"
spec:
  ingressClassName: nginx
  rules:
    - host: jupyter.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: proxy-public
                port:
                  number: 80
```

```bash
kubectl apply -f jupyter-ingress.yaml
```

## Deliverables

- [ ] **Screenshot** of JupyterHub login page
- [ ] **Screenshot** of profile selection showing GPU options
- [ ] **Screenshot** of notebook showing GPU detection output
- [ ] **Training output** from the ML test
- [ ] **Configuration YAML** with notes
- [ ] **MultiClusterService YAML** for k0rdent deployment (Task 7)

## Verification Checklist

- [ ] JupyterHub deployed and accessible
- [ ] Can login with test credentials
- [ ] Server profiles include GPU options
- [ ] GPU detected in notebook
- [ ] PyTorch GPU operations work
- [ ] Persistent storage working
- [ ] k0rdent MultiClusterService deployed (Task 7)

## Troubleshooting

### User Pod Stuck in Pending

**Check GPU availability:**
```bash
kubectl describe pod -n jupyter jupyter-<username>
kubectl get nodes -o custom-columns='NAME:.metadata.name,GPUs:.status.allocatable.nvidia\.com/gpu'
```

### GPU Not Detected in Notebook

**Check tolerations in spawned pod:**
```bash
kubectl get pod -n jupyter jupyter-<username> -o yaml | grep -A10 tolerations
```

**Verify NVIDIA runtime:**
```bash
kubectl exec -n jupyter jupyter-<username> -- nvidia-smi
```

### Out of Memory

**Increase memory limits** in profile configuration or choose larger profile.

### Notebook Server Won't Start

**Check hub logs:**
```bash
kubectl logs -n jupyter -l component=hub
```

## Cleanup

Remove lab resources:

```bash
kubectl delete namespace jupyter --wait=false
kubectl delete pvc -n jupyter --all

# Verify
kubectl get pods -n jupyter
```

> **Cost reminder:** GPU workloads consume resources even when idle. See the [labs README cleanup guide](README.md#cleanup).

## Key Takeaways

1. **JupyterHub enables self-service** GPU access for data scientists
2. **Profile system provides resource governance** — users choose appropriate tier
3. **Persistent storage preserves work** across sessions
4. **Idle culling prevents resource waste** — configure based on usage patterns
5. **GPU tolerations are critical** for scheduling on GPU nodes
6. **Always set resource limits** to prevent runaway notebooks
7. **Monitor usage patterns** to optimize profile offerings
8. **k0rdent ServiceTemplates** enable declarative JupyterHub deployment across clusters via `jupyterhub-4-2-0`
9. **Kubeflow Notebooks** is an alternative CRD-based approach for platform-integrated notebook management (see Theory 5.5)

## Next Lab

Proceed to [Lab 5.5 - Service Catalog Blueprints](lab-5.5-service-catalog.md)
