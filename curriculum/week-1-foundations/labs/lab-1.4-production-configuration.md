# Lab 1.4: Production Configuration and RBAC

**Duration:** 3 hours
**Type:** Hands-on Lab

## Table of Contents

- [Objectives](#objectives)
- [Prerequisites](#prerequisites)
- [Resuming This Lab](#resuming-this-lab)
- [Part 1: Production Architecture Overview (~5 min)](#part-1-production-architecture-overview-5-min)
  - [Single vs Multi-Node Management Cluster](#single-vs-multi-node-management-cluster)
  - [Exercise: Evaluate Your Setup](#exercise-evaluate-your-setup)
- [Part 2: Configure RBAC for Multi-Team Access (~20 min)](#part-2-configure-rbac-for-multi-team-access-20-min)
  - [Understanding k0rdent RBAC](#understanding-k0rdent-rbac)
  - [Create Namespaces for Teams](#create-namespaces-for-teams)
  - [Create Cluster Roles](#create-cluster-roles)
  - [Create Service Accounts and Bindings](#create-service-accounts-and-bindings)
- [Part 3: Configure Audit Logging (~10 min)](#part-3-configure-audit-logging-10-min)
  - [Enable Kubernetes Audit Logging](#enable-kubernetes-audit-logging)
  - [Configure k0s for Audit Logging](#configure-k0s-for-audit-logging)
- [Part 4: Configure Backup and Recovery (~30 min)](#part-4-configure-backup-and-recovery-30-min)
  - [Step 1: Configure Backup Storage](#step-1-configure-backup-storage)
  - [Step 2: Ensure the Velero AWS Plugin is Loaded](#step-2-ensure-the-velero-aws-plugin-is-loaded)
  - [Step 3: Create a Scheduled Backup](#step-3-create-a-scheduled-backup)
  - [Step 4: Create an On-Demand Backup](#step-4-create-an-on-demand-backup)
  - [Understanding What Gets Backed Up](#understanding-what-gets-backed-up)
- [Part 5: Security Hardening (~15 min)](#part-5-security-hardening-15-min)
  - [Network Policies](#network-policies)
  - [Pod Security Standards](#pod-security-standards)
  - [Secret Encryption](#secret-encryption)
- [Part 6: Configure Resource Quotas (~10 min)](#part-6-configure-resource-quotas-10-min)
  - [Set Namespace Quotas](#set-namespace-quotas)
- [Part 7: Production Readiness Checklist (~10 min)](#part-7-production-readiness-checklist-10-min)
  - [Create Assessment Script](#create-assessment-script)
- [Validation Checklist](#validation-checklist)
- [Summary](#summary)
- [Next Lab](#next-lab)

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

## Part 1: Production Architecture Overview (~5 min)

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

> **Expected output:** You should see a single node with status `Ready`. This is normal for the training environment.

## Part 2: Configure RBAC for Multi-Team Access (~20 min)

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

# Optional: add your own organizational labels for reporting or automation
kubectl label namespace team-platform team=platform
kubectl label namespace team-ml team=ml
kubectl label namespace team-data team=data
```

> **Note:** Current k0rdent access-control docs focus on namespace isolation and RoleBindings to built-in roles such as `kcm-namespace-editor-role` and `kcm-credentials-viewer-role`. A `k0rdent.mirantis.com/project` label is not required for namespace isolation, so this lab uses plain namespace boundaries and optional team labels instead.

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

## Part 3: Configure Audit Logging (~10 min)

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

## Part 4: Configure Backup and Recovery (~30 min)

k0rdent ships with **Velero** built into the Helm chart. Velero handles backup and restore of the management cluster's k0rdent state by backing up labeled k0rdent, CAPI, cert-manager, and related resources. k0rdent provides the `ManagementBackup` CRD to manage backup schedules declaratively.

### Step 1: Configure Backup Storage

Velero needs a storage location (S3 bucket) for backup data. In the training lab, the EC2 instance profile already has S3 permissions, so Velero can use it directly without static credentials.

```bash
source /opt/k0rdent-lab/config/lab-info.env

# Create an empty credentials file (Velero requires the secret to exist,
# but with an empty [default] profile it falls back to the instance profile)
kubectl create secret generic cloud-credentials \
  -n kcm-system \
  --from-literal=cloud=$'[default]\n' \
  --dry-run=client -o yaml | kubectl apply -f -
```

```bash
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

> **How credentials work here:** The Velero pod runs on an EC2 instance with an IAM instance profile that grants S3 access to the student bucket. When the AWS SDK finds empty static credentials, it falls back to the EC2 instance metadata service (IMDS) and uses the instance profile. In production, you would use IRSA (IAM Roles for Service Accounts) or explicit credentials instead.

### Step 2: Ensure the Velero AWS Plugin is Loaded

Velero needs the AWS plugin to interact with S3. k0rdent Enterprise 1.3.x bundles Velero 1.17.x, which pairs with `velero-plugin-for-aws` v1.13.x. Check if the plugin is already installed, and add it if not:

```bash
# Check if the AWS plugin is already configured
if kubectl get deployment velero -n kcm-system -o jsonpath='{.spec.template.spec.initContainers[*].name}' | grep -q velero-plugin-for-aws; then
  echo "AWS plugin already installed"
else
  echo "Installing AWS plugin..."
  kubectl patch deployment velero -n kcm-system --type=strategic -p '{
    "spec": {
      "template": {
        "spec": {
          "initContainers": [{
            "name": "velero-plugin-for-aws",
            "image": "velero/velero-plugin-for-aws:v1.13.2",
            "imagePullPolicy": "IfNotPresent",
            "volumeMounts": [{"mountPath": "/target", "name": "plugins"}]
          }]
        }
      }
    }
  }'
  kubectl rollout status deployment/velero -n kcm-system --timeout=120s
fi
```

```bash
# Verify the BackupStorageLocation is now Available
kubectl get backupstoragelocation -n kcm-system
```

You should see `aws-s3` with phase `Available`. If it still shows `Unavailable` or the phase column is empty, wait 30-60 seconds and re-run the command -- Velero validates the BSL periodically.

> **Production note:** For a permanent configuration, add the plugin via the Management object so it survives Helm reconciliation:
> ```yaml
> spec:
>   core:
>     kcm:
>       config:
>         regional:
>           velero:
>             initContainers:
>             - name: velero-plugin-for-aws
>               image: velero/velero-plugin-for-aws:v1.13.2
>               imagePullPolicy: IfNotPresent
>               volumeMounts:
>               - mountPath: /target
>                 name: plugins
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

> **Note:** `ManagementBackup` is cluster-scoped -- no `-n` flag is needed. You should see the `kcm` resource listed. The `SCHEDULE` column shows the cron expression; `LAST BACKUP` will be empty until the first scheduled run triggers.

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
# Watch the backup progress (Ctrl+C to exit once phase shows Completed)
kubectl get backup -n kcm-system --watch
```

> **Note:** The underlying Velero `Backup` objects are namespaced in `kcm-system` (unlike the `ManagementBackup` CRD which is cluster-scoped). The phase will transition from `InProgress` to `Completed`. This typically takes 30-60 seconds.

```bash
# Verify the backup exists in S3
kubectl get backup -n kcm-system
```

### Understanding What Gets Backed Up

k0rdent's ManagementBackup captures the resource sets selected by k0rdent's backup labels, including:
- k0rdent resources labeled `k0rdent.mirantis.com/component="kcm"`
- CAPI resources and ClusterDeployment-related objects
- cert-manager resources needed for dependent component creation
- Secrets referenced by the backed-up objects

> **Restore scenario:** If the management cluster is lost, you provision a fresh k0rdent install, configure the same BackupStorageLocation, and create a `Restore` object pointing to the backup. k0rdent reconnects to the existing managed clusters automatically — they keep running even if the management cluster is down.

## Part 5: Security Hardening (~15 min)

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

> **Note:** You may see `Warning: existing pods in namespace ... violate the new PodSecurity enforce level` -- this is expected if any pods already exist in these namespaces. The labels apply to future pod creation.

### Secret Encryption

```bash
# View k0s encryption configuration (if enabled)
kubectl get secret -n kube-system | grep encryption

# Note: At-rest encryption requires k0s configuration
# For production, enable encryption at rest
```

> **Note:** This command will likely return no results -- that is expected. The default k0s installation does not enable secret encryption at rest. In production, you would configure this in `/etc/k0s/k0s.yaml`.

## Part 6: Configure Resource Quotas (~10 min)

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

## Part 7: Production Readiness Checklist (~10 min)

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

> **Note:** If you see `[FAIL]` for any check, review the earlier sections to ensure you completed each step. The "CAPI pods running" check looks for pods with `capi` or `capa` in their name within `kcm-system` -- if none are running yet, this is expected before your first cluster deployment in Lab 1.5.

## Validation Checklist

Before completing this lab, verify:

- [ ] Created separate team namespaces
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
