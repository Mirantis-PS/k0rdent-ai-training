# Lab 1.2: Explore k0rdent UI and Configuration

**Duration:** 2 hours
**Type:** Hands-on Lab

## Objectives

In this lab, you will:
- Navigate the k0rdent Enterprise UI
- Understand the dashboard and key metrics
- Explore cluster templates
- Understand the external Service Catalog model
- Review management cluster configuration
- Understand credential management concepts

## Prerequisites

- Completed Lab 1.1 (k0rdent management cluster provisioned)
- SSH access to management cluster
- Web browser for UI access

## Part 1: Access the k0rdent UI

### Set up Port Forwarding

From your management cluster (SSH session):

```bash
# Enable port forwarding for the UI
kubectl port-forward svc/kcm-k0rdent-ui -n kcm-system 8080:3000 --address 0.0.0.0 &
```

From your local machine, create the SSH tunnel:

```bash
./scripts/lab-connect.sh k0rdent <your-engineer-id> --tunnel 8080:8080
```

### Access the UI

Open your browser to: `http://localhost:8080`

Login with:
- **Username:** admin
- **Password:** Run `cd lab-infrastructure/terraform/environments/k0rdent && terraform output -raw ui_password`

## Part 2: Dashboard Overview

The k0rdent dashboard provides a high-level view of your managed infrastructure.

### Key Dashboard Elements

1. **Cluster Summary**
   - Total managed clusters
   - Cluster health status
   - Resource utilization overview

2. **Recent Activity**
   - Recent deployments
   - Configuration changes
   - Alert notifications

3. **Quick Actions**
   - Create new cluster
   - Add provider credentials
   - Deploy services

### Exercise: Dashboard Exploration

Take 10 minutes to explore the dashboard:
- [ ] Identify the cluster count
- [ ] Note any alerts or warnings
- [ ] Find the resource utilization section

## Part 3: Explore Cluster Templates

Cluster templates define how Kubernetes clusters are provisioned across different infrastructure providers.

### Navigate to Templates

1. Click on **Templates** in the left navigation
2. Select **Cluster Templates**

### Understand Template Structure

Each cluster template includes:
- **Provider**: The infrastructure provider (AWS, Azure, vSphere)
- **Kubernetes Version**: Supported k8s versions
- **Node Configuration**: Default instance types, counts
- **Networking**: CNI configuration

### Exercise: Review AWS Template

Find and examine an AWS cluster template:

```bash
# From SSH session, view templates via kubectl (or use alias: kgct)
kubectl get clustertemplates -A

# Get details of a specific template (choose one from the list above)
kubectl get clustertemplate aws-standalone-cp-1-0-20 -n kcm-system -o yaml | head -100
```

> **Note:** Template names include version numbers (e.g., `aws-standalone-cp-1-0-20`). Use `kubectl get clustertemplates -A` to see available templates in your installation.

Questions to answer:
- [ ] What Kubernetes version does it deploy?
- [ ] What is the default instance type for control plane nodes?
- [ ] What CNI is configured?

## Part 4: Understanding the Service Catalog

k0rdent Enterprise uses an **external Service Catalog** model for deploying applications and services to managed clusters. ServiceTemplates still exist as Kubernetes CRDs, but the templates themselves are hosted externally and installed on-demand.

### The Service Catalog Architecture

```
+-------------------------+     +---------------------------+
|   catalog.k0rdent.io    |     |   k0rdent Management      |
|   (External Catalog)    |     |   Cluster                 |
+------------+------------+     +-------------+-------------+
             |                                |
             | helm install                   |
             +--------------->----------------+
                                              |
                              +---------------v---------------+
                              |  ServiceTemplate CRD          |
                              |  (installed in kcm-system)    |
                              +---------------+---------------+
                                              |
                              +---------------v---------------+
                              |  MultiClusterService          |
                              |  (deploys to managed clusters)|
                              +-------------------------------+
```

### Browse the Service Catalog

Open your browser to: **https://catalog.k0rdent.io/**

The catalog provides **150+ validated services** across categories:

| Category | Example Services |
|----------|-----------------|
| **AI/Machine Learning** | NVIDIA GPU Operator, KubeRay, KServe, MLflow |
| **Networking** | ingress-nginx, Cilium, Istio, MetalLB, cert-manager |
| **Security** | Kyverno, External Secrets, Falco, Gatekeeper |
| **Storage & Databases** | PostgreSQL Operator, MinIO, Milvus (vector DB) |
| **Monitoring** | Grafana, kube-prometheus-stack, VictoriaMetrics, OpenCost |
| **CI/CD** | Argo CD, GitLab, Harbor |

> **Enterprise Services:** Some services are marked as "Enterprise-only" (e.g., Ceph, StackLight, MSR). These are available exclusively with k0rdent Enterprise.

### Exercise: Explore the Catalog

Take 10 minutes to browse the catalog:
- [ ] Find the ingress-nginx service and note its available versions
- [ ] Locate the AI/Machine Learning category
- [ ] Identify at least one Enterprise-only service

### Check Currently Installed ServiceTemplates

```bash
# List any ServiceTemplates already installed
kubectl get servicetemplates -A

# You may see minimal or no templates - this is expected!
# Templates are installed from the catalog as needed
```

### Install a ServiceTemplate from the Catalog

To use a service, you first install its ServiceTemplate from the catalog:

```bash
# Example: Install the ingress-nginx ServiceTemplate
helm install ingress-nginx-service-template \
  oci://ghcr.io/k0rdent/catalog/charts/ingress-nginx-service-template \
  --version 4.11.0 \
  -n kcm-system

# Verify it's now available
kubectl get servicetemplates -n kcm-system
```

> **Note:** We'll cover deploying services to managed clusters in detail in **Lab 1.7: Multi-Cluster Service Deployment**.

### ServiceTemplate Structure

Once installed, examine a ServiceTemplate:

```bash
# View the installed ServiceTemplate
kubectl get servicetemplate ingress-nginx-4-11-0 -n kcm-system -o yaml
```

Key fields:
- **spec.helm.chartSpec**: References the Helm chart to deploy
- **spec.helm.chartSpec.sourceRef**: Points to the HelmRepository

### Why External Catalog?

| Aspect | Bundled Templates (Old) | External Catalog (Current) |
|--------|------------------------|---------------------------|
| **Updates** | Tied to k0rdent releases | Updated independently |
| **Selection** | Limited set | 150+ services |
| **Customization** | Difficult | Easy version selection |
| **Enterprise** | Mixed | Clear Enterprise-only marking |

## Part 5: Management Cluster Configuration

The management cluster is the control plane for all k0rdent operations.

### View Management Configuration

```bash
# Get management cluster object (or use alias: kgm)
kubectl get management -A

# View detailed configuration
kubectl get management kcm -n kcm-system -o yaml
```

### Key Configuration Elements

1. **Core Components**
   - KCM (Cluster Manager)
   - Cert Manager integration
   - Flux CD for GitOps

2. **Provider Configuration**
   - Which infrastructure providers are enabled
   - Provider-specific settings

3. **Feature Gates**
   - Experimental features
   - Beta capabilities

### Exercise: Document Current Configuration

Create a summary of your management cluster:
- [ ] List enabled providers
- [ ] Note the k0rdent version
- [ ] Identify any custom configurations

## Part 6: Credential Management

k0rdent manages credentials for accessing infrastructure providers securely.

### Understand Credential Flow

```
+-------------------+     +-------------------+     +-------------------+
|  User provides    | --> |  k0rdent stores   | --> |  Cluster API uses |
|  cloud creds      |     |  as K8s secrets   |     |  for provisioning |
+-------------------+     +-------------------+     +-------------------+
```

### View Existing Credentials

```bash
# List credential objects (or use alias: kgcred)
kubectl get credentials -A

# List related secrets
kubectl get secrets -n kcm-system | grep credential
```

### Credential Types

1. **AWS Credentials**
   - Access Key ID and Secret
   - IAM Role for cross-account access

2. **Azure Credentials**
   - Service Principal credentials
   - Subscription and tenant information

3. **vSphere Credentials**
   - vCenter server address
   - Username/password or API token

## Part 7: kubectl CLI Exploration

Beyond the UI, kubectl provides powerful access to k0rdent resources.

### Essential Commands

```bash
# View all k0rdent custom resources (CRDs use k0rdent.mirantis.com domain)
kubectl api-resources | grep k0rdent.mirantis.com

# List all k0rdent CRDs
kubectl get crds | grep k0rdent.mirantis.com

# List cluster deployments (or use alias: kgcd)
kubectl get clusterdeployments -A

# View cluster deployment details
kubectl describe clusterdeployment <cluster-name> -n <namespace>

# Check cluster deployment status
kubectl get clusterdeployment <cluster-name> -n <namespace> -o jsonpath='{.status}'
```

### Pre-configured Aliases

Your lab environment includes helpful aliases (defined in `/etc/profile.d/k0rdent-lab.sh`):

| Alias | Command | Description |
|-------|---------|-------------|
| `k` | `kubectl` | Short kubectl |
| `kgp` | `kubectl get pods` | List pods |
| `kgn` | `kubectl get nodes` | List nodes |
| `kgaa` | `kubectl get all -A` | All resources, all namespaces |
| `kgm` | `kubectl get management -A` | k0rdent management objects |
| `kgcd` | `kubectl get clusterdeployment -A` | Cluster deployments |
| `kgct` | `kubectl get clustertemplates -A` | Cluster templates |
| `kgcred` | `kubectl get credentials -A` | Credentials |

```bash
# Try the aliases
kgm          # Get management objects
kgct         # Get cluster templates
kgcred       # Get credentials
```

> **Tip:** Type `alias` to see all available aliases.

## Part 8: Configuration Best Practices

### Production Recommendations

1. **High Availability**
   - Deploy 3-node management cluster for HA
   - Use etcd backup/restore procedures

2. **Security**
   - Enable RBAC policies
   - Use OIDC for authentication
   - Rotate credentials regularly

3. **Monitoring**
   - Enable KOF (k0rdent Observability & FinOps)
   - Set up alerting
   - Monitor cluster health

### Documentation Exercise

Document your management cluster setup:

```markdown
## My k0rdent Management Cluster

- **Engineer ID:** [your-id]
- **k0rdent Version:** 1.2.1
- **k0s Version:** v1.32.4
- **Instance Type:** t3.xlarge
- **Region:** [your-region]

### Installed Components
- [ ] KCM (Cluster Manager)
- [ ] Cert Manager
- [ ] k0rdent UI
- [ ] Flux CD

### Enabled Providers
- [ ] AWS
- [ ] Azure
- [ ] vSphere
```

## Validation Checklist

Before completing this lab, verify:

- [ ] Successfully logged into k0rdent UI
- [ ] Explored dashboard and understood key metrics
- [ ] Reviewed at least one cluster template
- [ ] Browsed the Service Catalog at catalog.k0rdent.io
- [ ] Understood the external catalog model for ServiceTemplates
- [ ] Understood management cluster configuration
- [ ] Learned credential management concepts
- [ ] Practiced kubectl commands for k0rdent resources

## Summary

In this lab, you:
- Navigated the k0rdent Enterprise UI
- Explored cluster templates
- Learned about the external Service Catalog model (catalog.k0rdent.io)
- Reviewed management cluster configuration
- Understood credential management flow
- Practiced kubectl commands for k0rdent

## Next Lab

Continue to [Lab 1.3: Configure AWS Provider](lab-1.3-configure-aws-provider.md)
