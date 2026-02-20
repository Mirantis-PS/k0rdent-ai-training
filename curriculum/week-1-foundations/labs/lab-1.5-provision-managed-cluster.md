# Lab 1.5: Provision Your First Managed Cluster

**Duration:** 2.5 hours (active: ~1h, waiting for cluster provisioning: ~1.5h)
**Type:** Hands-on Lab

## Objectives

In this lab, you will:
- Provision a minimal managed Kubernetes cluster on AWS
- Monitor the Cluster API (CAPI) provisioning workflow
- Access and verify the managed cluster
- (Optional) Provision a cluster on Azure

## Prerequisites

- Completed Labs 1.1-1.4
- AWS credentials configured (Lab 1.3)
- SSH key pair created for cluster nodes (Lab 1.3)
- Understanding of ClusterDeployment concepts

## Cost Considerations

> **Important:** This lab provisions real cloud infrastructure that incurs costs.
>
> - **Estimated AWS cost:** ~$0.15/hour for minimal cluster (1 control plane + 1 worker)
> - **Remember to clean up** when finished with the lab
> - Cleanup instructions provided at the end

## Resuming This Lab

If your SSH session dropped or you're returning the next day:

```bash
# Reconnect from your local machine
cd lab-infrastructure
./scripts/lab-connect.sh <your-engineer-id>

# Verify management cluster is running
kubectl get nodes
kubectl get pods -n kcm-system

# Check if your managed cluster is still running
kubectl get clusterdeployment -n kcm-system
```

---

## Part 1: Verify Prerequisites

Before provisioning, ensure your AWS credentials and templates are ready.

### Check AWS Credential

```bash
# Verify the credential object exists (or use alias: kgcred)
kubectl get credentials -n kcm-system

# Expected output should include:
# aws-cluster-identity-cred
```

### Check AWS Identity

```bash
# Verify the AWSClusterStaticIdentity
kubectl get awsclusterstaticidentity -n kcm-system

# Verify the underlying secret exists
kubectl get secret aws-cluster-identity-secret -n kcm-system
```

### List Available Cluster Templates

```bash
# List all cluster templates (or use alias: kgct)
kubectl get clustertemplates -n kcm-system

# Filter for AWS templates
kubectl get clustertemplates -n kcm-system | grep -i aws
```

Note the available AWS template names. Common templates include:
- `aws-standalone-cp-*` - Standalone control plane on EC2
- `aws-hosted-cp-*` - Hosted control plane
- `aws-eks-*` - Amazon EKS managed

### Verify SSH Key Pair

> **Important:** The SSH key pair must exist in the **same region** where you'll provision the cluster.

```bash
# Set your target region (must match ClusterDeployment config.region)
export AWS_REGION="us-east-1"

# Check if your SSH key pair exists in AWS
aws ec2 describe-key-pairs --key-names k0rdent-clusters --region $AWS_REGION

# If not found, create it (from Lab 1.3):
# ssh-keygen -t ed25519 -f ~/.ssh/k0rdent-clusters -N ""
# aws ec2 import-key-pair --key-name k0rdent-clusters \
#   --public-key-material fileb://~/.ssh/k0rdent-clusters.pub --region $AWS_REGION
```

## Part 2: Create the ClusterDeployment

### Understand ClusterDeployment Structure

A ClusterDeployment defines:
- **template**: Which ClusterTemplate to use
- **credential**: Which cloud credentials to use
- **config**: Cluster-specific configuration (region, instance types, node counts)

### Create Your First Managed Cluster

Create a file `managed-cluster-01.yaml`:

First, find the exact template name for your k0rdent version:

```bash
# Find the AWS standalone control plane template
kubectl get clustertemplates -n kcm-system | grep aws-standalone-cp

# Note the exact name (e.g., aws-standalone-cp-1-0-20)
```

Then create the ClusterDeployment with the correct template name:

```bash
# Replace TEMPLATE_NAME with the actual template name from above
TEMPLATE_NAME="aws-standalone-cp-1-0-20"  # Adjust based on your output

cat << EOF > /tmp/managed-cluster-01.yaml
apiVersion: k0rdent.mirantis.com/v1beta1
kind: ClusterDeployment
metadata:
  name: managed-cluster-01
  namespace: kcm-system
  labels:
    environment: training
    owner: lab-user
spec:
  template: ${TEMPLATE_NAME}
  credential: aws-cluster-identity-cred
  dryRun: false
  cleanupOnDeletion: true
  config:
    region: us-east-1
    publicIP: true
    controlPlaneNumber: 1
    controlPlane:
      instanceType: t3.medium
      rootVolumeSize: 50
    workersNumber: 1
    worker:
      instanceType: t3.medium
      rootVolumeSize: 50
    sshKeyName: k0rdent-clusters
    clusterIdentity:
      name: aws-cluster-identity
      namespace: kcm-system
    clusterLabels:
      environment: training
EOF
```

> **Important Configuration Notes:**
> - **template**: Must match an available ClusterTemplate. Run `kubectl get clustertemplates -n kcm-system | grep aws` to find it.
> - **region**: Must match the region where you created your SSH key pair (Lab 1.3).
> - **sshKeyName**: Must match the key pair name you imported to AWS (Lab 1.3).
> - **clusterIdentity**: References your AWSClusterStaticIdentity created in Lab 1.3.

### Apply the ClusterDeployment

```bash
# Apply the cluster configuration
kubectl apply -f /tmp/managed-cluster-01.yaml

# Verify it was created
kubectl get clusterdeployment managed-cluster-01 -n kcm-system
```

## Part 3: Monitor Provisioning

Cluster provisioning takes 10-20 minutes. Monitor the progress using these methods.

### Watch ClusterDeployment Status

```bash
# Watch the ClusterDeployment status (or use alias: kgcd)
kubectl get clusterdeployment managed-cluster-01 -n kcm-system -w

# View detailed status
kubectl get clusterdeployment managed-cluster-01 -n kcm-system -o yaml | grep -A 20 "status:"
```

### Use clusterctl for Detailed Progress

```bash
# Get detailed cluster status (requires clusterctl)
clusterctl describe cluster managed-cluster-01 -n kcm-system
```

This shows:
- Control plane status
- Machine deployment status
- Infrastructure provisioning progress

### Monitor CAPI Resources

```bash
# Watch Cluster API resources being created
kubectl get clusters -n kcm-system -w

# Watch machines being provisioned
kubectl get machines -n kcm-system -w

# Check machine deployments
kubectl get machinedeployments -n kcm-system
```

### Check AWS Resources

```bash
# List EC2 instances being created (from local machine with AWS CLI)
aws ec2 describe-instances \
  --filters "Name=tag:kubernetes.io/cluster/managed-cluster-01,Values=owned" \
  --query 'Reservations[].Instances[].[InstanceId,State.Name,PrivateIpAddress]' \
  --output table \
  --region us-east-1
```

### Understanding Provisioning Stages

The provisioning follows these stages:

```
1. ClusterDeployment created
   ↓
2. Cluster API creates Cluster resource
   ↓
3. Infrastructure provider creates:
   - VPC and networking (if not using existing)
   - Security groups
   - Load balancer for API server
   ↓
4. Control plane machine(s) provisioned
   - EC2 instance launched
   - Kubernetes components installed
   - Control plane initialized
   ↓
5. Worker machine(s) provisioned
   - EC2 instances launched
   - Nodes join the cluster
   ↓
6. Cluster ready!
```

### Troubleshooting Provisioning Issues

If provisioning stalls, check:

```bash
# Check ClusterDeployment conditions
kubectl describe clusterdeployment managed-cluster-01 -n kcm-system

# Check Cluster conditions
kubectl describe cluster managed-cluster-01 -n kcm-system

# Check machine status
kubectl describe machines -n kcm-system

# Check CAPI controller logs
kubectl logs -n kcm-system -l cluster.x-k8s.io/provider=infrastructure-aws --tail=100
```

Common issues:

- **Insufficient IAM permissions**: Check AWS credential has required permissions (see Lab 1.3)
- **Instance type unavailable**: Try a different instance type or region
- **SSH key not found**: Ensure key pair exists in the target region (must match `config.region`)
- **"Namespace is not permitted to use AWSClusterStaticIdentity"**: Your identity's `allowedNamespaces` must include `kcm-system`. Patch with:
  ```bash
  kubectl patch awsclusterstaticidentity aws-cluster-identity -n kcm-system --type=merge \
    -p '{"spec":{"allowedNamespaces":{"list":["kcm-system"]}}}'
  ```
- **"AWS was not able to validate the provided access credentials"**: If using AWS SSO, ensure your secret includes `SessionToken`. Refresh credentials and update the secret (see Lab 1.3 SSO section)
- **Webhook timeout errors**: If you applied network policies in Lab 1.4, they may block webhooks. Delete them:
  ```bash
  kubectl delete networkpolicy -n kcm-system --all
  ```
- **Missing clusterIdentity error**: Ensure your ClusterDeployment config includes the `clusterIdentity` section with `name` and `namespace`

## Part 4: Access the Managed Cluster

Once the cluster shows `Ready`, retrieve the kubeconfig.

### Check Cluster is Ready

```bash
# Wait for Ready status
kubectl get clusterdeployment managed-cluster-01 -n kcm-system

# Status should show Ready: True
kubectl get clusterdeployment managed-cluster-01 -n kcm-system -o jsonpath='{.status.ready}'
```

### Retrieve Kubeconfig

```bash
# The kubeconfig is stored as a secret
kubectl get secret -n kcm-system managed-cluster-01-kubeconfig

# Extract and save the kubeconfig
kubectl get secret managed-cluster-01-kubeconfig -n kcm-system \
  -o jsonpath='{.data.value}' | base64 -d > /tmp/managed-cluster-01.kubeconfig

# Set permissions
chmod 600 /tmp/managed-cluster-01.kubeconfig
```

### Connect to the Managed Cluster

```bash
# Use the kubeconfig to access the managed cluster
export KUBECONFIG=/tmp/managed-cluster-01.kubeconfig

# Verify connection
kubectl cluster-info

# List nodes
kubectl get nodes

# Check system pods
kubectl get pods -A
```

### Verify Cluster Health

```bash
# Check all nodes are Ready
kubectl get nodes -o wide

# Verify core components
kubectl get pods -n kube-system

# Check cluster version
kubectl version
```

### Return to Management Cluster

```bash
# Unset KUBECONFIG to return to management cluster
unset KUBECONFIG

# Or explicitly use the management cluster config (k0s uses this path)
export KUBECONFIG=/home/ubuntu/.kube/config
```

## Part 5: Explore the Managed Cluster

With access to your managed cluster, explore its configuration.

### Check CNI (Container Network Interface)

```bash
export KUBECONFIG=/tmp/managed-cluster-01.kubeconfig

# Check which CNI is installed
kubectl get pods -n kube-system | grep -E 'calico|cilium|flannel|weave'

# Check CNI configuration
kubectl get cm -n kube-system | grep -i cni
```

### Verify Node Resources

```bash
# Check node capacity and allocatable resources
kubectl describe nodes | grep -A 10 "Capacity:"

# Check node conditions
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.conditions[-1].type}{"\n"}{end}'
```

### Deploy a Test Workload

```bash
# Deploy nginx to verify the cluster works
kubectl create deployment nginx-test --image=nginx --replicas=2

# Wait for pods to be ready
kubectl wait --for=condition=available deployment/nginx-test --timeout=60s

# Check pods are running
kubectl get pods -l app=nginx-test -o wide

# Clean up test deployment
kubectl delete deployment nginx-test
```

## Part 6: (Optional) Provision Azure Cluster

If you have Azure credentials, you can provision a cluster there too.

### Configure Azure Credentials

First, create Azure credentials (if not already done):

```bash
# Create Azure credentials secret
kubectl create secret generic azure-cluster-identity-secret \
  --from-literal=clientSecret="${AZURE_CLIENT_SECRET}" \
  -n kcm-system

# Create AzureClusterIdentity
# Note: CAPZ uses v1beta1 (not v1beta2 like CAPA). Verify with:
#   kubectl api-resources | grep azureclusteridentit
cat << EOF | kubectl apply -f -
apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
kind: AzureClusterIdentity
metadata:
  name: azure-cluster-identity
  namespace: kcm-system
spec:
  type: ServicePrincipal
  tenantID: "${AZURE_TENANT_ID}"
  clientID: "${AZURE_CLIENT_ID}"
  clientSecret:
    name: azure-cluster-identity-secret
    namespace: kcm-system
  allowedNamespaces:
    selector:
      matchLabels: {}
EOF

# Create k0rdent Credential
cat << EOF | kubectl apply -f -
apiVersion: k0rdent.mirantis.com/v1beta1
kind: Credential
metadata:
  name: azure-cluster-identity-cred
  namespace: kcm-system
spec:
  description: "Azure Credential"
  identityRef:
    apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
    kind: AzureClusterIdentity
    name: azure-cluster-identity
EOF
```

### Create Azure ClusterDeployment

```bash
cat << 'EOF' > /tmp/azure-cluster-01.yaml
apiVersion: k0rdent.mirantis.com/v1beta1
kind: ClusterDeployment
metadata:
  name: azure-cluster-01
  namespace: kcm-system
  labels:
    environment: training
    provider: azure
spec:
  template: azure-standalone-cp-0-1-0
  credential: azure-cluster-identity-cred
  dryRun: false
  cleanupOnDeletion: true
  config:
    location: eastus
    subscriptionID: "${AZURE_SUBSCRIPTION_ID}"
    controlPlaneNumber: 1
    controlPlane:
      vmSize: Standard_D2s_v3
    workersNumber: 1
    worker:
      vmSize: Standard_D2s_v3
EOF

kubectl apply -f /tmp/azure-cluster-01.yaml
```

### Monitor Azure Cluster

```bash
# Watch deployment
kubectl get clusterdeployment azure-cluster-01 -n kcm-system -w
```

## Part 7: Clean Up

> **Important:** Clean up resources to avoid unnecessary cloud costs!

### Delete Managed Cluster(s)

```bash
# Delete the AWS cluster
kubectl delete clusterdeployment managed-cluster-01 -n kcm-system

# If you created an Azure cluster
kubectl delete clusterdeployment azure-cluster-01 -n kcm-system
```

### Monitor Deletion

```bash
# Watch the deletion progress
kubectl get clusterdeployment -n kcm-system -w

# Verify AWS resources are cleaned up
aws ec2 describe-instances \
  --filters "Name=tag:kubernetes.io/cluster/managed-cluster-01,Values=owned" \
  --query 'Reservations[].Instances[].[InstanceId,State.Name]' \
  --output table \
  --region us-east-1
```

### Verify Complete Cleanup

```bash
# Ensure no orphaned CAPI resources
kubectl get clusters -n kcm-system
kubectl get machines -n kcm-system
kubectl get machinedeployments -n kcm-system
```

> **Note:** The `cleanupOnDeletion: true` setting ensures that Load Balancers and persistent volumes are also cleaned up.

## Validation Checklist

Before completing this lab, verify:

- [ ] Successfully created a ClusterDeployment
- [ ] Monitored the provisioning workflow
- [ ] Retrieved kubeconfig for the managed cluster
- [ ] Connected to and verified the managed cluster
- [ ] Deployed a test workload successfully
- [ ] Cleaned up all resources

## Summary

In this lab, you:
- Provisioned a minimal Kubernetes cluster on AWS using k0rdent
- Monitored the Cluster API provisioning workflow
- Accessed the managed cluster using kubeconfig
- Verified cluster health and deployed a test workload
- Learned about the ClusterDeployment lifecycle

## Key Concepts

| Concept | Description |
|---------|-------------|
| **ClusterDeployment** | k0rdent CRD that defines a managed cluster |
| **ClusterTemplate** | Reusable cluster configuration blueprint |
| **Credential** | Reference to cloud provider authentication |
| **CAPI (Cluster API)** | Kubernetes sub-project for cluster lifecycle management |

## Next Lab

Continue to [Lab 1.6: Deploy KOF (Observability & FinOps)](lab-1.6-deploy-kof.md)
