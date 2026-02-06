# Lab 1.7: Multi-Cluster Service Deployment

**Duration:** 2-3 hours
**Type:** Hands-on Lab

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
./scripts/lab-connect.sh k0rdent <your-engineer-id>
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

The catalog organizes 150+ services into categories:

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

ServiceTemplates must be installed on the management cluster before they can be deployed.

### Check Existing ServiceTemplates

```bash
# List any existing ServiceTemplates
kubectl get servicetemplates -n kcm-system

# You may see few or none - this is expected
```

### Install cert-manager ServiceTemplate

```bash
# Install cert-manager ServiceTemplate
helm install cert-manager-service-template \
  oci://ghcr.io/k0rdent/catalog/charts/cert-manager-service-template \
  --version 1.16.2 \
  -n kcm-system

# Verify installation
kubectl get servicetemplate -n kcm-system | grep cert-manager
```

### Install ingress-nginx ServiceTemplate

```bash
# Install ingress-nginx ServiceTemplate
helm install ingress-nginx-service-template \
  oci://ghcr.io/k0rdent/catalog/charts/ingress-nginx-service-template \
  --version 4.11.0 \
  -n kcm-system

# Verify installation
kubectl get servicetemplate -n kcm-system | grep ingress-nginx
```

### Install kyverno ServiceTemplate

```bash
# Install kyverno ServiceTemplate
helm install kyverno-service-template \
  oci://ghcr.io/k0rdent/catalog/charts/kyverno-service-template \
  --version 3.2.6 \
  -n kcm-system

# Verify installation
kubectl get servicetemplate -n kcm-system | grep kyverno
```

### Verify All Templates

```bash
# List all installed ServiceTemplates
kubectl get servicetemplates -n kcm-system

# Expected output:
# NAME                    AGE
# cert-manager-1-16-2     1m
# ingress-nginx-4-11-0    1m
# kyverno-3-2-6           1m
```

### Examine a ServiceTemplate

```bash
# View the structure of a ServiceTemplate
kubectl get servicetemplate cert-manager-1-16-2 -n kcm-system -o yaml
```

Key fields:
- `spec.helm.chartSpec.chart`: The Helm chart name
- `spec.helm.chartSpec.version`: Chart version
- `spec.helm.chartSpec.sourceRef`: Reference to HelmRepository

## Part 3: Label Clusters for Service Targeting

MultiClusterService uses label selectors to target clusters. Let's label our managed cluster(s).

### Check Current Cluster Labels

```bash
# View current ClusterDeployment labels
kubectl get clusterdeployment -n kcm-system --show-labels
```

### Add Labels for Service Targeting

```bash
# Label managed-cluster-01 for training environment
kubectl label clusterdeployment managed-cluster-01 \
  environment=training \
  tier=standard \
  services-enabled=true \
  -n kcm-system

# If you have a second cluster, label it too
# kubectl label clusterdeployment managed-cluster-02 \
#   environment=training \
#   tier=standard \
#   services-enabled=true \
#   -n kcm-system
```

### Verify Labels

```bash
# Confirm labels are applied
kubectl get clusterdeployment -n kcm-system -l environment=training

# Should list managed-cluster-01 (and -02 if created)
```

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

### Create the MultiClusterService

```bash
cat << 'EOF' > /tmp/training-services.yaml
apiVersion: k0rdent.mirantis.com/v1beta1
kind: MultiClusterService
metadata:
  name: training-baseline-services
  namespace: kcm-system
spec:
  clusterSelector:
    matchLabels:
      environment: training
      services-enabled: "true"
  serviceSpec:
    services:
    # cert-manager - Foundation for TLS
    - template: cert-manager-1-16-2
      name: cert-manager
      namespace: cert-manager
      values: |
        installCRDs: true
        prometheus:
          enabled: true

    # ingress-nginx - Ingress controller
    - template: ingress-nginx-4-11-0
      name: ingress-nginx
      namespace: ingress-nginx
      values: |
        controller:
          replicaCount: 1
          service:
            type: LoadBalancer
          metrics:
            enabled: true

    # kyverno - Policy engine
    - template: kyverno-3-2-6
      name: kyverno
      namespace: kyverno
      values: |
        replicaCount: 1
        backgroundController:
          enabled: true

    priority: 100
EOF

# Apply the MultiClusterService
kubectl apply -f /tmp/training-services.yaml
```

### Verify MultiClusterService

```bash
# Check MCS status
kubectl get multiclusterservice -n kcm-system

# View detailed status
kubectl describe multiclusterservice training-baseline-services -n kcm-system
```

## Part 5: Monitor Service Deployment

Services deploy asynchronously to all matched clusters. Monitor the progress.

### Watch MultiClusterService Status

```bash
# Watch for status updates
kubectl get multiclusterservice training-baseline-services -n kcm-system -w

# Check conditions
kubectl get multiclusterservice training-baseline-services -n kcm-system \
  -o jsonpath='{.status.conditions}' | jq
```

### Check Services on Managed Cluster

First, verify from the **management cluster** that the MCS is being reconciled:

```bash
# Check MCS status and conditions (works even without managed cluster access)
kubectl get multiclusterservice training-baseline-services -n kcm-system -o yaml | grep -A 5 "conditions:"

# Check if HelmReleases were created for the managed cluster
kubectl get helmreleases -A | grep managed-cluster-01
```

> **Fallback:** If your managed cluster is unreachable (e.g., provisioning issues from Lab 1.5), the management-side checks above still validate that k0rdent accepted your MultiClusterService and created the correct HelmRelease objects. The key learning -- how MCS translates to per-cluster HelmReleases via label selectors -- is visible from the management cluster alone.

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

### Verify HelmReleases

k0rdent uses Flux CD to manage Helm releases:

```bash
# On management cluster, check HelmReleases for the managed cluster
kubectl get helmreleases -A | grep managed-cluster-01
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

# Or use patch
kubectl patch multiclusterservice training-baseline-services -n kcm-system \
  --type=merge -p '{"spec":{"serviceSpec":{"services":[{"template":"ingress-nginx-4-11-0","name":"ingress-nginx","namespace":"ingress-nginx","values":"controller:\n  replicaCount: 2\n"}]}}}'
```

### Remove a Service

To remove a service, edit the MultiClusterService and remove it from the services list:

```bash
# Option 1: Edit directly
kubectl edit multiclusterservice training-baseline-services -n kcm-system
# Remove the service from the services array

# Option 2: Delete entire MCS (removes all services)
# kubectl delete multiclusterservice training-baseline-services -n kcm-system
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
  - name: ingress-nginx-4-11-0
  - name: ingress-nginx-4-10-0
    availableUpgrades:
    - name: ingress-nginx-4-11-0
```

## Part 9: Clean Up

If you're done with the lab and want to clean up:

### Remove MultiClusterService

```bash
# This will remove all deployed services from matched clusters
kubectl delete multiclusterservice training-baseline-services -n kcm-system

# Watch services being removed
export KUBECONFIG=/tmp/managed-cluster-01.kubeconfig
kubectl get pods -A -w
unset KUBECONFIG
```

### Remove ServiceTemplates (Optional)

```bash
# Uninstall ServiceTemplates
helm uninstall cert-manager-service-template -n kcm-system
helm uninstall ingress-nginx-service-template -n kcm-system
helm uninstall kyverno-service-template -n kcm-system

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
- Explored the k0rdent Service Catalog (150+ services)
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
