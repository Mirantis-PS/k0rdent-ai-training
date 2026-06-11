# Lab 1.6: Deploy k0rdent Observability & FinOps (KOF)

**Duration:** 3 hours (active: ~2h, waiting for Helm installs: ~1h)
**Type:** Hands-on Lab

## Table of Contents

- [Objectives](#objectives)
- [Prerequisites](#prerequisites)
- [Resuming This Lab](#resuming-this-lab)
- [Lab Path](#lab-path)
- [What is KOF?](#what-is-kof)
- [Part 1: Understanding KOF Architecture (~5 min)](#part-1-understanding-kof-architecture-5-min)
  - [Three-Tier Architecture](#three-tier-architecture)
  - [For This Lab](#for-this-lab)
- [Part 2: Install KOF Components (~30 min)](#part-2-install-kof-components-30-min)
  - [Step 1: Verify Prerequisites](#step-1-verify-prerequisites)
  - [Step 2: Install KOF Operators](#step-2-install-kof-operators)
  - [Step 3: Install KOF Mothership](#step-3-install-kof-mothership)
  - [Step 4: Install KOF Storage](#step-4-install-kof-storage)
  - [Step 5: Install KOF Collectors](#step-5-install-kof-collectors)
  - [Step 6: Verify Complete Installation](#step-6-verify-complete-installation)
  - [Troubleshooting Installation](#troubleshooting-installation)
- [Part 3: Deploy KOF on Child Clusters (~20 min)](#part-3-deploy-kof-on-child-clusters-20-min)
  - [Understanding Child Cluster Telemetry Flow](#understanding-child-cluster-telemetry-flow)
  - [Option 1: Automatic Deployment via Labels (Recommended)](#option-1-automatic-deployment-via-labels-recommended)
  - [Option 2: Regional Architecture (Production)](#option-2-regional-architecture-production)
  - [Option 3: Custom Endpoints via Annotations](#option-3-custom-endpoints-via-annotations)
  - [Option 4: Manual Helm Install (Development/Testing)](#option-4-manual-helm-install-developmenttesting)
  - [Networking Requirements](#networking-requirements)
  - [Verify Child Cluster Collectors](#verify-child-cluster-collectors)
  - [Component Summary](#component-summary)
- [Part 4: Access Grafana Dashboards (~15 min)](#part-4-access-grafana-dashboards-15-min)
  - [Get Grafana Credentials](#get-grafana-credentials)
  - [Port-Forward Grafana](#port-forward-grafana)
  - [Create SSH Tunnel (if needed)](#create-ssh-tunnel-if-needed)
  - [Access Grafana](#access-grafana)
  - [Explore Pre-built Dashboards](#explore-pre-built-dashboards)
  - [Exercise: Explore Dashboards](#exercise-explore-dashboards)
- [Part 5: Verify Telemetry Flow (~10 min)](#part-5-verify-telemetry-flow-10-min)
  - [Check Metrics in VictoriaMetrics](#check-metrics-in-victoriametrics)
  - [Check Logs in VictoriaLogs](#check-logs-in-victorialogs)
  - [Verify OpenCost Data](#verify-opencost-data)
- [Part 6: Create Custom Dashboard (Optional) (~10 min)](#part-6-create-custom-dashboard-optional-10-min)
  - [Create Dashboard via Grafana UI](#create-dashboard-via-grafana-ui)
  - [Or Import via JSON](#or-import-via-json)
- [Part 7: Understanding KOF Components (~5 min)](#part-7-understanding-kof-components-5-min)
  - [Component Deep Dive](#component-deep-dive)
  - [OpenTelemetry Collectors](#opentelemetry-collectors)
- [Validation Checklist](#validation-checklist)
- [Summary](#summary)
- [Key Concepts](#key-concepts)
- [Troubleshooting](#troubleshooting)
  - [Grafana Not Loading](#grafana-not-loading)
  - [No Metrics in Dashboards](#no-metrics-in-dashboards)
  - [PVC Pending](#pvc-pending)
  - [Namespace Stuck Terminating (During Reinstall)](#namespace-stuck-terminating-during-reinstall)
- [Next Lab](#next-lab)

## Objectives

In this lab, you will:
- Understand KOF architecture and components
- Deploy KOF operators on the management cluster
- Install the KOF mothership stack (Grafana, VictoriaMetrics, etc.)
- Configure managed clusters for telemetry collection
- Access Grafana dashboards and explore observability data

## Prerequisites

- Completed Labs 1.1-1.5
- Basic understanding of monitoring concepts

> **Keep your managed cluster running!** This lab requires the managed cluster from Lab 1.5 to be active. Do **not** run the Lab 1.5 cleanup steps until you have completed Labs 1.6 and 1.7.

## Resuming This Lab

If your SSH session dropped or you're returning the next day:

```bash
cd lab-infrastructure
./scripts/lab-connect.sh <your-engineer-id>
kubectl get nodes && kubectl get pods -n kcm-system

# Verify managed cluster is still running
kubectl get clusterdeployment -n kcm-system

# Check KOF namespace (if you already started KOF installation)
kubectl get pods -n kof
```

---

## Lab Path

This is the longest lab in Week 1. Choose your path based on available time:

| Path | Parts | Duration | What You Learn |
|------|-------|----------|----------------|
| **Core** (recommended) | 1-4, 7 | ~2h | KOF installation, Grafana access, dashboard basics |
| **Full** | 1-7 | ~3h | Above + child cluster deployment, custom dashboards, troubleshooting |

> Parts 5-6 cover child cluster KOF deployment options and advanced networking -- these are valuable but can be revisited later.

## What is KOF?

**KOF (k0rdent Observability & FinOps)** is a unified observability and cost management solution for k0rdent-managed infrastructure. It provides:

| Component | Purpose |
|-----------|---------|
| **VictoriaMetrics** | Time-series metrics storage (vmcluster, vmauth) |
| **VictoriaLogs** | Scalable log aggregation |
| **Jaeger + OpenTelemetry** | Distributed tracing |
| **OpenCost** | Cost allocation and FinOps |
| **Grafana** | Dashboards and visualization |
| **Promxy** | Cross-cluster metric queries |

## Part 1: Understanding KOF Architecture (~5 min)

### Three-Tier Architecture

KOF uses a hierarchical architecture:

```
+--------------------------------------------------+
|              Management Cluster                   |
|  +--------------------------------------------+  |
|  |  KOF Mothership                            |  |
|  |  - Grafana (dashboards)                    |  |
|  |  - Promxy (metric aggregation)             |  |
|  |  - KOF Operators                           |  |
|  +--------------------------------------------+  |
+--------------------------------------------------+
           |                    |
           v                    v
+-------------------+  +-------------------+
| Regional Cluster  |  | Regional Cluster  |
| (optional)        |  | (optional)        |
| - VictoriaMetrics |  | - VictoriaMetrics |
| - VictoriaLogs    |  | - VictoriaLogs    |
| - Jaeger          |  | - Jaeger          |
+-------------------+  +-------------------+
           |                    |
           v                    v
+-------------------+  +-------------------+
| Child Cluster 1   |  | Child Cluster 2   |
| - OpenTelemetry   |  | - OpenTelemetry   |
| - OpenCost        |  | - OpenCost        |
+-------------------+  +-------------------+
```

### For This Lab

We'll deploy the "Management to Management" configuration, where the management cluster stores its own telemetry data:

- **Management Cluster**: Full KOF stack with all four charts
  - kof-operators (Grafana + OpenTelemetry operators)
  - kof-mothership (Grafana, VictoriaMetrics operator, Promxy)
  - kof-storage (VictoriaLogs, Jaeger for local storage)
  - kof-collectors (OpenTelemetry, kube-state-metrics, node-exporter)

This is the recommended starting point for learning KOF. For production multi-cluster setups, you would deploy kof-child on managed clusters to send telemetry to the management cluster.

## Part 2: Install KOF Components (~30 min)

KOF requires **four Helm charts** installed in order:

| Chart | Purpose |
|-------|---------|
| **kof-operators** | Grafana and OpenTelemetry operators (CRDs) |
| **kof-mothership** | Core components: Grafana, VictoriaMetrics operator, Promxy |
| **kof-storage** | Storage: VictoriaLogs cluster, Jaeger, PromxyServerGroup |
| **kof-collectors** | Metrics collection: OpenTelemetry, kube-state-metrics, node-exporter |

> **Why four charts, and why this order?** Each chart depends on the one before it. `kof-operators` goes first because it installs the CRDs and operators (Grafana, OpenTelemetry) that everything else is built from. `kof-mothership` comes next: its Grafana and VictoriaMetrics components are custom resources that those operators reconcile. `kof-storage` then adds the log/trace storage backends. `kof-collectors` goes last because collectors are agents -- they need a running storage target to ship telemetry to. Installing out of order either fails fast (missing CRDs) or silently drops data (collectors with nowhere to write).

> **Why KOF 1.6.0 and not the latest release?** This lab pins the **newest KOF version that still uses this manual four-chart installation flow**. KOF 1.7 disabled Grafana by default, and KOF 1.8+ replaced this flow with a single `kof` umbrella chart that sequences components (including a separate victoria-metrics-operator release) through FluxCD HelmReleases. Running this lab's commands against KOF >= 1.7 fails -- e.g., `kof-mothership` 1.8+ aborts with `no matches for kind "VMCluster"` because the VictoriaMetrics operator and its CRDs no longer ship inside the mothership chart. Do not bump these pins without reworking the whole lab to the umbrella-chart flow.

### Step 1: Verify Prerequisites

```bash
# Verify helm is available
helm version

# Check storage class exists
kubectl get storageclass

# If no storage class exists, install local-path-provisioner:
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml
kubectl wait --for=condition=available deployment/local-path-provisioner -n local-path-storage --timeout=60s
kubectl get storageclass  # Should now show 'local-path'
```

### Step 2: Install KOF Operators

> **Note:** Each Helm install in this section uses `--wait`, which blocks until all pods are Ready. On resource-constrained nodes, installs may take longer than expected. If a `--wait` times out, check pod status with `kubectl get pods -n kof` -- if pods are still starting (ContainerCreating/Init), simply re-run the same `helm upgrade` command.

```bash
# Install KOF operators (Grafana + OpenTelemetry operators)
helm upgrade -i --reset-values --wait --create-namespace -n kof kof-operators \
  oci://ghcr.io/k0rdent/kof/charts/kof-operators \
  --version 1.6.0

# Verify operators are running
kubectl get pods -n kof
# Expected: kof-operators-grafana-operator-xxx, kof-operators-opentelemetry-operator-xxx
```

### Step 3: Install KOF Mothership

```bash
# Create mothership configuration
# NOTE: installTemplates: true creates ServiceTemplates for use with MultiClusterService.
# If ServiceTemplate creation fails (apiVersion mismatch), the mothership itself still
# installs correctly -- you can set installTemplates: false and create templates manually.
cat << 'EOF' > /tmp/mothership-values.yaml
kcm:
  installTemplates: true
global:
  storageClass: "local-path"
EOF

# Install the mothership (Grafana, VictoriaMetrics operator, Promxy)
helm upgrade -i --reset-values --wait -n kof kof-mothership \
  -f /tmp/mothership-values.yaml \
  oci://ghcr.io/k0rdent/kof/charts/kof-mothership \
  --version 1.6.0 \
  --timeout 10m

# Verify mothership pods
kubectl get pods -n kof
# Expected: grafana-vm-deployment-xxx, kof-mothership-promxy-xxx, vminsert-cluster-xxx, etc.
```

### Step 4: Install KOF Storage

```bash
# Create storage configuration
# (Disables components already provided by mothership)
cat << 'EOF' > /tmp/storage-values.yaml
grafana:
  enabled: false
  security:
    create_secret: false
victoria-metrics-operator:
  enabled: false
victoriametrics:
  enabled: false
promxy:
  # Promxy provides unified Prometheus-compatible query interface across VictoriaMetrics clusters.
  # The CRD (PromxyServerGroup) is managed by kof-storage; the deployment runs in kof-mothership.
  enabled: true
victoria-logs-cluster:
  vlstorage:
    persistentVolume:
      storageClassName: local-path
EOF

# Install storage (VictoriaLogs, Jaeger)
helm upgrade -i --reset-values --wait -n kof kof-storage \
  -f /tmp/storage-values.yaml \
  oci://ghcr.io/k0rdent/kof/charts/kof-storage \
  --version 1.6.0 \
  --timeout 10m
```

### Step 5: Install KOF Collectors

```bash
# Create collectors configuration
# The "collectors:" resource overrides right-size the OpenTelemetry collectors
# for this single-node training cluster: k0rdent Enterprise 1.3.x's provider
# fleet already allocates ~98% of the t3.xlarge's CPU requests, and at the
# default 100m-per-collector sizing the daemon collectors stay Pending with
# "Insufficient cpu".
cat << 'EOF' > /tmp/collectors-values.yaml
kcm:
  monitoring: true
opentelemetry-kube-stack:
  clusterName: mothership
  collectors:
    cluster:
      resources:
        requests:
          cpu: 50m
    target-allocator:
      resources:
        requests:
          cpu: 50m
    daemon:
      resources:
        requests:
          cpu: 50m
  defaultCRConfig:
    config:
      processors:
        resource/k8sclustername:
          attributes:
            - action: insert
              key: k8s.cluster.name
              value: mothership
            - action: insert
              key: k8s.cluster.namespace
              value: kcm-system
      exporters:
        prometheusremotewrite:
          external_labels:
            cluster: mothership
            clusterNamespace: kcm-system
opencost:
  opencost:
    exporter:
      # OpenCost serves /healthz only after its initial AWS pricing-index
      # download and parse, which takes 3+ minutes on this fully-loaded
      # single node. The chart's default startup probe budget (~160s) kills
      # the container first, leaving it in an endless restart loop. Give it
      # a larger budget (100 x 5s ~= 8 min).
      startupProbe:
        failureThreshold: 100
EOF

# Install collectors (OpenTelemetry, kube-state-metrics, node-exporter, OpenCost)
helm upgrade -i --reset-values --wait -n kof kof-collectors \
  -f /tmp/collectors-values.yaml \
  oci://ghcr.io/k0rdent/kof/charts/kof-collectors \
  --version 1.6.0 \
  --timeout 10m
```

### Step 6: Verify Complete Installation

> **Note:** The exact pod names and counts vary by KOF version. The list below is representative -- your output may show slightly different names or additional pods. The key check is that all pods reach `Running` or `Completed` status.

```bash
# Check all pods in kof namespace
kubectl get pods -n kof

# Expected pods (approximately 25-30):
# - grafana-vm-deployment-xxx
# - kof-operators-grafana-operator-xxx
# - kof-operators-opentelemetry-operator-xxx
# - kof-mothership-promxy-xxx
# - kof-mothership-victoria-metrics-operator-xxx
# - kof-collectors-kube-state-metrics-xxx
# - kof-collectors-prometheus-node-exporter-xxx
# - kof-collectors-opencost-xxx
# - kof-storage-jaeger-xxx
# - kof-storage-victoria-logs-cluster-xxx
# - vminsert-cluster-xxx
# - vmselect-cluster-xxx
# - vmstorage-cluster-xxx
# - vmalertmanager-cluster-xxx

# Check services
kubectl get svc -n kof
```

### Troubleshooting Installation

If pods are not starting:

```bash
# Check pod events
kubectl describe pods -n kof | grep -A 10 "Events:"

# Check for PVC issues (common problem)
kubectl get pvc -n kof

# If PVCs are pending, verify storage class
kubectl get storageclass
kubectl describe pvc -n kof
```

## Part 3: Deploy KOF on Child Clusters (~20 min)

KOF supports multiple deployment patterns for child clusters. This section covers all options from simple to production-grade.

### Understanding Child Cluster Telemetry Flow

```
+-------------------+     +-------------------+     +-------------------+
| Child Cluster 1   |     | Child Cluster 2   |     | Child Cluster N   |
| - kof-collectors  |     | - kof-collectors  |     | - kof-collectors  |
| - OpenTelemetry   |     | - OpenTelemetry   |     | - OpenTelemetry   |
| - OpenCost        |     | - OpenCost        |     | - OpenCost        |
+--------+----------+     +--------+----------+     +--------+----------+
         |                         |                         |
         |    metrics/logs/traces  |                         |
         +------------+------------+-------------------------+
                      |
                      v
         +------------------------+          +------------------------+
         | Regional Cluster       |    OR    | Management Cluster     |
         | (optional aggregation) |          | (direct storage)       |
         | - VictoriaMetrics      |          | - VictoriaMetrics      |
         | - VictoriaLogs         |          | - VictoriaLogs         |
         | - Jaeger               |          | - Grafana              |
         +------------------------+          +------------------------+
```

### Option 1: Automatic Deployment via Labels (Recommended)

The simplest approach uses labels on ClusterDeployment. The `kof-child` chart on the management cluster automatically deploys collectors to labeled clusters via **MultiClusterService**.

#### Step 1: Label the Managed Cluster

Two labels are required:
- `kof-cluster-role=child` - Marks cluster for collector deployment
- `kof-storage-secrets=true` - Enables credential distribution for authentication

```bash
# Label the cluster with KOF child role
kubectl label clusterdeployment managed-cluster-01 \
  k0rdent.mirantis.com/kof-cluster-role=child \
  -n kcm-system

# Label for secret distribution (required for collector authentication)
kubectl label clusterdeployment managed-cluster-01 \
  k0rdent.mirantis.com/kof-storage-secrets=true \
  -n kcm-system

# Verify labels were applied
kubectl get clusterdeployment managed-cluster-01 -n kcm-system --show-labels
```

#### Step 2: Create Cluster Configuration

> **Networking Prerequisite:** The endpoints below use internal Kubernetes DNS names (e.g., `vminsert-cluster.kof.svc.cluster.local`) that are only resolvable **within the management cluster**. In this training environment, the managed cluster runs in a separate VPC without direct connectivity to these services. We complete this step to learn the configuration pattern -- collectors will deploy but show connection errors until cross-VPC networking is established (see "Training Environment Limitation" below).

The child cluster needs to know where to send telemetry. Create a ConfigMap with the storage endpoints:

```bash
# Create cluster configuration with storage endpoints
cat << 'EOF' | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: kof-cluster-config-managed-cluster-01
  namespace: kcm-system
  labels:
    k0rdent.mirantis.com/kof-cluster-role: child
data:
  # Regional/storage cluster info
  regional_cluster_name: management
  regional_cluster_namespace: kcm-system
  regional_cluster_cloud: aws
  aws_region: eu-west-1

  # Metrics endpoints (VictoriaMetrics)
  write_metrics_endpoint: "http://vminsert-cluster.kof.svc.cluster.local:8480/insert/0/prometheus/api/v1/write"
  read_metrics_endpoint: "http://vmselect-cluster.kof.svc.cluster.local:8481/select/0/prometheus"

  # Logs endpoint (VictoriaLogs)
  write_logs_endpoint: "http://kof-storage-victoria-logs-cluster-vlinsert.kof.svc.cluster.local:9481/insert/opentelemetry/v1/logs"
  read_logs_endpoint: "http://kof-storage-victoria-logs-cluster-vlselect.kof.svc.cluster.local:9471"

  # Traces endpoint (Jaeger)
  write_traces_endpoint: "http://kof-storage-jaeger-collector.kof.svc.cluster.local:4318"
EOF
```

> **Note:** The ConfigMap name must follow the pattern `kof-cluster-config-<cluster-name>`. The endpoints above use internal service names which require network connectivity from child to management cluster.

#### Step 3: Install kof-child on Management Cluster

The `kof-child` chart creates MultiClusterService resources that automatically deploy collectors to all clusters with the `child` label:

```bash
# Install kof-child on management cluster (not on the child cluster!)
helm upgrade -i --reset-values --wait -n kof kof-child \
  oci://ghcr.io/k0rdent/kof/charts/kof-child \
  --version 1.6.0
```

This will automatically deploy:
- **cert-manager** - For TLS certificates
- **kof-operators** - OpenTelemetry operator (Grafana operator disabled on child)
- **kof-collectors** - OpenTelemetry collectors, kube-state-metrics, node-exporter, OpenCost

#### Step 4: Verify Automatic Deployment

```bash
# Check MultiClusterService was created
kubectl get multiclusterservice -A

# Check ClusterDeployment services status
kubectl get clusterdeployment managed-cluster-01 -n kcm-system

# Should show: SERVICES 4/4 (nginx + cert-manager + kof-operators + kof-collectors)
```

#### Step 5: Verify Collectors on Child Cluster

```bash
# Get kubeconfig for managed cluster
kubectl get secret managed-cluster-01-kubeconfig -n kcm-system \
  -o jsonpath='{.data.value}' | base64 -d > /tmp/managed.kubeconfig

# Check KOF pods on managed cluster
KUBECONFIG=/tmp/managed.kubeconfig kubectl get pods -n kof

# Expected pods (all should be Running):
# - cert-manager-xxx (3 pods)
# - kof-collectors-cluster-stats-collector-xxx
# - kof-collectors-daemon-collector-xxx (DaemonSet, one per node)
# - kof-collectors-kube-state-metrics-xxx
# - kof-collectors-prometheus-node-exporter-xxx (DaemonSet)
# - kof-collectors-opencost-xxx
# - kof-collectors-ta-daemon-collector-xxx (DaemonSet)
# - kof-collectors-ta-daemon-targetallocator-xxx
# - kof-operators-opentelemetry-operator-xxx
```

#### Troubleshooting Option 1

If pods show `CreateContainerConfigError`:
```bash
# Check if secrets were distributed
KUBECONFIG=/tmp/managed.kubeconfig kubectl get secrets -n kof | grep -E "vmuser|jaeger"

# Should see:
# - storage-vmuser-credentials
# - jaeger-admin-credentials
# - jaeger-admin-htpasswd

# If missing, verify the kof-storage-secrets label is set
kubectl get clusterdeployment managed-cluster-01 -n kcm-system -o jsonpath='{.metadata.labels}' | jq .
```

### Option 2: Regional Architecture (Production)

For large-scale deployments, use regional clusters as aggregation points to reduce cross-region traffic.

#### Regional Cluster Labels

When creating a regional cluster:

```yaml
apiVersion: k0rdent.mirantis.com/v1beta1
kind: ClusterDeployment
metadata:
  name: regional-us-east-1
  namespace: kcm-system
  labels:
    k0rdent.mirantis.com/kof-cluster-role: regional
    k0rdent.mirantis.com/kof-storage-secrets: "true"
  annotations:
    k0rdent.mirantis.com/kof-regional-domain: kof.us-east-1.example.com
    k0rdent.mirantis.com/kof-cert-email: admin@example.com
spec:
  template: aws-standalone-cp-1-0-20
  credential: aws-cluster-identity-cred
  config:
    region: us-east-1
    # ... rest of config
```

#### Child Clusters Point to Regional

Child clusters in the same region automatically discover and send telemetry to the regional cluster.

### Option 3: Custom Endpoints via Annotations

Configure child clusters to send telemetry to custom endpoints:

```yaml
apiVersion: k0rdent.mirantis.com/v1beta1
kind: ClusterDeployment
metadata:
  name: managed-cluster-01
  namespace: kcm-system
  labels:
    k0rdent.mirantis.com/kof-cluster-role: child
  annotations:
    # Custom write endpoints
    k0rdent.mirantis.com/kof-write-metrics-endpoint: "https://vmauth.example.com/vm/insert/0/prometheus/api/v1/write"
    k0rdent.mirantis.com/kof-write-logs-endpoint: "https://vmauth.example.com/vli/insert/opentelemetry/v1/logs"
    k0rdent.mirantis.com/kof-write-traces-endpoint: "https://jaeger.example.com/collector"
    # Custom read endpoints (for OpenCost)
    k0rdent.mirantis.com/kof-read-metrics-endpoint: "https://vmauth.example.com/vm/select/0/prometheus"
spec:
  template: aws-standalone-cp-1-0-20
  # ... rest of config
```

### Option 4: Manual Helm Install (Development/Testing)

For testing or when automatic deployment isn't suitable:

```bash
# Get kubeconfig for managed cluster
kubectl get secret managed-cluster-01-kubeconfig -n kcm-system \
  -o jsonpath='{.data.value}' | base64 -d > /tmp/managed-cluster-01.kubeconfig

# Create collectors values for the child cluster
cat << 'EOF' > /tmp/child-collectors-values.yaml
kcm:
  monitoring: true
opentelemetry-kube-stack:
  clusterName: managed-cluster-01
  defaultCRConfig:
    config:
      processors:
        resource/k8sclustername:
          attributes:
            - action: insert
              key: k8s.cluster.name
              value: managed-cluster-01
            - action: insert
              key: k8s.cluster.namespace
              value: kcm-system
      exporters:
        prometheusremotewrite:
          endpoint: http://<MANAGEMENT_VMINSERT_ENDPOINT>:8480/insert/0/prometheus/api/v1/write
          external_labels:
            cluster: managed-cluster-01
            clusterNamespace: kcm-system
EOF

# Install collectors on the child cluster
KUBECONFIG=/tmp/managed-cluster-01.kubeconfig \
helm upgrade -i --reset-values --wait --create-namespace -n kof kof-collectors \
  -f /tmp/child-collectors-values.yaml \
  oci://ghcr.io/k0rdent/kof/charts/kof-collectors \
  --version 1.6.0
```

> **Note:** Replace `<MANAGEMENT_VMINSERT_ENDPOINT>` with a reachable endpoint. See networking requirements below.

### Networking Requirements

For child clusters to send telemetry to the management/regional cluster:

| Requirement | Options |
|-------------|---------|
| **Network Path** | VPC peering, Transit Gateway, VPN, or public endpoint |
| **Authentication** | vmauth credentials (auto-distributed via `kof-storage-secrets` label) |
| **TLS** | Required for public endpoints; optional for private networks |
| **Ports** | 8480 (vminsert), 9481 (logs), 4318 (traces) |

#### Understanding the Cross-VPC Challenge

When CAPA (Cluster API for AWS) provisions managed clusters, it creates a **new VPC** for each cluster. This means:

1. **Internal service DNS doesn't work across VPCs** - `vminsert-cluster.kof.svc.cluster.local` only resolves within the management cluster
2. **Private IPs aren't routable** - The management cluster's pod/service IPs (10.x.x.x) aren't reachable from the managed cluster's VPC
3. **Network connectivity must be explicitly configured** - Unlike pods within a cluster, cross-VPC traffic requires infrastructure changes

#### Production Solutions

| Solution | Complexity | Cost | Best For |
|----------|------------|------|----------|
| **VPC Peering** | Medium | Free | Same-region clusters |
| **Transit Gateway** | Medium | ~$0.05/GB | Multi-VPC hub-spoke |
| **LoadBalancer + CCM** | Low-Medium | ~$16/month per NLB | Quick setup |
| **AWS PrivateLink** | High | Per-endpoint cost | Enterprise security |
| **Same-VPC Deployment** | Low | Free | Simplified networking |

##### Option A: LoadBalancer Approach (Requires AWS CCM)

To expose KOF services via AWS Network Load Balancers:

```bash
# 1. Install AWS Cloud Controller Manager (required for LoadBalancer type)
#    Note: k0s doesn't include CCM by default
#    See: https://kubernetes.github.io/cloud-provider-aws/

# 2. Patch services to LoadBalancer type
kubectl patch svc vminsert-cluster -n kof -p '{"spec": {"type": "LoadBalancer"}}'
kubectl patch svc kof-storage-victoria-logs-cluster-vlinsert -n kof -p '{"spec": {"type": "LoadBalancer"}}'
kubectl patch svc kof-storage-jaeger-collector -n kof -p '{"spec": {"type": "LoadBalancer"}}'

# 3. Wait for AWS to provision NLBs (1-2 minutes)
kubectl get svc -n kof -w

# 4. Update ConfigMap with LoadBalancer DNS names
VMINSERT_LB=$(kubectl get svc vminsert-cluster -n kof -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
# ... update kof-cluster-config-<cluster> ConfigMap
```

> **Important:** Without AWS Cloud Controller Manager installed, `type: LoadBalancer` services will stay in `<pending>` state indefinitely.

##### Option B: VPC Peering

```bash
# 1. Get VPC IDs
MGMT_VPC=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=*k0rdent*" --query 'Vpcs[0].VpcId' --output text)
MANAGED_VPC=$(aws ec2 describe-vpcs --filters "Name=tag:sigs.k8s.io/cluster-api-provider-aws/cluster/managed-cluster-01,Values=owned" --query 'Vpcs[0].VpcId' --output text)

# 2. Create peering connection
PEERING_ID=$(aws ec2 create-vpc-peering-connection --vpc-id $MGMT_VPC --peer-vpc-id $MANAGED_VPC --query 'VpcPeeringConnection.VpcPeeringConnectionId' --output text)
aws ec2 accept-vpc-peering-connection --vpc-peering-connection-id $PEERING_ID

# 3. Update route tables in both VPCs (add routes for each CIDR)
# 4. Update security groups to allow cross-VPC traffic on ports 8480, 9481, 4318
```

#### Training Environment Limitation

> **Training Environment Note:** In this training setup, the managed cluster runs in a separate AWS VPC created by CAPA. The management cluster uses k0s which doesn't include AWS Cloud Controller Manager by default.
>
> **What you'll observe:**
> - Collectors deploy successfully on the child cluster
> - Pods show `Running` status
> - Collector logs show connection errors to management cluster endpoints
>
> **This is expected behavior** - the collectors are correctly configured, but network connectivity isn't established.
>
> **For this lab**, we complete the labeling and configuration steps to understand the pattern. The key learning objectives are:
> 1. How to label clusters for automatic KOF deployment
> 2. How MultiClusterService distributes workloads
> 3. What configuration is needed for telemetry endpoints
>
> In production, you would implement one of the networking solutions above.

### Verify Child Cluster Collectors

Once networking is configured and collectors are deployed:

```bash
# Check KOF pods on managed cluster
KUBECONFIG=/tmp/managed-cluster-01.kubeconfig kubectl get pods -n kof

# Expected pods:
# - kof-collectors-cluster-stats-collector-xxx
# - kof-collectors-daemon-collector-xxx (DaemonSet)
# - kof-collectors-kube-state-metrics-xxx
# - kof-collectors-prometheus-node-exporter-xxx
# - kof-collectors-opencost-xxx

# Check if metrics are being exported (look for no errors)
KUBECONFIG=/tmp/managed-cluster-01.kubeconfig kubectl logs -n kof -l app.kubernetes.io/name=opentelemetry-collector --tail=20
```

### Component Summary

| Component | Deployed On | Purpose |
|-----------|-------------|---------|
| **kof-child** | Management cluster | Creates MultiClusterService to auto-deploy collectors |
| **kof-collectors** | Child clusters | OpenTelemetry, kube-state-metrics, node-exporter, OpenCost |
| **kof-regional** | Regional clusters | Storage + aggregation for a region |
| **vmauth credentials** | Auto-distributed | Authentication for remote write |

## Part 4: Access Grafana Dashboards (~15 min)

Grafana provides visualization for all observability data.

### Get Grafana Credentials

KOF generates random admin credentials stored in a Kubernetes secret:

```bash
# Get Grafana username
kubectl get secret grafana-admin-credentials -n kof \
  -o jsonpath='{.data.GF_SECURITY_ADMIN_USER}' | base64 -d && echo

# Get Grafana password
kubectl get secret grafana-admin-credentials -n kof \
  -o jsonpath='{.data.GF_SECURITY_ADMIN_PASSWORD}' | base64 -d && echo
```

> **Note:** Save these credentials - you'll need them to log into Grafana.

### Port-Forward Grafana

```bash
# From management cluster, port-forward Grafana
# Note: The service is named 'grafana-vm-service', not 'grafana'
kubectl port-forward svc/grafana-vm-service -n kof 3000:3000 --address 0.0.0.0 &

# Note the process ID for later cleanup
echo "Grafana port-forward PID: $!"
```

### Create SSH Tunnel (if needed)

If accessing remotely from your local machine:

```bash
# From local machine - create SSH tunnel through bastion
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -o ProxyCommand="ssh -i ./config/keys/bastion.pem -o StrictHostKeyChecking=no -W %h:%p ubuntu@<BASTION_IP>" \
    -i ./config/keys/lab-validation-k0rdent.pem \
    -L 3000:localhost:3000 \
    ubuntu@<MANAGEMENT_NODE_IP> \
    "kubectl port-forward svc/grafana-vm-service -n kof 3000:3000 --address 0.0.0.0"
```

Replace `<BASTION_IP>` and `<MANAGEMENT_NODE_IP>` with your infrastructure IPs.

### Access Grafana

1. Open browser to: `http://localhost:3000`
2. Login with the credentials retrieved from the secret above

> **Note:** If Grafana shows "Bad Gateway" or fails to load, wait 30 seconds and refresh. The Grafana operator provisions datasources and dashboards asynchronously after the pod starts -- dashboards may take 1-2 minutes to appear after first login.

### Explore Pre-built Dashboards

Navigate to **Dashboards** in the left menu. KOF includes pre-built dashboards organized by category (the exact count varies by version -- approximately 50-60 dashboards):

1. **Cluster API Dashboards**
   - `cluster-api` - CAPI controller metrics
   - `cluster-api-providers` - Infrastructure provider status
   - `cluster-api-state` - Cluster state overview

2. **k0rdent Dashboards**
   - `k0rdent-state` - Managed cluster status
   - `kcm-controller-manager` - k0rdent controller metrics
   - `cluster-deployment-events` - Deployment event timeline

3. **Kubernetes Dashboards** (kps-* prefix)
   - `kps-apiserver` - API server performance
   - `kps-etcd` - etcd cluster metrics
   - `kps-controller-manager` - Controller manager stats
   - `kps-cluster-total` - Cluster-wide resource usage

4. **Monitoring Stack Dashboards**
   - `kps-alertmanager-overview` - Alert management
   - `kps-grafana-overview` - Grafana performance

### Exercise: Explore Dashboards

Spend 15 minutes exploring:
- [ ] Open the `k0rdent-state` dashboard to see cluster overview
- [ ] Check `kps-cluster-total` for resource utilization
- [ ] Explore `cluster-api` to see CAPI controller activity
- [ ] Look at `kps-etcd` to monitor etcd health

## Part 5: Verify Telemetry Flow (~10 min)

Ensure metrics and logs are flowing into the KOF stack.

### Check Metrics in VictoriaMetrics

```bash
# Port-forward VictoriaMetrics vmselect (query endpoint)
kubectl port-forward svc/vmselect-cluster -n kof 8481:8481 &

# Query for metrics (from another terminal or use curl)
curl -s "http://localhost:8481/select/0/prometheus/api/v1/query?query=up" | jq '.data.result | length'

# Should return a number > 0 indicating active targets
# A fresh install typically shows 3+ targets
# NOTE: If this returns 0, wait 1-2 minutes for collectors to begin scraping

# Query specific metrics
curl -s "http://localhost:8481/select/0/prometheus/api/v1/query?query=kube_node_info" | jq '.data.result'
```

### Check Logs in VictoriaLogs

```bash
# Port-forward VictoriaLogs vlselect (query endpoint)
kubectl port-forward svc/kof-storage-victoria-logs-cluster-vlselect -n kof 9471:9471 &

# Query recent logs
curl -s "http://localhost:9471/select/logsql/query?query=*&limit=10"
```

> **Note:** VictoriaLogs may return empty results immediately after installation. It can take 2-3 minutes for the OpenTelemetry collectors to begin forwarding logs into VictoriaLogs. Re-run the query after a short wait if you see no output.

### Verify OpenCost Data

```bash
# Port-forward OpenCost
kubectl port-forward svc/kof-collectors-opencost -n kof 9090:9090 &

# Check OpenCost allocation API
curl -s "http://localhost:9090/allocation/compute?window=1h&aggregate=namespace" | jq '.data[0] | keys'
```

> **Note:** OpenCost may take a few minutes to start showing allocation data after initial deployment. In a training environment without cloud billing integration, cost values will use default pricing estimates rather than actual cloud costs. The allocation structure and namespace breakdown will still be visible.

## Part 6: Create Custom Dashboard (Optional) (~10 min)

Create a simple custom dashboard for your training environment.

### Create Dashboard via Grafana UI

1. In Grafana, click **+** → **Dashboard**
2. Click **Add visualization**
3. Select **VictoriaMetrics** as data source
4. Use query: `sum(kube_pod_info) by (namespace)`
5. Choose **Stat** visualization
6. Title: "Total Pods by Namespace"
7. Save dashboard as "Training Overview"

### Or Import via JSON

```bash
# Get Grafana credentials
GRAFANA_USER=$(kubectl get secret grafana-admin-credentials -n kof \
  -o jsonpath='{.data.GF_SECURITY_ADMIN_USER}' | base64 -d)
GRAFANA_PASS=$(kubectl get secret grafana-admin-credentials -n kof \
  -o jsonpath='{.data.GF_SECURITY_ADMIN_PASSWORD}' | base64 -d)

# Create a simple dashboard JSON
cat << 'EOF' > /tmp/training-dashboard.json
{
  "dashboard": {
    "title": "k0rdent Training Overview",
    "panels": [
      {
        "title": "Total Nodes",
        "type": "stat",
        "targets": [
          {
            "expr": "count(kube_node_info)",
            "refId": "A"
          }
        ],
        "gridPos": {"h": 4, "w": 6, "x": 0, "y": 0}
      },
      {
        "title": "Total Pods",
        "type": "stat",
        "targets": [
          {
            "expr": "count(kube_pod_info)",
            "refId": "A"
          }
        ],
        "gridPos": {"h": 4, "w": 6, "x": 6, "y": 0}
      }
    ]
  }
}
EOF

# Import via Grafana API (ensure port-forward is running on port 3000)
curl -X POST -H "Content-Type: application/json" \
  -d @/tmp/training-dashboard.json \
  http://${GRAFANA_USER}:${GRAFANA_PASS}@localhost:3000/api/dashboards/db
```

## Part 7: Understanding KOF Components (~5 min)

### Component Deep Dive

| Component | Chart | Purpose |
|-----------|-------|---------|
| **kof-operators** | kof-operators | Manages KOF component lifecycle |
| **kof-mothership** | kof-mothership | Core observability stack on management cluster |
| **kof-storage** | kof-storage | Configures persistent storage backends |
| **kof-collectors** | kof-collectors | OpenTelemetry collector configs |
| **kof-child** | kof-child | Components for managed clusters |
| **kof-regional** | kof-regional | Regional aggregation (optional tier) |

### OpenTelemetry Collectors

KOF uses OpenTelemetry for unified telemetry collection:

1. **Kube Cluster Collectors** - Cluster-level statistics
2. **Node Daemon Collectors** - Host metrics (DaemonSet)
3. **K0s Components Collector** - etcd, controller manager metrics
4. **Syslog Collector** - System logs with Grok patterns

## Validation Checklist

Before completing this lab, verify:

- [ ] KOF operators installed and running (Grafana + OpenTelemetry operators)
- [ ] KOF mothership deployed (Grafana, VictoriaMetrics operator, Promxy)
- [ ] KOF storage deployed (VictoriaLogs, Jaeger)
- [ ] KOF collectors deployed (kube-state-metrics, node-exporter, OpenTelemetry)
- [ ] All ~25 pods in kof namespace are Running
- [ ] Grafana accessible via port-forward
- [ ] Grafana showing ~50-60 pre-built dashboards
- [ ] Metrics visible in VictoriaMetrics (query returns > 0 results)
- [ ] (Optional) Managed cluster labeled with KOF role for child deployment

## Summary

In this lab, you:
- Learned the KOF three-tier architecture
- Deployed all four KOF charts on management cluster:
  - **kof-operators** - Grafana and OpenTelemetry operators
  - **kof-mothership** - Core components (Grafana, VictoriaMetrics operator, Promxy)
  - **kof-storage** - Storage backends (VictoriaLogs, Jaeger)
  - **kof-collectors** - Metrics collection (OpenTelemetry, kube-state-metrics)
- Accessed Grafana and explored pre-built dashboards
- Verified metrics are being collected from the management cluster

## Key Concepts

| Concept | Description |
|---------|-------------|
| **KOF Operators** | Manage lifecycle of observability components |
| **Mothership** | Central observability stack on management cluster |
| **OpenTelemetry** | Unified telemetry collection (metrics, logs, traces) |
| **VictoriaMetrics** | High-performance time-series database |
| **OpenCost** | Kubernetes cost allocation and FinOps |

## Troubleshooting

### Grafana Not Loading

```bash
# Check Grafana pod logs
kubectl logs -n kof -l app.kubernetes.io/name=grafana

# Verify Grafana service (note: service name is grafana-vm-service)
kubectl get svc grafana-vm-service -n kof

# Check Grafana deployment status
kubectl get deployment grafana-vm-deployment -n kof
```

### No Metrics in Dashboards

```bash
# 1. Verify VictoriaMetrics is receiving data
kubectl port-forward svc/vmselect-cluster -n kof 8481:8481 &
curl -s "http://localhost:8481/select/0/prometheus/api/v1/query?query=up" | jq '.data.result | length'

# 2. Check collector pods are running
kubectl get pods -n kof | grep -E 'collector|exporter|kube-state'

# 3. Check Grafana data sources are configured
kubectl get grafanadatasources -n kof

# 4. Verify vminsert is receiving writes
kubectl logs -n kof -l app.kubernetes.io/name=vminsert --tail=20
```

### PVC Pending

```bash
# Check storage class exists
kubectl get storageclass

# If no storage class exists, install local-path-provisioner:
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml

# Wait for provisioner to be ready
kubectl wait --for=condition=available deployment/local-path-provisioner -n local-path-storage --timeout=60s

# Verify storage class now exists
kubectl get storageclass

# Check PVC events
kubectl describe pvc -n kof
```

### Namespace Stuck Terminating (During Reinstall)

If you need to reinstall and the kof namespace won't delete:

```bash
# Remove finalizers from VictoriaMetrics CRs
for cr in vmagent vmalert vmcluster vmalertmanager vmrule vmservicescrape vmpodscrape vmnodescrape; do
  kubectl get $cr -n kof -o name 2>/dev/null | xargs -I {} kubectl patch {} -n kof --type=merge -p '{"metadata":{"finalizers":[]}}' 2>/dev/null
done

# Force finalize the namespace
kubectl get ns kof -o json | jq '.spec.finalizers=[]' | kubectl replace --raw "/api/v1/namespaces/kof/finalize" -f -
```

## Next Lab

Continue to [Lab 1.7: Multi-Cluster Service Deployment](lab-1.7-multicluster-services.md)
