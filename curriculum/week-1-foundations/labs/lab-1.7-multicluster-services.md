# Lab 1.7: Multi-Cluster Service Deployment

**Duration:** 2-3 hours
**Type:** Hands-on Lab

## Table of Contents

- [Objectives](#objectives)
- [Prerequisites](#prerequisites)
- [Resuming This Lab](#resuming-this-lab)
- [What is MultiClusterService?](#what-is-multiclusterservice)
- [Part 1: Browse the Service Catalog](#part-1-browse-the-service-catalog)
  - [Access the Catalog](#access-the-catalog)
  - [Explore Categories](#explore-categories)
  - [Exercise: Catalog Exploration](#exercise-catalog-exploration)
  - [Understanding Service Versions](#understanding-service-versions)
- [Part 2: Install ServiceTemplates from Catalog](#part-2-install-servicetemplates-from-catalog)
  - [Ensure the Catalog HelmRepository Exists](#ensure-the-catalog-helmrepository-exists)
  - [Check Existing ServiceTemplates](#check-existing-servicetemplates)
  - [Install ServiceTemplates](#install-servicetemplates)
  - [Verify All Templates](#verify-all-templates)
  - [Examine a ServiceTemplate](#examine-a-servicetemplate)
- [Part 3: Label Clusters for Service Targeting](#part-3-label-clusters-for-service-targeting)
  - [Check Current Cluster Labels](#check-current-cluster-labels)
  - [Add Labels for Targeted Service Deployment](#add-labels-for-targeted-service-deployment)
  - [Verify Labels](#verify-labels)
- [Part 4: Create MultiClusterService](#part-4-create-multiclusterservice)
  - [Understanding MultiClusterService Structure](#understanding-multiclusterservice-structure)
  - [Strategy: Two MultiClusterServices with Different Selectors](#strategy-two-multiclusterservices-with-different-selectors)
  - [Create the Baseline MCS (All Training Clusters)](#create-the-baseline-mcs-all-training-clusters)
  - [Create the Ingress MCS (Selective Targeting)](#create-the-ingress-mcs-selective-targeting)
  - [Verify Both MultiClusterServices](#verify-both-multiclusterservices)
- [Part 5: Monitor Service Deployment](#part-5-monitor-service-deployment)
  - [Watch MultiClusterService Status](#watch-multiclusterservice-status)
  - [Check Services on Managed Clusters](#check-services-on-managed-clusters)
  - [Verify ServiceSets and Sveltos Objects](#verify-servicesets-and-sveltos-objects)
- [Part 6: Service Dependencies](#part-6-service-dependencies)
  - [Understanding dependsOn](#understanding-dependson)
  - [Create Dependent Services Example](#create-dependent-services-example)
  - [Service Priority](#service-priority)
- [Part 7: Validate Deployed Services](#part-7-validate-deployed-services)
  - [Test cert-manager](#test-cert-manager)
  - [Test ingress-nginx](#test-ingress-nginx)
  - [Test kyverno](#test-kyverno)
  - [Return to Management Cluster](#return-to-management-cluster)
- [Part 8: Update and Remove Services](#part-8-update-and-remove-services)
  - [Update Service Values](#update-service-values)
  - [Remove a Service](#remove-a-service)
  - [ServiceTemplateChains for Upgrades](#servicetemplatechains-for-upgrades)
- [Part 9: Clean Up](#part-9-clean-up)
  - [Remove MultiClusterService](#remove-multiclusterservice)
  - [Remove ServiceTemplates (Optional)](#remove-servicetemplates-optional)
- [Validation Checklist](#validation-checklist)
- [Summary](#summary)
- [Key Concepts](#key-concepts)
- [Week 1 Complete!](#week-1-complete)
- [Next Week](#next-week)

## Objectives

In this lab, you will:
- Understand the MultiClusterService concept
- Browse and explore the k0rdent Service Catalog
- Install ServiceTemplates from the catalog
- Deploy services across managed clusters using MultiClusterService
- Understand service dependencies and ordering

## Prerequisites

- Completed Labs 1.1-1.6
- Understanding of Helm and Kubernetes services

> **Keep your managed cluster running!** This lab requires the managed cluster from Lab 1.5 to be active. This is the final lab of Week 1 -- you can run cleanup after completing it.

## Resuming This Lab

If your SSH session dropped or you're returning the next day:

```bash
cd lab-infrastructure
./scripts/lab-connect.sh <your-engineer-id>
kubectl get nodes && kubectl get pods -n kcm-system

# Verify managed cluster is still running
kubectl get clusterdeployment -n kcm-system

# Check if ServiceTemplates are already installed
kubectl get servicetemplates -n kcm-system
```

---

## What is MultiClusterService?

**MultiClusterService** is a k0rdent CRD that enables centralized deployment of services across multiple managed clusters. Instead of deploying services individually to each cluster, you define:

1. **Which clusters** to target (via label selectors)
2. **Which services** to deploy (via ServiceTemplates)
3. **Deployment order** (via dependencies)

```
+----------------------------------+
|        MultiClusterService       |
|  clusterSelector:                |
|    environment: production       |
|  services:                       |
|    - cert-manager                |
|    - ingress-nginx               |
|    - kyverno                     |
+----------------------------------+
            |
            v
    +-------+-------+
    |               |
    v               v
+--------+   +--------+
|Cluster1|   |Cluster2|
|  prod  |   |  prod  |
+--------+   +--------+
```

## Part 1: Browse the Service Catalog

Before deploying services, explore what's available in the k0rdent Service Catalog.

### Access the Catalog

Open your browser to: **https://catalog.k0rdent.io/**

### Explore Categories

The catalog organizes 100+ services into categories:

| Category | Description | Example Services |
|----------|-------------|-----------------|
| **AI/Machine Learning** | GPU operators, ML frameworks | NVIDIA, KubeRay, KServe, MLflow |
| **Networking** | Ingress, service mesh, load balancing | ingress-nginx, Cilium, Istio, MetalLB |
| **Security** | Policy, secrets, compliance | Kyverno, External Secrets, Falco |
| **Observability** | Monitoring, logging, tracing | Grafana, Prometheus, Loki |
| **Storage** | Databases, object storage | PostgreSQL, MinIO, Milvus |
| **CI/CD** | Continuous integration, GitOps | Argo CD, GitLab, Harbor |

### Exercise: Catalog Exploration

Spend 10 minutes exploring:
- [ ] Find **cert-manager** and note its latest version
- [ ] Find **ingress-nginx** and check available versions
- [ ] Find **kyverno** and read its description
- [ ] Identify one Enterprise-only service

### Understanding Service Versions

Each service shows:
- **Version**: The Helm chart version
- **App Version**: The underlying application version
- **Enterprise**: Whether it requires k0rdent Enterprise

## Part 2: Install ServiceTemplates from Catalog

ServiceTemplates must be installed on the management cluster before they can be deployed to managed clusters.

### Ensure the Catalog HelmRepository Exists

The ServiceTemplates reference charts from the `k0rdent-catalog` HelmRepository. If you created it in Lab 1.2, it should already exist:

```bash
kubectl get helmrepositories -n kcm-system | grep k0rdent-catalog
```

If not found, create it:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: k0rdent-catalog
  namespace: kcm-system
  labels:
    k0rdent.mirantis.com/managed: "true"
spec:
  type: oci
  url: oci://ghcr.io/k0rdent/catalog/charts
  interval: 10m0s
  provider: generic
EOF
```

### Check Existing ServiceTemplates

```bash
# List any existing ServiceTemplates
kubectl get servicetemplates -n kcm-system

# You may already have kyverno-3-8-1 from Lab 1.2
```

### Install ServiceTemplates

Create ServiceTemplates for the three services we'll deploy. Each references a chart from the `k0rdent-catalog` HelmRepository:

```bash
cat <<EOF | kubectl apply -f -
---
apiVersion: k0rdent.mirantis.com/v1beta1
kind: ServiceTemplate
metadata:
  name: cert-manager-1-20-2
  namespace: kcm-system
spec:
  helm:
    chartSpec:
      chart: cert-manager
      version: 1.20.2
      interval: 10m0s
      sourceRef:
        kind: HelmRepository
        name: k0rdent-catalog
---
apiVersion: k0rdent.mirantis.com/v1beta1
kind: ServiceTemplate
metadata:
  name: ingress-nginx-4-15-1
  namespace: kcm-system
spec:
  helm:
    chartSpec:
      chart: ingress-nginx
      version: 4.15.1
      interval: 10m0s
      sourceRef:
        kind: HelmRepository
        name: k0rdent-catalog
---
apiVersion: k0rdent.mirantis.com/v1beta1
kind: ServiceTemplate
metadata:
  name: kyverno-3-8-1
  namespace: kcm-system
spec:
  helm:
    chartSpec:
      chart: kyverno
      version: 3.8.1
      interval: 10m0s
      sourceRef:
        kind: HelmRepository
        name: k0rdent-catalog
EOF
```

```bash
# Verify all three are valid (may take ~30s for Flux to validate)
kubectl get servicetemplates -n kcm-system
```

You should see all three with `VALID: true`.

### Verify All Templates

```bash
# List all installed ServiceTemplates
kubectl get servicetemplates -n kcm-system

# Expected output:
# NAME                    AGE
# cert-manager-1-20-2     1m
# ingress-nginx-4-15-1    1m
# kyverno-3-8-1           1m
```

### Examine a ServiceTemplate

```bash
# View the structure of a ServiceTemplate
kubectl get servicetemplate cert-manager-1-20-2 -n kcm-system -o yaml
```

Key fields:
- `spec.helm.chartSpec.chart`: The Helm chart name
- `spec.helm.chartSpec.version`: Chart version
- `spec.helm.chartSpec.sourceRef`: Reference to HelmRepository

## Part 3: Label Clusters for Service Targeting

MultiClusterService uses label selectors to target clusters. MultiClusterService matches against ClusterDeployment **metadata labels** (set via `kubectl label`), not `spec.config.clusterLabels`.

### Check Current Cluster Labels

```bash
# View the metadata labels on each ClusterDeployment
kubectl get clusterdeployments -n kcm-system --show-labels

# Example output:
# NAME                 READY   STATUS   LABELS
# managed-cluster-01   True    ...      environment=training,owner=lab-user
```

### Add Labels for Targeted Service Deployment

We'll use two labeling strategies to demonstrate different targeting patterns:
- `environment: training` — already set on all clusters via metadata labels (deploy baseline services to all)
- `ingress: "true"` — opt-in label for clusters that need ingress (selective deployment)

```bash
# Add labels to ClusterDeployment METADATA (MCS matches these, not spec.config.clusterLabels)
kubectl label clusterdeployment managed-cluster-01 -n kcm-system \
  environment=training \
  ingress=true

# Cluster-02 gets only environment label (no ingress)
# kubectl label clusterdeployment managed-cluster-02 -n kcm-system \
#   environment=training
```

### Verify Labels

```bash
# Confirm metadata labels
kubectl get clusterdeployments -n kcm-system --show-labels

# Expected:
# managed-cluster-01 should show: environment=training,ingress=true,...
# managed-cluster-02 should show: environment=training,...
```

> **Important:** Use `kubectl label` to set metadata labels on ClusterDeployments. MultiClusterService `clusterSelector` matches against these **metadata labels**, not `spec.config.clusterLabels`. The `spec.config.clusterLabels` field propagates labels to the underlying CAPI Cluster object but is not used by MCS for targeting.

## Part 4: Create MultiClusterService

Now deploy services to all labeled clusters with a single resource.

### Understanding MultiClusterService Structure

```yaml
apiVersion: k0rdent.mirantis.com/v1beta1
kind: MultiClusterService
metadata:
  name: <name>
spec:
  clusterSelector:           # Which clusters to target
    matchLabels:
      key: value
  serviceSpec:
    services:                # List of services to deploy
    - template: <template-name>
      name: <release-name>
      namespace: <target-namespace>
      values: |              # Optional Helm values
        key: value
    priority: 100            # Deployment priority (higher = first)
  dependsOn:                 # Optional dependencies on other MCS
  - <other-mcs-name>
```

### Strategy: Two MultiClusterServices with Different Selectors

We'll create two MCS resources to demonstrate both patterns:

| MCS | Selector | Targets | Deploys |
|-----|----------|---------|---------|
| `baseline-services` | `environment: training` | **All** training clusters | cert-manager, kyverno |
| `ingress-services` | `ingress: "true"` | **Only** clusters that opted in | ingress-nginx |

This shows how you can deploy mandatory services to every cluster while keeping optional services targeted to specific clusters.

> **⚠️ Wrapper-chart values gotcha (important!):** The k0rdent catalog charts (`cert-manager`, `kyverno`, `ingress-nginx`, etc.) are **thin umbrella wrappers** around the upstream official charts. Each wrapper has a single dependency on the real chart with a matching name, and **no values.yaml of its own**. This means any values you pass must be **nested under the subchart name** to reach the real chart. For example:
>
> ```yaml
> # ✅ CORRECT — nested under subchart name
> values: |
>   cert-manager:
>     crds:
>       enabled: true
> ```
>
> ```yaml
> # ❌ WRONG — silently ignored by wrapper, chart installs with defaults
> values: |
>   crds:
>     enabled: true
> ```
>
> You can confirm this with `helm pull oci://ghcr.io/k0rdent/catalog/charts/<chart> --version <v> --untar` and inspecting `charts/<chart>/charts/<chart>/` — the real chart lives under the wrapper's `charts/` directory. This pattern applies to **every chart** in the k0rdent catalog.

### Create the Baseline MCS (All Training Clusters)

> **⚠️ Pick the right variant — did you complete Lab 1.6 Part 3 (kof-child)?** If you completed Lab 1.6 Part 3 (the recommended path), cert-manager is **already on this cluster**: the `kof-child` chart deployed it (Helm release `cert-manager` in the `kof` namespace, CRDs included) alongside `kof-operators` and `kof-collectors` via its own MultiClusterService. A second cert-manager install fails Helm's CRD ownership check -- the cluster-scoped cert-manager CRDs carry `meta.helm.sh/release-namespace: kof`, so the new release is rejected with `invalid ownership metadata`. And because services in a MultiClusterService deploy **sequentially**, the failed cert-manager would also block kyverno. **Use the kyverno-only variant (Option A).**

**Option A — kyverno-only variant** (use this if you completed Lab 1.6 Part 3):

```bash
cat <<EOF | kubectl apply -f -
apiVersion: k0rdent.mirantis.com/v1beta1
kind: MultiClusterService
metadata:
  name: baseline-services
spec:
  clusterSelector:
    matchLabels:
      environment: training
  serviceSpec:
    services:
    - template: kyverno-3-8-1
      name: kyverno
      namespace: kyverno
      values: |
        kyverno:
          admissionController:
            replicas: 1
    priority: 100
EOF
```

**Option B — full variant** (only if you **skipped** Lab 1.6 Part 3, so the cluster has no cert-manager yet):

```bash
cat <<EOF | kubectl apply -f -
apiVersion: k0rdent.mirantis.com/v1beta1
kind: MultiClusterService
metadata:
  name: baseline-services
spec:
  clusterSelector:
    matchLabels:
      environment: training
  serviceSpec:
    services:
    - template: cert-manager-1-20-2
      name: cert-manager
      namespace: cert-manager
      values: |
        cert-manager:
          crds:
            enabled: true
    - template: kyverno-3-8-1
      name: kyverno
      namespace: kyverno
      values: |
        kyverno:
          admissionController:
            replicas: 1
    priority: 100
EOF
```

This deploys cert-manager and kyverno to **every cluster** with `environment: training` — both managed-cluster-01 and managed-cluster-02.

> **Why `cert-manager.crds.enabled: true`?** cert-manager v1.15+ stopped installing CRDs by default. Without this value, the wrapper chart silently installs cert-manager without CRDs, the `cert-manager-startupapicheck` job loops forever waiting for `CertificateRequest` CRD, Helm install times out, and Sveltos reports `context deadline exceeded`. Because services in a MultiClusterService deploy **sequentially**, a failing cert-manager also blocks kyverno in the same MCS.

### Create the Ingress MCS (Selective Targeting)

```bash
cat <<EOF | kubectl apply -f -
apiVersion: k0rdent.mirantis.com/v1beta1
kind: MultiClusterService
metadata:
  name: ingress-services
spec:
  clusterSelector:
    matchLabels:
      ingress: "true"
  serviceSpec:
    services:
    - template: ingress-nginx-4-15-1
      name: ingress-nginx
      namespace: ingress-nginx
      values: |
        ingress-nginx:
          controller:
            replicaCount: 1
            service:
              type: LoadBalancer
    priority: 100
EOF
```

This deploys ingress-nginx **only** to managed-cluster-01 (which has `ingress: "true"`). Managed-cluster-02 doesn't get it.

### Verify Both MultiClusterServices

```bash
# Check MCS status — baseline should match 2 clusters, ingress should match 1
kubectl get multiclusterservice

# View cluster matching
kubectl describe multiclusterservice baseline-services | grep -A 5 "Matching Clusters"
kubectl describe multiclusterservice ingress-services | grep -A 5 "Matching Clusters"
```

Expected:
- `baseline-services` → `2/2` clusters (both have `environment: training`)
- `ingress-services` → `1/1` cluster (only managed-cluster-01 has `ingress: "true"`)

## Part 5: Monitor Service Deployment

Services deploy asynchronously to all matched clusters. Monitor the progress.

### Watch MultiClusterService Status

```bash
# Watch both MCS for status updates
kubectl get multiclusterservice -w

# Check conditions on each
kubectl get multiclusterservice baseline-services \
  -o jsonpath='{range .status.conditions[*]}{.type}: {.status} - {.message}{"\n"}{end}'
```

### Check Services on Managed Clusters

First, verify from the **management cluster** that services are being reconciled:

```bash
# Check ClusterDeployment service status
kubectl get clusterdeployments -n kcm-system

# managed-cluster-01 should show SERVICES 3/3 (cert-manager + kyverno + ingress-nginx)
# managed-cluster-02 should show SERVICES 2/2 (cert-manager + kyverno only)
```

> **Fallback:** If your managed cluster is unreachable (e.g., provisioning issues from Lab 1.5), the management-side checks above still validate that k0rdent accepted your MultiClusterService and created the expected `ServiceSet` and ProjectSveltos reconciliation objects. The key learning -- how MultiClusterService translates into provider-specific fleet reconciliation -- is visible from the management cluster alone.

If your managed cluster is accessible, verify services deployed there:

```bash
# Get kubeconfig for managed cluster
kubectl get secret managed-cluster-01-kubeconfig -n kcm-system \
  -o jsonpath='{.data.value}' | base64 -d > /tmp/managed-cluster-01.kubeconfig

# Export for convenience
export KUBECONFIG=/tmp/managed-cluster-01.kubeconfig

# Check cert-manager
kubectl get pods -n cert-manager
kubectl get certificates -A

# Check ingress-nginx
kubectl get pods -n ingress-nginx
kubectl get svc -n ingress-nginx

# Check kyverno
kubectl get pods -n kyverno
kubectl get clusterpolicies

# Return to management cluster
unset KUBECONFIG
```

### Verify ServiceSets and Sveltos Objects

In the current built-in KSM provider, k0rdent translates MultiClusterService objects into `ServiceSet` objects and ProjectSveltos resources:

```bash
# Check the ServiceSets generated by k0rdent
kubectl get servicesets -A | grep managed-cluster-01

# Check the ProjectSveltos profiles created for service rollout
kubectl get profiles -A 2>/dev/null | grep managed-cluster-01 || true
kubectl get clusterprofiles 2>/dev/null | grep managed-cluster-01 || true

# Check Sveltos status summaries
kubectl get clustersummaries -A 2>/dev/null | grep managed-cluster-01
```

## Part 6: Service Dependencies

For complex deployments, services may depend on each other. Let's explore dependency ordering.

### Understanding dependsOn

The `dependsOn` field ensures one MultiClusterService completes before another starts:

```yaml
apiVersion: k0rdent.mirantis.com/v1beta1
kind: MultiClusterService
metadata:
  name: mcs-apps
spec:
  dependsOn:
  - mcs-infrastructure  # Wait for infrastructure services first
  clusterSelector:
    matchLabels:
      environment: training
  serviceSpec:
    services:
    - template: my-app
      name: my-app
      namespace: apps
```

### Create Dependent Services Example

```bash
# Example: Apps that depend on ingress
cat << 'EOF' > /tmp/training-apps.yaml
apiVersion: k0rdent.mirantis.com/v1beta1
kind: MultiClusterService
metadata:
  name: training-apps
  namespace: kcm-system
spec:
  dependsOn:
  - training-baseline-services  # Wait for baseline (cert-manager, ingress, kyverno)
  clusterSelector:
    matchLabels:
      environment: training
      services-enabled: "true"
  serviceSpec:
    services: []  # Add your app services here
    priority: 50
EOF

# Note: This is a placeholder - in practice you'd add real app services
```

### Service Priority

Within a MultiClusterService, services deploy in order. Use `priority` to control cross-MCS ordering:

- **Higher priority (100+)**: Infrastructure services (cert-manager, ingress)
- **Medium priority (50-99)**: Platform services (monitoring, logging)
- **Lower priority (1-49)**: Application services

## Part 7: Validate Deployed Services

Let's verify each service is working correctly on the managed cluster.

### Test cert-manager

```bash
export KUBECONFIG=/tmp/managed-cluster-01.kubeconfig

# Check cert-manager is ready
kubectl get pods -n cert-manager

# Create a test certificate
cat << 'EOF' | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: test-cert
  namespace: default
spec:
  secretName: test-cert-tls
  duration: 2160h  # 90 days
  renewBefore: 360h # 15 days
  issuerRef:
    name: selfsigned-issuer
    kind: ClusterIssuer
  commonName: test.example.com
  dnsNames:
  - test.example.com
---
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned-issuer
spec:
  selfSigned: {}
EOF

# Verify certificate was issued
kubectl get certificate test-cert
kubectl get secret test-cert-tls

# Cleanup
kubectl delete certificate test-cert
kubectl delete clusterissuer selfsigned-issuer
```

### Test ingress-nginx

```bash
# Check ingress controller is running
kubectl get pods -n ingress-nginx

# Get the LoadBalancer external IP (may take a minute)
kubectl get svc -n ingress-nginx ingress-nginx-controller

# Create test deployment and ingress
kubectl create deployment nginx-test --image=nginx --replicas=1
kubectl expose deployment nginx-test --port=80

cat << 'EOF' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: nginx-test-ingress
  annotations:
    kubernetes.io/ingress.class: nginx
spec:
  rules:
  - host: nginx-test.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: nginx-test
            port:
              number: 80
EOF

# Check ingress was created
kubectl get ingress nginx-test-ingress

# Cleanup
kubectl delete ingress nginx-test-ingress
kubectl delete svc nginx-test
kubectl delete deployment nginx-test
```

### Test kyverno

```bash
# Check kyverno is running
kubectl get pods -n kyverno

# Create a simple policy
cat << 'EOF' | kubectl apply -f -
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-labels
spec:
  validationFailureAction: Audit  # Use 'Enforce' in production
  rules:
  - name: check-for-labels
    match:
      any:
      - resources:
          kinds:
          - Pod
    validate:
      message: "label 'app' is required"
      pattern:
        metadata:
          labels:
            app: "?*"
EOF

# Verify policy is active
kubectl get clusterpolicy require-labels

# Test the policy (this pod should trigger a policy event)
kubectl run test-pod --image=nginx --restart=Never

# Check policy reports
kubectl get policyreport -A

# Cleanup
kubectl delete pod test-pod
kubectl delete clusterpolicy require-labels
```

### Return to Management Cluster

```bash
unset KUBECONFIG
```

## Part 8: Update and Remove Services

Learn how to update and remove services via MultiClusterService.

### Update Service Values

```bash
# Edit the MultiClusterService to change values
kubectl edit multiclusterservice training-baseline-services -n kcm-system

# Edit the MultiClusterService to change values (recommended for targeted changes)
kubectl edit multiclusterservice baseline-services
```

> **⚠️ `--type=merge` replaces the entire `services` array!** A merge patch does not update a single entry in a list — it overwrites `spec.serviceSpec.services` with exactly what you supply. If you patched `baseline-services` with a one-entry array, every other service in it would be **silently removed** from all matched clusters. For targeted changes, prefer `kubectl edit`. If you do patch, you must include the **complete** services array — every service, including the one you're modifying.

The example below is safe because `ingress-services` contains only one service, so the complete array is that single (modified) entry. Note the values are nested under `ingress-nginx:` — the wrapper-chart rule from Part 4 applies here too:

```bash
kubectl patch multiclusterservice ingress-services --type=merge \
  -p '{"spec":{"serviceSpec":{"services":[{"template":"ingress-nginx-4-15-1","name":"ingress-nginx","namespace":"ingress-nginx","values":"ingress-nginx:\n  controller:\n    replicaCount: 2\n    service:\n      type: LoadBalancer\n"}]}}}'
```

### Remove a Service

To remove a service, edit the MultiClusterService and remove it from the services list:

```bash
# Option 1: Edit directly
kubectl edit multiclusterservice baseline-services
# Remove the service from the services array

# Option 2: Delete entire MCS (removes all services from matched clusters)
# kubectl delete multiclusterservice baseline-services
```

### ServiceTemplateChains for Upgrades

For version management, use ServiceTemplateChains:

```yaml
apiVersion: k0rdent.mirantis.com/v1beta1
kind: ServiceTemplateChain
metadata:
  name: ingress-nginx-chain
  namespace: kcm-system
spec:
  supportedTemplates:
  - name: ingress-nginx-4-15-1
  - name: ingress-nginx-4-10-0
    availableUpgrades:
    - name: ingress-nginx-4-15-1
```

## Part 9: Clean Up

If you're done with the lab and want to clean up:

### Remove MultiClusterService

```bash
# This will remove all deployed services from matched clusters
kubectl delete multiclusterservice baseline-services
kubectl delete multiclusterservice ingress-services

# Watch services being removed
export KUBECONFIG=/tmp/managed-cluster-01.kubeconfig
kubectl get pods -A -w
unset KUBECONFIG
```

### Remove ServiceTemplates (Optional)

```bash
# Delete ServiceTemplates
kubectl delete servicetemplate cert-manager-1-20-2 -n kcm-system
kubectl delete servicetemplate ingress-nginx-4-15-1 -n kcm-system
kubectl delete servicetemplate kyverno-3-8-1 -n kcm-system

# Verify removal
kubectl get servicetemplates -n kcm-system
```

## Validation Checklist

Before completing this lab, verify:

- [ ] Browsed the Service Catalog at catalog.k0rdent.io
- [ ] Installed at least 3 ServiceTemplates from catalog
- [ ] Labeled managed cluster(s) for service targeting
- [ ] Created a MultiClusterService
- [ ] Services deployed successfully to managed cluster(s)
- [ ] Tested cert-manager, ingress-nginx, and kyverno
- [ ] Understood service dependencies with dependsOn

## Summary

In this lab, you:
- Explored the k0rdent Service Catalog (100+ services)
- Installed ServiceTemplates from the catalog
- Created a MultiClusterService to deploy services at scale
- Deployed cert-manager, ingress-nginx, and kyverno
- Learned about service dependencies and ordering
- Validated services on managed clusters

## Key Concepts

| Concept | Description |
|---------|-------------|
| **Service Catalog** | External repository of validated ServiceTemplates |
| **ServiceTemplate** | CRD defining a deployable service |
| **MultiClusterService** | CRD for deploying services across multiple clusters |
| **Label Selectors** | Target clusters based on labels |
| **dependsOn** | Service ordering and dependencies |
| **ServiceTemplateChain** | Version management and upgrade paths |

## Week 1 Complete!

Congratulations on completing Week 1! You have:

1. **Lab 1.1**: Provisioned a k0rdent Enterprise management cluster
2. **Lab 1.2**: Explored the k0rdent UI and Service Catalog
3. **Lab 1.3**: Configured AWS infrastructure provider credentials
4. **Lab 1.4**: Hardened the setup for production use
5. **Lab 1.5**: Provisioned a managed Kubernetes cluster
6. **Lab 1.6**: Deployed KOF for observability and FinOps
7. **Lab 1.7**: Deployed services across clusters with MultiClusterService

You now have a solid foundation in k0rdent Enterprise for managing multi-cluster Kubernetes infrastructure.

## Next Week

Proceed to [Week 2: Bare Metal as a Service](../../week-2-bmaas/README.md) to learn how to manage bare metal infrastructure with k0rdent.
