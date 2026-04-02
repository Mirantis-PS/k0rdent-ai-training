# Lab 5.5 - Service Catalog Blueprints

---

## Lab Navigation

| Track | Tier | Duration |
|-------|------|----------|
| Foundation | Required | 2 hours |

### Week 5 Learning Paths

```
FOUNDATION (Required)                         CHOOSE YOUR PATH
━━━━━━━━━━━━━━━━━━━━                         ━━━━━━━━━━━━━━━━
5.1 ➔ 5.2 ➔ 5.3 ➔ 5.4 ➔ [5.5] ➔ 5.6    ──►  ML Platforms (5.9-5.12)
                          ↑                   Compliance (5.7-5.8)
                     YOU ARE HERE             Advanced (5.13-5.15)
```

| Previous | Current | Next |
|----------|---------|------|
| [Lab 5.4 - Jupyter Notebooks](lab-5.4-jupyter-notebooks.md) | **Lab 5.5 - Service Catalog** | [Lab 5.6 - Troubleshooting GPU](lab-5.6-troubleshooting-gpu.md) |

---

**Duration:** 2 hours
**Type:** Hands-on Technical
**Environment:** GPU Lab

## Objective

Install ServiceTemplates from k0rdent's external catalog and deploy AI/ML services across managed clusters using `MultiClusterService`, understanding how the catalog, templates, and deployment workflow connect.

## Prerequisites

- Completed Labs 5.1-5.4
- k0rdent management cluster access
- At least one workload cluster with GPU nodes
- Understanding of Helm and Kubernetes services

## Background

### How the k0rdent Service Catalog Works

The k0rdent service catalog is **external to the k0rdent deployment** — it is a curated directory of 105+ pre-validated services hosted at [catalog.k0rdent.io](https://catalog.k0rdent.io/). Services are stored as Helm charts in an OCI registry and installed onto the management cluster as `ServiceTemplate` CRDs using a meta-chart called `kgst` (k0rdent Generic Service Template).

```
┌──────────────────────────────────┐
│   External Catalog               │
│   catalog.k0rdent.io             │
│   OCI: ghcr.io/k0rdent/catalog  │
│                                  │
│   105+ services (Helm charts)    │
└────────────┬─────────────────────┘
             │ helm install (kgst)
             ▼
┌──────────────────────────────────┐
│   Management Cluster             │
│   ServiceTemplate CRDs           │
│   (kcm-system namespace)         │
└────────────┬─────────────────────┘
             │ MultiClusterService
             ▼
┌──────────────┐  ┌──────────────┐
│ GPU Cluster A │  │ GPU Cluster B │
│ (HelmRelease) │  │ (HelmRelease) │
└──────────────┘  └──────────────┘
```

### Key Concepts

| Concept | Description |
|---------|-------------|
| **ServiceTemplate** | CRD on the management cluster that wraps a Helm chart reference |
| **kgst** | Meta-chart that creates ServiceTemplate CRDs from the external catalog |
| **MultiClusterService** | CRD that deploys services to clusters matching label selectors |
| **ClusterDeployment.serviceSpec** | Inline service deployment for a specific cluster |
| **ServiceTemplateChain** | Defines allowed upgrade/rollback paths between template versions |
| **values** | Helm values passed as a YAML string (not structured object) |

### AI/ML Services in the Catalog

| Category | ServiceTemplate | Purpose |
|----------|----------------|---------|
| GPU Infrastructure | `gpu-operator-25-10-0` | NVIDIA GPU lifecycle management |
| Model Serving | `kserve-v0-15-0`, `kserve-crd-v0-15-0` | Serverless inference |
| Distributed Compute | `kuberay-operator-1-3-2`, `ray-cluster-1-3-2` | Ray clusters |
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

### Task 1: Explore the External Catalog (15 min)

1. **Browse the Catalog Website**
   - Open [catalog.k0rdent.io](https://catalog.k0rdent.io/) in your browser
   - Browse the available services and note the categories (AI/ML, Monitoring, Networking, etc.)
   - Click on a service (e.g., MLflow) to see its details, version, and installation command

2. **Check Existing ServiceTemplates on the Management Cluster**
   ```bash
   # List all ServiceTemplates currently installed
   kubectl get servicetemplates -n kcm-system

   # View details of a specific template
   kubectl get servicetemplate gpu-operator-25-10-0 -n kcm-system -o yaml
   ```

3. **Understand the ServiceTemplate Structure**

   A ServiceTemplate installed from the catalog looks like this:

   ```yaml
   apiVersion: k0rdent.mirantis.com/v1beta1
   kind: ServiceTemplate
   metadata:
     name: kserve-v0-15-0
     namespace: kcm-system
   spec:
     helm:
       chartSpec:
         chart: kserve
         version: v0.15.0
         interval: 10m0s
         reconcileStrategy: ChartVersion
         sourceRef:
           kind: HelmRepository
           name: k0rdent-catalog
   status:
     valid: true
     chartRef:
       kind: HelmChart
       name: kserve-v0-15-0
       namespace: kcm-system
   ```

   Key fields:
   - `spec.helm.chartSpec.chart` — Helm chart name in the OCI registry
   - `spec.helm.chartSpec.version` — Exact chart version
   - `spec.helm.chartSpec.sourceRef` — Points to the `HelmRepository` source
   - `status.valid` — Whether the template is ready to use

### Task 2: Install ServiceTemplates from the Catalog (20 min)

The catalog uses a meta-chart called **kgst** (k0rdent Generic Service Template). Installing it with a specific chart name/version creates the corresponding `ServiceTemplate` CRD on your management cluster.

1. **Install an ML Platform Stack**

   > **Note:** Verify the OCI chart path before running. Check [catalog.k0rdent.io](https://catalog.k0rdent.io/) for the latest kgst chart URL. If the path below fails, consult the [k0rdent documentation](https://docs.k0rdent.io/) for updated installation instructions.

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

2. **Verify the ServiceTemplates Were Created**
   ```bash
   kubectl get servicetemplates -n kcm-system

   # Expected output includes:
   # kserve-crd-v0-15-0
   # kserve-v0-15-0
   # mlflow-1-7-1
   # kuberay-operator-1-3-2

   # Check that templates are valid
   kubectl get servicetemplates -n kcm-system -o custom-columns='NAME:.metadata.name,VALID:.status.valid'
   ```

3. **Inspect a Template's Chart Reference**
   ```bash
   # See what Helm chart the template wraps
   kubectl get servicetemplate mlflow-1-7-1 -n kcm-system \
     -o jsonpath='{.spec.helm.chartSpec}' | jq .
   ```

> **Note:** The template naming convention converts chart version dots to dashes: chart `kserve:v0.15.0` becomes ServiceTemplate `kserve-v0-15-0`. This ensures Kubernetes-compatible resource names.

### Task 3: Deploy Services via MultiClusterService (30 min)

`MultiClusterService` deploys services to all clusters matching a label selector. This is the primary mechanism for multi-cluster service deployment in k0rdent.

1. **Verify Target Cluster Labels**
   ```bash
   # Check which clusters have the ml-training label
   kubectl get clusterdeployments -A -l workload-type=ml-training
   ```

2. **Create a MultiClusterService for an ML Stack**
   ```yaml
   # Save as ml-platform-mcs.yaml
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
         # GPU Operator (deploy first via higher priority)
         - template: gpu-operator-25-10-0
           name: gpu-operator
           namespace: gpu-operator

         # KServe for model serving
         - template: kserve-crd-v0-15-0
           name: kserve-crd
           namespace: kserve
         - template: kserve-v0-15-0
           name: kserve
           namespace: kserve

         # MLflow for experiment tracking
         - template: mlflow-1-7-1
           name: mlflow
           namespace: mlflow

         # KubeRay for distributed compute
         - template: kuberay-operator-1-3-2
           name: kuberay
           namespace: kuberay
       priority: 100
   ```

   ```bash
   kubectl apply -f ml-platform-mcs.yaml
   ```

3. **Monitor Deployment Status**
   ```bash
   # Watch the MultiClusterService status
   kubectl get multiclusterservice ml-platform -n kcm-system -o yaml

   # Check conditions for each target cluster
   kubectl get multiclusterservice ml-platform -n kcm-system \
     -o jsonpath='{.status.conditions[*].type}'

   # Look for SveltosClusterProfileReady condition
   kubectl get multiclusterservice ml-platform -n kcm-system \
     -o jsonpath='{.status.conditions[?(@.type=="SveltosClusterProfileReady")].status}'
   ```

4. **Verify on a Target Cluster**
   ```bash
   # Switch to a target cluster context (or use kubectl with --context)
   kubectl get pods -n kserve
   kubectl get pods -n mlflow
   kubectl get pods -n kuberay
   kubectl get pods -n gpu-operator
   ```

### Task 4: Customize Services with Helm Values (30 min)

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

### Task 5: Version Management with ServiceTemplateChain (15 min)

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

### Task 6: Single-Cluster Deployment via ClusterDeployment (15 min)

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

### Task 7: Remove a ServiceTemplate (10 min)

1. **Remove a MultiClusterService First**
   ```bash
   # Delete the MCS (this removes services from target clusters)
   kubectl delete multiclusterservice ml-platform -n kcm-system
   ```

2. **Remove a ServiceTemplate from the Catalog**
   ```bash
   # Uninstall the kgst Helm release (removes the ServiceTemplate CRD)
   helm uninstall mlflow -n kcm-system

   # Verify removal
   kubectl get servicetemplate mlflow-1-7-1 -n kcm-system
   # Expected: Error from server (NotFound)
   ```

> **Warning:** Do not remove a ServiceTemplate that is still referenced by an active MultiClusterService or ClusterDeployment. Remove the service references first, then uninstall the template.

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

# Delete ServiceTemplates installed during this lab
kubectl delete servicetemplates -n kcm-system -l installed-by=lab-5.5

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

Proceed to [Lab 5.6 - Troubleshooting GPU Scheduling](lab-5.6-troubleshooting-gpu.md)
