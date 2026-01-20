# Week 1 Labs Expansion Design

**Date:** 2025-01-20
**Status:** Approved
**Target:** k0rdent Enterprise v1.2.x

## Overview

This design documents the planned updates and additions to Week 1 Foundation labs to:
1. Reflect current k0rdent Enterprise architecture (Service Catalog model)
2. Add hands-on managed cluster provisioning
3. Include KOF (Observability & FinOps) deployment
4. Demonstrate multi-cluster service deployment

## Problem Statement

### Current Issues

| Lab | Issue |
|-----|-------|
| Lab 1.2 | References bundled ServiceTemplates that have been externalized to Service Catalog |
| Lab 1.3 | Configures AWS credentials but never uses them to provision a cluster |
| Week 1 | Missing hands-on cluster provisioning, KOF deployment, and multi-cluster services |

### Missing Content
- No lab actually provisions a managed cluster
- No observability/KOF coverage
- No demonstration of MultiClusterService for deploying services at scale

## Design

### 1. Lab 1.2 Updates (ServiceTemplates → Service Catalog)

**File:** `lab-1.2-explore-k0rdent-ui.md`
**Action:** Update Part 4

#### Current Content (Outdated)
```bash
# List service templates
kubectl get servicetemplates -A
kubectl get servicetemplate -n kcm-system -o yaml | head -100
```

#### New Content
Replace Part 4 "Explore Service Templates" with "Understanding the Service Catalog":

1. **Architecture explanation**: ServiceTemplates still exist as CRDs, but templates are now hosted externally at `catalog.k0rdent.io`

2. **Catalog exploration**:
   - Browse https://catalog.k0rdent.io/
   - Categories: AI/ML, Networking, Security, Storage, Monitoring
   - Enterprise-only services: Ceph, StackLight, MSR, Mirantis Velero

3. **Installing a template from catalog**:
   ```bash
   # Example: Install ingress-nginx ServiceTemplate
   helm install ingress-nginx-service-template \
     oci://ghcr.io/k0rdent/catalog/charts/ingress-nginx-service-template \
     --version 4.11.0 -n kcm-system

   # Verify it exists
   kubectl get servicetemplates -n kcm-system
   ```

4. **Forward reference** to Lab 1.7 for hands-on service deployment

---

### 2. Lab 1.5: Provision Managed Cluster (NEW)

**File:** `lab-1.5-provision-managed-cluster.md`
**Duration:** 2-3 hours
**Prerequisites:** Labs 1.1-1.4 completed

#### Objectives
- Provision a minimal managed cluster on AWS
- Monitor CAPI provisioning workflow
- Access the managed cluster
- (Optional) Provision on Azure

#### Lab Structure

**Part 1: Verify Prerequisites**
- Confirm AWS credential from Lab 1.3
- List available ClusterTemplates: `kubectl get clustertemplates -n kcm-system | grep aws`

**Part 2: Create ClusterDeployment (AWS)**
```yaml
apiVersion: k0rdent.mirantis.com/v1beta1
kind: ClusterDeployment
metadata:
  name: managed-cluster-01
  namespace: kcm-system
spec:
  template: aws-standalone-cp-0-1-0
  credential: aws-cluster-identity-cred
  dryRun: false
  config:
    region: us-east-1
    controlPlane:
      instanceType: t3.medium
      rootVolumeSize: 50
    controlPlaneNumber: 1
    workersNumber: 1
    worker:
      instanceType: t3.medium
      rootVolumeSize: 50
```

**Part 3: Monitor Provisioning**
- Watch ClusterDeployment status
- Use `clusterctl describe cluster` for detailed progress
- Troubleshooting common issues

**Part 4: Access the Managed Cluster**
- Retrieve kubeconfig from secret
- Connect and verify nodes/pods

**Part 5 (Optional): Azure Cluster**
- Configure Azure credentials (AzureClusterIdentity)
- Create Azure ClusterDeployment

#### Cost Considerations
- Estimated AWS cost: ~$0.15/hour for minimal cluster
- Cleanup instructions included

---

### 3. Lab 1.6: Deploy KOF (NEW)

**File:** `lab-1.6-deploy-kof.md`
**Duration:** 2 hours
**Prerequisites:** Lab 1.5 completed

#### Objectives
- Understand KOF architecture
- Deploy KOF operators and mothership
- Configure managed cluster for telemetry
- Access Grafana dashboards

#### Lab Structure

**Part 1: Understanding KOF Architecture**
- Three-tier model: Management → Regional → Child
- Components:
  | Component | Purpose |
  |-----------|---------|
  | VictoriaMetrics | Metrics storage |
  | VictoriaLogs | Log aggregation |
  | Jaeger + OpenTelemetry | Distributed tracing |
  | OpenCost | Cost allocation |
  | Grafana | Dashboards |

**Part 2: Install KOF Operators**
```bash
helm upgrade -i --wait --create-namespace -n kof kof-operators \
  oci://ghcr.io/k0rdent/kof/charts/kof-operators \
  --version 1.6.0
```

**Part 3: Deploy KOF Mothership**
- Create `mothership-values.yaml`
- Install kof-mothership chart
- Verify pods

**Part 4: Configure Managed Cluster**
- Label cluster: `k0rdent.mirantis.com/kof-cluster-role: child`
- Install kof-child components

**Part 5: Access Grafana**
- Port-forward Grafana
- Explore dashboards
- View OpenCost

**Part 6: Verify Telemetry**
- Generate sample workload
- Observe metrics, logs, traces

---

### 4. Lab 1.7: Multi-Cluster Service Deployment (NEW)

**File:** `lab-1.7-multicluster-services.md`
**Duration:** 2-3 hours
**Prerequisites:** Lab 1.5 completed

#### Objectives
- Understand MultiClusterService concept
- Browse and install from Service Catalog
- Deploy services across multiple clusters
- Understand service dependencies

#### Lab Structure

**Part 1: Understanding MultiClusterService**
- Label selectors for cluster targeting
- ServiceTemplateChains for upgrades
- Dependency ordering

**Part 2: Browse Service Catalog**
- Navigate https://catalog.k0rdent.io/
- Explore categories
- Identify Enterprise-only services

**Part 3: Install ServiceTemplates**
```bash
# cert-manager
helm install cert-manager-st \
  oci://ghcr.io/k0rdent/catalog/charts/cert-manager-service-template \
  --version 1.16.2 -n kcm-system

# ingress-nginx
helm install ingress-nginx-st \
  oci://ghcr.io/k0rdent/catalog/charts/ingress-nginx-service-template \
  --version 4.11.0 -n kcm-system

# kyverno
helm install kyverno-st \
  oci://ghcr.io/k0rdent/catalog/charts/kyverno-service-template \
  --version 3.2.6 -n kcm-system
```

**Part 4: Label Clusters**
```bash
kubectl label clusterdeployment managed-cluster-01 \
  environment=training tier=standard -n kcm-system
```

**Part 5: Create MultiClusterService**
```yaml
apiVersion: k0rdent.mirantis.com/v1beta1
kind: MultiClusterService
metadata:
  name: training-baseline-services
  namespace: kcm-system
spec:
  clusterSelector:
    matchLabels:
      environment: training
  serviceSpec:
    services:
    - template: cert-manager-1-16-2
      name: cert-manager
      namespace: cert-manager
    - template: ingress-nginx-4-11-0
      name: ingress-nginx
      namespace: ingress-nginx
    - template: kyverno-3-2-6
      name: kyverno
      namespace: kyverno
    priority: 100
```

**Part 6: Verify Deployment**
- Watch MultiClusterService status
- Verify pods on managed clusters
- Test ingress-nginx

**Part 7: Service Dependencies**
- Demonstrate `dependsOn` ordering

---

## Updated Week 1 Flow

```
Lab 1.1: Provision Management Cluster
    ↓
Lab 1.2: Explore UI + Service Catalog (UPDATED)
    ↓
Lab 1.3: Configure AWS Provider Credentials
    ↓
Lab 1.4: Production Configuration (RBAC, Backup)
    ↓
Lab 1.5: Provision Managed Cluster (NEW)
    ↓
Lab 1.6: Deploy KOF (NEW)
    ↓
Lab 1.7: Multi-Cluster Services (NEW)
```

## Dependencies

- Lab 1.5 requires Lab 1.3 (AWS credentials)
- Lab 1.6 requires Lab 1.5 (needs managed cluster)
- Lab 1.7 requires Lab 1.5 (needs managed cluster)

## Estimated Additional Training Time

| Lab | Duration |
|-----|----------|
| Lab 1.5 | 2-3 hours |
| Lab 1.6 | 2 hours |
| Lab 1.7 | 2-3 hours |
| **Total** | **6-8 hours** |

## Implementation Notes

### Template Names
- Actual ClusterTemplate names need verification against k0rdent Enterprise v1.2.x
- ServiceTemplate names from catalog may vary by version

### Cost Management
- All labs use minimal cluster specs (1 CP + 1 worker)
- Clear cleanup instructions in each lab
- Estimated AWS cost: ~$0.15/hour per cluster

### Azure Support
- Lab 1.5 includes optional Azure section
- Requires separate Azure credential configuration
- Uses similar minimal cluster spec

## Files to Create/Modify

| File | Action |
|------|--------|
| `lab-1.2-explore-k0rdent-ui.md` | Update Part 4 |
| `lab-1.5-provision-managed-cluster.md` | Create |
| `lab-1.6-deploy-kof.md` | Create |
| `lab-1.7-multicluster-services.md` | Create |
