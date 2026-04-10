# Lab 5.2 - Service Catalog Blueprints

---

## Lab Navigation

| Track | Tier | Duration |
|-------|------|----------|
| Foundation | Required | 45 min |

### Week 5 Learning Paths

```
FOUNDATION (Required)                              CHOOSE YOUR PATH
━━━━━━━━━━━━━━━━━━━━                              ━━━━━━━━━━━━━━━━
5.1 ➔ [5.2] ➔ 5.3 ➔ 5.4 ➔ 5.5 ➔ 5.6 ➔ 5.7 ➔ 5.8  ──►  ML Platforms (5.9-5.10)
        ↑                                                  Compliance (5.11-5.12)
   YOU ARE HERE                                            Advanced (5.13-5.16)
```

| Previous | Current | Next |
|----------|---------|------|
| [Lab 5.1 - GPU Cluster Setup](lab-5.1-gpu-cluster-setup.md) | **Lab 5.2 - Service Catalog** | [Lab 5.3 - KAI Scheduler](lab-5.3-kai-scheduler.md) |

---

## Table of Contents

- [Objective](#objective)
- [Prerequisites](#prerequisites)
- [AI/ML Services in the Catalog](#aiml-services-in-the-catalog)
- [Tasks](#tasks)
  - [Task 1: Install AI/ML ServiceTemplates](#task-1-install-aiml-servicetemplates-10-min)
  - [Task 2: Customize Services with Helm Values](#task-2-customize-services-with-helm-values-15-min)
  - [Task 3: Version Management with ServiceTemplateChain](#task-3-version-management-with-servicetemplatechain-10-min)
  - [Task 4: Single-Cluster Deployment via ClusterDeployment](#task-4-single-cluster-deployment-via-clusterdeployment-10-min)
- [Deliverables](#deliverables)
- [Verification Checklist](#verification-checklist)
- [Troubleshooting](#troubleshooting)
- [Cleanup](#cleanup)
- [Key Takeaways](#key-takeaways)
- [Next Lab](#next-lab)

**Duration:** 45 minutes
**Type:** Hands-on Technical
**Environment:** GPU Lab

## Objective

Deploy AI/ML services from the k0rdent catalog to GPU clusters, building on the ServiceTemplate and MultiClusterService skills from [Lab 1.7](../../week-1-foundations/labs/lab-1.7-multicluster-services.md). This lab focuses on what's new for AI workloads: AI-specific ServiceTemplates, Helm values customization, version management with ServiceTemplateChain, and single-cluster deployment via ClusterDeployment serviceSpec.

## Prerequisites

- Completed Lab 5.1 (GPU cluster provisioned)
- Completed Lab 1.7 (ServiceTemplate and MultiClusterService fundamentals)
- k0rdent management cluster access

> **Recap from Lab 1.7:** You already know how to browse [catalog.k0rdent.io](https://catalog.k0rdent.io/), install ServiceTemplates via `helm upgrade --install ... oci://ghcr.io/k0rdent/catalog/charts/kgst`, label clusters for targeting, and deploy via MultiClusterService. This lab skips those basics and focuses on AI-specific patterns.

### AI/ML Services in the Catalog

| Category | ServiceTemplate | Purpose |
|----------|----------------|---------|
| GPU Infrastructure | `gpu-operator-25-10-0` | NVIDIA GPU lifecycle management |
| Model Serving | `kserve-v0-15-0`, `kserve-crd-v0-15-0` | Serverless inference |
| Distributed Compute | `kuberay-operator-1-3-2` | Ray operator (manages RayCluster CRDs) |
| Multi-host Inference | `lws-0-7-0` | LeaderWorkerSet for vLLM multi-node |
| Experiment Tracking | `mlflow-1-7-1` | MLflow tracking and registry |
| Notebooks | `jupyterhub-4-2-0` | Multi-user Jupyter environments |
| Vector Databases | `milvus-5-0-1`, `qdrant-1-15-4` | Embedding storage |
| LLM Inference | `ollama-1-40-0` | Local LLM runtime |
| Chat Interface | `open-webui-8-12-3` | UI for LLM interaction |
| ML Tracking | `clearml-serving-1-6-2` | ClearML platform |

## Lab Environment

**Cluster Requirements:**
- k0rdent management cluster access
- At least one workload cluster labeled `workload-type: ml-training`
- Helm CLI installed locally

## Tasks

### Task 1: Install AI/ML ServiceTemplates (10 min)

Using the same `kgst` meta-chart pattern from Lab 1.7, install an AI/ML service stack:

```bash
# Install KServe CRDs (required before KServe itself)
helm upgrade --install kserve-crd \
  oci://ghcr.io/k0rdent/catalog/charts/kgst \
  --set "chart=kserve-crd:v0.15.0" \
  -n kcm-system

# Install KServe
helm upgrade --install kserve \
  oci://ghcr.io/k0rdent/catalog/charts/kgst \
  --set "chart=kserve:v0.15.0" \
  -n kcm-system

# Install MLflow
helm upgrade --install mlflow \
  oci://ghcr.io/k0rdent/catalog/charts/kgst \
  --set "chart=mlflow:1.7.1" \
  -n kcm-system

# Install KubeRay operator
helm upgrade --install kuberay-operator \
  oci://ghcr.io/k0rdent/catalog/charts/kgst \
  --set "chart=kuberay-operator:1.3.2" \
  -n kcm-system
```

Verify all templates are valid:

```bash
kubectl get servicetemplates -n kcm-system -o custom-columns='NAME:.metadata.name,VALID:.status.valid'
```

### Task 2: Customize Services with Helm Values (15 min)

The `values` field in service specs is a **string** (YAML-as-string using the `|` block scalar), not a structured object. This allows Helm templating within the values.

1. **Deploy MLflow with Custom Configuration**
   ```yaml
   # Save as mlflow-custom-mcs.yaml
   apiVersion: k0rdent.mirantis.com/v1beta1
   kind: MultiClusterService
   metadata:
     name: mlflow-custom
     namespace: kcm-system
   spec:
     clusterSelector:
       matchLabels:
         workload-type: ml-training
     serviceSpec:
       services:
         - template: mlflow-1-7-1
           name: mlflow
           namespace: mlflow
           values: |
             mlflow:
               tracking:
                 backendStoreUri: postgresql://mlflow:password@postgres:5432/mlflow
                 defaultArtifactRoot: s3://mlflow-artifacts/
               service:
                 type: ClusterIP
                 port: 5000
       priority: 100
   ```

   ```bash
   kubectl apply -f mlflow-custom-mcs.yaml
   ```

2. **Use valuesFrom for Secrets**

   For sensitive values (database credentials, API tokens), use `valuesFrom` to reference Kubernetes Secrets:

   ```bash
   # Create a Secret with Helm values (use --from-file for reliable multi-line YAML)
   cat <<EOF > /tmp/mlflow-custom-values.yaml
   mlflow:
     tracking:
       backendStoreUri: postgresql://mlflow:realpassword@postgresql.mlflow:5432/mlflow
       defaultArtifactRoot: s3://mlflow-artifacts/
   EOF
   kubectl create secret generic mlflow-db-values \
     -n kcm-system \
     --from-file=values=/tmp/mlflow-custom-values.yaml
   ```

   ```yaml
   # In MultiClusterService spec:
   services:
     - template: mlflow-1-7-1
       name: mlflow
       namespace: mlflow
       valuesFrom:
         - kind: Secret
           name: mlflow-db-values
           namespace: kcm-system
           optional: false
   ```

3. **Deploy KServe with Custom Serving Mode**
   ```yaml
   # Save as kserve-custom-mcs.yaml
   apiVersion: k0rdent.mirantis.com/v1beta1
   kind: MultiClusterService
   metadata:
     name: kserve-stack
     namespace: kcm-system
   spec:
     clusterSelector:
       matchLabels:
         workload-type: ml-inference
     serviceSpec:
       services:
         - template: kserve-crd-v0-15-0
           name: kserve-crd
           namespace: kserve
         - template: kserve-v0-15-0
           name: kserve
           namespace: kserve
           values: |
             kserve:
               controller:
                 deploymentMode: RawDeployment
               modelmesh:
                 enabled: false
       priority: 100
   ```

   ```bash
   kubectl apply -f kserve-custom-mcs.yaml
   ```

4. **Verify Custom Values Were Applied**
   ```bash
   # On the target cluster, check the HelmRelease created by k0rdent
   kubectl get helmreleases -A

   # Check the values on the HelmRelease
   kubectl get helmrelease mlflow -n mlflow -o jsonpath='{.spec.values}' | jq .
   ```

### Task 3: Version Management with ServiceTemplateChain (10 min)

`ServiceTemplateChain` defines allowed upgrade and rollback paths between ServiceTemplate versions. Once created, the chain spec is **immutable**.

1. **Create a ServiceTemplateChain**

   > **Note:** This chain references `kserve-v0-14-1`, which was not installed in Task 2. For the chain to work, both template versions must exist on the management cluster. Install the older version first:
   >
   > ```bash
   > helm upgrade --install kserve-old \
   >   oci://ghcr.io/k0rdent/catalog/charts/kgst \
   >   --set "chart=kserve:v0.14.1" \
   >   -n kcm-system
   > ```
   >
   > Alternatively, you can modify the chain below to only reference templates you already installed (e.g., use `kserve-crd-v0-15-0` and `kserve-v0-15-0`).

   ```yaml
   # Save as kserve-chain.yaml
   apiVersion: k0rdent.mirantis.com/v1beta1
   kind: ServiceTemplateChain
   metadata:
     name: kserve-chain
     namespace: kcm-system
   spec:
     supportedTemplates:
       - name: kserve-v0-14-1
         availableUpgrades:
           - name: kserve-v0-15-0
       - name: kserve-v0-15-0
   ```

   ```bash
   kubectl apply -f kserve-chain.yaml
   ```

   This defines: `kserve-v0-14-1` can upgrade to `kserve-v0-15-0`. The latest version has no further upgrades.

2. **Use the Chain in a MultiClusterService**
   ```yaml
   services:
     - template: kserve-v0-14-1
       templateChain: kserve-chain
       name: kserve
       namespace: kserve
   ```

   To upgrade, change the template reference to the new version:
   ```yaml
   services:
     - template: kserve-v0-15-0    # upgraded
       templateChain: kserve-chain
       name: kserve
       namespace: kserve
   ```

3. **Understand Version Pinning Strategy**

   | Environment | Strategy | Example |
   |-------------|----------|---------|
   | Development | Use latest available template | `kserve-v0-15-0` (change freely) |
   | Staging | Pin version + chain for controlled upgrades | `templateChain: kserve-chain` |
   | Production | Pin exact version, manual upgrade via chain | Change template ref only after testing |

### Task 4: Single-Cluster Deployment via ClusterDeployment (10 min)

For deploying services to a **specific cluster** (rather than all clusters matching a selector), use `ClusterDeployment.spec.serviceSpec`:

1. **Patch an Existing ClusterDeployment**
   ```bash
   # Add services to an existing cluster
   kubectl patch clusterdeployment my-gpu-cluster -n kcm-system --type='merge' -p '
   {
     "spec": {
       "serviceSpec": {
         "services": [
           {
             "template": "gpu-operator-25-10-0",
             "name": "gpu-operator",
             "namespace": "gpu-operator"
           },
           {
             "template": "mlflow-1-7-1",
             "name": "mlflow",
             "namespace": "mlflow"
           }
         ],
         "priority": 100
       }
     }
   }'
   ```

2. **Verify Service Deployment**
   ```bash
   # Check the ClusterDeployment status
   kubectl get clusterdeployment my-gpu-cluster -n kcm-system -o yaml

   # Look for service-related conditions
   kubectl get clusterdeployment my-gpu-cluster -n kcm-system \
     -o jsonpath='{.status.conditions[*].type}'
   ```

> **When to use which approach:**
> - **MultiClusterService** — Deploy the same services to all clusters matching labels (e.g., all GPU clusters get GPU Operator + KServe)
> - **ClusterDeployment.serviceSpec** — Deploy services to one specific cluster (e.g., only the staging cluster gets MLflow)

> **Removing ServiceTemplates:** Always delete MultiClusterService/ClusterDeployment service references first, then uninstall the kgst Helm release (e.g., `helm uninstall mlflow -n kcm-system`). See the [Cleanup](#cleanup) section.

## Deliverables

- [ ] **Screenshot** of catalog website showing available AI/ML services
- [ ] **Output** of `kubectl get servicetemplates -n kcm-system` showing installed templates
- [ ] **MultiClusterService YAML** with custom Helm values
- [ ] **ServiceTemplateChain YAML** demonstrating version management
- [ ] **Notes** on the difference between `MultiClusterService` and `ClusterDeployment.serviceSpec`

## Verification Checklist

- [ ] ServiceTemplates installed from catalog via `kgst` meta-chart
- [ ] Templates show `status.valid: true`
- [ ] MultiClusterService created and deploying to target clusters
- [ ] Custom Helm values applied via `values: |` string field
- [ ] ServiceTemplateChain created for version management
- [ ] Understand `MultiClusterService` vs `ClusterDeployment.serviceSpec` patterns

## Troubleshooting

### ServiceTemplate Shows `valid: false`

**Check the HelmRepository source:**
```bash
kubectl get helmrepository k0rdent-catalog -n kcm-system -o yaml
```

**Check FluxCD HelmChart reconciliation:**
```bash
kubectl get helmcharts -n kcm-system
kubectl describe helmchart <template-name> -n kcm-system
```

### MultiClusterService Not Deploying

**Check conditions:**
```bash
kubectl describe multiclusterservice <name> -n kcm-system
```

**Check if target clusters match the selector:**
```bash
kubectl get clusterdeployments -A --show-labels
```

**Check Sveltos ClusterProfile (k0rdent uses Sveltos for multi-cluster orchestration):**
```bash
kubectl get clusterprofiles -A
```

### Helm Values Not Applied

**Verify values format** — the `values` field must be a YAML string, not a structured object:
```yaml
# CORRECT — string with block scalar
values: |
  mlflow:
    tracking:
      port: 5000

# WRONG — structured object (will fail)
values:
  mlflow:
    tracking:
      port: 5000
```

### Conflict Between MultiClusterService and ClusterDeployment

If both a `MultiClusterService` and a `ClusterDeployment.serviceSpec` manage the same Helm release on the same cluster, the resource with higher `priority` wins. Check status for conflict messages:
```bash
kubectl get multiclusterservice <name> -n kcm-system \
  -o jsonpath='{.status.services[*].conditions}'
```

## Cleanup

Remove lab resources:

```bash
# Delete MultiClusterServices
kubectl delete multiclusterservice -n kcm-system --all

# Delete ServiceTemplateChains
kubectl delete servicetemplatechains -n kcm-system --all

# Delete ServiceTemplates installed during this lab (by uninstalling the Helm releases)
helm uninstall kserve-crd kserve mlflow kuberay-operator -n kcm-system 2>/dev/null
# If you also installed the old KServe version in Task 5:
helm uninstall kserve-old -n kcm-system 2>/dev/null

# Verify
kubectl get multiclusterservice,servicetemplatechains -n kcm-system
```

## Key Takeaways

1. **The catalog is external** — ServiceTemplates must be installed from `catalog.k0rdent.io` using the `kgst` meta-chart before they can be deployed
2. **ServiceTemplates wrap Helm charts** — they are CRDs that reference charts in OCI registries, not self-contained packages
3. **MultiClusterService is the primary deployment mechanism** — it targets clusters by label and deploys services declaratively
4. **Values are strings, not objects** — use the `|` block scalar for Helm values to enable templating
5. **ServiceTemplateChain controls upgrades** — define allowed version transitions to prevent accidental downgrades
6. **Priority resolves conflicts** — when multiple resources manage the same Helm release, highest priority wins
7. **Use ClusterDeployment.serviceSpec for single clusters** — targeted deployment without label selectors

## Next Lab

Proceed to [Lab 5.3 - KAI Scheduler](lab-5.3-kai-scheduler.md)
