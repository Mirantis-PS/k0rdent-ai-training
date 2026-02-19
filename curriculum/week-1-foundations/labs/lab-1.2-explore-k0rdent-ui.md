# Lab 1.2: Explore k0rdent UI and Configuration

**Duration:** 2.5 hours
**Type:** Hands-on Lab

## Objectives

In this lab, you will:
- Navigate the k0rdent Enterprise UI
- Understand how the UI is exposed (training vs. production)
- Understand the dashboard and key metrics
- Explore cluster templates
- Understand the external Service Catalog model
- Review management cluster configuration
- Understand credential management concepts

## Prerequisites

- Completed Lab 1.1 (k0rdent management cluster provisioned)
- SSH access to management cluster
- Web browser for UI access

## Resuming This Lab

If your SSH session dropped or you're returning the next day:

```bash
cd lab-infrastructure
./scripts/lab-connect.sh k0rdent <your-engineer-id> --region <your-region>
kubectl get nodes && kubectl get pods -n kcm-system
```

---

## Part 1: Access the k0rdent UI

The k0rdent UI is exposed via a Network Load Balancer (NLB) and accessible directly from your browser.

### Get the URL and Login

From your local machine:

```bash
cd lab-infrastructure/terraform/environments/k0rdent

# Get the UI URL
terraform output ui_url

# Get the UI password
terraform output -raw ui_password
```

Open the URL in your browser and login with:
- **Username:** `admin`
- **Password:** the output from the command above

> **Tip:** You can also run `./scripts/lab-connect.sh k0rdent <your-engineer-id> --region <your-region> --show-password` to retrieve the password.

## Part 2: Understanding k0rdent UI Access Architecture

Now that you've accessed the UI, let's understand how the k0rdent UI is exposed to your browser, why the training lab uses a simplified approach, and how to do it properly in a production enterprise environment.

### The k0rdent UI Service

The k0rdent UI is a web application deployed as a Pod in the `kcm-system` namespace. By default, k0rdent creates a **ClusterIP** Service (`kcm-k0rdent-ui`) on port 3000:

```bash
# Inspect the UI service (from your SSH session)
kubectl get svc kcm-k0rdent-ui -n kcm-system -o wide
```

A ClusterIP service is only reachable from **inside** the cluster. This is the default for good reason — the management UI should not be casually exposed to the internet. The official k0rdent documentation describes two access methods:

1. **`kubectl port-forward`** — forward the service port to your local machine
2. **Kubernetes Ingress** — create an Ingress resource to route external HTTP(S) traffic to the service

### How the Training Lab Exposes the UI

For this training environment, we use a simplified approach to avoid the complexity of deploying an ingress controller:

```
Your Browser
    │
    │ HTTP (:80)
    ▼
┌───────────────────┐
│  Network Load     │  Terraform-managed (aws_lb)
│  Balancer (NLB)   │
└────────┬──────────┘
         │
         │ TCP → NodePort :30080
         ▼
┌───────────────────┐
│  k0rdent UI Pod   │  Patched from ClusterIP to NodePort
│  (kcm-system)     │  after Helm installation
└───────────────────┘
```

The training lab cloud-init script patches the ClusterIP service to a NodePort after k0rdent installs:

```bash
# This runs automatically during provisioning (you don't need to run this)
kubectl patch svc kcm-k0rdent-ui -n kcm-system \
  -p '{"spec":{"type":"NodePort","ports":[{"port":3000,"targetPort":3000,"nodePort":30080,"protocol":"TCP"}]}}'
```

A Terraform-managed NLB then routes external traffic on port 80 to NodePort 30080 on the EC2 instance.

**Why this is acceptable for training but not for production:**

| Concern | Training Lab | Production |
|---------|-------------|------------|
| **TLS** | HTTP only (no encryption) | HTTPS with valid certificates required |
| **Authentication** | Basic auth (username/password) | OIDC with corporate identity provider |
| **Service ownership** | `kubectl patch` modifies a Helm-managed resource | Separate Ingress resource, no conflict |
| **Reconciliation** | Works because initial install is direct `helm install`, not Flux-managed | Flux/KCM would revert manual patches |
| **DNS** | Raw NLB hostname | Proper DNS record (e.g., `k0rdent.company.com`) |
| **Access control** | Open to anyone with the URL | Network policies, WAF, IP allowlists |

### Production Architecture: Ingress + TLS + OIDC

In a production enterprise environment, the k0rdent UI should be exposed through a **Kubernetes Ingress** backed by an ingress controller, with TLS termination and OIDC authentication. This pattern works across all infrastructure providers — AWS, Azure, vSphere, bare metal:

```
User Browser
    │
    │ HTTPS (k0rdent.company.com)
    ▼
┌──────────────────────┐
│  Load Balancer       │  Cloud LB (NLB/ALB/Azure LB) or MetalLB
│  (L4 or L7)         │
└──────────┬───────────┘
           │
           │ :443
           ▼
┌──────────────────────┐
│  Ingress Controller  │  ingress-nginx, deployed via k0rdent
│  (ingress-nginx)     │  Service Catalog
└──────────┬───────────┘
           │
           │ Ingress routing rule
           ▼
┌──────────────────────┐
│  kcm-k0rdent-ui      │  ClusterIP :3000 (untouched)
│  (kcm-system)        │
└──────────────────────┘
```

The key principle: **never modify the service managed by the Helm chart**. Instead, layer infrastructure on top of it. The Ingress resource is yours to manage — k0rdent's reconciliation loop only owns the `kcm-k0rdent-ui` Service, not your Ingress.

#### Step 1: Deploy an Ingress Controller via the Service Catalog

k0rdent's own Service Catalog provides `ingress-nginx` as a ServiceTemplate. You can deploy it to the management cluster itself using a `MultiClusterService`:

```yaml
# Install the ingress-nginx ServiceTemplate from the catalog
# (See Part 5 of this lab for Service Catalog details)

# Then deploy it to the management cluster using MultiClusterService:
apiVersion: k0rdent.mirantis.com/v1beta1
kind: MultiClusterService
metadata:
  name: mgmt-ingress
spec:
  clusterSelector:
    matchLabels:
      k0rdent.mirantis.com/management-cluster: "true"
      sveltos-agent: present
  serviceSpec:
    services:
      - template: ingress-nginx-4-11-3
        name: ingress-nginx
        namespace: ingress-nginx
```

This is the k0rdent-native way to deploy services to the management cluster. Alternatively, deploy ingress-nginx directly via Helm during provisioning if you want tighter control over the installation timing.

#### Step 2: Create an Ingress Resource for the UI

Once the ingress controller is running, create an Ingress resource that routes traffic to the k0rdent UI service:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: k0rdent-ui
  namespace: kcm-system
  annotations:
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - k0rdent.company.com
      secretName: k0rdent-ui-tls    # Provided by cert-manager or manually
  rules:
    - host: k0rdent.company.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: kcm-k0rdent-ui
                port:
                  number: 3000
```

This Ingress resource is **not managed by k0rdent's Helm chart** — it's a separate resource you control. The KCM operator will never touch it, so there is no reconciliation conflict.

#### Step 3: TLS Certificates

For TLS, you have several options depending on your environment:

| Method | Best For | How |
|--------|----------|-----|
| **cert-manager + Let's Encrypt** | Internet-facing clusters | Deploy cert-manager (available in Service Catalog), annotate the Ingress with `cert-manager.io/cluster-issuer` |
| **Cloud provider certificates** | AWS (ACM), Azure (Key Vault) | Terminate TLS at the load balancer level, before traffic reaches the ingress controller |
| **Corporate CA** | Enterprise environments | Create a TLS Secret from your internal CA certificate and key, reference it in the Ingress `tls.secretName` |

Example with cert-manager (provider-agnostic):

```yaml
# ClusterIssuer for Let's Encrypt
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: platform-team@company.com
    privateKeySecretRef:
      name: letsencrypt-prod-key
    solvers:
      - http01:
          ingress:
            class: nginx
```

Then add the annotation to your Ingress:

```yaml
metadata:
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
```

cert-manager will automatically provision and renew the TLS certificate.

#### Step 4: OIDC Authentication (Replace Basic Auth)

For production, replace basic auth with OIDC to integrate with your corporate identity provider (Okta, Azure AD/Entra ID, Google Workspace, etc.). The k0rdent UI supports OIDC natively via the Management custom resource:

```yaml
apiVersion: k0rdent.mirantis.com/v1beta1
kind: Management
metadata:
  name: kcm
  namespace: kcm-system
spec:
  core:
    kcm:
      config:
        k0rdent-ui:
          enabled: true
          auth:
            oidc:
              issuerUrl: "https://login.microsoftonline.com/<tenant-id>/v2.0"
              clientId: "<your-client-id>"
              clientSecret: "<your-client-secret>"
```

The Management object's `spec.core.kcm.config` section is passed as Helm values to the k0rdent deployment. The `k0rdent-ui` key maps to the UI subchart, and `auth.oidc` replaces `auth.basic` entirely.

> **Note:** The OIDC configuration above is for the **k0rdent UI application** itself. k0rdent also supports OIDC for the **Kubernetes API server** (for kubectl access) using the `StructuredAuthenticationConfiguration` feature gate — see the [k0rdent Authentication documentation](https://docs.k0rdent.io/latest/admin/installation/auth/) for details on Okta and Entra ID integration.

#### Step 5: DNS

Point a DNS record at your load balancer. This is provider-specific:

- **AWS**: Route53 alias record pointing to the NLB/ALB
- **Azure**: Azure DNS A record or CNAME
- **vSphere/Bare Metal**: Internal DNS (CoreDNS, BIND, or Active Directory DNS)
- **Any cloud**: External-dns controller can automate this from Ingress annotations

#### Complete Production Checklist

- [ ] Ingress controller deployed (via Service Catalog or Helm)
- [ ] TLS certificates provisioned (cert-manager, cloud provider, or internal CA)
- [ ] Ingress resource created in `kcm-system` namespace
- [ ] OIDC configured in the Management object (replacing basic auth)
- [ ] DNS record pointing to load balancer
- [ ] Network policies restricting UI access to corporate networks
- [ ] k0rdent UI ClusterIP service left **untouched** (no patches)

### Exercise: Examine the Training Lab Setup

From your SSH session, compare the training setup with what a production deployment would look like:

```bash
# 1. Check the current service type (should show NodePort in training)
kubectl get svc kcm-k0rdent-ui -n kcm-system -o jsonpath='{.spec.type}'
echo

# 2. Check if an ingress controller exists (none in training lab)
kubectl get pods -A | grep ingress || echo "No ingress controller deployed"

# 3. View the Management object's UI configuration
kubectl get management kcm -n kcm-system -o jsonpath='{.spec.core.kcm.config}' | jq . 2>/dev/null || echo "Default config (no customization)"

# 4. Check for any Ingress resources (none in training lab)
kubectl get ingress -A || echo "No Ingress resources"
```

Questions to answer:
- [ ] What service type is the k0rdent UI using in this training environment?
- [ ] Why would a `kubectl patch` on a Helm-managed service be reverted in a Flux-managed deployment?
- [ ] What are two advantages of using an Ingress resource over NodePort + NLB?
- [ ] Why is OIDC preferred over basic auth in an enterprise setting?

---

## Part 3: Dashboard Overview

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

## Part 4: Explore Cluster Templates

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
# From SSH session, list all available templates (or use alias: kgct)
kubectl get clustertemplates -n kcm-system

# Find the AWS standalone control plane template
AWS_TEMPLATE=$(kubectl get clustertemplates -n kcm-system -o name | grep aws-standalone-cp | head -1)
echo "Found template: $AWS_TEMPLATE"

# Get details of the template
kubectl get $AWS_TEMPLATE -n kcm-system -o yaml | head -100
```

> **Note:** Template names include version numbers (e.g., `aws-standalone-cp-1-0-20`) that change between k0rdent releases. Always list templates first rather than hardcoding names.

Questions to answer:
- [ ] What Kubernetes version does it deploy?
- [ ] What is the default instance type for control plane nodes?
- [ ] What CNI is configured?

## Part 5: Understanding the Service Catalog

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

## Part 6: Management Cluster Configuration

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

## Part 7: Credential Management

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

## Part 8: kubectl CLI Exploration

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

## Part 9: Configuration Best Practices

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
- [ ] Understood how the training lab exposes the UI (NLB + NodePort)
- [ ] Can explain the production approach (Ingress + TLS + OIDC)
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
- Learned how the UI is exposed in training (NLB + NodePort) vs. production (Ingress + TLS + OIDC)
- Explored cluster templates
- Learned about the external Service Catalog model (catalog.k0rdent.io)
- Reviewed management cluster configuration
- Understood credential management flow
- Practiced kubectl commands for k0rdent

## Next Lab

Continue to [Lab 1.3: Configure AWS Provider](lab-1.3-configure-aws-provider.md)
