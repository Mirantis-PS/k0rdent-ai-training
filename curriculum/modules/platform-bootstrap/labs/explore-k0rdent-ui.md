# Lab 1.2: Explore k0rdent UI and Configuration

**Duration:** 2.5-hour session: ~75 minutes of core exercises, with the remaining time for configuration analysis and production-design discussion.
**Type:** Hands-on Lab

## Table of Contents

- [Objectives](#objectives)
- [Prerequisites](#prerequisites)
- [Resuming This Lab](#resuming-this-lab)
- [Part 1: Access the k0rdent UI (~5 min)](#part-1-access-the-k0rdent-ui-5-min)
  - [Get the URL and Login](#get-the-url-and-login)
- [Part 2: Understanding k0rdent UI Access Architecture (~10 min)](#part-2-understanding-k0rdent-ui-access-architecture-10-min)
  - [How the UI is Exposed](#how-the-ui-is-exposed)
- [Part 3: Dashboard Overview (~10 min)](#part-3-dashboard-overview-10-min)
  - [What You Should See](#what-you-should-see)
  - [Key Dashboard Elements](#key-dashboard-elements)
  - [Exercise: Dashboard Exploration](#exercise-dashboard-exploration)
- [Part 4: Explore Cluster Templates (~10 min)](#part-4-explore-cluster-templates-10-min)
  - [Navigate to Templates](#navigate-to-templates)
  - [Understand Template Structure](#understand-template-structure)
  - [Exercise: Review AWS Template](#exercise-review-aws-template)
- [Part 5: Understanding the Service Catalog (~15 min)](#part-5-understanding-the-service-catalog-15-min)
  - [The Service Catalog Architecture](#the-service-catalog-architecture)
  - [Browse the Service Catalog](#browse-the-service-catalog)
  - [Exercise: Explore the Catalog](#exercise-explore-the-catalog)
  - [Check Currently Installed ServiceTemplates](#check-currently-installed-servicetemplates)
  - [Install a ServiceTemplate](#install-a-servicetemplate)
  - [View the ServiceTemplate in the UI](#view-the-servicetemplate-in-the-ui)
  - [Alternative: Install a ServiceTemplate from the UI](#alternative-install-a-servicetemplate-from-the-ui)
  - [Examine the ServiceTemplate Structure](#examine-the-servicetemplate-structure)
  - [Clean Up (Optional)](#clean-up-optional)
  - [Why External Catalog?](#why-external-catalog)
- [Part 6: Management Cluster Configuration (~5 min)](#part-6-management-cluster-configuration-5-min)
  - [View Management Configuration](#view-management-configuration)
  - [Key Configuration Elements](#key-configuration-elements)
  - [Exercise: Document Current Configuration](#exercise-document-current-configuration)
- [Part 7: Credential Management (~5 min)](#part-7-credential-management-5-min)
  - [Understand Credential Flow](#understand-credential-flow)
  - [View Existing Credentials](#view-existing-credentials)
  - [Credential Types](#credential-types)
- [Part 8: kubectl CLI Exploration (~10 min)](#part-8-kubectl-cli-exploration-10-min)
  - [Essential Commands](#essential-commands)
  - [Pre-configured Aliases](#pre-configured-aliases)
- [Part 9: Configuration Best Practices (~5 min)](#part-9-configuration-best-practices-5-min)
  - [Production Recommendations](#production-recommendations)
  - [Documentation Exercise](#documentation-exercise)
- [Validation Checklist](#validation-checklist)
- [Reference: Production UI Access Patterns](#reference-production-ui-access-patterns)
  - [Production Upgrade Path](#production-upgrade-path)
  - [Alternative Deployment Patterns](#alternative-deployment-patterns)
  - [TLS Configuration Patterns](#tls-configuration-patterns)
- [Summary](#summary)
- [Next Lab](#next-lab)

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

Use two terminals: a **workstation terminal** in your repository's `lab-infrastructure/` directory for `./scripts/lab-connect.sh`, and the **remote SSH terminal** for `kubectl` and `helm`. Workstation snippets use Bash; Fish users can start Bash or source the shell-specific AWS selection from Lab 1.1.

If the EC2 instances were stopped, start your management node and bastion first using their recorded instance IDs and region. Then, from the repository root in the workstation terminal:

```bash
cd lab-infrastructure
./scripts/lab-connect.sh <your-engineer-id>
```

In the remote SSH terminal, wait for the services used in this lab:

```bash
kubectl wait node --all --for=condition=Ready=True --timeout=300s
kubectl wait management kcm --for=condition=Ready=True --timeout=300s
kubectl rollout status deployment/kcm-k0rdent-ui -n kcm-system --timeout=300s
kubectl wait pod --all -n envoy-gateway-system --for=condition=Ready=True --timeout=300s
kubectl wait apiservice v1beta1.metrics.k8s.io --for=condition=Available=True --timeout=300s
kubectl top nodes
```

After a restart, node readiness and the stored Management condition can precede UI, proxy and metrics recovery. If a wait times out, inspect that component's pods and events. Do not reinstall it solely because its API is temporarily unavailable.

---

## Part 1: Access the k0rdent UI (~5 min)

The k0rdent UI is exposed via **Envoy Gateway** (using the Kubernetes Gateway API) and accessible directly from your browser.

### Get the URL and Login

The UI URL was printed at the end of provisioning. To retrieve it again:

```bash
# Workstation terminal: get the UI URL and credentials
./scripts/lab-connect.sh <your-engineer-id> --ui-url
```

Open the URL in your browser and login with:
- **Username:** `admin`
- **Password:** shown in the command output above

> **Tip:** To see the full Gateway API resource status, run `./scripts/lab-connect.sh <your-engineer-id> --show-gateway`.

## Part 2: Understanding k0rdent UI Access Architecture (~10 min)

### How the UI is Exposed

k0rdent Enterprise exposes its UI through the **Kubernetes Gateway API** using **Envoy Gateway** as the implementation.

#### Training Lab Architecture

```
Student Browser (HTTP)
    │
    ▼
AWS Classic ELB (auto-provisioned by AWS Cloud Controller Manager)
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

The optional [production reference](#reference-production-ui-access-patterns) compares TLS, OIDC and alternative load-balancer designs. Keep the working AWS HTTP route for the core exercises.

## Part 3: Dashboard Overview (~10 min)

The k0rdent dashboard provides a high-level view of your managed infrastructure.

### What You Should See

In Enterprise 1.3.1, **Cluster Templates**, **Service Templates**, **Addons** and **Credentials** are separate sidebar links. The Dashboard shows cluster/template/service counts, a deployment map, recent clusters and system information. With no workload clusters yet, zero deployed clusters is expected.

### Key Dashboard Elements

Record the cluster count, k0rdent version, template counts and any visible banner. The Dashboard does not expose management-node CPU/memory utilization in this lab. Use the Metrics API for that measurement; dashboard health and node resource usage answer different questions.

### Exercise: Dashboard Exploration

- [ ] Record the UI cluster count and compare it with `kubectl get clusterdeployments -A` (expect none).
- [ ] Record the version and visible warnings. An unlicensed banner is separate from Kubernetes health; confirm training license arrangements with the instructor.
- [ ] Run the commands below in the remote SSH terminal. Distinguish historical startup warnings from current failures by timestamp and current pod readiness.

```bash
kubectl get events -A --field-selector type=Warning
kubectl top nodes
kubectl get pods -A
```

## Part 4: Explore Cluster Templates (~10 min)

Cluster templates define how Kubernetes clusters are provisioned across different infrastructure providers.

### Navigate to Templates

1. Click **Cluster Templates** in the left navigation.
2. Open an AWS standalone control plane template.

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
kubectl get "$AWS_TEMPLATE" -n kcm-system -o yaml

# Extract the defaults used by the questions below
kubectl get "$AWS_TEMPLATE" -n kcm-system -o jsonpath='{.status.config.k0s.version}{"\n"}{.status.config.controlPlane.instanceType}{"\n"}{.status.config.k0s.network.provider}{"\n"}'
```

> **Note:** Template names include version numbers (e.g., `aws-standalone-cp-1-0-20`) that change between k0rdent releases. Always list templates first rather than hardcoding names.

Questions to answer:
- [ ] What Kubernetes version does it deploy?
- [ ] Is a control-plane instance type supplied by default, or must the deployment set one?
- [ ] What CNI is configured?

For the 1.3.1 lab's `aws-standalone-cp-1-0-26`, the defaults are k0s `v1.35.1+k0s.1`, an empty control-plane instance type, and Calico. The empty value requires deployment configuration; do not confuse chart defaults with the management node's instance type or Kubernetes version.

## Part 5: Understanding the Service Catalog (~15 min)

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

The catalog changes independently of the training release. Record the catalog version selector, chart version and support tier you actually see. Do not assume every Community entry is validated or commercially supported. Categories include:

| Category | Example Services |
|----------|-----------------|
| **AI/Machine Learning** | NVIDIA GPU Operator, KubeRay, KServe, MLflow |
| **Networking** | ingress-nginx, Cilium, Istio, MetalLB, cert-manager |
| **Security** | Kyverno, External Secrets, Falco, Gatekeeper |
| **Storage & Databases** | PostgreSQL Operator, MinIO, Milvus (vector DB) |
| **Monitoring** | Grafana, kube-prometheus-stack, VictoriaMetrics, OpenCost |
| **CI/CD** | Argo CD, GitLab, Harbor |

> **Support tiers:** The current catalog distinguishes **Mirantis Certified**, **Verified Partner** and **Community** entries. Record the displayed tier and linked support information; a catalog listing alone is not a support entitlement. For example, inspect Mirantis Ceph or Mirantis Secure Registry.

### Exercise: Explore the Catalog

Take 10 minutes to browse the catalog:
- [ ] Find the Kyverno service and note its available versions
- [ ] Locate the AI/Machine Learning category
- [ ] Identify one Mirantis Certified entry and compare its support description with a Community entry

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
# Verify the repository exists; OCI repositories can have blank READY/STATUS columns
kubectl get helmrepositories -n kcm-system
```

> **OCI readiness:** Blank READY/STATUS columns are normal for an OCI HelmRepository; it holds registry configuration rather than an index artifact. Validate the fetched HelmChart and ServiceTemplate next. See the [Flux OCI documentation](https://fluxcd.io/flux/components/source/helmrepositories/#helm-oci-repository).

> **What this does:** Creates a Flux HelmRepository that points to the k0rdent community catalog. The `k0rdent.mirantis.com/managed: "true"` label tells k0rdent to track this repository. Once created, any ServiceTemplate can reference charts from this catalog.

#### Step 2: Create a ServiceTemplate

Let's install **Kyverno** (a Kubernetes-native policy engine) as our example:

```bash
# Create a ServiceTemplate for Kyverno
cat <<EOF | kubectl apply -f -
apiVersion: k0rdent.mirantis.com/v1beta1
kind: ServiceTemplate
metadata:
  name: kyverno-3-8-1
  namespace: kcm-system
  annotations:
    helm.sh/resource-policy: keep
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
# Wait for actual validation rather than relying on elapsed time
kubectl wait servicetemplate kyverno-3-8-1 -n kcm-system \
  --for=jsonpath='{.status.valid}'=true --timeout=300s
kubectl get servicetemplates -n kcm-system
```

You should see:
```
NAME            VALID   AGE
kyverno-3-8-1   true    30s
```

If validation times out, inspect `kubectl get helmcharts -n kcm-system` and `kubectl describe servicetemplate kyverno-3-8-1 -n kcm-system`. The pinned 3.8.1 chart was fetched successfully in this lab; the website may display newer versions. Do not silently replace the tested pin.

### View the ServiceTemplate in the UI

1. Open the k0rdent UI in your browser
2. Click **Service Templates** in the left sidebar
3. Open the template details
4. You should see `kyverno-3-8-1` listed with its chart version and validation status

This is the same template that appears when you create a ClusterDeployment and add services to it — the UI reads from the ServiceTemplate CRDs in the cluster.

### Alternative: Install a ServiceTemplate from the UI

You can also install ServiceTemplates directly from the k0rdent UI without writing any YAML:

1. Click **Addons** in the left sidebar
2. Browse the available services from the catalog
3. Select **Add Template** for a service such as cert-manager.
4. Inspect the prefilled name, namespace, chart name, chart version and HelmRepository. Use the `k0rdent-catalog` repository created above.
5. Click **Create**, then verify the template becomes **Valid**. The success notification confirms object creation, not chart validation. Refresh the page if it still says Creating after kubectl reports `status.valid: true`.

> **Try it:** Add one additional template from Addons, open it under **Service Templates**, and verify the same name, chart version and `status.valid` with kubectl. Record the actual version shown; the catalog updates independently. This adds a template, not a running service or a second cert-manager installation.

> **Known issue:** Some service versions may fail to install from the Addons UI due to version tag formatting. If an install fails, use the kubectl method above as a reliable alternative.

Both approaches — kubectl and the UI — create the same Kubernetes resources. The UI is convenient for discovery and one-off installs; kubectl/YAML is better for automation and GitOps workflows.

### Examine the ServiceTemplate Structure

```bash
# View the full ServiceTemplate
kubectl get servicetemplate kyverno-3-8-1 -n kcm-system -o yaml
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
kubectl delete servicetemplate kyverno-3-8-1 -n kcm-system
```

### Why External Catalog?

| Aspect | Bundled Templates (Old) | External Catalog (Current) |
|--------|------------------------|---------------------------|
| **Updates** | Tied to k0rdent releases | Updated independently |
| **Selection** | Limited set | Evolving catalog; verify each entry's support tier |
| **Customization** | Difficult | Easy version selection |
| **Support** | Release-dependent | Per-entry support tiers |

## Part 6: Management Cluster Configuration (~5 min)

The management cluster is the control plane for all k0rdent operations.

### View Management Configuration

```bash
# Get management cluster object (or use alias: kgm)
kubectl get management -A

# View detailed configuration
kubectl get management kcm -o yaml
```

The full Management configuration may include generated UI authentication values. Inspect it privately; record provider names, release and relevant settings in your summary without copying credentials.

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

## Part 7: Credential Management (~5 min)

k0rdent manages credentials for accessing infrastructure providers securely.

### Understand Credential Flow

```
+-------------------+     +-------------------+     +-------------------+     +-------------------+
| Kubernetes Secret | --> | Provider Identity | --> | Credential CRD    | --> | ClusterDeployment |
| (actual keys)     |     | (AWS/Azure/etc.)  |     | (k0rdent object)  |     | references it     |
+-------------------+     +-------------------+     +-------------------+     +-------------------+
```

### View Existing Credentials

```bash
# List credential objects (or use alias: kgcred)
kubectl get credentials -A

# List related secrets
kubectl get secrets -n kcm-system | grep credential
```

> **Note:** Cloud-init creates an `aws-credentials` placeholder secret for local reference, but the actual AWS provider workflow in Lab 1.3 creates an `aws-cluster-identity-secret`, an `AWSClusterStaticIdentity`, and a `Credential` object.

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

## Part 8: kubectl CLI Exploration (~10 min)

There are no workload ClusterDeployments yet. Inspect their schema now; commands describing an actual deployment belong after Lab 1.5.

Beyond the UI, kubectl provides powerful access to k0rdent resources.

### Essential Commands

```bash
# View all k0rdent custom resources (CRDs use k0rdent.mirantis.com domain)
kubectl api-resources | grep k0rdent.mirantis.com

# List all k0rdent CRDs
kubectl get crds | grep k0rdent.mirantis.com

# List cluster deployments (or use alias: kgcd)
kubectl get clusterdeployments -A

# Inspect fields without inventing a deployment that does not exist yet
kubectl explain clusterdeployment.spec
kubectl explain clusterdeployment.status.conditions
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

## Part 9: Configuration Best Practices (~5 min)

### Production Recommendations

1. **High Availability**
   - Deploy 3-node management cluster for HA
   - Configure `ManagementBackup` and test Velero-based restore procedures

2. **Security**
   - Enable RBAC policies
   - Use OIDC for authentication
   - Rotate credentials regularly

3. **Monitoring**
   - Enable KOF (k0rdent Observability & FinOps)
   - Set up alerting
   - Monitor cluster health

### Documentation Exercise

Document your management cluster setup. Add both template names/versions, the HelmRepository URL, validation results and AWS template defaults. Explain why there are still no Kyverno or additional cert-manager workloads. Select one [production reference pattern](#reference-production-ui-access-patterns) and list its missing prerequisites and acceptance evidence; do not apply it to this cluster.

Use live values rather than treating this example as evidence:

```markdown
## My k0rdent Management Cluster

- **Engineer ID:** [your-id]
- **k0rdent Version:** 1.3.1
- **k0s Version:** v1.35.4
- **Instance Type:** t3.2xlarge
- **Region:** [your-region]

### Installed Components
- [ ] KCM (Cluster Manager)
- [ ] Cert Manager
- [ ] k0rdent UI
- [ ] ProjectSveltos / KSM provider

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
- [ ] Kyverno ServiceTemplate is valid and its UI chart/version match kubectl
- [ ] Added a second template through Addons and verified its validation in UI and CLI
- [ ] Explained why valid templates have not deployed workloads
- [ ] Understood management cluster configuration
- [ ] Learned credential management concepts
- [ ] Practiced kubectl commands for k0rdent resources

## Reference: Production UI Access Patterns

These are alternative designs, not sequential steps to apply to the training cluster. They require additional prerequisites such as owned DNS names, certificates, an IdP, or a suitable on-premises network. Use them for the Part 9 design discussion; do not deploy MetalLB or replace the AWS Gateway during the core exercise.

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

#### Step 2: Add OIDC Authentication

The training lab uses the built-in `admin` account. Production deployments replace this with **OIDC** against a corporate identity provider (e.g., Microsoft Entra ID, Okta, Keycloak). Conceptually, this means putting an OIDC-capable layer in front of the UI — for example, an Envoy Gateway `SecurityPolicy` or a dedicated OIDC proxy wired to your IdP — on the same Gateway and HTTPRoute resources you examined above.

The exact configuration fields are release-specific, so don't work from memory or copied snippets — follow the official [Mirantis k0rdent Enterprise documentation](https://docs.mirantis.com/k0rdent-enterprise/) for your installed version (1.3.1 in this lab).

One scope detail worth remembering when you configure this: the `Management` resource is **cluster-scoped**, so it takes no namespace flag:

```bash
# Correct — cluster-scoped, no -n flag
kubectl get management kcm -o yaml
```

#### Production Checklist

- [ ] TLS certificates provisioned (see TLS patterns below)
- [ ] Gateway listener updated to HTTPS (port 443)
- [ ] OIDC authentication configured per the official k0rdent Enterprise docs
- [ ] DNS record pointing to the LoadBalancer address
- [ ] Network policies restricting UI access to corporate networks
- [ ] HTTP → HTTPS redirect configured (optional HTTPRoute)

### Alternative Deployment Patterns

Different customer environments require different approaches to LoadBalancer provisioning. The Gateway API resources (GatewayClass, Gateway, HTTPRoute) stay the same — only the infrastructure layer changes.

#### Envoy Gateway + AWS CCM (Training Default)

Used in the training lab. AWS Cloud Controller Manager auto-provisions a Classic ELB (the unannotated in-tree CCM default) when the Gateway creates a `type: LoadBalancer` service.

**When to use:** AWS cloud environments with CCM configured.

**How it works:** Install Envoy Gateway → create Gateway → CCM provisions a Classic ELB automatically.

#### Envoy Gateway + MetalLB

For on-premises or bare-metal environments without a cloud LoadBalancer.

**When to use:** On-prem data centers, bare-metal clusters, home labs.

```bash
# Install MetalLB
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.16.0/config/manifests/metallb-native.yaml

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

The Gateway and HTTPRoute resources remain identical — MetalLB assigns an IP from the pool instead of a cloud load-balancer hostname.

#### Envoy Gateway + NodePort + External Load Balancer

For restricted cloud environments where CCM is not available or LoadBalancer services are not permitted.

**When to use:** Air-gapped environments, restricted cloud accounts, environments behind an existing external load balancer.

```yaml
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: EnvoyProxy
metadata:
  name: ui-nodeport
  namespace: kcm-system
spec:
  provider:
    type: Kubernetes
    kubernetes:
      envoyService:
        type: NodePort
```

Reference `ui-nodeport` from the Gateway's `spec.infrastructure.parametersRef` (group `gateway.envoyproxy.io`, kind `EnvoyProxy`). Then configure the external load balancer to route to the NodePort on the generated Envoy **data-plane** Service. The Envoy Gateway controller Helm service is a different resource.

#### kubectl port-forward

For quick local access without any infrastructure.

**When to use:** Developer laptops, quick debugging, temporary access.

```bash
kubectl port-forward svc/kcm-k0rdent-ui -n kcm-system 8080:3000
# Access at http://localhost:8080
```

No Gateway needed — direct access to the ClusterIP service.

### TLS Configuration Patterns

Choose where TLS terminates: Envoy uses a Gateway TLS listener and a certificate Secret; AWS ACM uses an NLB TLS listener with an HTTP backend. Keep the HTTPRoute attached to the listener used by that design.

#### cert-manager + Let's Encrypt

Automated certificate issuance and renewal. Best for public-facing deployments.

Before creating the Issuer, enable Gateway API support on the existing cert-manager release (`config.enableGatewayAPI: true` for the direct chart; nest under `cert-manager:` for the catalog wrapper). Keep an HTTP listener on port 80 on `k0rdent-gateway`, allowing HTTPRoutes from `kcm-system`, and publish DNS to its reachable load balancer. HTTP-01 issuance/renewal requires this listener even after adding HTTPS. Wait for `Certificate Ready=True` before referencing its Secret from an HTTPS listener.

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

#### AWS ACM (TLS at the NLB)

This alternative terminates TLS at the NLB and uses plaintext HTTP inside the VPC.
Apply the EnvoyProxy in the same namespace as the Gateway. Replace the certificate
ARN with an issued ACM certificate in the load balancer's region. AWS annotations
belong on the generated Service, configured through EnvoyProxy; annotating the
Gateway metadata does not configure the AWS load balancer.

```yaml
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: EnvoyProxy
metadata:
  name: ui-acm
  namespace: kcm-system
spec:
  provider:
    type: Kubernetes
    kubernetes:
      envoyService:
        type: LoadBalancer
        annotations:
          service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
          service.beta.kubernetes.io/aws-load-balancer-ssl-cert: "<issued-acm-certificate-arn>"
          service.beta.kubernetes.io/aws-load-balancer-ssl-ports: "443"
          service.beta.kubernetes.io/aws-load-balancer-backend-protocol: "tcp"
---
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: k0rdent-gateway
  namespace: kcm-system
spec:
  gatewayClassName: envoy-gateway
  infrastructure:
    parametersRef:
      group: gateway.envoyproxy.io
      kind: EnvoyProxy
      name: ui-acm
  listeners:
    - name: http
      protocol: HTTP
      port: 443
      allowedRoutes:
        namespaces:
          from: Same
```

Port 443 on the Service is the TLS frontend at the NLB. Its target is the Envoy
HTTP listener; this is why the Gateway listener is HTTP and has no TLS Secret.
Ensure the HTTPRoute parent reference uses this Gateway and, if it sets
`sectionName`, the `http` listener. Use the cert-manager/manual-Secret pattern
instead when encryption must extend to Envoy.

```bash
kubectl -n kcm-system wait gateway/k0rdent-gateway --for=condition=Accepted --timeout=2m
kubectl -n kcm-system wait gateway/k0rdent-gateway --for=condition=Programmed --timeout=5m
kubectl get svc -A -l gateway.envoyproxy.io/owning-gateway-name=k0rdent-gateway -o yaml
# Check the Service annotations, the AWS listener's TLS certificate and TCP backend,
# and the real DNS name covered by that certificate (do not use curl -k).
curl --fail --show-error --head https://k0rdent.company.com
```

Gateway readiness alone does not verify that AWS applied the certificate. Record
the successful HTTPS request as the acceptance evidence. The configuration follows
[EnvoyProxy service customization](https://gateway.envoyproxy.io/v1.7/tasks/operations/customize-envoyproxy/).

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
