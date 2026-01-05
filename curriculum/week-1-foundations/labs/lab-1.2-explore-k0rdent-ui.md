# Lab 1.2: Explore k0rdent UI and Configuration

**Duration:** 2 hours
**Type:** Hands-on Lab

## Objectives

In this lab, you will:
- Navigate the k0rdent Enterprise UI
- Understand the dashboard and key metrics
- Explore cluster templates and service templates
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
sudo k0s kubectl port-forward svc/k0rdent-ui -n kcm-system 8080:80 --address 0.0.0.0 &
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
# From SSH session, view templates via kubectl
sudo k0s kubectl get clustertemplate -A

# Get details of a specific template
sudo k0s kubectl get clustertemplate aws-standalone-cp-0-30-0 -n kcm-system -o yaml
```

Questions to answer:
- [ ] What Kubernetes version does it deploy?
- [ ] What is the default instance type for control plane nodes?
- [ ] What CNI is configured?

## Part 4: Explore Service Templates

Service templates define applications and services that can be deployed to managed clusters.

### Navigate to Service Templates

1. In the UI, go to **Templates** > **Service Templates**
2. Review available services

### Common Service Templates

- **Ingress Controllers** (nginx, traefik)
- **Monitoring** (Prometheus, Grafana)
- **Logging** (Fluentd, Loki)
- **Storage** (CSI drivers)

### Exercise: Examine Service Template

```bash
# List service templates
sudo k0s kubectl get servicetemplate -A

# View details
sudo k0s kubectl get servicetemplate -n kcm-system -o yaml | head -100
```

## Part 5: Management Cluster Configuration

The management cluster is the control plane for all k0rdent operations.

### View Management Configuration

```bash
# Get management cluster object
sudo k0s kubectl get management -A

# View detailed configuration
sudo k0s kubectl get management kcm -n kcm-system -o yaml
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
# List credential objects
sudo k0s kubectl get credentials -A

# List related secrets
sudo k0s kubectl get secrets -n kcm-system | grep credential
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
# View all k0rdent custom resources
sudo k0s kubectl api-resources | grep k0rdent

# List all clusters
sudo k0s kubectl get clusters -A

# View cluster details
sudo k0s kubectl describe cluster <cluster-name> -n <namespace>

# Check cluster status
sudo k0s kubectl get cluster <cluster-name> -n <namespace> -o jsonpath='{.status}'
```

### Exercise: Create kubectl Aliases

Add these aliases to your shell for easier access:

```bash
# Add to ~/.bashrc
alias kk='sudo k0s kubectl'
alias kkn='sudo k0s kubectl -n kcm-system'

# Reload
source ~/.bashrc

# Use aliases
kk get pods -A
kkn get management
```

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
- [ ] Reviewed at least one service template
- [ ] Understood management cluster configuration
- [ ] Learned credential management concepts
- [ ] Practiced kubectl commands for k0rdent resources

## Summary

In this lab, you:
- Navigated the k0rdent Enterprise UI
- Explored cluster and service templates
- Reviewed management cluster configuration
- Understood credential management flow
- Practiced kubectl commands for k0rdent

## Next Lab

Continue to [Lab 1.3: Configure AWS Provider](lab-1.3-configure-aws-provider.md)
