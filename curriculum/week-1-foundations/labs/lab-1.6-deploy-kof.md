# Lab 1.6: Deploy k0rdent Observability & FinOps (KOF)

**Duration:** 2 hours
**Type:** Hands-on Lab

## Objectives

In this lab, you will:
- Understand KOF architecture and components
- Deploy KOF operators on the management cluster
- Install the KOF mothership stack (Grafana, VictoriaMetrics, etc.)
- Configure managed clusters for telemetry collection
- Access Grafana dashboards and explore observability data

## Prerequisites

- Completed Labs 1.1-1.5
- At least one managed cluster running (from Lab 1.5)
- Basic understanding of monitoring concepts

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

## Part 1: Understanding KOF Architecture

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

We'll deploy a simplified setup:
- **Management Cluster**: KOF operators + mothership (Grafana, metrics storage)
- **Managed Cluster**: OpenTelemetry collectors + OpenCost

## Part 2: Install KOF Operators

The KOF operators manage the lifecycle of observability components.

### Add KOF Helm Repository

```bash
# Verify helm is available
helm version

# The KOF charts are available via OCI registry
# No need to add a traditional Helm repo
```

### Install KOF Operators

```bash
# Install KOF operators
helm upgrade -i --wait --create-namespace -n kof kof-operators \
  oci://ghcr.io/k0rdent/kof/charts/kof-operators \
  --version 1.6.0

# Wait for operators to be ready
kubectl wait --for=condition=available deployment -n kof --all --timeout=300s
```

### Verify Operator Installation

```bash
# Check KOF namespace was created
kubectl get namespace kof

# List operator pods
kubectl get pods -n kof

# Expected output:
# kof-operators-xxx   Running
```

### Check Operator CRDs

```bash
# KOF operators install several CRDs
kubectl get crds | grep -E 'victoriametrics|opentelemetry|kof'
```

## Part 3: Deploy KOF Mothership

The mothership includes Grafana, VictoriaMetrics, and other core components.

### Create Mothership Values

```bash
# First, identify your storage class
kubectl get storageclass

# Create mothership configuration
cat << 'EOF' > /tmp/mothership-values.yaml
kcm:
  installTemplates: true

global:
  # Use your cluster's storage class (usually 'gp2' on AWS, 'standard' on k0s)
  storageClass: "local-path"

# Grafana configuration
grafana:
  enabled: true
  adminPassword: "k0rdent-training-2024"
  persistence:
    enabled: true
    size: 5Gi

# VictoriaMetrics for metrics storage
victoriametrics:
  enabled: true
  server:
    persistentVolume:
      enabled: true
      size: 10Gi

# VictoriaLogs for log storage
victorialogs:
  enabled: true
  server:
    persistentVolume:
      enabled: true
      size: 10Gi

# OpenCost for cost analysis
opencost:
  enabled: true
EOF
```

> **Note:** Adjust `storageClass` based on your cluster. Use `kubectl get storageclass` to find available options.

### Install KOF Mothership

```bash
# Install the mothership components
helm upgrade -i --wait -n kof kof-mothership \
  -f /tmp/mothership-values.yaml \
  oci://ghcr.io/k0rdent/kof/charts/kof-mothership \
  --version 1.6.0 \
  --timeout 10m
```

### Verify Mothership Installation

```bash
# Check all pods in kof namespace
kubectl get pods -n kof

# Expected pods include:
# - grafana-xxx
# - victoriametrics-xxx (or vmsingle/vmcluster)
# - promxy-xxx (for cross-cluster queries)

# Check services
kubectl get svc -n kof
```

### Troubleshooting Mothership

If pods are not starting:

```bash
# Check pod events
kubectl describe pods -n kof | grep -A 10 "Events:"

# Check for PVC issues (common problem)
kubectl get pvc -n kof

# If PVCs are pending, check storage class
kubectl describe pvc -n kof
```

## Part 4: Configure Managed Cluster for KOF

Now configure your managed cluster to send telemetry to the management cluster.

### Label the Managed Cluster

```bash
# Label the cluster with KOF role
kubectl label clusterdeployment managed-cluster-01 \
  k0rdent.mirantis.com/kof-cluster-role=child \
  -n kcm-system

# Optionally add storage secrets label if using cloud storage
kubectl label clusterdeployment managed-cluster-01 \
  k0rdent.mirantis.com/kof-storage-secrets=true \
  -n kcm-system

# Verify labels
kubectl get clusterdeployment managed-cluster-01 -n kcm-system --show-labels
```

### Create KOF Child Configuration

For the managed cluster to send metrics, we need to create a configuration:

```bash
cat << 'EOF' > /tmp/kof-child-config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: kof-child-config
  namespace: kof
data:
  # Management cluster's VictoriaMetrics endpoint
  METRICS_REMOTE_WRITE_URL: "http://victoriametrics-vmsingle.kof.svc:8428/api/v1/write"
  # Management cluster's VictoriaLogs endpoint
  LOGS_REMOTE_WRITE_URL: "http://victorialogs.kof.svc:9428/insert/loki/api/v1/push"
EOF

kubectl apply -f /tmp/kof-child-config.yaml
```

### Install KOF Child Components on Managed Cluster

```bash
# Get kubeconfig for managed cluster
kubectl get secret managed-cluster-01-kubeconfig -n kcm-system \
  -o jsonpath='{.data.value}' | base64 -d > /tmp/managed-cluster-01.kubeconfig

# Install KOF child components on the managed cluster
KUBECONFIG=/tmp/managed-cluster-01.kubeconfig \
helm upgrade -i --wait --create-namespace -n kof kof-child \
  oci://ghcr.io/k0rdent/kof/charts/kof-child \
  --version 1.6.0 \
  --set "remoteWrite.url=http://<management-cluster-ip>:8428/api/v1/write"
```

> **Note:** Replace `<management-cluster-ip>` with your management cluster's IP or use internal DNS if clusters can communicate.

### Verify Collectors on Managed Cluster

```bash
# Check KOF components on managed cluster
KUBECONFIG=/tmp/managed-cluster-01.kubeconfig kubectl get pods -n kof

# Expected:
# - opentelemetry-collector-xxx (DaemonSet for node metrics)
# - opencost-xxx (cost allocation)
```

## Part 5: Access Grafana Dashboards

Grafana provides visualization for all observability data.

### Port-Forward Grafana

```bash
# From management cluster, port-forward Grafana
kubectl port-forward svc/grafana -n kof 3000:3000 --address 0.0.0.0 &

# Note the process ID for later cleanup
echo "Grafana port-forward PID: $!"
```

### Create SSH Tunnel (if needed)

If accessing remotely:

```bash
# From local machine
./scripts/lab-connect.sh k0rdent <your-engineer-id> --tunnel 3000:3000
```

### Access Grafana

1. Open browser to: `http://localhost:3000`
2. Login:
   - **Username:** admin
   - **Password:** k0rdent-training-2024 (or check your values file)

### Explore Pre-built Dashboards

Navigate to **Dashboards** in the left menu. Look for:

1. **Kubernetes / Cluster Overview**
   - Node status
   - Pod counts
   - Resource utilization

2. **Kubernetes / Nodes**
   - Per-node CPU/memory
   - Disk and network I/O

3. **k0rdent / ClusterDeployments**
   - Managed cluster status
   - Deployment metrics

4. **OpenCost / Cost Allocation**
   - Namespace costs
   - Resource cost breakdown

### Exercise: Explore Dashboards

Spend 15 minutes exploring:
- [ ] Find the total CPU utilization across all clusters
- [ ] Identify the most resource-intensive namespace
- [ ] Check if OpenCost is showing cost data

## Part 6: Verify Telemetry Flow

Ensure metrics and logs are flowing from managed clusters.

### Check Metrics in VictoriaMetrics

```bash
# Port-forward VictoriaMetrics
kubectl port-forward svc/victoriametrics-vmsingle -n kof 8428:8428 &

# Query for metrics (from another terminal or use curl)
curl -s "http://localhost:8428/api/v1/query?query=up" | jq '.data.result | length'

# Should return a number > 0 indicating active targets
```

### Check Logs in VictoriaLogs

```bash
# Port-forward VictoriaLogs
kubectl port-forward svc/victorialogs -n kof 9428:9428 &

# Query recent logs
curl -s "http://localhost:9428/select/logsql/query?query=*&limit=10"
```

### Verify OpenCost Data

```bash
# Port-forward OpenCost
kubectl port-forward svc/opencost -n kof 9090:9090 &

# Check OpenCost allocation API
curl -s "http://localhost:9090/allocation/compute?window=1h&aggregate=namespace" | jq '.data[0] | keys'
```

## Part 7: Create Custom Dashboard (Optional)

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

# Import via Grafana API
curl -X POST -H "Content-Type: application/json" \
  -d @/tmp/training-dashboard.json \
  http://admin:k0rdent-training-2024@localhost:3000/api/dashboards/db
```

## Part 8: Understanding KOF Components

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

- [ ] KOF operators installed and running
- [ ] KOF mothership deployed (Grafana, VictoriaMetrics)
- [ ] Managed cluster labeled with KOF role
- [ ] KOF child components installed on managed cluster
- [ ] Grafana accessible and showing dashboards
- [ ] Metrics flowing from managed cluster
- [ ] OpenCost showing cost data (if applicable)

## Summary

In this lab, you:
- Learned the KOF three-tier architecture
- Deployed KOF operators and mothership on management cluster
- Configured managed cluster for telemetry collection
- Accessed Grafana and explored pre-built dashboards
- Verified metrics, logs, and cost data are being collected

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

# Verify Grafana service
kubectl get svc grafana -n kof
```

### No Metrics in Dashboards

```bash
# Check VictoriaMetrics is receiving data
kubectl logs -n kof -l app=vmsingle --tail=50

# Verify collectors are running on managed cluster
KUBECONFIG=/tmp/managed-cluster-01.kubeconfig kubectl get pods -n kof
```

### PVC Pending

```bash
# Check storage class exists
kubectl get storageclass

# Check PVC events
kubectl describe pvc -n kof
```

## Next Lab

Continue to [Lab 1.7: Multi-Cluster Service Deployment](lab-1.7-multicluster-services.md)
