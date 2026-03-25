# Lab 1.4: Production Configuration and RBAC

**Duration:** 3 hours
**Type:** Hands-on Lab

## Objectives

In this lab, you will:
- Configure k0rdent for production readiness
- Set up RBAC policies for multi-team access
- Configure backup and disaster recovery
- Implement security hardening

## Prerequisites

- Completed Labs 1.1, 1.2, and 1.3
- Understanding of Kubernetes RBAC
- Basic security concepts

## Resuming This Lab

If your SSH session dropped or you're returning the next day:

```bash
cd lab-infrastructure
./scripts/lab-connect.sh <your-engineer-id>
kubectl get nodes && kubectl get pods -n kcm-system
```

---

## Part 1: Production Architecture Overview

### Single vs Multi-Node Management Cluster

| Aspect | Single Node | Multi-Node (HA) |
|--------|-------------|-----------------|
| Availability | No redundancy | Tolerates failures |
| Use Case | Dev/Test | Production |
| Etcd | Single instance | 3-node quorum |
| Cost | Lower | Higher |

### Exercise: Evaluate Your Setup

```bash
# Check current node count
kubectl get nodes

# For production, you would deploy 3 nodes
# This lab focuses on single-node configuration hardening
```

## Part 2: Configure RBAC for Multi-Team Access

### Understanding k0rdent RBAC

k0rdent extends Kubernetes RBAC with project-based isolation:

```
+-------------------+
|   Organization    |
+--------+----------+
         |
    +----+----+
    |         |
+---+---+ +---+---+
| Team A| | Team B|
+---+---+ +---+---+
    |         |
+---+---+ +---+---+
|Project| |Project|
+-------+ +-------+
```

### Create Namespaces for Teams

```bash
# Create team namespaces
kubectl create namespace team-platform
kubectl create namespace team-ml
kubectl create namespace team-data

# Label namespaces for k0rdent
kubectl label namespace team-platform k0rdent.mirantis.com/project=platform
kubectl label namespace team-ml k0rdent.mirantis.com/project=ml-team
kubectl label namespace team-data k0rdent.mirantis.com/project=data-team
```

### Create Cluster Roles

```bash
# Cluster Admin - Full access
cat << 'EOF' | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: k0rdent-cluster-admin
rules:
- apiGroups: ["k0rdent.mirantis.com"]
  resources: ["*"]
  verbs: ["*"]
- apiGroups: ["cluster.x-k8s.io"]
  resources: ["*"]
  verbs: ["*"]
- apiGroups: ["infrastructure.cluster.x-k8s.io"]
  resources: ["*"]
  verbs: ["*"]
EOF

# Cluster Viewer - Read-only access
cat << 'EOF' | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: k0rdent-cluster-viewer
rules:
- apiGroups: ["k0rdent.mirantis.com"]
  resources: ["*"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["cluster.x-k8s.io"]
  resources: ["*"]
  verbs: ["get", "list", "watch"]
EOF

# Project Admin - Manage clusters within a project
cat << 'EOF' | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: k0rdent-project-admin
  namespace: team-platform
rules:
- apiGroups: ["k0rdent.mirantis.com"]
  resources: ["clusterdeployments", "multiclusterservices"]
  verbs: ["*"]
- apiGroups: [""]
  resources: ["secrets"]
  verbs: ["get", "list", "create", "update", "delete"]
EOF
```

### Create Service Accounts and Bindings

```bash
# Create service accounts for teams
kubectl create serviceaccount platform-admin -n team-platform
kubectl create serviceaccount ml-admin -n team-ml
kubectl create serviceaccount ml-viewer -n team-ml

# Bind roles
kubectl create rolebinding platform-admin-binding \
  --role=k0rdent-project-admin \
  --serviceaccount=team-platform:platform-admin \
  -n team-platform
```

## Part 3: Configure Audit Logging

### Enable Kubernetes Audit Logging

```bash
# Create audit policy
cat << 'EOF' | sudo tee /var/lib/k0s/audit-policy.yaml
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
  # Log all k0rdent operations at RequestResponse level
  - level: RequestResponse
    resources:
    - group: "k0rdent.mirantis.com"
      resources: ["*"]

  # Log cluster operations
  - level: RequestResponse
    resources:
    - group: "cluster.x-k8s.io"
      resources: ["clusters", "machines"]

  # Log authentication attempts
  - level: Metadata
    resources:
    - group: ""
      resources: ["secrets"]
    verbs: ["get", "list"]

  # Don't log read-only requests to certain resources
  - level: None
    resources:
    - group: ""
      resources: ["events", "endpoints"]
    verbs: ["get", "list", "watch"]

  # Default level for everything else
  - level: Metadata
EOF
```

### Configure k0s for Audit Logging

> **Scope Note:** Enabling audit logging in k0s requires modifying `/etc/k0s/k0s.yaml` and restarting the k0s service, which would temporarily disrupt the management cluster. This is beyond the scope of this training lab. The audit policy file above is provided as a **production reference** -- in a real deployment, you would add the following to your k0s configuration:

```yaml
# Production reference only - do NOT apply in this training environment
# Add this under spec.api in /etc/k0s/k0s.yaml:
spec:
  api:
    extraArgs:
      audit-policy-file: /var/lib/k0s/audit-policy.yaml
      audit-log-path: /var/log/kubernetes/audit.log
      audit-log-maxage: "30"
      audit-log-maxbackup: "10"
      audit-log-maxsize: "100"
```

```bash
# View the current k0s config for reference
sudo k0s config create
```

## Part 4: Configure Backup and Recovery

k0rdent ships with **Velero** built into the Helm chart. Velero handles backup and restore of the management cluster's state — including all CRDs, secrets, and cluster configurations. k0rdent provides the `ManagementBackup` CRD to manage backup schedules declaratively.

### Step 1: Configure Backup Storage

Velero needs a storage location (S3 bucket) for backup data. Create the credentials secret and BackupStorageLocation:

```bash
# Create AWS credentials for Velero (uses the same credentials as CAPA)
# Format required by Velero's AWS plugin
cat <<EOF > /tmp/velero-credentials
[default]
aws_access_key_id = $(kubectl get secret aws-cluster-identity-secret -n kcm-system -o jsonpath='{.data.AccessKeyID}' | base64 -d)
aws_secret_access_key = $(kubectl get secret aws-cluster-identity-secret -n kcm-system -o jsonpath='{.data.SecretAccessKey}' | base64 -d)
EOF

# Create the Velero credentials secret
kubectl create secret generic cloud-credentials \
  -n kcm-system \
  --from-file=cloud=/tmp/velero-credentials \
  --dry-run=client -o yaml | kubectl apply -f -

# Clean up the temp file
rm -f /tmp/velero-credentials
```

```bash
# Get the region from the lab config
source /opt/k0rdent-lab/config/lab-info.env

# Create the BackupStorageLocation pointing to your S3 bucket
cat <<EOF | kubectl apply -f -
apiVersion: velero.io/v1
kind: BackupStorageLocation
metadata:
  name: aws-s3
  namespace: kcm-system
spec:
  provider: aws
  config:
    region: $AWS_REGION
  credential:
    name: cloud-credentials
    key: cloud
  objectStorage:
    bucket: $ARTIFACTS_BUCKET
    prefix: velero-backups
EOF
```

### Step 2: Ensure the Velero AWS Plugin is Loaded

Velero needs the AWS plugin to interact with S3. Check if it's already installed, and add it if not:

```bash
# Check if the AWS plugin is already configured
if kubectl get deployment velero -n kcm-system -o jsonpath='{.spec.template.spec.initContainers[*].name}' | grep -q velero-plugin-for-aws; then
  echo "AWS plugin already installed"
else
  echo "Installing AWS plugin..."
  kubectl patch deployment velero -n kcm-system --type=json -p='[
    {
      "op": "add",
      "path": "/spec/template/spec/initContainers/-",
      "value": {
        "name": "velero-plugin-for-aws",
        "image": "velero/velero-plugin-for-aws:v1.11.0",
        "imagePullPolicy": "IfNotPresent",
        "volumeMounts": [{"mountPath": "/target", "name": "plugins"}]
      }
    }
  ]'
  kubectl rollout status deployment/velero -n kcm-system --timeout=120s
fi
```

```bash
# Verify the BackupStorageLocation is now Available
kubectl get backupstoragelocation -n kcm-system
```

You should see `aws-s3` with phase `Available`. If it still shows `Unavailable`, wait 30 seconds — Velero validates the BSL periodically.

> **Production note:** For a permanent configuration, add the plugin via the Management object so it survives Helm reconciliation:
> ```yaml
> spec:
>   core:
>     kcm:
>       config:
>         velero:
>           initContainers:
>           - name: velero-plugin-for-aws
>             image: velero/velero-plugin-for-aws:v1.11.0
>             imagePullPolicy: IfNotPresent
>             volumeMounts:
>             - mountPath: /target
>               name: plugins
> ```

### Step 3: Create a Scheduled Backup

Use the `ManagementBackup` CRD to schedule automatic backups:

```bash
# Create a backup schedule (every 6 hours)
cat <<EOF | kubectl apply -f -
apiVersion: k0rdent.mirantis.com/v1beta1
kind: ManagementBackup
metadata:
  name: kcm
spec:
  schedule: "0 */6 * * *"
  storageLocation: aws-s3
EOF
```

```bash
# Verify the backup schedule
kubectl get managementbackup
```

### Step 4: Create an On-Demand Backup

Trigger an immediate backup to verify everything works:

```bash
# Create an on-demand backup (no schedule = immediate)
cat <<EOF | kubectl apply -f -
apiVersion: k0rdent.mirantis.com/v1beta1
kind: ManagementBackup
metadata:
  name: manual-backup-$(date +%Y%m%d)
spec:
  storageLocation: aws-s3
EOF
```

```bash
# Watch the backup progress
kubectl get backup -n kcm-system --watch
```

Wait until the phase shows `Completed`. This typically takes 30-60 seconds.

```bash
# Verify the backup exists in S3
kubectl get backup -n kcm-system
```

### Understanding What Gets Backed Up

k0rdent's ManagementBackup captures:
- All k0rdent CRDs (Management, ClusterDeployments, Credentials, Templates)
- CAPI resources (Clusters, Machines, MachineDeployments)
- Flux sources and HelmReleases
- cert-manager certificates
- Secrets referenced by the above

> **Restore scenario:** If the management cluster is lost, you provision a fresh k0rdent install, configure the same BackupStorageLocation, and create a `Restore` object pointing to the backup. k0rdent reconnects to the existing managed clusters automatically — they keep running even if the management cluster is down.

## Part 5: Security Hardening

### Network Policies

> **WARNING -- DO NOT APPLY IN TRAINING**
>
> The network policies below are for **production reference only**. Applying them in this training environment **WILL break cluster provisioning** in Labs 1.5-1.7 by blocking webhook traffic on port 9443. You would see `webhook timeout` errors when creating ClusterDeployments, and diagnosing this is non-obvious.
>
> **Read the YAML below for learning purposes, but do NOT run the `kubectl apply` command.** If you accidentally apply them, delete immediately with:
> ```
> kubectl delete networkpolicy -n kcm-system --all
> ```

For production environments, network policies should allow:
- Internal kcm-system pod-to-pod communication
- Kubernetes API server to webhook services
- Ingress from managed clusters for status updates

```yaml
# PRODUCTION REFERENCE — do not apply during training
# Save as: network-policy-kcm.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-kcm-internal
  namespace: kcm-system
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  ingress:
  # Allow traffic from within kcm-system
  - from:
    - namespaceSelector:
        matchLabels:
          name: kcm-system
  # Allow traffic from kube-system (for API server webhooks)
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
  # Allow all traffic to webhook ports (CRITICAL — without this,
  # cluster provisioning breaks with webhook timeout errors)
  - ports:
    - port: 9443
      protocol: TCP
```

**Applying After Week 1 (optional exercise):**

If you want to practice applying network policies after completing Labs 1.5-1.8:

```bash
# Label the namespace first
kubectl label namespace kcm-system name=kcm-system --overwrite

# Apply the policy
kubectl apply -f network-policy-kcm.yaml

# Verify provisioning still works by checking webhook connectivity
kubectl get clusterdeployments -A
```

> **Recovery:** If network policies break webhook traffic, remove them immediately:
> ```
> kubectl delete networkpolicy -n kcm-system --all
> ```

### Pod Security Standards

```bash
# Apply Pod Security Standards to namespaces
kubectl label namespace team-platform \
  pod-security.kubernetes.io/enforce=restricted \
  pod-security.kubernetes.io/warn=restricted

kubectl label namespace team-ml \
  pod-security.kubernetes.io/enforce=baseline \
  pod-security.kubernetes.io/warn=restricted
```

### Secret Encryption

```bash
# View k0s encryption configuration (if enabled)
kubectl get secret -n kube-system | grep encryption

# Note: At-rest encryption requires k0s configuration
# For production, enable encryption at rest
```

## Part 6: Configure Resource Quotas

### Set Namespace Quotas

```bash
# Set quotas for team namespaces
cat << 'EOF' | kubectl apply -f -
apiVersion: v1
kind: ResourceQuota
metadata:
  name: team-quota
  namespace: team-platform
spec:
  hard:
    requests.cpu: "10"
    requests.memory: 20Gi
    limits.cpu: "20"
    limits.memory: 40Gi
    count/clusters.cluster.x-k8s.io: "5"
---
apiVersion: v1
kind: ResourceQuota
metadata:
  name: team-quota
  namespace: team-ml
spec:
  hard:
    requests.cpu: "20"
    requests.memory: 40Gi
    limits.cpu: "40"
    limits.memory: 80Gi
    count/clusters.cluster.x-k8s.io: "10"
EOF
```

## Part 7: Production Readiness Checklist

### Create Assessment Script

```bash
cat << 'EOF' | sudo tee /usr/local/bin/production-readiness.sh
#!/bin/bash

echo "=== Production Readiness Assessment ==="
echo ""

PASS=0
FAIL=0

check() {
    local cmd="$1"
    local desc="$2"
    if eval "$cmd" >/dev/null 2>&1; then
        echo "[PASS] $desc"
        PASS=$((PASS + 1))
    else
        echo "[FAIL] $desc"
        FAIL=$((FAIL + 1))
    fi
}

# Core Components
check "kubectl get pods -n kcm-system | grep -q Running" "KCM pods running"
# Note: In k0rdent Enterprise, CAPI components run in kcm-system
check "kubectl get pods -n kcm-system | grep -E 'capi|capa' | grep -q Running" "CAPI pods running"
check "kubectl get credential -n kcm-system | grep -q aws" "AWS credentials configured"

# RBAC
check "kubectl get clusterrole k0rdent-cluster-admin" "Cluster admin role exists"
check "kubectl get clusterrole k0rdent-cluster-viewer" "Cluster viewer role exists"

# Backup
check "kubectl get backupstoragelocation aws-s3 -n kcm-system" "Backup storage location configured"
check "kubectl get managementbackup kcm" "Scheduled backup configured"

# Security (optional for training - network policies can block webhooks)
# Uncomment for production:
# check "kubectl get networkpolicy -n kcm-system | grep -q allow" "Network policies configured"
echo "[SKIP] Network policies (optional for training)"

echo ""
echo "=== Results ==="
echo "Passed: $PASS"
echo "Failed: $FAIL"
echo ""

if [ "$FAIL" -eq 0 ]; then
    echo "Production readiness: READY"
else
    echo "Production readiness: NOT READY - Address failures above"
fi
EOF

sudo chmod +x /usr/local/bin/production-readiness.sh

# Run assessment
sudo /usr/local/bin/production-readiness.sh
```

## Validation Checklist

Before completing this lab, verify:

- [ ] Created team namespaces with proper labels
- [ ] Configured RBAC roles and bindings
- [ ] Configured Velero with BackupStorageLocation (S3)
- [ ] Created scheduled ManagementBackup (every 6 hours)
- [ ] Completed an on-demand backup successfully
- [ ] (Optional) Applied network policies - skip for training environments
- [ ] Set resource quotas for namespaces
- [ ] Ran production readiness assessment

## Summary

In this lab, you:
- Configured multi-team RBAC policies
- Configured Velero-based backup with ManagementBackup CRD
- Applied security hardening measures
- Created production readiness assessment

## Next Lab

Continue to [Lab 1.5: Provision Your First Managed Cluster](lab-1.5-provision-managed-cluster.md)
