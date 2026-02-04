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
  resources: ["managedclusters", "clusterdeployments"]
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

```bash
# Note: This requires k0s configuration update
# View current k0s config
sudo k0s config create

# Audit logging is enabled via k0s.yaml configuration
# For this lab, we'll use kubectl for audit awareness
```

## Part 4: Configure Backup and Recovery

### Etcd Backup

```bash
# Create backup script
cat << 'EOF' | sudo tee /usr/local/bin/etcd-backup.sh
#!/bin/bash
BACKUP_DIR="/var/lib/k0s/backups"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

mkdir -p "$BACKUP_DIR"

# Take etcd snapshot
sudo k0s etcd snapshot save "$BACKUP_DIR/etcd-snapshot-$TIMESTAMP.db"

# Keep only last 7 backups
ls -t "$BACKUP_DIR"/etcd-snapshot-*.db | tail -n +8 | xargs -r rm

echo "Backup completed: $BACKUP_DIR/etcd-snapshot-$TIMESTAMP.db"
EOF

sudo chmod +x /usr/local/bin/etcd-backup.sh

# Test backup
sudo /usr/local/bin/etcd-backup.sh
```

### Schedule Automated Backups

```bash
# Add cron job for daily backups
echo "0 2 * * * root /usr/local/bin/etcd-backup.sh >> /var/log/etcd-backup.log 2>&1" | \
  sudo tee /etc/cron.d/etcd-backup
```

### Backup k0rdent Resources

```bash
# Export all k0rdent resources
kubectl get management,credential,clustertemplate,servicetemplate \
  -A -o yaml > k0rdent-resources-backup.yaml

# Export cluster configurations
kubectl get clusters,machines,machinedeployments \
  -A -o yaml > cluster-resources-backup.yaml
```

## Part 5: Security Hardening

### Network Policies

> **Warning for Training Environments:** The network policies below are for **production reference only**. In this training environment, applying restrictive network policies to `kcm-system` can block k0rdent webhooks and prevent cluster provisioning in Lab 1.5. **Skip this section** if you plan to continue with Labs 1.5-1.7, or delete the policies before proceeding.

For production environments, network policies should allow:
- Internal kcm-system pod-to-pod communication
- Kubernetes API server to webhook services
- Ingress from managed clusters for status updates

```bash
# PRODUCTION ONLY - First, label the namespace
kubectl label namespace kcm-system name=kcm-system --overwrite

# Create network policies that allow required traffic
cat << 'EOF' | kubectl apply -f -
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
  # Allow all traffic to webhook ports
  - ports:
    - port: 9443
      protocol: TCP
EOF
```

> **Note:** For this training lab, we recommend **skipping network policies** to avoid blocking k0rdent operations. Apply them only after completing all cluster provisioning labs.

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
check "test -x /usr/local/bin/etcd-backup.sh" "Backup script exists"
check "test -f /etc/cron.d/etcd-backup" "Backup cron configured"

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
- [ ] Set up etcd backup script
- [ ] Configured automated backup schedule
- [ ] (Optional) Applied network policies - skip for training environments
- [ ] Set resource quotas for namespaces
- [ ] Ran production readiness assessment

## Summary

In this lab, you:
- Configured multi-team RBAC policies
- Set up backup and disaster recovery procedures
- Applied security hardening measures
- Created production readiness assessment

## Next Lab

Continue to [Lab 1.5: Provision Your First Managed Cluster](lab-1.5-provision-managed-cluster.md)
