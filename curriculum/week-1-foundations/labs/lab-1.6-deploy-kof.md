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

We'll deploy the "Management to Management" configuration, where the management cluster stores its own telemetry data:

- **Management Cluster**: Full KOF stack with all four charts
  - kof-operators (Grafana + OpenTelemetry operators)
  - kof-mothership (Grafana, VictoriaMetrics operator, Promxy)
  - kof-storage (VictoriaLogs, Jaeger for local storage)
  - kof-collectors (OpenTelemetry, kube-state-metrics, node-exporter)

This is the recommended starting point for learning KOF. For production multi-cluster setups, you would deploy kof-child on managed clusters to send telemetry to the management cluster.

## Part 2: Install KOF Components

KOF requires **four Helm charts** installed in order:

| Chart | Purpose |
|-------|---------|
| **kof-operators** | Grafana and OpenTelemetry operators (CRDs) |
| **kof-mothership** | Core components: Grafana, VictoriaMetrics operator, Promxy |
| **kof-storage** | Storage: VictoriaLogs cluster, Jaeger, PromxyServerGroup |
| **kof-collectors** | Metrics collection: OpenTelemetry, kube-state-metrics, node-exporter |

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

```bash
# Install KOF operators (Grafana + OpenTelemetry operators)
helm upgrade -i --reset-values --wait --create-namespace -n kof kof-operators \
  oci://ghcr.io/k0rdent/kof/charts/kof-operators \
  --version 1.5.0

# Verify operators are running
kubectl get pods -n kof
# Expected: kof-operators-grafana-operator-xxx, kof-operators-opentelemetry-operator-xxx
```

### Step 3: Install KOF Mothership

```bash
# Create mothership configuration
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
  --version 1.5.0 \
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
  --version 1.5.0 \
  --timeout 10m
```

### Step 5: Install KOF Collectors

```bash
# Create collectors configuration
cat << 'EOF' > /tmp/collectors-values.yaml
kcm:
  monitoring: true
opentelemetry-kube-stack:
  clusterName: mothership
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
EOF

# Install collectors (OpenTelemetry, kube-state-metrics, node-exporter, OpenCost)
helm upgrade -i --reset-values --wait -n kof kof-collectors \
  -f /tmp/collectors-values.yaml \
  oci://ghcr.io/k0rdent/kof/charts/kof-collectors \
  --version 1.5.0 \
  --timeout 10m
```

### Step 6: Verify Complete Installation

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

## Part 4: Deploy KOF on Child Clusters

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

```bash
# Label the cluster with KOF child role
kubectl label clusterdeployment managed-cluster-01 \
  k0rdent.mirantis.com/kof-cluster-role=child \
  -n kcm-system

# Verify label was applied
kubectl get clusterdeployment managed-cluster-01 -n kcm-system --show-labels
```

#### Step 2: Install kof-child on Management Cluster

The `kof-child` chart creates MultiClusterService resources that automatically deploy collectors to all clusters with the `child` label:

```bash
# Install kof-child on management cluster (not on the child cluster!)
helm upgrade -i --reset-values --wait -n kof kof-child \
  oci://ghcr.io/k0rdent/kof/charts/kof-child \
  --version 1.5.0
```

This will automatically deploy `kof-collectors` to any ClusterDeployment with label `k0rdent.mirantis.com/kof-cluster-role=child`.

#### Step 3: Verify Automatic Deployment

```bash
# Check MultiClusterService was created
kubectl get multiclusterservice -n kcm-system

# Check if collectors are deploying to child cluster
kubectl get clusterdeployment managed-cluster-01 -n kcm-system -o yaml | grep -A 20 "serviceSpec"
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
  credential: aws-credential
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
  --version 1.5.0
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

#### Training Environment Limitation

> **Training Environment Note:** In this training setup, the managed cluster runs in a separate AWS VPC and cannot directly reach the management cluster's internal services.
>
> **To enable cross-cluster telemetry, you would need one of:**
> 1. **VPC Peering** - Connect the VPCs for private communication
> 2. **LoadBalancer + TLS** - Expose vminsert/vlinsert with authentication
> 3. **Service Mesh** - Use Istio for secure cross-cluster mTLS
> 4. **AWS PrivateLink** - Create private endpoints between VPCs
>
> **For this lab**, we complete the labeling steps to understand the pattern. In production, networking would be configured appropriately.

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

## Part 5: Access Grafana Dashboards

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

### Explore Pre-built Dashboards

Navigate to **Dashboards** in the left menu. KOF includes 56 pre-built dashboards organized by category:

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

## Part 6: Verify Telemetry Flow

Ensure metrics and logs are flowing into the KOF stack.

### Check Metrics in VictoriaMetrics

```bash
# Port-forward VictoriaMetrics vmselect (query endpoint)
kubectl port-forward svc/vmselect-cluster -n kof 8481:8481 &

# Query for metrics (from another terminal or use curl)
curl -s "http://localhost:8481/select/0/prometheus/api/v1/query?query=up" | jq '.data.result | length'

# Should return a number > 0 indicating active targets
# A fresh install typically shows 3+ metrics

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

### Verify OpenCost Data

```bash
# Port-forward OpenCost
kubectl port-forward svc/kof-collectors-opencost -n kof 9090:9090 &

# Check OpenCost allocation API
curl -s "http://localhost:9090/allocation/compute?window=1h&aggregate=namespace" | jq '.data[0] | keys'
```

> **Note:** OpenCost may take a few minutes to start showing allocation data after initial deployment.

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

- [ ] KOF operators installed and running (Grafana + OpenTelemetry operators)
- [ ] KOF mothership deployed (Grafana, VictoriaMetrics operator, Promxy)
- [ ] KOF storage deployed (VictoriaLogs, Jaeger)
- [ ] KOF collectors deployed (kube-state-metrics, node-exporter, OpenTelemetry)
- [ ] All ~25 pods in kof namespace are Running
- [ ] Grafana accessible via port-forward
- [ ] Grafana showing 56 pre-built dashboards
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
- Accessed Grafana and explored 56 pre-built dashboards
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
