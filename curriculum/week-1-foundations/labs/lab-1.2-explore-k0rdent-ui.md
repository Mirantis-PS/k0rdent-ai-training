# Lab 1.2: Explore k0rdent UI and Configuration

**Duration:** 2.5 hours
**Type:** Hands-on Lab

## Objectives

In this lab, you will:
- Navigate the k0rdent Enterprise UI
- Understand how the UI is exposed via Envoy Gateway and the Gateway API
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
./scripts/lab-connect.sh <your-engineer-id>
kubectl get nodes && kubectl get pods -n kcm-system
```

---

## Part 1: Access the k0rdent UI

The k0rdent UI is exposed via **Envoy Gateway** (using the Kubernetes Gateway API) and accessible directly from your browser.

### Get the URL and Login

The UI URL was printed at the end of provisioning. To retrieve it again:

```bash
# Get the UI URL and credentials
./scripts/lab-connect.sh <your-engineer-id> --ui-url
```

Open the URL in your browser and login with:
- **Username:** `admin`
- **Password:** shown in the command output above

> **Tip:** To see the full Gateway API resource status, run `./scripts/lab-connect.sh <your-engineer-id> --show-gateway`.

## Part 2: Understanding k0rdent UI Access Architecture

### How the UI is Exposed

k0rdent Enterprise exposes its UI through the **Kubernetes Gateway API** using **Envoy Gateway** as the implementation.

#### Training Lab Architecture

```
Student Browser (HTTP)
    │
    ▼
AWS NLB (auto-provisioned by AWS Cloud Controller Manager)
    │ port 80
    ▼
Envoy Gateway (envoy-gateway-system namespace)
    │ Gateway listener on port 80
    ▼
HTTPRoute (kcm-system namespace)
    │ path: / → kcm-k0rdent-ui:3000
    ▼
k0rdent UI Pod (ClusterIP, Helm-managed)
```

**Key resources:**

| Resource | Name | Namespace | Purpose |
|----------|------|-----------|---------|
| GatewayClass | `envoy-gateway` | cluster-scoped | Defines Envoy Gateway as the controller |
| Gateway | `k0rdent-gateway` | `kcm-system` | Listens on port 80 (HTTP) |
| HTTPRoute | `k0rdent-ui` | `kcm-system` | Routes `/` to `kcm-k0rdent-ui:3000` |

#### Exercise: Examine the Training Setup

```bash
# View the GatewayClass (cluster-scoped)
kubectl get gatewayclass envoy-gateway -o yaml

# View the Gateway and its LoadBalancer address
kubectl get gateway k0rdent-gateway -n kcm-system -o yaml

# View the HTTPRoute
kubectl get httproute k0rdent-ui -n kcm-system -o yaml

# View the auto-provisioned Envoy proxy pods
kubectl get pods -n envoy-gateway-system

# View the LoadBalancer service (created by Envoy Gateway controller)
kubectl get svc -n envoy-gateway-system
```

> **Discussion:** Notice how the original `kcm-k0rdent-ui` ClusterIP service is untouched — Envoy Gateway routes to it directly. This means the Helm chart can reconcile freely without affecting external access.

### Production Upgrade Path

The training lab uses HTTP with basic auth. Production deployments add **TLS termination** and **OIDC authentication** to the same Gateway resources.

#### Step 1: Add TLS to the Gateway

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: k0rdent-gateway
  namespace: kcm-system
spec:
  gatewayClassName: envoy-gateway
  listeners:
    - name: https
      protocol: HTTPS
      port: 443
      tls:
        mode: Terminate
        certificateRefs:
          - kind: Secret
            name: k0rdent-ui-tls
```

#### Step 2: Configure OIDC Authentication

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

#### Production Checklist

- [ ] TLS certificates provisioned (see TLS patterns below)
- [ ] Gateway listener updated to HTTPS (port 443)
- [ ] OIDC configured in the Management object
- [ ] DNS record pointing to the LoadBalancer address
- [ ] Network policies restricting UI access to corporate networks
- [ ] HTTP → HTTPS redirect configured (optional HTTPRoute)

### Alternative Deployment Patterns

Different customer environments require different approaches to LoadBalancer provisioning. The Gateway API resources (GatewayClass, Gateway, HTTPRoute) stay the same — only the infrastructure layer changes.

#### Envoy Gateway + AWS CCM (Training Default)

Used in the training lab. AWS Cloud Controller Manager auto-provisions a Network Load Balancer when the Gateway creates a `type: LoadBalancer` service.

**When to use:** AWS cloud environments with CCM configured.

**How it works:** Install Envoy Gateway → create Gateway → CCM provisions NLB automatically.

#### Envoy Gateway + MetalLB

For on-premises or bare-metal environments without a cloud LoadBalancer.

**When to use:** On-prem data centers, bare-metal clusters, home labs.

```bash
# Install MetalLB
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.9/config/manifests/metallb-native.yaml

# Configure IP pool
cat <<EOF | kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: lab-pool
  namespace: metallb-system
spec:
  addresses:
    - 192.168.1.240-192.168.1.250
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: lab-l2
  namespace: metallb-system
EOF
```

The Gateway and HTTPRoute resources remain identical — MetalLB assigns an IP from the pool instead of a cloud NLB hostname.

#### Envoy Gateway + NodePort + External Load Balancer

For restricted cloud environments where CCM is not available or LoadBalancer services are not permitted.

**When to use:** Air-gapped environments, restricted cloud accounts, environments behind an existing external load balancer.

```yaml
# Override Envoy Gateway's service type via Helm values
# helm install envoy-gateway ... --set service.type=NodePort
```

Then configure the external load balancer to route to the NodePort allocated by Kubernetes.

#### kubectl port-forward

For quick local access without any infrastructure.

**When to use:** Developer laptops, quick debugging, temporary access.

```bash
kubectl port-forward svc/kcm-k0rdent-ui -n kcm-system 8080:3000
# Access at http://localhost:8080
```

No Gateway needed — direct access to the ClusterIP service.

### TLS Configuration Patterns

All patterns configure TLS at the Gateway listener level. The HTTPRoute and backend service remain unchanged.

#### cert-manager + Let's Encrypt

Automated certificate issuance and renewal. Best for public-facing deployments.

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: ops@company.com
    privateKeySecretRef:
      name: letsencrypt-prod-key
    solvers:
      - http01:
          gatewayHTTPRoute:
            parentRefs:
              - name: k0rdent-gateway
                namespace: kcm-system
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: k0rdent-ui-tls
  namespace: kcm-system
spec:
  secretName: k0rdent-ui-tls
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  dnsNames:
    - k0rdent.company.com
```

#### cert-manager + Internal CA

For enterprises with existing PKI infrastructure.

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: internal-ca
spec:
  ca:
    secretName: internal-ca-key-pair
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: k0rdent-ui-tls
  namespace: kcm-system
spec:
  secretName: k0rdent-ui-tls
  issuerRef:
    name: internal-ca
    kind: ClusterIssuer
  dnsNames:
    - k0rdent.company.com
```

#### AWS ACM (via NLB Annotation)

AWS-native approach — no in-cluster cert management. TLS terminates at the NLB.

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: k0rdent-gateway
  namespace: kcm-system
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-ssl-cert: "arn:aws:acm:us-east-1:123456:certificate/abc-123"
    service.beta.kubernetes.io/aws-load-balancer-ssl-ports: "443"
spec:
  gatewayClassName: envoy-gateway
  listeners:
    - name: https
      protocol: HTTPS
      port: 443
```

> **Note:** With ACM, TLS terminates at the NLB. Traffic between NLB and Envoy Gateway is unencrypted inside the VPC. For end-to-end encryption, use cert-manager instead.

#### Manual TLS Secret

Bring your own certificate from any source.

```bash
kubectl create secret tls k0rdent-ui-tls \
  --cert=path/to/tls.crt \
  --key=path/to/tls.key \
  -n kcm-system
```

Then reference `k0rdent-ui-tls` in the Gateway's TLS listener configuration (same as the cert-manager examples above).

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

The catalog provides **100+ validated services** across categories:

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
- [ ] Find the Kyverno service and note its available versions
- [ ] Locate the AI/Machine Learning category
- [ ] Identify at least one Enterprise-only service

### Check Currently Installed ServiceTemplates

```bash
# List any ServiceTemplates already installed
kubectl get servicetemplates -A

# You may see minimal or no templates - this is expected!
# Templates are installed from the catalog as needed
```

### Install a ServiceTemplate

A ServiceTemplate is a YAML manifest that tells k0rdent which Helm chart to deploy and where to find it. It references a **HelmRepository** — a Flux source object that points to an OCI registry containing Helm charts.

Two resources are needed:
1. **HelmRepository** — connects k0rdent to the external catalog (`ghcr.io/k0rdent/catalog/charts`)
2. **ServiceTemplate** — declares which chart and version to make available

#### Step 1: Create the Catalog HelmRepository

```bash
# Connect k0rdent to the external service catalog
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

```bash
# Verify the repository is ready
kubectl get helmrepositories -n kcm-system
```

> **What this does:** Creates a Flux HelmRepository that points to the k0rdent community catalog. The `k0rdent.mirantis.com/managed: "true"` label tells k0rdent to track this repository. Once created, any ServiceTemplate can reference charts from this catalog.

#### Step 2: Create a ServiceTemplate

Let's install **Kyverno** (a Kubernetes-native policy engine) as our example:

```bash
# Create a ServiceTemplate for Kyverno
cat <<EOF | kubectl apply -f -
apiVersion: k0rdent.mirantis.com/v1beta1
kind: ServiceTemplate
metadata:
  name: kyverno-3-2-6
  namespace: kcm-system
  annotations:
    helm.sh/resource-policy: keep
spec:
  helm:
    chartSpec:
      chart: kyverno
      version: 3.2.6
      interval: 10m0s
      sourceRef:
        kind: HelmRepository
        name: k0rdent-catalog
EOF
```

```bash
# Verify it's installed and valid (may take ~30s for Flux to fetch the chart)
kubectl get servicetemplates -n kcm-system
```

You should see:
```
NAME            VALID   AGE
kyverno-3-2-6   true    30s
```

> **If VALID shows `false`:** Wait 30 seconds and check again. Flux needs to fetch the chart metadata from the OCI registry to validate the ServiceTemplate.

### View the ServiceTemplate in the UI

1. Open the k0rdent UI in your browser
2. Navigate to **Templates** in the left sidebar
3. Switch to the **Service Templates** tab
4. You should see `kyverno-3-2-6` listed with its chart version and validation status

This is the same template that appears when you create a ClusterDeployment and add services to it — the UI reads from the ServiceTemplate CRDs in the cluster.

### Examine the ServiceTemplate Structure

```bash
# View the full ServiceTemplate
kubectl get servicetemplate kyverno-3-2-6 -n kcm-system -o yaml
```

Key fields:
- **spec.helm.chartSpec.chart**: The Helm chart name from the catalog
- **spec.helm.chartSpec.version**: Pinned chart version
- **spec.helm.chartSpec.sourceRef**: Points to the `k0rdent-catalog` HelmRepository (created in Step 1)
- **status.valid**: `true` means k0rdent verified the chart exists in the referenced repository

> **How it works:** When you add this ServiceTemplate to a ClusterDeployment or MultiClusterService, k0rdent's KSM (via Sveltos) pulls the Helm chart from the catalog and deploys it to the target cluster(s). The ServiceTemplate itself doesn't install anything — it just makes the service *available* for deployment.

> **Note:** We'll cover deploying services to managed clusters in detail in **Lab 1.7: Multi-Cluster Service Deployment**.

### Clean Up (Optional)

```bash
# Remove the ServiceTemplate if you want to clean up
kubectl delete servicetemplate kyverno-3-2-6 -n kcm-system
```

### Why External Catalog?

| Aspect | Bundled Templates (Old) | External Catalog (Current) |
|--------|------------------------|---------------------------|
| **Updates** | Tied to k0rdent releases | Updated independently |
| **Selection** | Limited set | 100+ services |
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
- **k0rdent Version:** 1.2.2
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
- [ ] Understood how the training lab exposes the UI (Envoy Gateway + Gateway API)
- [ ] Can explain the production upgrade path (TLS + OIDC on the same Gateway)
- [ ] Explored dashboard and understood key metrics
- [ ] Reviewed at least one cluster template
- [ ] Browsed the Service Catalog at catalog.k0rdent.io
- [ ] Installed a ServiceTemplate (Kyverno) and viewed it in the UI
- [ ] Understood management cluster configuration
- [ ] Learned credential management concepts
- [ ] Practiced kubectl commands for k0rdent resources

## Summary

In this lab, you:
- Navigated the k0rdent Enterprise UI
- Learned how the UI is exposed via Envoy Gateway and the Gateway API, with production upgrade paths for TLS and OIDC
- Explored cluster templates
- Learned about the external Service Catalog model (catalog.k0rdent.io)
- Reviewed management cluster configuration
- Understood credential management flow
- Practiced kubectl commands for k0rdent

## Next Lab

Continue to [Lab 1.3: Configure AWS Provider](lab-1.3-configure-aws-provider.md)
